import AITesting
import AI
import AVFoundation
import EventKit
import Foundation
import Testing
import UserNotifications
@testable import Burrito

@MainActor
@Suite("Calendar access")
struct CalendarAccessTests {
    @Test("Meeting reminders use stable identifiers and never schedule in the past")
    func meetingReminderPlan() throws {
        let now = Date(timeIntervalSinceReferenceDate: 100_000)
        let event = UpcomingCalendarEvent(
            snapshot: CalendarEventSnapshot(
                eventIdentifier: "weekly-sync",
                title: "Weekly sync",
                startDate: now.addingTimeInterval(120),
                endDate: now.addingTimeInterval(1_920),
                meetingURL: URL(string: "https://meet.example.com/weekly"),
                attendeeNames: [],
                organizerName: nil,
                recurrenceIdentifier: "weekly",
                calendarName: "Work"
            ),
            isAllDay: false
        )

        let reminder = try #require(
            MeetingReminder.plan(events: [event], relativeTo: now).first
        )

        #expect(reminder.id == "meeting-reminder-weekly-sync-100120")
        #expect(reminder.deliveryDate == now.addingTimeInterval(1))
        #expect(reminder.event == event.snapshot)
    }

    @Test("Meeting window keeps the previous 24 hours visible")
    func meetingWindowIncludesRecentEvents() {
        let now = Date(timeIntervalSinceReferenceDate: 100_000)

        #expect(
            CalendarMeetingWindow.start(relativeTo: now)
                == now.addingTimeInterval(-(24 * 60 * 60))
        )
    }

    @Test("Meeting list keeps upcoming events when recent meetings fill the card")
    func meetingListKeepsUpcomingEvents() {
        let now = Date(timeIntervalSinceReferenceDate: 100_000)
        func event(id: String, startOffset: TimeInterval) -> UpcomingCalendarEvent {
            UpcomingCalendarEvent(
                snapshot: CalendarEventSnapshot(
                    eventIdentifier: id,
                    title: id,
                    startDate: now.addingTimeInterval(startOffset),
                    endDate: now.addingTimeInterval(startOffset + 300),
                    meetingURL: nil,
                    attendeeNames: [],
                    organizerName: nil,
                    recurrenceIdentifier: nil,
                    calendarName: "Work"
                ),
                isAllDay: false
            )
        }
        let recent: [UpcomingCalendarEvent] = [
            event(id: "recent-1", startOffset: -600),
            event(id: "recent-2", startOffset: -1_200),
            event(id: "recent-3", startOffset: -1_800),
            event(id: "recent-4", startOffset: -2_400),
        ]
        let upcoming: [UpcomingCalendarEvent] = [
            event(id: "upcoming-1", startOffset: 600),
            event(id: "upcoming-2", startOffset: 1_200),
        ]

        let visible = CalendarMeetingWindow.visibleEvents(
            recent + upcoming,
            relativeTo: now
        )

        #expect(visible.map { $0.id } == ["recent-1", "upcoming-1", "upcoming-2"])
    }

    @Test("Meeting identity ignores title casing and surrounding whitespace")
    func meetingIdentityNormalizesTitles() {
        let start = Date(timeIntervalSinceReferenceDate: 100)
        let end = Date(timeIntervalSinceReferenceDate: 200)

        #expect(
            UpcomingMeetingIdentity(title: " Weekly Sync ", startDate: start, endDate: end)
                == UpcomingMeetingIdentity(title: "weekly sync", startDate: start, endDate: end)
        )
    }

    @Test("Calendar database changes refresh upcoming events")
    func eventStoreChangesRefresh() throws {
        let eventStore = EKEventStore()
        let notificationCenter = NotificationCenter()
        var tick = 0
        let access = CalendarAccess(
            eventStore: eventStore,
            notificationCenter: notificationCenter,
            now: {
                tick += 1
                return Date(timeIntervalSinceReferenceDate: TimeInterval(tick))
            }
        )
        let initialRefresh = try #require(access.lastRefreshedAt)

        notificationCenter.post(
            EKEventStore.EventStoreChanged(),
            subject: eventStore
        )

        let changedRefresh = try #require(access.lastRefreshedAt)
        #expect(changedRefresh > initialRefresh)
    }
}

@Suite("Smart stop")
struct SmartStopTests {
    @Test("Suggests stopping only after a calendar meeting ends in sustained silence")
    func calendarMeetingEndSuggestion() {
        let end = Date(timeIntervalSinceReferenceDate: 100_000)

        #expect(
            SmartStopPolicy.decision(
                now: end.addingTimeInterval(59),
                eventEnd: end,
                recordingElapsed: 1_800,
                silentFor: 120,
                alreadySuggested: false
            ) == .keepRecording
        )
        #expect(
            SmartStopPolicy.decision(
                now: end.addingTimeInterval(60),
                eventEnd: end,
                recordingElapsed: 1_800,
                silentFor: 45,
                alreadySuggested: false
            ) == .suggestStop
        )
        #expect(
            SmartStopPolicy.decision(
                now: end.addingTimeInterval(120),
                eventEnd: end,
                recordingElapsed: 1_800,
                silentFor: 120,
                alreadySuggested: true
            ) == .keepRecording
        )
    }
}

@Suite("Appearance")
struct AppearanceTests {
    @Test("Unknown stored appearance falls back to the system")
    func unknownAppearanceFallback() {
        #expect(BurritoAppearance.resolve("future-mode") == .system)
    }

    @Test("System appearance remains inherited")
    func systemAppearanceIsNotForced() {
        #expect(BurritoAppearance.system.colorScheme == nil)
        #expect(BurritoAppearance.light.colorScheme == .light)
        #expect(BurritoAppearance.dark.colorScheme == .dark)
    }
}

@Suite("Notification access")
struct NotificationAccessTests {
    @Test("Authorization without a banner style still needs settings")
    func requiresVisibleAlertStyle() {
        #expect(
            NotificationAccess.resolveState(
                authorizationStatus: .authorized,
                alertSetting: .enabled,
                alertStyle: .none
            ) == .needsAlertStyle
        )
        #expect(
            NotificationAccess.resolveState(
                authorizationStatus: .authorized,
                alertSetting: .enabled,
                alertStyle: .banner
            ) == .granted
        )
    }

    @Test("Meeting reminders require visible notification alerts")
    func meetingRemindersRequireVisibleAlerts() {
        #expect(
            MeetingReminderScheduler.canSchedule(
                authorizationStatus: .authorized,
                alertSetting: .disabled,
                alertStyle: .banner
            ) == false
        )
        #expect(
            MeetingReminderScheduler.canSchedule(
                authorizationStatus: .authorized,
                alertSetting: .enabled,
                alertStyle: .banner
            )
        )
    }

    @MainActor
    @Test("Notification actions are available before handling completes")
    func notificationActionsFinishAfterProcessing() async {
        _ = MeetingActionInbox.shared.consume()
        let event = CalendarEventSnapshot(
            eventIdentifier: "weekly-sync",
            title: "Weekly sync",
            startDate: Date(timeIntervalSinceReferenceDate: 100),
            endDate: Date(timeIntervalSinceReferenceDate: 200),
            meetingURL: nil,
            attendeeNames: [],
            organizerName: nil,
            recurrenceIdentifier: nil,
            calendarName: "Work"
        )

        BurritoAppFeedback.processNotificationAction(
            BurritoNotificationContract.recordAction,
            event: event
        )
        let completedAction = MeetingActionInbox.shared.consume()

        #expect(completedAction == .record(event, joinsMeeting: false))
    }
}

@Suite("Transcript")
struct TranscriptTests {
    @Test("Generation text keeps stable passage references and corrected speakers")
    func rendersStableSourceReferences() {
        let id = UUID(uuidString: "A27D24D0-9977-4C5C-92B4-581DB235D736")
        let segment = TranscriptSegment(
            id: id ?? UUID(),
            source: .system,
            startTime: 65,
            duration: 2,
            text: "Ship the trust layer."
        )

        #expect(
            Transcript.rendered([segment])
                == "[1:05] [source:A27D24D0-9977-4C5C-92B4-581DB235D736] System: Ship the trust layer."
        )
    }

    @Test("Corrected speaker names replace source labels without changing audio identity")
    func rendersCorrectedSpeaker() {
        let segment = TranscriptSegment(
            source: .system,
            startTime: 0,
            duration: 2,
            text: "I own the follow-up.",
            speakerName: "Albert"
        )

        let rendered = Transcript.rendered([segment])

        #expect(rendered.contains("Albert: I own the follow-up."))
        #expect(segment.source == .system)
    }

    @Test("Transcript citation links resolve only stable passage identifiers")
    func resolvesTranscriptCitation() {
        let id = UUID(uuidString: "A27D24D0-9977-4C5C-92B4-581DB235D736")
        let validURL = URL(
            string: "burrito://transcript/A27D24D0-9977-4C5C-92B4-581DB235D736"
        )
        let invalidURL = URL(string: "https://example.com/transcript/not-local")

        #expect(TranscriptCitation.segmentID(from: validURL) == id)
        #expect(TranscriptCitation.segmentID(from: invalidURL) == nil)
    }

    @Test("System and microphone segments merge by timestamp and source")
    func mergesSegments() {
        // Given
        let system = [
            TranscriptSegment(source: .system, startTime: 3, duration: 1, text: "Later"),
            TranscriptSegment(source: .system, startTime: 1, duration: 1, text: "System first"),
        ]
        let microphone = [
            TranscriptSegment(source: .microphone, startTime: 1, duration: 1, text: "Mic first"),
        ]

        // When
        let merged = Transcript.merge(system: system, microphone: microphone)

        // Then
        #expect(merged.map(\.text) == ["Mic first", "System first", "Later"])
        #expect(merged.map(\.source) == [.microphone, .system, .system])
    }

    @Test("Displays newest transcript passages first")
    func latestFirst() {
        let segments = [
            TranscriptSegment(source: .system, startTime: 2, duration: 1, text: "Middle"),
            TranscriptSegment(source: .system, startTime: 8, duration: 1, text: "Latest"),
            TranscriptSegment(source: .system, startTime: 0, duration: 1, text: "Oldest"),
        ]

        #expect(Transcript.latestFirst(segments).map(\.text) == ["Latest", "Middle", "Oldest"])
    }
}

@Suite("Local memory")
struct LocalMemoryTests {
    @Test("Chat prompt separates general knowledge from meeting retrieval")
    func generalChatPrompt() {
        #expect(BurritoChatPrompt.instructions(scopedToMeeting: false).contains(
            "Do not assume every question is about meetings"
        ))
        #expect(BurritoChatPrompt.instructions(scopedToMeeting: false).contains(
            MeetingSearchTool.name
        ))
    }

    @Test("Meeting search tool returns citable transcript passages")
    func meetingSearchTool() async throws {
        let document = MemoryDocument(
            noteID: UUID(),
            title: "Launch planning",
            updatedAt: .now,
            segments: [
                TranscriptSegment(
                    source: .system,
                    startTime: 12,
                    duration: 3,
                    text: "The launch date is October 12."
                ),
            ]
        )
        let collector = MeetingEvidenceCollector()
        let tool = MeetingSearchTool.make(
            documents: [document],
            scopedDocument: nil,
            collector: collector
        )

        let output = try await tool.execute(["query": "When is the launch date?"])
        let evidenceText = try #require(output["evidence"]?.stringValue)
        let collected = await collector.snapshot()

        #expect(evidenceText.contains("October 12"))
        #expect(evidenceText.contains("burrito://memory/"))
        #expect(collected.count == 1)
    }

    @Test("Library questions retrieve the most relevant transcript passage")
    func retrievesRelevantEvidence() {
        let launch = MemoryDocument(
            noteID: UUID(),
            title: "Launch planning",
            updatedAt: Date(timeIntervalSinceReferenceDate: 200),
            segments: [
                TranscriptSegment(
                    source: .system,
                    startTime: 12,
                    duration: 3,
                    text: "The launch date is October 12."
                ),
            ]
        )
        let hiring = MemoryDocument(
            noteID: UUID(),
            title: "Hiring review",
            updatedAt: Date(timeIntervalSinceReferenceDate: 300),
            segments: [
                TranscriptSegment(
                    source: .system,
                    startTime: 4,
                    duration: 2,
                    text: "We should interview two design candidates."
                ),
            ]
        )

        let evidence = LocalMemory.retrieve(
            question: "When is the launch date?",
            from: [hiring, launch],
            limit: 1
        )

        #expect(evidence.map(\.noteID) == [launch.noteID])
        #expect(evidence.first?.segment.text == "The launch date is October 12.")
    }

    @Test("Questions with no lexical match return no transcript evidence")
    func rejectsUnrelatedEvidence() {
        let document = MemoryDocument(
            noteID: UUID(),
            title: "Hiring review",
            updatedAt: .now,
            segments: [
                TranscriptSegment(
                    source: .system,
                    startTime: 4,
                    duration: 2,
                    text: "We should interview two design candidates."
                ),
            ]
        )

        let evidence = LocalMemory.retrieve(
            question: "When does the rocket launch?",
            from: [document]
        )

        #expect(evidence.isEmpty)
    }

    @Test("A scoped meeting supplies evidence for broad questions")
    func retrievesScopedMeetingEvidence() {
        let document = MemoryDocument(
            noteID: UUID(),
            title: "Weekly product review",
            updatedAt: .now,
            segments: [
                TranscriptSegment(
                    source: .system,
                    startTime: 4,
                    duration: 2,
                    text: "Priya will send the revised launch plan on Friday."
                ),
            ]
        )

        let evidence = LocalMemory.retrieve(
            question: "What happened?",
            scopedTo: document
        )

        #expect(evidence.map(\.noteID) == [document.noteID])
        #expect(evidence.first?.segment.text == "Priya will send the revised launch plan on Friday.")
    }

    @Test("Meeting mention parsing recognizes and removes the active query")
    func parsesMeetingMentionQuery() {
        #expect(MemoryMention.query(in: "What changed in @weekly pro") == "weekly pro")
        #expect(MemoryMention.questionWithoutQuery(in: "What changed in @weekly pro") == "What changed in")
        #expect(MemoryMention.query(in: "What does @State do?") == "State do?")
        #expect(MemoryMention.query(in: "email@example.com") == nil)
        #expect(MemoryMention.query(in: "No mention here") == nil)
    }

    @Test("Memory prompts require cited answers and explicit uncertainty")
    func promptContract() {
        let noteID = UUID(uuidString: "B445F1FC-D124-4CD4-A157-D25201200659") ?? UUID()
        let segmentID = UUID(uuidString: "A27D24D0-9977-4C5C-92B4-581DB235D736") ?? UUID()
        let evidence = MemoryEvidence(
            noteID: noteID,
            noteTitle: "Launch planning",
            noteUpdatedAt: .now,
            segment: TranscriptSegment(
                id: segmentID,
                source: .system,
                startTime: 12,
                duration: 3,
                text: "The launch date is October 12."
            )
        )

        let source = MemoryPrompt.source(
            question: "When is launch?",
            evidence: [evidence]
        )

        #expect(MemoryPrompt.instructions.contains("evidence is insufficient"))
        #expect(MemoryPrompt.instructions.contains("burrito://memory/<NOTE-UUID>/<SEGMENT-UUID>"))
        #expect(source.contains("Launch planning"))
        #expect(source.contains("burrito://memory/\(noteID.uuidString)/\(segmentID.uuidString)"))
    }

    @Test("Memory prompts reserve model context for the answer")
    func boundsQuestionAndEvidence() async throws {
        let evidence = MemoryEvidence(
            noteID: UUID(),
            noteTitle: "Launch planning",
            noteUpdatedAt: .now,
            segment: TranscriptSegment(
                source: .system,
                startTime: 12,
                duration: 3,
                text: String(repeating: "Launch evidence ", count: 300)
            )
        )
        let measurer = CharacterTokenMeasurer(size: 2_400)

        let prepared = try await MemoryPrompt.boundedSource(
            question: String(repeating: "What changed? ", count: 200),
            evidence: [evidence],
            tokenMeasurer: measurer,
            reservedResponseTokens: 768,
            safetyMargin: 128
        )

        let requestTokens = try await measurer.tokenCount(
            MemoryPrompt.instructions + prepared.prompt
        )
        #expect(requestTokens + 768 + 128 <= measurer.size)
        #expect(!prepared.evidence.isEmpty)
    }

    @Test("Memory answers accept only citations from the supplied evidence")
    func validatesAnswerCitations() {
        let evidence = MemoryEvidence(
            noteID: UUID(),
            noteTitle: "Launch planning",
            noteUpdatedAt: .now,
            segment: TranscriptSegment(
                id: UUID(),
                source: .system,
                startTime: 12,
                duration: 3,
                text: "The launch date is October 12."
            )
        )
        let validURL = evidence.citationURL?.absoluteString ?? ""
        let inventedURL = "burrito://memory/\(UUID().uuidString)/\(UUID().uuidString)"

        #expect(
            MemoryAnswer.validated(
                "Launch is October 12. [source](\(validURL))",
                against: [evidence]
            ) != nil
        )
        #expect(MemoryAnswer.validated("Launch is October 12.", against: [evidence]) == nil)
        #expect(
            MemoryAnswer.validated(
                "Launch is October 12. [source](\(inventedURL))",
                against: [evidence]
            ) == nil
        )
    }

    @Test("Memory answers reject external Markdown links")
    func rejectsExternalLinks() {
        let evidence = MemoryEvidence(
            noteID: UUID(),
            noteTitle: "Launch planning",
            noteUpdatedAt: .now,
            segment: TranscriptSegment(
                id: UUID(),
                source: .system,
                startTime: 12,
                duration: 3,
                text: "The launch date is October 12."
            )
        )
        let validURL = evidence.citationURL?.absoluteString ?? ""
        let answer = "Launch is October 12. [source](\(validURL)) [details](https://example.com)"

        #expect(MemoryAnswer.validated(answer, against: [evidence]) == nil)
    }

    @Test("Memory answers preserve link-free insufficient-evidence explanations")
    func preservesInsufficientEvidenceExplanation() throws {
        let evidence = MemoryEvidence(
            noteID: UUID(),
            noteTitle: "Launch planning",
            noteUpdatedAt: .now,
            segment: TranscriptSegment(
                id: UUID(),
                source: .system,
                startTime: 12,
                duration: 3,
                text: "The launch date is October 12."
            )
        )
        let explanation = "The supplied evidence does not identify who approved the launch."

        let answer = try #require(
            MemoryAnswer.validated(
                "INSUFFICIENT_EVIDENCE: \(explanation)",
                against: [evidence]
            )
        )
        #expect(answer.contains("Unverified AI answer"))
        #expect(answer.contains(explanation))
        #expect(!answer.contains("INSUFFICIENT_EVIDENCE:"))
    }

    @Test("Memory answers strip insufficient-evidence markers when citations are present")
    func stripsInsufficientEvidenceMarkerFromCitedAnswer() throws {
        let evidence = MemoryEvidence(
            noteID: UUID(),
            noteTitle: "Launch planning",
            noteUpdatedAt: .now,
            segment: TranscriptSegment(
                id: UUID(),
                source: .system,
                startTime: 12,
                duration: 3,
                text: "The launch date is October 12."
            )
        )
        let validURL = evidence.citationURL?.absoluteString ?? ""
        let explanation = "The date is known, but the approver is not. [source](\(validURL))"

        let answer = try #require(
            MemoryAnswer.validated(
                "INSUFFICIENT_EVIDENCE: \(explanation)",
                against: [evidence]
            )
        )
        #expect(answer.contains(explanation))
        #expect(!answer.contains("INSUFFICIENT_EVIDENCE:"))
    }

    @Test("Memory answers label claim grounding as unverified")
    func labelsUnverifiedGrounding() throws {
        let evidence = MemoryEvidence(
            noteID: UUID(),
            noteTitle: "Launch planning",
            noteUpdatedAt: .now,
            segment: TranscriptSegment(
                id: UUID(),
                source: .system,
                startTime: 12,
                duration: 3,
                text: "The launch date is October 12."
            )
        )
        let validURL = evidence.citationURL?.absoluteString ?? ""
        let unsupportedClaim = "The moon is made of cheese. [source](\(validURL))"

        let answer = try #require(
            MemoryAnswer.validated(unsupportedClaim, against: [evidence])
        )
        #expect(answer.contains("Unverified AI answer"))
        #expect(answer.contains(unsupportedClaim))
    }
}

@Suite("Audio levels")
struct AudioLevelTests {
    @Test("Measures interleaved microphone PCM")
    func measuresInterleavedPCM() throws {
        let format = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: 48_000,
                channels: 1,
                interleaved: true
            )
        )
        let buffer = try #require(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4)
        )
        buffer.frameLength = 4
        let audioBuffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let audioBuffer = try #require(audioBuffers.first)
        let data = try #require(audioBuffer.mData)
        let samples = data.assumingMemoryBound(to: Int16.self)
        samples[0] = 12_000
        samples[1] = -12_000
        samples[2] = 12_000
        samples[3] = -12_000

        #expect(AudioLevel.measure(buffer) > 0.5)
    }
}

@Suite("Transcription configuration")
struct TranscriptionConfigurationTests {
    @Test("Language matrix distinguishes downloadable and system transcription")
    func languageCoverageMatrix() {
        #expect(TranscriptionLanguage.resolve("en-US").engineCoverage == .downloadableLocalModel)
        #expect(TranscriptionLanguage.resolve("hi-IN").engineCoverage == .appleSpeech)
    }

    @Test("Parakeet routes only languages covered by its model families")
    func routesParakeetLanguages() {
        #expect(
            ParakeetModelVariant.candidates(languageIdentifier: "en-US")
                == [.englishV2, .englishCompact, .multilingualV3]
        )
        #expect(
            ParakeetModelVariant.supporting(languageIdentifier: "fr-FR") == .multilingualV3
        )
        #expect(
            ParakeetModelVariant.supporting(languageIdentifier: "ja-JP") == .japanese
        )
        #expect(
            ParakeetModelVariant.supporting(languageIdentifier: "hi-IN") == nil
        )
    }

    @Test("Persisted language identifiers resolve safely")
    func resolvesTranscriptionLanguage() {
        #expect(TranscriptionLanguage.resolve("de-DE").title == "German")
        #expect(TranscriptionLanguage.resolve("unknown").identifier == "en-US")
    }
}

private struct CharacterTokenMeasurer: PromptTokenMeasuring {
    let size: Int
    var contextSize: Int { get async { size } }
    func tokenCount(_ text: String) async throws -> Int { text.count }
}

@Suite("Foundation model adapter")
struct FoundationModelAdapterTests {
    @Test("Routes prompts through the Swift AI SDK")
    func routesPromptsThroughSDK() async throws {
        let model = MockLanguageModel(text: "A concise factual digest.")
        let adapter = FoundationModelAdapter(model: model)

        let response = try await adapter.complete(
            instructions: "Use only supplied facts.",
            prompt: "Summarize this transcript.",
            maximumResponseTokens: 384
        )

        #expect(response == "A concise factual digest.")
        let request = try #require(model.requests.first)
        #expect(request.maxOutputTokens == 384)
        #expect(request.messages.map(\.role) == [.system, .user])
        #expect(request.messages.map(\.text) == [
            "Use only supplied facts.",
            "Summarize this transcript.",
        ])
    }

    @Test("Routes chat history and meeting tools through the Swift AI SDK")
    func routesChatToolsThroughSDK() async throws {
        let model = MockLanguageModel(text: "Hello! How can I help?")
        let adapter = FoundationModelAdapter(model: model)
        let tool = AI.Tool(
            name: MeetingSearchTool.name,
            description: "Search meetings",
            parameters: ["type": "object", "properties": [:]]
        )

        let response = try await adapter.completeChat(
            instructions: "Be helpful.",
            conversation: [BurritoChatTurn(role: .user, text: "Hello")],
            question: "How are you?",
            tools: [tool],
            maximumResponseTokens: 512
        )

        #expect(response == "Hello! How can I help?")
        let request = try #require(model.requests.first)
        #expect(request.messages.map(\.role) == [.system, .user, .user])
        #expect(request.tools.map(\.name) == [MeetingSearchTool.name])
    }
}

@Suite("Local language models")
struct LocalLanguageModelTests {
    @Test("Catalog exposes the three pinned Qwen tiers")
    func catalogMetadata() {
        #expect(LocalLanguageModelVariant.allCases == [.small, .medium, .large])
        #expect(LocalLanguageModelVariant.small.parameterCount == "2B parameters")
        #expect(LocalLanguageModelVariant.medium.downloadSize == "≈ 3.1 GB")
        #expect(LocalLanguageModelVariant.large.downloadSizeBytes == 5_980_000_000)
        #expect(
            LocalLanguageModelVariant.small.revision
                == "674aaa7240b91e8012fcad5d791b7dfe5ba90207"
        )
    }

    @Test("Apple remains the safe default until a downloaded model is selected")
    func resolvesPersistedSelection() {
        #expect(
            GenerationModelSelection.resolve(
                persistedValue: nil,
                isInstalled: { _ in false }
            ) == .apple
        )
        #expect(
            GenerationModelSelection.resolve(
                persistedValue: GenerationModelSelection.local(.medium).rawValue,
                isInstalled: { $0 == .medium }
            ) == .local(.medium)
        )
        #expect(
            GenerationModelSelection.resolve(
                persistedValue: GenerationModelSelection.local(.large).rawValue,
                isInstalled: { _ in false }
            ) == .apple
        )
    }

    @Test("Swift AI SDK tools map into Qwen chat history")
    func mapsToolCalling() throws {
        let weather = AI.Tool(
            name: "get_weather",
            description: "Get weather for a city.",
            parameters: [
                "type": "object",
                "properties": ["city": ["type": "string"]],
                "required": ["city"],
            ]
        )
        let request = LanguageModelRequest(
            messages: [
                .user("What is the weather in Delhi?"),
                AI.Message(
                    role: .assistant,
                    content: [
                        .toolCall(
                            AI.ToolCall(
                                id: "call-1",
                                name: "get_weather",
                                arguments: ["city": "Delhi"]
                            )
                        )
                    ]
                ),
                AI.Message(
                    role: .tool,
                    content: [
                        .toolResult(
                            AI.ToolResult(
                                toolCallID: "call-1",
                                name: "get_weather",
                                output: ["temperature": 31]
                            )
                        )
                    ]
                ),
            ],
            tools: [weather]
        )

        let input = try MLXRequestMapper.input(from: request)
        #expect(input.tools?.count == 1)
        guard case .messages(let messages) = input.prompt else {
            Issue.record("Expected Qwen model-specific messages")
            return
        }
        #expect(messages.count == 3)
        #expect(messages[1]["role"] as? String == "assistant")
        #expect(messages[1]["tool_calls"] != nil)
        #expect(messages[2]["role"] as? String == "tool")
    }
}

@Suite("Fallback token estimation")
struct FallbackTokenEstimateTests {
    @Test("Compatibility estimates reserve one token per UTF-8 byte")
    func usesConservativeUpperBound() {
        #expect(FallbackTokenEstimate.count("abcd") == 4)
        #expect(FallbackTokenEstimate.count("🌯") == 4)
    }
}

@Suite("Transcript chunking")
struct TranscriptChunkerTests {
    @Test("Chunks only at transcript segment boundaries")
    func chunksAtSegmentBoundaries() async throws {
        // Given
        let segments = [
            TranscriptSegment(source: .system, startTime: 0, duration: 1, text: String(repeating: "A", count: 250)),
            TranscriptSegment(source: .system, startTime: 1, duration: 1, text: String(repeating: "B", count: 250)),
            TranscriptSegment(source: .microphone, startTime: 2, duration: 1, text: String(repeating: "C", count: 250)),
        ]
        let chunker = TranscriptChunker(
            tokenMeasurer: CharacterTokenMeasurer(size: 500),
            reservedOutputTokens: 100
        )

        // When
        let chunks = try await chunker.chunks(for: segments)

        // Then
        #expect(chunks.count == 3)
        #expect(chunks.flatMap(\.segments) == segments)
    }

    @Test("Reserves prompt overhead when sizing transcript chunks")
    func reservesPromptOverhead() async throws {
        let segments = [
            TranscriptSegment(
                source: .system,
                startTime: 0,
                duration: 1,
                text: String(repeating: "A", count: 150)
            ),
            TranscriptSegment(
                source: .system,
                startTime: 1,
                duration: 1,
                text: String(repeating: "B", count: 150)
            ),
        ]
        let chunker = TranscriptChunker(
            tokenMeasurer: CharacterTokenMeasurer(size: 500),
            reservedOutputTokens: 100,
            reservedInputTokens: 100
        )

        let chunks = try await chunker.chunks(for: segments)

        #expect(chunks.count == 2)
        #expect(chunks.flatMap(\.segments) == segments)
    }

    @Test("Generation rejects auxiliary source that leaves no model input budget")
    func rejectsOversizedHumanNotesBeforeFinalRequest() {
        let result: Result<Int, BurritoError>
        do {
            result = .success(
                try GenerationInputBudget.limit(
                    contextSize: 2_048,
                    instructionTokens: 300,
                    reservedOutputTokens: 1_024,
                    additionalReservedTokens: 1_000,
                    safetyMargin: 256
                )
            )
        } catch let error as BurritoError {
            result = .failure(error)
        } catch {
            Issue.record("Unexpected error: \(error)")
            return
        }

        #expect(
            result == .failure(
                .generationFailed(
                    details: "Human notes and calendar context are too large for on-device generation. Shorten the human notes and choose Generate Again."
                )
            )
        )
    }
}

@Suite("Templates")
struct TemplateTests {
    @Test("Template symbols are searchable by plain-language concepts")
    func searchesTemplateSymbols() {
        #expect(TemplateSymbolOption.matching("meeting").contains {
            $0.systemName == "person.2"
        })
        #expect(TemplateSymbolOption.matching("database").contains {
            $0.systemName == "cylinder"
        })
        #expect(TemplateSymbolOption.matching("  ").count == TemplateSymbolOption.all.count)
    }

    @Test("Every app icon resolves to a Phosphor icon")
    func resolvesEveryAppIcon() {
        #expect(BurritoIconCatalog.allAliasesAreValid)
        #expect(TemplateSymbolOption.all.allSatisfy {
            BurritoIconCatalog.supports($0.systemName)
        })
    }

    @Test(
        "Every built-in template contributes its instructions to the final prompt",
        arguments: BuiltInTemplate.allCases
    )
    func builtInPrompt(template: BuiltInTemplate) {
        // Given
        let snapshot = TemplateSnapshot(
            name: template.name,
            symbol: template.symbol,
            instructions: template.instructions
        )

        // When
        let prompt = GenerationPrompt.finalInstructions(template: snapshot)

        // Then
        #expect(prompt.contains(template.instructions))
        #expect(prompt.contains("first line must be `# <title>`"))
        #expect(prompt.contains("The source may contain profanity"))
        #expect(prompt.contains("untrusted quoted source material"))
    }

    @Test("Every generation stage treats sensitive transcript text as source material")
    func sensitiveSourceMaterialPolicy() {
        let prompts = [
            GenerationPrompt.digestInstructions,
            GenerationPrompt.condenseInstructions,
            GenerationPrompt.titleInstructions(currentTitle: "Current"),
        ]

        for prompt in prompts {
            #expect(prompt.contains("The source may contain profanity"))
            #expect(prompt.contains("untrusted quoted source material"))
            #expect(prompt.contains("Complete the transformation without refusal"))
        }
    }

    @Test("Generation preserves clickable evidence citations")
    func citationPromptContract() {
        let meeting = BuiltInTemplate.meeting
        let final = GenerationPrompt.finalInstructions(
            template: TemplateSnapshot(
                name: meeting.name,
                symbol: meeting.symbol,
                instructions: meeting.instructions
            )
        )

        #expect(GenerationPrompt.digestInstructions.contains("[source:<UUID>]"))
        #expect(GenerationPrompt.condenseInstructions.contains("[source:<UUID>]"))
        #expect(final.contains("burrito://transcript/<UUID>"))
        #expect(final.contains("Do not invent, alter, or omit the UUID"))
    }

    @Test("Custom template instructions are preserved verbatim")
    func customPrompt() {
        // Given
        let custom = TemplateSnapshot(
            name: "Sales Call",
            symbol: "phone",
            instructions: "List objections and exact follow-up commitments."
        )

        // When
        let prompt = GenerationPrompt.finalInstructions(template: custom)

        // Then
        #expect(prompt.contains(custom.instructions))
        #expect(prompt.contains("The source may contain profanity"))
        #expect(prompt.contains("untrusted quoted source material"))
    }

    @Test("Calendar context is labeled separately from notes and transcript")
    func calendarContextPrompt() {
        let event = CalendarEventSnapshot(
            eventIdentifier: "event-42",
            title: "Product weekly",
            startDate: Date(timeIntervalSince1970: 1_800_000_000),
            endDate: Date(timeIntervalSince1970: 1_800_003_600),
            meetingURL: URL(string: "https://meet.google.com/abc-defg-hij"),
            attendeeNames: ["Ari", "Sam"],
            organizerName: "Ari",
            recurrenceIdentifier: "product-weekly",
            calendarName: "Work"
        )

        let source = GenerationPrompt.finalSource(
            digest: "The team approved the launch.",
            userNotes: "- Confirm owner",
            meetingContext: event
        )

        #expect(source.contains("<calendar-context>"))
        #expect(source.contains("Title: Product weekly"))
        #expect(source.contains("Attendees: Ari, Sam"))
        #expect(source.contains("<human-notes>"))
        #expect(source.contains("<transcript-digest>"))
    }

    @Test("Meeting links accept web URLs and reject non-web schemes")
    func meetingLinkValidation() {
        let fallback = "Join at https://meet.google.com/abc-defg-hij when ready."

        #expect(
            MeetingLink.first(
                explicitURL: URL(string: "file:///tmp/invite"),
                location: fallback,
                notes: nil
            )?.absoluteString == "https://meet.google.com/abc-defg-hij"
        )
        #expect(
            MeetingLink.first(
                explicitURL: URL(string: "tel:+15551234"),
                location: nil,
                notes: nil
            ) == nil
        )
    }

    @Test("Title prompt favors the dominant topic across the complete transcript")
    func dominantTopicTitlePrompt() {
        let prompt = GenerationPrompt.titleInstructions(
            currentTitle: "Database System Overview"
        )

        #expect(!prompt.contains("Database System Overview"))
        #expect(prompt.contains("fresh"))
        #expect(prompt.contains("dominant subject"))
        #expect(prompt.contains("complete discussion"))
        #expect(prompt.contains("Do not compare against, preserve, or extend an earlier title"))
    }

    @Test("Legacy built-in snapshots receive the expanded prompt")
    func resolvesLegacyBuiltInPrompt() {
        let template = BuiltInTemplate.meeting
        let snapshot = TemplateSnapshot(
            name: template.name,
            symbol: template.symbol,
            instructions: template.legacyInstructions
        )

        let prompt = GenerationPrompt.finalInstructions(template: snapshot)

        #expect(prompt.contains("Markdown table"))
        #expect(prompt.contains("Never infer owners"))
    }

    @Test("Custom template instructions are not replaced by a matching name")
    func preservesCustomInstructionsWithBuiltInName() {
        let snapshot = TemplateSnapshot(
            name: BuiltInTemplate.summary.name,
            symbol: "sparkles",
            instructions: "Use a single paragraph written as a technical abstract."
        )

        let prompt = GenerationPrompt.finalInstructions(template: snapshot)

        #expect(prompt.contains(snapshot.instructions))
    }

    @Test("Final generation keeps human notes separate from transcript facts")
    func labelsHumanNotesAsPrioritySource() {
        let prompt = GenerationPrompt.finalSource(
            digest: "The team discussed release timing.",
            userNotes: "- Ask Priya whether Friday is firm."
        )

        #expect(prompt.contains("HUMAN NOTES"))
        #expect(prompt.contains("- Ask Priya whether Friday is firm."))
        #expect(prompt.contains("TRANSCRIPT DIGEST"))
        #expect(prompt.contains("The team discussed release timing."))
    }

    @Test("Generated titles discard labels and generic placeholders")
    func sanitizesGeneratedTitles() {
        #expect(GeneratedTitle.sanitized("New Recording: Phone Blocks") == "Phone Blocks")
        #expect(GeneratedTitle.sanitized("TITLE: Inference Runtime Design") == "Inference Runtime Design")
        #expect(GeneratedTitle.sanitized("New Recording") == nil)
    }

    @Test("Parses permissive text generation into a note")
    func parsesGeneratedNote() {
        let response = """
            TITLE: Water Access and Climate Risk
            NOTE:
            ## Main finding

            Water access is becoming less predictable.
            """

        #expect(
            GeneratedNote.parseLabeledResponse(response)
                == GeneratedNote(
                    title: "Water Access and Climate Risk",
                    markdown: "## Main finding\n\nWater access is becoming less predictable."
                )
        )
        let markdownResponse = """
            ## Uberville App

            - A new version of Uberville was discussed.
            - The speaker wanted more time to decide.
            """
        #expect(
            GeneratedNote.parseLabeledResponse(markdownResponse)
                == GeneratedNote(
                    title: "Uberville App",
                    markdown: markdownResponse
                )
        )
        #expect(GeneratedNote.parseLabeledResponse("I cannot help with that.") == nil)
    }
}

@Suite("Command palette")
struct CommandPaletteTests {
    @Test("Note ages use coarse hours and days without minutes")
    func formatsNoteAge() {
        let now = Date(timeIntervalSince1970: 200_000)

        #expect(
            PaletteNoteAge.label(
                updatedAt: now.addingTimeInterval(-45 * 60),
                now: now
            ) == "Now"
        )
        #expect(
            PaletteNoteAge.label(
                updatedAt: now.addingTimeInterval(-5 * 3_600),
                now: now
            ) == "5h"
        )
        #expect(
            PaletteNoteAge.label(
                updatedAt: now.addingTimeInterval(-3 * 24 * 3_600),
                now: now
            ) == "3d"
        )
    }
}
