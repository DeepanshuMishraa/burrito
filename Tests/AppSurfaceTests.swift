import Foundation
import Testing
@testable import Burrito

@Suite("App surfaces")
struct AppSurfaceTests {
    @Test("Calendar meeting links skip non-web links before a web link")
    func calendarMeetingLinkSkipsNonWebLinks() {
        let location = "Dial tel:+15551234 or join https://meet.example.com/weekly"

        #expect(
            MeetingLink.first(
                explicitURL: nil,
                location: location,
                notes: nil
            )?.absoluteString == "https://meet.example.com/weekly"
        )
    }

    @MainActor
    @Test("Menu recordings use the persisted built-in template edits")
    func menuRecordingUsesPersistedTemplateEdits() {
        let edited = NoteTemplate(
            builtInID: BuiltInTemplate.summary.rawValue,
            name: "My Summary",
            symbol: "sparkles",
            instructions: "Use my edited structure."
        )

        let snapshot = RecordingTemplateResolver.snapshot(
            for: .listenAlong,
            defaultTemplateID: BuiltInTemplate.summary.rawValue,
            templates: [edited]
        )

        #expect(snapshot == edited.snapshot)
    }

    @MainActor
    @Test("Recording destinations remain queued until the main window consumes them")
    func recordingDestinationRemainsQueued() {
        let inbox = RecordingDestinationInbox()

        inbox.submit(.newNote)

        #expect(inbox.pending == .newNote)
        #expect(inbox.consume() == .newNote)
        #expect(inbox.pending == nil)
    }

    @MainActor
    @Test("Timeline excerpts show human notes when generated Markdown is empty")
    func timelineExcerptFallsBackToHumanNotes() {
        let note = Note(
            lifecycle: .ready,
            title: "Planning",
            userNotes: "## Remember\nCall Priya tomorrow.",
            languageIdentifier: "en-US",
            template: TemplateSnapshot(
                name: "Summary",
                symbol: "doc",
                instructions: "Summarize."
            ),
            retainsAudio: false
        )

        #expect(NoteExcerpt.text(for: note) == "Remember\nCall Priya tomorrow.")
    }
}
