import Foundation

enum AudioSource: String, Codable, CaseIterable, Sendable {
    case system = "System"
    case microphone = "Microphone"
}

struct TranscriptSegment: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var source: AudioSource
    var startTime: TimeInterval
    var duration: TimeInterval
    var text: String

    init(
        id: UUID = UUID(),
        source: AudioSource,
        startTime: TimeInterval,
        duration: TimeInterval,
        text: String
    ) {
        self.id = id
        self.source = source
        self.startTime = startTime
        self.duration = duration
        self.text = text
    }
}

enum Transcript {
    static func merge(
        system: [TranscriptSegment],
        microphone: [TranscriptSegment]
    ) -> [TranscriptSegment] {
        (system + microphone).sorted {
            if $0.startTime == $1.startTime {
                return $0.source.rawValue < $1.source.rawValue
            }
            return $0.startTime < $1.startTime
        }
    }

    static func rendered(_ segments: [TranscriptSegment]) -> String {
        segments.map {
            let timestamp = Duration.seconds($0.startTime).formatted(.time(pattern: .minuteSecond))
            return "[\(timestamp)] \($0.source.rawValue): \($0.text)"
        }
        .joined(separator: "\n")
    }
}

enum CaptureState: Equatable, Sendable {
    case idle
    case preparing
    case recording(sessionID: UUID, startedAt: Date)
    case stopping(sessionID: UUID)
    case failed(sessionID: UUID?, message: String)

    var isRecording: Bool {
        if case .recording = self { true } else { false }
    }
}

enum ProcessingStage: String, Codable, CaseIterable, Sendable {
    case preparingAudio = "Preparing Audio"
    case transcribing = "Transcribing"
    case organizing = "Organizing"
    case generatingNotes = "Generating Notes"
}

enum NoteLifecycle: String, Codable, Sendable {
    case recording
    case processing
    case ready
    case recoverable
    case failed
}

enum BurritoError: Error, Equatable, Sendable {
    case appleIntelligenceUnavailable(reason: String)
    case screenRecordingPermissionDenied
    case microphonePermissionDenied
    case speechRecognitionPermissionDenied
    case unsupportedLanguage(identifier: String)
    case languageAssetMissing(identifier: String)
    case languageAssetInstallationFailed(identifier: String, details: String)
    case recordingAlreadyInProgress
    case noActiveRecording
    case captureFailed(details: String)
    case transcriptionFailed(details: String)
    case generationFailed(details: String)
    case storageFailed(details: String)

    var recoveryMessage: String {
        switch self {
        case .appleIntelligenceUnavailable(let reason):
            "Apple Intelligence is unavailable: \(reason). Your recording is preserved. Enable Apple Intelligence in System Settings, then choose Generate Again."
        case .screenRecordingPermissionDenied:
            "Screen Recording access is required for system audio. Open System Settings → Privacy & Security → Screen & System Audio Recording, enable Burrito, then retry."
        case .microphonePermissionDenied:
            "Microphone access is required for the selected microphone track. Enable Burrito in System Settings → Privacy & Security → Microphone, or turn the microphone track off."
        case .speechRecognitionPermissionDenied:
            "Speech Recognition access is required. Enable Burrito in System Settings → Privacy & Security → Speech Recognition, then retry."
        case .unsupportedLanguage(let identifier):
            "\(identifier) is not supported by the local transcriber. Choose a supported language in Settings."
        case .languageAssetMissing(let identifier):
            "The \(identifier) transcription asset is not installed. Install it before recording, then retry."
        case .languageAssetInstallationFailed(let identifier, let details):
            "Burrito could not install the \(identifier) transcription asset: \(details). Check your internet connection and try again."
        case .recordingAlreadyInProgress:
            "A recording is already active. Stop it before starting another."
        case .noActiveRecording:
            "There is no active recording to stop."
        case .captureFailed(let details):
            "Audio capture failed: \(details). Any audio already written remains available for recovery."
        case .transcriptionFailed(let details):
            "Transcription failed: \(details). The audio is preserved so you can retry."
        case .generationFailed(let details):
            "Note generation failed: \(details). The transcript and retained audio remain available; choose Generate Again."
        case .storageFailed(let details):
            "Burrito could not save the recording: \(details). Existing notes and files were not changed."
        }
    }
}

enum BuiltInTemplate: String, Codable, CaseIterable, Identifiable, Sendable {
    case summary
    case detailed
    case studyNotes
    case meeting

    var id: String { rawValue }

    var name: String {
        switch self {
        case .summary: "Summary"
        case .detailed: "Detailed"
        case .studyNotes: "Study Notes"
        case .meeting: "Meeting"
        }
    }

    var symbol: String {
        switch self {
        case .summary: "text.alignleft"
        case .detailed: "doc.text"
        case .studyNotes: "graduationcap"
        case .meeting: "person.3"
        }
    }

    var instructions: String {
        switch self {
        case .summary:
            "Create a concise overview, key points, and takeaways."
        case .detailed:
            "Create an overview, clearly titled topic sections, important details, and conclusions."
        case .studyNotes:
            "Create learning objectives, concepts, explanations, examples, a glossary, and review questions."
        case .meeting:
            "Create a meeting summary, decisions, action items with owners when stated, and open questions."
        }
    }
}

struct TemplateSnapshot: Codable, Equatable, Sendable {
    var name: String
    var symbol: String
    var instructions: String
}

struct RecordingOptions: Equatable, Sendable {
    var template: TemplateSnapshot
    var languageIdentifier: String
    var includesMicrophone: Bool
    var retainsAudio: Bool
}

enum RecordingDestination: Equatable, Identifiable, Sendable {
    case newNote
    case appendToNote(id: UUID)

    var id: String {
        switch self {
        case .newNote:
            "new-note"
        case .appendToNote(let id):
            "append-\(id.uuidString)"
        }
    }
}

struct RecordingFiles: Equatable, Sendable {
    var sessionID: UUID
    var systemAudioURL: URL
    var microphoneAudioURL: URL?
}

struct GeneratedNote: Equatable, Sendable {
    var title: String
    var markdown: String
}

struct PromptChunk: Equatable, Sendable {
    var segments: [TranscriptSegment]
    var text: String { Transcript.rendered(segments) }
}
