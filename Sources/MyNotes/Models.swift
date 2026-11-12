import AppKit
import Foundation
import Observation
import SwiftData
import MyNotesKit

@Model
final class ClipboardEntry {
    @Attribute(.unique) var uid: UUID
    var capturedAt: Date
    var kind: String
    var fingerprint: String
    var text: String
    @Attribute(.externalStorage) var imageData: Data?
    var fileURLsJSON: String

    init(kind: String, fingerprint: String, text: String = "", imageData: Data? = nil,
         fileURLsJSON: String = "[]", uid: UUID = UUID(), capturedAt: Date = .now) {
        self.uid = uid
        self.capturedAt = capturedAt
        self.kind = kind
        self.fingerprint = fingerprint
        self.text = text
        self.imageData = imageData
        self.fileURLsJSON = fileURLsJSON
    }

    var fileURLs: [URL] {
        guard let data = fileURLsJSON.data(using: .utf8),
              let paths = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return paths.map { URL(fileURLWithPath: $0) }
    }

    var preview: String {
        switch kind {
        case ClipboardHistory.Kind.text.rawValue:
            return text.replacingOccurrences(of: "\n", with: " ").prefix(160).description
        case ClipboardHistory.Kind.image.rawValue:
            return "Image"
        case ClipboardHistory.Kind.files.rawValue:
            let names = fileURLs.map(\.lastPathComponent)
            return names.count == 1 ? names[0] : "\(names.count) files"
        default:
            return "Clipboard item"
        }
    }
}

@MainActor
@Observable
final class AppModel {
    var container: ModelContainer
    var notes: [TextNote]
    var storageError: String?
    var unreadableNoteFiles: [String] = []
    var selectedNoteID: UUID?
    var searchText = ""
    var focusTitleForNoteID: UUID?
    var searchFocusRequest = 0
    @ObservationIgnored private var clipboardTimer: Timer?
    @ObservationIgnored private var lastClipboardChangeCount: Int?
    @ObservationIgnored private var deletedNoteIDs = Set<UUID>()
    var settingsTab: SettingsTab = SettingsTab(
        rawValue: UserDefaults.standard.string(forKey: "settings.tab") ?? ""
    ) ?? .general {
        didSet {
            if !Store.isOverridden { UserDefaults.standard.set(settingsTab.rawValue, forKey: "settings.tab") }
        }
    }
    private(set) var panelController: FloatingNotesPanelController?
    private var noteStore: TextNoteStore

    init(container: ModelContainer) {
        self.container = container
        let store = TextNoteStore(directoryURL: Store.folderURL)
        noteStore = store
        do {
            let result = try store.loadDetailed()
            notes = result.notes
            unreadableNoteFiles = result.unreadableFiles
            storageError = nil
        } catch {
            notes = []
            storageError = "Could not read notes from this folder: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func addNote() -> TextNote? {
        do {
            // A note created while searching may not match the current query,
            // leaving the editor on a different note and making the new one
            // appear unresponsive.
            searchText = ""
            let note = try noteStore.create()
            notes.insert(note, at: 0)
            storageError = nil
            selectedNoteID = note.id
            focusTitleForNoteID = note.id
            return note
        } catch {
            storageError = "Could not create the note: \(error.localizedDescription)"
            return nil
        }
    }

    func saveNote(_ note: TextNote) {
        // A debounced save or NoteEditor.onDisappear can arrive after the
        // delete action. Do not let that stale editor recreate the .txt file.
        guard !deletedNoteIDs.contains(note.id) else { return }
        do {
            // The debounce or onDisappear callback can outlive a folder
            // switch. Always route a note back to the folder that owns its
            // file instead of the currently selected folder.
            try TextNoteStore.owning(note: note).update(note, title: note.title, body: note.body)
            notes.sort {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            storageError = nil
        } catch {
            storageError = "Could not save the note: \(error.localizedDescription)"
        }
    }

    func deleteNote(_ note: TextNote) {
        do {
            // A note can outlive the selected folder briefly while SwiftUI
            // tears down its editor, and folder URLs can have different
            // aliases (for example, a picker/bookmark URL versus its
            // standardized file URL). Delete through the file's owner just
            // like delayed saves, never through whichever folder is active.
            try TextNoteStore.owning(note: note).delete(note)
            deletedNoteIDs.insert(note.id)
            notes.removeAll { $0.id == note.id }
            if selectedNoteID == note.id { selectedNoteID = nil }
            storageError = nil
        } catch {
            storageError = "Could not delete the note: \(error.localizedDescription)"
        }
    }

    func refreshNotes() {
        do {
            let result = try noteStore.loadDetailed()
            notes = result.notes
            unreadableNoteFiles = result.unreadableFiles
            if let selectedNoteID, !notes.contains(where: { $0.id == selectedNoteID }) {
                self.selectedNoteID = nil
            }
            storageError = nil
        } catch {
            storageError = "Could not read notes from this folder: \(error.localizedDescription)"
        }
    }

    private func selectNoteFolder(_ folder: URL) throws {
        // Persist the open editor before replacing the visible notes. Its
        // onDisappear save may run after noteStore changes, so save through
        // the current store now and make later delayed saves owner-aware.
        if let selectedNote = notes.first(where: { $0.id == selectedNoteID }) {
            try noteStore.update(selectedNote, title: selectedNote.title, body: selectedNote.body)
        }
        let nextStore = TextNoteStore(directoryURL: folder)
        let loadResult = try nextStore.loadDetailed()
        let nextNotes = loadResult.notes
        let nextContainer = try Store.makeContainer(in: folder.appending(path: "ClipboardHistory.store"))
        UserDefaults.standard.set(folder.path, forKey: Store.folderPreferenceKey)
        noteStore = nextStore
        notes = nextNotes
        unreadableNoteFiles = loadResult.unreadableFiles
        container = nextContainer
        storageError = nil
        selectedNoteID = nil
        searchText = ""
        panelController?.refreshStore()
    }

    func selectStorageFolder(_ folder: URL) throws {
        guard !Store.isOverridden else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try selectNoteFolder(folder)
    }

    func startPanelMonitoring() {
        guard panelController == nil else { return }
        let controller = FloatingNotesPanelController(model: self)
        panelController = controller
        guard !Store.isOverridden, GestureProcessLease.shared.acquire() else { return }
        controller.startMonitoring()
        startClipboardMonitoring()
    }

    func showQuickNotes() { panelController?.present() }
    func hideQuickNotes() { panelController?.hide() }
    func focusSearch() { searchFocusRequest &+= 1 }

    var clipboardHistoryEnabled: Bool {
        UserDefaults.standard.object(forKey: "clipboard.historyEnabled") as? Bool ?? false
    }

    func setClipboardHistoryEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "clipboard.historyEnabled")
        lastClipboardChangeCount = NSPasteboard.general.changeCount
    }

    func clearClipboardHistory() {
        let context = container.mainContext
        do {
            let entries = try context.fetch(FetchDescriptor<ClipboardEntry>())
            for entry in entries { context.delete(entry) }
            try context.save()
            storageError = nil
        } catch {
            context.rollback()
            storageError = "Could not clear clipboard history: \(error.localizedDescription)"
        }
    }

    func deleteClipboardEntry(_ entry: ClipboardEntry) {
        let context = container.mainContext
        context.delete(entry)
        do {
            try context.save()
            storageError = nil
        } catch {
            context.rollback()
            storageError = "Could not remove that clipboard item: \(error.localizedDescription)"
        }
    }

    private func startClipboardMonitoring() {
        guard clipboardTimer == nil else { return }
        lastClipboardChangeCount = NSPasteboard.general.changeCount
        let timer = Timer(timeInterval: 0.6, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.captureClipboardIfChanged() }
        }
        timer.tolerance = 0.2
        clipboardTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func captureClipboardIfChanged() {
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        guard changeCount != lastClipboardChangeCount else { return }
        guard clipboardHistoryEnabled else {
            lastClipboardChangeCount = changeCount
            return
        }
        let result = ClipboardHistory.capture(from: pasteboard, in: container.mainContext)
        // Do not retry the same failed pasteboard change every timer tick.
        lastClipboardChangeCount = changeCount
        switch result {
        case .captured, .ignored:
            storageError = nil
        case .failed(let error):
            storageError = "Could not save clipboard history: \(error.localizedDescription)"
        }
    }
}
