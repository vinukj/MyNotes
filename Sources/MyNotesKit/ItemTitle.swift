import Foundation

/// Small note-search rule that can be tested without launching the app.
public enum NoteSearch {
    public static func matches(title: String, body: String, query: String) -> Bool {
        let phrase = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty else { return true }
        return title.localizedCaseInsensitiveContains(phrase)
            || body.localizedCaseInsensitiveContains(phrase)
    }
}

/// Kept as a separate pure helper for tests and future import flows.
public enum ItemTitle {
    /// Trims spaces and line breaks, collapses inner runs of spaces, and
    /// falls back to "New Note" for an empty title.
    public static func clean(_ text: String) -> String {
        let words = text.split(whereSeparator: \.isWhitespace)
        return words.isEmpty ? "New Note" : words.joined(separator: " ")
    }
}
