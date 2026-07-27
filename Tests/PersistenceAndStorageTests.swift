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
}

@Suite("Recording storage")
struct RecordingStorageTests {
    @Test("Successful cleanup removes both tracks")
    func removesAudio() throws {
        // Given
        let root = FileManager.default.temporaryDirectory
            .appending(path: "BurritoTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LocalRecordingFileStore(root: root)
        let files = try store.createSession(id: UUID(), includesMicrophone: true).get()
        try Data("system".utf8).write(to: files.systemAudioURL)
        let microphoneURL = try #require(files.microphoneAudioURL)
        try Data("microphone".utf8).write(to: microphoneURL)

        // When
        try store.removeAudio(for: files).get()

        // Then
        #expect(!FileManager.default.fileExists(atPath: files.systemAudioURL.path()))
        #expect(!FileManager.default.fileExists(atPath: microphoneURL.path()))
    }
}
