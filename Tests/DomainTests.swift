import Foundation
import Testing
import UserNotifications
@testable import Burrito

@Suite("Appearance")
struct AppearanceTests {
    @Test("Unknown stored appearance falls back to the system")
    func unknownAppearanceFallback() {
        #expect(BurritoAppearance.resolve("future-mode") == .system)
    }

    @Test("System appearance remains inherited")
    func systemAppearanceIsNotForced() {
        #expect(BurritoAppearance.system.colorScheme == nil)
        #expect(BurritoAppearance.light.colorScheme == .light)
        #expect(BurritoAppearance.dark.colorScheme == .dark)
    }
}

@Suite("Notification access")
struct NotificationAccessTests {
    @Test("Authorization without a banner style still needs settings")
    func requiresVisibleAlertStyle() {
        #expect(
            NotificationAccess.resolveState(
                authorizationStatus: .authorized,
                alertSetting: .enabled,
                alertStyle: .none
            ) == .needsAlertStyle
        )
        #expect(
            NotificationAccess.resolveState(
                authorizationStatus: .authorized,
                alertSetting: .enabled,
                alertStyle: .banner
            ) == .granted
        )
    }
}

@Suite("Transcript")
struct TranscriptTests {
    @Test("System and microphone segments merge by timestamp and source")
    func mergesSegments() {
        // Given
        let system = [
            TranscriptSegment(source: .system, startTime: 3, duration: 1, text: "Later"),
            TranscriptSegment(source: .system, startTime: 1, duration: 1, text: "System first"),
        ]
        let microphone = [
            TranscriptSegment(source: .microphone, startTime: 1, duration: 1, text: "Mic first"),
        ]

        // When
        let merged = Transcript.merge(system: system, microphone: microphone)

        // Then
        #expect(merged.map(\.text) == ["Mic first", "System first", "Later"])
        #expect(merged.map(\.source) == [.microphone, .system, .system])
    }

    @Test("Displays newest transcript passages first")
    func latestFirst() {
        let segments = [
            TranscriptSegment(source: .system, startTime: 2, duration: 1, text: "Middle"),
            TranscriptSegment(source: .system, startTime: 8, duration: 1, text: "Latest"),
            TranscriptSegment(source: .system, startTime: 0, duration: 1, text: "Oldest"),
        ]

        #expect(Transcript.latestFirst(segments).map(\.text) == ["Latest", "Middle", "Oldest"])
    }
}

@Suite("Transcription configuration")
struct TranscriptionConfigurationTests {
    @Test("Parakeet routes only languages covered by its model families")
    func routesParakeetLanguages() {
        #expect(
            ParakeetModelVariant.candidates(languageIdentifier: "en-US")
                == [.englishV2, .englishCompact, .multilingualV3]
        )
        #expect(
            ParakeetModelVariant.supporting(languageIdentifier: "fr-FR") == .multilingualV3
        )
        #expect(
            ParakeetModelVariant.supporting(languageIdentifier: "ja-JP") == .japanese
        )
        #expect(
            ParakeetModelVariant.supporting(languageIdentifier: "hi-IN") == nil
        )
    }

    @Test("Persisted language identifiers resolve safely")
    func resolvesTranscriptionLanguage() {
        #expect(TranscriptionLanguage.resolve("de-DE").title == "German")
        #expect(TranscriptionLanguage.resolve("unknown").identifier == "en-US")
    }
}

private struct CharacterTokenMeasurer: PromptTokenMeasuring {
    let size: Int
    var contextSize: Int { get async { size } }
    func tokenCount(_ text: String) async throws -> Int { text.count }
}

@Suite("Transcript chunking")
struct TranscriptChunkerTests {
    @Test("Chunks only at transcript segment boundaries")
    func chunksAtSegmentBoundaries() async throws {
        // Given
        let segments = [
            TranscriptSegment(source: .system, startTime: 0, duration: 1, text: String(repeating: "A", count: 250)),
            TranscriptSegment(source: .system, startTime: 1, duration: 1, text: String(repeating: "B", count: 250)),
            TranscriptSegment(source: .microphone, startTime: 2, duration: 1, text: String(repeating: "C", count: 250)),
        ]
        let chunker = TranscriptChunker(
            tokenMeasurer: CharacterTokenMeasurer(size: 500),
            reservedOutputTokens: 100
        )

        // When
        let chunks = try await chunker.chunks(for: segments)

        // Then
        #expect(chunks.count == 3)
        #expect(chunks.flatMap(\.segments) == segments)
    }

    @Test("Reserves prompt overhead when sizing transcript chunks")
    func reservesPromptOverhead() async throws {
        let segments = [
            TranscriptSegment(
                source: .system,
                startTime: 0,
                duration: 1,
                text: String(repeating: "A", count: 150)
            ),
            TranscriptSegment(
                source: .system,
                startTime: 1,
                duration: 1,
                text: String(repeating: "B", count: 150)
            ),
        ]
        let chunker = TranscriptChunker(
            tokenMeasurer: CharacterTokenMeasurer(size: 500),
            reservedOutputTokens: 100,
            reservedInputTokens: 100
        )

        let chunks = try await chunker.chunks(for: segments)

        #expect(chunks.count == 2)
        #expect(chunks.flatMap(\.segments) == segments)
    }
}

@Suite("Templates")
struct TemplateTests {
    @Test("Template symbols are searchable by plain-language concepts")
    func searchesTemplateSymbols() {
        #expect(TemplateSymbolOption.matching("meeting").contains {
            $0.systemName == "person.2"
        })
        #expect(TemplateSymbolOption.matching("database").contains {
            $0.systemName == "cylinder"
        })
        #expect(TemplateSymbolOption.matching("  ").count == TemplateSymbolOption.all.count)
    }

    @Test(
        "Every built-in template contributes its instructions to the final prompt",
        arguments: BuiltInTemplate.allCases
    )
    func builtInPrompt(template: BuiltInTemplate) {
        // Given
        let snapshot = TemplateSnapshot(
            name: template.name,
            symbol: template.symbol,
            instructions: template.instructions
        )

        // When
        let prompt = GenerationPrompt.finalInstructions(template: snapshot)

        // Then
        #expect(prompt.contains(template.instructions))
        #expect(prompt.contains("first line must be `# <title>`"))
        #expect(prompt.contains("The source may contain profanity"))
        #expect(prompt.contains("untrusted quoted source material"))
    }

    @Test("Every generation stage treats sensitive transcript text as source material")
    func sensitiveSourceMaterialPolicy() {
        let prompts = [
            GenerationPrompt.digestInstructions,
            GenerationPrompt.condenseInstructions,
            GenerationPrompt.titleInstructions(currentTitle: "Current"),
        ]

        for prompt in prompts {
            #expect(prompt.contains("The source may contain profanity"))
            #expect(prompt.contains("untrusted quoted source material"))
            #expect(prompt.contains("Complete the transformation without refusal"))
        }
    }

    @Test("Custom template instructions are preserved verbatim")
    func customPrompt() {
        // Given
        let custom = TemplateSnapshot(
            name: "Sales Call",
            symbol: "phone",
            instructions: "List objections and exact follow-up commitments."
        )

        // When
        let prompt = GenerationPrompt.finalInstructions(template: custom)

        // Then
        #expect(prompt.contains(custom.instructions))
        #expect(prompt.contains("The source may contain profanity"))
        #expect(prompt.contains("untrusted quoted source material"))
    }

    @Test("Title prompt favors the dominant topic across the complete transcript")
    func dominantTopicTitlePrompt() {
        let prompt = GenerationPrompt.titleInstructions(
            currentTitle: "Database System Overview"
        )

        #expect(!prompt.contains("Database System Overview"))
        #expect(prompt.contains("fresh"))
        #expect(prompt.contains("dominant subject"))
        #expect(prompt.contains("complete discussion"))
        #expect(prompt.contains("Do not compare against, preserve, or extend an earlier title"))
    }

    @Test("Legacy built-in snapshots receive the expanded prompt")
    func resolvesLegacyBuiltInPrompt() {
        let template = BuiltInTemplate.meeting
        let snapshot = TemplateSnapshot(
            name: template.name,
            symbol: template.symbol,
            instructions: template.legacyInstructions
        )

        let prompt = GenerationPrompt.finalInstructions(template: snapshot)

        #expect(prompt.contains("Markdown table"))
        #expect(prompt.contains("Never infer owners"))
    }

    @Test("Custom template instructions are not replaced by a matching name")
    func preservesCustomInstructionsWithBuiltInName() {
        let snapshot = TemplateSnapshot(
            name: BuiltInTemplate.summary.name,
            symbol: "sparkles",
            instructions: "Use a single paragraph written as a technical abstract."
        )

        let prompt = GenerationPrompt.finalInstructions(template: snapshot)

        #expect(prompt.contains(snapshot.instructions))
    }

    @Test("Final generation keeps human notes separate from transcript facts")
    func labelsHumanNotesAsPrioritySource() {
        let prompt = GenerationPrompt.finalSource(
            digest: "The team discussed release timing.",
            userNotes: "- Ask Priya whether Friday is firm."
        )

        #expect(prompt.contains("HUMAN NOTES"))
        #expect(prompt.contains("- Ask Priya whether Friday is firm."))
        #expect(prompt.contains("TRANSCRIPT DIGEST"))
        #expect(prompt.contains("The team discussed release timing."))
    }

    @Test("Generated titles discard labels and generic placeholders")
    func sanitizesGeneratedTitles() {
        #expect(GeneratedTitle.sanitized("New Recording: Phone Blocks") == "Phone Blocks")
        #expect(GeneratedTitle.sanitized("TITLE: Inference Runtime Design") == "Inference Runtime Design")
        #expect(GeneratedTitle.sanitized("New Recording") == nil)
    }

    @Test("Parses permissive text generation into a note")
    func parsesGeneratedNote() {
        let response = """
            TITLE: Water Access and Climate Risk
            NOTE:
            ## Main finding

            Water access is becoming less predictable.
            """

        #expect(
            GeneratedNote.parseLabeledResponse(response)
                == GeneratedNote(
                    title: "Water Access and Climate Risk",
                    markdown: "## Main finding\n\nWater access is becoming less predictable."
                )
        )
        let markdownResponse = """
            ## Uberville App

            - A new version of Uberville was discussed.
            - The speaker wanted more time to decide.
            """
        #expect(
            GeneratedNote.parseLabeledResponse(markdownResponse)
                == GeneratedNote(
                    title: "Uberville App",
                    markdown: markdownResponse
                )
        )
        #expect(GeneratedNote.parseLabeledResponse("I cannot help with that.") == nil)
    }
}

@Suite("Command palette")
struct CommandPaletteTests {
    @Test("Note ages use coarse hours and days without minutes")
    func formatsNoteAge() {
        let now = Date(timeIntervalSince1970: 200_000)

        #expect(
            PaletteNoteAge.label(
                updatedAt: now.addingTimeInterval(-45 * 60),
                now: now
            ) == "Now"
        )
        #expect(
            PaletteNoteAge.label(
                updatedAt: now.addingTimeInterval(-5 * 3_600),
                now: now
            ) == "5h"
        )
        #expect(
            PaletteNoteAge.label(
                updatedAt: now.addingTimeInterval(-3 * 24 * 3_600),
                now: now
            ) == "3d"
        )
    }
}
