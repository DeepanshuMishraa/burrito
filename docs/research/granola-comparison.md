# Burrito vs. Granola: product-gap research

**Research date:** July 30, 2026

**Scope:** Granola's public first-party website, help center, changelog, security material, and API documentation; Burrito's current repository. Granola's public changelog visible during this review ends at the week of April 27, 2026, so newer app-only behavior may not be represented.

## Executive conclusion

Burrito already has the essential private capture-to-note loop: bot-free system and microphone capture, local transcription, on-device note generation, editable transcripts and notes, custom templates, search, folders, favorites, Trash, Markdown export, recovery, and optional retained audio. Its strongest differentiation is not feature parity but **inspectable, local ownership**: no account, no Burrito cloud, no third-party inference, and an MIT-licensed codebase ([README](../../README.md), [license](../../LICENSE)).

It is not yet a complete open-source Granola alternative because it lacks three parts of Granola's core experience:

1. **A meeting-aware capture workflow:** event-linked notes, meeting URLs and attendees, reminders, call detection, smart start/stop, and a lightweight out-of-window controller.
2. **Human-in-the-loop notes and memory:** writing private notes during capture, using them to guide generation, source citations, and chat over one or many meetings.
3. **Useful paths out of the app:** integrations or a stable local API/MCP surface, plus optional sync/sharing for people who need a team product.

The menu-bar app is useful, but it is not the primary missing feature. Build a small menu-bar controller only as part of the meeting-aware workflow. A menu-bar icon that merely opens the main window would add little value.

## Feature matrix

Status reflects implementation found in this repository, not a fresh end-to-end release test.

| Capability | Granola | Burrito | Assessment |
| --- | --- | --- | --- |
| Bot-free desktop capture | Captures system audio and microphone on the user's device and works across meeting apps ([transcription docs](https://docs.granola.ai/help-center/taking-notes/transcription), [security overview](https://www.granola.ai/security)). | Captures system audio and an optional microphone track with ScreenCaptureKit; it records no screen frames ([capture](../../Sources/SystemAudioCapture.swift), [README](../../README.md)). | **Core parity.** |
| Local/private processing | Audio is not retained, but live transcription and summarization use providers including Deepgram, AssemblyAI, OpenAI, and Anthropic; notes and transcripts are stored in US-hosted AWS ([security overview](https://www.granola.ai/security)). | Apple Speech or local Parakeet transcription and Apple Foundation Models generation; notes and files remain on the Mac ([transcriber](../../Sources/LocalTranscriber.swift), [generator](../../Sources/FoundationNoteGenerator.swift), [privacy policy](../../website/src/LegalPages.tsx)). | **Burrito advantage.** |
| Live transcript | Shows a live transcript, separated into system audio and microphone, with search, copying, deletion, pause, and resume ([transcription docs](https://docs.granola.ai/help-center/taking-notes/transcription)). | Capture writes audio and shows activity levels; transcription runs from the saved files after recording stops, and editing is available after processing ([capture](../../Sources/SystemAudioCapture.swift), [coordinator](../../Sources/AppCoordinator.swift), [note UI](../../Sources/ContentView.swift)). | **Gap.** Add live transcription only if it improves trust or correction without distracting from the meeting. |
| Human notes during the meeting | Users type rough notes during capture; those notes guide the enhanced result and remain visually distinguishable from AI additions ([writing notes](https://docs.granola.ai/help-center/taking-notes/taking-notes-in-granola), [AI-enhanced notes](https://docs.granola.ai/help-center/taking-notes/ai-enhanced-notes)). | The active recording view replaces the note editor. Generation uses only the transcript plus template, then assigns the result to `markdownBody`; it does not use existing `markdownBody` as meeting guidance ([note UI](../../Sources/ContentView.swift), [generation](../../Sources/FoundationNoteGenerator.swift), [coordinator](../../Sources/AppCoordinator.swift)). | **Major gap.** This is more central to Granola's product identity than its menu bar. |
| Structured notes and templates | Built-in and custom templates, regeneration, profile context, and AI-selected formats ([templates](https://docs.granola.ai/help-center/taking-notes/customise-notes-with-templates), [AI-enhanced notes](https://docs.granola.ai/help-center/taking-notes/ai-enhanced-notes)). | Built-in and editable custom templates, local generation, regeneration, and protection against silently replacing user edits ([models](../../Sources/Models.swift), [templates UI](../../Sources/ContentView.swift), [coordinator](../../Sources/AppCoordinator.swift)). | **Strong parity** for individual use. Granola additionally uses calendar/attendee/profile context and can share templates. |
| Source grounding | A user can inspect the transcript basis for a generated point; Granola Chat returns source-linked answers ([AI-enhanced notes](https://docs.granola.ai/help-center/taking-notes/ai-enhanced-notes), [Chat](https://docs.granola.ai/help-center/getting-more-from-your-notes/chatting-with-your-meetings)). | Timestamps exist on transcript segments, but generated Markdown has no durable citation mapping back to passages ([domain](../../Sources/Domain.swift), [generator](../../Sources/FoundationNoteGenerator.swift)). | **Major trust gap.** Add local passage citations before broad chat. |
| Chat and cross-meeting memory | Chat operates on one meeting, selected meetings, folders, people/companies, or the entire history; it supports file context and model selection ([Chat](https://docs.granola.ai/help-center/getting-more-from-your-notes/chatting-with-your-meetings)). | Search covers titles, generated Markdown, and transcript text. There is no conversational retrieval or synthesis across notes ([search UI](../../Sources/ContentView.swift)). | **Major gap.** A local, cited RAG workflow fits Burrito's positioning well. |
| Reusable post-meeting workflows | Recipes are reusable prompts for single or multiple meetings and can be private, workspace-shared, or link-shared ([recipes](https://docs.granola.ai/help-center/getting-more-from-your-notes/recipes)). Granola can draft contextual follow-up emails ([follow-up emails](https://docs.granola.ai/help-center/taking-notes/follow-up-emails)). | Note templates control initial generation, but there is no saved analysis/action workflow after a note exists. | **Gap.** Implement local "actions" or recipes after cited chat exists. |
| Calendar integration | Google and Outlook calendars, selectable calendars, meeting metadata, links, attendees, recurring-meeting relationships, reminders, and event attachment ([calendar docs](https://docs.granola.ai/help-center/getting-started/syncing-your-calendars)). | Calendar events are display-only metadata: Burrito shows up to three local events for seven days, but "Record" starts a generic note; event identity, URL, attendees, and recurrence are not persisted on `Note` ([calendar access](../../Sources/CalendarAccess.swift), [models](../../Sources/Models.swift), [home UI](../../Sources/ContentView.swift)). | **Major workflow gap.** Persist an event snapshot and use it in title, note context, and related-meeting grouping. |
| Meeting reminders and detection | One-minute calendar prompts can open the call, open the matching note, and start transcription. Granola also detects microphone use for ad-hoc call prompts ([notifications](https://docs.granola.ai/help-center/taking-notes/notifications)). | Native notifications report recording started/stopped and note completion; there are no pre-meeting reminders or call detection ([feedback](../../Sources/AppFeedback.swift)). | **High-value gap.** Start with calendar reminders; make call detection optional and transparent. |
| Start/stop automation | Can start at scheduled time after a user opens a meeting note and can stop based on call state, inactivity, sleep, and calendar timing ([transcription docs](https://docs.granola.ai/help-center/taking-notes/transcription)). | Explicit start/stop with an app-scoped keyboard shortcut; interrupted recordings become recoverable ([commands](../../Sources/AppCommands.swift), [coordinator](../../Sources/AppCoordinator.swift)). | **Partial.** Manual start is privacy-friendly; add opt-in smart stop and visible state rather than silent background capture. |
| Menu-bar and out-of-window controls | The macOS tray links to meetings/notes, shows meeting time remaining, and complements a draggable live meeting indicator ([official engineering post](https://www.granola.ai/blog/back-button), [December 2025 update](https://www.granola.ai/updates/whats-new-2025-12-12), [transcription docs](https://docs.granola.ai/help-center/taking-notes/transcription)). | Window-based app with menu commands and shortcuts; there is no `MenuBarExtra`, `NSStatusItem`, or floating capture indicator ([app scene](../../Sources/burritoApp.swift), [commands](../../Sources/AppCommands.swift)). | **Useful supporting gap, not a product pillar.** |
| Speaker identity | Speaker tags can use participant display names in Google Meet and Zoom; fallback is "Me" and "Them" ([speaker tags](https://docs.granola.ai/help-center/taking-notes/speaker-attribution)). | Segments identify only system audio or microphone ("Computer" and "You") ([domain](../../Sources/Domain.swift), [transcript UI](../../Sources/ContentView.swift)). | **High-value gap** for interviews, sales, and multi-party meetings. Prefer local diarization first; platform-name mapping can remain optional. |
| Languages | Desktop supports English plus a multi-language mode across ten documented languages; mobile supports additional languages ([language docs](https://docs.granola.ai/help-center/customising-granola/multi-language)). | User selects a locale; Apple Speech provides the broad fallback and optional Parakeet models serve supported languages ([settings](../../Sources/Settings.swift), [Parakeet](../../Sources/ParakeetTranscriber.swift)). | **Partial/uncertain.** Burrito needs a published, tested support matrix rather than a raw locale picker. |
| Organization and retrieval | Private and team spaces, nested/multi-membership folders, recurring-meeting auto-add, People and Companies, and chat at each scope ([spaces and folders](https://docs.granola.ai/help-center/sharing/folders/spaces-and-folders), [People and Companies](https://docs.granola.ai/help-center/people-and-companies)). | One folder per note, favorites, full-text search, Trash, and recent date grouping ([models](../../Sources/Models.swift), [library UI](../../Sources/ContentView.swift)). | **Good personal baseline.** Add people/recurring-meeting views before complex folder semantics. |
| Sharing and collaboration | Private by default, with viewer/collaborator roles, public links, shared/team folders, comments/mentions, and browser access ([sharing](https://docs.granola.ai/help-center/sharing/sharing-notes), [spaces and folders](https://docs.granola.ai/help-center/sharing/folders/spaces-and-folders)). | macOS share sheet, clipboard, and a Markdown file export. No accounts, sync, shared editing, or web viewer ([note UI](../../Sources/ContentView.swift)). | **Intentional gap today.** Important for a Granola replacement for teams, but not required for a compelling private personal alternative. |
| Integrations and automation | Slack, Notion, Zapier, HubSpot, Attio, Affinity, public API, MCP, and webhooks are documented ([integrations](https://docs.granola.ai/help-center/sharing/integrations/integrations-with-granola), [API](https://docs.granola.ai/introduction), [MCP](https://docs.granola.ai/help-center/sharing/integrations/mcp), [webhooks](https://docs.granola.ai/webhooks)). | Markdown export, clipboard, and the macOS share sheet only. | **Strategic gap.** A local read-only API, CLI, URL scheme, or MCP server is more aligned than cloning every SaaS connector. |
| Bulk portability | Per-user CSV export includes titles, summaries, transcripts, and details, subject to documented exclusions ([export docs](https://docs.granola.ai/help-center/sharing/exporting-notes)). | Exports one note's generated Markdown at a time; the transcript is not included in that Markdown export ([note UI](../../Sources/ContentView.swift)). | **Gap.** Add bulk, documented, lossless export/import before cloud sync. |
| Platforms | macOS, Windows, iOS, Android, web viewing/editing, phone calls, and Apple Watch entry points are documented ([product page](https://www.granola.ai/), [mobile docs](https://docs.granola.ai/help-center/ios/getting-started), [Watch docs](https://docs.granola.ai/help-center/ios/apple-watch)). | macOS 26 on Apple silicon with Apple Intelligence ([README](../../README.md), [project](../../project.yml)). | **Large reach gap, but not the first priority.** Platform expansion would challenge the local Foundation Models architecture. |
| Reliability and recovery | Granola does not store desktop audio, so audio playback/recovery is unavailable; the service provides cloud sync and daily backups for stored notes ([transcription docs](https://docs.granola.ai/help-center/taking-notes/transcription), [security overview](https://www.granola.ai/security)). | Interrupted/failed sessions preserve recoverable audio, notes are local, successful audio deletion is the default, and users may opt to retain/play audio ([coordinator](../../Sources/AppCoordinator.swift), [recording store](../../Sources/RecordingFileStore.swift)). | **Burrito advantage** for capture recovery and ownership; **Granola advantage** for multi-device availability and remote backup. |
| Open source and extensibility | Granola is a proprietary hosted product; its terms reserve Granola's rights in the service and IP ([platform terms](https://www.granola.ai/static/Granola-Platform-Terms-2025-12-19.pdf)). | Complete application source is MIT licensed ([license](../../LICENSE)). | **Burrito's defining advantage.** Protect this by keeping core capture, storage, retrieval, and inference usable without a service. |

## Ranked gaps

The ranking weighs user value, how often the feature affects meetings, fit with Burrito's local-first promise, and implementation leverage.

### 1. In-meeting notes that guide generation

**Priority: P0 · Very high value · Excellent strategic fit**

Let the user write rough Markdown while Burrito records, store it separately from generated notes, and feed it to local generation as high-priority context. Preserve provenance in the UI so the user can distinguish their words from generated expansion.

This closes the most important conceptual gap: Granola is a notepad that listens, while Burrito currently behaves more like a recorder that later creates a document.

### 2. Event-linked recordings and meeting context

**Priority: P0 · Very high value · Excellent fit**

Persist a small `CalendarEventSnapshot` on each note: stable event ID where available, title, start/end, meeting URL, attendee names, organizer, recurrence identifier, and calendar name. Starting from an upcoming event should create or open that event's note, not a generic recording. Use this snapshot for note generation and related-meeting views.

This one domain change unlocks better titles, one-click join/start, reminders, attendee-aware notes, recurring history, future people views, and an actually useful menu-bar surface.

### 3. Grounded local chat over one or many notes

**Priority: P0 · Very high value · Strong differentiator**

Build in two increments:

1. Generate stable source references from note sections to transcript segment IDs.
2. Add cited local Q&A for one note, then selected notes/folders, then all notes.

Answers should quote or link to timestamped passages and say when the local evidence is insufficient. This turns a library of Markdown into memory while preserving the local-first advantage Granola cannot offer.

### 4. Speaker attribution

**Priority: P1 · High value · Good fit**

Add local diarization and a correction workflow. Keep audio source (`system`/`microphone`) separate from speaker identity; several people can share the system track. Calendar attendees can provide suggestions, but should never be treated as proof of who spoke.

### 5. Meeting reminders, optional call detection, and smart stop

**Priority: P1 · High value · Good fit with explicit controls**

First ship event reminders that open the meeting URL and event-linked Burrito note. Then consider opt-in call detection and inactivity/call-end stopping. Every automatic path should preserve Granola's useful rule: the user takes an explicit action before capture begins.

### 6. A compact menu-bar meeting controller

**Priority: P1 · Medium-high value · Supporting feature**

Build it after event-linked notes because its useful content depends on meeting state. The smallest valuable surface is:

- next meeting and "Join + start";
- current note title, elapsed/time remaining, and unmistakable recording state;
- stop/resume and open note;
- recent ready/recoverable notes;
- quick recording;
- Quit with an explicit warning while recording.

Do not make Burrito menu-bar-only. The library, editor, transcript, templates, and models require a real window. A draggable floating indicator is optional polish after the menu-bar controller proves that users lose track of capture state.

### 7. Lossless portability and an extension surface

**Priority: P1 · High strategic value · Excellent open-source fit**

Provide versioned bulk export/import containing notes, raw user notes, generated Markdown, transcript segments and timestamps, template snapshots, event snapshots, folders, and retained-audio references. Then expose a read-only local CLI/API or MCP server. This enables Obsidian, Raycast, Shortcuts, and community integrations without requiring Burrito to host a SaaS integration platform.

### 8. Local recipes and post-meeting actions

**Priority: P2 · Medium value · Good fit**

After cited chat exists, allow saved local prompts such as "draft follow-up," "extract decisions," or "create issue list." Keep recipes separate from generation templates: templates shape the canonical note; recipes derive optional outputs.

### 9. Relationship and recurring-meeting views

**Priority: P2 · Medium value · Good fit**

Use event and attendee metadata to group recurring meetings, people, and companies locally. This is more useful than reproducing Granola's team-space folder complexity for a single-user app.

### 10. Optional encrypted sync and collaboration

**Priority: P3 · High value for teams · Weak immediate fit / high cost**

This is necessary only if "open-source Granola" means a team replacement, rather than the best private personal alternative. Treat it as a separable, opt-in subsystem. Start with user-owned sync/export and read-only sharing before real-time collaborative editing, workspace administration, SSO, audit controls, or CRM connectors.

### 11. Mobile, Windows, web, and Watch

**Priority: P3 · Segment-expanding · Very high cost**

These increase reach but do not repair Burrito's current meeting loop. iPhone capture is the most strategically coherent next platform for in-person meetings. Windows would require replacement choices for ScreenCaptureKit, SwiftUI, Apple Speech, SwiftData, and Foundation Models, making it closer to a product rewrite than a port.

## Do we need the menu-bar app?

**Yes, eventually; no, it is not the blocker to product-market parity.**

Granola's menu-bar/tray surface solves three concrete problems: reach the right upcoming meeting, see that capture is active without returning to the app, and control the meeting while another window has focus. Burrito currently relies on its full window, shortcuts, and native notifications. For a tool used during calls, persistent state visibility is a trust and convenience feature—not merely decoration.

The implementation is justified when it is backed by event-linked notes and recording state. Until then:

- `⌘⇧R` already covers expert start/stop;
- native notifications cover start, stop, and completion;
- a tray icon would mainly duplicate "open Burrito" and "new recording."

Recommended sequence:

1. Event-linked notes and one-click join/start.
2. Pre-meeting reminder and unmistakable active recording state.
3. Compact menu-bar controller.
4. Measure missed starts, accidental long recordings, and window switching.
5. Add a floating indicator only if those observations show the menu bar is insufficient.

## Privacy and open-source position

### Where Burrito is materially stronger

- **No account or service dependency.** The current app has no authentication, payment, remote database, analytics, or Burrito-operated API ([README](../../README.md), [privacy policy](../../website/src/LegalPages.tsx)).
- **Inference remains on-device.** Transcription uses Apple Speech or downloaded local Parakeet models; generation uses Apple Foundation Models ([local transcriber](../../Sources/LocalTranscriber.swift), [Parakeet](../../Sources/ParakeetTranscriber.swift), [generator](../../Sources/FoundationNoteGenerator.swift)).
- **Auditable and forkable.** MIT licensing makes the behavior inspectable and permits community modification ([license](../../LICENSE)).
- **Recoverability is explicit.** Failed and interrupted sessions retain local audio; successful sessions delete it by default unless the user opts in ([coordinator](../../Sources/AppCoordinator.swift)).

Granola, by contrast, states that it sends data to transcription and AI providers, stores notes and transcripts in an AWS VPC in the United States, and may use anonymized data to improve its models unless the user opts out; third-party model training is prohibited by its provider agreements ([security overview](https://www.granola.ai/security), [model training](https://docs.granola.ai/help-center/consent-security-privacy/model-training), [privacy policy](https://docs.granola.ai/help-center/policies/privacy-policy)). Granola also offers controls Burrito does not yet have, including SOC 2 Type II, enterprise sharing controls, data processing terms, transcript retention controls, and documented transparency features ([security standards](https://docs.granola.ai/help-center/consent-security-privacy/our-security-standards), [transcript auto-deletion](https://docs.granola.ai/help-center/consent-security-privacy/transcript-auto-deletion), [transparency features](https://docs.granola.ai/help-center/consent-security-privacy/transparency-solutions/introduction)).

### Claims Burrito should not overstate

Local-first and open source do not automatically mean secure:

- The project currently disables the App Sandbox ([project configuration](../../project.yml)).
- The repository does not show application-level encryption for the SwiftData store or retained recordings. Protection therefore depends substantially on macOS account security and disk encryption.
- There is no independent security audit, signed privacy guarantee, enterprise admin policy, or documented threat model in this repository.
- Speaker attribution, call detection, and meeting capture create consent obligations regardless of whether processing is local. A visible capture indicator and clear consent guidance should accompany those features.
- Optional Parakeet downloads contact third-party hosting, even though meeting content is not part of that download request ([privacy policy](../../website/src/LegalPages.tsx)).

The credible positioning is:

> **The open-source, local-first meeting notebook for people who want useful memory without surrendering their conversations to a service.**

That is stronger and more defensible than claiming feature-for-feature Granola parity today.

## Suggested product sequence

1. **Notepad-first capture:** simultaneous rough notes, separate provenance, and generation informed by user cues.
2. **Meeting-aware foundation:** event snapshot, join/start, attendees, recurrence, and related notes.
3. **Trust layer:** generated-note citations, better live state, speaker corrections, and a tested language support matrix.
4. **Local memory:** cited single-note chat, then multi-note/folder chat.
5. **Low-friction capture:** reminders, smart stop, and the compact menu-bar controller.
6. **Ownership and ecosystem:** bulk export/import, local API/CLI/MCP, Shortcuts/Raycast/Obsidian paths.
7. **Optional network features:** encrypted user-owned sync, shareable read-only notes, then collaboration if demand justifies operating a service.

## Verification caveats

- Granola is proprietary; this report can verify only behavior documented in its public first-party material, not implementation details or unannounced experiments.
- Granola's public product changelog available during research ended at April 27, 2026 even though this report's cutoff is July 30, 2026 ([changelog](https://docs.granola.ai/help-center/changelog)). Public documentation may lag the shipping app.
- Plan availability changes over time. The matrix focuses on capability, not entitlement; Granola's pricing page should be checked before making plan-by-plan claims ([pricing](https://www.granola.ai/pricing)).
- Burrito status is based on source inspection. This research did not install both production apps and run a controlled set of meetings, so transcription quality, latency, energy use, failure recovery, and UX polish are not benchmarked.
- Neither vendor publishes directly comparable transcription or note-quality evaluations for the exact same meeting corpus. No accuracy winner is asserted.
