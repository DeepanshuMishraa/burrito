import Foundation
import SwiftData
import Synchronization
import Testing
@testable import Burrito

@MainActor
private final class CaptureSpyingStub: AudioCapturing {
    var activity = AudioActivity.silent
    var hasMeaningfulAudio = true
    private(set) var starts = 0
    private(set) var stops = 0
    private(set) var languageIdentifiers: [String] = []
    private(set) var modes: [RecordingMode] = []
    var startResult: Result<Void, BurritoError> = .success(())
    var stopResult: Result<Void, BurritoError> = .success(())

    func start(
        files: RecordingFiles,
        mode: RecordingMode,
        languageIdentifier: String
    ) async -> Result<Void, BurritoError> {
        starts += 1
        languageIdentifiers.append(languageIdentifier)
        modes.append(mode)
        return startResult
    }

    func stop() async -> Result<Void, BurritoError> {
        stops += 1
        return stopResult
    }
}

@MainActor
private final class FeedbackSpy: AppFeedbackProviding {
    private(set) var events: [String] = []

    func recordingStarted() {
        events.append("recordingStarted")
    }

    func recordingStopped() {
        events.append("recordingStopped")
    }

    func noteReady(title: String) {
        events.append("noteReady:\(title)")
    }
}

private struct TranscriberStub: Transcribing {
    var languageResult: Result<Void, BurritoError> = .success(())
    var installationResult: Result<Void, BurritoError> = .success(())
    var needsSpeechAuthorization = true

    func requiresSpeechAuthorization(for identifier: String) -> Bool {
        needsSpeechAuthorization
    }

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
        .success(suggestedTitle)
    }
}

private final class RetryingTitleGeneratorStub: NoteGenerating, Sendable {
    let titleResponses: Mutex<[Result<String, BurritoError>]>
    let titleCallCount = Mutex(0)

    init(titleResponses: [Result<String, BurritoError>]) {
        self.titleResponses = Mutex(titleResponses)
    }

    func availability(languageIdentifier: String) async -> Result<Void, BurritoError> {
        .success(())
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
        titleCallCount.withLock { $0 += 1 }
        return titleResponses.withLock { responses in
            guard !responses.isEmpty else {
                return .failure(.generationFailed(details: "No title response remains."))
            }
            return responses.removeFirst()
        }
    }
}

private final class FileStoreSpy: RecordingFileStore, Sendable {
    let removeCount = Mutex(0)
    let root: URL

    init(root: URL) {
        self.root = root
    }

    func createSession(id: UUID, mode: RecordingMode) -> Result<RecordingFiles, BurritoError> {
        .success(
            RecordingFiles(
                sessionID: id,
                systemAudioURL: mode == .listenAlong ? root.appending(path: "system.m4a") : nil,
                microphoneAudioURL: mode == .meeting ? root.appending(path: "microphone.m4a") : nil
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
    @Test("Local transcription starts without requesting Apple Speech access")
    func localTranscriptionSkipsSpeechAuthorization() async throws {
        let context = try makeContext()
        let capture = CaptureSpyingStub()
        let authorizationRequests = Mutex(0)
        let coordinator = AppCoordinator(
            capture: capture,
            transcriber: TranscriberStub(needsSpeechAuthorization: false),
            generator: GeneratorStub(),
            fileStore: FileStoreSpy(root: FileManager.default.temporaryDirectory),
            requestSpeechAuthorization: {
                authorizationRequests.withLock { $0 += 1 }
                return false
            }
        )
        let options = RecordingOptions(
            template: TemplateSnapshot(
                name: "Summary",
                symbol: "text.alignleft",
                instructions: "Summarize."
            ),
            languageIdentifier: "en-US",
            mode: .meeting,
            retainsAudio: false
        )

        await coordinator.start(options: options, context: context)

        #expect(coordinator.captureState.isRecording)
        #expect(capture.starts == 1)
        #expect(authorizationRequests.withLock { $0 } == 0)
        await coordinator.stop(context: context)
    }

    @Test("Repeated start is rejected and a successful stop produces a ready note")
    func startStopProtection() async throws {
        // Given
        let context = try makeContext()
        let capture = CaptureSpyingStub()
        let fileStore = FileStoreSpy(root: FileManager.default.temporaryDirectory)
        let feedback = FeedbackSpy()
        let coordinator = AppCoordinator(
            capture: capture,
            transcriber: TranscriberStub(),
            generator: GeneratorStub(),
            fileStore: fileStore,
            feedback: feedback,
            requestSpeechAuthorization: { true }
        )
        let options = RecordingOptions(
            template: TemplateSnapshot(name: "Summary", symbol: "text.alignleft", instructions: "Summarize."),
            languageIdentifier: "en-US",
            mode: .meeting,
            retainsAudio: false
        )

        // When
        await coordinator.start(options: options, context: context)
        await coordinator.start(options: options, context: context)

        // Then
        #expect(coordinator.captureState.isRecording)
        #expect(coordinator.lastError == .recordingAlreadyInProgress)
        #expect(capture.starts == 1)
        #expect(feedback.events == ["recordingStarted"])

        // When
        await coordinator.stop(context: context)
        let notes = try context.fetch(FetchDescriptor<Note>())
        let note = try #require(notes.first)

        // Then
        #expect(capture.stops == 1)
        #expect(note.lifecycle == .ready)
        #expect(note.title == "Generated title")
        #expect(note.transcriptSegments.count == 1)
        #expect(fileStore.removeCount.withLock { $0 } == 1)
        #expect(
            feedback.events
                == ["recordingStarted", "recordingStopped", "noteReady:Generated title"]
        )
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
            recordingMode: .meeting,
            retainsAudio: false
        )
        note.duration = 10
        context.insert(note)
        try context.save()
        let capture = CaptureSpyingStub()
        let coordinator = AppCoordinator(
            capture: capture,
            transcriber: TranscriberStub(),
            generator: GeneratorStub(),
            fileStore: FileStoreSpy(root: FileManager.default.temporaryDirectory),
            requestSpeechAuthorization: { true }
        )
        let options = RecordingOptions(
            template: note.templateSnapshot,
            languageIdentifier: note.languageIdentifier,
            mode: .listenAlong,
            retainsAudio: false
        )

        await coordinator.start(
            options: options,
            destination: .appendToNote(id: note.id),
            context: context
        )
        #expect(coordinator.activeNoteID == note.id)
        #expect(capture.modes == [.meeting])
        await coordinator.stop(context: context)

        let notes = try context.fetch(FetchDescriptor<Note>())
        #expect(notes.count == 1)
        #expect(note.transcriptSegments.map(\.text) == ["Existing text", "Microphone text"])
        #expect(note.transcriptSegments.last?.startTime == 4)
        #expect(note.duration >= 10)
        #expect(note.title == "Generated title")
        #expect(note.markdownBody.hasPrefix("# Existing notes"))
        #expect(note.markdownBody.contains("# Generated"))
        #expect(note.lifecycle == .ready)
    }

    @Test("A failed parallel title pass retries after note generation")
    func retriesDynamicTitleAfterGeneration() async throws {
        let context = try makeContext()
        let note = Note(
            lifecycle: .ready,
            title: "Database Notes",
            markdownBody: "# Existing notes",
            transcriptSegments: [
                TranscriptSegment(
                    source: .system,
                    startTime: 0,
                    duration: 4,
                    text: "The database originally stored request metadata."
                ),
            ],
            languageIdentifier: "en-US",
            template: TemplateSnapshot(
                name: "Summary",
                symbol: "doc",
                instructions: "Summarize."
            ),
            retainsAudio: false
        )
        context.insert(note)
        try context.save()
        let generator = RetryingTitleGeneratorStub(titleResponses: [
            .failure(.generationFailed(details: "The model was busy.")),
            .success("Inference Runtime Architecture"),
        ])
        let coordinator = AppCoordinator(
            capture: CaptureSpyingStub(),
            transcriber: TranscriberStub(),
            generator: generator,
            fileStore: FileStoreSpy(root: FileManager.default.temporaryDirectory),
            requestSpeechAuthorization: { true }
        )

        await coordinator.start(
            options: RecordingOptions(
                template: note.templateSnapshot,
                languageIdentifier: note.languageIdentifier,
                mode: .listenAlong,
                retainsAudio: false
            ),
            destination: .appendToNote(id: note.id),
            context: context
        )
        await coordinator.stop(context: context)

        #expect(note.title == "Inference Runtime Architecture")
        #expect(generator.titleCallCount.withLock { $0 } == 2)
    }

    @Test("Recording publishes live audio activity")
    func liveRecordingFeedback() async throws {
        let context = try makeContext()
        let capture = CaptureSpyingStub()
        capture.activity = AudioActivity(system: 0.72, microphone: 0.31)
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
            mode: .meeting,
            retainsAudio: false
        )

        await coordinator.start(options: options, context: context)
        try await Task.sleep(for: .milliseconds(120))

        #expect(coordinator.activity == capture.activity)
        #expect(capture.languageIdentifiers == ["en-US"])

        await coordinator.stop(context: context)
        #expect(coordinator.activity == .silent)
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
            mode: .listenAlong,
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
            mode: .listenAlong,
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
            mode: .listenAlong,
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
