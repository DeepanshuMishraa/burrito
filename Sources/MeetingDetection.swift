import AppKit
import CoreAudio
import QuartzCore
import SwiftData
import SwiftUI

struct AudioProcessActivity: Equatable, Sendable {
    let bundleIdentifier: String
    let applicationName: String
    let windowTitles: [String]
    let activeWindowTitle: String?
    let isApplicationFrontmost: Bool
    let isUsingMicrophone: Bool
    let isUsingCamera: Bool
    let isPlayingAudio: Bool
}

enum AudioProcessIdentity {
    private static let systemConferenceBundleIdentifierPrefixes = [
        "com.apple.avconferenced",
    ]

    static func bundleIdentifier(
        audioBundleIdentifier: String?,
        runningApplicationBundleIdentifier: String?
    ) -> String? {
        let candidates: [String?] = [
            audioBundleIdentifier,
            runningApplicationBundleIdentifier,
        ]
        for candidate in candidates {
            guard let candidate else { continue }
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    static func belongsToSameApplicationFamily(_ lhs: String, _ rhs: String) -> Bool {
        let lhs = lhs.lowercased()
        let rhs = rhs.lowercased()
        return lhs == rhs
            || lhs.hasPrefix(rhs + ".")
            || rhs.hasPrefix(lhs + ".")
    }

    static func isSystemConferenceService(_ bundleIdentifier: String) -> Bool {
        let bundleIdentifier = bundleIdentifier.lowercased()
        return systemConferenceBundleIdentifierPrefixes.contains {
            bundleIdentifier == $0 || bundleIdentifier.hasPrefix($0 + ".")
        }
    }
}

enum DetectedNoteTakingKind: String, Equatable, Sendable {
    case meeting
    case listenAlong
}

enum NoteTakingDetectionEligibility {
    static let storageKey = "noteTakingDetectionEnabled"

    static var isUserEnabled: Bool {
        UserDefaults.standard.object(forKey: storageKey) as? Bool ?? true
    }

    static func isEnabled(
        userEnabled: Bool = isUserEnabled,
        permissionOnboardingCompleted: Bool,
        permissionsGranted: Bool
    ) -> Bool {
        userEnabled && permissionOnboardingCompleted && permissionsGranted
    }
}

struct DetectedNoteTakingSession: Equatable, Identifiable, Sendable {
    let sourceID: String
    let applicationName: String
    let kind: DetectedNoteTakingKind
    let activityIdentifier: String?

    init(
        sourceID: String,
        applicationName: String,
        kind: DetectedNoteTakingKind,
        activityIdentifier: String? = nil
    ) {
        self.sourceID = sourceID
        self.applicationName = applicationName
        self.kind = kind
        self.activityIdentifier = activityIdentifier
    }

    var id: String {
        [kind.rawValue, sourceID, activityIdentifier]
            .compactMap { $0 }
            .joined(separator: ":")
    }
}

struct NoteTakingSessionStabilizer {
    private let samplesToBegin: Int
    private let samplesToEnd: Int
    private var activeSession: DetectedNoteTakingSession?
    private var candidateSession: DetectedNoteTakingSession?
    private var candidateSampleCount = 0
    private var missingSampleCount = 0

    init(samplesToBegin: Int, samplesToEnd: Int) {
        self.samplesToBegin = max(1, samplesToBegin)
        self.samplesToEnd = max(1, samplesToEnd)
    }

    mutating func update(
        with detectedSession: DetectedNoteTakingSession?
    ) -> DetectedNoteTakingSession? {
        guard let detectedSession else {
            candidateSession = nil
            candidateSampleCount = 0
            guard activeSession != nil else { return nil }
            missingSampleCount += 1
            if missingSampleCount >= samplesToEnd {
                activeSession = nil
                missingSampleCount = 0
            }
            return activeSession
        }

        missingSampleCount = 0
        guard detectedSession != activeSession else {
            candidateSession = nil
            candidateSampleCount = 0
            return activeSession
        }

        if candidateSession == detectedSession {
            candidateSampleCount += 1
        } else {
            candidateSession = detectedSession
            candidateSampleCount = 1
        }
        guard candidateSampleCount >= samplesToBegin else {
            return activeSession
        }

        activeSession = detectedSession
        candidateSession = nil
        candidateSampleCount = 0
        return activeSession
    }

    mutating func reset() {
        activeSession = nil
        candidateSession = nil
        candidateSampleCount = 0
        missingSampleCount = 0
    }
}

@MainActor
final class DetectedRecordingRequestHandler {
    static let shared = DetectedRecordingRequestHandler()

    private var handler: ((RecordingMode) async -> Bool)?

    func configure(_ handler: @escaping (RecordingMode) async -> Bool) {
        self.handler = handler
    }

    @discardableResult
    func startRecording(mode: RecordingMode) async -> Bool {
        guard let handler else { return false }
        return await handler(mode)
    }
}

@MainActor
enum DetectedRecordingLauncher {
    static func start(
        mode: RecordingMode,
        coordinator: AppCoordinator,
        context: ModelContext,
        defaults: UserDefaults = .standard,
        openMainWindow: () -> Void = { MainWindowRouter.shared.open() }
    ) async -> Bool {
        guard coordinator.captureState == .idle else { return false }

        let defaultTemplateID = defaults.string(forKey: "defaultTemplateID")
            ?? BuiltInTemplate.summary.rawValue
        let templates = (try? context.fetch(FetchDescriptor<NoteTemplate>())) ?? []
        let template = RecordingTemplateResolver.snapshot(
            for: mode,
            defaultTemplateID: defaultTemplateID,
            templates: templates
        )
        let languageIdentifier = defaults.string(forKey: "transcriptionLanguage")
            ?? "en-US"
        let retainsAudio = defaults.bool(forKey: "retainAudioDefault")

        await coordinator.start(
            options: RecordingOptions(
                template: template,
                languageIdentifier: languageIdentifier,
                mode: mode,
                retainsAudio: retainsAudio
            ),
            destination: .newNote,
            context: context
        )
        guard coordinator.captureState.isRecording,
              let activeNoteID = coordinator.activeNoteID
        else {
            return false
        }
        NoteSelectionInbox.shared.submit(activeNoteID)
        openMainWindow()
        return true
    }
}

enum NoteTakingSessionClassifier {
    private struct ApplicationFamily {
        let id: String
        let name: String
        let bundleIdentifierPrefixes: [String]
    }

    private static let dedicatedMeetingApplications = [
        ApplicationFamily(
            id: "facetime",
            name: "FaceTime",
            bundleIdentifierPrefixes: ["com.apple.facetime"]
        ),
        ApplicationFamily(
            id: "zoom",
            name: "Zoom",
            bundleIdentifierPrefixes: ["us.zoom.xos"]
        ),
        ApplicationFamily(
            id: "teams",
            name: "Microsoft Teams",
            bundleIdentifierPrefixes: ["com.microsoft.teams", "com.microsoft.teams2"]
        ),
        ApplicationFamily(
            id: "webex",
            name: "Webex",
            bundleIdentifierPrefixes: ["com.cisco.webex", "cisco-systems.spark"]
        ),
        ApplicationFamily(
            id: "slack",
            name: "Slack",
            bundleIdentifierPrefixes: ["com.tinyspeck.slackmacgap"]
        ),
        ApplicationFamily(
            id: "discord",
            name: "Discord",
            bundleIdentifierPrefixes: ["com.hnc.discord"]
        ),
        ApplicationFamily(
            id: "whatsapp",
            name: "WhatsApp",
            bundleIdentifierPrefixes: ["net.whatsapp.whatsapp"]
        ),
        ApplicationFamily(
            id: "telegram",
            name: "Telegram",
            bundleIdentifierPrefixes: ["ru.keepcoder.telegram", "org.telegram.desktop"]
        ),
    ]

    private static let browserApplications = [
        ApplicationFamily(
            id: "safari",
            name: "Safari",
            bundleIdentifierPrefixes: ["com.apple.safari"]
        ),
        ApplicationFamily(
            id: "chrome",
            name: "Google Chrome",
            bundleIdentifierPrefixes: ["com.google.chrome"]
        ),
        ApplicationFamily(
            id: "arc",
            name: "Arc",
            bundleIdentifierPrefixes: ["company.thebrowser.browser"]
        ),
        ApplicationFamily(
            id: "dia",
            name: "Dia",
            bundleIdentifierPrefixes: ["company.thebrowser.dia"]
        ),
        ApplicationFamily(
            id: "edge",
            name: "Microsoft Edge",
            bundleIdentifierPrefixes: ["com.microsoft.edgemac"]
        ),
        ApplicationFamily(
            id: "firefox",
            name: "Firefox",
            bundleIdentifierPrefixes: ["org.mozilla.firefox"]
        ),
        ApplicationFamily(
            id: "brave",
            name: "Brave",
            bundleIdentifierPrefixes: ["com.brave.browser"]
        ),
        ApplicationFamily(
            id: "helium",
            name: "Helium",
            bundleIdentifierPrefixes: ["net.imput.helium"]
        ),
    ]

    private static let mediaApplications = [
        ApplicationFamily(
            id: "quicktime",
            name: "QuickTime Player",
            bundleIdentifierPrefixes: ["com.apple.quicktimeplayerx"]
        ),
        ApplicationFamily(
            id: "tv",
            name: "Apple TV",
            bundleIdentifierPrefixes: ["com.apple.tv"]
        ),
        ApplicationFamily(
            id: "vlc",
            name: "VLC",
            bundleIdentifierPrefixes: ["org.videolan.vlc"]
        ),
        ApplicationFamily(
            id: "iina",
            name: "IINA",
            bundleIdentifierPrefixes: ["com.colliderli.iina"]
        ),
        ApplicationFamily(
            id: "infuse",
            name: "Infuse",
            bundleIdentifierPrefixes: ["com.firecore.infuse"]
        ),
        ApplicationFamily(
            id: "elmedia",
            name: "Elmedia Player",
            bundleIdentifierPrefixes: ["com.eltima.elmedia"]
        ),
        ApplicationFamily(
            id: "mpv",
            name: "mpv",
            bundleIdentifierPrefixes: ["io.mpv", "org.mpv"]
        ),
    ]

    private static let browserMeetingTitleMarkers = [
        "google meet",
        "meet.google.com",
        "microsoft teams",
        "teams.microsoft.com",
        "zoom meeting",
        "app.zoom.us",
        "webex",
        "whereby",
        "jitsi meet",
        "meet.jit.si",
        "slack huddle",
        "discord call",
        "gotomeeting",
        "go to meeting",
        "bluejeans",
        "around video",
        "butter.us",
        "livestorm",
    ]

    private static let browserMediaTitleMarkers = [
        "youtube",
        "vimeo",
        "udemy",
        "coursera",
        "skillshare",
        "linkedin learning",
        "pluralsight",
    ]

    static func detect(
        in processes: [AudioProcessActivity]
    ) -> DetectedNoteTakingSession? {
        if let meeting = detectMeeting(in: processes) {
            return meeting
        }
        return detectMedia(in: processes)
    }

    private static func detectMeeting(
        in processes: [AudioProcessActivity]
    ) -> DetectedNoteTakingSession? {
        for process in processes where process.isUsingMicrophone || process.isUsingCamera {
            let bundleIdentifier = process.bundleIdentifier.lowercased()

            if let application = dedicatedMeetingApplications.first(where: {
                matches(bundleIdentifier, prefixes: $0.bundleIdentifierPrefixes)
            }) {
                return DetectedNoteTakingSession(
                    sourceID: application.id,
                    applicationName: application.name,
                    kind: .meeting
                )
            }

            guard let browser = browserApplications.first(where: {
                matches(bundleIdentifier, prefixes: $0.bundleIdentifierPrefixes)
            }) else {
                continue
            }
            if process.isUsingCamera, !process.isUsingMicrophone {
                guard process.isApplicationFrontmost,
                      let activeWindowTitle = process.activeWindowTitle,
                      hasMeetingWindow([activeWindowTitle])
                else {
                    continue
                }
            }
            if process.isApplicationFrontmost,
               let activeWindowTitle = process.activeWindowTitle,
               hasMediaWindow([activeWindowTitle]),
               !hasMeetingWindow([activeWindowTitle])
            {
                continue
            }
            return DetectedNoteTakingSession(
                sourceID: browser.id,
                applicationName: browser.name,
                kind: .meeting,
                activityIdentifier: process.activeWindowTitle.flatMap { title in
                    hasMeetingWindow([title]) ? activityIdentifier(for: title) : nil
                }
            )
        }

        for process in processes where process.isPlayingAudio {
            let bundleIdentifier = process.bundleIdentifier.lowercased()
            guard let browser = browserApplications.first(where: {
                matches(bundleIdentifier, prefixes: $0.bundleIdentifierPrefixes)
            }), process.isApplicationFrontmost,
                  let activeWindowTitle = process.activeWindowTitle,
                  hasMeetingWindow([activeWindowTitle])
            else {
                continue
            }
            return DetectedNoteTakingSession(
                sourceID: browser.id,
                applicationName: browser.name,
                kind: .meeting,
                activityIdentifier: activityIdentifier(for: activeWindowTitle)
            )
        }

        let systemConferenceMicrophoneIsActive = processes.contains { process in
            process.isUsingMicrophone
                && AudioProcessIdentity.isSystemConferenceService(
                    process.bundleIdentifier
                )
        }
        guard systemConferenceMicrophoneIsActive else { return nil }

        for process in processes where process.isPlayingAudio {
            let bundleIdentifier = process.bundleIdentifier.lowercased()
            guard let application = dedicatedMeetingApplications.first(where: {
                matches(bundleIdentifier, prefixes: $0.bundleIdentifierPrefixes)
            }) else {
                continue
            }
            return DetectedNoteTakingSession(
                sourceID: application.id,
                applicationName: application.name,
                kind: .meeting,
                activityIdentifier: activityIdentifier(
                    for: process.activeWindowTitle ?? process.windowTitles.first
                )
            )
        }

        return nil
    }

    private static func detectMedia(
        in processes: [AudioProcessActivity]
    ) -> DetectedNoteTakingSession? {
        for process in processes where process.isPlayingAudio {
            let bundleIdentifier = process.bundleIdentifier.lowercased()

            if dedicatedMeetingApplications.contains(where: {
                matches(bundleIdentifier, prefixes: $0.bundleIdentifierPrefixes)
            }) {
                continue
            }

            if let browser = browserApplications.first(where: {
                matches(bundleIdentifier, prefixes: $0.bundleIdentifierPrefixes)
            }) {
                // Core Audio cannot identify which browser window produced audio.
                // Use the active window only as session context, never as audio attribution.
                let activeWindowTitle = process.isApplicationFrontmost
                    ? process.activeWindowTitle
                    : nil
                if let activeWindowTitle {
                    guard !hasMeetingWindow([activeWindowTitle]),
                          !process.isUsingMicrophone
                            || hasMediaWindow([activeWindowTitle])
                    else {
                        continue
                    }
                }
                return DetectedNoteTakingSession(
                    sourceID: browser.id,
                    applicationName: browser.name,
                    kind: .listenAlong,
                    activityIdentifier: activityIdentifier(for: activeWindowTitle)
                )
            }

            guard !process.isUsingMicrophone else { continue }
            if let mediaApplication = mediaApplications.first(where: {
                matches(bundleIdentifier, prefixes: $0.bundleIdentifierPrefixes)
            }) {
                return DetectedNoteTakingSession(
                    sourceID: mediaApplication.id,
                    applicationName: mediaApplication.name,
                    kind: .listenAlong,
                    activityIdentifier: activityIdentifier(
                        for: process.activeWindowTitle ?? process.windowTitles.first
                    )
                )
            }
        }

        return nil
    }

    private static func hasMeetingWindow(_ titles: [String]) -> Bool {
        titles.contains { title in
            let normalizedTitle = title.lowercased()
            return browserMeetingTitleMarkers.contains {
                normalizedTitle.contains($0)
            }
        }
    }

    private static func hasMediaWindow(_ titles: [String]) -> Bool {
        titles.contains { title in
            let normalizedTitle = title.lowercased()
            return browserMediaTitleMarkers.contains {
                normalizedTitle.contains($0)
            }
        }
    }

    private static func activityIdentifier(for title: String?) -> String? {
        guard let title else { return nil }
        let normalizedTitle = title
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return normalizedTitle.isEmpty ? nil : normalizedTitle
    }

    private static func matches(_ identifier: String, prefixes: [String]) -> Bool {
        prefixes.contains {
            identifier == $0 || identifier.hasPrefix($0 + ".")
        }
    }
}

private struct AudioWindowSnapshot {
    let processIdentifier: pid_t
    let ownerName: String
    let bundleIdentifier: String?
    let title: String
}

private enum AudioWindowReader {
    static func snapshots() -> [AudioWindowSnapshot] {
        guard let entries = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        return entries.compactMap { entry in
            guard let processNumber = entry[kCGWindowOwnerPID as String] as? NSNumber,
                  let ownerName = entry[kCGWindowOwnerName as String] as? String,
                  let title = entry[kCGWindowName as String] as? String,
                  !title.isEmpty
            else {
                return nil
            }
            return AudioWindowSnapshot(
                processIdentifier: processNumber.int32Value,
                ownerName: ownerName,
                bundleIdentifier: NSRunningApplication(
                    processIdentifier: processNumber.int32Value
                )?.bundleIdentifier,
                title: title
            )
        }
    }
}

private struct CoreAudioProcessActivityReader {
    func processes() -> [AudioProcessActivity] {
        let windows = AudioWindowReader.snapshots()
        let ownBundleIdentifier = Bundle.main.bundleIdentifier
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        let audioProcesses = (try? AudioHardwareSystem.shared.processes) ?? []
        var activities: [AudioProcessActivity] = audioProcesses.compactMap {
            audioProcess -> AudioProcessActivity? in
            let isUsingMicrophone = (try? audioProcess.isRunningInput) ?? false
            let isPlayingAudio = (try? audioProcess.isRunningOutput) ?? false
            guard isUsingMicrophone || isPlayingAudio,
                  let processIdentifier = try? audioProcess.pid
            else {
                return nil
            }

            let application = NSRunningApplication(
                processIdentifier: processIdentifier
            )
            guard let bundleIdentifier = AudioProcessIdentity.bundleIdentifier(
                audioBundleIdentifier: try? audioProcess.bundleID,
                runningApplicationBundleIdentifier: application?.bundleIdentifier
            ),
                  bundleIdentifier != ownBundleIdentifier
            else {
                return nil
            }

            let applicationName = application?.localizedName ?? bundleIdentifier
            let isApplicationFrontmost = Self.isSameApplicationFamily(
                bundleIdentifier: bundleIdentifier,
                applicationName: applicationName,
                as: frontmostApplication
            )
            let relatedTitles = Self.relatedTitles(
                processIdentifier: processIdentifier,
                bundleIdentifier: bundleIdentifier,
                applicationName: applicationName,
                windows: windows
            )

            return AudioProcessActivity(
                bundleIdentifier: bundleIdentifier,
                applicationName: applicationName,
                windowTitles: relatedTitles,
                activeWindowTitle: isApplicationFrontmost ? relatedTitles.first : nil,
                isApplicationFrontmost: isApplicationFrontmost,
                isUsingMicrophone: isUsingMicrophone,
                isUsingCamera: false,
                isPlayingAudio: isPlayingAudio
            )
        }

        let systemConferenceMicrophoneIsActive = activities.contains { activity in
            activity.isUsingMicrophone
                && AudioProcessIdentity.isSystemConferenceService(
                    activity.bundleIdentifier
                )
        }
        guard systemConferenceMicrophoneIsActive,
              let frontmostApplication,
              let frontmostBundleIdentifier = frontmostApplication.bundleIdentifier,
              frontmostBundleIdentifier != ownBundleIdentifier,
              !activities.contains(where: {
                  AudioProcessIdentity.belongsToSameApplicationFamily(
                    $0.bundleIdentifier,
                    frontmostBundleIdentifier
                  )
              })
        else {
            return activities
        }

        let applicationName = frontmostApplication.localizedName
            ?? frontmostBundleIdentifier
        let relatedTitles = Self.relatedTitles(
            processIdentifier: frontmostApplication.processIdentifier,
            bundleIdentifier: frontmostBundleIdentifier,
            applicationName: applicationName,
            windows: windows
        )
        activities.append(
            AudioProcessActivity(
                bundleIdentifier: frontmostBundleIdentifier,
                applicationName: applicationName,
                windowTitles: relatedTitles,
                activeWindowTitle: relatedTitles.first,
                isApplicationFrontmost: true,
                isUsingMicrophone: systemConferenceMicrophoneIsActive,
                isUsingCamera: false,
                isPlayingAudio: false
            )
        )
        return activities
    }

    private static func relatedTitles(
        processIdentifier: pid_t,
        bundleIdentifier: String,
        applicationName: String,
        windows: [AudioWindowSnapshot]
    ) -> [String] {
        let normalizedApplicationName = normalize(applicationName)
        return windows.compactMap { window in
            if window.processIdentifier == processIdentifier {
                return window.title
            }
            if let windowBundleIdentifier = window.bundleIdentifier,
               AudioProcessIdentity.belongsToSameApplicationFamily(
                bundleIdentifier,
                windowBundleIdentifier
               )
            {
                return window.title
            }
            let normalizedOwnerName = normalize(window.ownerName)
            guard normalizedApplicationName.hasPrefix(normalizedOwnerName)
                || normalizedOwnerName.hasPrefix(normalizedApplicationName)
            else {
                return nil
            }
            return window.title
        }
    }

    private static func isSameApplicationFamily(
        bundleIdentifier: String,
        applicationName: String,
        as application: NSRunningApplication?
    ) -> Bool {
        guard let application else { return false }

        if let frontmostBundleIdentifier = application.bundleIdentifier,
           AudioProcessIdentity.belongsToSameApplicationFamily(
            bundleIdentifier,
            frontmostBundleIdentifier
           )
        {
            return true
        }

        let normalizedName = normalize(applicationName)
        let normalizedFrontmostName = normalize(
            application.localizedName ?? application.bundleIdentifier ?? ""
        )
        guard !normalizedName.isEmpty, !normalizedFrontmostName.isEmpty else {
            return false
        }
        return normalizedName.hasPrefix(normalizedFrontmostName)
            || normalizedFrontmostName.hasPrefix(normalizedName)
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

}

@MainActor
final class NoteTakingDetectionController {
    static let shared = NoteTakingDetectionController()

    private static let pollInterval = Duration.seconds(1)
    private static let presentationDuration = Duration.seconds(10)

    private let prompt = NoteTakingPromptPanelController()
    private weak var coordinator: AppCoordinator?
    private var monitoringTask: Task<Void, Never>?
    private var autoDismissTask: Task<Void, Never>?
    private var stabilizer = NoteTakingSessionStabilizer(
        samplesToBegin: 2,
        samplesToEnd: 3
    )
    private var currentSession: DetectedNoteTakingSession?
    private var presentedSessionID: String?
    private var dismissedSessionID: String?

    private init() {}

    func configure(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    func setEnabled(_ isEnabled: Bool) {
        if isEnabled {
            start()
        } else {
            stop()
        }
    }

    func start() {
        guard monitoringTask == nil else { return }
        monitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                guard NoteTakingDetectionEligibility.isUserEnabled else {
                    self?.suppressPrompt()
                    try? await Task.sleep(for: Self.pollInterval)
                    continue
                }
                let processes = await Task.detached(priority: .utility) {
                    CoreAudioProcessActivityReader().processes()
                }.value
                guard !Task.isCancelled else { return }
                self?.refresh(processes: processes)
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    func stop() {
        monitoringTask?.cancel()
        autoDismissTask?.cancel()
        monitoringTask = nil
        autoDismissTask = nil
        resetSession()
        prompt.hide(animated: false)
    }

    private func refresh(processes: [AudioProcessActivity]) {
        guard NoteTakingDetectionEligibility.isUserEnabled else {
            if currentSession != nil || presentedSessionID != nil {
                resetSession()
                prompt.hide(animated: false)
            }
            return
        }
        let classifiedSession = NoteTakingSessionClassifier.detect(in: processes)
        guard let detectedSession = stabilizer.update(with: classifiedSession) else {
            if currentSession != nil {
                resetSession()
                prompt.hide()
            }
            return
        }

        if currentSession?.id != detectedSession.id {
            autoDismissTask?.cancel()
            currentSession = detectedSession
            presentedSessionID = nil
            dismissedSessionID = nil
        }

        guard coordinator?.captureState == .idle else {
            autoDismissTask?.cancel()
            autoDismissTask = nil
            presentedSessionID = nil
            prompt.hide()
            return
        }

        guard dismissedSessionID != detectedSession.id,
              presentedSessionID != detectedSession.id
        else {
            return
        }

        presentedSessionID = detectedSession.id
        prompt.show(
            session: detectedSession,
            start: { [weak self] in self?.startNoteTaking() },
            dismiss: { [weak self] in self?.dismissCurrentSession() }
        )
        scheduleAutoDismiss(for: detectedSession.id)
    }

    private func scheduleAutoDismiss(for sessionID: String) {
        autoDismissTask?.cancel()
        autoDismissTask = Task { [weak self] in
            try? await Task.sleep(for: Self.presentationDuration)
            guard !Task.isCancelled,
                  self?.currentSession?.id == sessionID,
                  self?.presentedSessionID == sessionID
            else {
                return
            }
            self?.dismissCurrentSession()
        }
    }

    private func startNoteTaking() {
        guard let kind = currentSession?.kind else { return }
        let mode: RecordingMode = switch kind {
        case .meeting:
            .meeting
        case .listenAlong:
            .listenAlong
        }
        Task { [weak self] in
            guard await DetectedRecordingRequestHandler.shared.startRecording(mode: mode) else {
                return
            }
            self?.dismissCurrentSession()
        }
    }

    private func dismissCurrentSession() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        dismissedSessionID = currentSession?.id
        presentedSessionID = nil
        prompt.hide()
    }

    private func suppressPrompt() {
        guard currentSession != nil || presentedSessionID != nil else { return }
        resetSession()
        prompt.hide(animated: false)
    }

    private func resetSession() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        stabilizer.reset()
        currentSession = nil
        presentedSessionID = nil
        dismissedSessionID = nil
    }
}

@MainActor
private final class NoteTakingPromptPanelController {
    private let panel: NoteTakingPromptPanel
    private var presentedSessionID: String?
    private var generation = 0

    init() {
        panel = NoteTakingPromptPanel(
            contentRect: NSRect(x: 0, y: 0, width: 452, height: 88),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle,
        ]
        panel.animationBehavior = .none
    }

    func show(
        session: DetectedNoteTakingSession,
        start: @escaping () -> Void,
        dismiss: @escaping () -> Void
    ) {
        guard presentedSessionID != session.id || !panel.isVisible else { return }
        generation &+= 1
        presentedSessionID = session.id
        panel.contentView = NSHostingView(
            rootView: NoteTakingPromptView(
                session: session,
                start: start,
                dismiss: dismiss
            )
            .environment(BurritoStyleStore.shared)
        )

        let targetFrame = frameOnActiveScreen()
        let reducesMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = reducesMotion ? 1 : 0
        panel.setFrame(
            targetFrame.offsetBy(dx: 0, dy: reducesMotion ? 0 : -10),
            display: false
        )
        panel.orderFrontRegardless()

        guard !reducesMotion else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrameOrigin(targetFrame.origin)
        }
    }

    func hide(animated: Bool = true) {
        guard panel.isVisible else {
            presentedSessionID = nil
            return
        }
        presentedSessionID = nil
        let shouldAnimate = animated
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard shouldAnimate else {
            panel.orderOut(nil)
            panel.alphaValue = 1
            return
        }

        let restingOrigin = panel.frame.origin
        let hiddenOrigin = NSPoint(x: restingOrigin.x, y: restingOrigin.y - 6)
        let hideGeneration = generation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
            panel.animator().setFrameOrigin(hiddenOrigin)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard self?.generation == hideGeneration else { return }
                self?.panel.orderOut(nil)
                self?.panel.alphaValue = 1
            }
        }
    }

    private func frameOnActiveScreen() -> NSRect {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? .zero
        let panelSize = panel.frame.size
        return NSRect(
            x: visibleFrame.midX - (panelSize.width / 2),
            y: visibleFrame.minY + 20,
            width: panelSize.width,
            height: panelSize.height
        )
    }
}

private final class NoteTakingPromptPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct NoteTakingPromptView: View {
    @Environment(BurritoStyleStore.self) private var styleStore
    @Environment(\.accessibilityReduceTransparency) private var reducesTransparency

    let session: DetectedNoteTakingSession
    let start: () -> Void
    let dismiss: () -> Void

    private var title: String {
        switch session.kind {
        case .meeting: "Take notes for this meeting?"
        case .listenAlong: "Take notes while you listen?"
        }
    }

    private var subtitle: String {
        switch session.kind {
        case .meeting: "Microphone or call audio is active in \(session.applicationName)"
        case .listenAlong: "Media is playing in \(session.applicationName)"
        }
    }

    private var symbol: String {
        switch session.kind {
        case .meeting: "person.wave.2.fill"
        case .listenAlong: "waveform"
        }
    }

    private var actionTitle: String {
        "Start"
    }

    private var actionHint: String {
        switch session.kind {
        case .meeting: "Starts a new recording in Meeting mode"
        case .listenAlong: "Starts a new recording in Listen Along mode"
        }
    }

    var body: some View {
        ZStack {
            let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
            if reducesTransparency {
                shape.fill(BurritoTheme.raised)
            } else {
                shape.fill(.regularMaterial)
            }

            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(BurritoTheme.accent)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.burritoUI(size: 13, weight: 620, relativeTo: .headline))
                        .foregroundStyle(BurritoTheme.foreground)
                    Text(subtitle)
                        .font(.burritoUI(size: 11, weight: .regular, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Button(action: start) {
                    Label(actionTitle, systemImage: "record.circle")
                        .font(.burritoUI(size: 12, weight: 620, relativeTo: .callout))
                        .padding(.horizontal, 2)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 8))
                .controlSize(.large)
                .tint(BurritoTheme.accent)
                .keyboardShortcut(.defaultAction)
                .accessibilityHint(actionHint)

                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Not now")
                .accessibilityLabel("Dismiss note-taking prompt")
            }
            .padding(.horizontal, 14)
        }
        .frame(width: 436, height: 72)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.primary.opacity(0.10), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
        .padding(8)
        .preferredColorScheme(styleStore.colorScheme)
        .font(.burritoUI(size: 13, weight: .regular))
        .id(
            "\(styleStore.theme.rawValue)-\(styleStore.font.rawValue)-\(styleStore.interfaceFontSize)"
        )
    }
}
