import Testing
@testable import Burrito

@Suite("Note-taking detection")
struct MeetingDetectionTests {
    @Test("Uses Core Audio identity for unregistered helper processes")
    func resolvesUnregisteredAudioHelperIdentity() {
        #expect(
            AudioProcessIdentity.bundleIdentifier(
                audioBundleIdentifier: "net.imput.helium.helper",
                runningApplicationBundleIdentifier: nil
            ) == "net.imput.helium.helper"
        )
        #expect(
            AudioProcessIdentity.belongsToSameApplicationFamily(
                "net.imput.helium.helper",
                "net.imput.helium"
            )
        )
    }

    @Test("Detection requires completed onboarding and all permissions")
    func requiresOnboardingAndPermissions() {
        #expect(
            !NoteTakingDetectionEligibility.isEnabled(
                userEnabled: true,
                permissionOnboardingCompleted: false,
                permissionsGranted: true
            )
        )
        #expect(
            !NoteTakingDetectionEligibility.isEnabled(
                userEnabled: true,
                permissionOnboardingCompleted: true,
                permissionsGranted: false
            )
        )
        #expect(
            NoteTakingDetectionEligibility.isEnabled(
                userEnabled: true,
                permissionOnboardingCompleted: true,
                permissionsGranted: true
            )
        )
    }

    @Test("User toggle can disable detection")
    func userToggleDisablesDetection() {
        #expect(
            !NoteTakingDetectionEligibility.isEnabled(
                userEnabled: false,
                permissionOnboardingCompleted: true,
                permissionsGranted: true
            )
        )
        #expect(
            NoteTakingDetectionEligibility.isEnabled(
                userEnabled: true,
                permissionOnboardingCompleted: true,
                permissionsGranted: true
            )
        )
    }

    @Test("Detects a dedicated meeting app using the microphone")
    func detectsDedicatedMeetingApp() {
        let detected = NoteTakingSessionClassifier.detect(in: [
            process(
                bundleIdentifier: "us.zoom.xos",
                applicationName: "zoom.us",
                isUsingMicrophone: true,
                isPlayingAudio: true
            ),
        ])

        #expect(
            detected == DetectedNoteTakingSession(
                sourceID: "zoom",
                applicationName: "Zoom",
                kind: .meeting
            )
        )
    }

    @Test("Detects a frontmost dedicated meeting app using the camera")
    func detectsDedicatedMeetingAppCamera() {
        let detected = NoteTakingSessionClassifier.detect(in: [
            process(
                bundleIdentifier: "net.whatsapp.WhatsApp",
                applicationName: "WhatsApp",
                isUsingCamera: true
            ),
        ])

        #expect(detected?.kind == .meeting)
        #expect(detected?.applicationName == "WhatsApp")
    }

    @Test("Meeting detection wins over simultaneous media playback")
    func prioritizesMeetingDetection() {
        let detected = NoteTakingSessionClassifier.detect(in: [
            process(
                bundleIdentifier: "com.apple.Safari",
                applicationName: "Safari",
                windowTitles: ["Course lesson"],
                isPlayingAudio: true
            ),
            process(
                bundleIdentifier: "com.microsoft.teams2",
                applicationName: "Microsoft Teams",
                isUsingMicrophone: true,
                isPlayingAudio: true
            ),
        ])

        #expect(detected?.kind == .meeting)
        #expect(detected?.applicationName == "Microsoft Teams")
    }

    @Test("Detects a browser meeting tab using the microphone")
    func detectsBrowserMeetingTab() {
        let detected = NoteTakingSessionClassifier.detect(in: [
            process(
                bundleIdentifier: "com.google.Chrome.helper.renderer",
                applicationName: "Google Chrome Helper (Renderer)",
                windowTitles: ["Product sync — Google Meet"],
                isUsingMicrophone: true,
                isPlayingAudio: true
            ),
        ])

        #expect(detected?.kind == .meeting)
        #expect(detected?.applicationName == "Google Chrome")
    }

    @Test("Treats an unrecognized browser room using the microphone as a meeting")
    func detectsUnrecognizedBrowserCall() {
        let detected = NoteTakingSessionClassifier.detect(in: [
            process(
                bundleIdentifier: "com.apple.Safari",
                applicationName: "Safari",
                windowTitles: ["Customer room"],
                isUsingMicrophone: true,
                isPlayingAudio: true
            ),
        ])

        #expect(detected?.kind == .meeting)
        #expect(detected?.applicationName == "Safari")
    }

    @Test("Detects a muted meeting website from its active call audio")
    func detectsMutedBrowserMeeting() {
        let detected = NoteTakingSessionClassifier.detect(in: [
            process(
                bundleIdentifier: "company.thebrowser.dia.helper",
                applicationName: "Dia Helper",
                windowTitles: ["Design review — Google Meet"],
                isPlayingAudio: true
            ),
        ])

        #expect(detected?.kind == .meeting)
        #expect(detected?.applicationName == "Dia")
    }

    @Test("Detects a meeting website using the camera")
    func detectsBrowserMeetingCamera() {
        let detected = NoteTakingSessionClassifier.detect(in: [
            process(
                bundleIdentifier: "company.thebrowser.dia",
                applicationName: "Dia",
                windowTitles: ["Design review — Google Meet"],
                isUsingCamera: true
            ),
        ])

        #expect(detected?.kind == .meeting)
        #expect(detected?.applicationName == "Dia")
    }

    @Test("Does not attribute global camera use to an unknown browser page")
    func ignoresUnattributedBrowserCamera() {
        let detected = NoteTakingSessionClassifier.detect(in: [
            process(
                bundleIdentifier: "com.apple.Safari",
                applicationName: "Safari",
                windowTitles: ["Documentation"],
                isUsingCamera: true
            ),
        ])

        #expect(detected == nil)
    }

    @Test("Classifies meeting website audio as a meeting")
    func classifiesMeetingWebsiteAudio() {
        let detected = NoteTakingSessionClassifier.detect(in: [
            process(
                bundleIdentifier: "com.apple.Safari",
                applicationName: "Safari",
                windowTitles: ["Weekly review | Microsoft Teams"],
                isUsingMicrophone: false,
                isPlayingAudio: true
            ),
        ])

        #expect(detected?.kind == .meeting)
        #expect(detected?.applicationName == "Safari")
    }

    @Test("Uses the active meeting window when a browser has mixed windows")
    func usesActiveMeetingWindow() {
        let detected = NoteTakingSessionClassifier.detect(in: [
            process(
                bundleIdentifier: "com.google.Chrome.helper",
                applicationName: "Google Chrome Helper",
                windowTitles: [
                    "Weekly review — Google Meet",
                    "Swift concurrency tutorial — YouTube",
                ],
                isPlayingAudio: true
            ),
        ])

        #expect(detected?.kind == .meeting)
    }

    @Test("Detects background browser playback without guessing its tab")
    func detectsBackgroundBrowserPlaybackWithoutGuessingItsTab() {
        let detected = NoteTakingSessionClassifier.detect(in: [
            process(
                bundleIdentifier: "com.google.Chrome.helper",
                applicationName: "Google Chrome Helper",
                windowTitles: ["Swift concurrency tutorial — YouTube"],
                isApplicationFrontmost: false,
                isPlayingAudio: true
            ),
        ])

        #expect(
            detected == DetectedNoteTakingSession(
                sourceID: "chrome",
                applicationName: "Google Chrome",
                kind: .listenAlong
            )
        )
    }

    @Test("Detects browser media playback for Listen Along")
    func detectsBrowserMediaPlayback() {
        let detected = NoteTakingSessionClassifier.detect(in: [
            process(
                bundleIdentifier: "com.google.Chrome.helper",
                applicationName: "Google Chrome Helper",
                windowTitles: ["Swift concurrency tutorial — YouTube"],
                isPlayingAudio: true
            ),
        ])

        #expect(
            detected == DetectedNoteTakingSession(
                sourceID: "chrome",
                applicationName: "Google Chrome",
                kind: .listenAlong,
                activityIdentifier: "swift concurrency tutorial — youtube"
            )
        )
    }

    @Test("Detects Helium helper media playback")
    func detectsHeliumMediaPlayback() {
        let detected = NoteTakingSessionClassifier.detect(in: [
            process(
                bundleIdentifier: "net.imput.helium.helper",
                applicationName: "Helium Helper",
                windowTitles: ["Swift concurrency tutorial — YouTube"],
                isPlayingAudio: true
            ),
        ])

        #expect(
            detected == DetectedNoteTakingSession(
                sourceID: "helium",
                applicationName: "Helium",
                kind: .listenAlong,
                activityIdentifier: "swift concurrency tutorial — youtube"
            )
        )
    }

    @Test("Detects Google Meet in Helium")
    func detectsHeliumMeeting() {
        let detected = NoteTakingSessionClassifier.detect(in: [
            process(
                bundleIdentifier: "net.imput.helium.helper",
                applicationName: "Helium Helper",
                windowTitles: ["Daily sync — Google Meet"],
                isUsingMicrophone: true,
                isPlayingAudio: true
            ),
        ])

        #expect(
            detected == DetectedNoteTakingSession(
                sourceID: "helium",
                applicationName: "Helium",
                kind: .meeting,
                activityIdentifier: "daily sync — google meet"
            )
        )
    }

    @Test("An active YouTube video is Listen Along despite a stale Meet window")
    func activeMediaWindowOverridesStaleMeetingWindow() {
        let detected = NoteTakingSessionClassifier.detect(in: [
            process(
                bundleIdentifier: "net.imput.helium.helper",
                applicationName: "Helium Helper",
                windowTitles: [
                    "Daily sync — Google Meet",
                    "Swift concurrency tutorial — YouTube",
                ],
                activeWindowTitle: "Swift concurrency tutorial — YouTube",
                isUsingMicrophone: true,
                isPlayingAudio: true
            ),
        ])

        #expect(detected?.kind == .listenAlong)
    }

    @Test("WhatsApp calls routed through macOS conferencing are meetings")
    func detectsSystemRoutedWhatsAppCall() {
        let detected = NoteTakingSessionClassifier.detect(in: [
            process(
                bundleIdentifier: "com.apple.avconferenced",
                applicationName: "avconferenced",
                isUsingMicrophone: true,
                isPlayingAudio: true
            ),
            process(
                bundleIdentifier: "net.whatsapp.WhatsApp",
                applicationName: "WhatsApp",
                isPlayingAudio: true
            ),
        ])

        #expect(detected?.kind == .meeting)
        #expect(detected?.applicationName == "WhatsApp")
    }

    @Test("Different browser media titles create different prompt sessions")
    func mediaTitlesCreateDistinctSessions() {
        let first = NoteTakingSessionClassifier.detect(in: [
            process(
                bundleIdentifier: "net.imput.helium.helper",
                applicationName: "Helium Helper",
                windowTitles: ["First lesson — YouTube"],
                isPlayingAudio: true
            ),
        ])
        let second = NoteTakingSessionClassifier.detect(in: [
            process(
                bundleIdentifier: "net.imput.helium.helper",
                applicationName: "Helium Helper",
                windowTitles: ["Second lesson — YouTube"],
                isPlayingAudio: true
            ),
        ])

        #expect(first?.id != second?.id)
    }

    @Test("Treats microphone-active unknown browser audio as a meeting")
    func classifiesMicrophoneActiveBrowserAudio() {
        let detected = NoteTakingSessionClassifier.detect(in: [
            process(
                bundleIdentifier: "com.google.Chrome.helper",
                applicationName: "Google Chrome Helper",
                windowTitles: ["Unrecognized call room"],
                isUsingMicrophone: true,
                isPlayingAudio: true
            ),
        ])

        #expect(detected?.kind == .meeting)
    }

    @Test("Detects an unrecognized microphone-active browser without playback")
    func detectsUnrecognizedMicrophoneSiteWithoutPlayback() {
        let detected = NoteTakingSessionClassifier.detect(in: [
            process(
                bundleIdentifier: "com.apple.Safari",
                applicationName: "Safari",
                windowTitles: ["Unrecognized call room"],
                isUsingMicrophone: true
            ),
        ])

        #expect(detected?.kind == .meeting)
        #expect(detected?.applicationName == "Safari")
    }

    @Test("Detects supported local video players for Listen Along")
    func detectsLocalMediaPlayer() {
        let detected = NoteTakingSessionClassifier.detect(in: [
            process(
                bundleIdentifier: "org.videolan.vlc",
                applicationName: "VLC",
                isPlayingAudio: true
            ),
        ])

        #expect(detected?.kind == .listenAlong)
        #expect(detected?.applicationName == "VLC")
    }

    @Test("Ignores a supported player while it is paused")
    func ignoresPausedMediaPlayer() {
        let detected = NoteTakingSessionClassifier.detect(in: [
            process(
                bundleIdentifier: "com.apple.QuickTimePlayerX",
                applicationName: "QuickTime Player"
            ),
        ])

        #expect(detected == nil)
    }

    @Test("Ignores unsupported audio applications")
    func ignoresUnsupportedAudioApplication() {
        let detected = NoteTakingSessionClassifier.detect(in: [
            process(
                bundleIdentifier: "com.spotify.client",
                applicationName: "Spotify",
                isPlayingAudio: true
            ),
        ])

        #expect(detected == nil)
    }

    @Test("Ignores an idle meeting app")
    func ignoresIdleMeetingApp() {
        let detected = NoteTakingSessionClassifier.detect(in: [
            process(
                bundleIdentifier: "com.microsoft.teams2",
                applicationName: "Microsoft Teams"
            ),
        ])

        #expect(detected == nil)
    }

    private func process(
        bundleIdentifier: String,
        applicationName: String,
        windowTitles: [String] = [],
        activeWindowTitle: String? = nil,
        isApplicationFrontmost: Bool = true,
        isUsingMicrophone: Bool = false,
        isUsingCamera: Bool = false,
        isPlayingAudio: Bool = false
    ) -> AudioProcessActivity {
        AudioProcessActivity(
            bundleIdentifier: bundleIdentifier,
            applicationName: applicationName,
            windowTitles: windowTitles,
            activeWindowTitle: activeWindowTitle ?? windowTitles.first,
            isApplicationFrontmost: isApplicationFrontmost,
            isUsingMicrophone: isUsingMicrophone,
            isUsingCamera: isUsingCamera,
            isPlayingAudio: isPlayingAudio
        )
    }
}

@Suite("Note-taking detection stability")
struct NoteTakingDetectionStabilityTests {
    private let meeting = DetectedNoteTakingSession(
        sourceID: "zoom",
        applicationName: "Zoom",
        kind: .meeting
    )

    @Test("Requires a stable signal before beginning a session")
    func requiresStableStart() {
        var stabilizer = NoteTakingSessionStabilizer(
            samplesToBegin: 2,
            samplesToEnd: 3
        )

        #expect(stabilizer.update(with: meeting) == nil)
        #expect(stabilizer.update(with: meeting) == meeting)
    }

    @Test("Keeps a session through brief missing samples")
    func toleratesBriefDropout() {
        var stabilizer = NoteTakingSessionStabilizer(
            samplesToBegin: 2,
            samplesToEnd: 3
        )
        _ = stabilizer.update(with: meeting)
        _ = stabilizer.update(with: meeting)

        #expect(stabilizer.update(with: nil) == meeting)
        #expect(stabilizer.update(with: nil) == meeting)
        #expect(stabilizer.update(with: nil) == nil)
    }

    @Test("A changed signal must stabilize before replacing the active session")
    func stabilizesSessionChanges() {
        let media = DetectedNoteTakingSession(
            sourceID: "safari",
            applicationName: "Safari",
            kind: .listenAlong
        )
        var stabilizer = NoteTakingSessionStabilizer(
            samplesToBegin: 2,
            samplesToEnd: 3
        )
        _ = stabilizer.update(with: meeting)
        _ = stabilizer.update(with: meeting)

        #expect(stabilizer.update(with: media) == meeting)
        #expect(stabilizer.update(with: media) == media)
    }
}

@Suite("Detected recording routing")
@MainActor
struct DetectedRecordingRequestHandlerTests {
    @Test("Routes recording requests without a window subscriber")
    func routesRecordingRequest() async {
        let handler = DetectedRecordingRequestHandler()
        var receivedModes: [RecordingMode] = []
        handler.configure {
            receivedModes.append($0)
            return true
        }

        let accepted = await handler.startRecording(mode: .listenAlong)

        #expect(accepted)
        #expect(receivedModes == [.listenAlong])
    }

    @Test("Keeps the prompt actionable until a recording handler exists")
    func rejectsUnconfiguredRequest() async {
        let handler = DetectedRecordingRequestHandler()

        #expect(!(await handler.startRecording(mode: .meeting)))
    }

    @Test("Keeps the prompt actionable when recording launch is rejected")
    func propagatesRejectedLaunch() async {
        let handler = DetectedRecordingRequestHandler()
        handler.configure { _ in false }

        #expect(!(await handler.startRecording(mode: .meeting)))
    }
}
