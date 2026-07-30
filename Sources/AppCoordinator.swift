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
    private(set) var activity = AudioActivity.silent
    private(set) var lastError: BurritoError?
    private(set) var isInstallingLanguageAsset = false

    private let capture: any AudioCapturing
    private let transcriber: any Transcribing
    private let generator: any NoteGenerating
    private let fileStore: any RecordingFileStore
    private let feedback: any AppFeedbackProviding
    private let requestSpeechAuthorization: @MainActor @Sendable () async -> Bool
    private var activeFiles: RecordingFiles?
    private var appendsToExistingNote = false
    private var timerTask: Task<Void, Never>?

    init(
        capture: any AudioCapturing,
        transcriber: any Transcribing,
        generator: any NoteGenerating,
        fileStore: any RecordingFileStore,
        feedback: any AppFeedbackProviding = SilentAppFeedback(),
        requestSpeechAuthorization: @escaping @MainActor @Sendable () async -> Bool = AppCoordinator.systemSpeechAuthorization
    ) {
        self.capture = capture
        self.transcriber = transcriber
        self.generator = generator
        self.fileStore = fileStore
        self.feedback = feedback
        self.requestSpeechAuthorization = requestSpeechAuthorization
    }

    static func live() -> AppCoordinator {
        AppCoordinator(
            capture: SystemAudioCapture(),
            transcriber: LocalTranscriber(),
            generator: FoundationNoteGenerator(),
            fileStore: LocalRecordingFileStore(),
            feedback: BurritoAppFeedback.shared
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

    func start(
        options: RecordingOptions,
        destination: RecordingDestination = .newNote,
        context: ModelContext
    ) async {
        guard captureState == .idle else {
            lastError = .recordingAlreadyInProgress
            return
        }
        captureState = .preparing
        lastError = nil

        let existingNote: Note? = switch destination {
        case .newNote:
            nil
        case .appendToNote(let id):
            fetchNote(id: id, context: context)
        }
        if case .appendToNote = destination, existingNote == nil {
            failBeforeRecording(
                .storageFailed(
                    details: "The note to extend no longer exists. No recording was started."
                )
            )
            return
        }
        let languageIdentifier = existingNote?.languageIdentifier ?? options.languageIdentifier
        let recordingMode = existingNote?.recordingMode ?? options.mode

        let modelAvailability = await generator.availability(
            languageIdentifier: languageIdentifier
        )
        if case .failure(let error) = modelAvailability {
            failBeforeRecording(error)
            return
        }

        if transcriber.requiresSpeechAuthorization(for: languageIdentifier) {
            guard await requestSpeechAuthorization() else {
                failBeforeRecording(.speechRecognitionPermissionDenied)
                return
            }
        }

        let languageAvailability = await transcriber.verifyLanguage(languageIdentifier)
        if case .failure(let error) = languageAvailability {
            failBeforeRecording(error)
            return
        }

        let sessionID = UUID()
        guard case .success(let files) = fileStore.createSession(
            id: sessionID,
            mode: recordingMode
        ) else {
            failBeforeRecording(.storageFailed(details: "The recording directory could not be created."))
            return
        }

        let now = Date.now
        let note: Note
        if let existingNote {
            note = existingNote
            note.lifecycle = .recording
            note.processingStage = nil
            note.lastErrorMessage = nil
            note.retainsAudio = note.retainsAudio || options.retainsAudio
        } else {
            let newNote = Note(
                id: sessionID,
                lifecycle: .recording,
                createdAt: now,
                languageIdentifier: options.languageIdentifier,
                template: options.template,
                recordingMode: recordingMode,
                retainsAudio: options.retainsAudio
            )
            newNote.systemAudioRelativePath = files.systemAudioURL.map(
                fileStore.relativePath(for:)
            )
            newNote.microphoneAudioRelativePath = files.microphoneAudioURL.map(
                fileStore.relativePath(for:)
            )
            context.insert(newNote)
            note = newNote
        }

        do {
            try context.save()
        } catch {
            failBeforeRecording(.storageFailed(details: error.localizedDescription))
            return
        }

        switch await capture.start(
            files: files,
            mode: recordingMode,
            languageIdentifier: languageIdentifier
        ) {
        case .success:
            activeFiles = files
            activeNoteID = note.id
            appendsToExistingNote = existingNote != nil
            captureState = .recording(sessionID: sessionID, startedAt: now)
            elapsed = 0
            activity = .silent
            startTimer(startedAt: now)
            feedback.recordingStarted()
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
              let noteID = activeNoteID,
              let note = fetchNote(id: noteID, context: context)
        else {
            lastError = .noActiveRecording
            return
        }

        timerTask?.cancel()
        timerTask = nil
        activity = .silent
        captureState = .stopping(sessionID: sessionID)
        note.lifecycle = .processing
        note.processingStage = .preparingAudio
        let recordingDuration = Date.now.timeIntervalSince(startedAt)
        note.updatedAt = .now
        try? context.save()

        if case .failure(let error) = await capture.stop() {
            fail(note: note, error: error, context: context)
            return
        }
        feedback.recordingStopped()

        guard capture.hasMeaningfulAudio else {
            finishSilentRecording(note: note, files: files, context: context)
            return
        }

        note.duration = appendsToExistingNote
            ? note.duration + recordingDuration
            : recordingDuration
        note.processingStage = .transcribing
        try? context.save()

        var systemSegments: [TranscriptSegment] = []
        if let systemURL = files.systemAudioURL {
            let systemResult = await transcriber.transcribe(
                fileURL: systemURL,
                source: .system,
                languageIdentifier: note.languageIdentifier
            )
            guard case .success(let segments) = systemResult else {
                if case .failure(let error) = systemResult {
                    fail(note: note, error: error, context: context)
                }
                return
            }
            systemSegments = segments
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
        let newSegments = Transcript.merge(
            system: systemSegments,
            microphone: microphoneSegments
        )
        let combinedSegments: [TranscriptSegment]
        if appendsToExistingNote {
            let existingSegments = note.transcriptSegments
            let offset = existingSegments
                .map { $0.startTime + $0.duration }
                .max() ?? 0
            let appendedSegments = newSegments.map { segment in
                TranscriptSegment(
                    id: segment.id,
                    source: segment.source,
                    startTime: segment.startTime + offset,
                    duration: segment.duration,
                    text: segment.text
                )
            }
            combinedSegments = existingSegments + appendedSegments
        } else {
            combinedSegments = newSegments
        }
        note.replaceTranscript(
            with: combinedSegments,
            marksEdited: true
        )
        try? context.save()

        if note.retainsAudio {
            note.systemAudioRelativePath = files.systemAudioURL.map(
                fileStore.relativePath(for:)
            )
            note.microphoneAudioRelativePath = files.microphoneAudioURL.map(
                fileStore.relativePath(for:)
            )
        } else {
            if case .failure(let error) = fileStore.removeAudio(for: files) {
                note.lastErrorMessage = error.recoveryMessage
            } else {
                note.systemAudioRelativePath = nil
                note.microphoneAudioRelativePath = nil
            }
        }

        if appendsToExistingNote {
            await appendGeneratedNotes(
                from: newSegments,
                to: note,
                context: context
            )
        } else {
            await generate(note: note, context: context)
        }
        activeFiles = nil
        activeNoteID = nil
        appendsToExistingNote = false
        captureState = .idle
        elapsed = 0
        activity = .silent
    }

    private func finishSilentRecording(
        note: Note,
        files: RecordingFiles,
        context: ModelContext
    ) {
        if !note.retainsAudio {
            if case .failure(let error) = fileStore.removeAudio(for: files) {
                note.lastErrorMessage = error.recoveryMessage
            }
            if !appendsToExistingNote {
                note.systemAudioRelativePath = nil
                note.microphoneAudioRelativePath = nil
            }
        }
        note.lifecycle = .ready
        note.processingStage = nil
        note.updatedAt = .now
        try? context.save()
        activeFiles = nil
        activeNoteID = nil
        appendsToExistingNote = false
        captureState = .idle
        elapsed = 0
        activity = .silent
    }

    func generate(note: Note, context: ModelContext, undoManager: UndoManager? = nil) async {
        let oldTitle = note.title
        let oldBody = note.markdownBody
        let transcriptSegments = note.transcriptSegments
        let userNotes = note.userNotes
        let template = note.templateSnapshot
        let languageIdentifier = note.languageIdentifier

        note.lifecycle = .processing
        note.processingStage = .generatingNotes
        note.lastErrorMessage = nil
        try? context.save()

        async let generatedResult = generator.generate(
            segments: transcriptSegments,
            userNotes: userNotes,
            template: template,
            languageIdentifier: languageIdentifier
        )
        async let titleResult = generator.suggestTitle(
            segments: transcriptSegments,
            currentTitle: oldTitle,
            languageIdentifier: languageIdentifier
        )
        let (generatedResultValue, titleResultValue) = await (generatedResult, titleResult)

        switch generatedResultValue {
        case .success(let generated):
            note.title = await resolvedSuggestedTitle(
                initialResult: titleResultValue,
                segments: transcriptSegments,
                currentTitle: oldTitle,
                languageIdentifier: languageIdentifier
            ) ?? generated.title
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
        if note.lifecycle == .ready {
            feedback.noteReady(title: note.title)
        }
    }

    private func appendGeneratedNotes(
        from segments: [TranscriptSegment],
        to note: Note,
        context: ModelContext
    ) async {
        let existingTitle = note.title
        let existingBody = note.markdownBody
        let hadUserEdits = note.userEditedNotes
        let completeTranscript = note.transcriptSegments
        let userNotes = note.userNotes
        let template = note.templateSnapshot
        let languageIdentifier = note.languageIdentifier

        note.lifecycle = .processing
        note.processingStage = .generatingNotes
        note.lastErrorMessage = nil
        try? context.save()

        async let generatedResult = generator.generate(
            segments: segments,
            userNotes: userNotes,
            template: template,
            languageIdentifier: languageIdentifier
        )
        async let titleResult = generator.suggestTitle(
            segments: completeTranscript,
            currentTitle: existingTitle,
            languageIdentifier: languageIdentifier
        )
        let (generatedResultValue, titleResultValue) = await (generatedResult, titleResult)

        switch generatedResultValue {
        case .success(let generated):
            let updatedTitle = await resolvedSuggestedTitle(
                initialResult: titleResultValue,
                segments: completeTranscript,
                currentTitle: existingTitle,
                languageIdentifier: languageIdentifier
            ) ?? existingTitle
            let appendedBody = """
                ## \(generated.title)

                \(generated.markdown)
                """
            note.title = updatedTitle
            note.markdownBody = existingBody.trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
                ? generated.markdown
                : "\(existingBody)\n\n---\n\n\(appendedBody)"
            note.generatedFromTranscriptRevision = note.transcriptRevision
            note.userEditedNotes = hadUserEdits
            note.lifecycle = .ready
            note.processingStage = nil
            note.updatedAt = .now
        case .failure(let error):
            note.lifecycle = .recoverable
            note.processingStage = nil
            note.lastErrorMessage = error.recoveryMessage
            lastError = error
        }
        try? context.save()
        if note.lifecycle == .ready {
            feedback.noteReady(title: note.title)
        }
    }

    private func resolvedSuggestedTitle(
        initialResult: Result<String, BurritoError>,
        segments: [TranscriptSegment],
        currentTitle: String,
        languageIdentifier: String
    ) async -> String? {
        let result: Result<String, BurritoError>
        switch initialResult {
        case .success:
            result = initialResult
        case .failure:
            result = await generator.suggestTitle(
                segments: segments,
                currentTitle: currentTitle,
                languageIdentifier: languageIdentifier
            )
        }

        guard case .success(let candidate) = result else { return nil }
        let normalizedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCurrentTitle = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCandidate.isEmpty,
              normalizedCandidate.localizedCaseInsensitiveCompare(normalizedCurrentTitle) != .orderedSame
        else {
            return nil
        }
        return normalizedCandidate
    }

    func dismissFailure() {
        if case .failed = captureState {
            captureState = .idle
            activeNoteID = nil
            appendsToExistingNote = false
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
        activity = .silent
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
        appendsToExistingNote = false
        activity = .silent
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
                try? await Task.sleep(for: .milliseconds(80))
                guard !Task.isCancelled else { return }
                guard let self else { return }
                elapsed = Date.now.timeIntervalSince(startedAt)
                activity = capture.activity
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
