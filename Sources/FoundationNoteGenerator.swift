import Foundation
import FoundationModels

enum GenerationPrompt {
    static let digestInstructions = "Extract only facts present in the transcript. Preserve names, decisions, examples, and action items. Do not add commentary."
    static let digestPrefix = "Create a compact factual digest of this timestamped transcript:\n\n"
    static let condenseInstructions = "Combine these factual digests into a shorter digest without inventing facts, omitting decisions, or duplicating information."

    static func finalInstructions(template: TemplateSnapshot) -> String {
        """
        Write accurate local notes from the supplied factual digest.
        Follow this template: \(template.instructions)
        Return a short TITLE: and a complete NOTE: in Markdown.
        """
    }

    static func titleInstructions(currentTitle: String) -> String {
        """
        Return only a short title for the dominant subject of the complete factual digest.
        The current title is "\(currentTitle)".
        Keep it when it still describes the dominant subject. Change it when the transcript
        has clearly shifted and another subject now occupies most of the discussion.
        Do not use quotes, labels, commentary, or Markdown.
        """
    }
}

struct TranscriptChunker: Sendable {
    let tokenMeasurer: any PromptTokenMeasuring
    let reservedOutputTokens: Int
    let reservedInputTokens: Int

    init(
        tokenMeasurer: any PromptTokenMeasuring,
        reservedOutputTokens: Int = 1_024,
        reservedInputTokens: Int = 0
    ) {
        self.tokenMeasurer = tokenMeasurer
        self.reservedOutputTokens = reservedOutputTokens
        self.reservedInputTokens = reservedInputTokens
    }

    func chunks(for segments: [TranscriptSegment]) async throws -> [PromptChunk] {
        let limit = max(
            256,
            await tokenMeasurer.contextSize - reservedOutputTokens - reservedInputTokens
        )
        var chunks: [PromptChunk] = []
        var current: [TranscriptSegment] = []

        for segment in segments {
            let candidate = current + [segment]
            if !current.isEmpty,
               try await tokenMeasurer.tokenCount(Transcript.rendered(candidate)) > limit {
                chunks.append(PromptChunk(segments: current))
                current = [segment]
            } else {
                current = candidate
            }
        }
        if !current.isEmpty {
            chunks.append(PromptChunk(segments: current))
        }
        return chunks
    }
}

@Generable
private struct GeneratedNoteResponse {
    @Guide(description: "A short title without Markdown formatting.")
    var title: String

    @Guide(description: "The complete note formatted as Markdown.")
    var markdown: String
}

actor AppleModelAdapter: PromptTokenMeasuring, TextCompleting {
    private let model = SystemLanguageModel.default

    var contextSize: Int { model.contextSize }

    func tokenCount(_ text: String) async throws -> Int {
        if #available(macOS 26.4, *) {
            return try await model.tokenCount(for: text)
        }
        return max(1, text.utf8.count / 3)
    }

    func complete(
        instructions: String,
        prompt: String,
        maximumResponseTokens: Int
    ) async throws -> String {
        let session = LanguageModelSession(model: model, instructions: instructions)
        let options = GenerationOptions(
            sampling: nil,
            temperature: nil,
            maximumResponseTokens: maximumResponseTokens
        )
        return try await session.respond(to: prompt, options: options).content
    }

    func completeNote(
        instructions: String,
        prompt: String,
        maximumResponseTokens: Int
    ) async throws -> GeneratedNote {
        let session = LanguageModelSession(model: model, instructions: instructions)
        let options = GenerationOptions(
            sampling: nil,
            temperature: nil,
            maximumResponseTokens: maximumResponseTokens
        )
        let response = try await session.respond(
            to: prompt,
            generating: GeneratedNoteResponse.self,
            options: options
        ).content
        return GeneratedNote(
            title: response.title.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
            markdown: response.markdown.trimmingCharacters(
                in: CharacterSet.whitespacesAndNewlines
            )
        )
    }
}

struct FoundationNoteGenerator: NoteGenerating {
    private enum TokenBudget {
        static let digestOutput = 512
        static let condensedOutput = 512
        static let finalOutput = 1_024
        static let titleOutput = 64
        static let safetyMargin = 256
        static let generatedNoteSchema = 256
    }

    private let model = SystemLanguageModel.default
    private let adapter: AppleModelAdapter

    init(adapter: AppleModelAdapter = AppleModelAdapter()) {
        self.adapter = adapter
    }

    func availability(languageIdentifier: String) async -> Result<Void, BurritoError> {
        switch model.availability {
        case .available:
            guard model.supportsLocale(Locale(identifier: languageIdentifier)) else {
                return .failure(
                    .appleIntelligenceUnavailable(
                        reason: "The selected language is not supported by the on-device model."
                    )
                )
            }
            return .success(())
        case .unavailable(let reason):
            let message = switch reason {
            case .deviceNotEligible: "this Mac is not eligible"
            case .appleIntelligenceNotEnabled: "Apple Intelligence is disabled"
            case .modelNotReady: "the on-device model is not ready"
            @unknown default: "the on-device model reported an unknown availability state"
            }
            return .failure(.appleIntelligenceUnavailable(reason: message))
        }
    }

    func generate(
        segments: [TranscriptSegment],
        template: TemplateSnapshot,
        languageIdentifier: String
    ) async -> Result<GeneratedNote, BurritoError> {
        let available = await availability(languageIdentifier: languageIdentifier)
        if case .failure(let error) = available { return .failure(error) }

        do {
            let finalInstructions = GenerationPrompt.finalInstructions(template: template)
            let condensed = try await factualDigest(
                segments: segments,
                finalInstructions: finalInstructions,
                reservedOutputTokens: TokenBudget.finalOutput,
                additionalReservedTokens: TokenBudget.generatedNoteSchema
            )
            let generated = try await adapter.completeNote(
                instructions: finalInstructions,
                prompt: condensed,
                maximumResponseTokens: TokenBudget.finalOutput
            )
            guard !generated.title.isEmpty, !generated.markdown.isEmpty else {
                return .failure(
                    .generationFailed(details: "The model returned an empty title or note.")
                )
            }
            return .success(generated)
        } catch {
            return .failure(.generationFailed(details: error.localizedDescription))
        }
    }

    func suggestTitle(
        segments: [TranscriptSegment],
        currentTitle: String,
        languageIdentifier: String
    ) async -> Result<String, BurritoError> {
        let available = await availability(languageIdentifier: languageIdentifier)
        if case .failure(let error) = available { return .failure(error) }

        do {
            let instructions = GenerationPrompt.titleInstructions(currentTitle: currentTitle)
            let digest = try await factualDigest(
                segments: segments,
                finalInstructions: instructions,
                reservedOutputTokens: TokenBudget.titleOutput
            )
            let response = try await adapter.complete(
                instructions: instructions,
                prompt: digest,
                maximumResponseTokens: TokenBudget.titleOutput
            )
            let firstLine = response.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            let unlabeledTitle = firstLine.lowercased().hasPrefix("title:")
                ? String(firstLine.dropFirst("title:".count))
                : firstLine
            let title = unlabeledTitle.trimmingCharacters(
                in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "#*\""))
            )
            guard !title.isEmpty else {
                return .failure(.generationFailed(details: "The model returned an empty title."))
            }
            return .success(title)
        } catch {
            return .failure(.generationFailed(details: error.localizedDescription))
        }
    }

    private func factualDigest(
        segments: [TranscriptSegment],
        finalInstructions: String,
        reservedOutputTokens: Int,
        additionalReservedTokens: Int = 0
    ) async throws -> String {
        let digestOverhead = try await tokenCount(
            GenerationPrompt.digestInstructions + GenerationPrompt.digestPrefix
        )
        let chunker = TranscriptChunker(
            tokenMeasurer: adapter,
            reservedOutputTokens: TokenBudget.digestOutput,
            reservedInputTokens: digestOverhead + TokenBudget.safetyMargin
        )
        let chunks = try await chunker.chunks(for: segments)
        var digests: [String] = []

        for chunk in chunks {
            let digest = try await adapter.complete(
                instructions: GenerationPrompt.digestInstructions,
                prompt: GenerationPrompt.digestPrefix + chunk.text,
                maximumResponseTokens: TokenBudget.digestOutput
            )
            digests.append(digest)
        }

        let finalInputLimit = try await inputLimit(
            instructions: finalInstructions,
            reservedOutputTokens: reservedOutputTokens,
            additionalReservedTokens: additionalReservedTokens
        )
        let condenseInputLimit = try await inputLimit(
            instructions: GenerationPrompt.condenseInstructions,
            reservedOutputTokens: TokenBudget.condensedOutput
        )
        return try await recursivelyCondense(
            digests,
            finalInputLimit: finalInputLimit,
            condenseInputLimit: condenseInputLimit
        )
    }

    private func recursivelyCondense(
        _ values: [String],
        finalInputLimit: Int,
        condenseInputLimit: Int
    ) async throws -> String {
        var current = values

        while try await tokenCount(current.joined(separator: "\n\n")) > finalInputLimit {
            var next: [String] = []
            var batch: [String] = []
            for value in current {
                let candidate = (batch + [value]).joined(separator: "\n\n")
                if !batch.isEmpty, try await tokenCount(candidate) > condenseInputLimit {
                    next.append(try await condense(batch))
                    batch = [value]
                } else {
                    batch.append(value)
                }
            }
            if !batch.isEmpty {
                next.append(try await condense(batch))
            }
            current = next
        }
        return current.joined(separator: "\n\n")
    }

    private func condense(_ values: [String]) async throws -> String {
        try await adapter.complete(
            instructions: GenerationPrompt.condenseInstructions,
            prompt: values.joined(separator: "\n\n"),
            maximumResponseTokens: TokenBudget.condensedOutput
        )
    }

    private func inputLimit(
        instructions: String,
        reservedOutputTokens: Int,
        additionalReservedTokens: Int = 0
    ) async throws -> Int {
        let instructionTokens = try await tokenCount(instructions)
        return max(
            256,
            await adapter.contextSize
                - reservedOutputTokens
                - additionalReservedTokens
                - TokenBudget.safetyMargin
                - instructionTokens
        )
    }

    private func tokenCount(_ text: String) async throws -> Int {
        try await adapter.tokenCount(text)
    }
}
