# Local transcription at accelerated playback speeds

## Recommendation

Use a **language-aware, two-pass local pipeline**:

1. On stop, produce the final transcript with:
   - **English:** Parakeet TDT 0.6B v2 through FluidAudio/Core ML.
   - **Parakeet v3 languages:** Parakeet TDT 0.6B v3 through FluidAudio/Core ML.
   - **Hindi and every unsupported locale:** Apple's `SpeechAnalyzer` accurate final preset.
2. Before final ASR, normalize known accelerated system audio back toward natural speech tempo with pitch-preserving offline time-stretch. Do not modify the microphone track.
3. Ask for an explicit playback rate from 1× through 10×. Consider `Auto` only after confidence and stability thresholds pass a representative benchmark.
4. Keep lossless PCM from capture through normalization and ASR. Encode AAC only for retained playback audio.
5. Prefer direct import of original audio or video whenever it is available; this avoids information already discarded by accelerated playback.

This architecture is the best practical fit for Burrito because it gives final transcription a fast, controllable ASR backend and addresses the actual accelerated-playback problem at the signal boundary. Swapping ASR models alone cannot guarantee accuracy on heavily time-compressed speech.

## The important distinction

Two unrelated ideas are often called “speed”:

- **Inference throughput:** how many seconds of audio a model can process per second, usually RTFx.
- **Playback tempo:** words and phonemes are physically shorter because a source is playing at 2x or 3x.

High RTFx does not imply robustness to accelerated speech. None of the primary model sources reviewed publishes a 1x/2x/3x playback-tempo benchmark. “Reliable regardless of audio speed” therefore cannot be claimed for Apple Speech, Parakeet, or Whisper without a Burrito-specific evaluation.

At 3x, the player’s time-stretching algorithm may already have discarded or smeared short acoustic events. Expanding that signal later gives the recognizer durations closer to training speech, but cannot recreate information that is no longer present.

## Implemented Burrito pipeline

Burrito captures system and optional microphone audio with ScreenCaptureKit. It writes temporary lossless PCM alongside optional AAC, then transcribes after recording ([`SystemAudioCapture.swift`](../../Sources/SystemAudioCapture.swift)). For system capture above 1×, it performs pitch-preserving inverse-tempo rendering to 16 kHz mono before local ASR and maps timestamps back to the capture clock ([`AudioPreparation.swift`](../../Sources/AudioPreparation.swift), [`LocalTranscriber.swift`](../../Sources/LocalTranscriber.swift)).

The recording sheet exposes an explicit 1×–10× source rate. Burrito never applies that rate to the microphone track. The temporary PCM files are deleted after transcription; AAC remains the retained user-facing format when requested.

Direct media import extracts the original local audio track to PCM and bypasses capture-rate normalization ([`MediaAudioExtractor.swift`](../../Sources/MediaAudioExtractor.swift)). This makes transcription independent of player speed, although no ASR system can promise perfect recognition for every source.

ScreenCaptureKit exposes captured audio samples and lets Burrito choose sample rate and channel count; it does not document source-player playback-rate metadata. It is therefore safest to treat playback speed as unavailable for arbitrary system audio unless Burrito gets an explicit hint from the user or controls the player itself. This is an inference from the documented API surface, not an Apple guarantee. [Apple ScreenCaptureKit audio output](https://developer.apple.com/documentation/screencapturekit/scstreamoutputtype/audio), [SCStreamConfiguration](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration)

## Model/runtime comparison

| Option | Accuracy evidence | Apple-silicon speed | Integration and license | 2x/3x conclusion |
| --- | --- | --- | --- | --- |
| Apple `SpeechAnalyzer` / `SpeechTranscriber` | Apple describes the model as on-device, fast, accurate, and designed for live, long-form, conversational, and distant audio. Apple publishes no WER or accelerated-speech result. | System-managed model; no app model download or app-process memory footprint. | Already integrated; assets are installed and updated by the OS. Native Swift API. | Keep for unsupported-language fallback. No evidence of 3x robustness. |
| Parakeet TDT 0.6B v2 | NVIDIA reports 6.05% average WER across its eight English Open-ASR sets and 1.69% on LibriSpeech test-clean. Its required input is 16 kHz mono. | FluidAudio reports 2.1% LibriSpeech test-clean WER and 145.8x overall RTFx for its Core ML conversion on an M4 Pro. This is the runtime author's benchmark, not an independent result. | FluidAudio is native Swift/SPM and Apache-2.0. Parakeet weights are CC BY 4.0, so attribution must ship with the app. | Best first production candidate for Burrito's English final pass. Still requires speed-perturbed testing. |
| Parakeet TDT 0.6B v3 | NVIDIA reports 6.34% average English-leaderboard WER and supports 25 European languages with punctuation and timestamps. | FluidAudio reports about 156x overall RTFx and 2.5% LibriSpeech test-clean WER on M4 Pro for its Core ML conversion. | Same native Swift path and licenses as v2. NVIDIA's supported deployment is Linux/NVIDIA hardware; FluidAudio's Core ML conversion is the macOS-enabling layer. | Use for supported non-English locales. It does **not** support Hindi, so it cannot replace Apple Speech globally. |
| Parakeet TDT-CTC 110M | FluidAudio reports 3.01% LibriSpeech test-clean WER and 96.5x RTFx on M2. | Smaller and iOS-compatible according to FluidAudio. | Native FluidAudio/Core ML. | Interesting low-footprint tier, but the published evidence is too narrow to prefer it over v2 for Burrito's quality-first final pass. |
| Whisper large-v3-turbo through WhisperKit | OpenAI describes turbo as an 809M-parameter speed-optimized large-v3 variant with minimal accuracy degradation. Argmax reports up to 72x real-time on M2 Ultra with GPU+ANE; its reproducible benchmark framework covers 77 languages. | Slower than reported Parakeet Core ML throughput, but far broader language coverage. | WhisperKit is native Swift/Core ML and MIT; OpenAI Whisper is MIT. | Strong optional quality/fallback experiment, especially outside Parakeet's languages. No published 3x guarantee. |
| `whisper.cpp` | Same Whisper weights; supports quantization, VAD, word timestamps, and many model sizes. | First-class Apple Silicon support through NEON, Accelerate, Metal, and optional Core ML. | Mature C API and MIT license; more bridging/build work than a Swift package. | Best if Burrito needs maximum runtime control or Intel fallback, not the lowest-integration-cost path. |
| MLX Whisper | Uses the same Whisper family and supports word timestamps and 4-bit conversion. | MLX is optimized for Apple Silicon/Metal, but the official Whisper example is Python. MLX Swift exists, while an official native Swift Whisper pipeline is not supplied. | MLX and its examples are MIT. A Python helper would be a packaging and reliability regression for a native app. | Useful for experiments; inferior production fit to FluidAudio or WhisperKit here. |

Sources:

- [Apple: Bring advanced speech-to-text to your app with SpeechAnalyzer](https://developer.apple.com/videos/play/wwdc2025/277/)
- [Apple: SpeechTranscriber presets](https://developer.apple.com/documentation/speech/speechtranscriber/preset)
- [Apple: AssetInventory](https://developer.apple.com/documentation/speech/assetinventory)
- [NVIDIA: Parakeet TDT 0.6B v2 model card](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2)
- [NVIDIA: Parakeet TDT 0.6B v3 model card](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3)
- [FluidAudio: ASR models and architecture](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Models.md)
- [FluidAudio: reproducible benchmarks](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Benchmarks.md)
- [FluidAudio: API and audio format requirements](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/API.md)
- [OpenAI: Whisper model card](https://github.com/openai/whisper/blob/main/model-card.md)
- [OpenAI: Whisper paper](https://cdn.openai.com/papers/whisper.pdf)
- [whisper.cpp repository](https://github.com/ggml-org/whisper.cpp)
- [WhisperKit repository](https://github.com/argmaxinc/argmax-oss-swift)
- [WhisperKit benchmark methodology](https://github.com/argmaxinc/argmax-oss-swift/discussions/243)
- [MLX Whisper example](https://github.com/ml-explore/mlx-examples/blob/main/whisper/README.md)
- [MLX Swift](https://github.com/ml-explore/mlx-swift)

## Audio normalization design

### Known playback rate

If the user says the source is playing at `r`, process only the system track with a pitch-preserving rate of approximately `1 / r` before final ASR:

| Captured source | Offline normalization rate |
| --- | --- |
| 1x | 1.0 |
| 1.5x | 0.667 |
| 2x | 0.5 |
| 2.5x | 0.4 |
| 3x | 0.333 |

Use `AVAudioUnitTimePitch`, which changes playback rate and pitch independently and supports rates from 1/32 through 32. Render it through `AVAudioEngine` manual offline mode, which Apple explicitly supports for processing faster than real time. Keep pitch at zero. After time-stretch, downmix and resample once to the selected ASR model's required 16 kHz mono Float32 input. [AVAudioUnitTimePitch](https://developer.apple.com/documentation/avfaudio/avaudiounittimepitch), [rate](https://developer.apple.com/documentation/avfaudio/avaudiounittimepitch/rate), [offline audio processing](https://developer.apple.com/documentation/avfaudio/performing-offline-audio-processing), [AVAudioConverter sample-rate conversion](https://developer.apple.com/documentation/technotes/tn3136-avaudioconverter-performing-sample-rate-conversions)

Do not use plain sample-rate relabeling as the “slow down” operation. It changes pitch and tempo together. Use time-pitch processing for tempo, then ordinary sample-rate conversion for the model format.

Time-stretch changes the ASR timeline, so map every system result back to capture time before merging it with the untouched microphone track. If the offline normalization rate is `n = 1 / playbackRate`, use:

```text
capture start/duration = normalized ASR start/duration × n
```

For example, a word located at 20 seconds in system audio expanded with `n = 0.5` occurred at 10 seconds on Burrito's recording clock. Without this mapping, system and microphone passages drift out of chronological order.

### Unknown playback rate

The implemented UX accepts an explicit rate from 1× through 10× and persists the last selection. There is no unverified `Auto` mode.

`Auto` should be a rescue mode, not an unverified promise:

1. Run VAD and take the first 15–30 seconds of confident system speech.
2. Produce candidate windows at 1.0, 0.667, 0.5, 0.4, and 0.333.
3. Transcribe candidates with the same final model.
4. Score model confidence, repeated-token/compression anomalies, word rate, and agreement across overlapping windows.
5. Select a non-1x candidate only when it beats 1x by a threshold established on the benchmark below.
6. Lock the choice for the recording; reconsider only after a long silence or explicit user change.

FluidAudio exposes ASR confidence and token timing, so it provides the necessary raw signals. Those confidence values are not documented as calibrated across time-stretched variants; selection thresholds must be learned on held-out Burrito audio rather than guessed. [FluidAudio ASR API](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/API.md)

For a fast first implementation, skip `Auto`: ask for playback speed and prove the deterministic normalization path first.

## Proposed production flow

```text
ScreenCaptureKit PCM or imported original media
  ├─ microphone PCM ───────────────┐
  └─ system PCM                    │
       └─ on stop                  │
            ├─ VAD / silence gate │
            ├─ inverse time-stretch when rate > 1
            ├─ 16 kHz mono Float32
            └─ language router
                 ├─ en-* → Parakeet v2
                 ├─ supported v3 locale → Parakeet v3
                 └─ hi-IN / unsupported → SpeechAnalyzer
                                    │
                    timestamp merge┘
                            ↓
                    final transcript
```

Keep microphone and system segments separate until after ASR. A video at 3x does not imply that the person speaking into the microphone is speaking at 3x.

Use VAD before ASR and reject empty/low-speech recordings. This reduces hallucinated text on silence, but VAD thresholds must be tested against quiet and distant speech. FluidAudio provides local Silero VAD and describes its thresholds and segmentation API. [FluidAudio VAD API](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/API.md)

## Required benchmark before choosing a default

Build a checked-in evaluation manifest, while keeping licensed audio outside Git:

- At least 2–3 hours representative of lectures, YouTube, meetings, accents, jargon, music beds, compression, and quiet speech.
- Exact human reference transcripts.
- Generate pitch-preserving versions at every rate in the checked-in manifest, from 1× through 10×, using the same class of playback processing users actually hear.
- Test both raw accelerated capture and inverse-time-stretched recovery.
- Evaluate Apple final SpeechTranscriber, Parakeet v2/v3 Core ML, and WhisperKit large-v3-turbo.
- Report WER by speed and domain, silence hallucination rate, timestamp error, cold/warm load latency, RTFx, peak memory, energy impact, and model download size on the oldest supported Apple Silicon Mac.
- Run a separate Hindi set; do not extrapolate Parakeet's European-language results.
- Set release gates before implementation, for example: no more than a chosen relative WER regression at 2x, bounded hallucination rate on silence, and finalization below a chosen fraction of audio duration.

The benchmark—not a leaderboard measured on normal-speed speech—should decide whether Parakeet v2, Whisper, or Apple Speech is Burrito's English default and whether `Auto` is safe to expose.

## Delivery order

1. Preserve a temporary PCM path for final ASR; retain AAC only after processing. **Implemented.**
2. Add explicit 1×–10× playback-speed metadata, pitch-preserving offline normalization, and direct original-media import. **Implemented.**
3. Add the speed-perturbed benchmark corpus and baseline the existing Apple pipeline.
4. Integrate FluidAudio behind the existing `Transcribing` protocol and route English to Parakeet v2.
5. Add v3 for its supported languages; keep Apple for Hindi and other gaps.
6. Compare WhisperKit large-v3-turbo before deciding whether a second downloadable backend is worth its product complexity.
7. Implement `Auto` only after candidate-selection thresholds pass held-out tests.

## Bottom line

For this app, **Parakeet through FluidAudio is the strongest fast native final-ASR candidate, but input tempo normalization is the actual fix for accelerated playback**. Keep Apple Speech for language coverage, especially Hindi. Do not promise speed-independent reliability until the same models and normalization pipeline pass a speed-perturbed Burrito benchmark.
