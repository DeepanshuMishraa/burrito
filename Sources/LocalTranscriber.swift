import AVFoundation
import CoreMedia
import Foundation
import Speech

struct LocalTranscriber: Transcribing {
    func verifyLanguage(_ identifier: String) async -> Result<Void, BurritoError> {
        let requested = Locale(identifier: identifier)
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: requested) else {
            return .failure(.unsupportedLanguage(identifier: identifier))
        }
        let transcriber = SpeechTranscriber(locale: supported, preset: .timeIndexedProgressiveTranscription)
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
                preset: .timeIndexedProgressiveTranscription
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
