import Foundation
import SwiftData

@Model
final class Folder {
    @Attribute(.unique) var id: UUID
    var name: String
    var order: Int
    @Relationship(deleteRule: .nullify, inverse: \Note.folder) var notes: [Note]

    init(id: UUID = UUID(), name: String, order: Int = 0) {
        self.id = id
        self.name = name
        self.order = order
        self.notes = []
    }
}

@Model
final class NoteTemplate {
    @Attribute(.unique) var id: UUID
    var builtInID: String?
    var name: String
    var symbol: String
    var instructions: String
    var createdAt: Date

    var isBuiltIn: Bool { builtInID != nil }

    init(
        id: UUID = UUID(),
        builtInID: String? = nil,
        name: String,
        symbol: String,
        instructions: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.builtInID = builtInID
        self.name = name
        self.symbol = symbol
        self.instructions = instructions
        self.createdAt = createdAt
    }

    var snapshot: TemplateSnapshot {
        TemplateSnapshot(name: name, symbol: symbol, instructions: instructions)
    }
}

@Model
final class Note {
    @Attribute(.unique) var id: UUID
    var lifecycleRawValue: String
    var processingStageRawValue: String?
    var title: String
    var markdownBody: String
    var userNotes: String = ""
    var transcriptData: Data
    var createdAt: Date
    var updatedAt: Date
    var recordingStartedAt: Date?
    var duration: TimeInterval
    var languageIdentifier: String
    var templateName: String
    var templateSymbol: String
    var templateInstructions: String
    var isFavorite: Bool
    var deletedAt: Date?
    var systemAudioRelativePath: String?
    var microphoneAudioRelativePath: String?
    var recordingModeRawValue: String?
    var playbackRateValue: Double = PlaybackRate.natural.rawValue
    var retainsAudio: Bool
    var transcriptRevision: Int
    var generatedFromTranscriptRevision: Int
    var userEditedNotes: Bool
    var lastErrorMessage: String?
    var calendarEventData: Data?
    var folder: Folder?
    /// Manual position within the note's day group once the user has
    /// reordered the timeline by dragging. nil means "no manual order yet".
    var manualOrder: Int?

    init(
        id: UUID = UUID(),
        lifecycle: NoteLifecycle = .recording,
        title: String = "New Recording",
        markdownBody: String = "",
        userNotes: String = "",
        transcriptSegments: [TranscriptSegment] = [],
        createdAt: Date = .now,
        languageIdentifier: String,
        template: TemplateSnapshot,
        recordingMode: RecordingMode = .listenAlong,
        playbackRate: PlaybackRate = .natural,
        retainsAudio: Bool,
        calendarEvent: CalendarEventSnapshot? = nil
    ) {
        self.id = id
        self.lifecycleRawValue = lifecycle.rawValue
        self.processingStageRawValue = nil
        self.title = title
        self.markdownBody = markdownBody
        self.userNotes = userNotes
        self.transcriptData = (try? JSONEncoder().encode(transcriptSegments)) ?? Data()
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.recordingStartedAt = createdAt
        self.duration = 0
        self.languageIdentifier = languageIdentifier
        self.templateName = template.name
        self.templateSymbol = template.symbol
        self.templateInstructions = template.instructions
        self.isFavorite = false
        self.deletedAt = nil
        self.systemAudioRelativePath = nil
        self.microphoneAudioRelativePath = nil
        self.recordingModeRawValue = recordingMode.rawValue
        self.playbackRateValue = playbackRate.rawValue
        self.retainsAudio = retainsAudio
        self.transcriptRevision = 0
        self.generatedFromTranscriptRevision = 0
        self.userEditedNotes = false
        self.lastErrorMessage = nil
        self.calendarEventData = calendarEvent.flatMap { try? JSONEncoder().encode($0) }
        self.folder = nil
        self.manualOrder = nil
    }

    var lifecycle: NoteLifecycle {
        get { NoteLifecycle(rawValue: lifecycleRawValue) ?? .recoverable }
        set { lifecycleRawValue = newValue.rawValue }
    }

    var processingStage: ProcessingStage? {
        get { processingStageRawValue.flatMap(ProcessingStage.init(rawValue:)) }
        set { processingStageRawValue = newValue?.rawValue }
    }

    var transcriptSegments: [TranscriptSegment] {
        get { (try? JSONDecoder().decode([TranscriptSegment].self, from: transcriptData)) ?? [] }
        set { transcriptData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var templateSnapshot: TemplateSnapshot {
        TemplateSnapshot(name: templateName, symbol: templateSymbol, instructions: templateInstructions)
    }

    var recordingMode: RecordingMode {
        get { recordingModeRawValue.flatMap(RecordingMode.init(rawValue:)) ?? .listenAlong }
        set { recordingModeRawValue = newValue.rawValue }
    }

    var playbackRate: PlaybackRate {
        get { PlaybackRate(rawValue: playbackRateValue) ?? .natural }
        set { playbackRateValue = newValue.rawValue }
    }

    var calendarEvent: CalendarEventSnapshot? {
        get {
            calendarEventData.flatMap {
                try? JSONDecoder().decode(CalendarEventSnapshot.self, from: $0)
            }
        }
        set {
            calendarEventData = newValue.flatMap { try? JSONEncoder().encode($0) }
        }
    }

    var continuationRecordingOptions: RecordingOptions {
        RecordingOptions(
            template: templateSnapshot,
            languageIdentifier: languageIdentifier,
            mode: recordingMode,
            retainsAudio: retainsAudio,
            playbackRate: playbackRate
        )
    }

    var notesMayBeOutdated: Bool {
        transcriptRevision != generatedFromTranscriptRevision
    }

    var exportedMarkdown: String {
        let human = userNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let generated = GeneratedNote
            .strippedSourceArtifacts(from: markdownBody)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !human.isEmpty else { return generated }
        guard !generated.isEmpty else {
            return "## Your notes\n\n\(human)"
        }
        return """
            ## Your notes

            \(human)

            ---

            ## Burrito notes

            \(generated)
            """
    }

    func replaceTranscript(with segments: [TranscriptSegment], marksEdited: Bool) {
        transcriptSegments = segments
        transcriptRevision += 1
        updatedAt = .now
        if !marksEdited {
            generatedFromTranscriptRevision = transcriptRevision
        }
    }
}

extension Note {
    /// Display order inside one day group. Once any note in the group has a
    /// manual order (the user reordered the timeline), manual positions win
    /// and new notes without one sink below the reordered ones; otherwise
    /// the most recently updated note comes first.
    static func orderedWithinDay(_ notes: [Note]) -> [Note] {
        guard notes.contains(where: { $0.manualOrder != nil }) else {
            return notes.sorted { $0.updatedAt > $1.updatedAt }
        }
        let manual = notes
            .filter { $0.manualOrder != nil }
            .sorted { ($0.manualOrder ?? 0) < ($1.manualOrder ?? 0) }
        let rest = notes
            .filter { $0.manualOrder == nil }
            .sorted { $0.updatedAt > $1.updatedAt }
        return manual + rest
    }
}

enum SeedData {
    @MainActor
    static func insertBuiltInTemplatesIfNeeded(context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<NoteTemplate>())
        let existingIDs = Set(existing.compactMap(\.builtInID))

        for template in BuiltInTemplate.allCases {
            if !existingIDs.contains(template.rawValue) {
                context.insert(
                    NoteTemplate(
                        builtInID: template.rawValue,
                        name: template.name,
                        symbol: template.symbol,
                        instructions: template.instructions
                    )
                )
            } else if let stored = existing.first(where: { $0.builtInID == template.rawValue }),
                      stored.instructions == template.legacyInstructions
                        || stored.instructions == template.previousInstructions
                        || stored.instructions == template.expandedInstructions {
                stored.instructions = template.instructions
            }
        }
        try context.save()
    }
}
