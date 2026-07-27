import Foundation
import SwiftData
import Synchronization
import Testing
@testable import Burrito

@MainActor
private final class CaptureSpyingStub: AudioCapturing {
    var activity = AudioActivity.silent
    var liveTranscript = ""
    var hasMeaningfulAudio = true
    private(set) var starts = 0
    private(set) var stops = 0
    private(set) var languageIdentifiers: [String] = []
    var startResult: Result<Void, BurritoError> = .success(())
    var stopResult: Result<Void, BurritoError> = .success(())

    func start(
        files: RecordingFiles,
        includesMicrophone: Bool,
        languageIdentifier: String
    ) async -> Result<Void, BurritoError> {
        starts += 1
        languageIdentifiers.append(languageIdentifier)
        return startResult
    }

    func stop() async -> Result<Void, BurritoError> {
        stops += 1
        return stopResult
    }
}

private struct TranscriberStub: Transcribing {
    var languageResult: Result<Void, BurritoError> = .success(())
    var installationResult: Result<Void, BurritoError> = .success(())

    func verifyLanguage(_ identifier: String) async -> Result<Void, BurritoError> {
        languageResult
    }

    func installLanguageAsset(_ identifier: String) async -> Result<Void, BurritoError> {
        installationResult
    }

    func transcribe(
        fileURL: URL,
        source: AudioSource,
        languageIdentifier: String
    ) async -> Result<[TranscriptSegment], BurritoError> {
        .success([
            TranscriptSegment(source: source, startTime: 0, duration: 1, text: "\(source.rawValue) text"),
        ])
    }
}

private struct GeneratorStub: NoteGenerating {
    var availabilityResult: Result<Void, BurritoError> = .success(())
    var suggestedTitle = "Generated title"

    func availability(languageIdentifier: String) async -> Result<Void, BurritoError> {
        availabilityResult
    }

    func generate(
        segments: [TranscriptSegment],
        template: TemplateSnapshot,
        languageIdentifier: String
    ) async -> Result<GeneratedNote, BurritoError> {
        .success(GeneratedNote(title: "Generated", markdown: "# Generated"))
    }

    func suggestTitle(
        segments: [TranscriptSegment],
        currentTitle: String,
        languageIdentifier: String
    ) async -> Result<String, BurritoError> {
        .success(segments.count > 1 ? suggestedTitle : currentTitle)
    }
}

private final class FileStoreSpy: RecordingFileStore, Sendable {
    let removeCount = Mutex(0)
    let root: URL

    init(root: URL) {
        self.root = root
    }

    func createSession(id: UUID, includesMicrophone: Bool) -> Result<RecordingFiles, BurritoError> {
        .success(
            RecordingFiles(
                sessionID: id,
                systemAudioURL: root.appending(path: "system.m4a"),
                microphoneAudioURL: includesMicrophone ? root.appending(path: "microphone.m4a") : nil
            )
        )
    }

    func relativePath(for url: URL) -> String { url.lastPathComponent }
    func url(forRelativePath path: String) -> URL { root.appending(path: path) }

    func removeAudio(for files: RecordingFiles) -> Result<Void, BurritoError> {
        removeCount.withLock { $0 += 1 }
        return .success(())
    }
}

@MainActor
@Suite("Recording coordinator")
struct CoordinatorTests {
    @Test("Repeated start is rejected and a successful stop produces a ready note")
    func startStopProtection() async throws {
        // Given
        let context = try makeContext()
        let capture = CaptureSpyingStub()
        let fileStore = FileStoreSpy(root: FileManager.default.temporaryDirectory)
        let coordinator = AppCoordinator(
            capture: capture,
            transcriber: TranscriberStub(),
            generator: GeneratorStub(),
            fileStore: fileStore,
            requestSpeechAuthorization: { true }
        )
        let options = RecordingOptions(
            template: TemplateSnapshot(name: "Summary", symbol: "text.alignleft", instructions: "Summarize."),
            languageIdentifier: "en-US",
            includesMicrophone: true,
            retainsAudio: false
        )

        // When
        await coordinator.start(options: options, context: context)
        await coordinator.start(options: options, context: context)

        // Then
        #expect(coordinator.captureState.isRecording)
        #expect(coordinator.lastError == .recordingAlreadyInProgress)
        #expect(capture.starts == 1)

        // When
        await coordinator.stop(context: context)
        let notes = try context.fetch(FetchDescriptor<Note>())
        let note = try #require(notes.first)

        // Then
        #expect(capture.stops == 1)
        #expect(note.lifecycle == .ready)
        #expect(note.title == "Generated")
        #expect(note.transcriptSegments.count == 2)
        #expect(fileStore.removeCount.withLock { $0 } == 1)
    }

    @Test("Continuing a note appends transcript and duration without creating another note")
    func appendsRecordingToExistingNote() async throws {
        let context = try makeContext()
        let existingSegment = TranscriptSegment(
            source: .system,
            startTime: 0,
            duration: 4,
            text: "Existing text"
        )
        let note = Note(
            lifecycle: .ready,
            title: "Existing note",
            markdownBody: "# Existing notes",
            transcriptSegments: [existingSegment],
            languageIdentifier: "en-US",
            template: TemplateSnapshot(
                name: "Summary",
                symbol: "doc",
                instructions: "Summarize."
            ),
            retainsAudio: false
        )
        note.duration = 10
        context.insert(note)
        try context.save()
        let coordinator = AppCoordinator(
            capture: CaptureSpyingStub(),
            transcriber: TranscriberStub(),
            generator: GeneratorStub(),
            fileStore: FileStoreSpy(root: FileManager.default.temporaryDirectory),
            requestSpeechAuthorization: { true }
        )
        let options = RecordingOptions(
            template: note.templateSnapshot,
            languageIdentifier: note.languageIdentifier,
            includesMicrophone: false,
            retainsAudio: false
        )

        await coordinator.start(
            options: options,
            destination: .appendToNote(id: note.id),
            context: context
        )
        #expect(coordinator.activeNoteID == note.id)
        await coordinator.stop(context: context)

        let notes = try context.fetch(FetchDescriptor<Note>())
        #expect(notes.count == 1)
        #expect(note.transcriptSegments.map(\.text) == ["Existing text", "System text"])
        #expect(note.transcriptSegments.last?.startTime == 4)
        #expect(note.duration >= 10)
        #expect(note.title == "Generated title")
        #expect(note.markdownBody.hasPrefix("# Existing notes"))
        #expect(note.markdownBody.contains("# Generated"))
        #expect(note.lifecycle == .ready)
    }

    @Test("Recording publishes live transcript and audio activity")
    func liveRecordingFeedback() async throws {
        let context = try makeContext()
        let capture = CaptureSpyingStub()
        capture.activity = AudioActivity(system: 0.72, microphone: 0.31)
        capture.liveTranscript = "A live sentence"
        let coordinator = AppCoordinator(
            capture: capture,
            transcriber: TranscriberStub(),
            generator: GeneratorStub(),
            fileStore: FileStoreSpy(root: FileManager.default.temporaryDirectory),
            requestSpeechAuthorization: { true }
        )
        let options = RecordingOptions(
            template: TemplateSnapshot(
                name: "Summary",
                symbol: "doc",
                instructions: "Summarize."
            ),
            languageIdentifier: "en-US",
            includesMicrophone: true,
            retainsAudio: false
        )

        await coordinator.start(options: options, context: context)
        try await Task.sleep(for: .milliseconds(120))

        #expect(coordinator.activity == capture.activity)
        #expect(coordinator.liveTranscript == "A live sentence")
        #expect(capture.languageIdentifiers == ["en-US"])

        await coordinator.stop(context: context)
        #expect(coordinator.activity == .silent)
        #expect(coordinator.liveTranscript.isEmpty)
    }

    @Test("Silent recordings do not create transcripts or generated notes")
    func silentRecordingDoesNotGenerateNotes() async throws {
        let context = try makeContext()
        let capture = CaptureSpyingStub()
        capture.hasMeaningfulAudio = false
        let fileStore = FileStoreSpy(root: FileManager.default.temporaryDirectory)
        let coordinator = AppCoordinator(
            capture: capture,
            transcriber: TranscriberStub(),
            generator: GeneratorStub(),
            fileStore: fileStore,
            requestSpeechAuthorization: { true }
        )
        let options = RecordingOptions(
            template: TemplateSnapshot(
                name: "Summary",
                symbol: "doc",
                instructions: "Summarize."
            ),
            languageIdentifier: "en-US",
            includesMicrophone: false,
            retainsAudio: false
        )

        await coordinator.start(options: options, context: context)
        await coordinator.stop(context: context)

        let note = try #require(context.fetch(FetchDescriptor<Note>()).first)
        #expect(note.lifecycle == .ready)
        #expect(note.transcriptSegments.isEmpty)
        #expect(note.markdownBody.isEmpty)
        #expect(note.title == "New Recording")
        #expect(fileStore.removeCount.withLock { $0 } == 1)
    }

    @Test("Language failure prevents recording and creates no note")
    func languageFailure() async throws {
        // Given
        let context = try makeContext()
        let capture = CaptureSpyingStub()
        let coordinator = AppCoordinator(
            capture: capture,
            transcriber: TranscriberStub(
                languageResult: .failure(.languageAssetMissing(identifier: "en-US"))
            ),
            generator: GeneratorStub(),
            fileStore: FileStoreSpy(root: FileManager.default.temporaryDirectory),
            requestSpeechAuthorization: { true }
        )
        let options = RecordingOptions(
            template: TemplateSnapshot(name: "Summary", symbol: "doc", instructions: "Summarize."),
            languageIdentifier: "en-US",
            includesMicrophone: false,
            retainsAudio: false
        )

        // When
        await coordinator.start(options: options, context: context)

        // Then
        #expect(capture.starts == 0)
        #expect(coordinator.lastError == .languageAssetMissing(identifier: "en-US"))
        #expect(try context.fetch(FetchDescriptor<Note>()).isEmpty)
    }

    @Test("Installing a missing language asset clears the recoverable error")
    func languageAssetInstallation() async throws {
        let context = try makeContext()
        let coordinator = AppCoordinator(
            capture: CaptureSpyingStub(),
            transcriber: TranscriberStub(
                languageResult: .failure(.languageAssetMissing(identifier: "en-US")),
                installationResult: .success(())
            ),
            generator: GeneratorStub(),
            fileStore: FileStoreSpy(root: FileManager.default.temporaryDirectory),
            requestSpeechAuthorization: { true }
        )
        let options = RecordingOptions(
            template: TemplateSnapshot(name: "Summary", symbol: "doc", instructions: "Summarize."),
            languageIdentifier: "en-US",
            includesMicrophone: false,
            retainsAudio: false
        )

        await coordinator.start(options: options, context: context)
        await coordinator.installMissingLanguageAsset()

        #expect(coordinator.lastError == nil)
        #expect(coordinator.isInstallingLanguageAsset == false)
    }

    @Test("Interrupted recording becomes recoverable on relaunch")
    func interruptionRecovery() throws {
        // Given
        let context = try makeContext()
        let note = Note(
            lifecycle: .recording,
            languageIdentifier: "en-US",
            template: TemplateSnapshot(name: "Summary", symbol: "doc", instructions: "Summarize."),
            retainsAudio: false
        )
        context.insert(note)
        try context.save()
        let coordinator = AppCoordinator(
            capture: CaptureSpyingStub(),
            transcriber: TranscriberStub(),
            generator: GeneratorStub(),
            fileStore: FileStoreSpy(root: FileManager.default.temporaryDirectory),
            requestSpeechAuthorization: { true }
        )

        // When
        coordinator.recoverInterruptedNotes(context: context)

        // Then
        #expect(note.lifecycle == .recoverable)
        #expect(note.lastErrorMessage?.contains("preserved") == true)
    }

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Note.self,
            Folder.self,
            NoteTemplate.self,
            configurations: configuration
        )
        return ModelContext(container)
    }
}
