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
