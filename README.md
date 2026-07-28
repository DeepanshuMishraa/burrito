# Burrito

**Private meeting capture and genuinely useful notes—entirely on your Mac.**

Burrito records system audio with an optional microphone track, transcribes it locally, then turns the conversation into structured Markdown using Apple Intelligence. No accounts, meeting bots, cloud uploads, analytics, or third-party AI services.

## A calmer way to remember

- Capture system audio and your microphone as separate, synchronized sources
- See real upcoming Calendar events and start the right recording from home
- Transcribe after recording with Apple Speech or an optional local Parakeet model
- Generate summaries, detailed notes, study guides, or meeting notes
- Create custom note templates with your own instructions
- Edit the transcript and notes in a focused, Granola-inspired workspace
- Organize notes with folders, favorites, search, Trash, and Markdown export
- Recover interrupted sessions without losing usable audio

## Local by design

Recordings live in Burrito’s Application Support directory. Audio is removed after successful transcription by default, while failed or interrupted sessions retain recoverable files. Transcripts and notes remain editable and local.

## Requirements

Burrito is built for Apple-silicon Macs running macOS 26 with Apple Intelligence enabled. System-audio capture, microphone access, and speech recognition permissions are requested before the library opens. Parakeet is an optional download; Apple Speech remains available without it.

## Development

The project uses Swift 6, SwiftUI, SwiftData, ScreenCaptureKit, Speech, Foundation Models, and XcodeGen.

```sh
xcodegen generate
open burrito.xcodeproj
```

## Model attribution

Optional local transcription uses [FluidAudio](https://github.com/FluidInference/FluidAudio) and NVIDIA’s [Parakeet TDT 0.6B v2](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2) or [v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) models. FluidAudio is Apache-2.0 licensed. The Parakeet model weights are provided under CC BY 4.0.

## License

MIT © 2026 Deepanshu Mishra
