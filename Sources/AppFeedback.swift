import AppKit
import Observation
import UserNotifications

@MainActor
@Observable
final class NotificationAccess {
    enum State: Equatable {
        case unknown
        case needsAccess
        case denied
        case granted
    }

    static let shared = NotificationAccess()

    private(set) var state: State = .unknown
    private let notificationCenter = UNUserNotificationCenter.current()

    private init() {
        Task { await refresh() }
    }

    var needsPrompt: Bool {
        state == .needsAccess || state == .denied
    }

    var actionTitle: String {
        state == .denied ? "Open settings" : "Allow notifications"
    }

    func refresh() async {
        let settings = await notificationCenter.notificationSettings()
        state = switch settings.authorizationStatus {
        case .notDetermined: .needsAccess
        case .denied: .denied
        case .authorized, .provisional, .ephemeral: .granted
        @unknown default: .denied
        }
    }

    func requestAccess() async {
        if state == .denied {
            openSystemSettings()
            return
        }

        do {
            _ = try await notificationCenter.requestAuthorization(options: [.alert])
        } catch {
            // Refresh exposes the system's resulting state in the sidebar.
        }
        await refresh()
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

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        notificationCenter.add(request)
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
