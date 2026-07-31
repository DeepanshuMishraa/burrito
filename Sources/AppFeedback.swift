import AppKit
import Observation
import OSLog
import UserNotifications

enum MeetingReminderAction: Equatable, Sendable {
    case record(CalendarEventSnapshot, joinsMeeting: Bool)
}

@MainActor
@Observable
final class MeetingActionInbox {
    static let shared = MeetingActionInbox()

    private(set) var pending: MeetingReminderAction?

    private init() {}

    func submit(_ action: MeetingReminderAction) {
        pending = action
    }

    func consume() -> MeetingReminderAction? {
        defer { pending = nil }
        return pending
    }
}

enum BurritoNotificationContract {
    static let meetingCategory = "BURRITO_MEETING_REMINDER"
    static let joinAndRecordAction = "BURRITO_JOIN_AND_RECORD"
    static let recordAction = "BURRITO_RECORD"
    static let smartStopCategory = "BURRITO_SMART_STOP"
    static let stopAction = "BURRITO_STOP_RECORDING"
    static let keepRecordingAction = "BURRITO_KEEP_RECORDING"
    static let eventKey = "calendarEvent"
    static let reminderPrefix = "meeting-reminder-"
}

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
    func smartStopSuggested(title: String)
}

extension AppFeedbackProviding {
    func smartStopSuggested(title _: String) {}
}

@MainActor
final class SilentAppFeedback: AppFeedbackProviding {
    func recordingStarted() {}
    func recordingStopped() {}
    func noteReady(title: String) {}
    func smartStopSuggested(title: String) {}
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
    private let stopSound = NSSound(named: NSSound.Name("Pop"))

    private override init() {
        super.init()
        startSound?.volume = 0.42
        stopSound?.volume = 0.38
        notificationCenter.delegate = self
        registerCategories()
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

    func smartStopSuggested(title: String) {
        deliver(
            title: "Is the meeting finished?",
            body: "\(title) has ended and Burrito has heard sustained silence.",
            categoryIdentifier: BurritoNotificationContract.smartStopCategory
        )
    }

    private func registerCategories() {
        let join = UNNotificationAction(
            identifier: BurritoNotificationContract.joinAndRecordAction,
            title: "Join + Record",
            options: [.foreground]
        )
        let record = UNNotificationAction(
            identifier: BurritoNotificationContract.recordAction,
            title: "Record only",
            options: [.foreground]
        )
        let stop = UNNotificationAction(
            identifier: BurritoNotificationContract.stopAction,
            title: "Stop recording",
            options: [.foreground, .destructive]
        )
        let keep = UNNotificationAction(
            identifier: BurritoNotificationContract.keepRecordingAction,
            title: "Keep recording",
            options: []
        )
        notificationCenter.setNotificationCategories([
            UNNotificationCategory(
                identifier: BurritoNotificationContract.meetingCategory,
                actions: [join, record],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: BurritoNotificationContract.smartStopCategory,
                actions: [stop, keep],
                intentIdentifiers: []
            ),
        ])
    }

    private func deliver(
        title: String,
        body: String,
        categoryIdentifier: String = ""
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.interruptionLevel = .active
        content.categoryIdentifier = categoryIdentifier

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

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionIdentifier = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo
        let event = Self.decodeEvent(from: userInfo)
        completionHandler()

        Task { @MainActor in
            switch actionIdentifier {
            case BurritoNotificationContract.joinAndRecordAction,
                 BurritoNotificationContract.recordAction:
                guard let event else { return }
                MeetingActionInbox.shared.submit(
                    .record(
                        event,
                        joinsMeeting:
                            actionIdentifier
                                == BurritoNotificationContract.joinAndRecordAction
                    )
                )
                NSApp.activate(ignoringOtherApps: true)
            case BurritoNotificationContract.stopAction:
                NotificationCenter.default.post(name: .burritoStopRecording, object: nil)
                NSApp.activate(ignoringOtherApps: true)
            case BurritoNotificationContract.keepRecordingAction:
                NotificationCenter.default.post(name: .burritoKeepRecording, object: nil)
            default:
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    nonisolated private static func decodeEvent(
        from userInfo: [AnyHashable: Any]
    ) -> CalendarEventSnapshot? {
        guard let encoded = userInfo[BurritoNotificationContract.eventKey] as? String,
              let data = Data(base64Encoded: encoded)
        else {
            return nil
        }
        return try? JSONDecoder().decode(CalendarEventSnapshot.self, from: data)
    }
}

@MainActor
final class MeetingReminderScheduler {
    static let shared = MeetingReminderScheduler()

    private let notificationCenter = UNUserNotificationCenter.current()

    private init() {}

    func synchronize(events: [UpcomingCalendarEvent], relativeTo now: Date = .now) async {
        let plans = MeetingReminder.plan(events: events, relativeTo: now)
        let pending = await notificationCenter.pendingNotificationRequests()
        let oldIdentifiers = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(BurritoNotificationContract.reminderPrefix) }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: oldIdentifiers)

        let settings = await notificationCenter.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else {
            return
        }

        for plan in plans {
            guard let encodedEvent = try? JSONEncoder().encode(plan.event) else {
                continue
            }
            let content = UNMutableNotificationContent()
            content.title = plan.event.title
            content.body = "Starts at \(plan.event.startDate.formatted(date: .omitted, time: .shortened)). Ready to join and record?"
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            content.categoryIdentifier = BurritoNotificationContract.meetingCategory
            content.userInfo = [
                BurritoNotificationContract.eventKey: encodedEvent.base64EncodedString(),
            ]
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: plan.deliveryDate
            )
            let request = UNNotificationRequest(
                identifier: plan.id,
                content: content,
                trigger: UNCalendarNotificationTrigger(
                    dateMatching: components,
                    repeats: false
                )
            )
            do {
                try await notificationCenter.add(request)
            } catch {
                NotificationAccess.shared.markDeliveryFailed()
            }
        }
    }
}
