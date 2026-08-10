import AppKit
import CoreAudio
import QuartzCore
import SwiftData
import SwiftUI

struct AudioProcessActivity: Equatable, Sendable {
    let bundleIdentifier: String
    let applicationName: String
    let windowTitles: [String]
    let isApplicationFrontmost: Bool
    let isUsingMicrophone: Bool
    let isPlayingAudio: Bool
}

enum AudioProcessIdentity {
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
}

enum DetectedNoteTakingKind: String, Equatable, Sendable {
    case meeting
    case listenAlong
}

enum NoteTakingDetectionEligibility {
    static func isEnabled(
        permissionOnboardingCompleted: Bool,
        permissionsGranted: Bool
    ) -> Bool {
        permissionOnboardingCompleted && permissionsGranted
    }
}

struct DetectedNoteTakingSession: Equatable, Identifiable, Sendable {
    let sourceID: String
    let applicationName: String
    let kind: DetectedNoteTakingKind

    var id: String { "\(kind.rawValue):\(sourceID)" }
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
        for process in processes where process.isUsingMicrophone {
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
            }), hasMeetingWindow(process.windowTitles) else {
                continue
            }
            return DetectedNoteTakingSession(
                sourceID: browser.id,
                applicationName: browser.name,
                kind: .meeting
            )
        }

        return nil
    }

    private static func detectMedia(
        in processes: [AudioProcessActivity]
    ) -> DetectedNoteTakingSession? {
        for process in processes where process.isPlayingAudio && !process.isUsingMicrophone {
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
                // Avoid guessing when any related window may be a meeting.
                guard process.isApplicationFrontmost,
                      !process.windowTitles.isEmpty,
                      !hasMeetingWindow(process.windowTitles)
                else {
                    continue
                }
                return DetectedNoteTakingSession(
                    sourceID: browser.id,
                    applicationName: browser.name,
                    kind: .listenAlong
                )
            }

            if let mediaApplication = mediaApplications.first(where: {
                matches(bundleIdentifier, prefixes: $0.bundleIdentifierPrefixes)
            }) {
                return DetectedNoteTakingSession(
                    sourceID: mediaApplication.id,
                    applicationName: mediaApplication.name,
                    kind: .listenAlong
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
        return audioProcesses.compactMap { audioProcess in
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
            let normalizedApplicationName = Self.normalize(applicationName)
            let isApplicationFrontmost = Self.isSameApplicationFamily(
                bundleIdentifier: bundleIdentifier,
                applicationName: applicationName,
                as: frontmostApplication
            )
            let relatedTitles = windows.compactMap { window -> String? in
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
                let normalizedOwnerName = Self.normalize(window.ownerName)
                guard normalizedApplicationName.hasPrefix(normalizedOwnerName)
                    || normalizedOwnerName.hasPrefix(normalizedApplicationName)
                else {
                    return nil
                }
                return window.title
            }

            return AudioProcessActivity(
                bundleIdentifier: bundleIdentifier,
                applicationName: applicationName,
                windowTitles: relatedTitles,
                isApplicationFrontmost: isApplicationFrontmost,
                isUsingMicrophone: isUsingMicrophone,
                isPlayingAudio: isPlayingAudio
            )
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

    private static let pollInterval = Duration.seconds(2)
    private static let presentationDuration = Duration.seconds(10)
    private static let missingSamplesToEndSession = 3

    private let prompt = NoteTakingPromptPanelController()
    private weak var coordinator: AppCoordinator?
    private var monitoringTask: Task<Void, Never>?
    private var autoDismissTask: Task<Void, Never>?
    private var currentSession: DetectedNoteTakingSession?
    private var presentedSessionID: String?
    private var dismissedSessionID: String?
    private var missingSampleCount = 0

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
        guard let detectedSession = NoteTakingSessionClassifier.detect(
            in: processes
        ) else {
            missingSampleCount += 1
            if missingSampleCount >= Self.missingSamplesToEndSession {
                resetSession()
                prompt.hide()
            }
            return
        }

        missingSampleCount = 0
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

    private func resetSession() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        currentSession = nil
        presentedSessionID = nil
        dismissedSessionID = nil
        missingSampleCount = 0
    }
}

@MainActor
private final class NoteTakingPromptPanelController {
    private let panel: NoteTakingPromptPanel
    private var presentedSessionID: String?
    private var generation = 0

    init() {
        panel = NoteTakingPromptPanel(
            contentRect: NSRect(x: 0, y: 0, width: 504, height: 96),
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
            y: visibleFrame.minY + 28,
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
    @AppStorage(BurritoAppearance.storageKey) private var appearanceRawValue =
        BurritoAppearance.system.rawValue

    let session: DetectedNoteTakingSession
    let start: () -> Void
    let dismiss: () -> Void

    private var appearance: BurritoAppearance {
        BurritoAppearance.resolve(appearanceRawValue)
    }

    private var title: String {
        switch session.kind {
        case .meeting: "Meeting detected"
        case .listenAlong: "Audio detected"
        }
    }

    private var subtitle: String {
        switch session.kind {
        case .meeting: "Live in \(session.applicationName)"
        case .listenAlong: "Playing in \(session.applicationName)"
        }
    }

    private var symbol: String {
        switch session.kind {
        case .meeting: "video.fill"
        case .listenAlong: "play.rectangle.fill"
        }
    }

    private var actionTitle: String {
        switch session.kind {
        case .meeting: "Start meeting note"
        case .listenAlong: "Start taking notes"
        }
    }

    private var actionHint: String {
        switch session.kind {
        case .meeting: "Starts a new recording in Meeting mode"
        case .listenAlong: "Starts a new recording in Listen Along mode"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(BurritoTheme.accent)
                .frame(width: 34, height: 34)
                .background(
                    BurritoTheme.accentSoft,
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.burritoUI(size: 14, weight: 620, relativeTo: .headline))
                    .foregroundStyle(BurritoTheme.foreground)
                HStack(spacing: 5) {
                    Circle()
                        .fill(BurritoTheme.sage)
                        .frame(width: 6, height: 6)
                    Text(subtitle)
                        .font(.burritoUI(size: 11, weight: .regular, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            Button(action: start) {
                HStack(spacing: 7) {
                    Image(systemName: "waveform")
                        .font(.system(size: 12, weight: .semibold))
                    Text(actionTitle)
                        .font(.burritoUI(size: 12, weight: 620, relativeTo: .callout))
                }
                .foregroundStyle(BurritoTheme.accentForeground)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(
                    BurritoTheme.accent,
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .accessibilityHint(actionHint)

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Not now")
            .accessibilityLabel("Dismiss note-taking prompt")
        }
        .padding(.horizontal, 14)
        .frame(width: 488, height: 80)
        .background(
            BurritoTheme.raised,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(BurritoTheme.softBorder, lineWidth: 1)
        }
        .burritoElevation(.floating)
        .padding(8)
        .preferredColorScheme(appearance.colorScheme)
        .font(.burritoUI(size: 13, weight: .regular))
        .id(
            "\(styleStore.theme.rawValue)-\(styleStore.font.rawValue)-\(styleStore.interfaceFontSize)"
        )
    }
}
