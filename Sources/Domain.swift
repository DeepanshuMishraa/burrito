import Foundation

enum AudioSource: String, Codable, CaseIterable, Sendable {
    case system = "System"
    case microphone = "Microphone"
}

struct PlaybackRate: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    static let validRange = 1.0...10.0
    static let natural = PlaybackRate(validatedRawValue: 1)
    static let menuPresets = [1, 1.25, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10]
        .map(PlaybackRate.init(validatedRawValue:))

    let rawValue: Double

    init?(rawValue: Double) {
        guard rawValue.isFinite, Self.validRange.contains(rawValue) else { return nil }
        self.init(validatedRawValue: rawValue)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(Double.self)
        guard let rate = PlaybackRate(rawValue: value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Playback rate must be a finite value from 1 through 10."
            )
        }
        self = rate
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var displayTitle: String {
        rawValue.formatted(.number.precision(.fractionLength(0...2))) + "×"
    }

    private init(validatedRawValue: Double) {
        self.rawValue = validatedRawValue
    }
}

enum TranscriptionInput: Equatable, Sendable {
    case natural(fileURL: URL, source: AudioSource)
    case systemCapture(fileURL: URL, playbackRate: PlaybackRate)
    case importedMedia(fileURL: URL, source: AudioSource)
}

struct TranscriptSegment: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var source: AudioSource
    var startTime: TimeInterval
    var duration: TimeInterval
    var text: String
    var speakerName: String?

    init(
        id: UUID = UUID(),
        source: AudioSource,
        startTime: TimeInterval,
        duration: TimeInterval,
        text: String,
        speakerName: String? = nil
    ) {
        self.id = id
        self.source = source
        self.startTime = startTime
        self.duration = duration
        self.text = text
        self.speakerName = speakerName
    }
}

struct LiveTranscriptPassage: Equatable, Identifiable, Sendable {
    let id: UUID
    let source: AudioSource
    let startTime: TimeInterval
    let duration: TimeInterval
    let text: String
    let isFinal: Bool

    init(
        id: UUID = UUID(),
        source: AudioSource,
        startTime: TimeInterval,
        duration: TimeInterval,
        text: String,
        isFinal: Bool
    ) {
        self.id = id
        self.source = source
        self.startTime = startTime
        self.duration = duration
        self.text = text
        self.isFinal = isFinal
    }
}

enum LiveTranscriptionAvailability: Equatable, Sendable {
    case preparing
    case available
    case unavailable(reason: String)
}

struct LiveTranscriptSnapshot: Equatable, Sendable {
    var availability: LiveTranscriptionAvailability
    var passages: [LiveTranscriptPassage]

    static let preparing = LiveTranscriptSnapshot(
        availability: .preparing,
        passages: []
    )
}

struct SpeakerTurn: Equatable, Sendable {
    let id: String
    let startTime: TimeInterval
    let endTime: TimeInterval
}

enum SpeakerAttribution {
    static func assign(
        turns: [SpeakerTurn],
        to segments: [TranscriptSegment]
    ) -> [TranscriptSegment] {
        let orderedSpeakerIDs = turns
            .sorted { $0.startTime < $1.startTime }
            .reduce(into: [String]()) { result, turn in
                if !result.contains(turn.id) {
                    result.append(turn.id)
                }
            }
        let labels = Dictionary(
            uniqueKeysWithValues: orderedSpeakerIDs.enumerated().map {
                ($0.element, "Speaker \($0.offset + 1)")
            }
        )

        return segments.map { segment in
            var attributed = segment
            if segment.source == .microphone {
                attributed.speakerName = "You"
                return attributed
            }
            let segmentEnd = segment.startTime + segment.duration
            let bestTurn = turns.max { left, right in
                overlap(
                    start: segment.startTime,
                    end: segmentEnd,
                    with: left
                ) < overlap(
                    start: segment.startTime,
                    end: segmentEnd,
                    with: right
                )
            }
            if let bestTurn,
               overlap(start: segment.startTime, end: segmentEnd, with: bestTurn) > 0 {
                attributed.speakerName = labels[bestTurn.id]
            }
            return attributed
        }
    }

    static func rename(
        speaker original: String,
        to replacement: String,
        in segments: [TranscriptSegment]
    ) -> [TranscriptSegment] {
        let name = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        return segments.map { segment in
            guard segment.speakerName == original else { return segment }
            var renamed = segment
            renamed.speakerName = name.isEmpty ? nil : name
            return renamed
        }
    }

    private static func overlap(
        start: TimeInterval,
        end: TimeInterval,
        with turn: SpeakerTurn
    ) -> TimeInterval {
        max(0, min(end, turn.endTime) - max(start, turn.startTime))
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
            let correctedSpeaker = $0.speakerName?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let speaker = correctedSpeaker?.isEmpty == false
                ? correctedSpeaker ?? $0.source.rawValue
                : $0.source.rawValue
            return "[\(timestamp)] [source:\($0.id.uuidString)] \(speaker): \($0.text)"
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

enum TranscriptCitation {
    static func segmentID(from url: URL?) -> UUID? {
        guard let url,
              url.scheme == "burrito",
              url.host == "transcript"
        else {
            return nil
        }
        let value = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return UUID(uuidString: value)
    }
}

struct MemoryDocument: Equatable, Sendable {
    let noteID: UUID
    let title: String
    let updatedAt: Date
    let segments: [TranscriptSegment]
}

enum MemoryMention {
    static func query(in text: String) -> String? {
        guard let start = queryStart(in: text) else { return nil }
        let valueStart = text.index(after: start)
        return String(text[valueStart...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func questionWithoutQuery(in text: String) -> String {
        guard let start = queryStart(in: text) else { return text }
        return String(text[..<start])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func queryStart(in text: String) -> String.Index? {
        guard let start = text.lastIndex(of: "@") else { return nil }
        guard start == text.startIndex
                || text[text.index(before: start)].isWhitespace
        else {
            return nil
        }
        return start
    }
}

struct MemoryEvidence: Equatable, Identifiable, Sendable {
    let noteID: UUID
    let noteTitle: String
    let noteUpdatedAt: Date
    let segment: TranscriptSegment

    var id: String { "\(noteID.uuidString):\(segment.id.uuidString)" }

    var citationURL: URL? {
        URL(
            string: "burrito://memory/\(noteID.uuidString)/\(segment.id.uuidString)"
        )
    }
}

struct MemoryCitation: Equatable, Sendable {
    let noteID: UUID
    let segmentID: UUID

    static func resolve(_ url: URL?) -> MemoryCitation? {
        guard let url,
              url.scheme == "burrito",
              url.host == "memory"
        else {
            return nil
        }
        let values = url.path
            .split(separator: "/")
            .map(String.init)
        guard values.count == 2,
              let noteID = UUID(uuidString: values[0]),
              let segmentID = UUID(uuidString: values[1])
        else {
            return nil
        }
        return MemoryCitation(noteID: noteID, segmentID: segmentID)
    }
}

enum LocalMemory {
    static func retrieve(
        question: String,
        from documents: [MemoryDocument],
        limit: Int = 18
    ) -> [MemoryEvidence] {
        guard limit > 0 else { return [] }
        let queryTerms = terms(in: question)
        let candidates = documents.flatMap { document in
            let titleMatches = queryTerms.intersection(terms(in: document.title)).count
            return document.segments.map { segment in
                let passageMatches = queryTerms.intersection(terms(in: segment.text)).count
                return (
                    evidence: MemoryEvidence(
                        noteID: document.noteID,
                        noteTitle: document.title,
                        noteUpdatedAt: document.updatedAt,
                        segment: segment
                    ),
                    score: (titleMatches * 3) + passageMatches
                )
            }
        }
        return candidates
            .filter { $0.score > 0 }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                if $0.evidence.noteUpdatedAt != $1.evidence.noteUpdatedAt {
                    return $0.evidence.noteUpdatedAt > $1.evidence.noteUpdatedAt
                }
                return $0.evidence.segment.startTime < $1.evidence.segment.startTime
            }
            .prefix(limit)
            .map(\.evidence)
    }

    static func retrieve(
        question: String,
        scopedTo document: MemoryDocument,
        limit: Int = 18
    ) -> [MemoryEvidence] {
        guard limit > 0 else { return [] }
        let ranked = retrieve(question: question, from: [document], limit: limit)
        guard ranked.isEmpty else { return ranked }
        return document.segments
            .sorted { $0.startTime < $1.startTime }
            .prefix(limit)
            .map { segment in
                MemoryEvidence(
                    noteID: document.noteID,
                    noteTitle: document.title,
                    noteUpdatedAt: document.updatedAt,
                    segment: segment
                )
            }
    }

    private static func terms(in text: String) -> Set<String> {
        let ignored = Set([
            "a", "an", "and", "are", "did", "do", "for", "how", "in", "is",
            "it", "of", "on", "the", "to", "was", "what", "when", "where", "who",
        ])
        return Set(
            text.lowercased()
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .filter { $0.count > 1 && !ignored.contains($0) }
        )
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

enum SmartStopDecision: Equatable, Sendable {
    case keepRecording
    case suggestStop
}

enum SmartStopStatus: Equatable, Sendable {
    case monitoring
    case suggested
    case dismissed

    var wasSuggested: Bool {
        self != .monitoring
    }
}

enum SmartStopPolicy {
    static let meetingEndGrace: TimeInterval = 60
    static let requiredSilence: TimeInterval = 45
    static let minimumRecordingDuration: TimeInterval = 2 * 60

    static func decision(
        now: Date,
        eventEnd: Date?,
        recordingElapsed: TimeInterval,
        silentFor: TimeInterval,
        alreadySuggested: Bool
    ) -> SmartStopDecision {
        guard !alreadySuggested,
              recordingElapsed >= minimumRecordingDuration,
              silentFor >= requiredSilence,
              let eventEnd,
              now >= eventEnd.addingTimeInterval(meetingEndGrace)
        else {
            return .keepRecording
        }
        return .suggestStop
    }
}

enum ProcessingStage: String, Codable, CaseIterable, Sendable {
    case preparingAudio = "Preparing Audio"
    case transcribing = "Transcribing"
    case identifyingSpeakers = "Identifying Speakers"
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
    case audioPreparationFailed(details: String)
    case mediaImportFailed(details: String)
    case transcriptionFailed(details: String)
    case speakerDiarizationFailed(details: String)
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
        case .audioPreparationFailed(let details):
            "Audio preparation failed: \(details). The original recording is preserved; retry or import the original media file."
        case .mediaImportFailed(let details):
            "Media import failed: \(details)"
        case .transcriptionFailed(let details):
            "Transcription failed: \(details). The audio is preserved so you can retry."
        case .speakerDiarizationFailed(let details):
            "Speaker identification did not finish: \(details). The transcript is preserved with audio-source labels; retry after checking your connection or edit speaker names manually."
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
            Act as an executive briefing editor. Compress the source into the smallest useful account
            for a busy reader who needs the bottom line, not a record of every topic discussed.

            Output:
            - `## Bottom Line`: one paragraph of at most three sentences stating the dominant subject,
              why it mattered, and the principal outcome or conclusion.
            - `## Essential Points`: include only as many importance-ranked bullets as the source
              supports, with no minimum and normally no more than eight. Each bullet must add a distinct
              fact, argument, finding, constraint, or consequence.
            - `## Outcomes and Next Steps`: include only explicit decisions, commitments, or next steps.
            - `## Unresolved`: include only questions or uncertainties that materially affect the bottom line.

            Selection policy:
            - Favor conclusions and decision-relevant facts over background, process detail, and examples.
            - Include a supporting example only when the central point would be unclear without it.
            - Merge repeated ideas. Exclude greetings, tangents, minor asides, and speaker-by-speaker narration.
            - Keep proposals, opinions, and confirmed outcomes visibly distinct.
            - Do not turn this into comprehensive notes, a lesson, or meeting minutes.
            - Omit optional sections when unsupported. Never invent context, rationale, ownership, or next steps.
            """
        case .detailed:
            """
            Act as a technical archivist. Build a durable reference record that preserves the source's
            material detail, reasoning, and nuance without reproducing it speaker by speaker.

            Output:
            - `## Scope and Context`: identify the subject, purpose, boundaries, and relevant background.
            - Create descriptive `##` sections for every major topic in a logical reading order.
            - Within each topic, use `###` subsections where useful to separate how something works,
              supporting evidence or examples, alternatives, constraints, and consequences.
            - Add `## Process or Timeline` when sequence is essential to understanding events or instructions.
            - End with any supported `## Conclusions`, `## Decisions`, and `## Open Questions` sections.

            Coverage policy:
            - Optimize for retrieval and completeness, not brevity. Preserve meaningful secondary points,
              caveats, exceptions, dependencies, figures, dates, commands, and ordered steps.
            - Reassemble fragmented remarks under the topic they clarify; do not preserve transcript order
              when it obscures the subject.
            - Attribute claims when identity affects authority, disagreement, or interpretation.
            - Preserve uncertainty and competing viewpoints rather than resolving them yourself.
            - Merge only genuine repetition. Do not manufacture explanations, transitions, or conclusions.
            - Do not add study exercises or force operational meeting fields onto non-meeting material.
            """
        case .studyNotes:
            """
            Act as an instructional designer. Turn the source into a self-contained learning aid that helps
            a learner understand, connect, and later recall the taught material.

            Output:
            - `## Learning Map`: briefly show the concepts covered and how they relate.
            - `## Learning Objectives`: include only as many observable outcomes as the source supports,
              with no minimum and normally no more than seven. Phrase each as what the learner can explain,
              compare, derive, or apply using this material.
            - Create one `##` section per major concept. For each, separate `### Definition`,
              `### How It Works`, and `### Why It Matters` when the source supports them.
            - Add source-backed `### Examples`, derivations, or procedures directly beneath their concept.
            - `## Key Terms`: define only terminology introduced by the source.
            - `## Check Your Understanding`: write recall and reasoning questions answerable entirely from
              the notes. Do not provide an answer key.
            - Add `## Common Pitfalls` only for misconceptions, edge cases, or warnings actually discussed.

            Teaching policy:
            - Preserve formulas, technical terms, causal links, prerequisites, and step order exactly.
            - Make implicit connections only when the source directly supports them; never fill gaps with
              outside knowledge or invented examples.
            - Keep definitions, mechanisms, evidence, and examples distinct so the learner can study them.
            - Do not frame decisions or action items as meeting minutes unless they are themselves lesson content.
            """
        case .meeting:
            """
            Act as an operations recorder. Produce a decision-and-accountability record that lets the team
            act after the meeting without rereading the discussion.

            Output:
            - `## Meeting Outcome`: state the purpose, overall result, and current status in one short paragraph.
            - `## Discussion by Topic`: for each agenda topic, capture only context needed to understand
              proposals, objections, tradeoffs, and the resulting position.
            - `## Decision Log`: a Markdown table with `Decision`, `Rationale`, and `Constraints` columns.
              Include only decisions explicitly reached; write `Not stated` for omitted rationale or constraints.
            - `## Action Register`: a Markdown table with `Action`, `Owner`, and `Due` columns. Use
              `Unassigned` and `Not stated` rather than guessing missing values.
            - `## Risks and Blockers`: include active dependencies, risks, or blockers requiring attention.
            - `## Open Questions`: include unresolved items and who must answer them when explicitly stated.
            - `## Follow-up`: include a stated next meeting, checkpoint, or future agenda.

            Recording policy:
            - Attribute proposals, objections, decisions, and commitments when attribution affects accountability.
            - Never convert discussion into a decision, a suggestion into an action, or attendance into agreement.
            - Never infer owners, deadlines, consensus, status, or priority.
            - Preserve project terms, quantities, dates, commitments, and explicitly identified participants.
            - Exclude greetings, commentary about the meeting itself, and background unrelated to an outcome.
            - Omit every unsupported section instead of writing placeholders, except required table cells.
            """
        }
    }

    var expandedInstructions: String {
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

    var previousInstructions: String {
        switch self {
        case .summary:
            instructions.replacingOccurrences(
                of: "include only as many importance-ranked bullets as the source\n"
                    + "  supports, with no minimum and normally no more than eight. Each bullet must add a distinct",
                with: "four to eight importance-ranked bullets. Each bullet must add a\n"
                    + "  distinct"
            )
        case .studyNotes:
            instructions.replacingOccurrences(
                of: "include only as many observable outcomes as the source supports,\n"
                    + "  with no minimum and normally no more than seven. Phrase each as what the learner can explain,\n"
                    + "  compare, derive, or apply using this material.",
                with: "three to seven observable outcomes phrased as what the learner can\n"
                    + "  explain, compare, derive, or apply using this material."
            )
        case .detailed, .meeting:
            instructions
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
                    || $0.previousInstructions == template.instructions
                    || $0.expandedInstructions == template.instructions
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

enum LocalLanguageModelVariant: String, CaseIterable, Identifiable, Equatable, Sendable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .small: "Qwen 3.5 Small"
        case .medium: "Qwen 3.5 Medium"
        case .large: "Qwen 3.5 Large"
        }
    }

    var summary: String {
        switch self {
        case .small: "Fast, capable generation for Macs with less unified memory."
        case .medium: "The best balance of intelligence, speed, and memory use."
        case .large: "The strongest local generation option for higher-memory Macs."
        }
    }

    var parameterCount: String {
        switch self {
        case .small: "2B parameters"
        case .medium: "4B parameters"
        case .large: "9B parameters"
        }
    }

    var downloadSize: String {
        "≈ " + ByteCountFormatter.string(
            fromByteCount: downloadSizeBytes,
            countStyle: .decimal
        )
    }

    var downloadSizeBytes: Int64 {
        switch self {
        case .small: 1_750_000_000
        case .medium: 3_060_000_000
        case .large: 5_980_000_000
        }
    }

    var repositoryID: String {
        switch self {
        case .small: "mlx-community/Qwen3.5-2B-4bit"
        case .medium: "mlx-community/Qwen3.5-4B-4bit"
        case .large: "mlx-community/Qwen3.5-9B-4bit"
        }
    }

    var revision: String {
        switch self {
        case .small: "674aaa7240b91e8012fcad5d791b7dfe5ba90207"
        case .medium: "0e7ffd5c629ef7719d4cbc04069232580bfa9d9c"
        case .large: "8b2b98c00a6b4d291155e4890773ca8f769aee53"
        }
    }
}

enum GenerationModelSelection: Equatable, Sendable {
    static let storageKey = "generationModel"

    case apple
    case local(LocalLanguageModelVariant)

    var rawValue: String {
        switch self {
        case .apple: "apple"
        case .local(let variant): "qwen3.5-\(variant.rawValue)"
        }
    }

    init?(rawValue: String) {
        if rawValue == "apple" {
            self = .apple
            return
        }
        let prefix = "qwen3.5-"
        guard rawValue.hasPrefix(prefix),
              let variant = LocalLanguageModelVariant(
                rawValue: String(rawValue.dropFirst(prefix.count))
              )
        else {
            return nil
        }
        self = .local(variant)
    }

    static func resolve(
        persistedValue: String?,
        isInstalled: (LocalLanguageModelVariant) -> Bool
    ) -> GenerationModelSelection {
        guard let persistedValue,
              let selection = GenerationModelSelection(rawValue: persistedValue)
        else {
            return .apple
        }
        switch selection {
        case .apple:
            return .apple
        case .local(let variant):
            return isInstalled(variant) ? selection : .apple
        }
    }
}

enum TranscriptionEngineCoverage: Equatable, Sendable {
    case downloadableLocalModel
    case appleSpeech

    var title: String {
        switch self {
        case .downloadableLocalModel: "Parakeet model available"
        case .appleSpeech: "Apple Speech"
        }
    }

    var detail: String {
        switch self {
        case .downloadableLocalModel:
            "Uses an installed on-device Parakeet model, with Apple Speech as fallback."
        case .appleSpeech:
            "Availability is verified by macOS before recording starts."
        }
    }
}

struct TranscriptionLanguage: Identifiable, Equatable, Sendable {
    let identifier: String
    let title: String
    let compactTitle: String

    var id: String { identifier }

    var engineCoverage: TranscriptionEngineCoverage {
        ParakeetModelVariant.candidates(languageIdentifier: identifier).isEmpty
            ? .appleSpeech
            : .downloadableLocalModel
    }

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
        case .meeting: "Capture the call and your microphone separately."
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
    var playbackRate: PlaybackRate = .natural
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
    var systemTranscriptionURL: URL? = nil
    var microphoneTranscriptionURL: URL? = nil

    var allURLs: [URL] {
        [
            systemAudioURL,
            microphoneAudioURL,
            systemTranscriptionURL,
            microphoneTranscriptionURL,
        ].compactMap { $0 }
    }

    var transcriptionURLs: [URL] {
        [systemTranscriptionURL, microphoneTranscriptionURL].compactMap { $0 }
    }
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
