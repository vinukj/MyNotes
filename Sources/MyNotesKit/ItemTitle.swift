import Foundation

/// Small note-search rule that can be tested without launching the app.
public enum NoteSearch {
    public struct Entry: Sendable {
        public let id: UUID
        public let title: String
        public let body: String

        public init(id: UUID, title: String, body: String) {
            self.id = id
            self.title = title
            self.body = body
        }
    }

    public static func matches(title: String, body: String, query: String) -> Bool {
        let phrase = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty else { return true }
        return title.localizedCaseInsensitiveContains(phrase)
            || body.localizedCaseInsensitiveContains(phrase)
    }

    public static func matchingIDs(
        in entries: [Entry],
        query: String,
        cancellationCheck: @Sendable () -> Bool = { false }
    ) -> Set<UUID> {
        var matches = Set<UUID>()
        for (index, entry) in entries.enumerated() {
            if index.isMultiple(of: 32), cancellationCheck() { break }
            if Self.matches(title: entry.title, body: entry.body, query: query) {
                matches.insert(entry.id)
            }
        }
        return matches
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
