import FluidAudio
import Foundation
import Observation

enum ParakeetModelState: Equatable {
    case notInstalled
    case paused(progress: Double)
    case downloading(progress: Double)
    case installed
    case failed(message: String)
}

@MainActor
@Observable
final class ParakeetModelStore {
    static let shared = ParakeetModelStore()

    private(set) var states: [ParakeetModelVariant: ParakeetModelState] = [:]

    private init() {
        refresh()
    }

    func refresh() {
        for variant in ParakeetModelVariant.allCases {
            guard !isDownloading(variant) else { continue }
            states[variant] = Self.persistedState(for: variant)
        }
    }

    func state(for variant: ParakeetModelVariant) -> ParakeetModelState {
        states[variant] ?? Self.persistedState(for: variant)
    }

    func install(_ variant: ParakeetModelVariant) async {
        states[variant] = .downloading(progress: 0)
        do {
            _ = try await AsrModels.download(
                version: variant.fluidAudioVersion
            ) { [weak self] update in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.states[variant] = .downloading(
                        progress: min(1, max(0, update.fractionCompleted))
                    )
                }
            }
            states[variant] = .installed
        } catch is CancellationError {
            states[variant] = Self.persistedState(for: variant)
        } catch {
            states[variant] = .failed(message: error.localizedDescription)
        }
    }

    nonisolated static func isInstalled(_ variant: ParakeetModelVariant) -> Bool {
        AsrModels.modelsExist(
            at: AsrModels.defaultCacheDirectory(for: variant.fluidAudioVersion),
            version: variant.fluidAudioVersion
        )
    }

    nonisolated static func installedModel(
        for languageIdentifier: String
    ) -> ParakeetModelVariant? {
        ParakeetModelVariant
            .candidates(languageIdentifier: languageIdentifier)
            .first(where: isInstalled)
    }

    nonisolated private static func persistedState(
        for variant: ParakeetModelVariant
    ) -> ParakeetModelState {
        if isInstalled(variant) {
            return .installed
        }
        let progress = cachedDownloadFraction(for: variant)
        return progress > 0 ? .paused(progress: progress) : .notInstalled
    }

    nonisolated private static func cachedDownloadFraction(
        for variant: ParakeetModelVariant
    ) -> Double {
        let directory = AsrModels.defaultCacheDirectory(for: variant.fluidAudioVersion)
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var bytes: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey]
            ),
            values.isRegularFile == true,
            let fileSize = values.fileSize
            else {
                continue
            }
            bytes += Int64(fileSize)
        }
        return min(0.99, max(0, Double(bytes) / Double(variant.downloadSizeBytes)))
    }

    private func isDownloading(_ variant: ParakeetModelVariant) -> Bool {
        guard case .downloading = states[variant] else { return false }
        return true
    }
}

actor ParakeetTranscriber {
    static let shared = ParakeetTranscriber()

    private var manager: AsrManager?
    private var loadedVariant: ParakeetModelVariant?

    func release() {
        manager = nil
        loadedVariant = nil
    }

    func transcribe(
        fileURL: URL,
        source: AudioSource,
        variant: ParakeetModelVariant,
        languageIdentifier: String
    ) async throws -> [TranscriptSegment] {
        let manager = try await manager(for: variant)
        let decoderLayerCount = await manager.decoderLayerCount
        var decoderState = try TdtDecoderState(decoderLayers: decoderLayerCount)
        let languageCode = Locale(identifier: languageIdentifier)
            .language
            .languageCode?
            .identifier
        let language = languageCode.flatMap(Language.init(rawValue:))
        let result = try await manager.transcribe(
            fileURL,
            decoderState: &decoderState,
            language: language
        )
        return Self.segments(from: result, source: source)
    }

    private func manager(for variant: ParakeetModelVariant) async throws -> AsrManager {
        if let manager, loadedVariant == variant {
            return manager
        }

        await LocalLanguageModelRuntime.shared.release()
        let models = try await AsrModels.loadFromCache(version: variant.fluidAudioVersion)
        let newManager = AsrManager(config: .default, models: models)
        manager = newManager
        loadedVariant = variant
        return newManager
    }

    private static func segments(
        from result: ASRResult,
        source: AudioSource
    ) -> [TranscriptSegment] {
        let fallbackText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fallbackText.isEmpty else { return [] }
        guard let timings = result.tokenTimings, !timings.isEmpty else {
            return [
                TranscriptSegment(
                    source: source,
                    startTime: 0,
                    duration: max(0, result.duration),
                    text: fallbackText
                )
            ]
        }

        var output: [TranscriptSegment] = []
        var current: [TokenTiming] = []

        func appendCurrent() {
            guard let first = current.first, let last = current.last else { return }
            let text = current
                .map(\.token)
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                current.removeAll(keepingCapacity: true)
                return
            }
            output.append(
                TranscriptSegment(
                    source: source,
                    startTime: max(0, first.startTime),
                    duration: max(0, last.endTime - first.startTime),
                    text: text
                )
            )
            current.removeAll(keepingCapacity: true)
        }

        for timing in timings {
            if let previous = current.last,
               timing.startTime - previous.endTime > 1.2
            {
                appendCurrent()
            }
            current.append(timing)

            guard let first = current.first else { continue }
            let hasTerminalPunctuation = timing.token.contains {
                ".!?".contains($0)
            }
            if hasTerminalPunctuation || timing.endTime - first.startTime >= 12 {
                appendCurrent()
            }
        }
        appendCurrent()

        return output.isEmpty
            ? [
                TranscriptSegment(
                    source: source,
                    startTime: 0,
                    duration: max(0, result.duration),
                    text: fallbackText
                )
            ]
            : output
    }
}

extension ParakeetModelVariant {
    fileprivate var fluidAudioVersion: AsrModelVersion {
        switch self {
        case .englishV2: .v2
        case .multilingualV3: .v3
        case .englishCompact: .tdtCtc110m
        case .japanese: .tdtJa
        }
    }
}
