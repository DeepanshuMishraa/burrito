# Burrito

**Private meeting capture and genuinely useful notes—entirely on your Mac.**

Burrito records system audio with an optional microphone track, transcribes it locally, then turns the conversation into structured Markdown using Apple Intelligence. No accounts, meeting bots, cloud uploads, analytics, or third-party AI.

## A calmer way to remember

- Capture system audio and your microphone as separate, synchronized sources
- Transcribe after recording with on-device Speech frameworks
- Generate summaries, detailed notes, study guides, or meeting notes
- Create custom note templates with your own instructions
- Edit the transcript and notes in a focused, Granola-inspired workspace
- Organize notes with folders, favorites, search, Trash, and Markdown export
- Recover interrupted sessions without losing usable audio

## Local by design

Recordings live in Burrito’s Application Support directory. Audio is removed after successful transcription by default, while failed or interrupted sessions retain recoverable files. Transcripts and notes remain editable and local.

## Requirements

Burrito is built for Apple-silicon Macs running macOS 26 with Apple Intelligence enabled. System-audio capture, microphone access, and speech recognition permissions are requested before the library opens.

## Development

The project uses Swift 6, SwiftUI, SwiftData, ScreenCaptureKit, Speech, Foundation Models, and XcodeGen.

```sh
xcodegen generate
open burrito.xcodeproj
```

## License

MIT © 2026 Deepanshu Mishra
