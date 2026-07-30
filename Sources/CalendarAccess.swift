import AppKit
import EventKit
import Observation

struct UpcomingCalendarEvent: Identifiable, Equatable, Sendable {
    let snapshot: CalendarEventSnapshot
    let isAllDay: Bool

    var id: String { snapshot.eventIdentifier }
    var title: String { snapshot.title }
    var startDate: Date { snapshot.startDate }
    var endDate: Date { snapshot.endDate }
    var calendarName: String { snapshot.calendarName }
    var meetingURL: URL? { snapshot.meetingURL }
}

struct UpcomingMeetingIdentity: Hashable {
    let normalizedTitle: String
    let startDate: Date
    let endDate: Date

    init(title: String, startDate: Date, endDate: Date) {
        normalizedTitle = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        self.startDate = startDate
        self.endDate = endDate
    }
}

enum CalendarMeetingWindow {
    static let recentLookback: TimeInterval = 24 * 60 * 60
    static let recentLimit = 1
    static let upcomingLimit = 5

    static func start(relativeTo now: Date) -> Date {
        now.addingTimeInterval(-recentLookback)
    }

    static func visibleEvents(
        _ events: [UpcomingCalendarEvent],
        relativeTo now: Date
    ) -> [UpcomingCalendarEvent] {
        let recent = events
            .filter { $0.endDate < now }
            .sorted { $0.startDate > $1.startDate }
            .prefix(recentLimit)
        let upcoming = events
            .filter { $0.endDate >= now }
            .sorted { $0.startDate < $1.startDate }
            .prefix(upcomingLimit)
        return Array(recent) + Array(upcoming)
    }
}

@MainActor
@Observable
final class CalendarAccess {
    enum State: Equatable {
        case notDetermined
        case requesting
        case authorized
        case denied
        case failed(String)
    }

    @ObservationIgnored private let eventStore: EKEventStore
    @ObservationIgnored private let notificationCenter: NotificationCenter
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var eventStoreObservation: NotificationCenter.ObservationToken?
    private(set) var state: State = .notDetermined
    private(set) var upcomingEvents: [UpcomingCalendarEvent] = []
    private(set) var lastRefreshedAt: Date?

    init(
        eventStore: EKEventStore = EKEventStore(),
        notificationCenter: NotificationCenter = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.eventStore = eventStore
        self.notificationCenter = notificationCenter
        self.now = now
        eventStoreObservation = notificationCenter.addObserver(
            of: eventStore,
            for: .changed
        ) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    deinit {
        if let eventStoreObservation {
            notificationCenter.removeObserver(eventStoreObservation)
        }
    }

    func refresh() {
        lastRefreshedAt = now()
        let previousState = state
        let refreshedState: State = switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized:
            .authorized
        case .denied, .restricted, .writeOnly:
            .denied
        case .notDetermined:
            .notDetermined
        @unknown default:
            .denied
        }
        state = refreshedState

        if state == .authorized {
            if previousState != .authorized {
                eventStore.reset()
            }
            loadUpcomingEvents()
        } else {
            upcomingEvents = []
        }
    }

    func requestAccess() async {
        guard state != .requesting else { return }
        state = .requesting

        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            state = granted ? .authorized : .denied
            if granted {
                eventStore.reset()
                loadUpcomingEvents()
            }
        } catch {
            state = .failed(error.localizedDescription)
            upcomingEvents = []
        }
    }

    func openSystemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func loadUpcomingEvents() {
        let now = now()
        let calendar = Calendar.current
        let start = CalendarMeetingWindow.start(relativeTo: now)
        guard let end = calendar.date(byAdding: .day, value: 30, to: now) else {
            upcomingEvents = []
            return
        }

        let predicate = eventStore.predicateForEvents(
            withStart: start,
            end: end,
            calendars: nil
        )
        var seenMeetings = Set<UpcomingMeetingIdentity>()
        let meetings = eventStore.events(matching: predicate)
            .filter { $0.endDate >= start }
            .sorted { $0.startDate < $1.startDate }
            .compactMap { event -> UpcomingCalendarEvent? in
                guard !event.isAllDay, event.status != .canceled else {
                    return nil
                }

                let title = event.title?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty ?? "Untitled event"
                let identity = UpcomingMeetingIdentity(
                    title: title,
                    startDate: event.startDate,
                    endDate: event.endDate
                )
                guard seenMeetings.insert(identity).inserted else {
                    return nil
                }

                let eventIdentifier = event.calendarItemIdentifier
                return UpcomingCalendarEvent(
                    snapshot: CalendarEventSnapshot(
                        eventIdentifier: eventIdentifier,
                        title: title,
                        startDate: event.startDate,
                        endDate: event.endDate,
                        meetingURL: MeetingLink.first(
                            explicitURL: event.url,
                            location: event.location,
                            notes: event.notes
                        ),
                        attendeeNames: (event.attendees ?? []).compactMap {
                            $0.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                        },
                        organizerName: event.organizer?.name?
                            .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                        recurrenceIdentifier: event.hasRecurrenceRules ? eventIdentifier : nil,
                        calendarName: event.calendar.title
                    ),
                    isAllDay: false,
                )
            }
        upcomingEvents = CalendarMeetingWindow.visibleEvents(
            meetings,
            relativeTo: now
        )
    }
}

enum MeetingLink {
    static func first(explicitURL: URL?, location: String?, notes: String?) -> URL? {
        if let explicitURL, isWebURL(explicitURL) {
            return explicitURL
        }

        for text in [location, notes].compactMap({ $0 }) {
            guard let detector = try? NSDataDetector(
                types: NSTextCheckingResult.CheckingType.link.rawValue
            ) else {
                continue
            }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if let url = detector.firstMatch(in: text, range: range)?.url, isWebURL(url) {
                return url
            }
        }
        return nil
    }

    private static func isWebURL(_ url: URL) -> Bool {
        url.scheme == "https" || url.scheme == "http"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
