import AppKit
import MyNotesKit
import SwiftUI

struct MeetingCaptureView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Bindable private var capture: MeetingCaptureCoordinator
    @State private var agenda = ""
    @State private var transcriptDraft = ""
    @State private var copied = false

    init() {
        _capture = Bindable(wrappedValue: AppModel.shared.meetingCapture)
    }

    private var canSave: Bool {
        capture.state == .completed && !transcriptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            header

            TextField("Meeting agenda (optional)", text: $agenda)
                .textFieldStyle(.roundedBorder)
                .gridProbe("meeting-agenda", area: "meeting-capture")

            recordingControls

            if capture.state == .completed || capture.state == .failed && !capture.transcript.isEmpty {
                transcriptEditor
            } else if capture.state == .idle || capture.state == .unavailable || capture.state == .permissionRequired {
                ContentUnavailableView("Ready to Record", systemImage: "waveform",
                                       description: Text("Recording uses your microphone. MyNotes transcribes locally with macOS Speech assets. Temporary audio is deleted afterward."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer(minLength: Space.xl)
            }

            if let message = capture.message {
                Label(message, systemImage: capture.state == .failed ? "exclamationmark.triangle" : "info.circle")
                    .font(.callout)
                    .foregroundStyle(capture.state == .failed ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .gridProbe("meeting-message", area: "meeting-capture")
            }
            if let storageError = model.storageError {
                Label(storageError, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.xl)
        .frame(minWidth: 600, minHeight: 440, alignment: .topLeading)
        .gridArea("meeting-capture")
        .noInitialFocus()
        .task { await capture.refreshSpeechAssetStatus() }
        .onChange(of: capture.state) { _, state in
            guard state == .completed, transcriptDraft.isEmpty else { return }
            transcriptDraft = capture.transcript.map { segment in
                let seconds = max(0, Int(segment.startTime))
                return "[\(String(format: "%02d:%02d", seconds / 60, seconds % 60))] \(segment.text)"
            }.joined(separator: "\n")
        }
    }

    private var header: some View {
        let isRecording = capture.state == .recording
        return HStack(spacing: Space.md) {
            Image(systemName: "waveform.and.mic")
                .font(.title2)
                .foregroundStyle(isRecording ? Color.red : capture.state == .paused ? Color.orange : Palette.accent)
                .shadow(color: isRecording ? .red.opacity(0.65) : .clear, radius: isRecording ? 8 : 0)
                .symbolEffect(.pulse, options: .repeating, isActive: isRecording)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Meeting Capture").font(.title2.weight(.semibold))
                Text("Local microphone transcription • No audio uploads")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label(captureStatusTitle,
                  systemImage: capture.state == .recording ? "record.circle.fill" : capture.state == .paused ? "pause.circle.fill" : capture.state == .processing ? "waveform" : "waveform")
                .font(.callout.weight(.medium))
                .foregroundStyle(isRecording ? .red : capture.state == .paused ? .orange : capture.state == .processing ? .blue : .secondary)
                .accessibilityIdentifier("meeting-capture-state")
        }
        .gridProbe("meeting-header", area: "meeting-capture")
    }

    @ViewBuilder
    private var recordingControls: some View {
        HStack(spacing: Space.md) {
            switch capture.state {
            case .idle, .failed, .completed, .unavailable, .permissionRequired:
                Button("Start Recording", systemImage: "record.circle") {
                    transcriptDraft = ""
                    Task { await capture.start() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(capture.state == .preparing || capture.isInstallingSpeechAssets)
                switch capture.speechAssetsAvailability {
                case .checking:
                    ProgressView("Checking local assets…")
                case .ready(let locale):
                    Label("Speech assets ready · \(locale)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityIdentifier("speech-assets-ready")
                case .downloadRequired(let locale):
                    Button("Download Speech Assets · \(locale)", systemImage: "arrow.down.circle") {
                        Task { await capture.installSpeechAssets() }
                    }
                    .disabled(capture.isInstallingSpeechAssets)
                case .downloading(let locale):
                    ProgressView("macOS is downloading \(locale)…")
                case .unsupported(let locale):
                    Label("Speech assets unavailable · \(locale)", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                case .unavailable:
                    Label("No local Speech language is available", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
                if capture.isInstallingSpeechAssets {
                    ProgressView("Installing local assets…")
                }
            case .preparing:
                ProgressView("Preparing microphone…")
            case .recording:
                Label(clock(capture.elapsed), systemImage: "record.circle.fill")
                    .monospacedDigit()
                    .foregroundStyle(.red)
                Button("Pause", systemImage: "pause.fill") { capture.pause() }
                Button("Stop and Transcribe", systemImage: "stop.fill") { capture.stopAndTranscribe() }
                    .buttonStyle(.borderedProminent)
            case .paused:
                Label("Paused · \(clock(capture.elapsed))", systemImage: "pause.circle.fill")
                    .monospacedDigit()
                Button("Resume", systemImage: "play.fill") { capture.resume() }
                    .buttonStyle(.borderedProminent)
                Button("Stop and Transcribe", systemImage: "stop.fill") { capture.stopAndTranscribe() }
            case .processing:
                ProgressView("Transcribing locally…")
                Button("Cancel", role: .cancel) { capture.cancelProcessing() }
            }
        }
        .gridProbe("meeting-controls", area: "meeting-capture")
    }

    private var transcriptEditor: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Label("Review transcript", systemImage: "text.alignleft")
                .font(.headline)
            TextEditor(text: $transcriptDraft)
                .font(.body.monospaced())
                .scrollContentBackground(.hidden)
                .padding(Space.xs)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                .frame(minHeight: 180)
                .accessibilityLabel("Editable meeting transcript")
                .gridProbe("meeting-transcript", area: "meeting-capture")
            HStack {
                Button(copied ? "Copied" : "Copy Markdown", systemImage: copied ? "checkmark" : "doc.on.doc") {
                    let markdown = renderedMarkdown
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    copied = pasteboard.setString(markdown, forType: .string)
                }
                Button("Create Note", systemImage: "note.text.badge.plus") {
                    guard let note = model.createMeetingNote(title: metadata.noteTitle, body: renderedMarkdown) else { return }
                    model.selectedNoteID = note.id
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
                Spacer()
                Button("Discard", role: .destructive) {
                    transcriptDraft = ""
                    capture.reset()
                }
            }
        }
        .gridProbe("meeting-review", area: "meeting-capture")
    }

    private var metadata: MeetingMetadata {
        MeetingMetadata(startedAt: capture.startedAt ?? .now, endedAt: .now,
                        durationSeconds: capture.elapsed, title: agenda)
    }

    private var renderedMarkdown: String {
        MeetingMarkdownRenderer.renderTranscript(metadata: metadata, transcript: transcriptDraft)
    }

    private func clock(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%02d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
    }

    private var captureStatusTitle: String {
        switch capture.state {
        case .recording: "Recording"
        case .paused: "Paused"
        case .processing: "Transcribing"
        default: capture.state.rawValue.capitalized
        }
    }
}
