import AppKit
import SwiftData
import SwiftUI
import MyNotesKit

@MainActor
final class FloatingNotesPanelController {
    private weak var model: AppModel?
    private var triggerMonitor: TopEdgeGestureMonitor?
    private(set) var panel: QuickNotesPanel?

    init(model: AppModel) {
        self.model = model
    }

    func startMonitoring() {
        guard triggerMonitor == nil else { return }
        let monitor = TopEdgeGestureMonitor { [weak self] in self?.present() }
        triggerMonitor = monitor
        monitor.start()
    }

    func present() {
        guard model != nil else { return }
        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel)
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func refreshStore() {
        guard let panel, model != nil else { return }
        panel.contentView = NSHostingView(rootView: panelRoot())
    }

    private func makePanel() -> QuickNotesPanel {
        let panel = QuickNotesPanel(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 352),
                                    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        let host = NSHostingView(rootView: panelRoot())
        host.sizingOptions = []
        panel.contentView = host
        return panel
    }

    private func panelRoot() -> some View {
        guard let model else { return AnyView(EmptyView()) }
        return AnyView(QuickNotesPanelView()
            .environment(model)
            .modelContainer(model.container)
            .themed())
    }

    private func position(_ panel: NSPanel) {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { panel.center(); return }
        let width = max(720, frame.width - Space.lg * 2)
        let height: CGFloat = 352
        panel.setFrame(NSRect(x: frame.minX + (frame.width - width) / 2,
                              y: frame.maxY - height - Space.sm,
                              width: width,
                              height: height), display: false)
    }
}

@MainActor
final class QuickNotesPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }

    override func resignKey() {
        super.resignKey()
        if shouldDismissOnKeyLoss(at: NSEvent.mouseLocation) {
            orderOut(nil)
        }
    }

    func shouldDismissOnKeyLoss(at pointerLocation: NSPoint) -> Bool {
        !frame.contains(pointerLocation)
    }
}

@MainActor
final class TopEdgeGestureMonitor {
    private let reveal: () -> Void
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isArmed = false

    init(reveal: @escaping () -> Void) {
        self.reveal = reveal
    }

    func start() {
        guard globalMonitor == nil, localMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .scrollWheel]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.consume(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.consume(event) }
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func consume(_ event: NSEvent) {
        guard UserDefaults.standard.object(forKey: "gesture.topEdgeEnabled") as? Bool != false else { return }
        let atTopEdge = NSScreen.screens.contains { abs($0.frame.maxY - NSEvent.mouseLocation.y) <= Space.sm }
        if event.type == .mouseMoved {
            isArmed = atTopEdge
            return
        }
        guard event.type == .scrollWheel, isArmed, atTopEdge else { return }
        let physicalDeltaY = event.scrollingDeltaY * (event.isDirectionInvertedFromDevice ? -1 : 1)
        guard physicalDeltaY < -0.5 else { return }
        isArmed = false
        reveal()
    }

}

struct QuickNotesPanelView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @FocusState private var searchIsFocused: Bool
    @State private var showingClipboardHistory = false
    @State private var clipboardSearch = ""

    private var visible: [TextNote] {
        model.notes.filter { NoteSearch.matches(title: $0.title, body: $0.body, query: model.searchText) }
    }
    private var selected: TextNote? { visible.first { $0.id == model.selectedNoteID } ?? visible.first }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: Space.sm) {
            HStack {
                Label(showingClipboardHistory ? "Clipboard History" : "Quick Notes",
                      systemImage: showingClipboardHistory ? "doc.on.clipboard" : "note.text")
                    .font(.headline)
                Spacer()
                Button("New Note", systemImage: "plus") { model.addNote() }
                    .labelStyle(.iconOnly)
                    .help("New Note (Command-N)")
                Button(showingClipboardHistory ? "Show Notes" : "Clipboard History",
                       systemImage: showingClipboardHistory ? "note.text" : "doc.on.clipboard") {
                    showingClipboardHistory.toggle()
                }
                .labelStyle(.iconOnly)
                .help(showingClipboardHistory ? "Show Quick Notes" : "Search Clipboard History")
                Button("Storage Settings", systemImage: "gearshape") {
                    model.settingsTab = .storage
                    openSettings()
                }
                .labelStyle(.iconOnly)
                .help("Choose where notes are stored")
                Button("Hide Quick Notes", systemImage: "xmark") {
                    NSApp.keyWindow?.orderOut(nil)
                }
                .labelStyle(.iconOnly)
                .help("Hide Quick Notes (Escape)")
            }
            if !showingClipboardHistory, !model.unreadableNoteFiles.isEmpty {
                Label("Skipped \(model.unreadableNoteFiles.count) unreadable .txt file(s)",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(model.unreadableNoteFiles.joined(separator: "\n"))
            }
            if showingClipboardHistory {
                ClipboardHistoryView(search: $clipboardSearch)
            } else {
                HStack(spacing: Space.md) {
                    VStack(spacing: Space.sm) {
                        TextField("Search Notes", text: $model.searchText)
                            .textFieldStyle(.roundedBorder)
                            .focused($searchIsFocused)
                        List(visible, selection: $model.selectedNoteID) { note in
                            HStack(spacing: Space.xs) {
                                VStack(alignment: .leading, spacing: Space.xs) {
                                    Text(note.title.isEmpty ? "Untitled" : note.title).lineLimit(1)
                                    Text(note.body.isEmpty ? "No additional text" : note.body)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer(minLength: 0)
                                Button("Delete Note", systemImage: "trash", role: .destructive) {
                                    model.deleteNote(note)
                                }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                                .help("Delete \(note.title)")
                            }
                            .tag(note.id)
                        }
                        .overlay {
                            if visible.isEmpty {
                                ContentUnavailableView("No Notes", systemImage: "note.text", description: Text("Create a note or change your search."))
                            }
                        }
                    }
                    .frame(width: 240)

                    if let note = selected {
                        NoteEditor(note: note)
                            .id(note.id)
                    } else {
                        ContentUnavailableView("Your Quick Notes", systemImage: "note.text", description: Text("Create a note to get started."))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .padding(Space.lg)
        .background(.ultraThinMaterial)
        .overlay { RoundedRectangle(cornerRadius: Space.md).strokeBorder(.primary.opacity(0.08), lineWidth: 1) }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if model.selectedNoteID == nil { model.selectedNoteID = visible.first?.id }
        }
        .onChange(of: model.searchFocusRequest) { searchIsFocused = true }
        .storageErrorAlert(model: model)
    }
}

private struct ClipboardHistoryView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("clipboard.historyEnabled") private var historyEnabled = false
    @Query(sort: \ClipboardEntry.capturedAt, order: .reverse) private var entries: [ClipboardEntry]
    @Binding var search: String

    private var visibleEntries: [ClipboardEntry] {
        guard !search.isEmpty else { return entries }
        return entries.filter { entry in
            entry.preview.localizedCaseInsensitiveContains(search)
                || entry.text.localizedCaseInsensitiveContains(search)
                || entry.fileURLs.contains { $0.lastPathComponent.localizedCaseInsensitiveContains(search) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            if !historyEnabled {
                ContentUnavailableView {
                    Label("Clipboard History Is Off", systemImage: "doc.on.clipboard")
                } description: {
                    Text("Turn it on to keep recent copies on this Mac.")
                } actions: {
                    Button("Enable Clipboard History") { model.setClipboardHistoryEnabled(true) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: Space.sm) {
                    TextField("Search Clipboard", text: $search)
                        .textFieldStyle(.roundedBorder)
                    if !entries.isEmpty {
                        Button("Clear History", systemImage: "trash", role: .destructive) {
                            model.clearClipboardHistory()
                        }
                        .labelStyle(.iconOnly)
                        .help("Clear Clipboard History")
                    }
                }

                if visibleEntries.isEmpty {
                    ContentUnavailableView(search.isEmpty ? "Clipboard Is Empty" : "No Matching Items",
                                           systemImage: search.isEmpty ? "doc.on.clipboard" : "magnifyingglass",
                                           description: Text(search.isEmpty ? "Copied items will appear here." : "Try another search."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: Space.xs) {
                            ForEach(visibleEntries) { entry in
                                ClipboardHistoryRow(entry: entry) {
                                    _ = ClipboardHistory.restore(entry)
                                } onDelete: {
                                    model.deleteClipboardEntry(entry)
                                }
                            }
                        }
                    }
                    .scrollIndicators(.automatic)
                }
            }
        }
    }
}

private struct ClipboardHistoryRow: View {
    let entry: ClipboardEntry
    let onRestore: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: Space.sm) {
            Button(action: onRestore) {
                HStack(spacing: Space.sm) {
                    if entry.kind == ClipboardHistory.Kind.image.rawValue,
                       let data = entry.imageData, let image = NSImage(data: data) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: Space.xs))
                    } else {
                        Image(systemName: symbol)
                            .font(.body)
                            .frame(width: 32, height: 32)
                    }
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(entry.preview)
                            .lineLimit(1)
                        Text(entry.capturedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                        .font(.caption)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Restore this item to the clipboard")

            Button("Remove Item", systemImage: "xmark") { onDelete() }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .help("Remove from Clipboard History")
        }
        .padding(.horizontal, Space.sm)
        .padding(.vertical, Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: Space.xs))
        .overlay { RoundedRectangle(cornerRadius: Space.xs).strokeBorder(.primary.opacity(0.08), lineWidth: 1) }
    }

    private var symbol: String {
        switch entry.kind {
        case ClipboardHistory.Kind.files.rawValue: "doc.on.doc"
        case ClipboardHistory.Kind.image.rawValue: "photo"
        default: "doc.text"
        }
    }
}
