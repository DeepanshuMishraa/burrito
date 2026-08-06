import AVFoundation
import Foundation

struct ImportedMediaAudio: Equatable, Sendable {
    var duration: TimeInterval
}

protocol MediaAudioExtracting: Sendable {
    func extract(
        sourceURL: URL,
        transcriptionURL: URL,
        retainedAudioURL: URL?
    ) async -> Result<ImportedMediaAudio, BurritoError>
}

actor LocalMediaAudioExtractor: MediaAudioExtracting {
    func extract(
        sourceURL: URL,
        transcriptionURL: URL,
        retainedAudioURL: URL?
    ) async -> Result<ImportedMediaAudio, BurritoError> {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { sourceURL.stopAccessingSecurityScopedResource() }
        }

        do {
            let asset = AVURLAsset(url: sourceURL)
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            guard let track = tracks.first else {
                return .failure(
                    .mediaImportFailed(
                        details: "\(sourceURL.lastPathComponent) contains no readable audio track. "
                            + "Choose an audio or video file with unprotected audio."
                    )
                )
            }

            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(
                track: track,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVLinearPCMBitDepthKey: 32,
                    AVLinearPCMIsFloatKey: true,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false,
                ]
            )
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else {
                throw MediaImportError.readerOutputUnavailable
            }
            reader.add(output)
            guard reader.startReading() else {
                throw reader.error ?? MediaImportError.readerCouldNotStart
            }

            let writer = PCMFileWriter(url: transcriptionURL)
            var wroteFrames = false
            while let sampleBuffer = output.copyNextSampleBuffer() {
                try Task.checkCancellation()
                let buffer = try Self.copyPCMBuffer(from: sampleBuffer)
                try writer.write(buffer)
                wroteFrames = wroteFrames || buffer.frameLength > 0
            }
            writer.finish()

            guard reader.status == .completed, wroteFrames else {
                throw reader.error ?? MediaImportError.emptyAudioTrack
            }

            if let retainedAudioURL {
                guard let export = AVAssetExportSession(
                    asset: asset,
                    presetName: AVAssetExportPresetAppleM4A
                ) else {
                    throw MediaImportError.retainedAudioExportUnavailable
                }
                try await export.export(to: retainedAudioURL, as: .m4a)
            }

            let duration = try await asset.load(.duration).seconds
            return .success(ImportedMediaAudio(duration: max(0, duration)))
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: transcriptionURL)
            if let retainedAudioURL { try? FileManager.default.removeItem(at: retainedAudioURL) }
            return .failure(
                .mediaImportFailed(
                    details: "Import was cancelled. The selected media file was not changed."
                )
            )
        } catch {
            try? FileManager.default.removeItem(at: transcriptionURL)
            if let retainedAudioURL { try? FileManager.default.removeItem(at: retainedAudioURL) }
            return .failure(
                .mediaImportFailed(
                    details: "\(sourceURL.lastPathComponent) could not be decoded locally: "
                        + "\(error.localizedDescription). The selected file was not changed; "
                        + "try an unprotected audio or video file."
                )
            )
        }
    }

    private static func copyPCMBuffer(
        from sampleBuffer: CMSampleBuffer
    ) throws -> AVAudioPCMBuffer {
        guard sampleBuffer.isValid,
              CMSampleBufferDataIsReady(sampleBuffer),
              let description = sampleBuffer.formatDescription
        else {
            throw MediaImportError.invalidAudioSample
        }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        return try sampleBuffer.withAudioBufferList { sourceBuffers, _ in
            let frameCount = AVAudioFrameCount(sampleBuffer.numSamples)
            guard let copy = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: frameCount
            ) else {
                throw MediaImportError.audioBufferUnavailable
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
    }
}

private enum MediaImportError: LocalizedError {
    case readerOutputUnavailable
    case readerCouldNotStart
    case emptyAudioTrack
    case retainedAudioExportUnavailable
    case invalidAudioSample
    case audioBufferUnavailable

    var errorDescription: String? {
        switch self {
        case .readerOutputUnavailable:
            "AVFoundation cannot decode this audio track."
        case .readerCouldNotStart:
            "AVFoundation could not start reading this media file."
        case .emptyAudioTrack:
            "The audio track contains no decodable samples."
        case .retainedAudioExportUnavailable:
            "The imported audio could not be prepared for later playback."
        case .invalidAudioSample:
            "The media file produced an invalid audio sample."
        case .audioBufferUnavailable:
            "An audio buffer could not be allocated during import."
        }
    }
}
