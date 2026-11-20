import AppKit
import SwiftData
import SwiftUI

// MyNotes
//   MyNotes                      the app
//   APP_STORE=<file> MyNotes     use another database (tests, experiments)
//   APP_SNAPSHOT=<dir> MyNotes   save a PNG of every sidebar page and Settings tab in light and dark mode, then quit
//   APP_SEED=1 MyNotes           fill an empty /tmp store with sample items (tools/snap.sh)
//   MyNotes --selftest           run the self-test on a /tmp store and quit with 0 or 1 (tools/selftest.sh)
//   APP_ACCENT=<id> MyNotes      run with another accent from Theme.all (UI/Theme.swift)
//   APP_GRID=1 MyNotes           draw the 8 pt grid and the layout probes over the window

@main
struct MyNotesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared

    private var opensLibraryForAutomation: Bool {
        let environment = ProcessInfo.processInfo.environment
        return SelfTest.requested || environment["APP_SEED"] == "1" || environment["APP_SNAPSHOT"] != nil
    }

    private var meetingIsRecording: Bool { model.meetingCapture.state == .recording }

    private var menuBarSymbol: String {
        switch model.meetingCapture.state {
        case .recording: "waveform.circle.fill"
        case .paused: "pause.circle.fill"
        case .processing: "waveform"
        default: "note.text"
        }
    }

    var body: some Scene {
        Window("MyNotes", id: "main") {
            ContentView()
                .environment(model)
                .themed()
                .overlay { if GridOverlay.enabled { GridOverlay() } }
                .frame(minWidth: 760, minHeight: 480)
        }
        .modelContainer(model.container)
        .defaultSize(width: 1100, height: 720)
        .windowToolbarStyle(.unified)
        .defaultLaunchBehavior(opensLibraryForAutomation ? .automatic : .suppressed)
        .commands {
            SidebarCommands()
            ToolbarCommands()
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { NSApp.sendAction(Selector(("undo:")), to: nil, from: nil) }
                    .keyboardShortcut("z", modifiers: .command)
                Button("Redo") { NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .pasteboard) {
                Button("Cut") { NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) }
                    .keyboardShortcut("x", modifiers: .command)
                Button("Copy") { NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) }
                    .keyboardShortcut("c", modifiers: .command)
                Button("Paste") { NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) }
                    .keyboardShortcut("v", modifiers: .command)
                Button("Select All") { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }
                    .keyboardShortcut("a", modifiers: .command)
            }
            CommandGroup(replacing: .newItem) {
                Button("New Note") { model.addNote() }
                    .keyboardShortcut("n")
            }
            CommandGroup(after: .newItem) {
                Button("Show Quick Notes") { model.showQuickNotes() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Find Notes") { model.focusSearch() }
                    .keyboardShortcut("f", modifiers: .command)
            }
        }

        Window("Meeting Capture", id: "meeting-capture") {
            MeetingCaptureView()
                .environment(model)
                .themed()
        }
        .defaultSize(width: 720, height: 560)
        .windowResizability(.contentSize)

        MenuBarExtra("MyNotes", systemImage: menuBarSymbol) {
            MenuBarMenu()
                .environment(model)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environment(model)
                .themed()
        }
        .windowResizability(.contentSize)
    }
}

private struct MenuBarMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Show Quick Notes") { model.showQuickNotes() }
        Button("Open Notes Library") { openWindow(id: "main") }
        Button("Settings…") { openSettings() }
        Divider()
        Button("Quit MyNotes") { NSApp.terminate(nil) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        MeetingCaptureCoordinator.cleanupStaleAudio()
        AppModel.shared.startPanelMonitoring()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// The self-test's result becomes the exit code, after a normal quit.
    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.meetingCapture.terminate()
        if SelfTest.requested { exit(SelfTest.exitCode) }
    }
}

/// Plain-text notes live directly in the Notes Folder. A separate SwiftData
/// file stores only richer clipboard-history items; the former MyNotes.store
/// is deliberately left untouched so older app data is never opened as the
/// new clipboard schema.
enum Store {
    static let folderPreferenceKey = "storage.folderPath"

    /// True when APP_STORE points somewhere else (tests, snapshots, seed data).
    static var isOverridden: Bool {
        !(ProcessInfo.processInfo.environment["APP_STORE"] ?? "").isEmpty
    }

    static var url: URL {
        if let path = ProcessInfo.processInfo.environment["APP_STORE"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return clipboardURL
    }

    static var folderURL: URL {
        if isOverridden {
            let storeURL = url
            return storeURL.deletingLastPathComponent()
                .appendingPathComponent(storeURL.lastPathComponent + "-notes", isDirectory: true)
        }
        if !isOverridden,
           let path = UserDefaults.standard.string(forKey: folderPreferenceKey), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return URL.applicationSupportDirectory.appending(path: "MyNotes", directoryHint: .isDirectory)
    }

    static var clipboardURL: URL {
        folderURL.appending(path: "ClipboardHistory.store")
    }

    static func makeContainer() -> ModelContainer {
        do { return try makeContainer(in: url) }
        catch { fatalError("Could not open the clipboard history at \(url.path): \(error)") }
    }

    static func makeContainer(in storeURL: URL) throws -> ModelContainer {
        try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try ModelContainer(for: ClipboardEntry.self,
                                  configurations: ModelConfiguration(url: storeURL))
    }
}
