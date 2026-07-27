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

    var activity: AudioActivity {
        isActive ? AudioActivity(system: 0.58, microphone: output?.hasMicrophone == true ? 0.42 : 0) : .silent
    }

    func start(files: RecordingFiles, includesMicrophone: Bool) async -> Result<Void, BurritoError> {
        guard !isActive else { return .failure(.recordingAlreadyInProgress) }

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

    init(files: RecordingFiles) throws {
        self.systemWriter = try AudioSampleWriter(url: files.systemAudioURL, channelCount: 2)
        self.microphoneWriter = try files.microphoneAudioURL.map {
            try AudioSampleWriter(url: $0, channelCount: 1)
        }
        self.hasMicrophone = files.microphoneAudioURL != nil
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
        case .microphone:
            microphoneWriter?.append(sampleBuffer)
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
        if let streamError = lock.withLock({ streamError }) {
            throw streamError
        }
        try await systemWriter.finish()
        try await microphoneWriter?.finish()
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
