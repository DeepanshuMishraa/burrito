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
    private(set) var silentFor: TimeInterval = 0
    private(set) var activeCalendarEvent: CalendarEventSnapshot?
    private(set) var smartStopStatus: SmartStopStatus = .monitoring
    private(set) var isPaused = false
    private(set) var liveTranscript = LiveTranscriptSnapshot.preparing
    private(set) var lastError: BurritoError?
    private(set) var isInstallingLanguageAsset = false

    private let capture: any AudioCapturing
    private let transcriber: any Transcribing
    private let generator: any NoteGenerating
    private let fileStore: any RecordingFileStore
    private let feedback: any AppFeedbackProviding
    private let mediaAudioExtractor: any MediaAudioExtracting
    private let speakerDiarizer: any SpeakerDiarizing
    private let requestSpeechAuthorization: @MainActor @Sendable () async -> Bool
    private let now: @MainActor @Sendable () -> Date
    private var activeFiles: RecordingFiles?
    private var appendsToExistingNote = false
    private var timerTask: Task<Void, Never>?
    private var pausedAt: Date?
    private var accumulatedPausedDuration: TimeInterval = 0
    private var studySession: StudySession?
    private var studyRotationInFlight = false
    private var studyRotationTask: Task<Void, Never>?
    /// Per-note chains of background segment processing. Each finished
    /// segment queues behind the previous one for the same note so appended
    /// segments are never dropped and never race each other on the note.
    private var processingChains: [UUID: ProcessingChain] = [:]
    /// Notes whose regeneration was requested from the background (notes
    /// list). Their processing UI is suppressed so the user never sees a
    /// generation screen they did not opt into.
    private(set) var backgroundGenerationNoteIDs: Set<UUID> = []
    /// Serializes model inference app-wide: on-device models run one request
    /// chain at a time, so a finished study segment can never collide with a
    /// manual regeneration, an import, or the concurrent title pass.
    private let generationGate = GenerationGate()

    private struct StudySession {
        let id: UUID
        let folderID: UUID
        let options: RecordingOptions
    }

    /// Serial queue for model inference. Only the model calls are gated:
    /// note state mutations stay in the caller's task, so observers never
    /// see a note half-updated between generation and its follow-up work.
    private actor GenerationGate {
        private var tail: Task<Void, Never> = Task {}

        func run<T: Sendable>(
            _ operation: @escaping @MainActor () async -> T
        ) async -> T {
            let previous = tail
            let task = Task { @MainActor in
                await previous.value
                return await operation()
            }
            tail = Task { @MainActor in
                _ = await task.value
            }
            return await task.value
        }
    }

    /// Whether note generation currently routes through a terminal agent
    /// harness. Harness CLI processes run independently, so concurrent note
    /// generations are safe and must NOT be serialized — each `opencode run`
    /// is a separate process. Only in-process models (Apple Intelligence,
    /// MLX) share one session and must run one request chain at a time.
    private var usesAgentHarnessBackend: Bool {
        guard let harness = AgentHarnessStore.currentSelection() else { return false }
        return harness.resolveExecutableURL() != nil
    }

    /// Runs a model operation, serialized only when the backend is an
    /// in-process model. Agent-harness backends run in parallel so two notes
    /// regenerate at the same time instead of queueing behind each other.
    private func runGeneration<T: Sendable>(
        _ operation: @escaping @MainActor () async -> T
    ) async -> T {
        if usesAgentHarnessBackend {
            return await operation()
        }
        return await generationGate.run(operation)
    }

    /// Holds the tail of a note's background processing chain. All access
    /// happens on the main actor (the chain tasks inherit it).
    private final class ProcessingChain: @unchecked Sendable {
        var task: Task<Void, Never>?
        var sequence = 0
    }

    private static let studySegmentLimit: TimeInterval = 10 * 60
    /// Generation attempts for one note. Transient failures (a busy on-device
    /// model, a timed-out agent harness) resolve on retry so study segments
    /// finish their notes without a manual "Generate again".
    private static let maxGenerationAttempts = 3
    /// Backoff seconds before retry `n` (1-based): 1s, then 2s.
    private static let generationRetryBackoff: [Int: TimeInterval] = [1: 1, 2: 2]
    /// Prior session context is bounded so it never dominates the prompt
    /// budget of small on-device models.
    private static let priorContextCharacterBudget = 2_500

    init(
        capture: any AudioCapturing,
        transcriber: any Transcribing,
        generator: any NoteGenerating,
        fileStore: any RecordingFileStore,
        feedback: any AppFeedbackProviding = SilentAppFeedback(),
        mediaAudioExtractor: any MediaAudioExtracting = LocalMediaAudioExtractor(),
        speakerDiarizer: any SpeakerDiarizing = LocalSpeakerDiarizer(),
        requestSpeechAuthorization: @escaping @MainActor @Sendable () async -> Bool = AppCoordinator.systemSpeechAuthorization,
        now: @escaping @MainActor @Sendable () -> Date = { .now }
    ) {
        self.capture = capture
        self.transcriber = transcriber
        self.generator = generator
        self.fileStore = fileStore
        self.feedback = feedback
        self.mediaAudioExtractor = mediaAudioExtractor
        self.speakerDiarizer = speakerDiarizer
        self.requestSpeechAuthorization = requestSpeechAuthorization
        self.now = now
    }

    func importMedia(
        fileURL: URL,
        options: RecordingOptions,
        context: ModelContext
    ) async -> Result<UUID, BurritoError> {
        guard captureState == .idle else {
            return .failure(.recordingAlreadyInProgress)
        }
        captureState = .preparing
        lastError = nil

        let modelAvailability = await generator.availability(
            languageIdentifier: options.languageIdentifier
        )
        if case .failure(let error) = modelAvailability {
            failBeforeRecording(error)
            return .failure(error)
        }
        if transcriber.requiresSpeechAuthorization(for: options.languageIdentifier) {
            guard await requestSpeechAuthorization() else {
                let error = BurritoError.speechRecognitionPermissionDenied
                failBeforeRecording(error)
                return .failure(error)
            }
        }
        let languageAvailability = await transcriber.verifyLanguage(options.languageIdentifier)
        if case .failure(let error) = languageAvailability {
            failBeforeRecording(error)
            return .failure(error)
        }

        let sessionID = UUID()
        guard case .success(let files) = fileStore.createSession(
            id: sessionID,
            mode: .listenAlong
        ) else {
            let error = BurritoError.storageFailed(
                details: "A workspace for the imported media could not be created."
            )
            failBeforeRecording(error)
            return .failure(error)
        }
        guard let transcriptionURL = files.systemTranscriptionURL else {
            let error = BurritoError.storageFailed(
                details: "The import workspace has no transcription destination."
            )
            failBeforeRecording(error)
            return .failure(error)
        }

        let note = Note(
            id: sessionID,
            lifecycle: .processing,
            title: fileURL.deletingPathExtension().lastPathComponent,
            createdAt: now(),
            languageIdentifier: options.languageIdentifier,
            template: options.template,
            recordingMode: .listenAlong,
            // Imported original media is already at natural tempo; the capture-only rate is ignored.
            playbackRate: .natural,
            retainsAudio: options.retainsAudio
        )
        note.processingStage = .preparingAudio
        context.insert(note)
        do {
            try context.save()
        } catch {
            let failure = BurritoError.storageFailed(details: error.localizedDescription)
            failImport(note: note, files: files, error: failure, context: context)
            return .failure(failure)
        }

        let extraction = await mediaAudioExtractor.extract(
            sourceURL: fileURL,
            transcriptionURL: transcriptionURL,
            retainedAudioURL: options.retainsAudio ? files.systemAudioURL : nil
        )
        guard case .success(let importedAudio) = extraction else {
            if case .failure(let error) = extraction {
                failImport(note: note, files: files, error: error, context: context)
                return .failure(error)
            }
            let error = BurritoError.mediaImportFailed(details: "The extraction result was invalid.")
            failImport(note: note, files: files, error: error, context: context)
            return .failure(error)
        }

        note.duration = importedAudio.duration
        note.processingStage = .transcribing
        try? context.save()
        let transcription = await transcriber.transcribe(
            input: .importedMedia(fileURL: transcriptionURL, source: .system),
            languageIdentifier: note.languageIdentifier
        )
        guard case .success(let segments) = transcription else {
            if case .failure(let error) = transcription {
                failImport(note: note, files: files, error: error, context: context)
                return .failure(error)
            }
            let error = BurritoError.transcriptionFailed(details: "The import transcript was unavailable.")
            failImport(note: note, files: files, error: error, context: context)
            return .failure(error)
        }

        note.processingStage = .organizing
        note.replaceTranscript(with: segments, marksEdited: true)
        if options.retainsAudio {
            note.systemAudioRelativePath = files.systemAudioURL.map(
                fileStore.relativePath(for:)
            )
            if case .failure(let error) = fileStore.removeTranscriptionAudio(for: files) {
                note.lastErrorMessage = error.recoveryMessage
            }
        } else if case .failure(let error) = fileStore.removeAudio(for: files) {
            note.lastErrorMessage = error.recoveryMessage
        }
        try? context.save()

        await generate(note: note, context: context)
        captureState = .idle
        if note.lifecycle == .ready {
            return .success(note.id)
        }
        let error = lastError ?? .generationFailed(
            details: "The transcript is preserved, but note generation did not finish. Retry generation from the note."
        )
        return .failure(error)
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
            for note in notes
            where (note.lifecycle == .recording || note.lifecycle == .processing)
                && note.id != activeNoteID
            {
                note.lifecycle = .recoverable
                note.processingStage = nil
                note.lastErrorMessage = "Burrito closed before this recording finished. Existing audio is preserved; retry processing when ready."
            }
            try context.save()
            healUnfinishedNotes(in: notes, context: context)
        } catch {
            lastError = .storageFailed(details: error.localizedDescription)
        }
    }

    /// Auto-finishes notes whose transcript was preserved but whose notes
    /// never generated (an interrupted or failed background run): their
    /// generation restarts in the background on launch, so a study segment
    /// resolves without the user clicking "Generate again".
    private func healUnfinishedNotes(in notes: [Note], context: ModelContext) {
        for note in notes
        where note.lifecycle == .recoverable
            && note.processingStage == nil
            && !note.userEditedNotes
            && note.notesMayBeOutdated
            && !note.transcriptSegments.isEmpty
            && note.lastErrorMessage != nil
        {
            note.lastErrorMessage = nil
            Task { [weak self] in
                await self?.generateInBackground(note: note, context: context)
            }
        }
    }

    func startStudyMode(
        name: String,
        folderID: UUID? = nil,
        options: RecordingOptions,
        context: ModelContext
    ) async -> Bool {
        guard captureState == .idle else {
            lastError = .recordingAlreadyInProgress
            return false
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty || folderID != nil else {
            lastError = .storageFailed(details: "A study session needs a name before recording can start.")
            return false
        }

        var createdFolder = false
        let folder: Folder
        if let folderID,
           let existing = fetchFolder(id: folderID, context: context) {
            // Continuing an earlier study session: new 10-minute notes keep
            // landing in the same folder.
            folder = existing
        } else {
            let newFolder = Folder(
                name: trimmedName,
                order: (try? context.fetch(FetchDescriptor<Folder>()).count) ?? 0
            )
            context.insert(newFolder)
            try? context.save()
            folder = newFolder
            createdFolder = true
        }
        studySession = StudySession(id: UUID(), folderID: folder.id, options: options)
        studyRotationInFlight = false
        await start(options: options, context: context)
        let started = captureState.isRecording && activeNoteID != nil
        if !started {
            if createdFolder {
                context.delete(folder)
                try? context.save()
            }
            studySession = nil
        }
        return started
    }

    func start(
        options: RecordingOptions,
        destination: RecordingDestination = .newNote,
        studySessionID: UUID? = nil,
        context: ModelContext
    ) async {
        defer {
            if let studySessionID,
               !(captureState.isRecording && studySession?.id == studySessionID) {
                studySession = nil
                studyRotationInFlight = false
                studyRotationTask = nil
            }
        }
        guard captureState == .idle else {
            lastError = .recordingAlreadyInProgress
            return
        }
        captureState = .preparing
        lastError = nil

        let existingNote: Note? = switch destination {
        case .newNote, .calendarEvent:
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

        let now = now()
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
                title: destination.calendarEvent?.title ?? "New Recording",
                createdAt: now,
                languageIdentifier: options.languageIdentifier,
                template: options.template,
                recordingMode: recordingMode,
                playbackRate: options.playbackRate,
                retainsAudio: options.retainsAudio,
                calendarEvent: destination.calendarEvent
            )
            newNote.systemAudioRelativePath = files.systemAudioURL.map(
                fileStore.relativePath(for:)
            )
            newNote.microphoneAudioRelativePath = files.microphoneAudioURL.map(
                fileStore.relativePath(for:)
            )
            newNote.manualOrder = nextManualOrder(after: now, context: context)
            if newNote.manualOrder != nil {
                newNote.manualOrderDay = Calendar.current.startOfDay(for: now)
            }
            // Study-session segments always carry a manual position: their
            // day group then orders them by creation time, never by whichever
            // segment happened to finish processing last.
            if newNote.manualOrder == nil, studySession != nil {
                newNote.manualOrder = 0
                newNote.manualOrderDay = Calendar.current.startOfDay(for: now)
            }
            context.insert(newNote)
            if let studySession,
               let folder = fetchFolder(id: studySession.folderID, context: context) {
                newNote.folder = folder
            }
            note = newNote
        }

        do {
            try context.save()
        } catch {
            failBeforeRecording(.storageFailed(details: error.localizedDescription))
            return
        }

        guard !Task.isCancelled,
              studySessionID == nil || studySession?.id == studySessionID
        else {
            if existingNote == nil {
                context.delete(note)
            }
            _ = fileStore.removeAudio(for: files)
            try? context.save()
            finishCaptureSession()
            lastError = nil
            return
        }

        switch await capture.start(
            files: files,
            mode: recordingMode,
            languageIdentifier: languageIdentifier
        ) {
        case .success:
            guard !Task.isCancelled,
                  studySessionID == nil || studySession?.id == studySessionID
            else {
                switch await capture.stop() {
                case .success:
                    if existingNote == nil {
                        context.delete(note)
                    }
                    _ = fileStore.removeAudio(for: files)
                    try? context.save()
                    finishCaptureSession()
                    lastError = nil
                case .failure(let error):
                    note.lifecycle = .recoverable
                    note.processingStage = nil
                    note.lastErrorMessage = error.recoveryMessage
                    try? context.save()
                    lastError = error
                    captureState = .failed(
                        sessionID: note.id,
                        message: error.recoveryMessage
                    )
                }
                return
            }
            activeFiles = files
            activeNoteID = note.id
            appendsToExistingNote = existingNote != nil
            activeCalendarEvent = note.calendarEvent
            captureState = .recording(sessionID: sessionID, startedAt: now)
            elapsed = 0
            activity = .silent
            isPaused = false
            pausedAt = nil
            accumulatedPausedDuration = 0
            liveTranscript = capture.liveTranscript
            silentFor = 0
            smartStopStatus = .monitoring
            startTimer(startedAt: now, context: context)
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

    func pause() async {
        guard captureState.isRecording, !isPaused else { return }
        switch await capture.pause() {
        case .success:
            isPaused = true
            pausedAt = now()
            activity = .silent
        case .failure(let error):
            lastError = error
        }
    }

    func resume() async {
        guard captureState.isRecording, isPaused else { return }
        switch await capture.resume() {
        case .success:
            if let pausedAt {
                accumulatedPausedDuration += max(0, now().timeIntervalSince(pausedAt))
            }
            pausedAt = nil
            isPaused = false
        case .failure(let error):
            lastError = error
        }
    }

    func stop(context: ModelContext) async {
        studySession = nil
        studyRotationInFlight = false
        studyRotationTask?.cancel()
        studyRotationTask = nil
        guard captureState.isRecording else { return }
        await stopCapture(context: context, continueStudy: false)
    }

    private func stopCapture(
        context: ModelContext,
        continueStudy: Bool
    ) async {
        guard !continueStudy || !Task.isCancelled else { return }
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
        silentFor = 0
        captureState = .stopping(sessionID: sessionID)
        note.lifecycle = .processing
        note.processingStage = .preparingAudio
        // Computed before finishCaptureSession() resets the pause accounting.
        let recordingDuration = activeRecordingDuration(since: startedAt, at: now())
        let appendsToExisting = appendsToExistingNote
        isPaused = false
        pausedAt = nil
        note.updatedAt = .now
        try? context.save()

        if case .failure(let error) = await capture.stop() {
            if continueStudy {
                studySession = nil
                studyRotationInFlight = false
                studyRotationTask = nil
            }
            fail(note: note, error: error, context: context)
            return
        }
        liveTranscript = capture.liveTranscript
        feedback.recordingStopped()
        let completedAudioWasMeaningful = capture.hasMeaningfulAudio
        let nextStudySession = continueStudy && !Task.isCancelled ? studySession : nil
        // The capture device is released; processing below runs in the
        // background so a new recording can start immediately.
        finishCaptureSession()

        if let nextStudySession {
            studyRotationInFlight = false
            await start(
                options: nextStudySession.options,
                studySessionID: nextStudySession.id,
                context: context
            )
            studyRotationTask = nil
            if !(captureState.isRecording && studySession?.id == nextStudySession.id) {
                studySession = nil
                studyRotationInFlight = false
            }
        }

        guard completedAudioWasMeaningful else {
            finishSilentRecording(
                note: note,
                files: files,
                appendsToExistingNote: appendsToExisting,
                context: context
            )
            return
        }

        note.duration = appendsToExisting
            ? note.duration + recordingDuration
            : recordingDuration
        note.processingStage = .transcribing
        try? context.save()

        // Process the finished segment in a task owned by this note, never by
        // the rotation or stop caller. A later Stop (or the next 10-minute
        // rotation) cancels only the capture handoff, so the completed
        // segment always transcribes and generates its note in the
        // background while the next segment records. Segments appended to
        // the same note queue behind any in-flight processing so nothing is
        // silently dropped.
        let chain = processingChains[note.id] ?? ProcessingChain()
        processingChains[note.id] = chain
        let previousTask = chain.task
        chain.sequence += 1
        let mySequence = chain.sequence
        chain.task = Task { [weak self] in
            await previousTask?.value
            guard let self else { return }
            await self.processFinishedRecording(
                note: note,
                files: files,
                appendsToExisting: appendsToExisting,
                context: context
            )
            // Remove the chain only if we are still its tail: a newer
            // segment may have queued behind us.
            if self.processingChains[note.id] === chain,
               chain.sequence == mySequence {
                self.processingChains[note.id] = nil
            }
        }
    }

    private func processFinishedRecording(
        note: Note,
        files: RecordingFiles,
        appendsToExisting: Bool,
        context: ModelContext
    ) async {
        var processingWarnings: [String] = []
        var systemSegments: [TranscriptSegment] = []
        let systemURL = existingPCMURL(files.systemTranscriptionURL)
            ?? files.systemAudioURL
        if let systemURL {
            let systemResult = await transcriber.transcribe(
                input: .systemCapture(
                    fileURL: systemURL,
                    playbackRate: note.playbackRate
                ),
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
        let microphoneURL = existingPCMURL(files.microphoneTranscriptionURL)
            ?? files.microphoneAudioURL
        if let microphoneURL {
            let microphoneResult = await transcriber.transcribe(
                input: .natural(fileURL: microphoneURL, source: .microphone),
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

        if note.recordingMode == .meeting,
           let systemURL,
           FileManager.default.fileExists(atPath: systemURL.path()),
           !systemSegments.isEmpty {
            note.processingStage = .identifyingSpeakers
            try? context.save()
            switch await speakerDiarizer.assignSpeakers(
                audioURL: systemURL,
                to: systemSegments
            ) {
            case .success(let attributed):
                systemSegments = attributed
            case .failure(let error):
                processingWarnings.append(error.recoveryMessage)
                note.lastErrorMessage = processingWarnings.joined(separator: "\n\n")
            }
        }
        microphoneSegments = SpeakerAttribution.assign(
            turns: [],
            to: microphoneSegments
        )

        if case .failure(let error) = fileStore.removeTranscriptionAudio(for: files) {
            processingWarnings.append(error.recoveryMessage)
            note.lastErrorMessage = processingWarnings.joined(separator: "\n\n")
        }

        note.processingStage = .organizing
        let newSegments = Transcript.merge(
            system: systemSegments,
            microphone: microphoneSegments
        )
        let combinedSegments: [TranscriptSegment]
        if appendsToExisting {
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
                    text: segment.text,
                    speakerName: segment.speakerName
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
        // The transcript is persisted before generation so the note always
        // keeps its source material — "Generate Again" works even if the
        // model step fails.
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
                processingWarnings.append(error.recoveryMessage)
                note.lastErrorMessage = processingWarnings.joined(separator: "\n\n")
            } else {
                note.systemAudioRelativePath = nil
                note.microphoneAudioRelativePath = nil
            }
        }

        if appendsToExisting {
            await appendGeneratedNotes(
                from: newSegments,
                to: note,
                context: context
            )
        } else {
            await generate(note: note, context: context)
        }
        if !processingWarnings.isEmpty {
            var messages = processingWarnings
            if let generationMessage = note.lastErrorMessage {
                messages.insert(generationMessage, at: 0)
            }
            note.lastErrorMessage = messages.joined(separator: "\n\n")
            try? context.save()
        }
    }

    private func existingPCMURL(_ url: URL?) -> URL? {
        guard let url, FileManager.default.fileExists(atPath: url.path()) else { return nil }
        return url
    }

    private func finishCaptureSession() {
        activeFiles = nil
        activeNoteID = nil
        activeCalendarEvent = nil
        appendsToExistingNote = false
        captureState = .idle
        elapsed = 0
        activity = .silent
        isPaused = false
        pausedAt = nil
        accumulatedPausedDuration = 0
        silentFor = 0
        smartStopStatus = .monitoring
    }

    private func finishSilentRecording(
        note: Note,
        files: RecordingFiles,
        appendsToExistingNote: Bool,
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
    }

    func generate(note: Note, context: ModelContext, undoManager: UndoManager? = nil) async {
        await performGeneration(
            note: note,
            context: context,
            undoManager: undoManager
        )
    }

    private func performGeneration(
        note: Note,
        context: ModelContext,
        undoManager: UndoManager?
    ) async {
        let oldTitle = note.title
        let oldBody = note.markdownBody
        let transcriptSegments = note.transcriptSegments
        let userNotes = note.userNotes
        let calendarEvent = note.calendarEvent
        let template = note.templateSnapshot
        let languageIdentifier = note.languageIdentifier
        let priorContext = priorSessionContext(for: note)

        note.lifecycle = .processing
        note.processingStage = .generatingNotes
        note.lastErrorMessage = nil
        try? context.save()

        // Transient failures retry in the background so study segments
        // resolve their notes without a manual click. The note keeps its
        // transcript across attempts; the revision anchor only moves on
        // success, so the "notes may be outdated" state never appears
        // while retries are still running.
        var generated: GeneratedNote?
        var generationError: BurritoError?
        for attempt in 0..<Self.maxGenerationAttempts {
            if attempt > 0 {
                try? await Task.sleep(
                    for: .milliseconds(
                        (Self.generationRetryBackoff[attempt] ?? 1) * 1_000
                    )
                )
            }
            let result = await runGeneration { () -> Result<GeneratedNote, BurritoError> in
                await self.generator.generate(
                    segments: transcriptSegments,
                    userNotes: userNotes,
                    meetingContext: calendarEvent,
                    template: template,
                    languageIdentifier: languageIdentifier,
                    priorContext: priorContext
                )
            }
            switch result {
            case .success(let value):
                generated = value
            case .failure(let error):
                generationError = error
            }
            if generated != nil { break }
        }

        guard let generated else {
            let error = generationError ?? .generationFailed(
                details: "Notes could not be generated right now. Your transcript is preserved; choose Generate again."
            )
            note.lifecycle = .recoverable
            note.processingStage = nil
            note.lastErrorMessage = error.recoveryMessage
            // A background failure (regeneration or a finished study segment)
            // must not raise the global error overlay while the user is
            // recording or viewing a different note.
            if activeNoteID == note.id {
                lastError = error
            }
            try? context.save()
            return
        }

        // The title pass runs through the same gate (never alongside another
        // model request) but after generation, so two model sessions are
        // never active at the same time.
        let resolvedTitle = await runGeneration { () -> String? in
            if let calendarEvent {
                return self.calendarAwareTitle(
                    event: calendarEvent,
                    currentTitle: oldTitle
                )
            }
            let titleResult = await self.suggestedTitle(
                segments: transcriptSegments,
                currentTitle: oldTitle,
                languageIdentifier: languageIdentifier,
                calendarEvent: calendarEvent
            )
            return await self.resolvedSuggestedTitle(
                initialResult: titleResult,
                segments: transcriptSegments,
                currentTitle: oldTitle,
                languageIdentifier: languageIdentifier
            )
        }
        note.title = resolvedTitle ?? generated.title
        note.markdownBody = generated.markdown
        note.generatedFromTranscriptRevision = note.transcriptRevision
        note.userEditedNotes = false
        note.lifecycle = .ready
        note.processingStage = nil
        undoManager?.registerUndo(withTarget: note) { target in
            target.title = oldTitle
            target.markdownBody = oldBody
            target.userEditedNotes = true
        }
        try? context.save()
        if note.lifecycle == .ready {
            feedback.noteReady(title: note.title)
        }
    }

    /// Continuity material for a folder-backed note: the most recent sibling
    /// note's generated notes (or its raw transcript when notes are not ready
    /// yet), bounded to a small budget. Study-mode 10-minute segments use
    /// this so the next segment's notes stay consistent with the previous one.
    private func priorSessionContext(for note: Note) -> String? {
        guard let siblings = note.folder?.notes else { return nil }
        let previous = siblings
            .filter { $0.id != note.id && $0.deletedAt == nil }
            .max { $0.createdAt < $1.createdAt }
        guard let previous else { return nil }
        let generated = GeneratedNote
            .strippedSourceArtifacts(from: previous.markdownBody)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let content = generated.isEmpty
            ? Transcript.rendered(previous.transcriptSegments)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            : generated
        guard !content.isEmpty else { return nil }
        return String(content.prefix(Self.priorContextCharacterBudget))
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
        let calendarEvent = note.calendarEvent
        let template = note.templateSnapshot
        let languageIdentifier = note.languageIdentifier

        note.lifecycle = .processing
        note.processingStage = .generatingNotes
        note.lastErrorMessage = nil
        try? context.save()

        let generatedResult = await runGeneration { () -> Result<GeneratedNote, BurritoError> in
            await self.generator.generate(
                segments: segments,
                userNotes: userNotes,
                meetingContext: calendarEvent,
                template: template,
                languageIdentifier: languageIdentifier
            )
        }
        let resolvedTitle = await runGeneration { () -> String? in
            if let calendarEvent {
                return self.calendarAwareTitle(
                    event: calendarEvent,
                    currentTitle: existingTitle
                )
            }
            let titleResult = await self.suggestedTitle(
                segments: completeTranscript,
                currentTitle: existingTitle,
                languageIdentifier: languageIdentifier,
                calendarEvent: calendarEvent
            )
            return await self.resolvedSuggestedTitle(
                initialResult: titleResult,
                segments: completeTranscript,
                currentTitle: existingTitle,
                languageIdentifier: languageIdentifier
            )
        }

        switch generatedResult {
        case .success(let generated):
            note.title = resolvedTitle ?? existingTitle
            let appendedBody = """
                ## \(generated.title)

                \(generated.markdown)
                """
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
            if activeNoteID == note.id {
                lastError = error
            }
        }
        try? context.save()
        if note.lifecycle == .ready {
            feedback.noteReady(title: note.title)
        }
    }

    /// Regenerates a note without any processing UI: used by the notes list
    /// and the note detail's "Generate again". The note keeps its current
    /// appearance; the caller surfaces the outcome (toast).
    func generateInBackground(
        note: Note,
        context: ModelContext,
        undoManager: UndoManager? = nil
    ) async {
        backgroundGenerationNoteIDs.insert(note.id)
        defer { backgroundGenerationNoteIDs.remove(note.id) }
        await generate(note: note, context: context, undoManager: undoManager)
    }

    private func suggestedTitle(
        segments: [TranscriptSegment],
        currentTitle: String,
        languageIdentifier: String,
        calendarEvent: CalendarEventSnapshot?
    ) async -> Result<String, BurritoError> {
        if let calendarEvent {
            return .success(
                calendarAwareTitle(event: calendarEvent, currentTitle: currentTitle)
            )
        }
        return await generator.suggestTitle(
            segments: segments,
            currentTitle: currentTitle,
            languageIdentifier: languageIdentifier
        )
    }

    private func calendarAwareTitle(
        event: CalendarEventSnapshot,
        currentTitle: String
    ) -> String {
        let current = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if current.isEmpty || current == "New Recording" {
            return event.title
        }
        return current
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

    func keepRecording() {
        smartStopStatus = .dismissed
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
        isPaused = false
        pausedAt = nil
        accumulatedPausedDuration = 0
        liveTranscript = .preparing
        silentFor = 0
        activeCalendarEvent = nil
        smartStopStatus = .monitoring
        lastError = error
    }

    private func failImport(
        note: Note,
        files: RecordingFiles,
        error: BurritoError,
        context: ModelContext
    ) {
        _ = fileStore.removeAudio(for: files)
        context.delete(note)
        try? context.save()
        failBeforeRecording(error)
    }

    private func fail(note: Note, error: BurritoError, context: ModelContext) {
        note.lifecycle = .recoverable
        note.processingStage = nil
        note.lastErrorMessage = error.recoveryMessage
        try? context.save()
        guard activeNoteID == note.id else { return }
        lastError = error
        captureState = .failed(sessionID: note.id, message: error.recoveryMessage)
        activeFiles = nil
        activeCalendarEvent = nil
        appendsToExistingNote = false
        activity = .silent
        isPaused = false
        pausedAt = nil
        accumulatedPausedDuration = 0
        silentFor = 0
        smartStopStatus = .monitoring
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

    /// Manual position for a brand-new note: on top of its day group when
    /// that day has already been manually reordered, otherwise no manual
    /// order (the default updated-first ordering applies). The day bounds
    /// match the timeline's grouping, which uses `updatedAt`.
    private func nextManualOrder(after date: Date, context: ModelContext) -> Int? {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else {
            return nil
        }
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate {
                $0.manualOrder != nil
                    && $0.updatedAt >= day
                    && $0.updatedAt < nextDay
            }
        )
        guard let notes = try? context.fetch(descriptor),
              let minimum = notes
                  .filter(\.hasValidManualOrder)
                  .compactMap(\.manualOrder)
                  .min()
        else {
            return nil
        }
        return minimum - 1
    }

    private func fetchFolder(id: UUID, context: ModelContext) -> Folder? {
        let requestedID = id
        let descriptor = FetchDescriptor<Folder>(
            predicate: #Predicate { $0.id == requestedID }
        )
        return try? context.fetch(descriptor).first
    }

    private func startTimer(startedAt: Date, context: ModelContext) {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            guard let initialTick = self?.now() else { return }
            var lastTick = initialTick
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(80))
                guard !Task.isCancelled else { return }
                guard let self else { return }
                let now = now()
                let tickDuration = max(0, now.timeIntervalSince(lastTick))
                lastTick = now
                elapsed = activeRecordingDuration(since: startedAt, at: now)
                liveTranscript = capture.liveTranscript
                activity = isPaused ? .silent : capture.activity
                if studySession != nil,
                   !studyRotationInFlight,
                   elapsed >= Self.studySegmentLimit {
                    studyRotationInFlight = true
                    studyRotationTask = Task { [weak self] in
                        guard let self, !Task.isCancelled else { return }
                        await stopCapture(context: context, continueStudy: true)
                    }
                    return
                }
                if isPaused {
                    continue
                } else if max(activity.system, activity.microphone) >= 0.04 {
                    silentFor = 0
                } else {
                    silentFor += tickDuration
                }
                if SmartStopPolicy.decision(
                    now: now,
                    eventEnd: activeCalendarEvent?.endDate,
                    recordingElapsed: elapsed,
                    silentFor: silentFor,
                    alreadySuggested: smartStopStatus.wasSuggested
                ) == .suggestStop {
                    smartStopStatus = .suggested
                    feedback.smartStopSuggested(
                        title: activeCalendarEvent?.title ?? "Your recording"
                    )
                }
            }
        }
    }

    private func activeRecordingDuration(since startedAt: Date, at currentDate: Date) -> TimeInterval {
        let currentPauseDuration = pausedAt.map {
            max(0, currentDate.timeIntervalSince($0))
        } ?? 0
        return max(
            0,
            currentDate.timeIntervalSince(startedAt)
                - accumulatedPausedDuration
                - currentPauseDuration
        )
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
