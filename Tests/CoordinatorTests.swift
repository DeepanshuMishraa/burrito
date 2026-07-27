import Foundation
import SwiftData
import Synchronization
import Testing
@testable import Burrito

@MainActor
private final class CaptureSpyingStub: AudioCapturing {
    var activity = AudioActivity.silent
    private(set) var starts = 0
    private(set) var stops = 0
    var startResult: Result<Void, BurritoError> = .success(())
    var stopResult: Result<Void, BurritoError> = .success(())

    func start(files: RecordingFiles, includesMicrophone: Bool) async -> Result<Void, BurritoError> {
        starts += 1
        return startResult
    }

    func stop() async -> Result<Void, BurritoError> {
        stops += 1
        return stopResult
    }
}

private struct TranscriberStub: Transcribing {
    var languageResult: Result<Void, BurritoError> = .success(())

    func verifyLanguage(_ identifier: String) async -> Result<Void, BurritoError> {
        languageResult
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
