import Foundation

@MainActor
protocol AudioCapturing: AnyObject {
    var activity: AudioActivity { get }
    var hasMeaningfulAudio: Bool { get }
    func start(
        files: RecordingFiles,
        includesMicrophone: Bool,
        languageIdentifier: String
    ) async -> Result<Void, BurritoError>
    func stop() async -> Result<Void, BurritoError>
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
        fileURL: URL,
        source: AudioSource,
        languageIdentifier: String
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
        template: TemplateSnapshot,
        languageIdentifier: String
    ) async -> Result<GeneratedNote, BurritoError>
    func suggestTitle(
        segments: [TranscriptSegment],
        currentTitle: String,
        languageIdentifier: String
    ) async -> Result<String, BurritoError>
}

protocol RecordingFileStore: Sendable {
    func createSession(id: UUID, includesMicrophone: Bool) -> Result<RecordingFiles, BurritoError>
    func relativePath(for url: URL) -> String
    func url(forRelativePath path: String) -> URL
    func removeAudio(for files: RecordingFiles) -> Result<Void, BurritoError>
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
