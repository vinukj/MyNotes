import AVFAudio
import Foundation
import MyNotesKit
import Observation
import Speech

enum SpeechAssetsAvailability: Equatable {
    case checking
    case ready(String)
    case downloadRequired(String)
    case downloading(String)
    case unsupported(String)
    case unavailable
}

@MainActor
@Observable
final class MeetingCaptureCoordinator {
    private(set) var state: MeetingCaptureState = .idle
    private(set) var elapsed: TimeInterval = 0
    private(set) var transcript: [TranscriptSegment] = []
    private(set) var message: String?
    private(set) var startedAt: Date?
    private(set) var isInstallingSpeechAssets = false
    private(set) var speechAssetsAvailability: SpeechAssetsAvailability = .checking

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var sink: AudioCaptureSink?
    @ObservationIgnored private var audioURL: URL?
    @ObservationIgnored private var analyzer: SpeechAnalyzer?
    @ObservationIgnored private var activeSince: Date?
    @ObservationIgnored private var activeDuration: TimeInterval = 0
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var processingTask: Task<Void, Never>?

    static func cleanupStaleAudio() {
        let directory = temporaryDirectory
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return }
        for url in urls where url.pathExtension == "caf" {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func start() async {
        guard state == .idle || state == .failed || state == .completed else { return }
        state = .preparing
        message = nil
        transcript = []
        do {
            guard await Self.requestMicrophonePermission() else {
                state = .permissionRequired
                message = "Microphone access is required. Enable MyNotes in System Settings → Privacy & Security → Microphone."
                return
            }
            guard await Self.requestSpeechRecognitionPermission() else {
                state = .permissionRequired
                message = "Speech Recognition access is required. Enable MyNotes in System Settings → Privacy & Security → Speech Recognition."
                return
            }
            await refreshSpeechAssetStatus()
            _ = try await Self.installedTranscriber()
            try beginCapture()
            startedAt = .now
            activeSince = .now
            activeDuration = 0
            elapsed = 0
            state = .recording
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.updateElapsed() }
            }
        } catch {
            cleanupAudio()
            state = .failed
            message = error is CaptureError && (error as? CaptureError) == .speechAssetsUnavailable
                ? "Local macOS Speech assets are not ready. Check their status below before recording."
                : error.localizedDescription
        }
    }

    func refreshSpeechAssetStatus() async {
        speechAssetsAvailability = .checking

        let installed = await SpeechTranscriber.installedLocales
        let preferred = await SpeechTranscriber.supportedLocale(equivalentTo: .current)
        if let locale = Self.preferredLocale(current: preferred, supported: installed) {
            let transcriber = SpeechTranscriber(locale: locale, preset: .transcriptionWithAlternatives)
            if await AssetInventory.status(forModules: [transcriber]) == .installed {
                speechAssetsAvailability = .ready(locale.identifier)
                return
            }
        }

        guard let (transcriber, locale) = await Self.supportedTranscriber() else {
            speechAssetsAvailability = .unavailable
            return
        }
        switch await AssetInventory.status(forModules: [transcriber]) {
        case .installed:
            speechAssetsAvailability = .ready(locale.identifier)
        case .supported:
            speechAssetsAvailability = .downloadRequired(locale.identifier)
        case .downloading:
            speechAssetsAvailability = .downloading(locale.identifier)
        case .unsupported:
            speechAssetsAvailability = .unsupported(locale.identifier)
        @unknown default:
            speechAssetsAvailability = .unavailable
        }
    }

    func installSpeechAssets() async {
        guard !isInstallingSpeechAssets, state != .recording, state != .paused, state != .processing else { return }
        isInstallingSpeechAssets = true
        message = nil
        defer { isInstallingSpeechAssets = false }

        guard await Self.requestSpeechRecognitionPermission() else {
            state = .permissionRequired
            message = "Speech Recognition access is required. Enable MyNotes in System Settings → Privacy & Security → Speech Recognition."
            return
        }

        do {
            guard let (transcriber, locale) = await Self.supportedTranscriber() else {
                state = .unavailable
                message = "macOS reports no supported local Speech transcription language on this Mac."
                return
            }
            switch await AssetInventory.status(forModules: [transcriber]) {
            case .installed:
                speechAssetsAvailability = .ready(locale.identifier)
                state = .idle
                message = "Local Speech assets for \(locale.identifier) are ready. You can record."
                return
            case .unsupported:
                speechAssetsAvailability = .unsupported(locale.identifier)
                state = .unavailable
                message = "macOS does not provide local Speech assets for \(locale.identifier) on this Mac."
                return
            case .downloading:
                speechAssetsAvailability = .downloading(locale.identifier)
                state = .idle
                message = "macOS is already downloading Speech assets for \(locale.identifier). Try again when it finishes."
                return
            case .supported:
                break
            @unknown default:
                state = .unavailable
                message = "macOS could not determine whether Speech assets are available."
                return
            }

            speechAssetsAvailability = .downloading(locale.identifier)
            guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
                state = .failed
                speechAssetsAvailability = .downloadRequired(locale.identifier)
                message = "macOS did not provide a Speech asset installation request for \(locale.identifier)."
                return
            }
            try await request.downloadAndInstall()
            guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
                throw CaptureError.speechAssetsUnavailable
            }
            speechAssetsAvailability = .ready(locale.identifier)
            state = .idle
            message = "Local Speech assets for \(locale.identifier) are installed. You can record."
        } catch {
            state = .failed
            message = "Speech assets could not be installed: \(error.localizedDescription)"
            await refreshSpeechAssetStatus()
        }
    }

    func pause() {
        guard state == .recording else { return }
        if let activeSince { activeDuration += Date().timeIntervalSince(activeSince) }
        activeSince = nil
        sink?.setPaused(true)
        engine?.pause()
        state = .paused
        updateElapsed()
    }

    func resume() {
        guard state == .paused, let engine else { return }
        do {
            try engine.start()
            sink?.setPaused(false)
            activeSince = .now
            state = .recording
        } catch {
            state = .failed
            message = "Microphone capture could not resume: \(error.localizedDescription)"
            _ = stopCapture()
        }
    }

    func stopAndTranscribe() {
        guard state == .recording || state == .paused else { return }
        updateElapsed()
        if let captureFailure = stopCapture() {
            state = .failed
            message = captureFailure
            cleanupAudio()
            return
        }
        state = .processing
        let url = audioURL
        guard let url else {
            state = .failed
            message = "The temporary audio file could not be finalized. No note was created."
            cleanupAudio()
            return
        }
        processingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let segments = try await self.transcribe(url: url)
                try Task.checkCancellation()
                self.transcript = segments
                self.state = .completed
                self.message = segments.isEmpty ? "No speech was recognized. You can still add or edit transcript text before saving." : nil
            } catch is CancellationError {
                self.state = .idle
            } catch {
                self.state = .failed
                self.message = error.localizedDescription
            }
            self.cleanupAudio()
            self.processingTask = nil
        }
    }

    func cancelProcessing() {
        processingTask?.cancel()
        let activeAnalyzer = analyzer
        Task { await activeAnalyzer?.cancelAndFinishNow() }
    }

    func reset() {
        guard state != .recording && state != .paused && state != .processing else { return }
        transcript = []
        message = nil
        elapsed = 0
        startedAt = nil
        state = .idle
    }

    func terminate() {
        processingTask?.cancel()
        engine?.stop()
        cleanupAudio()
        timer?.invalidate()
        timer = nil
    }

    private func beginCapture() throws {
        let directory = Self.temporaryDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let url = directory.appending(path: "\(UUID().uuidString).caf")
        do {
            let engine = AVAudioEngine()
            let input = engine.inputNode
            let inputFormat = input.outputFormat(forBus: 0)
            guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else {
                throw CaptureError.microphoneUnavailable
            }
            guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000,
                                                   channels: 1, interleaved: true) else {
                throw CaptureError.audioFormatUnavailable
            }
            let file = try AVAudioFile(forWriting: url, settings: outputFormat.settings,
                                       commonFormat: .pcmFormatInt16, interleaved: true)
            let sink = try AudioCaptureSink(file: file, inputFormat: inputFormat, outputFormat: outputFormat)
            sink.installTap(on: input, format: inputFormat)
            try engine.start()
            self.audioURL = url
            self.engine = engine
            self.sink = sink
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    private func stopCapture() -> String? {
        timer?.invalidate()
        timer = nil
        if let activeSince { activeDuration += Date().timeIntervalSince(activeSince) }
        activeSince = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        let failure = sink?.finish()
        engine = nil
        sink = nil
        updateElapsed()
        return failure
    }

    private func updateElapsed() {
        elapsed = activeDuration + (activeSince.map { Date().timeIntervalSince($0) } ?? 0)
    }

    private func cleanupAudio() {
        stopCaptureIfNeeded()
        if let audioURL { try? FileManager.default.removeItem(at: audioURL) }
        audioURL = nil
    }

    private func stopCaptureIfNeeded() {
        guard engine != nil || sink != nil else { return }
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        _ = sink?.finish()
        engine = nil
        sink = nil
    }

    private static var temporaryDirectory: URL {
        FileManager.default.temporaryDirectory.appending(path: "MyNotesMeetingSessions", directoryHint: .isDirectory)
    }

    static func preferredLocale(current: Locale?, supported: [Locale]) -> Locale? {
        current.flatMap { current in supported.first { $0.identifier == current.identifier } }
            ?? supported.first { $0.language.languageCode?.identifier == "en" }
    }

    private static func supportedTranscriber() async -> (SpeechTranscriber, Locale)? {
        let locales = await SpeechTranscriber.supportedLocales
        let preferred = await SpeechTranscriber.supportedLocale(equivalentTo: .current)
        guard let locale = preferredLocale(current: preferred, supported: locales) else { return nil }
        return (SpeechTranscriber(locale: locale, preset: .transcriptionWithAlternatives), locale)
    }

    private static func installedTranscriber() async throws -> (transcriber: SpeechTranscriber, locale: Locale) {
        let installed = await SpeechTranscriber.installedLocales
        let current = await SpeechTranscriber.supportedLocale(equivalentTo: .current)
        let locale = preferredLocale(current: current, supported: installed)
        guard let locale else { throw CaptureError.speechAssetsUnavailable }
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcriptionWithAlternatives)
        guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
            throw CaptureError.speechAssetsUnavailable
        }
        return (transcriber, locale)
    }

    private static func requestMicrophonePermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
            }
        @unknown default: return false
        }
    }

    private static func requestSpeechRecognitionPermission() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .denied, .restricted: return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        @unknown default: return false
        }
    }

    private func transcribe(url: URL) async throws -> [TranscriptSegment] {
        let (transcriber, locale) = try await Self.installedTranscriber()
        let audioFile = try AVAudioFile(forReading: url)
        let analyzer = SpeechAnalyzer(modules: [transcriber], options: .init(priority: .userInitiated, modelRetention: .whileInUse))
        self.analyzer = analyzer
        defer { self.analyzer = nil }
        let audioFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber],
                                                                         considering: audioFile.processingFormat)
        try await analyzer.prepareToAnalyze(in: audioFormat)
        let resultsTask = Task { () throws -> [TranscriptSegment] in
            var segments: [TranscriptSegment] = []
            for try await result in transcriber.results {
                let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let start = result.range.start.seconds
                let end = start + result.range.duration.seconds
                segments.append(TranscriptSegment(startTime: start.isFinite ? start : 0,
                                                  endTime: end.isFinite ? end : 0,
                                                  text: text, languageCode: locale.identifier))
            }
            return segments
        }
        do {
            let finalTime = try await analyzer.analyzeSequence(from: audioFile)
            if let finalTime {
                try await analyzer.finalizeAndFinish(through: finalTime)
            } else {
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            }
        } catch {
            resultsTask.cancel()
            throw error
        }
        let segments = try await resultsTask.value
        return segments.sorted { $0.startTime < $1.startTime }
    }

    fileprivate enum CaptureError: LocalizedError, Equatable {
        case microphoneUnavailable, speechAssetsUnavailable, audioFormatUnavailable, audioConverterUnavailable
        var errorDescription: String? {
            switch self {
            case .microphoneUnavailable: "No usable microphone is available. Connect a microphone and try again."
            case .speechAssetsUnavailable: "No compatible local macOS Speech assets are installed. Use Download Speech Assets before recording."
            case .audioFormatUnavailable: "MyNotes could not prepare a compatible audio format for transcription."
            case .audioConverterUnavailable: "MyNotes could not prepare the microphone audio converter."
            }
        }
    }
}

/// Writes bounded, resampled mono audio synchronously from AVAudioEngine's serial tap callback.
nonisolated private final class AudioCaptureSink: @unchecked Sendable {
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var paused = false
    private var failure: String?

    init(file: AVAudioFile, inputFormat: AVAudioFormat, outputFormat: AVAudioFormat) throws {
        self.file = file
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw MeetingCaptureCoordinator.CaptureError.audioConverterUnavailable
        }
        self.converter = converter
    }

    func installTap(on input: AVAudioInputNode, format: AVAudioFormat) {
        // Keep the realtime callback in this nonisolated type: AVAudioEngine
        // invokes it off the main actor, and inheriting UI isolation crashes.
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            self.consume(buffer)
        }
    }

    func setPaused(_ paused: Bool) {
        lock.lock()
        self.paused = paused
        lock.unlock()
    }

    func consume(_ input: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard failure == nil, !paused, let file, let converter else { return }
        let ratio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio + 64)
        guard let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else {
            failure = "MyNotes could not allocate a microphone audio buffer."
            return
        }
        var conversionError: NSError?
        var suppliedInput = false
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            guard !suppliedInput else {
                inputStatus.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            inputStatus.pointee = .haveData
            return input
        }
        guard status != .error, conversionError == nil else {
            failure = "Microphone audio conversion failed: \(conversionError?.localizedDescription ?? "unknown conversion error")."
            return
        }
        guard output.frameLength > 0 else { return }
        do {
            try file.write(from: output)
        } catch {
            failure = "Could not write temporary microphone audio: \(error.localizedDescription)"
        }
    }

    func finish() -> String? {
        lock.lock()
        let error = failure
        file = nil
        converter = nil
        lock.unlock()
        return error
    }
}
