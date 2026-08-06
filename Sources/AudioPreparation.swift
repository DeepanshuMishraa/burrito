import AVFoundation
import Foundation

struct PreparedTranscriptionAudio: Equatable, Sendable {
    var fileURL: URL
    var source: AudioSource
    var timelineScale: Double
    var temporaryFileURL: URL?

    func remap(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        guard timelineScale != 1 else { return segments }
        return segments.map { segment in
            TranscriptSegment(
                id: segment.id,
                source: segment.source,
                startTime: segment.startTime * timelineScale,
                duration: segment.duration * timelineScale,
                text: segment.text,
                speakerName: segment.speakerName
            )
        }
    }
}

protocol TranscriptionAudioPreparing: Sendable {
    func prepare(_ input: TranscriptionInput) async -> Result<PreparedTranscriptionAudio, BurritoError>
}

actor AudioTempoNormalizer: TranscriptionAudioPreparing {
    private let fileManager: FileManager
    private let outputDirectory: URL

    init(
        fileManager: FileManager = .default,
        outputDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        self.outputDirectory = outputDirectory
            ?? fileManager.temporaryDirectory.appending(
                path: "Burrito/PreparedAudio",
                directoryHint: .isDirectory
            )
    }

    func prepare(
        _ input: TranscriptionInput
    ) async -> Result<PreparedTranscriptionAudio, BurritoError> {
        switch input {
        case .natural(let fileURL, let source), .importedMedia(let fileURL, let source):
            return .success(
                PreparedTranscriptionAudio(
                    fileURL: fileURL,
                    source: source,
                    timelineScale: 1,
                    temporaryFileURL: nil
                )
            )
        case .systemCapture(let fileURL, let playbackRate):
            guard playbackRate != .natural else {
                return .success(
                    PreparedTranscriptionAudio(
                        fileURL: fileURL,
                        source: .system,
                        timelineScale: 1,
                        temporaryFileURL: nil
                    )
                )
            }

            let destination = outputDirectory
                .appending(path: UUID().uuidString)
                .appendingPathExtension("caf")
            do {
                try fileManager.createDirectory(
                    at: outputDirectory,
                    withIntermediateDirectories: true
                )
                try render(
                    sourceURL: fileURL,
                    destinationURL: destination,
                    playbackRate: playbackRate
                )
                return .success(
                    PreparedTranscriptionAudio(
                        fileURL: destination,
                        source: .system,
                        timelineScale: 1 / playbackRate.rawValue,
                        temporaryFileURL: destination
                    )
                )
            } catch {
                try? fileManager.removeItem(at: destination)
                return .failure(
                    .audioPreparationFailed(
                        details: "The \(playbackRate.displayTitle) system track could not be "
                            + "normalized without losing the original: \(error.localizedDescription)"
                    )
                )
            }
        }
    }

    private func render(
        sourceURL: URL,
        destinationURL: URL,
        playbackRate: PlaybackRate
    ) throws {
        let sourceFile = try AVAudioFile(forReading: sourceURL)
        guard sourceFile.length > 0 else {
            throw AudioPreparationError.emptyInput
        }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()
        timePitch.rate = Float(1 / playbackRate.rawValue)
        timePitch.pitch = 0

        engine.attach(player)
        engine.attach(timePitch)
        engine.connect(player, to: timePitch, format: sourceFile.processingFormat)
        engine.connect(timePitch, to: engine.mainMixerNode, format: nil)

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioPreparationError.outputFormatUnavailable
        }
        let maximumFrameCount: AVAudioFrameCount = 4_096
        try engine.enableManualRenderingMode(
            .offline,
            format: outputFormat,
            maximumFrameCount: maximumFrameCount
        )
        let destinationFile = try AVAudioFile(
            forWriting: destinationURL,
            settings: engine.manualRenderingFormat.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        guard let renderBuffer = AVAudioPCMBuffer(
            pcmFormat: engine.manualRenderingFormat,
            frameCapacity: maximumFrameCount
        ) else {
            throw AudioPreparationError.renderBufferUnavailable
        }

        let sourceDuration = Double(sourceFile.length) / sourceFile.processingFormat.sampleRate
        let expectedFrames = AVAudioFramePosition(
            ceil(sourceDuration * outputFormat.sampleRate * playbackRate.rawValue)
        )

        player.scheduleFile(sourceFile, at: nil)
        let flushFrames = AVAudioFrameCount(sourceFile.processingFormat.sampleRate)
        guard let flushBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFile.processingFormat,
            frameCapacity: flushFrames
        ) else {
            throw AudioPreparationError.renderBufferUnavailable
        }
        flushBuffer.frameLength = flushFrames
        player.scheduleBuffer(flushBuffer)
        try engine.start()
        player.play()
        defer {
            player.stop()
            engine.stop()
            engine.disableManualRenderingMode()
        }

        while engine.manualRenderingSampleTime < expectedFrames {
            let remaining = expectedFrames - engine.manualRenderingSampleTime
            let requestedFrames = AVAudioFrameCount(
                min(AVAudioFramePosition(maximumFrameCount), remaining)
            )
            let status = try engine.renderOffline(requestedFrames, to: renderBuffer)
            switch status {
            case .success:
                if renderBuffer.frameLength > 0 {
                    try destinationFile.write(from: renderBuffer)
                }
            case .insufficientDataFromInputNode:
                throw AudioPreparationError.inputEndedEarly
            case .cannotDoInCurrentContext:
                continue
            case .error:
                throw AudioPreparationError.renderFailed
            @unknown default:
                throw AudioPreparationError.renderFailed
            }
        }
    }
}

private enum AudioPreparationError: LocalizedError {
    case emptyInput
    case outputFormatUnavailable
    case renderBufferUnavailable
    case inputEndedEarly
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            "The captured track contains no audio frames."
        case .outputFormatUnavailable:
            "A 16 kHz mono transcription format is unavailable."
        case .renderBufferUnavailable:
            "The offline audio buffer could not be allocated."
        case .inputEndedEarly:
            "The source ended before the normalized track was complete."
        case .renderFailed:
            "AVFoundation could not render the normalized track."
        }
    }
}
