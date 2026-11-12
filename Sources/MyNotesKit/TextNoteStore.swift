import Foundation
import Observation

/// A note backed by one ordinary UTF-8 `.txt` file.
@Observable
public final class TextNote: Identifiable {
    public let id: UUID
    public fileprivate(set) var fileURL: URL
    public var title: String
    public var body: String
    public fileprivate(set) var createdAt: Date
    public fileprivate(set) var updatedAt: Date

    fileprivate init(id: UUID = UUID(), fileURL: URL, title: String, body: String,
                     createdAt: Date, updatedAt: Date) {
        self.id = id
        self.fileURL = fileURL
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Reads and writes top-level text files in a user-selected folder.
public struct TextNoteStore {
    public let directoryURL: URL
    private let fileManager: FileManager

    public init(directoryURL: URL, fileManager: FileManager = .default) {
        self.directoryURL = directoryURL.standardizedFileURL
        self.fileManager = fileManager
    }

    /// Returns the store that owns a note, even if the app's selected folder
    /// has changed since that note's editor was created. Delayed SwiftUI saves
    /// can arrive while an old editor is being removed from the view tree.
    public static func owning(note: TextNote, fileManager: FileManager = .default) -> Self {
        Self(directoryURL: note.fileURL.deletingLastPathComponent(), fileManager: fileManager)
    }

    public func load() throws -> [TextNote] {
        try loadDetailed().notes
    }

    public func loadDetailed() throws -> TextNoteLoadResult {
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return TextNoteLoadResult(notes: [], unreadableFiles: [])
        }
        let urls = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var notes: [TextNote] = []
        var unreadableFiles: [String] = []
        for url in urls where url.pathExtension.caseInsensitiveCompare("txt") == .orderedSame {
            do {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .creationDateKey])
                guard values.isRegularFile == true else { continue }
                let data = try Data(contentsOf: url)
                guard let text = String(data: data, encoding: .utf8) else {
                    unreadableFiles.append(url.lastPathComponent)
                    continue
                }
                let modified = values.contentModificationDate ?? .distantPast
                notes.append(TextNote(fileURL: url,
                                      title: url.deletingPathExtension().lastPathComponent,
                                      body: text,
                                      createdAt: values.creationDate ?? modified,
                                      updatedAt: modified))
            } catch {
                unreadableFiles.append(url.lastPathComponent)
            }
        }
        let sortedNotes = notes.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
        return TextNoteLoadResult(notes: sortedNotes, unreadableFiles: unreadableFiles.sorted())
    }

    @discardableResult
    public func create(title: String = "", body: String = "") throws -> TextNote {
        try ensureDirectory()
        let cleanedTitle = ItemTitle.clean(title)
        let url = availableURL(for: cleanedTitle)
        let storedTitle = url.deletingPathExtension().lastPathComponent
        try Data(body.utf8).write(to: url, options: .atomic)
        let now = Date.now
        return TextNote(fileURL: url, title: storedTitle, body: body, createdAt: now, updatedAt: now)
    }

    @discardableResult
    public func update(_ note: TextNote, title: String, body: String) throws -> TextNote {
        try ensureNoteIsInFolder(note)
        try ensureDirectory()
        let cleanedTitle = ItemTitle.clean(title)
        let destination = availableURL(for: cleanedTitle, allowing: note.fileURL)
        let storedTitle = destination.deletingPathExtension().lastPathComponent

        // Write the new complete file before removing an old filename. If the
        // write fails, the existing note remains intact.
        try Data(body.utf8).write(to: destination, options: .atomic)
        if destination != note.fileURL, fileManager.fileExists(atPath: note.fileURL.path) {
            try fileManager.removeItem(at: note.fileURL)
        }

        note.fileURL = destination
        note.title = storedTitle
        note.body = body
        note.updatedAt = .now
        return note
    }

    public func delete(_ note: TextNote) throws {
        try ensureNoteIsInFolder(note)
        guard fileManager.fileExists(atPath: note.fileURL.path) else { return }
        try fileManager.removeItem(at: note.fileURL)
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func ensureNoteIsInFolder(_ note: TextNote) throws {
        guard note.fileURL.deletingLastPathComponent().standardizedFileURL == directoryURL else {
            throw TextNoteStoreError.noteOutsideFolder
        }
    }

    private func availableURL(for title: String, allowing currentURL: URL? = nil) -> URL {
        let base = Self.safeFilename(title)
        var candidate = directoryURL.appendingPathComponent(base).appendingPathExtension("txt")
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path), candidate != currentURL {
            candidate = directoryURL.appendingPathComponent("\(base) \(suffix)").appendingPathExtension("txt")
            suffix += 1
        }
        return candidate
    }

    private static func safeFilename(_ title: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\0")
            .union(.newlines)
            .union(.controlCharacters)
        let safe = title.components(separatedBy: forbidden).filter { !$0.isEmpty }.joined(separator: "-")
        return safe.isEmpty ? "New Note" : safe
    }
}

public struct TextNoteLoadResult {
    public let notes: [TextNote]
    public let unreadableFiles: [String]

    public init(notes: [TextNote], unreadableFiles: [String]) {
        self.notes = notes
        self.unreadableFiles = unreadableFiles
    }
}

public enum TextNoteStoreError: LocalizedError {
    case noteOutsideFolder
    case unreadableNote(String)

    public var errorDescription: String? {
        switch self {
        case .noteOutsideFolder:
            "This note is not inside the selected Notes Folder."
        case .unreadableNote(let filename):
            "Could not read “\(filename)”. Check that the file is a readable UTF-8 text file."
        }
    }
}
