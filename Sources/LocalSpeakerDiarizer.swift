@preconcurrency import FluidAudio
import Foundation

final class LocalSpeakerDiarizer: SpeakerDiarizing {
    private typealias AssignmentResult = Result<[TranscriptSegment], BurritoError>

    private struct Request: Sendable {
        let audioURL: URL
        let segments: [TranscriptSegment]
        let continuation: CheckedContinuation<AssignmentResult, Never>
    }

    private let requestContinuation: AsyncStream<Request>.Continuation
    private let worker: Task<Void, Never>

    init() {
        let pair = AsyncStream<Request>.makeStream(bufferingPolicy: .bufferingOldest(1))
        requestContinuation = pair.continuation
        // FluidAudio's manager is not Sendable. Keep it scoped to one request so
        // Core ML diarizer models do not remain resident after processing.
        worker = Task.detached(priority: .userInitiated) {
            for await request in pair.stream {
                let result: AssignmentResult
                do {
                    let manager = OfflineDiarizerManager()
                    try await manager.prepareModels()
                    let diarization = try await manager.process(request.audioURL)
                    let turns = diarization.segments.map {
                        SpeakerTurn(
                            id: $0.speakerId,
                            startTime: Double($0.startTimeSeconds),
                            endTime: Double($0.endTimeSeconds)
                        )
                    }
                    result = .success(
                        SpeakerAttribution.assign(turns: turns, to: request.segments)
                    )
                } catch {
                    result = .failure(
                        .speakerDiarizationFailed(details: error.localizedDescription)
                    )
                }
                request.continuation.resume(returning: result)
            }
        }
    }

    deinit {
        requestContinuation.finish()
        worker.cancel()
    }

    func assignSpeakers(
        audioURL: URL,
        to segments: [TranscriptSegment]
    ) async -> Result<[TranscriptSegment], BurritoError> {
        guard !segments.isEmpty else { return .success(segments) }

        return await withCheckedContinuation { continuation in
            let request = Request(
                audioURL: audioURL,
                segments: segments,
                continuation: continuation
            )
            switch requestContinuation.yield(request) {
            case .enqueued:
                break
            case .dropped(let dropped):
                dropped.continuation.resume(
                    returning: .failure(
                        .speakerDiarizationFailed(
                            details: "Speaker identification was already busy."
                        )
                    )
                )
            case .terminated:
                continuation.resume(
                    returning: .failure(
                        .speakerDiarizationFailed(
                            details: "The local diarization worker is no longer available. "
                                + "Restart Burrito before future meeting recordings."
                        )
                    )
                )
            @unknown default:
                continuation.resume(
                    returning: .failure(
                        .speakerDiarizationFailed(
                            details: "Speaker identification could not be queued."
                        )
                    )
                )
            }
        }
    }
}
