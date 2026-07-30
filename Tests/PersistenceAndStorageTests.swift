import Foundation
import SwiftData
import Testing
@testable import Burrito

@MainActor
@Suite("Persistence")
struct PersistenceTests {
    @Test("Folders, favorites, Trash, and restore keep migration-safe defaults")
    func libraryOperations() throws {
        // Given
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Note.self,
            Folder.self,
            NoteTemplate.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let folder = Folder(name: "Lectures")
        let note = Note(
            languageIdentifier: "en-US",
            template: TemplateSnapshot(name: "Study Notes", symbol: "graduationcap", instructions: "Study."),
            retainsAudio: false
        )
        note.folder = folder
        note.isFavorite = true
        context.insert(folder)
        context.insert(note)
        try context.save()

        // When / Then
        #expect(note.folder?.name == "Lectures")
        #expect(note.isFavorite)
        #expect(note.deletedAt == nil)
        #expect(note.transcriptSegments.isEmpty)

        note.deletedAt = .now
        try context.save()
        #expect(note.deletedAt != nil)

        note.deletedAt = nil
        try context.save()
        #expect(note.deletedAt == nil)
    }

    @Test("Transcript edits mark generated notes as outdated")
    func transcriptRevisionSafety() {
        // Given
        let note = Note(
            languageIdentifier: "en-US",
            template: TemplateSnapshot(name: "Summary", symbol: "doc", instructions: "Summarize."),
            retainsAudio: false
        )
        note.generatedFromTranscriptRevision = note.transcriptRevision

        // When
        note.replaceTranscript(
            with: [TranscriptSegment(source: .system, startTime: 0, duration: 1, text: "Edited")],
            marksEdited: true
        )

        // Then
        #expect(note.notesMayBeOutdated)
    }

    @Test("Human notes persist independently from generated notes")
    func humanNotesRemainIndependent() {
        let note = Note(
            markdownBody: "## Enhanced notes\n\nGenerated summary.",
            userNotes: "- Ask about the launch date",
            languageIdentifier: "en-US",
            template: TemplateSnapshot(name: "Summary", symbol: "doc", instructions: "Summarize."),
            retainsAudio: false
        )

        note.markdownBody = "## Enhanced notes\n\nRegenerated summary."

        #expect(note.userNotes == "- Ask about the launch date")
        #expect(note.markdownBody == "## Enhanced notes\n\nRegenerated summary.")
        #expect(note.exportedMarkdown.contains("## Your notes"))
        #expect(note.exportedMarkdown.contains("- Ask about the launch date"))
        #expect(note.exportedMarkdown.contains("## Burrito notes"))
        #expect(note.exportedMarkdown.contains("Regenerated summary."))
    }

    @Test("Calendar event snapshots persist independently with recurring identity")
    func calendarEventSnapshotPersists() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Note.self,
            Folder.self,
            NoteTemplate.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let event = CalendarEventSnapshot(
            eventIdentifier: "event-42",
            title: "Product weekly",
            startDate: Date(timeIntervalSince1970: 1_800_000_000),
            endDate: Date(timeIntervalSince1970: 1_800_003_600),
            meetingURL: URL(string: "https://meet.google.com/abc-defg-hij"),
            attendeeNames: ["Ari", "Sam"],
            organizerName: "Ari",
            recurrenceIdentifier: "product-weekly",
            calendarName: "Work"
        )
        let note = Note(
            languageIdentifier: "en-US",
            template: TemplateSnapshot(name: "Meeting", symbol: "person.3", instructions: "Meet."),
            retainsAudio: false,
            calendarEvent: event
        )
        context.insert(note)
        try context.save()

        let stored = try #require(context.fetch(FetchDescriptor<Note>()).first)

        #expect(stored.calendarEvent == event)
        #expect(stored.calendarEvent?.relatedMeetingIdentifier == "product-weekly")
    }

    @Test("Seed data upgrades untouched legacy built-in prompts")
    func upgradesLegacyBuiltInPrompts() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Note.self,
            Folder.self,
            NoteTemplate.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let template = BuiltInTemplate.summary
        let stored = NoteTemplate(
            builtInID: template.rawValue,
            name: template.name,
            symbol: template.symbol,
            instructions: template.legacyInstructions
        )
        context.insert(stored)
        try context.save()

        try SeedData.insertBuiltInTemplatesIfNeeded(context: context)

        #expect(stored.instructions == template.instructions)
    }
}

@Suite("Recording storage")
struct RecordingStorageTests {
    @Test("Successful cleanup removes the selected audio source")
    func removesAudio() throws {
        // Given
        let root = FileManager.default.temporaryDirectory
            .appending(path: "BurritoTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LocalRecordingFileStore(root: root)
        let files = try store.createSession(id: UUID(), mode: .meeting).get()
        #expect(files.systemAudioURL == nil)
        let microphoneURL = try #require(files.microphoneAudioURL)
        try Data("microphone".utf8).write(to: microphoneURL)

        // When
        try store.removeAudio(for: files).get()

        // Then
        #expect(!FileManager.default.fileExists(atPath: microphoneURL.path()))
    }
}
