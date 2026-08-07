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
    private var liveTranscriptStore = LiveTranscriptStore()
    private var lastLiveTranscript = LiveTranscriptSnapshot.preparing

    var activity: AudioActivity {
        isActive ? output?.activity ?? .silent : .silent
    }

    var hasMeaningfulAudio: Bool {
        output?.hasMeaningfulAudio ?? capturedMeaningfulAudio
    }

    var liveTranscript: LiveTranscriptSnapshot {
        isActive ? liveTranscriptStore.snapshot : lastLiveTranscript
    }

    func start(
        files: RecordingFiles,
        mode: RecordingMode,
        languageIdentifier: String
    ) async -> Result<Void, BurritoError> {
        guard !isActive else { return .failure(.recordingAlreadyInProgress) }
        capturedMeaningfulAudio = false
        liveTranscriptStore = LiveTranscriptStore()
        lastLiveTranscript = .preparing

        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            return .failure(.screenRecordingPermissionDenied)
        }

        if mode == .meeting {
            let allowed = await microphoneAccess()
            guard allowed else { return .failure(.microphonePermissionDenied) }
        }

        var liveSession: LiveSpeechTranscriptionSession?
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
            configuration.captureMicrophone = mode == .meeting
            configuration.width = 2
            configuration.height = 2
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            configuration.queueDepth = 1
            configuration.showsCursor = false

            let sources: [AudioSource] = mode == .meeting
                ? [.system, .microphone]
                : [.system]
            switch await LiveSpeechTranscriptionSession.make(
                languageIdentifier: languageIdentifier,
                sources: sources,
                store: liveTranscriptStore
            ) {
            case .success(let session):
                liveSession = session
            case .failure:
                liveSession = nil
            }

            let newOutput = try CaptureOutput(
                files: files,
                liveTranscription: liveSession
            )
            let newStream = SCStream(filter: filter, configuration: configuration, delegate: newOutput)
            try newStream.addStreamOutput(
                newOutput,
                type: .audio,
                sampleHandlerQueue: CaptureOutput.queue
            )
            if mode == .meeting {
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
            await liveSession?.finish()
            return .failure(.captureFailed(details: error.localizedDescription))
        }
    }

    func pause() async -> Result<Void, BurritoError> {
        guard let output, isActive else { return .failure(.noActiveRecording) }
        output.setPaused(true)
        return .success(())
    }

    func resume() async -> Result<Void, BurritoError> {
        guard let output, isActive else { return .failure(.noActiveRecording) }
        output.setPaused(false)
        return .success(())
    }

    func stop() async -> Result<Void, BurritoError> {
        guard let stream, let output, isActive else {
            return .failure(.noActiveRecording)
        }

        do {
            try await stream.stopCapture()
            try await output.finish()
            capturedMeaningfulAudio = output.hasMeaningfulAudio
            lastLiveTranscript = liveTranscriptStore.snapshot
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
    private let systemWriter: AudioSampleWriter?
    private let microphoneWriter: AudioSampleWriter?
    private let systemTranscriptionWriter: PCMFileWriter?
    private let microphoneTranscriptionWriter: PCMFileWriter?
    private let lock = NSLock()
    private var streamError: Error?
    private var systemTranscriptionError: Error?
    private var microphoneTranscriptionError: Error?
    private var transcriptionTimelineOrigin: CMTime?
    private var systemLevel = 0.0
    private var microphoneLevel = 0.0
    private var meaningfulAudioDuration = 0.0
    private var isPaused = false
    private let liveTranscription: LiveSpeechTranscriptionSession?

    var hasMeaningfulAudio: Bool {
        lock.withLock { meaningfulAudioDuration >= 0.25 }
    }

    var activity: AudioActivity {
        lock.withLock {
            AudioActivity(system: systemLevel, microphone: microphoneLevel)
        }
    }

    init(
        files: RecordingFiles,
        liveTranscription: LiveSpeechTranscriptionSession?
    ) throws {
        self.systemWriter = try files.systemAudioURL.map {
            try AudioSampleWriter(url: $0, channelCount: 2)
        }
        self.microphoneWriter = try files.microphoneAudioURL.map {
            try AudioSampleWriter(url: $0, channelCount: 1)
        }
        self.systemTranscriptionWriter = files.systemTranscriptionURL.map { PCMFileWriter(url: $0) }
        self.microphoneTranscriptionWriter = files.microphoneTranscriptionURL.map { PCMFileWriter(url: $0) }
        self.hasMicrophone = files.microphoneAudioURL != nil
        self.liveTranscription = liveTranscription
        super.init()
    }

    func setPaused(_ paused: Bool) {
        lock.withLock {
            isPaused = paused
            if paused {
                systemLevel = 0
                microphoneLevel = 0
            }
        }
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard sampleBuffer.isValid,
              CMSampleBufferDataIsReady(sampleBuffer),
              !lock.withLock({ isPaused })
        else {
            return
        }
        switch type {
        case .audio:
            systemWriter?.append(sampleBuffer)
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
        systemTranscriptionWriter?.finish()
        microphoneTranscriptionWriter?.finish()
        await liveTranscription?.finish()
        if let captureError { throw captureError }
        try await systemWriter?.finish()
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
            let presentationTime = transcriptionPresentationTime(
                sampleBuffer.presentationTimeStamp
            )
            liveTranscription?.append(
                buffer,
                presentationTime: presentationTime,
                source: source
            )
            writeTranscription(
                buffer,
                presentationTime: presentationTime,
                source: source
            )
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

    private func writeTranscription(
        _ buffer: AVAudioPCMBuffer,
        presentationTime: CMTime,
        source: AudioSource
    ) {
        do {
            switch source {
            case .system:
                try systemTranscriptionWriter?.write(
                    buffer,
                    presentationTime: presentationTime
                )
            case .microphone:
                try microphoneTranscriptionWriter?.write(
                    buffer,
                    presentationTime: presentationTime
                )
            }
        } catch {
            lock.withLock {
                switch source {
                case .system:
                    systemTranscriptionError = systemTranscriptionError ?? error
                case .microphone:
                    microphoneTranscriptionError = microphoneTranscriptionError ?? error
                }
            }
            switch source {
            case .system:
                systemTranscriptionWriter?.discard()
            case .microphone:
                microphoneTranscriptionWriter?.discard()
            }
        }
    }

    private func transcriptionPresentationTime(_ presentationTime: CMTime) -> CMTime {
        lock.withLock {
            guard presentationTime.isValid, presentationTime.isNumeric else { return .zero }
            guard let origin = transcriptionTimelineOrigin else {
                transcriptionTimelineOrigin = presentationTime
                return .zero
            }
            guard CMTimeCompare(presentationTime, origin) >= 0 else { return .zero }
            return CMTimeSubtract(presentationTime, origin)
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

final class PCMFileWriter: @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var isFinished = false

    init(url: URL) {
        self.url = url
    }

    func write(_ buffer: AVAudioPCMBuffer) throws {
        try write(buffer, presentationTime: nil)
    }

    func write(_ buffer: AVAudioPCMBuffer, presentationTime: CMTime) throws {
        try write(buffer, presentationTime: Optional(presentationTime))
    }

    private func write(
        _ buffer: AVAudioPCMBuffer,
        presentationTime: CMTime?
    ) throws {
        try lock.withLock {
            guard !isFinished else { return }
            let destination: AVAudioFile
            if let file {
                destination = file
            } else {
                let newFile = try AVAudioFile(
                    forWriting: url,
                    settings: buffer.format.settings,
                    commonFormat: buffer.format.commonFormat,
                    interleaved: buffer.format.isInterleaved
                )
                file = newFile
                destination = newFile
            }
            if let presentationTime {
                try writeSilence(
                    until: presentationTime,
                    format: buffer.format,
                    destination: destination
                )
            }
            try destination.write(from: buffer)
        }
    }

    private func writeSilence(
        until presentationTime: CMTime,
        format: AVAudioFormat,
        destination: AVAudioFile
    ) throws {
        let seconds = presentationTime.seconds
        guard seconds.isFinite, seconds > 0 else { return }
        let presentationFrame = AVAudioFramePosition(
            (seconds * format.sampleRate).rounded()
        )
        var remainingFrames = presentationFrame - destination.length
        while remainingFrames > 0 {
            let frameCount = AVAudioFrameCount(min(remainingFrames, 4_096))
            guard let silence = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: frameCount
            ) else {
                throw BurritoError.captureFailed(
                    details: "A transcription silence buffer could not be allocated."
                )
            }
            silence.frameLength = frameCount
            for audioBuffer in UnsafeMutableAudioBufferListPointer(
                silence.mutableAudioBufferList
            ) {
                guard let data = audioBuffer.mData else { continue }
                memset(data, 0, Int(audioBuffer.mDataByteSize))
            }
            try destination.write(from: silence)
            remainingFrames -= AVAudioFramePosition(frameCount)
        }
    }

    func finish() {
        lock.withLock {
            isFinished = true
            file = nil
        }
    }

    func discard() {
        finish()
        try? FileManager.default.removeItem(at: url)
    }
}

enum AudioLevel {
    static func measure(_ buffer: AVAudioPCMBuffer) -> Double {
        guard buffer.frameLength > 0 else { return 0 }

        var sumOfSquares = 0.0
        var sampleCount = 0
        let buffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)

        for audioBuffer in buffers {
            guard let data = audioBuffer.mData else { continue }
            switch buffer.format.commonFormat {
            case .pcmFormatFloat32:
                let samples = data.assumingMemoryBound(to: Float.self)
                let count = Int(audioBuffer.mDataByteSize) / MemoryLayout<Float>.stride
                for index in 0..<count {
                    let sample = Double(samples[index])
                    sumOfSquares += sample * sample
                }
                sampleCount += count
            case .pcmFormatFloat64:
                let samples = data.assumingMemoryBound(to: Double.self)
                let count = Int(audioBuffer.mDataByteSize) / MemoryLayout<Double>.stride
                for index in 0..<count {
                    let sample = samples[index]
                    sumOfSquares += sample * sample
                }
                sampleCount += count
            case .pcmFormatInt16:
                let samples = data.assumingMemoryBound(to: Int16.self)
                let count = Int(audioBuffer.mDataByteSize) / MemoryLayout<Int16>.stride
                for index in 0..<count {
                    let sample = Double(samples[index]) / Double(Int16.max)
                    sumOfSquares += sample * sample
                }
                sampleCount += count
            case .pcmFormatInt32:
                let samples = data.assumingMemoryBound(to: Int32.self)
                let count = Int(audioBuffer.mDataByteSize) / MemoryLayout<Int32>.stride
                for index in 0..<count {
                    let sample = Double(samples[index]) / Double(Int32.max)
                    sumOfSquares += sample * sample
                }
                sampleCount += count
            case .otherFormat:
                continue
            @unknown default:
                continue
            }
        }

        guard sampleCount > 0 else { return 0 }
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
