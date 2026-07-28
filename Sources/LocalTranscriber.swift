import AVFoundation
import CoreMedia
import Foundation
import Speech

private struct AppleSpeechTranscriber: Transcribing {
    func verifyLanguage(_ identifier: String) async -> Result<Void, BurritoError> {
        let requested = Locale(identifier: identifier)
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: requested) else {
            return .failure(.unsupportedLanguage(identifier: identifier))
        }
        let transcriber = SpeechTranscriber(
            locale: supported,
            preset: .timeIndexedTranscriptionWithAlternatives
        )
        switch await AssetInventory.status(forModules: [transcriber]) {
        case .installed:
            return .success(())
        case .unsupported:
            return .failure(.unsupportedLanguage(identifier: identifier))
        case .supported, .downloading:
            return .failure(.languageAssetMissing(identifier: identifier))
        @unknown default:
            return .failure(.languageAssetMissing(identifier: identifier))
        }
    }

    func installLanguageAsset(_ identifier: String) async -> Result<Void, BurritoError> {
        let requested = Locale(identifier: identifier)
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: requested) else {
            return .failure(.unsupportedLanguage(identifier: identifier))
        }

        let transcriber = SpeechTranscriber(
            locale: supported,
            preset: .timeIndexedTranscriptionWithAlternatives
        )

        do {
            guard let request = try await AssetInventory.assetInstallationRequest(
                supporting: [transcriber]
            ) else {
                return await verifyLanguage(identifier)
            }
            try await request.downloadAndInstall()
            return await verifyLanguage(identifier)
        } catch {
            return .failure(
                .languageAssetInstallationFailed(
                    identifier: identifier,
                    details: error.localizedDescription
                )
            )
        }
    }

    func transcribe(
        fileURL: URL,
        source: AudioSource,
        languageIdentifier: String
    ) async -> Result<[TranscriptSegment], BurritoError> {
        let languageCheck = await verifyLanguage(languageIdentifier)
        if case .failure(let error) = languageCheck { return .failure(error) }

        do {
            let requested = Locale(identifier: languageIdentifier)
            guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requested) else {
                return .failure(.unsupportedLanguage(identifier: languageIdentifier))
            }
            let transcriber = SpeechTranscriber(
                locale: locale,
                preset: .timeIndexedTranscriptionWithAlternatives
            )
            let audioFile = try AVAudioFile(forReading: fileURL)
            let analyzer = SpeechAnalyzer(modules: [transcriber])

            async let collected = collectResults(from: transcriber, source: source)
            _ = try await analyzer.analyzeSequence(from: audioFile)
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            return .success(try await collected)
        } catch {
            return .failure(.transcriptionFailed(details: error.localizedDescription))
        }
    }

    private func collectResults(
        from transcriber: SpeechTranscriber,
        source: AudioSource
    ) async throws -> [TranscriptSegment] {
        var segments: [TranscriptSegment] = []
        for try await result in transcriber.results where result.isFinal {
            let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            segments.append(
                TranscriptSegment(
                    source: source,
                    startTime: max(0, result.range.start.seconds),
                    duration: max(0, result.range.duration.seconds),
                    text: text
                )
            )
        }
        return segments
    }
}

struct LocalTranscriber: Transcribing {
    private let apple = AppleSpeechTranscriber()
    private let parakeet = ParakeetTranscriber.shared

    func requiresSpeechAuthorization(for identifier: String) -> Bool {
        selectedParakeetModel(for: identifier) == nil
    }

    func verifyLanguage(_ identifier: String) async -> Result<Void, BurritoError> {
        if selectedParakeetModel(for: identifier) != nil {
            return .success(())
        }
        return await apple.verifyLanguage(identifier)
    }

    func installLanguageAsset(_ identifier: String) async -> Result<Void, BurritoError> {
        await apple.installLanguageAsset(identifier)
    }

    func transcribe(
        fileURL: URL,
        source: AudioSource,
        languageIdentifier: String
    ) async -> Result<[TranscriptSegment], BurritoError> {
        guard let variant = selectedParakeetModel(for: languageIdentifier) else {
            return await apple.transcribe(
                fileURL: fileURL,
                source: source,
                languageIdentifier: languageIdentifier
            )
        }

        do {
            let segments = try await parakeet.transcribe(
                fileURL: fileURL,
                source: source,
                variant: variant,
                languageIdentifier: languageIdentifier
            )
            guard !segments.isEmpty else {
                return .failure(
                    .transcriptionFailed(
                        details: "\(variant.displayName) returned an empty transcript. "
                            + "The saved audio is intact; retry processing or choose Apple Speech."
                    )
                )
            }
            return .success(segments)
        } catch {
            return .failure(
                .transcriptionFailed(
                    details: "\(variant.displayName) could not process the saved audio: "
                        + "\(error.localizedDescription). The saved audio is intact; "
                        + "retry processing or choose Apple Speech."
                )
            )
        }
    }

    private func selectedParakeetModel(
        for languageIdentifier: String
    ) -> ParakeetModelVariant? {
        ParakeetModelStore.installedModel(for: languageIdentifier)
    }
}
