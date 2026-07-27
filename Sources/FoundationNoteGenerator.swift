import Foundation
import FoundationModels

enum GenerationPrompt {
    static let digestInstructions = "Extract only facts present in the transcript. Preserve names, decisions, examples, and action items. Do not add commentary."

    static func finalInstructions(template: TemplateSnapshot) -> String {
        """
        Write accurate local notes from the supplied factual digest.
        Follow this template: \(template.instructions)
        Return exactly:
        TITLE: <short title>
        NOTE:
        <Markdown note>
        """
    }
}

struct TranscriptChunker: Sendable {
    let tokenMeasurer: any PromptTokenMeasuring
    let reservedOutputTokens: Int

    init(tokenMeasurer: any PromptTokenMeasuring, reservedOutputTokens: Int = 1_024) {
        self.tokenMeasurer = tokenMeasurer
        self.reservedOutputTokens = reservedOutputTokens
    }

    func chunks(for segments: [TranscriptSegment]) async throws -> [PromptChunk] {
        let limit = max(256, await tokenMeasurer.contextSize - reservedOutputTokens)
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

actor AppleModelAdapter: PromptTokenMeasuring, TextCompleting {
    private let model = SystemLanguageModel.default

    var contextSize: Int { model.contextSize }

    func tokenCount(_ text: String) async throws -> Int {
        if #available(macOS 26.4, *) {
            return try await model.tokenCount(for: text)
        }
        return max(1, text.utf8.count / 3)
    }

    func complete(instructions: String, prompt: String) async throws -> String {
        let session = LanguageModelSession(model: model, instructions: instructions)
        return try await session.respond(to: prompt).content
    }
}

struct FoundationNoteGenerator: NoteGenerating {
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
            let chunker = TranscriptChunker(tokenMeasurer: adapter)
            let chunks = try await chunker.chunks(for: segments)
            var digests: [String] = []

            for chunk in chunks {
                let digest = try await adapter.complete(
                    instructions: GenerationPrompt.digestInstructions,
                    prompt: "Create a compact factual digest of this timestamped transcript:\n\n\(chunk.text)"
                )
                digests.append(digest)
            }

            let condensed = try await recursivelyCondense(digests)
            let final = try await adapter.complete(
                instructions: GenerationPrompt.finalInstructions(template: template),
                prompt: condensed
            )
            guard let parsed = parseFinal(final) else {
                return .failure(
                    .generationFailed(details: "The model returned an unexpected note format.")
                )
            }
            return .success(parsed)
        } catch {
            return .failure(.generationFailed(details: error.localizedDescription))
        }
    }

    private func recursivelyCondense(_ values: [String]) async throws -> String {
        let limit = max(256, await adapter.contextSize - 1_024)
        var current = values

        while try await adapter.tokenCount(current.joined(separator: "\n\n")) > limit {
            var next: [String] = []
            var batch: [String] = []
            for value in current {
                let candidate = (batch + [value]).joined(separator: "\n\n")
                if !batch.isEmpty, try await adapter.tokenCount(candidate) > limit {
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
            instructions: "Combine these factual digests without inventing, omitting decisions, or duplicating facts.",
            prompt: values.joined(separator: "\n\n")
        )
    }

    private func parseFinal(_ value: String) -> GeneratedNote? {
        guard let noteRange = value.range(of: "\nNOTE:") else { return nil }
        let titlePart = value[..<noteRange.lowerBound]
            .replacingOccurrences(of: "TITLE:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let body = value[noteRange.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !titlePart.isEmpty, !body.isEmpty else { return nil }
        return GeneratedNote(title: titlePart, markdown: body)
    }
}
