@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import Speech
import Synchronization

final class LiveTranscriptStore: Sendable {
    private struct State: Sendable {
        var availability: LiveTranscriptionAvailability = .preparing
        var passages: [LiveTranscriptPassage] = []
    }

    private let state = Mutex(State())

    var snapshot: LiveTranscriptSnapshot {
        state.withLock { state in
            LiveTranscriptSnapshot(
                availability: state.availability,
                passages: state.passages.sorted {
                    if $0.startTime == $1.startTime {
                        return $0.source.rawValue < $1.source.rawValue
                    }
                    return $0.startTime < $1.startTime
                }
            )
        }
    }

    func markAvailable() {
        state.withLock { $0.availability = .available }
    }

    func markUnavailable(_ reason: String) {
        state.withLock { $0.availability = .unavailable(reason: reason) }
    }

    func apply(
        source: AudioSource,
        startTime: TimeInterval,
        duration: TimeInterval,
        text: String,
        isFinal: Bool,
        finalizedThrough: TimeInterval
    ) {
        var passage = LiveTranscriptPassage(
            source: source,
            startTime: startTime,
            duration: duration,
            text: text,
            isFinal: isFinal
        )
        state.withLock { state in
            var shouldAppend = true
            var reusedID: UUID?
            state.passages = state.passages.compactMap { existing in
                guard existing.source == source else { return existing }
                if Self.rangesOverlap(existing, passage) {
                    if existing.isFinal && !isFinal {
                        shouldAppend = false
                        return existing
                    }
                    reusedID = reusedID ?? existing.id
                    return nil
                }
                if !existing.isFinal,
                   existing.startTime + existing.duration <= finalizedThrough {
                    return LiveTranscriptPassage(
                        id: existing.id,
                        source: existing.source,
                        startTime: existing.startTime,
                        duration: existing.duration,
                        text: existing.text,
                        isFinal: true
                    )
                }
                return existing
            }
            if shouldAppend {
                if let reusedID {
                    passage = LiveTranscriptPassage(
                        id: reusedID,
                        source: passage.source,
                        startTime: passage.startTime,
                        duration: passage.duration,
                        text: passage.text,
                        isFinal: passage.isFinal
                    )
                }
                state.passages.append(passage)
            }
            if state.passages.count > 160 {
                state.passages.removeFirst(state.passages.count - 160)
            }
        }
    }

    private static func rangesOverlap(
        _ left: LiveTranscriptPassage,
        _ right: LiveTranscriptPassage
    ) -> Bool {
        let tolerance = 0.08
        let leftEnd = left.startTime + max(left.duration, tolerance)
        let rightEnd = right.startTime + max(right.duration, tolerance)
        return left.startTime < rightEnd && right.startTime < leftEnd
    }
}

final class LiveSpeechTranscriptionSession: Sendable {
    let store: LiveTranscriptStore

    private let channels: [AudioSource: LiveSpeechChannel]

    private init(
        store: LiveTranscriptStore,
        channels: [AudioSource: LiveSpeechChannel]
    ) {
        self.store = store
        self.channels = channels
    }

    static func make(
        languageIdentifier: String,
        sources: [AudioSource],
        store: LiveTranscriptStore
    ) async -> Result<LiveSpeechTranscriptionSession, BurritoError> {
        let requested = Locale(identifier: languageIdentifier)
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requested) else {
            let error = BurritoError.unsupportedLanguage(identifier: languageIdentifier)
            store.markUnavailable(error.recoveryMessage)
            return .failure(error)
        }

        var channels: [AudioSource: LiveSpeechChannel] = [:]
        do {
            for source in sources {
                channels[source] = try await LiveSpeechChannel(
                    locale: locale,
                    source: source,
                    store: store
                )
            }
            store.markAvailable()
            return .success(
                LiveSpeechTranscriptionSession(store: store, channels: channels)
            )
        } catch {
            for channel in channels.values {
                await channel.finish()
            }
            let failure = BurritoError.transcriptionFailed(
                details: "Live transcription could not start: \(error.localizedDescription)"
            )
            store.markUnavailable(failure.recoveryMessage)
            return .failure(failure)
        }
    }

    func append(
        _ buffer: AVAudioPCMBuffer,
        presentationTime: CMTime,
        source: AudioSource
    ) {
        channels[source]?.append(buffer, presentationTime: presentationTime)
    }

    func finish() async {
        for channel in channels.values {
            await channel.finish()
        }
    }
}

private final class LiveSpeechChannel: Sendable {
    private let analyzer: SpeechAnalyzer
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private let analysisTask: Task<Void, Never>
    private let resultsTask: Task<Void, Never>
    private let audioConverter: SpeechAudioConversion
    private let store: LiveTranscriptStore

    init(
        locale: Locale,
        source: AudioSource,
        store: LiveTranscriptStore
    ) async throws {
        let transcriber = SpeechTranscriber(
            locale: locale,
            preset: .timeIndexedProgressiveTranscription
        )
        guard case .installed = await AssetInventory.status(forModules: [transcriber]) else {
            throw BurritoError.languageAssetMissing(identifier: locale.identifier)
        }
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber]
        ) else {
            throw BurritoError.transcriptionFailed(
                details: "A compatible live transcription audio format is unavailable."
            )
        }

        let pair = AsyncStream<AnalyzerInput>.makeStream(
            bufferingPolicy: .bufferingNewest(256)
        )
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.prepareToAnalyze(in: analyzerFormat)

        self.analyzer = analyzer
        self.continuation = pair.continuation
        self.audioConverter = SpeechAudioConversion(outputFormat: analyzerFormat)
        self.store = store
        self.analysisTask = Task {
            do {
                try await analyzer.start(inputSequence: pair.stream)
            } catch {
                store.markUnavailable(
                    "Live transcription stopped: \(error.localizedDescription). The recording is still being saved."
                )
            }
        }
        self.resultsTask = Task {
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    store.apply(
                        source: source,
                        startTime: max(0, result.range.start.seconds),
                        duration: max(0, result.range.duration.seconds),
                        text: text,
                        isFinal: result.isFinal,
                        finalizedThrough: max(0, result.resultsFinalizationTime.seconds)
                    )
                }
            } catch {
                store.markUnavailable(
                    "Live transcription results stopped: \(error.localizedDescription). The recording is still being saved."
                )
            }
        }
    }

    func append(_ buffer: AVAudioPCMBuffer, presentationTime: CMTime) {
        do {
            let converted = try audioConverter.convert(buffer)
            let result = continuation.yield(
                AnalyzerInput(buffer: converted, bufferStartTime: presentationTime)
            )
            if case .dropped = result {
                store.markUnavailable(
                    "Live transcription fell behind and skipped some audio. The recording is still being saved."
                )
            }
        } catch {
            store.markUnavailable(
                "Live audio conversion stopped: \(error.localizedDescription). The recording is still being saved."
            )
        }
    }

    func finish() async {
        continuation.finish()
        do {
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            store.markUnavailable(
                "Live transcription could not finalize: \(error.localizedDescription). The saved recording is intact."
            )
        }
        _ = await analysisTask.result
        _ = await resultsTask.result
    }
}

private final class SpeechAudioConversion: Sendable {
    private struct State {
        var inputFormat: AVAudioFormat?
        var converter: AVAudioConverter?
    }

    private let outputFormat: AVAudioFormat
    // AVAudioConverter is not Sendable; the mutex serializes all access to it.
    private let state = Mutex(State())

    init(outputFormat: AVAudioFormat) {
        self.outputFormat = outputFormat
    }

    func convert(_ input: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        try state.withLock { state in
            if state.inputFormat?.isEqual(input.format) != true {
                guard let converter = AVAudioConverter(from: input.format, to: outputFormat) else {
                    throw BurritoError.transcriptionFailed(
                        details: "The live audio format could not be converted for speech recognition."
                    )
                }
                state.inputFormat = input.format
                state.converter = converter
            }
            guard let converter = state.converter else {
                throw BurritoError.transcriptionFailed(
                    details: "The live audio converter is unavailable."
                )
            }

            let rateRatio = outputFormat.sampleRate / input.format.sampleRate
            let capacity = AVAudioFrameCount(
                ceil(Double(input.frameLength) * rateRatio) + 32
            )
            guard let output = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: capacity
            ) else {
                throw BurritoError.transcriptionFailed(
                    details: "A live speech audio buffer could not be allocated."
                )
            }

            let suppliedInput = Mutex(false)
            var conversionError: NSError?
            let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
                let shouldSupply = suppliedInput.withLock { supplied in
                    guard !supplied else { return false }
                    supplied = true
                    return true
                }
                guard shouldSupply else {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                inputStatus.pointee = .haveData
                return input
            }
            if let conversionError {
                throw conversionError
            }
            guard status != .error, output.frameLength > 0 else {
                throw BurritoError.transcriptionFailed(
                    details: "Live audio conversion produced no speech samples."
                )
            }
            return output
        }
    }
}
