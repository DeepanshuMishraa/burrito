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
        let pair = AsyncStream<Request>.makeStream()
        requestContinuation = pair.continuation
        // FluidAudio's manager is not Sendable. One worker owns it for its full
        // lifetime, serializing requests while retaining the prepared models.
        worker = Task.detached(priority: .userInitiated) {
            let manager = OfflineDiarizerManager()
            var isPrepared = false

            for await request in pair.stream {
                let result: AssignmentResult
                do {
                    if !isPrepared {
                        try await manager.prepareModels()
                        isPrepared = true
                    }
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
            if case .terminated = requestContinuation.yield(request) {
                continuation.resume(
                    returning: .failure(
                        .speakerDiarizationFailed(
                            details: "The local diarization worker is no longer available. "
                                + "Restart Burrito and retry speaker identification."
                        )
                    )
                )
            }
        }
    }
}
