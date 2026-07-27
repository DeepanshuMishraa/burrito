import Foundation
import Observation
import Speech
import SwiftData

@MainActor
@Observable
final class AppCoordinator {
    private(set) var captureState: CaptureState = .idle
    private(set) var activeNoteID: UUID?
    private(set) var elapsed: TimeInterval = 0
    private(set) var lastError: BurritoError?
    private(set) var isInstallingLanguageAsset = false

    private let capture: any AudioCapturing
    private let transcriber: any Transcribing
    private let generator: any NoteGenerating
    private let fileStore: any RecordingFileStore
    private let requestSpeechAuthorization: @MainActor @Sendable () async -> Bool
    private var activeFiles: RecordingFiles?
    private var timerTask: Task<Void, Never>?

    var activity: AudioActivity { capture.activity }

    init(
        capture: any AudioCapturing,
        transcriber: any Transcribing,
        generator: any NoteGenerating,
        fileStore: any RecordingFileStore,
        requestSpeechAuthorization: @escaping @MainActor @Sendable () async -> Bool = AppCoordinator.systemSpeechAuthorization
    ) {
        self.capture = capture
        self.transcriber = transcriber
        self.generator = generator
        self.fileStore = fileStore
        self.requestSpeechAuthorization = requestSpeechAuthorization
    }

    static func live() -> AppCoordinator {
        AppCoordinator(
            capture: SystemAudioCapture(),
            transcriber: LocalTranscriber(),
            generator: FoundationNoteGenerator(),
            fileStore: LocalRecordingFileStore()
        )
    }

    func recoverInterruptedNotes(context: ModelContext) {
        do {
            let notes = try context.fetch(FetchDescriptor<Note>())
            for note in notes where note.lifecycle == .recording || note.lifecycle == .processing {
                note.lifecycle = .recoverable
                note.processingStage = nil
                note.lastErrorMessage = "Burrito closed before this recording finished. Existing audio is preserved; retry processing when ready."
            }
            try context.save()
        } catch {
            lastError = .storageFailed(details: error.localizedDescription)
        }
    }

    func start(options: RecordingOptions, context: ModelContext) async {
        guard captureState == .idle else {
            lastError = .recordingAlreadyInProgress
            return
        }
        captureState = .preparing
        lastError = nil

        let modelAvailability = await generator.availability(
            languageIdentifier: options.languageIdentifier
        )
        if case .failure(let error) = modelAvailability {
            failBeforeRecording(error)
            return
        }

        guard await requestSpeechAuthorization() else {
            failBeforeRecording(.speechRecognitionPermissionDenied)
            return
        }

        let languageAvailability = await transcriber.verifyLanguage(options.languageIdentifier)
        if case .failure(let error) = languageAvailability {
            failBeforeRecording(error)
            return
        }

        let sessionID = UUID()
        guard case .success(let files) = fileStore.createSession(
            id: sessionID,
            includesMicrophone: options.includesMicrophone
        ) else {
            failBeforeRecording(.storageFailed(details: "The recording directory could not be created."))
            return
        }

        let now = Date.now
        let note = Note(
            id: sessionID,
            lifecycle: .recording,
            createdAt: now,
            languageIdentifier: options.languageIdentifier,
            template: options.template,
            retainsAudio: options.retainsAudio
        )
        note.systemAudioRelativePath = fileStore.relativePath(for: files.systemAudioURL)
        note.microphoneAudioRelativePath = files.microphoneAudioURL.map(fileStore.relativePath(for:))
        context.insert(note)

        do {
            try context.save()
        } catch {
            failBeforeRecording(.storageFailed(details: error.localizedDescription))
            return
        }

        switch await capture.start(files: files, includesMicrophone: options.includesMicrophone) {
        case .success:
            activeFiles = files
            activeNoteID = note.id
            captureState = .recording(sessionID: sessionID, startedAt: now)
            elapsed = 0
            startTimer(startedAt: now)
        case .failure(let error):
            note.lifecycle = .recoverable
            note.lastErrorMessage = error.recoveryMessage
            try? context.save()
            activeNoteID = note.id
            captureState = .failed(sessionID: sessionID, message: error.recoveryMessage)
            lastError = error
        }
    }

    func stop(context: ModelContext) async {
        guard case .recording(let sessionID, let startedAt) = captureState,
              let files = activeFiles,
              let note = fetchNote(id: sessionID, context: context)
        else {
            lastError = .noActiveRecording
            return
        }

        timerTask?.cancel()
        timerTask = nil
        captureState = .stopping(sessionID: sessionID)
        note.lifecycle = .processing
        note.processingStage = .preparingAudio
        note.duration = Date.now.timeIntervalSince(startedAt)
        note.updatedAt = .now
        try? context.save()

        if case .failure(let error) = await capture.stop() {
            fail(note: note, error: error, context: context)
            return
        }

        note.processingStage = .transcribing
        try? context.save()

        let systemResult = await transcriber.transcribe(
            fileURL: files.systemAudioURL,
            source: .system,
            languageIdentifier: note.languageIdentifier
        )
        guard case .success(let systemSegments) = systemResult else {
            if case .failure(let error) = systemResult {
                fail(note: note, error: error, context: context)
            }
            return
        }

        var microphoneSegments: [TranscriptSegment] = []
        if let microphoneURL = files.microphoneAudioURL {
            let microphoneResult = await transcriber.transcribe(
                fileURL: microphoneURL,
                source: .microphone,
                languageIdentifier: note.languageIdentifier
            )
            guard case .success(let segments) = microphoneResult else {
                if case .failure(let error) = microphoneResult {
                    fail(note: note, error: error, context: context)
                }
                return
            }
            microphoneSegments = segments
        }

        note.processingStage = .organizing
        note.replaceTranscript(
            with: Transcript.merge(system: systemSegments, microphone: microphoneSegments),
            marksEdited: false
        )
        try? context.save()

        if !note.retainsAudio {
            if case .failure(let error) = fileStore.removeAudio(for: files) {
                note.lastErrorMessage = error.recoveryMessage
            } else {
                note.systemAudioRelativePath = nil
                note.microphoneAudioRelativePath = nil
            }
        }

        await generate(note: note, context: context)
        activeFiles = nil
        activeNoteID = nil
        captureState = .idle
        elapsed = 0
    }

    func generate(note: Note, context: ModelContext, undoManager: UndoManager? = nil) async {
        let oldTitle = note.title
        let oldBody = note.markdownBody

        note.lifecycle = .processing
        note.processingStage = .generatingNotes
        note.lastErrorMessage = nil
        try? context.save()

        switch await generator.generate(
            segments: note.transcriptSegments,
            template: note.templateSnapshot,
            languageIdentifier: note.languageIdentifier
        ) {
        case .success(let generated):
            note.title = generated.title
            note.markdownBody = generated.markdown
            note.generatedFromTranscriptRevision = note.transcriptRevision
            note.userEditedNotes = false
            note.lifecycle = .ready
            note.processingStage = nil
            note.updatedAt = .now
            undoManager?.registerUndo(withTarget: note) { target in
                target.title = oldTitle
                target.markdownBody = oldBody
                target.userEditedNotes = true
            }
        case .failure(let error):
            note.lifecycle = .recoverable
            note.processingStage = nil
            note.lastErrorMessage = error.recoveryMessage
            lastError = error
        }
        try? context.save()
    }

    func dismissFailure() {
        if case .failed = captureState {
            captureState = .idle
            activeNoteID = nil
        }
        lastError = nil
    }

    func installMissingLanguageAsset() async {
        guard case .languageAssetMissing(let identifier) = lastError,
              !isInstallingLanguageAsset
        else {
            return
        }

        isInstallingLanguageAsset = true
        defer { isInstallingLanguageAsset = false }

        switch await transcriber.installLanguageAsset(identifier) {
        case .success:
            dismissFailure()
        case .failure(let error):
            lastError = error
        }
    }

    private func failBeforeRecording(_ error: BurritoError) {
        captureState = .idle
        lastError = error
    }

    private func fail(note: Note, error: BurritoError, context: ModelContext) {
        note.lifecycle = .recoverable
        note.processingStage = nil
        note.lastErrorMessage = error.recoveryMessage
        try? context.save()
        lastError = error
        captureState = .failed(sessionID: note.id, message: error.recoveryMessage)
        activeFiles = nil
        timerTask?.cancel()
        timerTask = nil
    }

    private func fetchNote(id: UUID, context: ModelContext) -> Note? {
        let requestedID = id
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate { $0.id == requestedID }
        )
        return try? context.fetch(descriptor).first
    }

    private func startTimer(startedAt: Date) {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.elapsed = Date.now.timeIntervalSince(startedAt)
            }
        }
    }

    private static func systemSpeechAuthorization() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            true
        case .notDetermined:
            await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        case .denied, .restricted:
            false
        @unknown default:
            false
        }
    }
}
