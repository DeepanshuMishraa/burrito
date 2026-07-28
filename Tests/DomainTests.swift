import Foundation
import Testing
@testable import Burrito

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
        #expect(prompt.contains("TITLE:"))
        #expect(prompt.contains("NOTE:"))
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
        #expect(GeneratedNote.parseLabeledResponse("I cannot help with that.") == nil)
    }
}
