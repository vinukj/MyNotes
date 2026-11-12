import SwiftData
import SwiftUI
import MyNotesKit

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        NavigationSplitView {
            List {
                Label("All Notes", systemImage: "note.text")
            }
            .listStyle(.sidebar)
            .navigationTitle("Library")
        } content: {
            NoteList()
                .navigationSplitViewColumnWidth(min: 240, ideal: 300)
        } detail: {
            NoteDetail()
        }
        .task {
            model.startPanelMonitoring()
            SeedData.insertIfRequested(into: model)
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings)
        }
        .storageErrorAlert(model: model)
    }
}

extension View {
    func storageErrorAlert(model: AppModel) -> some View {
        alert("Storage Issue", isPresented: Binding(
            get: { model.storageError != nil },
            set: { if !$0 { model.storageError = nil } }
        )) {
            Button("OK", role: .cancel) { model.storageError = nil }
        } message: {
            Text(model.storageError ?? "An unexpected storage error occurred.")
        }
    }
}

struct NoteList: View {
    @Environment(AppModel.self) private var model
    @FocusState private var searchIsFocused: Bool

    private var visible: [TextNote] {
        model.notes.filter { NoteSearch.matches(title: $0.title, body: $0.body, query: model.searchText) }
    }

    var body: some View {
        @Bindable var model = model
        List(visible, selection: $model.selectedNoteID) { note in
            HStack(spacing: Space.sm) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(note.title.isEmpty ? "Untitled" : note.title)
                        .lineLimit(1)
                    if !note.body.isEmpty {
                        Text(note.body)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: Space.xs)
                Button("Delete Note", systemImage: "trash", role: .destructive) {
                    model.deleteNote(note)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Delete \(note.title)")
            }
            .tag(note.id)
            .contextMenu {
                Button("Delete Note", systemImage: "trash", role: .destructive) {
                    model.deleteNote(note)
                }
            }
        }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Search Notes")
        .searchFocused($searchIsFocused)
        .onChange(of: model.searchFocusRequest) { searchIsFocused = true }
        .overlay {
            if visible.isEmpty {
                ContentUnavailableView(
                    model.searchText.isEmpty ? "No Notes Yet" : "No Matching Notes",
                    systemImage: model.searchText.isEmpty ? "note.text" : "magnifyingglass",
                    description: Text(model.searchText.isEmpty ? "Create a note to get started." : "Try another search.")
                )
            }
        }
        .navigationTitle("All Notes")
        .toolbar {
            ToolbarItem {
                Button("New Note", systemImage: "square.and.pencil") { model.addNote() }
                    .help("Create a note (Command-N)")
            }
        }
        .onDeleteCommand {
            guard let note = model.notes.first(where: { $0.id == model.selectedNoteID }) else { return }
            model.deleteNote(note)
        }
    }
}

struct NoteDetail: View {
    @Environment(AppModel.self) private var model

    private var selectedNote: TextNote? { model.notes.first { $0.id == model.selectedNoteID } }

    var body: some View {
        if let note = selectedNote {
            NoteEditor(note: note)
                .id(note.id)
        } else {
            ContentUnavailableView("Select a Note", systemImage: "note.text", description: Text("Choose a note or create a new one."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct NoteEditor: View {
    @Environment(AppModel.self) private var model
    @Bindable var note: TextNote
    @FocusState private var titleIsFocused: Bool
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            TextField("Title", text: $note.title)
                .font(.title2)
                .textFieldStyle(.plain)
                .focused($titleIsFocused)
                .onChange(of: note.title) { scheduleSave() }
            TextEditor(text: $note.body)
                .font(.body)
                .scrollContentBackground(.hidden)
                .onChange(of: note.body) { scheduleSave() }
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: model.focusTitleForNoteID, initial: true) { _, newValue in
            guard newValue == note.id else { return }
            Task { @MainActor in
                // Let SwiftUI install the newly selected editor before moving
                // first responder, especially in the nonactivating panel.
                await Task.yield()
                guard model.selectedNoteID == note.id else { return }
                titleIsFocused = true
                model.focusTitleForNoteID = nil
            }
        }
        .onDisappear {
            saveTask?.cancel()
            model.saveNote(note)
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            model.saveNote(note)
        }
    }
}
