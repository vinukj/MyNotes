import Foundation
import Testing
@testable import MyNotesKit

@Test("Text note store loads only top-level text files and preserves their contents")
func loadsTopLevelTextNotes() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    try Data("A note body\nwith a second line".utf8)
        .write(to: directory.appendingPathComponent("Old note.txt"))
    try Data("Ignore me".utf8)
        .write(to: directory.appendingPathComponent("Clipboard.store"))
    let nested = directory.appendingPathComponent("Nested", isDirectory: true)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    try Data("Nested note".utf8).write(to: nested.appendingPathComponent("Hidden.txt"))

    let notes = try TextNoteStore(directoryURL: directory).load()

    #expect(notes.count == 1)
    #expect(notes.first?.title == "Old note")
    #expect(notes.first?.body == "A note body\nwith a second line")
}

@Test("An unreadable text file does not hide other notes")
func unreadableTextFileDoesNotHideReadableNotes() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    try Data("Readable note".utf8)
        .write(to: directory.appendingPathComponent("Readable.txt"))
    try Data([0xFF, 0x00, 0xFE])
        .write(to: directory.appendingPathComponent("Not actually text.txt"))

    let result = try TextNoteStore(directoryURL: directory).loadDetailed()

    #expect(result.notes.count == 1)
    #expect(result.notes.first?.title == "Readable")
    #expect(result.notes.first?.body == "Readable note")
    #expect(result.unreadableFiles == ["Not actually text.txt"])
}

@Test("Text note store creates plain text notes and reloads them")
func createsAndReloadsTextNote() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = TextNoteStore(directoryURL: directory)

    let note = try store.create(title: "Weekend trip", body: "Book the train")
    let reloaded = try store.load()

    #expect(note.fileURL.pathExtension == "txt")
    #expect(try String(contentsOf: note.fileURL, encoding: .utf8) == "Book the train")
    #expect(reloaded.count == 1)
    #expect(reloaded.first?.title == "Weekend trip")
    #expect(reloaded.first?.body == "Book the train")
}

@Test("Text note store renames a note when its title changes")
func updatesAndRenamesTextNote() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = TextNoteStore(directoryURL: directory)
    let original = try store.create(title: "New Note", body: "First draft")
    let originalURL = original.fileURL

    let updated = try store.update(original, title: "A better title", body: "Revised text")

    #expect(updated.title == "A better title")
    #expect(updated.body == "Revised text")
    #expect(!FileManager.default.fileExists(atPath: originalURL.path))
    #expect(try String(contentsOf: updated.fileURL, encoding: .utf8) == "Revised text")
}

@Test("A delayed save after switching folders still writes to the note's original folder")
func delayedSaveUsesOwningFolderAfterFolderSwitch() throws {
    let originalDirectory = try makeTemporaryDirectory()
    let selectedDirectory = try makeTemporaryDirectory()
    defer {
        try? FileManager.default.removeItem(at: originalDirectory)
        try? FileManager.default.removeItem(at: selectedDirectory)
    }

    let originalStore = TextNoteStore(directoryURL: originalDirectory)
    let selectedStore = TextNoteStore(directoryURL: selectedDirectory)
    let note = try originalStore.create(title: "Draft", body: "Before folder switch")

    note.title = "Saved Draft"
    note.body = "Typed while the editor was closing"
    try TextNoteStore.owning(note: note).update(note, title: note.title, body: note.body)

    #expect(try String(contentsOf: originalDirectory.appendingPathComponent("Saved Draft.txt"), encoding: .utf8)
            == "Typed while the editor was closing")
    #expect(try selectedStore.load().isEmpty)
}

@Test("Text note store deletes only the selected note")
func deletesOnlySelectedTextNote() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = TextNoteStore(directoryURL: directory)
    let selected = try store.create(title: "Delete me", body: "")
    let retained = try store.create(title: "Keep me", body: "Still here")

    try store.delete(selected)

    #expect(!FileManager.default.fileExists(atPath: selected.fileURL.path))
    #expect(FileManager.default.fileExists(atPath: retained.fileURL.path))
    #expect(try store.load().map(\.title) == ["Keep me"])
}

@Test("A note can be deleted through its owning folder after folder selection changes")
func deletesNoteThroughOwningFolderAfterFolderSwitch() throws {
    let originalDirectory = try makeTemporaryDirectory()
    let selectedDirectory = try makeTemporaryDirectory()
    defer {
        try? FileManager.default.removeItem(at: originalDirectory)
        try? FileManager.default.removeItem(at: selectedDirectory)
    }

    let originalStore = TextNoteStore(directoryURL: originalDirectory)
    let selectedStore = TextNoteStore(directoryURL: selectedDirectory)
    let note = try originalStore.create(title: "Delete from original", body: "")

    try TextNoteStore.owning(note: note).delete(note)

    #expect(!FileManager.default.fileExists(atPath: note.fileURL.path))
    #expect(try selectedStore.load().isEmpty)
}

private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("MyNotes-TextNoteStoreTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
