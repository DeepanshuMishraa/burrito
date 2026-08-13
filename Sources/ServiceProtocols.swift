import AI
import Foundation

@MainActor
protocol AudioCapturing: AnyObject {
    var activity: AudioActivity { get }
    var hasMeaningfulAudio: Bool { get }
    var liveTranscript: LiveTranscriptSnapshot { get }
    func start(
        files: RecordingFiles,
        mode: RecordingMode,
        languageIdentifier: String
    ) async -> Result<Void, BurritoError>
    func pause() async -> Result<Void, BurritoError>
    func resume() async -> Result<Void, BurritoError>
    func stop() async -> Result<Void, BurritoError>
}

extension AudioCapturing {
    var liveTranscript: LiveTranscriptSnapshot {
        LiveTranscriptSnapshot(
            availability: .unavailable(reason: "Live transcription is unavailable."),
            passages: []
        )
    }
}

struct AudioActivity: Equatable, Sendable {
    var system: Double
    var microphone: Double

    static let silent = AudioActivity(system: 0, microphone: 0)
}

protocol Transcribing: Sendable {
    func requiresSpeechAuthorization(for identifier: String) -> Bool
    func verifyLanguage(_ identifier: String) async -> Result<Void, BurritoError>
    func installLanguageAsset(_ identifier: String) async -> Result<Void, BurritoError>
    func transcribe(
        input: TranscriptionInput,
        languageIdentifier: String
    ) async -> Result<[TranscriptSegment], BurritoError>
}

protocol SpeakerDiarizing: Sendable {
    func assignSpeakers(
        audioURL: URL,
        to segments: [TranscriptSegment]
    ) async -> Result<[TranscriptSegment], BurritoError>
}

extension Transcribing {
    func requiresSpeechAuthorization(for identifier: String) -> Bool {
        true
    }
}

protocol NoteGenerating: Sendable {
    func availability(languageIdentifier: String) async -> Result<Void, BurritoError>
    func generate(
        segments: [TranscriptSegment],
        userNotes: String,
        meetingContext: CalendarEventSnapshot?,
        template: TemplateSnapshot,
        languageIdentifier: String,
        priorContext: String?
    ) async -> Result<GeneratedNote, BurritoError>
    func suggestTitle(
        segments: [TranscriptSegment],
        currentTitle: String,
        languageIdentifier: String
    ) async -> Result<String, BurritoError>
}

extension NoteGenerating {
    /// Convenience for notes with no earlier session material: runs
    /// generation without prior session context.
    func generate(
        segments: [TranscriptSegment],
        userNotes: String,
        meetingContext: CalendarEventSnapshot?,
        template: TemplateSnapshot,
        languageIdentifier: String
    ) async -> Result<GeneratedNote, BurritoError> {
        await generate(
            segments: segments,
            userNotes: userNotes,
            meetingContext: meetingContext,
            template: template,
            languageIdentifier: languageIdentifier,
            priorContext: nil
        )
    }
}

protocol RecordingFileStore: Sendable {
    func createSession(id: UUID, mode: RecordingMode) -> Result<RecordingFiles, BurritoError>
    func relativePath(for url: URL) -> String
    func url(forRelativePath path: String) -> URL
    func removeAudio(for files: RecordingFiles) -> Result<Void, BurritoError>
    func removeTranscriptionAudio(for files: RecordingFiles) -> Result<Void, BurritoError>
}

protocol PromptTokenMeasuring: Sendable {
    var contextSize: Int { get async }
    func tokenCount(_ text: String) async throws -> Int
}

protocol TextCompleting: Sendable {
    func complete(
        instructions: String,
        prompt: String,
        maximumResponseTokens: Int
    ) async throws -> String
    func completeNote(
        instructions: String,
        prompt: String,
        maximumResponseTokens: Int
    ) async throws -> GeneratedNote
}

/// A note-generation backend: an in-process model (Apple Intelligence or an
/// MLX download) or a terminal agent harness routed through its CLI.
protocol GenerationAdapter: PromptTokenMeasuring, TextCompleting {
    var supportsToolCalling: Bool { get }
    func completeTitle(
        instructions: String,
        prompt: String,
        maximumResponseTokens: Int
    ) async throws -> String
    func completeStreaming(
        instructions: String,
        prompt: String,
        maximumResponseTokens: Int,
        onTextUpdate: @MainActor @Sendable @escaping (String) -> Void
    ) async throws -> String
    func completeChatStreaming(
        instructions: String,
        conversation: [BurritoChatTurn],
        question: String,
        tools: [any AIToolProtocol],
        meetingEvidence: String?,
        maximumResponseTokens: Int,
        onTextUpdate: @MainActor @Sendable @escaping (String) -> Void
    ) async throws -> String
}
