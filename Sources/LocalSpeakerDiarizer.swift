@preconcurrency import FluidAudio
import Foundation

struct LocalSpeakerDiarizer: SpeakerDiarizing {
    func assignSpeakers(
        audioURL: URL,
        to segments: [TranscriptSegment]
    ) async -> Result<[TranscriptSegment], BurritoError> {
        guard !segments.isEmpty else { return .success(segments) }

        do {
            let manager = OfflineDiarizerManager()
            try await manager.prepareModels()
            let result = try await manager.process(audioURL)
            let turns = result.segments.map {
                SpeakerTurn(
                    id: $0.speakerId,
                    startTime: Double($0.startTimeSeconds),
                    endTime: Double($0.endTimeSeconds)
                )
            }
            return .success(SpeakerAttribution.assign(turns: turns, to: segments))
        } catch {
            return .failure(
                .speakerDiarizationFailed(details: error.localizedDescription)
            )
        }
    }
}
