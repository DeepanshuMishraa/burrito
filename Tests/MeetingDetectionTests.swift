import Testing
@testable import Burrito

@Suite("Note-taking detection")
struct MeetingDetectionTests {
    @Test("Detection requires completed onboarding and all permissions")
    func requiresOnboardingAndPermissions() {
        #expect(
            !NoteTakingDetectionEligibility.isEnabled(
                permissionOnboardingCompleted: false,
                permissionsGranted: true
            )
        )
        #expect(
            !NoteTakingDetectionEligibility.isEnabled(
                permissionOnboardingCompleted: true,
                permissionsGranted: false
            )
        )
        #expect(
            NoteTakingDetectionEligibility.isEnabled(
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

    @Test("Excludes meeting websites from Listen Along detection")
    func excludesMeetingWebsiteAudio() {
        let detected = NoteTakingSessionClassifier.detect(in: [
            process(
                bundleIdentifier: "com.apple.Safari",
                applicationName: "Safari",
                windowTitles: ["Weekly review | Microsoft Teams"],
                isUsingMicrophone: false,
                isPlayingAudio: true
            ),
        ])

        #expect(detected == nil)
    }

    @Test("A separate meeting window does not suppress browser media playback")
    func allowsMediaAlongsideMeetingWindow() {
        let detected = NoteTakingSessionClassifier.detect(in: [
            process(
                bundleIdentifier: "com.google.Chrome.helper",
                applicationName: "Google Chrome Helper",
                windowTitles: [
                    "Weekly review — Google Meet",
                    "Swift concurrency tutorial — YouTube",
                ],
                foregroundWindowTitle: "Swift concurrency tutorial — YouTube",
                isPlayingAudio: true
            ),
        ])

        #expect(detected?.kind == .listenAlong)
        #expect(detected?.applicationName == "Google Chrome")
    }

    @Test("A background browser window cannot drive media classification")
    func ignoresBackgroundBrowserWindow() {
        let detected = NoteTakingSessionClassifier.detect(in: [
            process(
                bundleIdentifier: "com.google.Chrome.helper",
                applicationName: "Google Chrome Helper",
                windowTitles: [
                    "Swift concurrency tutorial — YouTube",
                    "Weekly review — Google Meet",
                ],
                foregroundWindowTitle: "Swift concurrency tutorial — YouTube",
                isApplicationFrontmost: false,
                isPlayingAudio: true
            ),
        ])

        #expect(detected == nil)
    }

    @Test("A foreground meeting window suppresses other browser media windows")
    func suppressesMediaBehindForegroundMeetingWindow() {
        let detected = NoteTakingSessionClassifier.detect(in: [
            process(
                bundleIdentifier: "com.google.Chrome.helper",
                applicationName: "Google Chrome Helper",
                windowTitles: [
                    "Weekly review — Google Meet",
                    "Swift concurrency tutorial — YouTube",
                ],
                foregroundWindowTitle: "Weekly review — Google Meet",
                isPlayingAudio: true
            ),
        ])

        #expect(detected == nil)
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
                kind: .listenAlong
            )
        )
    }

    @Test("Does not treat microphone-active browser audio as media playback")
    func ignoresMicrophoneActiveBrowserAudio() {
        let detected = NoteTakingSessionClassifier.detect(in: [
            process(
                bundleIdentifier: "com.google.Chrome.helper",
                applicationName: "Google Chrome Helper",
                windowTitles: ["Unrecognized call room"],
                isUsingMicrophone: true,
                isPlayingAudio: true
            ),
        ])

        #expect(detected == nil)
    }

    @Test("Ignores an unrecognized microphone-active browser without playback")
    func ignoresUnrecognizedMicrophoneSiteWithoutPlayback() {
        let detected = NoteTakingSessionClassifier.detect(in: [
            process(
                bundleIdentifier: "com.apple.Safari",
                applicationName: "Safari",
                windowTitles: ["Unrecognized call room"],
                isUsingMicrophone: true
            ),
        ])

        #expect(detected == nil)
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
        foregroundWindowTitle: String? = nil,
        isApplicationFrontmost: Bool = true,
        isUsingMicrophone: Bool = false,
        isPlayingAudio: Bool = false
    ) -> AudioProcessActivity {
        AudioProcessActivity(
            bundleIdentifier: bundleIdentifier,
            applicationName: applicationName,
            windowTitles: windowTitles,
            foregroundWindowTitle: foregroundWindowTitle ?? windowTitles.first,
            isApplicationFrontmost: isApplicationFrontmost,
            isUsingMicrophone: isUsingMicrophone,
            isPlayingAudio: isPlayingAudio
        )
    }
}

@Suite("Detected recording routing")
@MainActor
struct DetectedRecordingRequestHandlerTests {
    @Test("Routes recording requests without a window subscriber")
    func routesRecordingRequest() {
        let handler = DetectedRecordingRequestHandler()
        var receivedModes: [RecordingMode] = []
        handler.configure { receivedModes.append($0) }

        let accepted = handler.startRecording(mode: .listenAlong)

        #expect(accepted)
        #expect(receivedModes == [.listenAlong])
    }

    @Test("Keeps the prompt actionable until a recording handler exists")
    func rejectsUnconfiguredRequest() {
        let handler = DetectedRecordingRequestHandler()

        #expect(!handler.startRecording(mode: .meeting))
    }
}
