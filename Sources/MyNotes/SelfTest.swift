import AppKit
import SwiftData
import MyNotesKit

/// Self-test for the app's real functions on a test store,
/// prints PASS or FAIL per check, and quits with exit code 0 or 1.
///   APP_STORE=/tmp/MyNotes-self.store ~/Applications/MyNotes.app/Contents/MacOS/MyNotes --selftest
/// (tools/selftest.sh does this.) Add a check for every story with logic.
@MainActor
enum SelfTest {
    static var requested: Bool { CommandLine.arguments.contains("--selftest") }
    /// Read by AppDelegate.applicationWillTerminate.
    static var exitCode: Int32 = 0
    private static var failures = 0
    private static var count = 0

    static func runIfRequested(model: AppModel) {
        guard requested else { return }
        // Print each line at once, so a crash keeps the lines before it.
        setvbuf(stdout, nil, _IOLBF, 0)
        guard Store.isOverridden else {
            print("SELFTEST refused: set APP_STORE to a file in /tmp")
            finish(code: 1)
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            let context = model.container.mainContext

            // APP_STORE gives this run an isolated sibling notes folder.
            for note in model.notes { model.deleteNote(note) }

            let before = model.notes.count
            let newNote = model.addNote()
            check("New Note creates one plain-text note", newNote != nil && model.notes.count == before + 1)
            check("the new note is selected", model.selectedNoteID != nil)
            model.startPanelMonitoring()
            model.showQuickNotes()
            check("Quick Notes shows without making a second panel", model.panelController?.panel?.isVisible == true)
            if let panel = model.panelController?.panel {
                let inside = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
                let outside = NSPoint(x: panel.frame.maxX + 1, y: panel.frame.midY)
                check("Quick Notes stays open when editing inside the panel", !panel.shouldDismissOnKeyLoss(at: inside))
                check("Quick Notes dismisses when focus leaves the panel", panel.shouldDismissOnKeyLoss(at: outside))
            }
            model.hideQuickNotes()
            check("Quick Notes hides cleanly", model.panelController?.panel?.isVisible == false)

            let clipboard = NSPasteboard(name: NSPasteboard.Name("MyNotesSelfTestClipboard"))
            clipboard.declareTypes([.string], owner: nil)
            clipboard.setString("Clipboard test text", forType: .string)
            let clipboardCaptured = ClipboardHistory.capture(from: clipboard, in: context)
            if case .captured = clipboardCaptured {
                check("clipboard history captures text locally", true)
            } else {
                check("clipboard history captures text locally", false)
            }
            let capturedEntries = (try? context.fetch(FetchDescriptor<ClipboardEntry>())) ?? []
            check("clipboard capture creates one history item", capturedEntries.count == 1 && capturedEntries.first?.text == "Clipboard test text")

            clipboard.declareTypes([.string], owner: nil)
            clipboard.setString("Clipboard test text", forType: .string)
            _ = ClipboardHistory.capture(from: clipboard, in: context)
            let deduplicatedEntries = (try? context.fetch(FetchDescriptor<ClipboardEntry>())) ?? []
            check("duplicate clipboard items do not create extra entries", deduplicatedEntries.count == 1)

            if let entry = deduplicatedEntries.first {
                let restored = ClipboardHistory.restore(entry, to: clipboard)
                check("clipboard history restores text", restored && clipboard.string(forType: .string) == "Clipboard test text")
            }

            let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
            clipboard.declareTypes([.string, concealedType], owner: nil)
            clipboard.setString("Sensitive clipboard text", forType: .string)
            let concealedResult = ClipboardHistory.capture(from: clipboard, in: context)
            if case .ignored = concealedResult {
                check("marked-sensitive clipboard items are skipped", true)
            } else {
                check("marked-sensitive clipboard items are skipped", false)
            }

            let sourceType = NSPasteboard.PasteboardType("org.nspasteboard.source")
            clipboard.declareTypes([.string, sourceType], owner: nil)
            clipboard.setString("Password", forType: .string)
            clipboard.setString("com.agilebits.onepassword", forType: sourceType)
            let passwordManagerResult = ClipboardHistory.capture(from: clipboard, in: context)
            if case .ignored = passwordManagerResult {
                check("password-manager clipboard items are skipped", true)
            } else {
                check("password-manager clipboard items are skipped", false)
            }
            model.clearClipboardHistory()
            check("clipboard history can be cleared", ((try? context.fetch(FetchDescriptor<ClipboardEntry>())) ?? []).isEmpty)

            if let note = model.notes.first(where: { $0.id == model.selectedNoteID }) {
                note.title = "Local-first title"
                note.body = "Searchable body text"
                model.saveNote(note)
                let savedNote = (try? TextNoteStore(directoryURL: Store.folderURL).load())?
                    .first { $0.title == "Local-first title" }
                check("a note saves its title and body as text", savedNote?.body == "Searchable body text")
                check("search matches note title", NoteSearch.matches(title: note.title, body: note.body, query: "LOCAL-FIRST"))
                check("search matches note body", NoteSearch.matches(title: note.title, body: note.body, query: "searchable"))
                check("empty search includes notes", NoteSearch.matches(title: note.title, body: note.body, query: "  "))
                let noteID = note.id
                check("the selected note uses its stable ID", noteID == model.selectedNoteID)
                model.deleteNote(note)
                check("deleting the note removes its text file",
                      model.notes.count == before && !FileManager.default.fileExists(atPath: note.fileURL.path),
                      model.storageError ?? note.fileURL.path)
                model.saveNote(note) // Simulate a debounced/onDisappear save arriving late.
                check("a delayed editor save cannot recreate a deleted note",
                      !FileManager.default.fileExists(atPath: note.fileURL.path))
            }
            check("empty titles have a friendly fallback", ItemTitle.clean("  \n") == "New Note")

            print(failures == 0 ? "SELFTEST PASS \(count) checks" : "SELFTEST FAIL \(failures) of \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        count += 1
        if !ok { failures += 1 }
        print(ok ? "PASS \(name)" : "FAIL \(name)\(detail.isEmpty ? "" : ": \(detail)")")
    }

    /// Quits through NSApp.terminate, never exit(), and closes sheets first:
    /// an open sheet refuses terminate, and the run would wait forever.
    static func finish(code: Int32) {
        exitCode = code
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        NSApp.terminate(nil)
    }
}
