import Foundation
import SwiftData
import Testing
@testable import Burrito

@MainActor
@Suite("Persistence")
struct PersistenceTests {
    enum PriorInstructionVersion: CaseIterable, Sendable {
        case previous
        case expanded

        func instructions(for template: BuiltInTemplate) -> String {
            switch self {
            case .previous: template.previousInstructions
            case .expanded: template.expandedInstructions
            }
        }
    }

    @Test("A versioned archive round-trips notes, transcripts, folders, and templates")
    func archiveRoundTrip() throws {
        let folder = Folder(
            id: UUID(uuidString: "35DD3525-1105-496B-AB20-0910859B365D") ?? UUID(),
            name: "Research",
            order: 2
        )
        let template = NoteTemplate(
            id: UUID(uuidString: "67BF505E-958E-43D4-89AD-0FD62D729F3D") ?? UUID(),
            name: "Customer interview",
            symbol: "person.2",
            instructions: "Capture objections.",
            createdAt: Date(timeIntervalSinceReferenceDate: 80)
        )
        let note = Note(
            id: UUID(uuidString: "FFB42F83-817F-462A-B302-D4AA3BE25626") ?? UUID(),
            lifecycle: .ready,
            title: "Pricing interview",
            markdownBody: "## Decision\n\nKeep the free plan.",
            userNotes: "- Follow up with Sam",
            transcriptSegments: [
                TranscriptSegment(
                    source: .microphone,
                    startTime: 12,
                    duration: 3,
                    text: "The free plan matters.",
                    speakerName: "Sam"
                ),
            ],
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            languageIdentifier: "en-US",
            template: template.snapshot,
            recordingMode: .meeting,
            retainsAudio: true
        )
        note.folder = folder
        note.isFavorite = true
        note.updatedAt = Date(timeIntervalSinceReferenceDate: 200)
        note.duration = 95

        let archive = BurritoArchive.capture(
            notes: [note],
            folders: [folder],
            templates: [template],
            exportedAt: Date(timeIntervalSinceReferenceDate: 300)
        )
        let decoded = try BurritoArchive.decode(archive.encoded())

        #expect(decoded.version == 1)
        #expect(decoded.folders.first?.name == "Research")
        #expect(decoded.templates.first?.instructions == "Capture objections.")
        #expect(decoded.notes.first?.folderID == folder.id)
        #expect(decoded.notes.first?.transcriptSegments == note.transcriptSegments)
        #expect(decoded.notes.first?.markdownBody == note.markdownBody)
        #expect(decoded.notes.first?.isFavorite == true)
    }

    @Test("Restoring the same archive twice preserves local data and skips duplicates")
    func archiveRestoreIsDuplicateSafe() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Note.self,
            Folder.self,
            NoteTemplate.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let folder = Folder(name: "Imported")
        let template = NoteTemplate(
            name: "Interview",
            symbol: "person.2",
            instructions: "Capture themes."
        )
        let note = Note(
            lifecycle: .ready,
            title: "Original title",
            markdownBody: "## Summary\n\nImported.",
            languageIdentifier: "en-US",
            template: template.snapshot,
            retainsAudio: false
        )
        note.folder = folder
        let archive = BurritoArchive.capture(
            notes: [note],
            folders: [folder],
            templates: [template]
        )

        let first = try archive.restore(into: context)
        let imported = try #require(context.fetch(FetchDescriptor<Note>()).first)
        imported.title = "Locally renamed"
        try context.save()
        let second = try archive.restore(into: context)

        #expect(first == ArchiveRestoreReport(notesInserted: 1, foldersInserted: 1, templatesInserted: 1, duplicatesSkipped: 0))
        #expect(second.duplicatesSkipped == 3)
        #expect(try context.fetch(FetchDescriptor<Note>()).count == 1)
        #expect(imported.title == "Locally renamed")
        #expect(imported.folder?.name == "Imported")
    }

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

    @Test(
        "Seed data upgrades every recognized prior built-in prompt",
        arguments: BuiltInTemplate.allCases,
        PriorInstructionVersion.allCases
    )
    func upgradesPreviousExpandedBuiltInPrompts(
        template: BuiltInTemplate,
        version: PriorInstructionVersion
    ) throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Note.self,
            Folder.self,
            NoteTemplate.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let stored = NoteTemplate(
            builtInID: template.rawValue,
            name: template.name,
            symbol: template.symbol,
            instructions: version.instructions(for: template)
        )
        context.insert(stored)
        try context.save()

        try SeedData.insertBuiltInTemplatesIfNeeded(context: context)

        #expect(stored.instructions == template.instructions)
    }
}

@Suite("Recording storage")
struct RecordingStorageTests {
    @MainActor
    @Test("Invalid backup audio is rejected before recording directories are created")
    func invalidBackupAudioLeavesNoRecordingDirectories() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: "BurritoInvalidAudioTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let sourceRoot = temporaryRoot.appending(path: "Source", directoryHint: .isDirectory)
        let restoredRoot = temporaryRoot.appending(path: "Restored", directoryHint: .isDirectory)
        let backup = temporaryRoot.appending(path: "Backup", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let sourceStore = LocalRecordingFileStore(root: sourceRoot)
        let note = Note(
            lifecycle: .ready,
            title: "Missing audio",
            markdownBody: "Keep the note safe.",
            languageIdentifier: "en-US",
            template: TemplateSnapshot(name: "Summary", symbol: "doc", instructions: "Summarize."),
            retainsAudio: true
        )
        let files = try sourceStore.createSession(id: note.id, mode: .listenAlong).get()
        let systemURL = try #require(files.systemAudioURL)
        try Data("system".utf8).write(to: systemURL)
        note.systemAudioRelativePath = sourceStore.relativePath(for: systemURL)
        _ = try BurritoArchivePackage.export(
            notes: [note],
            folders: [],
            templates: [],
            recordingStore: sourceStore,
            to: backup
        )
        try FileManager.default.removeItem(
            at: backup.appending(path: "Audio/\(note.id.uuidString)/system.m4a")
        )

        var rejected = false
        do {
            _ = try BurritoArchivePackage.restore(
                from: backup,
                into: try inMemoryModelContext(),
                recordingStore: LocalRecordingFileStore(root: restoredRoot)
            )
        } catch {
            rejected = true
        }

        #expect(rejected)
        #expect(!FileManager.default.fileExists(atPath: restoredRoot.path()))
    }

    @Test("Same-titled notes with matching UUID prefixes export to distinct Markdown files")
    func exportMarkdownFilenamesAreCollisionFree() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: "BurritoCollisionTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let destination = temporaryRoot.appending(path: "Backup", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let first = Note(
            id: UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000001") ?? UUID(),
            lifecycle: .ready,
            title: "Weekly review",
            markdownBody: "First note",
            languageIdentifier: "en-US",
            template: TemplateSnapshot(name: "Summary", symbol: "doc", instructions: "Summarize."),
            retainsAudio: false
        )
        let second = Note(
            id: UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000002") ?? UUID(),
            lifecycle: .ready,
            title: "Weekly review",
            markdownBody: "Second note",
            languageIdentifier: "en-US",
            template: TemplateSnapshot(name: "Summary", symbol: "doc", instructions: "Summarize."),
            retainsAudio: false
        )

        let report = try BurritoArchivePackage.export(
            notes: [first, second],
            folders: [],
            templates: [],
            recordingStore: LocalRecordingFileStore(
                root: temporaryRoot.appending(path: "Recordings", directoryHint: .isDirectory)
            ),
            to: destination
        )
        let contents = try report.markdownFiles.map {
            try String(contentsOf: $0, encoding: .utf8)
        }

        #expect(report.markdownFiles.count == 2)
        #expect(Set(report.markdownFiles.map(\.lastPathComponent)).count == 2)
        #expect(contents.contains { $0.contains("First note") })
        #expect(contents.contains { $0.contains("Second note") })
    }

    @Test("Mismatched export note records are rejected without creating a backup")
    func mismatchedExportInputIsRejected() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: "BurritoMismatchedExportTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let destination = temporaryRoot.appending(path: "Backup", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let first = Note(
            lifecycle: .ready,
            title: "First",
            markdownBody: "First note",
            languageIdentifier: "en-US",
            template: TemplateSnapshot(name: "Summary", symbol: "doc", instructions: "Summarize."),
            retainsAudio: false
        )
        let second = Note(
            lifecycle: .ready,
            title: "Second",
            markdownBody: "Second note",
            languageIdentifier: "en-US",
            template: TemplateSnapshot(name: "Summary", symbol: "doc", instructions: "Summarize."),
            retainsAudio: false
        )
        var input = BurritoArchivePackage.prepareExport(
            notes: [first, second],
            folders: [],
            templates: [],
            recordingStore: LocalRecordingFileStore(
                root: temporaryRoot.appending(path: "Recordings", directoryHint: .isDirectory)
            )
        )
        input.archive.notes.swapAt(0, 1)

        #expect(throws: BurritoArchiveError.self) {
            try BurritoArchivePackage.export(input, to: destination)
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path()))
    }

    @MainActor
    @Test("A library package restores retained audio without overwriting duplicates")
    func restoresCompleteLibraryPackage() async throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: "BurritoRestoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let sourceRoot = temporaryRoot.appending(path: "Source", directoryHint: .isDirectory)
        let restoredRoot = temporaryRoot.appending(path: "Restored", directoryHint: .isDirectory)
        let backup = temporaryRoot.appending(path: "Backup", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let sourceStore = LocalRecordingFileStore(root: sourceRoot)
        let note = Note(
            lifecycle: .ready,
            title: "Audio restore",
            markdownBody: "Complete.",
            languageIdentifier: "en-US",
            template: TemplateSnapshot(name: "Summary", symbol: "doc", instructions: "Summarize."),
            recordingMode: .meeting,
            retainsAudio: true
        )
        let sourceFiles = try sourceStore.createSession(id: note.id, mode: .meeting).get()
        let sourceSystemURL = try #require(sourceFiles.systemAudioURL)
        let sourceMicrophoneURL = try #require(sourceFiles.microphoneAudioURL)
        try Data("system".utf8).write(to: sourceSystemURL)
        try Data("microphone".utf8).write(to: sourceMicrophoneURL)
        note.systemAudioRelativePath = sourceStore.relativePath(for: sourceSystemURL)
        note.microphoneAudioRelativePath = sourceStore.relativePath(for: sourceMicrophoneURL)
        _ = try BurritoArchivePackage.export(
            notes: [note],
            folders: [],
            templates: [],
            recordingStore: sourceStore,
            to: backup
        )

        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Note.self,
            Folder.self,
            NoteTemplate.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let restoredStore = LocalRecordingFileStore(root: restoredRoot)
        let first = try await BurritoArchivePackage.restore(
            from: backup,
            into: context,
            recordingStore: restoredStore
        )
        let restoredNote = try #require(context.fetch(FetchDescriptor<Note>()).first)
        let restoredSystemPath = try #require(restoredNote.systemAudioRelativePath)
        restoredNote.title = "Keep this local title"
        try context.save()
        let second = try await BurritoArchivePackage.restore(
            from: backup,
            into: context,
            recordingStore: restoredStore
        )

        #expect(first.notesInserted == 1)
        #expect(first.audioFilesRestored == 2)
        #expect(try Data(contentsOf: restoredStore.url(forRelativePath: restoredSystemPath)) == Data("system".utf8))
        #expect(second.notesInserted == 0)
        #expect(second.audioFilesRestored == 0)
        #expect(restoredNote.title == "Keep this local title")
    }

    @Test("A library package contains its archive, readable notes, and retained audio")
    func exportsCompleteLibraryPackage() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: "BurritoExportTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let recordingRoot = temporaryRoot.appending(path: "Recordings", directoryHint: .isDirectory)
        let destination = temporaryRoot.appending(path: "Backup", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let store = LocalRecordingFileStore(root: recordingRoot)
        let note = Note(
            lifecycle: .ready,
            title: "Planning / review",
            markdownBody: "## Decision\n\nShip the backup.",
            userNotes: "- Verify restore",
            transcriptSegments: [
                TranscriptSegment(
                    source: .microphone,
                    startTime: 1,
                    duration: 2,
                    text: "Let’s ship it.",
                    speakerName: "Ari"
                ),
            ],
            languageIdentifier: "en-US",
            template: TemplateSnapshot(name: "Summary", symbol: "doc", instructions: "Summarize."),
            recordingMode: .meeting,
            retainsAudio: true
        )
        let files = try store.createSession(id: note.id, mode: .meeting).get()
        let systemURL = try #require(files.systemAudioURL)
        let microphoneURL = try #require(files.microphoneAudioURL)
        try Data("system".utf8).write(to: systemURL)
        try Data("microphone".utf8).write(to: microphoneURL)
        note.systemAudioRelativePath = store.relativePath(for: systemURL)
        note.microphoneAudioRelativePath = store.relativePath(for: microphoneURL)

        let report = try BurritoArchivePackage.export(
            notes: [note],
            folders: [],
            templates: [],
            recordingStore: store,
            to: destination
        )
        let archive = try BurritoArchive.decode(
            Data(contentsOf: destination.appending(path: "burrito.json"))
        )
        let markdown = try String(
            contentsOf: try #require(report.markdownFiles.first),
            encoding: .utf8
        )

        #expect(report.notesExported == 1)
        #expect(report.audioFilesExported == 2)
        #expect(markdown.contains("Ship the backup."))
        #expect(markdown.contains("Ari: Let’s ship it."))
        #expect(archive.notes.first?.systemAudioArchivePath != nil)
        #expect(archive.notes.first?.microphoneAudioArchivePath != nil)
        #expect(
            FileManager.default.fileExists(
                atPath: destination.appending(path: "Audio/\(note.id.uuidString)/system.m4a").path()
            )
        )
    }

    @Test("Meeting recordings retain separate call and microphone tracks")
    func removesAudio() throws {
        // Given
        let root = FileManager.default.temporaryDirectory
            .appending(path: "BurritoTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LocalRecordingFileStore(root: root)
        let files = try store.createSession(id: UUID(), mode: .meeting).get()
        let systemURL = try #require(files.systemAudioURL)
        let microphoneURL = try #require(files.microphoneAudioURL)
        try Data("system".utf8).write(to: systemURL)
        try Data("microphone".utf8).write(to: microphoneURL)

        // When
        try store.removeAudio(for: files).get()

        // Then
        #expect(!FileManager.default.fileExists(atPath: systemURL.path()))
        #expect(!FileManager.default.fileExists(atPath: microphoneURL.path()))
    }
}

@MainActor
private func inMemoryModelContext() throws -> ModelContext {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: Note.self,
        Folder.self,
        NoteTemplate.self,
        configurations: configuration
    )
    return ModelContext(container)
}
