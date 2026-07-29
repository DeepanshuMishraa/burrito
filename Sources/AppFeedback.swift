import AppKit
import Observation
import OSLog
import UserNotifications

@MainActor
@Observable
final class NotificationAccess {
    enum State: Equatable {
        case unknown
        case needsAccess
        case needsAlertStyle
        case denied
        case deliveryFailed
        case granted
    }

    static let shared = NotificationAccess()

    private(set) var state: State = .unknown
    private let notificationCenter = UNUserNotificationCenter.current()

    private init() {
        Task { await refresh() }
    }

    var needsPrompt: Bool {
        switch state {
        case .unknown, .granted: false
        case .needsAccess, .needsAlertStyle, .denied, .deliveryFailed: true
        }
    }

    var actionTitle: String {
        state == .needsAccess ? "Allow notifications" : "Open settings"
    }

    var canDeliverAlerts: Bool {
        state == .granted
    }

    func refresh() async {
        let settings = await notificationCenter.notificationSettings()
        state = Self.resolveState(
            authorizationStatus: settings.authorizationStatus,
            alertSetting: settings.alertSetting,
            alertStyle: settings.alertStyle
        )
    }

    func requestAccess() async {
        if state == .denied || state == .needsAlertStyle || state == .deliveryFailed {
            openSystemSettings()
            return
        }

        do {
            _ = try await notificationCenter.requestAuthorization(options: [.alert, .sound])
        } catch {
            state = .deliveryFailed
        }
        await refresh()
    }

    func markDeliveryFailed() {
        state = .deliveryFailed
    }

    nonisolated static func resolveState(
        authorizationStatus: UNAuthorizationStatus,
        alertSetting: UNNotificationSetting,
        alertStyle: UNAlertStyle
    ) -> State {
        switch authorizationStatus {
        case .notDetermined:
            return .needsAccess
        case .denied:
            return .denied
        case .authorized, .provisional, .ephemeral:
            return alertSetting == .enabled && alertStyle != .none
                ? .granted
                : .needsAlertStyle
        @unknown default:
            return .denied
        }
    }

    private func openSystemSettings() {
        let baseURL = "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        let destination: URL?
        if let identifier = Bundle.main.bundleIdentifier,
           let encodedIdentifier = identifier.addingPercentEncoding(
               withAllowedCharacters: .urlQueryAllowed
           ) {
            destination = URL(string: "\(baseURL)?id=\(encodedIdentifier)")
        } else {
            destination = URL(string: baseURL)
        }
        guard let destination else { return }
        NSWorkspace.shared.open(destination)
    }
}

@MainActor
protocol AppFeedbackProviding: AnyObject {
    func recordingStarted()
    func recordingStopped()
    func noteReady(title: String)
}

@MainActor
final class SilentAppFeedback: AppFeedbackProviding {
    func recordingStarted() {}
    func recordingStopped() {}
    func noteReady(title: String) {}
}

@MainActor
final class BurritoAppFeedback: NSObject, AppFeedbackProviding {
    static let shared = BurritoAppFeedback()

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.local.burrito",
        category: "Notifications"
    )
    private let notificationCenter = UNUserNotificationCenter.current()
    private let startSound = NSSound(named: NSSound.Name("Pop"))
    private let stopSound = NSSound(named: NSSound.Name("Tink"))

    private override init() {
        super.init()
        startSound?.volume = 0.42
        stopSound?.volume = 0.38
        notificationCenter.delegate = self
    }

    func recordingStarted() {
        startSound?.stop()
        startSound?.play()
        deliver(
            title: "Recording started",
            body: "Burrito is listening on this Mac."
        )
    }

    func recordingStopped() {
        stopSound?.stop()
        stopSound?.play()
        deliver(
            title: "Recording ended",
            body: "Audio captured. Building your note now."
        )
    }

    func noteReady(title: String) {
        deliver(
            title: "Note ready",
            body: title
        )
    }

    private func deliver(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.interruptionLevel = .active

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        Task {
            let access = NotificationAccess.shared
            await access.refresh()
            guard access.canDeliverAlerts else {
                Self.logger.notice(
                    "Notification not scheduled because visible alerts are disabled."
                )
                return
            }

            do {
                try await notificationCenter.add(request)
            } catch {
                Self.logger.error(
                    "Could not schedule notification: \(error.localizedDescription, privacy: .public)"
                )
                access.markDeliveryFailed()
            }
        }
    }
}

extension BurritoAppFeedback: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }
}
