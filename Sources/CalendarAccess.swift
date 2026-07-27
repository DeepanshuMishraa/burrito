import EventKit
import Observation

struct UpcomingCalendarEvent: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarName: String
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
                UpcomingCalendarEvent(
                    id: $0.eventIdentifier,
                    title: $0.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                        ?? "Untitled event",
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    isAllDay: $0.isAllDay,
                    calendarName: $0.calendar.title
                )
            }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
