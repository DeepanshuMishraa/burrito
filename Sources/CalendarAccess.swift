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

    private let eventStore = EKEventStore()
    private(set) var state: State = .notDetermined
    private(set) var upcomingEvents: [UpcomingCalendarEvent] = []

    init() {
        refresh()
    }

    func refresh() {
        state = switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized:
            .authorized
        case .denied, .restricted, .writeOnly:
            .denied
        case .notDetermined:
            .notDetermined
        @unknown default:
            .denied
        }

        if state == .authorized {
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
                loadUpcomingEvents()
            }
        } catch {
            state = .failed(error.localizedDescription)
            upcomingEvents = []
        }
    }

    private func loadUpcomingEvents(now: Date = .now) {
        let calendar = Calendar.current
        guard let end = calendar.date(byAdding: .day, value: 7, to: now) else {
            upcomingEvents = []
            return
        }

        let predicate = eventStore.predicateForEvents(
            withStart: now,
            end: end,
            calendars: nil
        )
        upcomingEvents = eventStore.events(matching: predicate)
            .filter { $0.endDate >= now }
            .sorted { $0.startDate < $1.startDate }
            .prefix(3)
            .map {
                let eventIdentifier = $0.calendarItemIdentifier
                return UpcomingCalendarEvent(
                    snapshot: CalendarEventSnapshot(
                        eventIdentifier: eventIdentifier,
                        title: $0.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                            ?? "Untitled event",
                        startDate: $0.startDate,
                        endDate: $0.endDate,
                        meetingURL: MeetingLink.first(
                            explicitURL: $0.url,
                            location: $0.location,
                            notes: $0.notes
                        ),
                        attendeeNames: ($0.attendees ?? []).compactMap {
                            $0.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                        },
                        organizerName: $0.organizer?.name?
                            .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                        recurrenceIdentifier: $0.hasRecurrenceRules ? eventIdentifier : nil,
                        calendarName: $0.calendar.title
                    ),
                    isAllDay: $0.isAllDay,
                )
            }
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
