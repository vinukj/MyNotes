import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.settingsTab) {
            ForEach(SettingsTab.allCases) { tab in
                page(tab)
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .tag(tab)
            }
        }
        .noInitialFocus()
    }

    @ViewBuilder
    private func page(_ tab: SettingsTab) -> some View {
        Form {
            switch tab {
            case .general: GeneralSettings()
            case .storage: StorageSettings()
            case .appearance: AppearanceSettings()
            }
        }
        .formStyle(.grouped)
        .fitsContent()
        .frame(width: 520)
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, storage, appearance

    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: "General"
        case .storage: "Storage"
        case .appearance: "Appearance"
        }
    }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .storage: "folder"
        case .appearance: "paintpalette"
        }
    }
}

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage("gesture.topEdgeEnabled") private var topEdgeGestureEnabled = true
    @AppStorage("clipboard.historyEnabled") private var clipboardHistoryEnabled = false

    var body: some View {
        Section("Quick Notes") {
            Toggle("Enable top-edge gesture", isOn: $topEdgeGestureEnabled)
            Text("Move the pointer to the top edge, then scroll down to reveal Quick Notes.")
                .foregroundStyle(.secondary)
        }
        Section("Clipboard History") {
            Toggle("Keep a local clipboard history", isOn: $clipboardHistoryEnabled)
                .onChange(of: clipboardHistoryEnabled) { _, enabled in
                    model.setClipboardHistoryEnabled(enabled)
                }
            Text("When enabled, recent text, images, and copied files are kept on this Mac in ClipboardHistory.store inside your selected folder. Notes themselves remain ordinary .txt files. Password-manager and marked-sensitive copies are skipped.")
                .foregroundStyle(.secondary)
            if clipboardHistoryEnabled {
                Button("Clear Clipboard History", systemImage: "trash", role: .destructive) {
                    model.clearClipboardHistory()
                }
            }
        }
    }
}

struct StorageSettings: View {
    @Environment(AppModel.self) private var model
    @State private var errorMessage: String?

    var body: some View {
        Section("Notes Folder") {
            LabeledContent("Current Folder") {
                Text(Store.folderURL.path)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            Button("Choose Folder…", systemImage: "folder") { chooseFolder() }
                .disabled(Store.isOverridden)
            Text("Changing folders switches to that folder’s library; it does not move notes from the current folder.")
                .foregroundStyle(.secondary)
            Text("Notes are stored as individual .txt files directly in this folder. Clipboard history, when enabled, uses a separate ClipboardHistory.store file here.")
                .foregroundStyle(.secondary)
            if Store.isOverridden {
                Text("Folder selection is disabled during test and snapshot runs.")
                    .foregroundStyle(.secondary)
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
    }

    private func chooseFolder() {
        let picker = NSOpenPanel()
        picker.title = "Choose Notes Folder"
        picker.prompt = "Use This Folder"
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        picker.allowsMultipleSelection = false
        guard picker.runModal() == .OK, let folder = picker.url else { return }
        do {
            try model.selectStorageFolder(folder)
        } catch {
            errorMessage = "Could not use that folder: \(error.localizedDescription)"
        }
    }
}
