import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

@MainActor
final class SystemAudioCapture: AudioCapturing {
    private var stream: SCStream?
    private var output: CaptureOutput?
    private var isActive = false
    private var capturedMeaningfulAudio = false

    var activity: AudioActivity {
        isActive ? output?.activity ?? .silent : .silent
    }

    var hasMeaningfulAudio: Bool {
        output?.hasMeaningfulAudio ?? capturedMeaningfulAudio
    }

    func start(
        files: RecordingFiles,
        includesMicrophone: Bool,
        languageIdentifier _: String
    ) async -> Result<Void, BurritoError> {
        guard !isActive else { return .failure(.recordingAlreadyInProgress) }
        capturedMeaningfulAudio = false

        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            return .failure(.screenRecordingPermissionDenied)
        }

        if includesMicrophone {
            let allowed = await microphoneAccess()
            guard allowed else { return .failure(.microphonePermissionDenied) }
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: false
            )
            guard let display = content.displays.first else {
                return .failure(.captureFailed(details: "No display is available for system audio capture."))
            }

            let ownApplication = content.applications.first {
                $0.bundleIdentifier == Bundle.main.bundleIdentifier
            }
            let filter = SCContentFilter(
                display: display,
                excludingApplications: [ownApplication].compactMap { $0 },
                exceptingWindows: []
            )
            let configuration = SCStreamConfiguration()
            configuration.capturesAudio = true
            configuration.excludesCurrentProcessAudio = true
            configuration.sampleRate = 48_000
            configuration.channelCount = 2
            configuration.captureMicrophone = includesMicrophone
            configuration.width = 2
            configuration.height = 2
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            configuration.queueDepth = 1
            configuration.showsCursor = false

            let newOutput = try CaptureOutput(files: files)
            let newStream = SCStream(filter: filter, configuration: configuration, delegate: newOutput)
            try newStream.addStreamOutput(
                newOutput,
                type: .audio,
                sampleHandlerQueue: CaptureOutput.queue
            )
            if includesMicrophone {
                try newStream.addStreamOutput(
                    newOutput,
                    type: .microphone,
                    sampleHandlerQueue: CaptureOutput.queue
                )
            }
            try await newStream.startCapture()

            stream = newStream
            output = newOutput
            isActive = true
            return .success(())
        } catch {
            return .failure(.captureFailed(details: error.localizedDescription))
        }
    }

    func stop() async -> Result<Void, BurritoError> {
        guard let stream, let output, isActive else {
            return .failure(.noActiveRecording)
        }

        do {
            try await stream.stopCapture()
            try await output.finish()
            capturedMeaningfulAudio = output.hasMeaningfulAudio
            self.stream = nil
            self.output = nil
            isActive = false
            return .success(())
        } catch {
            self.stream = nil
            self.output = nil
            isActive = false
            return .failure(.captureFailed(details: error.localizedDescription))
        }
    }

    private func microphoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            true
        case .notDetermined:
            await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            false
        @unknown default:
            false
        }
    }
}

private final class CaptureOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    static let queue = DispatchQueue(label: "com.local.burrito.audio-capture")

    let hasMicrophone: Bool
    private let systemWriter: AudioSampleWriter
    private let microphoneWriter: AudioSampleWriter?
    private let lock = NSLock()
    private var streamError: Error?
    private var systemLevel = 0.0
    private var microphoneLevel = 0.0
    private var meaningfulAudioDuration = 0.0

    var hasMeaningfulAudio: Bool {
        lock.withLock { meaningfulAudioDuration >= 0.25 }
    }

    var activity: AudioActivity {
        lock.withLock {
            AudioActivity(system: systemLevel, microphone: microphoneLevel)
        }
    }

    init(files: RecordingFiles) throws {
        self.systemWriter = try AudioSampleWriter(url: files.systemAudioURL, channelCount: 2)
        self.microphoneWriter = try files.microphoneAudioURL.map {
            try AudioSampleWriter(url: $0, channelCount: 1)
        }
        self.hasMicrophone = files.microphoneAudioURL != nil
        super.init()
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer) else { return }
        switch type {
        case .audio:
            systemWriter.append(sampleBuffer)
            consume(sampleBuffer, source: .system)
        case .microphone:
            microphoneWriter?.append(sampleBuffer)
            consume(sampleBuffer, source: .microphone)
        case .screen:
            break
        @unknown default:
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        lock.withLock { streamError = error }
    }

    func finish() async throws {
        let captureError = lock.withLock { streamError }
        if let captureError { throw captureError }
        try await systemWriter.finish()
        try await microphoneWriter?.finish()
    }

    private func consume(
        _ sampleBuffer: CMSampleBuffer,
        source: AudioSource
    ) {
        guard let formatDescription = sampleBuffer.formatDescription else {
            return
        }
        let format = AVAudioFormat(cmAudioFormatDescription: formatDescription)

        do {
            let buffer = try sampleBuffer.withAudioBufferList { sourceBuffers, _ in
                let frameCount = AVAudioFrameCount(sampleBuffer.numSamples)
                guard let copy = AVAudioPCMBuffer(
                    pcmFormat: format,
                    frameCapacity: frameCount
                ) else {
                    throw BurritoError.captureFailed(
                        details: "A live audio buffer could not be allocated."
                    )
                }
                copy.frameLength = frameCount
                let destinationBuffers = UnsafeMutableAudioBufferListPointer(
                    copy.mutableAudioBufferList
                )
                for index in 0..<min(sourceBuffers.count, destinationBuffers.count) {
                    guard let sourceData = sourceBuffers[index].mData,
                          let destinationData = destinationBuffers[index].mData
                    else {
                        continue
                    }
                    let byteCount = min(
                        Int(sourceBuffers[index].mDataByteSize),
                        Int(destinationBuffers[index].mDataByteSize)
                    )
                    memcpy(destinationData, sourceData, byteCount)
                }
                return copy
            }
            let level = AudioLevel.measure(buffer)
            updateLevel(
                level,
                duration: Double(buffer.frameLength) / buffer.format.sampleRate,
                source: source
            )
        } catch {
            lock.withLock {
                streamError = streamError ?? error
            }
        }
    }

    private func updateLevel(
        _ measuredLevel: Double,
        duration: TimeInterval,
        source: AudioSource
    ) {
        lock.withLock {
            if measuredLevel >= 0.04 {
                meaningfulAudioDuration += duration
            }
            switch source {
            case .system:
                systemLevel = AudioLevel.smoothed(previous: systemLevel, next: measuredLevel)
            case .microphone:
                microphoneLevel = AudioLevel.smoothed(previous: microphoneLevel, next: measuredLevel)
            }
        }
    }
}

private enum AudioLevel {
    static func measure(_ buffer: AVAudioPCMBuffer) -> Double {
        guard let channels = buffer.floatChannelData,
              buffer.frameLength > 0
        else {
            return 0
        }

        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        var sumOfSquares = 0.0
        for channel in 0..<channelCount {
            let samples = channels[channel]
            for frame in 0..<frameCount {
                let sample = Double(samples[frame])
                sumOfSquares += sample * sample
            }
        }
        let sampleCount = max(1, frameCount * channelCount)
        let rootMeanSquare = sqrt(sumOfSquares / Double(sampleCount))
        guard rootMeanSquare > 0 else { return 0 }
        let decibels = 20 * log10(rootMeanSquare)
        return min(1, max(0, (decibels + 52) / 52))
    }

    static func smoothed(previous: Double, next: Double) -> Double {
        let response = next > previous ? 0.58 : 0.22
        return previous + ((next - previous) * response)
    }
}

private final class AudioSampleWriter: @unchecked Sendable {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let lock = NSLock()
    private var started = false

    init(url: URL, channelCount: Int) throws {
        self.writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        self.input = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: channelCount,
                AVEncoderBitRateKey: channelCount == 1 ? 96_000 : 160_000,
            ]
        )
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else {
            throw BurritoError.captureFailed(details: "The audio encoder could not be configured.")
        }
        writer.add(input)
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        lock.withLock {
            if !started {
                guard writer.startWriting() else { return }
                writer.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)
                started = true
            }
            if input.isReadyForMoreMediaData {
                input.append(sampleBuffer)
            }
        }
    }

    func finish() async throws {
        let didStart = lock.withLock { () -> Bool in
            guard started else { return false }
            input.markAsFinished()
            return true
        }
        guard didStart else {
            throw BurritoError.captureFailed(details: "No audio samples were captured.")
        }

        await writer.finishWriting()
        if let error = writer.error {
            throw error
        }
    }
}
