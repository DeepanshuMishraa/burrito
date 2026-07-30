# Burrito

**Private meeting capture and genuinely useful notes—entirely on your Mac.**

Burrito records system audio with an optional microphone track, transcribes it locally, then turns the conversation into structured Markdown using Apple Intelligence. No accounts, meeting bots, cloud uploads, analytics, or third-party AI services.

## A calmer way to remember

- Capture system audio and your microphone as separate, synchronized sources
- Write rough notes while recording and use them to guide the generated result
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

## Releases

Push a semantic version tag such as `v1.1.0`, then publish a GitHub Release for
that tag. The macOS release workflow builds Burrito, signs the update archive
with Sparkle EdDSA, and attaches `Burrito.dmg` and the latest `appcast.xml`.

```sh
git switch main
git pull --ff-only
git tag -a v0.0.2 -m "Burrito v0.0.2"
git push origin v0.0.2
gh release create v0.0.2 --verify-tag --title "Burrito v0.0.2" --generate-notes
```

No version file needs to be edited. The workflow derives
`CFBundleShortVersionString` from the release tag and uses the GitHub Actions run
number as the monotonically increasing `CFBundleVersion`.

The first download is currently ad-hoc signed, so macOS requires the user to
approve that installation. Once Burrito is installed, Sparkle validates future
releases with Burrito’s embedded public key, installs them in place, and
relaunches the app. The private signing key is stored only in the
`SPARKLE_PRIVATE_KEY` GitHub Actions secret and the maintainer’s login Keychain.

## Model attribution

Optional local transcription uses [FluidAudio](https://github.com/FluidInference/FluidAudio) and NVIDIA’s [Parakeet TDT 0.6B v2](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2) or [v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) models. FluidAudio is Apache-2.0 licensed. The Parakeet model weights are provided under CC BY 4.0.

## License

MIT © 2026 Deepanshu Mishra
