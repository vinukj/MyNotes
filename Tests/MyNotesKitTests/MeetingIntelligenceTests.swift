import Foundation
import Testing
@testable import MyNotesKit

@Test("Meeting note title combines agenda and local timestamp")
func meetingNoteTitleUsesAgendaAndTimestamp() {
    let metadata = MeetingMetadata(startedAt: Date(timeIntervalSince1970: 1_795_180_200), title: "  Launch planning  ")

    #expect(metadata.noteTitle.hasPrefix("Launch planning — "))
    #expect(!metadata.noteTitle.contains("Not specified"))
    #expect(metadata.noteTitle.range(of: #"\d{4}-\d{2}-\d{2} \d{2}-\d{2}$"#, options: .regularExpression) != nil)
    #expect(!metadata.noteTitle.contains(":"))
}

@Test("Transcript Markdown keeps agenda, timestamp, duration, and editable transcript text")
func transcriptMarkdownContainsMeetingContext() {
    let metadata = MeetingMetadata(startedAt: Date(timeIntervalSince1970: 1_795_180_200),
                                   durationSeconds: 125, title: "Launch planning")

    let markdown = MeetingMarkdownRenderer.renderTranscript(metadata: metadata,
                                                             transcript: "[00:00] Review release risks.")

    #expect(markdown.hasPrefix("# Launch planning — "))
    #expect(markdown.contains("**Agenda:** Launch planning"))
    #expect(markdown.contains("**Duration:** 2m 5s"))
    #expect(markdown.contains("## Transcript\n\n[00:00] Review release risks."))
}
