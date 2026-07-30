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

    static func latestFirst(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        segments.sorted {
            if $0.startTime == $1.startTime {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.startTime > $1.startTime
        }
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
            """
            Produce a concise, high-signal summary for someone who did not hear the recording.

            Structure:
            - Start with `## Overview`: one compact paragraph explaining the central subject, purpose, and outcome.
            - Add `## Key Points`: a prioritized bullet list of the most important facts, arguments, explanations, and examples.
            - Add `## Decisions and Actions` only when the source contains decisions, commitments, owners, or next steps.
            - End with `## Takeaways`: two to five durable conclusions the reader should remember.

            Rules:
            - Organize by importance, not transcript order.
            - Merge repeated ideas and remove conversational filler, greetings, tangents, and verbal scaffolding.
            - Preserve material names, numbers, dates, constraints, comparisons, and qualifications exactly.
            - Distinguish confirmed conclusions from proposals, opinions, and unresolved questions.
            - Never invent context, rationale, decisions, owners, deadlines, or recommendations.
            - Omit any section that would otherwise be empty.
            - Prefer precise, information-dense sentences over generic statements.
            """
        case .detailed:
            """
            Produce comprehensive reference notes that retain the recording's useful substance without becoming a transcript.

            Structure:
            - Start with `## Overview`: the subject, purpose, scope, and main conclusion.
            - Create descriptive `##` topic sections in a logical reading order.
            - Within each topic, capture definitions, background, reasoning, mechanisms, evidence, examples, tradeoffs, constraints, and consequences when present.
            - Add `## Decisions`, `## Action Items`, and `## Open Questions` only when supported by the source.
            - End with `## Conclusions` when the discussion reaches meaningful conclusions.

            Rules:
            - Reorganize fragmented remarks into coherent topics while preserving their meaning.
            - Retain important names, terminology, figures, dates, commands, steps, and quoted labels accurately.
            - Attribute claims or viewpoints when the speaker or source attribution matters.
            - Preserve uncertainty and disagreement; do not turn tentative language into fact.
            - Merge duplication, but do not discard distinct caveats or supporting details.
            - Do not add outside knowledge, explanations, recommendations, or inferred intent.
            - Use short paragraphs and bullets where they improve scanning. Omit empty sections.
            """
        case .studyNotes:
            """
            Produce rigorous study notes that teach the supplied material and support later revision.

            Structure:
            - Start with `## Topic Overview`: a compact map of what the material covers.
            - Add `## Learning Objectives`: observable things a learner should understand or be able to explain after studying.
            - Create one `##` section per major concept. Define it, explain how it works, connect it to related concepts, and preserve stated reasoning or derivations.
            - Include `### Examples` beneath the relevant concept when examples appear in the source.
            - Add `## Key Terms`: a concise glossary containing only terms actually used.
            - Add `## Review Questions`: questions answerable from these notes, spanning recall and conceptual understanding.
            - Add `## Common Pitfalls` only when misconceptions, edge cases, or warnings are discussed.

            Rules:
            - Explain clearly without introducing facts that are absent from the recording.
            - Preserve formulas, technical terms, commands, numbers, causal relationships, and step order exactly.
            - Separate definitions, examples, and consequences instead of blending them together.
            - Call out comparisons and tradeoffs explicitly when discussed.
            - Do not fabricate examples, answers, mnemonics, citations, or missing steps.
            - Remove repetition and filler. Omit unsupported or empty sections.
            """
        case .meeting:
            """
            Produce operational meeting notes that make outcomes, ownership, and unresolved work immediately clear.

            Structure:
            - Start with `## Meeting Summary`: the meeting purpose, principal topics, and overall outcome.
            - Add `## Discussion`: concise, topic-based bullets capturing material context, proposals, objections, tradeoffs, and conclusions.
            - Add `## Decisions`: each explicit decision and its stated rationale or constraint.
            - Add `## Action Items`: a Markdown table with `Action`, `Owner`, and `Due` columns. Use `Unassigned` or `Not stated` when the recording does not provide an owner or deadline.
            - Add `## Open Questions`: unresolved questions, blockers, dependencies, and items requiring follow-up.
            - Add `## Next Meeting` only when scheduling or a future agenda is stated.

            Rules:
            - Include participants or roles only when explicitly identified.
            - Attribute proposals, concerns, and commitments when attribution affects meaning.
            - Never convert a suggestion into a decision or a discussion point into an action item.
            - Never infer owners, deadlines, consensus, status, or priority.
            - Preserve names, dates, quantities, project terms, and commitments accurately.
            - Consolidate repetition and omit greetings, filler, and empty sections.
            """
        }
    }

    var legacyInstructions: String {
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

    static func resolvedInstructions(for template: TemplateSnapshot) -> String {
        guard let builtIn = allCases.first(where: {
            $0.name == template.name
                && ($0.instructions == template.instructions
                    || $0.legacyInstructions == template.instructions)
        }) else {
            return template.instructions
        }
        return builtIn.instructions
    }
}

struct TemplateSnapshot: Codable, Equatable, Sendable {
    var name: String
    var symbol: String
    var instructions: String
}

struct TemplateSymbolOption: Identifiable, Equatable, Sendable {
    let systemName: String
    let title: String
    let keywords: String

    var id: String { systemName }

    static let all: [TemplateSymbolOption] = [
        option("note.text", "Note", "writing document"),
        option("text.alignleft", "Summary", "overview paragraph"),
        option("doc.text", "Document", "file report"),
        option("list.bullet", "List", "bullets outline"),
        option("checklist", "Checklist", "tasks todo"),
        option("square.and.pencil", "Writing", "edit compose"),
        option("highlighter", "Highlights", "important marker"),
        option("quote.bubble", "Quotes", "speech citation"),
        option("bubble.left.and.bubble.right", "Conversation", "discussion chat"),
        option("message", "Messages", "chat conversation"),
        option("waveform", "Audio", "recording sound"),
        option("mic", "Microphone", "recording voice"),
        option("phone", "Phone call", "call conversation"),
        option("video", "Video call", "camera meeting"),
        option("person.2", "Meeting", "people discussion"),
        option("person.3", "Team", "group meeting"),
        option("person.crop.circle", "Interview", "person profile"),
        option("briefcase", "Work", "business job"),
        option("building.2", "Company", "office organization"),
        option("handshake", "Partnership", "deal agreement sales"),
        option("megaphone", "Marketing", "announcement campaign"),
        option("cart", "Sales", "shopping commerce"),
        option("dollarsign.circle", "Finance", "money budget"),
        option("creditcard", "Payments", "billing purchase"),
        option("lightbulb", "Idea", "insight concept"),
        option("brain.head.profile", "Thinking", "learning knowledge"),
        option("graduationcap", "Study", "education learning school"),
        option("book.closed", "Book", "reading study"),
        option("books.vertical", "Library", "reading reference"),
        option("bookmark", "Reference", "saved reading"),
        option("questionmark.circle", "Questions", "help unknown"),
        option("exclamationmark.triangle", "Warning", "risk caution"),
        option("flag", "Goal", "milestone objective"),
        option("target", "Target", "goal objective"),
        option("checkmark.circle", "Tasks", "done action items"),
        option("calendar", "Schedule", "date event plan"),
        option("clock", "Timeline", "time history"),
        option("hourglass", "Deadline", "time waiting"),
        option("chart.bar", "Analytics", "metrics data"),
        option("chart.line.uptrend.xyaxis", "Growth", "trend analytics"),
        option("chart.pie", "Report", "data analytics"),
        option("tablecells", "Table", "grid spreadsheet"),
        option("folder", "Project", "files organization"),
        option("tray", "Inbox", "incoming capture"),
        option("archivebox", "Archive", "storage history"),
        option("shippingbox", "Product", "package delivery"),
        option("gearshape", "Process", "settings workflow"),
        option("wrench.and.screwdriver", "Tools", "maintenance engineering"),
        option("hammer", "Build", "construction engineering"),
        option("terminal", "Terminal", "command code developer"),
        option("chevron.left.forwardslash.chevron.right", "Code", "programming developer"),
        option("cpu", "Technology", "processor hardware"),
        option("server.rack", "Infrastructure", "server cloud systems"),
        option("cylinder", "Database", "data storage"),
        option("network", "Systems", "architecture connected"),
        option("lock.shield", "Security", "protection privacy"),
        option("key", "Access", "security authentication"),
        option("shield", "Protection", "security privacy"),
        option("eye", "Observation", "research review"),
        option("magnifyingglass", "Research", "search investigate"),
        option("link", "Connection", "relationship collaboration"),
        option("paperclip", "Attachments", "files documents"),
        option("tag", "Category", "label organization"),
        option("number", "Numbers", "data count"),
        option("function", "Formula", "math calculation"),
        option("sum", "Mathematics", "numbers calculation"),
        option("atom", "Science", "research physics"),
        option("heart", "Health", "wellness care"),
        option("cross.case", "Medicine", "health clinical"),
        option("leaf", "Environment", "nature sustainability"),
        option("globe", "World", "international web"),
        option("map", "Map", "location travel"),
        option("location", "Location", "place travel"),
        option("airplane", "Travel", "flight trip"),
        option("car", "Transport", "vehicle travel"),
        option("fork.knife", "Food", "restaurant meal"),
        option("cup.and.saucer", "Coffee", "break cafe"),
        option("music.note", "Music", "audio song"),
        option("film", "Media", "video movie"),
        option("camera", "Photography", "photo image"),
        option("paintpalette", "Design", "creative art"),
        option("sparkles", "Creative", "magic polish"),
        option("wand.and.stars", "AI", "magic generate"),
        option("bolt", "Energy", "fast power"),
        option("flame", "Priority", "hot urgent"),
        option("star", "Favorite", "important featured"),
        option("trophy", "Achievement", "win success"),
    ]

    static func matching(_ query: String) -> [TemplateSymbolOption] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return all }
        return all.filter {
            $0.title.localizedStandardContains(value)
                || $0.keywords.localizedStandardContains(value)
                || $0.systemName.localizedStandardContains(value)
        }
    }

    static func title(for systemName: String) -> String {
        all.first { $0.systemName == systemName }?.title ?? "Selected symbol"
    }

    private static func option(
        _ systemName: String,
        _ title: String,
        _ keywords: String
    ) -> TemplateSymbolOption {
        TemplateSymbolOption(systemName: systemName, title: title, keywords: keywords)
    }
}

enum PaletteNoteAge {
    static func label(updatedAt: Date, now: Date = .now) -> String {
        let elapsed = max(0, now.timeIntervalSince(updatedAt))
        let hours = Int(elapsed / 3_600)
        guard hours > 0 else { return "Now" }
        guard hours < 24 else { return "\(hours / 24)d" }
        return "\(hours)h"
    }
}

enum ParakeetModelVariant: String, CaseIterable, Identifiable, Equatable, Sendable {
    case englishV2
    case multilingualV3
    case englishCompact
    case japanese

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .englishV2: "Parakeet TDT v2"
        case .multilingualV3: "Parakeet TDT v3"
        case .englishCompact: "Parakeet TDT-CTC 110M"
        case .japanese: "Parakeet Japanese"
        }
    }

    var summary: String {
        switch self {
        case .englishV2:
            "The strongest long-form English model."
        case .multilingualV3:
            "One model for 25 European languages."
        case .englishCompact:
            "A smaller English model with a lighter memory footprint."
        case .japanese:
            "A dedicated Japanese transcription model."
        }
    }

    var parameterCount: String {
        switch self {
        case .englishCompact: "110M parameters"
        case .englishV2, .multilingualV3, .japanese: "600M parameters"
        }
    }

    var languageSummary: String {
        switch self {
        case .englishV2, .englishCompact: "English only"
        case .multilingualV3: "Multilingual · 25 languages"
        case .japanese: "Japanese only"
        }
    }

    var downloadSize: String {
        switch self {
        case .englishV2: "≈ 464 MB"
        case .multilingualV3: "≈ 483 MB"
        case .englishCompact: "≈ 227 MB"
        case .japanese: "≈ 619 MB"
        }
    }

    var downloadSizeBytes: Int64 {
        switch self {
        case .englishV2: 464_413_247
        case .multilingualV3: 483_105_645
        case .englishCompact: 227_466_209
        case .japanese: 619_065_246
        }
    }

    static func candidates(languageIdentifier: String) -> [ParakeetModelVariant] {
        let languageCode = Locale(identifier: languageIdentifier).language.languageCode?.identifier
        switch languageCode {
        case "en":
            return [.englishV2, .englishCompact, .multilingualV3]
        case "bg", "hr", "cs", "da", "nl", "et", "fi", "fr", "de", "el",
             "hu", "it", "lv", "lt", "mt", "pl", "pt", "ro", "ru", "sk",
             "sl", "es", "sv", "uk":
            return [.multilingualV3]
        case "ja":
            return [.japanese]
        default:
            return []
        }
    }

    static func supporting(languageIdentifier: String) -> ParakeetModelVariant? {
        candidates(languageIdentifier: languageIdentifier).first
    }
}

struct TranscriptionLanguage: Identifiable, Equatable, Sendable {
    let identifier: String
    let title: String
    let compactTitle: String

    var id: String { identifier }

    static let supported = [
        TranscriptionLanguage(
            identifier: "bg-BG",
            title: "Bulgarian",
            compactTitle: "Bulgarian"
        ),
        TranscriptionLanguage(
            identifier: "hr-HR",
            title: "Croatian",
            compactTitle: "Croatian"
        ),
        TranscriptionLanguage(
            identifier: "cs-CZ",
            title: "Czech",
            compactTitle: "Czech"
        ),
        TranscriptionLanguage(
            identifier: "da-DK",
            title: "Danish",
            compactTitle: "Danish"
        ),
        TranscriptionLanguage(
            identifier: "nl-NL",
            title: "Dutch",
            compactTitle: "Dutch"
        ),
        TranscriptionLanguage(
            identifier: "en-US",
            title: "English (US)",
            compactTitle: "English · US"
        ),
        TranscriptionLanguage(
            identifier: "en-GB",
            title: "English (UK)",
            compactTitle: "English · UK"
        ),
        TranscriptionLanguage(
            identifier: "et-EE",
            title: "Estonian",
            compactTitle: "Estonian"
        ),
        TranscriptionLanguage(
            identifier: "fi-FI",
            title: "Finnish",
            compactTitle: "Finnish"
        ),
        TranscriptionLanguage(
            identifier: "fr-FR",
            title: "French",
            compactTitle: "French"
        ),
        TranscriptionLanguage(
            identifier: "de-DE",
            title: "German",
            compactTitle: "German"
        ),
        TranscriptionLanguage(
            identifier: "el-GR",
            title: "Greek",
            compactTitle: "Greek"
        ),
        TranscriptionLanguage(
            identifier: "hi-IN",
            title: "Hindi",
            compactTitle: "Hindi"
        ),
        TranscriptionLanguage(
            identifier: "hu-HU",
            title: "Hungarian",
            compactTitle: "Hungarian"
        ),
        TranscriptionLanguage(
            identifier: "it-IT",
            title: "Italian",
            compactTitle: "Italian"
        ),
        TranscriptionLanguage(
            identifier: "ja-JP",
            title: "Japanese",
            compactTitle: "Japanese"
        ),
        TranscriptionLanguage(
            identifier: "lv-LV",
            title: "Latvian",
            compactTitle: "Latvian"
        ),
        TranscriptionLanguage(
            identifier: "lt-LT",
            title: "Lithuanian",
            compactTitle: "Lithuanian"
        ),
        TranscriptionLanguage(
            identifier: "mt-MT",
            title: "Maltese",
            compactTitle: "Maltese"
        ),
        TranscriptionLanguage(
            identifier: "pl-PL",
            title: "Polish",
            compactTitle: "Polish"
        ),
        TranscriptionLanguage(
            identifier: "pt-PT",
            title: "Portuguese",
            compactTitle: "Portuguese"
        ),
        TranscriptionLanguage(
            identifier: "ro-RO",
            title: "Romanian",
            compactTitle: "Romanian"
        ),
        TranscriptionLanguage(
            identifier: "ru-RU",
            title: "Russian",
            compactTitle: "Russian"
        ),
        TranscriptionLanguage(
            identifier: "sk-SK",
            title: "Slovak",
            compactTitle: "Slovak"
        ),
        TranscriptionLanguage(
            identifier: "sl-SI",
            title: "Slovenian",
            compactTitle: "Slovenian"
        ),
        TranscriptionLanguage(
            identifier: "es-ES",
            title: "Spanish",
            compactTitle: "Spanish"
        ),
        TranscriptionLanguage(
            identifier: "sv-SE",
            title: "Swedish",
            compactTitle: "Swedish"
        ),
        TranscriptionLanguage(
            identifier: "uk-UA",
            title: "Ukrainian",
            compactTitle: "Ukrainian"
        ),
    ]

    static func resolve(_ identifier: String) -> TranscriptionLanguage {
        supported.first { $0.identifier == identifier }
            ?? supported.first { $0.identifier == "en-US" }
            ?? TranscriptionLanguage(
                identifier: "en-US",
                title: "English (US)",
                compactTitle: "English · US"
            )
    }
}

enum RecordingMode: String, CaseIterable, Identifiable, Sendable {
    case listenAlong
    case meeting

    var id: Self { self }

    var title: String {
        switch self {
        case .listenAlong: "Listen along"
        case .meeting: "Meeting mode"
        }
    }

    var description: String {
        switch self {
        case .listenAlong: "Capture audio playing on this Mac."
        case .meeting: "Capture the room through your microphone."
        }
    }

    var symbol: String {
        switch self {
        case .listenAlong: "macbook.and.iphone"
        case .meeting: "person.2.wave.2"
        }
    }
}

struct RecordingOptions: Equatable, Sendable {
    var template: TemplateSnapshot
    var languageIdentifier: String
    var mode: RecordingMode
    var retainsAudio: Bool
}

struct CalendarEventSnapshot: Codable, Equatable, Sendable {
    var eventIdentifier: String
    var title: String
    var startDate: Date
    var endDate: Date
    var meetingURL: URL?
    var attendeeNames: [String]
    var organizerName: String?
    var recurrenceIdentifier: String?
    var calendarName: String

    var relatedMeetingIdentifier: String {
        recurrenceIdentifier ?? eventIdentifier
    }

    var generationContext: String {
        let attendees = attendeeNames.isEmpty ? "Not listed" : attendeeNames.joined(separator: ", ")
        return """
            Title: \(title)
            Starts: \(startDate.formatted(.iso8601))
            Ends: \(endDate.formatted(.iso8601))
            Calendar: \(calendarName)
            Organizer: \(organizerName ?? "Not listed")
            Attendees: \(attendees)
            Meeting URL: \(meetingURL?.absoluteString ?? "Not listed")
            """
    }
}

enum RecordingDestination: Equatable, Identifiable, Sendable {
    case newNote
    case calendarEvent(CalendarEventSnapshot)
    case appendToNote(id: UUID)

    var id: String {
        switch self {
        case .newNote:
            "new-note"
        case .calendarEvent(let event):
            "calendar-\(event.eventIdentifier)-\(event.startDate.timeIntervalSinceReferenceDate)"
        case .appendToNote(let id):
            "append-\(id.uuidString)"
        }
    }

    var calendarEvent: CalendarEventSnapshot? {
        if case .calendarEvent(let event) = self { event } else { nil }
    }
}

struct RecordingFiles: Equatable, Sendable {
    var sessionID: UUID
    var systemAudioURL: URL?
    var microphoneAudioURL: URL?
}

struct GeneratedNote: Equatable, Sendable {
    var title: String
    var markdown: String

    static func parseLabeledResponse(_ response: String) -> GeneratedNote? {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if let titleMarker = trimmed.range(
            of: "TITLE:",
            options: [.caseInsensitive]
        ),
           let noteMarker = trimmed.range(
            of: "NOTE:",
            options: [.caseInsensitive],
            range: titleMarker.upperBound..<trimmed.endIndex
           ) {
            let rawTitle = String(trimmed[titleMarker.upperBound..<noteMarker.lowerBound])
            let markdown = String(trimmed[noteMarker.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let title = GeneratedTitle.sanitized(rawTitle), !markdown.isEmpty {
                return GeneratedNote(title: title, markdown: markdown)
            }
        }

        for line in trimmed.split(whereSeparator: \.isNewline) {
            let candidate = line.trimmingCharacters(in: .whitespaces)
            let marker = candidate.prefix(while: { $0 == "#" })
            guard (1...6).contains(marker.count) else { continue }

            let remainder = candidate.dropFirst(marker.count)
            guard let separator = remainder.first, separator.isWhitespace else { continue }

            let rawTitle = String(remainder.dropFirst())
            if let title = GeneratedTitle.sanitized(rawTitle) {
                return GeneratedNote(title: title, markdown: trimmed)
            }
        }
        return nil
    }
}

struct PromptChunk: Equatable, Sendable {
    var segments: [TranscriptSegment]
    var text: String { Transcript.rendered(segments) }
}
