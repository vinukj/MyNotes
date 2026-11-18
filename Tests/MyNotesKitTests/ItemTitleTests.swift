import Foundation
import Testing
@testable import MyNotesKit

@Test("Clean titles", arguments: [
    ("Buy milk", "Buy milk"),
    ("  Buy   milk \n", "Buy milk"),
    ("", "New Note"),
    ("   ", "New Note"),
])
func cleans(_ input: String, expected: String) {
    #expect(ItemTitle.clean(input) == expected)
}

@Test("Search checks title and body without case sensitivity")
func searchesTitleAndBody() {
    #expect(NoteSearch.matches(title: "Swift Notes", body: "A local notebook", query: "swift"))
    #expect(NoteSearch.matches(title: "Swift Notes", body: "A local notebook", query: "NOTEBOOK"))
    #expect(NoteSearch.matches(title: "Swift Notes", body: "A local notebook", query: "  "))
    #expect(!NoteSearch.matches(title: "Swift Notes", body: "A local notebook", query: "cloud"))
}

@Test("Search treats URL text literally across a larger note collection")
func searchesURLWithoutOpeningIt() {
    let entries = (0..<2_000).map { index in
        NoteSearch.Entry(id: UUID(), title: "Note \(index)", body: index == 1_999 ? "Visit http://40.81.228.103/" : "Ordinary note body")
    }

    let matches = NoteSearch.matchingIDs(in: entries, query: "http://40.81.228.103/")
    #expect(matches == [entries[1_999].id])
    #expect(NoteSearch.matchingIDs(in: entries, query: "Note", cancellationCheck: { true }).isEmpty)
}
