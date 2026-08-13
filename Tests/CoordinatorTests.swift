import Foundation
import SwiftData
import Synchronization
import Testing
@testable import Burrito

@MainActor
private final class CaptureSpyingStub: AudioCapturing {
    var activity = AudioActivity.silent
    var hasMeaningfulAudio = true
    var liveTranscript = LiveTranscriptSnapshot(
        availability: .unavailable(reason: "Live transcription is unavailable."),
        passages: []
    )
    private(set) var starts = 0
    private(set) var stops = 0
    private(set) var pauses = 0
    private(set) var resumes = 0
    private(set) var languageIdentifiers: [String] = []
    private(set) var modes: [RecordingMode] = []
    var startResult: Result<Void, BurritoError> = .success(())
    var stopResult: Result<Void, BurritoError> = .success(())
    var didStart: (() -> Void)?

    func start(
        files: RecordingFiles,
        mode: RecordingMode,
        languageIdentifier: String
    ) async -> Result<Void, BurritoError> {
        starts += 1
        languageIdentifiers.append(languageIdentifier)
        modes.append(mode)
        didStart?()
        return startResult
    }

    func stop() async -> Result<Void, BurritoError> {
        stops += 1
        return stopResult
    }

    func pause() async -> Result<Void, BurritoError> {
        pauses += 1
        return .success(())
    }

    func resume() async -> Result<Void, BurritoError> {
        resumes += 1
        return .success(())
    }
}

private struct SpeakerDiarizerFailureStub: SpeakerDiarizing {
    let error: BurritoError

    func assignSpeakers(
        audioURL: URL,
        to segments: [TranscriptSegment]
    ) async -> Result<[TranscriptSegment], BurritoError> {
        .failure(error)
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

@MainActor
private final class TestClock {
    private(set) var now = Date()

    func advance(by interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
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
        input: TranscriptionInput,
        languageIdentifier: String
    ) async -> Result<[TranscriptSegment], BurritoError> {
        let source: AudioSource = switch input {
        case .natural(_, let source), .importedMedia(_, let source): source
        case .systemCapture: .system
        }
        return .success([
            TranscriptSegment(source: source, startTime: 0, duration: 1, text: "\(source.rawValue) text"),
        ])
    }
}

private final class TranscriptionInputSpy: Transcribing, Sendable {
    let inputs = Mutex<[TranscriptionInput]>([])
    private let result: Result<[TranscriptSegment], BurritoError>?

    init(result: Result<[TranscriptSegment], BurritoError>? = nil) {
        self.result = result
    }

    func requiresSpeechAuthorization(for identifier: String) -> Bool { false }

    func verifyLanguage(_ identifier: String) async -> Result<Void, BurritoError> {
        .success(())
    }

    func installLanguageAsset(_ identifier: String) async -> Result<Void, BurritoError> {
        .success(())
    }

    func transcribe(
        input: TranscriptionInput,
        languageIdentifier: String
    ) async -> Result<[TranscriptSegment], BurritoError> {
        inputs.withLock { $0.append(input) }
        if let result { return result }
        let source: AudioSource = switch input {
        case .natural(_, let source), .importedMedia(_, let source): source
        case .systemCapture: .system
        }
        return .success([
            TranscriptSegment(source: source, startTime: 0, duration: 1, text: "Text"),
        ])
    }
}

private struct GeneratorStub: NoteGenerating {
    var availabilityResult: Result<Void, BurritoError> = .success(())
    var generationResult: Result<GeneratedNote, BurritoError> = .success(
        GeneratedNote(title: "Generated", markdown: "# Generated")
    )
    var suggestedTitle = "Generated title"

    func availability(languageIdentifier: String) async -> Result<Void, BurritoError> {
        availabilityResult
    }

    func generate(
        segments: [TranscriptSegment],
        userNotes: String,
        meetingContext: CalendarEventSnapshot?,
        template: TemplateSnapshot,
        languageIdentifier: String,
        priorContext: String?
    ) async -> Result<GeneratedNote, BurritoError> {
        generationResult
    }

    func suggestTitle(
        segments: [TranscriptSegment],
        currentTitle: String,
        languageIdentifier: String
    ) async -> Result<String, BurritoError> {
        .success(suggestedTitle)
    }
}

private final class HumanNotesGeneratorSpy: NoteGenerating, Sendable {
    let receivedUserNotes = Mutex<[String]>([])
    let receivedMeetingContexts = Mutex<[CalendarEventSnapshot?]>([])
    let receivedPriorContexts = Mutex<[String?]>([])

    func availability(languageIdentifier: String) async -> Result<Void, BurritoError> {
        .success(())
    }

    func generate(
        segments: [TranscriptSegment],
        userNotes: String,
        meetingContext: CalendarEventSnapshot?,
        template: TemplateSnapshot,
        languageIdentifier: String,
        priorContext: String?
    ) async -> Result<GeneratedNote, BurritoError> {
        receivedUserNotes.withLock { $0.append(userNotes) }
        receivedMeetingContexts.withLock { $0.append(meetingContext) }
        receivedPriorContexts.withLock { $0.append(priorContext) }
        return .success(GeneratedNote(title: "Generated", markdown: "# Generated"))
    }

    func suggestTitle(
        segments: [TranscriptSegment],
        currentTitle: String,
        languageIdentifier: String
    ) async -> Result<String, BurritoError> {
        .success("Guided meeting")
    }
}

private final class BlockingGeneratorStub: NoteGenerating, Sendable {
    let generationStarted = Mutex(false)
    let allowGeneration = Mutex(false)

    func availability(languageIdentifier: String) async -> Result<Void, BurritoError> {
        .success(())
    }

    func generate(
        segments: [TranscriptSegment],
        userNotes: String,
        meetingContext: CalendarEventSnapshot?,
        template: TemplateSnapshot,
        languageIdentifier: String,
        priorContext: String?
    ) async -> Result<GeneratedNote, BurritoError> {
        generationStarted.withLock { $0 = true }
        while !allowGeneration.withLock({ $0 }) {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return .success(GeneratedNote(title: "Generated", markdown: "# Generated"))
    }

    func suggestTitle(
        segments: [TranscriptSegment],
        currentTitle: String,
        languageIdentifier: String
    ) async -> Result<String, BurritoError> {
        .success("Generated title")
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
        userNotes: String,
        meetingContext: CalendarEventSnapshot?,
        template: TemplateSnapshot,
        languageIdentifier: String,
        priorContext: String?
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

private final class FlakyGeneratorStub: NoteGenerating, Sendable {
    let callCount = Mutex(0)
    let failuresBeforeSuccess: Int

    init(failuresBeforeSuccess: Int) {
        self.failuresBeforeSuccess = failuresBeforeSuccess
    }

    func availability(languageIdentifier: String) async -> Result<Void, BurritoError> {
        .success(())
    }

    func generate(
        segments: [TranscriptSegment],
        userNotes: String,
        meetingContext: CalendarEventSnapshot?,
        template: TemplateSnapshot,
        languageIdentifier: String,
        priorContext: String?
    ) async -> Result<GeneratedNote, BurritoError> {
        let attempt = callCount.withLock { count in
            count += 1
            return count
        }
        guard attempt > failuresBeforeSuccess else {
            return .failure(.generationFailed(details: "The model was busy."))
        }
        return .success(GeneratedNote(title: "Generated", markdown: "# Generated"))
    }

    func suggestTitle(
        segments: [TranscriptSegment],
        currentTitle: String,
        languageIdentifier: String
    ) async -> Result<String, BurritoError> {
        .success("Generated title")
    }
}

private struct MediaAudioExtractorStub: MediaAudioExtracting {
    var result: Result<ImportedMediaAudio, BurritoError> = .success(
        ImportedMediaAudio(duration: 42)
    )

    func extract(
        sourceURL: URL,
        transcriptionURL: URL,
        retainedAudioURL: URL?
    ) async -> Result<ImportedMediaAudio, BurritoError> {
        result
    }
}

private final class FileStoreSpy: RecordingFileStore, Sendable {
    let removeCount = Mutex(0)
    let removeTranscriptionCount = Mutex(0)
    let root: URL
    let removeAudioResult: Result<Void, BurritoError>
    let removeTranscriptionAudioResult: Result<Void, BurritoError>

    init(
        root: URL,
        removeAudioResult: Result<Void, BurritoError> = .success(()),
        removeTranscriptionAudioResult: Result<Void, BurritoError> = .success(())
    ) {
        self.root = root
        self.removeAudioResult = removeAudioResult
        self.removeTranscriptionAudioResult = removeTranscriptionAudioResult
    }

    func createSession(id: UUID, mode: RecordingMode) -> Result<RecordingFiles, BurritoError> {
        .success(
            RecordingFiles(
                sessionID: id,
                systemAudioURL: root.appending(path: "system.m4a"),
                microphoneAudioURL: mode == .meeting ? root.appending(path: "microphone.m4a") : nil,
                systemTranscriptionURL: root.appending(path: "system-transcription.caf"),
                microphoneTranscriptionURL: mode == .meeting
                    ? root.appending(path: "microphone-transcription.caf")
                    : nil
            )
        )
    }

    func relativePath(for url: URL) -> String { url.lastPathComponent }
    func url(forRelativePath path: String) -> URL { root.appending(path: path) }

    func removeAudio(for files: RecordingFiles) -> Result<Void, BurritoError> {
        removeCount.withLock { $0 += 1 }
        return removeAudioResult
    }

    func removeTranscriptionAudio(for files: RecordingFiles) -> Result<Void, BurritoError> {
        removeTranscriptionCount.withLock { $0 += 1 }
        return removeTranscriptionAudioResult
    }
}

private func sampleCalendarEvent() -> CalendarEventSnapshot {
    CalendarEventSnapshot(
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
}

@MainActor
@Suite("Recording coordinator")
struct CoordinatorTests {
    @Test("Detected recording opens the new note only after capture starts")
    func detectedRecordingOpensStartedNote() async throws {
        let context = try makeContext()
        let coordinator = AppCoordinator(
            capture: CaptureSpyingStub(),
            transcriber: TranscriberStub(needsSpeechAuthorization: false),
            generator: GeneratorStub(),
            fileStore: FileStoreSpy(root: FileManager.default.temporaryDirectory)
        )
        var openedMainWindow = false
        _ = NoteSelectionInbox.shared.consume()

        let accepted = await DetectedRecordingLauncher.start(
            mode: .listenAlong,
            coordinator: coordinator,
            context: context,
            openMainWindow: { openedMainWindow = true }
        )

        #expect(accepted)
        #expect(coordinator.captureState.isRecording)
        #expect(NoteSelectionInbox.shared.pendingNoteID == coordinator.activeNoteID)
        #expect(openedMainWindow)

        _ = NoteSelectionInbox.shared.consume()
        await coordinator.stop(context: context)
    }

    @Test("Detected recording rejects a non-idle coordinator without opening")
    func detectedRecordingRejectsNonIdleCoordinator() async throws {
        let context = try makeContext()
        let coordinator = AppCoordinator(
            capture: CaptureSpyingStub(),
            transcriber: TranscriberStub(needsSpeechAuthorization: false),
            generator: GeneratorStub(),
            fileStore: FileStoreSpy(root: FileManager.default.temporaryDirectory)
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
        var openedMainWindow = false

        let accepted = await DetectedRecordingLauncher.start(
            mode: .listenAlong,
            coordinator: coordinator,
            context: context,
            openMainWindow: { openedMainWindow = true }
        )

        #expect(!accepted)
        #expect(!openedMainWindow)

        await coordinator.stop(context: context)
    }

    @Test("Selected playback rate applies only to captured system audio")
    func routesPlaybackRateToSystemAudio() async throws {
        let context = try makeContext()
        let transcriber = TranscriptionInputSpy()
        let rate = try #require(PlaybackRate(rawValue: 3))
        let coordinator = AppCoordinator(
            capture: CaptureSpyingStub(),
            transcriber: transcriber,
            generator: GeneratorStub(),
            fileStore: FileStoreSpy(root: FileManager.default.temporaryDirectory)
        )
        let options = RecordingOptions(
            template: TemplateSnapshot(
                name: "Summary",
                symbol: "doc",
                instructions: "Summarize."
            ),
            languageIdentifier: "en-US",
            mode: .meeting,
            retainsAudio: false,
            playbackRate: rate
        )

        await coordinator.start(options: options, context: context)
        await coordinator.stop(context: context)
        await waitUntil { transcriber.inputs.withLock { $0 }.count == 2 }

        let inputs = transcriber.inputs.withLock { $0 }
        #expect(inputs.count == 2)
        #expect(
            inputs.contains {
                if case .systemCapture(let fileURL, let playbackRate) = $0 {
                    return fileURL.lastPathComponent == "system.m4a"
                        && playbackRate == rate
                }
                return false
            }
        )
        #expect(
            inputs.contains {
                if case .natural(let fileURL, let source) = $0 {
                    return fileURL.lastPathComponent == "microphone.m4a"
                        && source == .microphone
                }
                return false
            }
        )
    }

    @Test("Importing original media bypasses capture and produces a ready note")
    func importsOriginalMedia() async throws {
        let context = try makeContext()
        let capture = CaptureSpyingStub()
        let transcriber = TranscriptionInputSpy()
        let coordinator = AppCoordinator(
            capture: capture,
            transcriber: transcriber,
            generator: GeneratorStub(),
            fileStore: FileStoreSpy(root: FileManager.default.temporaryDirectory),
            mediaAudioExtractor: MediaAudioExtractorStub(),
            requestSpeechAuthorization: { true }
        )
        let options = RecordingOptions(
            template: TemplateSnapshot(
                name: "Study guide",
                symbol: "book",
                instructions: "Build a study guide."
            ),
            languageIdentifier: "en-US",
            mode: .listenAlong,
            retainsAudio: false,
            playbackRate: try #require(PlaybackRate(rawValue: 10))
        )

        let result = await coordinator.importMedia(
            fileURL: URL(filePath: "/tmp/accelerated-lecture.mov"),
            options: options,
            context: context
        )
        let noteID = try result.get()
        let note = try #require(context.fetch(FetchDescriptor<Note>()).first)

        #expect(note.id == noteID)
        #expect(note.lifecycle == .ready)
        #expect(note.duration == 42)
        #expect(note.playbackRate == .natural)
        #expect(note.transcriptSegments.map(\.source) == [.system])
        #expect(capture.starts == 0)
        let input = try #require(transcriber.inputs.withLock { $0 }.first)
        if case .importedMedia(_, .system) = input {
            // Expected: imported media must not be treated as natural captured audio.
        } else {
            Issue.record("Expected imported system media input, received \(input).")
        }
    }

    @Test("Failed imported transcription removes its incomplete note and audio")
    func importFailureRemovesIncompleteSession() async throws {
        let context = try makeContext()
        let expectedError = BurritoError.transcriptionFailed(details: "Fixture failure")
        let fileStore = FileStoreSpy(root: FileManager.default.temporaryDirectory)
        let coordinator = AppCoordinator(
            capture: CaptureSpyingStub(),
            transcriber: TranscriptionInputSpy(result: .failure(expectedError)),
            generator: GeneratorStub(),
            fileStore: fileStore,
            mediaAudioExtractor: MediaAudioExtractorStub()
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

        let result = await coordinator.importMedia(
            fileURL: URL(filePath: "/tmp/fixture.mov"),
            options: options,
            context: context
        )

        #expect(result == .failure(expectedError))
        #expect(fileStore.removeCount.withLock { $0 } == 1)
        #expect(try context.fetch(FetchDescriptor<Note>()).isEmpty)
    }

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
        await waitUntil { note.lifecycle != .processing }

        // Then
        #expect(capture.stops == 1)
        #expect(note.lifecycle == .ready)
        #expect(note.title == "Generated title")
        #expect(note.transcriptSegments.count == 2)
        #expect(note.transcriptSegments.map(\.source) == [.microphone, .system])
        #expect(fileStore.removeCount.withLock { $0 } == 1)
        #expect(
            feedback.events
                == ["recordingStarted", "recordingStopped", "noteReady:Generated title"]
        )
    }

    @Test("A new recording can start while the previous note is still generating")
    func recordingStartsWhilePreviousNoteGenerates() async throws {
        let context = try makeContext()
        let capture = CaptureSpyingStub()
        let generator = BlockingGeneratorStub()
        let coordinator = AppCoordinator(
            capture: capture,
            transcriber: TranscriberStub(),
            generator: generator,
            fileStore: FileStoreSpy(root: FileManager.default.temporaryDirectory),
            requestSpeechAuthorization: { true }
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
        let stopTask = Task { await coordinator.stop(context: context) }
        await waitUntil { generator.generationStarted.withLock { $0 } }

        #expect(coordinator.captureState == .idle)
        #expect(capture.stops == 1)

        await coordinator.start(options: options, context: context)
        #expect(coordinator.captureState.isRecording)
        #expect(coordinator.lastError == nil)
        #expect(capture.starts == 2)

        generator.allowGeneration.withLock { $0 = true }
        await stopTask.value
        await coordinator.stop(context: context)

        let notes = try context.fetch(FetchDescriptor<Note>())
        #expect(notes.count == 2)
        await waitUntil { notes.allSatisfy { $0.lifecycle == .ready } }
        #expect(notes.allSatisfy { $0.lifecycle == .ready })
    }

    @Test("Study mode creates a named folder and assigns the recording")
    func studyModeCreatesNamedFolder() async throws {
        let context = try makeContext()
        let coordinator = AppCoordinator(
            capture: CaptureSpyingStub(),
            transcriber: TranscriberStub(needsSpeechAuthorization: false),
            generator: GeneratorStub(),
            fileStore: FileStoreSpy(root: FileManager.default.temporaryDirectory)
        )
        let options = RecordingOptions(
            template: TemplateSnapshot(
                name: "Study Notes",
                symbol: "book",
                instructions: "Teach the material."
            ),
            languageIdentifier: "en-US",
            mode: .listenAlong,
            retainsAudio: false
        )

        let started = await coordinator.startStudyMode(
            name: "Database isolation",
            options: options,
            context: context
        )

        #expect(started)
        let folder = try #require(context.fetch(FetchDescriptor<Folder>()).first)
        let note = try #require(context.fetch(FetchDescriptor<Note>()).first)
        #expect(folder.name == "Database isolation")
        #expect(note.folder?.id == folder.id)

        await coordinator.stop(context: context)
    }

    @Test("Study mode continues recording into an existing folder")
    func studyModeContinuesIntoExistingFolder() async throws {
        let context = try makeContext()
        let folder = Folder(name: "Database isolation", order: 0)
        context.insert(folder)
        try context.save()

        let coordinator = AppCoordinator(
            capture: CaptureSpyingStub(),
            transcriber: TranscriberStub(needsSpeechAuthorization: false),
            generator: GeneratorStub(),
            fileStore: FileStoreSpy(root: FileManager.default.temporaryDirectory)
        )
        let options = RecordingOptions(
            template: TemplateSnapshot(
                name: "Study Notes",
                symbol: "book",
                instructions: "Teach the material."
            ),
            languageIdentifier: "en-US",
            mode: .listenAlong,
            retainsAudio: false
        )

        let started = await coordinator.startStudyMode(
            name: "Database isolation",
            folderID: folder.id,
            options: options,
            context: context
        )

        #expect(started)
        // No duplicate folder was created for the continuation.
        let folders = try context.fetch(FetchDescriptor<Folder>())
        #expect(folders.count == 1)
        let note = try #require(context.fetch(FetchDescriptor<Note>()).first)
        #expect(note.folder?.id == folder.id)

        await coordinator.stop(context: context)
    }

    @Test("Study rotation keeps generating notes after the session is stopped")
    func studyRotationKeepsProcessingAfterStop() async throws {
        let context = try makeContext()
        let capture = CaptureSpyingStub()
        let generator = BlockingGeneratorStub()
        let clock = TestClock()
        let coordinator = AppCoordinator(
            capture: capture,
            transcriber: TranscriberStub(needsSpeechAuthorization: false),
            generator: generator,
            fileStore: FileStoreSpy(root: FileManager.default.temporaryDirectory),
            now: { clock.now }
        )
        let options = RecordingOptions(
            template: TemplateSnapshot(
                name: "Study Notes",
                symbol: "book",
                instructions: "Teach the material."
            ),
            languageIdentifier: "en-US",
            mode: .listenAlong,
            retainsAudio: false
        )

        let started = await coordinator.startStudyMode(
            name: "Database isolation",
            options: options,
            context: context
        )
        #expect(started)

        // Cross the 10-minute study segment boundary: the finished segment's
        // transcription and generation start while the next segment records.
        clock.advance(by: 601)
        await waitUntil { capture.stops == 1 }
        await waitUntil { generator.generationStarted.withLock { $0 } }

        // Stopping the session must NOT abandon the finished segment's note.
        await coordinator.stop(context: context)

        generator.allowGeneration.withLock { $0 = true }

        let notes = try context.fetch(FetchDescriptor<Note>())
        #expect(notes.count == 2)
        await waitUntil { notes.allSatisfy { $0.lifecycle == .ready } }
        #expect(notes.filter { $0.markdownBody == "# Generated" }.count == 2)
        #expect(notes.allSatisfy { !$0.transcriptSegments.isEmpty })
    }

    @Test("Study segments keep creation order regardless of processing finish order")
    func studySegmentsOrderByCreationTime() async throws {
        let context = try makeContext()
        let capture = CaptureSpyingStub()
        let generator = BlockingGeneratorStub()
        let clock = TestClock()
        let coordinator = AppCoordinator(
            capture: capture,
            transcriber: TranscriberStub(needsSpeechAuthorization: false),
            generator: generator,
            fileStore: FileStoreSpy(root: FileManager.default.temporaryDirectory),
            now: { clock.now }
        )
        let options = RecordingOptions(
            template: TemplateSnapshot(
                name: "Study Notes",
                symbol: "book",
                instructions: "Teach the material."
            ),
            languageIdentifier: "en-US",
            mode: .listenAlong,
            retainsAudio: false
        )

        let started = await coordinator.startStudyMode(
            name: "Database isolation",
            options: options,
            context: context
        )
        #expect(started)

        clock.advance(by: 601)
        await waitUntil { capture.stops == 1 }
        // The second segment must be recording before its note exists.
        await waitUntil { capture.starts == 2 }

        generator.allowGeneration.withLock { $0 = true }
        let notes = try context.fetch(FetchDescriptor<Note>())
        #expect(notes.count == 2)

        let first = try #require(notes.min { $0.createdAt < $1.createdAt })
        let second = try #require(notes.max { $0.createdAt < $1.createdAt })
        // The newer segment carries a smaller manual position (ascending =
        // newest on top), independent of which segment finished generating.
        #expect(first.manualOrder == 0)
        #expect(second.manualOrder == -1)
        #expect(Note.orderedWithinDay(notes).map(\.id) == [second.id, first.id])

        await coordinator.stop(context: context)
    }

    @Test("Transient generation failures retry until the note is ready")
    func transientGenerationFailureRetries() async throws {
        let context = try makeContext()
        let generator = FlakyGeneratorStub(failuresBeforeSuccess: 1)
        let coordinator = AppCoordinator(
            capture: CaptureSpyingStub(),
            transcriber: TranscriberStub(),
            generator: generator,
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
        await coordinator.stop(context: context)

        let note = try #require(context.fetch(FetchDescriptor<Note>()).first)
        await waitUntil { note.lifecycle != .processing }
        #expect(note.lifecycle == .ready)
        #expect(generator.callCount.withLock { $0 } == 2)
        #expect(note.lastErrorMessage == nil)
    }

    @Test("Folder-backed notes receive the previous note as prior session context")
    func priorSessionContextComesFromFolderSibling() async throws {
        let context = try makeContext()
        let folder = Folder(name: "Database isolation", order: 0)
        context.insert(folder)
        let template = TemplateSnapshot(
            name: "Study Notes",
            symbol: "book",
            instructions: "Teach the material."
        )
        let older = Note(
            lifecycle: .ready,
            title: "Segment one",
            markdownBody: "# Segment one\n\nCovered indexes and joins.",
            languageIdentifier: "en-US",
            template: template,
            retainsAudio: false
        )
        older.folder = folder
        let current = Note(
            lifecycle: .ready,
            title: "Segment two",
            languageIdentifier: "en-US",
            template: template,
            retainsAudio: false
        )
        current.folder = folder
        context.insert(older)
        context.insert(current)
        try context.save()

        let spy = HumanNotesGeneratorSpy()
        let coordinator = AppCoordinator(
            capture: CaptureSpyingStub(),
            transcriber: TranscriberStub(),
            generator: spy,
            fileStore: FileStoreSpy(root: FileManager.default.temporaryDirectory),
            requestSpeechAuthorization: { true }
        )
        await coordinator.generate(note: current, context: context)

        let received = spy.receivedPriorContexts.withLock { $0 }
        #expect(received == ["# Segment one\n\nCovered indexes and joins."])
    }

    @Test("Recoverable notes with a transcript auto-regenerate on launch")
    func recoverableNotesAutoHealOnLaunch() async throws {
        let context = try makeContext()
        let note = Note(
            lifecycle: .recoverable,
            title: "Interrupted segment",
            languageIdentifier: "en-US",
            template: TemplateSnapshot(
                name: "Study Notes",
                symbol: "book",
                instructions: "Teach the material."
            ),
            retainsAudio: false
        )
        note.replaceTranscript(
            with: [
                TranscriptSegment(
                    source: .system,
                    startTime: 0,
                    duration: 4,
                    text: "The transcript survived the interruption."
                ),
            ],
            marksEdited: true
        )
        note.lastErrorMessage = "The model was busy."
        context.insert(note)
        try context.save()

        let coordinator = AppCoordinator(
            capture: CaptureSpyingStub(),
            transcriber: TranscriberStub(),
            generator: GeneratorStub(),
            fileStore: FileStoreSpy(root: FileManager.default.temporaryDirectory),
            requestSpeechAuthorization: { true }
        )
        coordinator.recoverInterruptedNotes(context: context)

        await waitUntil { note.lifecycle == .ready }
        #expect(note.lifecycle == .ready)
        #expect(note.notesMayBeOutdated == false)
    }

    @Test("Regenerating a note preserves its timeline time and position")
    func regenerationPreservesActivityTime() async throws {
        let context = try makeContext()
        let originalTime = Date(timeIntervalSinceReferenceDate: 100)
        let note = Note(
            lifecycle: .ready,
            title: "Old title",
            markdownBody: "# Old notes",
            transcriptSegments: [
                TranscriptSegment(
                    source: .system,
                    startTime: 0,
                    duration: 4,
                    text: "The recorded material."
                ),
            ],
            createdAt: originalTime,
            languageIdentifier: "en-US",
            template: TemplateSnapshot(
                name: "Summary",
                symbol: "doc",
                instructions: "Summarize."
            ),
            retainsAudio: false
        )
        note.updatedAt = originalTime
        context.insert(note)
        try context.save()

        let coordinator = AppCoordinator(
            capture: CaptureSpyingStub(),
            transcriber: TranscriberStub(),
            generator: GeneratorStub(),
            fileStore: FileStoreSpy(root: FileManager.default.temporaryDirectory),
            requestSpeechAuthorization: { true }
        )
        await coordinator.generateInBackground(note: note, context: context)

        #expect(note.lifecycle == .ready)
        #expect(note.markdownBody == "# Generated")
        // Regeneration must never bump the activity time: the note keeps
        // its timeline position instead of jumping to "now".
        #expect(note.updatedAt == originalTime)
    }

    @Test("Appended segments queue behind in-flight processing instead of being dropped")
    func appendedSegmentsQueueBehindInFlightProcessing() async throws {
        let context = try makeContext()
        let capture = CaptureSpyingStub()
        let generator = BlockingGeneratorStub()
        let coordinator = AppCoordinator(
            capture: capture,
            transcriber: TranscriberStub(),
            generator: generator,
            fileStore: FileStoreSpy(root: FileManager.default.temporaryDirectory),
            requestSpeechAuthorization: { true }
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
        let note = try #require(context.fetch(FetchDescriptor<Note>()).first)

        await coordinator.stop(context: context)
        await waitUntil { generator.generationStarted.withLock { $0 } }

        // The first segment is still generating; append a second recording
        // to the same note and stop it. The second segment must queue
        // behind the in-flight processing, never be dropped.
        await coordinator.start(
            options: options,
            destination: .appendToNote(id: note.id),
            context: context
        )
        await coordinator.stop(context: context)

        generator.allowGeneration.withLock { $0 = true }
        // The appended segment's transcript merges after the first segment
        // finishes generating; wait for both so the assertion never races
        // the background chain.
        await waitUntil {
            note.lifecycle != .processing && note.transcriptSegments.count == 4
        }

        #expect(note.lifecycle == .ready)
        #expect(note.transcriptSegments.count == 4)
        #expect(note.transcriptSegments.map(\.source).contains(.system))
    }

    @Test("Human notes written during capture guide generation and remain intact")
    func humanNotesGuideGeneration() async throws {
        let context = try makeContext()
        let generator = HumanNotesGeneratorSpy()
        let coordinator = AppCoordinator(
            capture: CaptureSpyingStub(),
            transcriber: TranscriberStub(),
            generator: generator,
            fileStore: FileStoreSpy(root: FileManager.default.temporaryDirectory),
            requestSpeechAuthorization: { true }
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
        let note = try #require(context.fetch(FetchDescriptor<Note>()).first)
        note.userNotes = "- The launch date is the key decision."
        await coordinator.stop(context: context)
        await waitUntil { note.lifecycle != .processing }

        #expect(
            generator.receivedUserNotes.withLock { $0 }
                == ["- The launch date is the key decision."]
        )
        #expect(note.userNotes == "- The launch date is the key decision.")
        #expect(note.markdownBody == "# Generated")
    }

    @Test("Calendar recordings preserve event identity and supply meeting context")
    func calendarRecordingUsesEventContext() async throws {
        let context = try makeContext()
        let generator = HumanNotesGeneratorSpy()
        let coordinator = AppCoordinator(
            capture: CaptureSpyingStub(),
            transcriber: TranscriberStub(),
            generator: generator,
            fileStore: FileStoreSpy(root: FileManager.default.temporaryDirectory),
            requestSpeechAuthorization: { true }
        )
        let options = RecordingOptions(
            template: TemplateSnapshot(
                name: "Meeting",
                symbol: "person.3",
                instructions: "Capture decisions."
            ),
            languageIdentifier: "en-US",
            mode: .meeting,
            retainsAudio: false
        )
        let event = sampleCalendarEvent()

        await coordinator.start(
            options: options,
            destination: .calendarEvent(event),
            context: context
        )
        let note = try #require(context.fetch(FetchDescriptor<Note>()).first)

        #expect(note.title == event.title)
        #expect(note.calendarEvent == event)

        await coordinator.stop(context: context)
        await waitUntil { note.lifecycle != .processing }

        #expect(note.lifecycle == .ready)
        #expect(note.title == event.title)
        #expect(generator.receivedMeetingContexts.withLock { $0 } == [event])

        note.title = "My product review"
        await coordinator.generate(note: note, context: context)

        #expect(note.title == "My product review")
        #expect(generator.receivedMeetingContexts.withLock { $0 } == [event, event])
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
        await waitUntil { note.lifecycle != .processing }

        let notes = try context.fetch(FetchDescriptor<Note>())
        #expect(notes.count == 1)
        #expect(
            note.transcriptSegments.map(\.text)
                == ["Existing text", "Microphone text", "System text"]
        )
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
        await waitUntil { note.lifecycle != .processing }

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
        await waitUntil { coordinator.activity == capture.activity }

        #expect(coordinator.activity == capture.activity)
        #expect(capture.languageIdentifiers == ["en-US"])

        await coordinator.stop(context: context)
        #expect(coordinator.activity == .silent)
    }

    @Test("Recording can pause and resume without ending the note")
    func pauseAndResumeRecording() async throws {
        let context = try makeContext()
        let capture = CaptureSpyingStub()
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
        await coordinator.pause()

        #expect(coordinator.isPaused)
        #expect(coordinator.captureState.isRecording)
        #expect(capture.pauses == 1)

        await coordinator.resume()

        #expect(!coordinator.isPaused)
        #expect(capture.resumes == 1)

        await coordinator.stop(context: context)
    }

    @Test("Paused wall-clock time is excluded from the recording duration")
    func pausedTimeIsExcludedFromDuration() async throws {
        let context = try makeContext()
        let clock = Mutex(Date(timeIntervalSinceReferenceDate: 100))
        let capture = CaptureSpyingStub()
        let coordinator = AppCoordinator(
            capture: capture,
            transcriber: TranscriberStub(),
            generator: GeneratorStub(),
            fileStore: FileStoreSpy(root: FileManager.default.temporaryDirectory),
            requestSpeechAuthorization: { true },
            now: { clock.withLock { $0 } }
        )
        let options = RecordingOptions(
            template: TemplateSnapshot(name: "Summary", symbol: "doc", instructions: "Summarize."),
            languageIdentifier: "en-US",
            mode: .listenAlong,
            retainsAudio: false
        )

        await coordinator.start(options: options, context: context)
        clock.withLock { $0 = Date(timeIntervalSinceReferenceDate: 110) }
        await coordinator.pause()
        clock.withLock { $0 = Date(timeIntervalSinceReferenceDate: 140) }
        await waitUntil { coordinator.elapsed == 10 }
        #expect(coordinator.elapsed == 10)
        await coordinator.resume()
        clock.withLock { $0 = Date(timeIntervalSinceReferenceDate: 150) }
        await coordinator.stop(context: context)

        let note = try #require(context.fetch(FetchDescriptor<Note>()).first)
        #expect(note.duration == 20)
    }

    @Test("Stopping preserves the final live transcript snapshot")
    func stopPreservesFinalLiveTranscript() async throws {
        let context = try makeContext()
        let capture = CaptureSpyingStub()
        let coordinator = AppCoordinator(
            capture: capture,
            transcriber: TranscriberStub(),
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
        let finalSnapshot = LiveTranscriptSnapshot(
            availability: .available,
            passages: [
                LiveTranscriptPassage(
                    source: .system,
                    startTime: 0,
                    duration: 2,
                    text: "Final passage",
                    isFinal: true
                ),
            ]
        )

        await coordinator.start(options: options, context: context)
        capture.liveTranscript = finalSnapshot
        await coordinator.stop(context: context)

        #expect(coordinator.liveTranscript == finalSnapshot)
    }

    @Test("Successful generation preserves every nonfatal processing warning")
    func generationPreservesDiarizationWarning() async throws {
        let context = try makeContext()
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root.appending(path: "system.m4a"))
        let warning = BurritoError.speakerDiarizationFailed(details: "Model unavailable")
        let cleanupWarning = BurritoError.storageFailed(details: "Temporary audio is locked")
        let coordinator = AppCoordinator(
            capture: CaptureSpyingStub(),
            transcriber: TranscriberStub(),
            generator: GeneratorStub(),
            fileStore: FileStoreSpy(
                root: root,
                removeTranscriptionAudioResult: .failure(cleanupWarning)
            ),
            speakerDiarizer: SpeakerDiarizerFailureStub(error: warning),
            requestSpeechAuthorization: { true }
        )
        let options = RecordingOptions(
            template: TemplateSnapshot(name: "Summary", symbol: "doc", instructions: "Summarize."),
            languageIdentifier: "en-US",
            mode: .meeting,
            retainsAudio: false
        )

        await coordinator.start(options: options, context: context)
        await coordinator.stop(context: context)

        let note = try #require(context.fetch(FetchDescriptor<Note>()).first)
        await waitUntil { note.lifecycle != .processing }
        #expect(note.lifecycle == .ready)
        #expect(note.lastErrorMessage?.contains(warning.recoveryMessage) == true)
        #expect(note.lastErrorMessage?.contains(cleanupWarning.recoveryMessage) == true)
    }

    @Test("Failed generation preserves every nonfatal processing warning")
    func failedGenerationPreservesProcessingWarnings() async throws {
        let context = try makeContext()
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root.appending(path: "system.m4a"))
        let generationError = BurritoError.generationFailed(details: "The model is unavailable")
        let diarizationWarning = BurritoError.speakerDiarizationFailed(details: "Model unavailable")
        let cleanupWarning = BurritoError.storageFailed(details: "Temporary audio is locked")
        let coordinator = AppCoordinator(
            capture: CaptureSpyingStub(),
            transcriber: TranscriberStub(),
            generator: GeneratorStub(generationResult: .failure(generationError)),
            fileStore: FileStoreSpy(
                root: root,
                removeTranscriptionAudioResult: .failure(cleanupWarning)
            ),
            speakerDiarizer: SpeakerDiarizerFailureStub(error: diarizationWarning),
            requestSpeechAuthorization: { true }
        )
        let options = RecordingOptions(
            template: TemplateSnapshot(name: "Summary", symbol: "doc", instructions: "Summarize."),
            languageIdentifier: "en-US",
            mode: .meeting,
            retainsAudio: false
        )

        await coordinator.start(options: options, context: context)
        await coordinator.stop(context: context)

        let note = try #require(context.fetch(FetchDescriptor<Note>()).first)
        await waitUntil { note.lifecycle != .processing }
        #expect(note.lifecycle == .recoverable)
        #expect(note.lastErrorMessage?.contains(generationError.recoveryMessage) == true)
        #expect(note.lastErrorMessage?.contains(diarizationWarning.recoveryMessage) == true)
        #expect(note.lastErrorMessage?.contains(cleanupWarning.recoveryMessage) == true)
    }

    @Test("Capture startup time does not count as recording silence")
    func captureStartupDoesNotCountAsSilence() async throws {
        let context = try makeContext()
        let clock = Mutex(Date(timeIntervalSinceReferenceDate: 100))
        let capture = CaptureSpyingStub()
        capture.didStart = {
            clock.withLock { $0 = Date(timeIntervalSinceReferenceDate: 160) }
        }
        let coordinator = AppCoordinator(
            capture: capture,
            transcriber: TranscriberStub(),
            generator: GeneratorStub(),
            fileStore: FileStoreSpy(root: FileManager.default.temporaryDirectory),
            requestSpeechAuthorization: { true },
            now: { clock.withLock { $0 } }
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

        #expect(coordinator.silentFor == 0)

        await coordinator.stop(context: context)
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

    @Test("Reopening the window does not recover the active recording pipeline")
    func activeRecordingPipelineIsNotRecovered() async throws {
        let context = try makeContext()
        let coordinator = AppCoordinator(
            capture: CaptureSpyingStub(),
            transcriber: TranscriberStub(needsSpeechAuthorization: false),
            generator: GeneratorStub(),
            fileStore: FileStoreSpy(root: FileManager.default.temporaryDirectory)
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
        let noteID = try #require(coordinator.activeNoteID)
        let note = try #require(
            try context.fetch(FetchDescriptor<Note>()).first { $0.id == noteID }
        )

        coordinator.recoverInterruptedNotes(context: context)

        #expect(note.lifecycle == .recording)
        #expect(note.processingStage == nil)
        #expect(note.lastErrorMessage == nil)

        note.lifecycle = .processing
        note.processingStage = .transcribing
        try context.save()
        coordinator.recoverInterruptedNotes(context: context)

        #expect(note.lifecycle == .processing)
        #expect(note.processingStage == .transcribing)
        #expect(note.lastErrorMessage == nil)

        await coordinator.stop(context: context)
    }

    private func waitUntil(
        _ condition: @MainActor () -> Bool,
        attempts: Int = 500
    ) async {
        for _ in 0..<attempts {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
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
