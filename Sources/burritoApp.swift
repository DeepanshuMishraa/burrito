import AppKit
import SwiftUI
import SwiftData

@MainActor
private final class BurritoAppDelegate: NSObject, NSApplicationDelegate {
    private let updater = BurritoUpdateManager.shared

    func applicationWillFinishLaunching(_ notification: Notification) {
        BurritoFontRegistrar.registerFontsIfNeeded()
        _ = BurritoAppFeedback.shared
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        updater.start()
    }
}

@main
struct burritoApp: App {
    @NSApplicationDelegateAdaptor(BurritoAppDelegate.self) private var appDelegate
    @State private var coordinator = AppCoordinator.live()
    @State private var calendarAccess = CalendarAccess()

    private let container: ModelContainer = {
        do {
            return try ModelContainer(for: Note.self, Folder.self, NoteTemplate.self)
        } catch {
            fatalError("Burrito could not create its local data store: \(error.localizedDescription)")
        }
    }()

    var body: some Scene {
        WindowGroup("Burrito", id: "main") {
            ContentView(
                coordinator: coordinator,
                calendarAccess: calendarAccess
            )
            .font(.spline(size: 13, weight: .regular))
        }
        .modelContainer(container)
        .defaultSize(width: 1_180, height: 760)
        .windowStyle(.hiddenTitleBar)
        .commands {
            BurritoCommands()
        }

        MenuBarExtra {
            BurritoMenuBarMenu(
                coordinator: coordinator,
                calendarAccess: calendarAccess
            )
            .modelContainer(container)
        } label: {
            Image(
                nsImage: BurritoMenuBarArtwork.image(
                    isRecording: coordinator.captureState.isRecording
                )
            )
            .renderingMode(.template)
            .accessibilityLabel(
                coordinator.captureState.isRecording ? "Burrito is recording" : "Burrito"
            )
        }
        .menuBarExtraStyle(.menu)
    }
}

private enum BurritoMenuBarArtwork {
    private static let idle = makeImage(isRecording: false)
    private static let recording = makeImage(isRecording: true)

    static func image(isRecording: Bool) -> NSImage {
        isRecording ? recording : idle
    }

    private static func makeImage(isRecording: Bool) -> NSImage {
        let image = NSImage(
            size: NSSize(width: 18, height: 18),
            flipped: true
        ) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let headphones = NSBezierPath()
            headphones.move(to: NSPoint(x: 3.2, y: 8.2))
            headphones.curve(
                to: NSPoint(x: 14.8, y: 8.2),
                controlPoint1: NSPoint(x: 3.2, y: 1.8),
                controlPoint2: NSPoint(x: 14.8, y: 1.8)
            )
            headphones.lineWidth = 1.45
            headphones.lineCapStyle = .round
            headphones.stroke()

            let body = NSBezierPath(
                roundedRect: NSRect(x: 4.2, y: 5.7, width: 9.6, height: 10.5),
                xRadius: 2.8,
                yRadius: 2.8
            )
            body.lineWidth = 1.25
            body.lineJoinStyle = .round
            body.stroke()

            let fold = NSBezierPath()
            fold.move(to: NSPoint(x: 4.8, y: 7.1))
            fold.line(to: NSPoint(x: 12.9, y: 11.1))
            fold.lineWidth = 1.05
            fold.lineCapStyle = .round
            fold.stroke()

            NSBezierPath(
                roundedRect: NSRect(x: 2.1, y: 7.2, width: 2.8, height: 5.6),
                xRadius: 1.25,
                yRadius: 1.25
            ).fill()
            NSBezierPath(
                roundedRect: NSRect(x: 13.1, y: 7.2, width: 2.8, height: 5.6),
                xRadius: 1.25,
                yRadius: 1.25
            ).fill()
            NSBezierPath(
                ovalIn: NSRect(x: 6.25, y: 11.05, width: 1.2, height: 1.35)
            ).fill()
            NSBezierPath(
                ovalIn: NSRect(x: 10.55, y: 11.05, width: 1.2, height: 1.35)
            ).fill()

            let smile = NSBezierPath()
            smile.move(to: NSPoint(x: 8.05, y: 13.1))
            smile.curve(
                to: NSPoint(x: 9.95, y: 13.1),
                controlPoint1: NSPoint(x: 8.45, y: 14),
                controlPoint2: NSPoint(x: 9.55, y: 14)
            )
            smile.lineWidth = 0.85
            smile.lineCapStyle = .round
            smile.stroke()

            if isRecording {
                NSColor.white.setFill()
                NSBezierPath(
                    ovalIn: NSRect(x: 12.4, y: 12.4, width: 5.2, height: 5.2)
                ).fill()
                NSColor.black.setFill()
                NSBezierPath(
                    ovalIn: NSRect(x: 13.25, y: 13.25, width: 3.5, height: 3.5)
                ).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Burrito"
        return image
    }
}

private struct BurritoMenuBarMenu: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \NoteTemplate.createdAt) private var templates: [NoteTemplate]

    let coordinator: AppCoordinator
    let calendarAccess: CalendarAccess

    @AppStorage("defaultTemplateID") private var defaultTemplateID =
        BuiltInTemplate.summary.rawValue
    @AppStorage("transcriptionLanguage") private var language = "en-US"
    @AppStorage("retainAudioDefault") private var retainsAudio = false

    private var nextMeeting: UpcomingCalendarEvent? {
        calendarAccess.upcomingEvents
            .filter { $0.endDate >= .now }
            .min { $0.startDate < $1.startDate }
    }

    var body: some View {
        if coordinator.captureState.isRecording {
            Button(
                "Recording · \(Duration.seconds(coordinator.elapsed).formatted(.time(pattern: .minuteSecond)))",
                systemImage: "record.circle.fill"
            ) {}
            .disabled(true)

            if let event = coordinator.activeCalendarEvent {
                Button(event.title, systemImage: "calendar") {}
                    .disabled(true)
            }

            if coordinator.smartStopStatus == .suggested {
                Button("Meeting looks finished", systemImage: "checkmark.circle") {}
                    .disabled(true)
                Button("Keep Recording") {
                    coordinator.keepRecording()
                }
            }

            Button("Stop and Build Note", systemImage: "stop.fill") {
                Task { await coordinator.stop(context: modelContext) }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Divider()

            Button("Open Active Recording", systemImage: "macwindow") {
                openMainWindow()
            }
        } else {
            Menu("Start Recording", systemImage: "record.circle") {
                Button("Listen Along", systemImage: "speaker.wave.2") {
                    startQuickRecording(mode: .listenAlong)
                }
                Button("Meeting Mode", systemImage: "person.2.wave.2") {
                    startQuickRecording(mode: .meeting)
                }
            }

            Button("New Recording…", systemImage: "slider.horizontal.3") {
                openRecordingSetup()
            }
            .keyboardShortcut("n", modifiers: .command)

            Divider()

            if let event = nextMeeting {
                Menu("Next: \(event.title)", systemImage: "calendar") {
                    Button(
                        event.startDate.formatted(date: .abbreviated, time: .shortened),
                        systemImage: "clock"
                    ) {}
                    .disabled(true)

                    if event.meetingURL != nil {
                        Button("Join + Record", systemImage: "video.fill") {
                            start(event, joinsMeeting: true)
                        }
                    }
                    Button("Record Without Joining", systemImage: "waveform") {
                        start(event, joinsMeeting: false)
                    }
                }
            } else {
                Button("No Upcoming Meetings", systemImage: "calendar.badge.clock") {}
                    .disabled(true)
            }

            Button("Refresh Calendar", systemImage: "arrow.clockwise") {
                calendarAccess.refresh()
                Task {
                    await MeetingReminderScheduler.shared.synchronize(
                        events: calendarAccess.upcomingEvents
                    )
                }
            }

            Divider()

            if let error = coordinator.lastError {
                Button("Recording Needs Attention", systemImage: "exclamationmark.triangle") {
                    openMainWindow()
                }
                .help(error.recoveryMessage)
            }

            Button("Open Burrito") {
                openMainWindow()
            }

            Button("Settings…", systemImage: "gearshape") {
                openMainWindow()
                NotificationCenter.default.post(name: .burritoOpenSettings, object: nil)
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Quit Burrito") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    private func start(_ event: UpcomingCalendarEvent, joinsMeeting: Bool) {
        if joinsMeeting, let meetingURL = event.meetingURL {
            NSWorkspace.shared.open(meetingURL)
        }
        Task {
            await coordinator.start(
                options: RecordingOptions(
                    template: RecordingTemplateResolver.snapshot(
                        for: .meeting,
                        defaultTemplateID: defaultTemplateID,
                        templates: templates
                    ),
                    languageIdentifier: language,
                    mode: .meeting,
                    retainsAudio: retainsAudio
                ),
                destination: .calendarEvent(event.snapshot),
                context: modelContext
            )
        }
    }

    private func startQuickRecording(mode: RecordingMode) {
        Task {
            await coordinator.start(
                options: RecordingOptions(
                    template: RecordingTemplateResolver.snapshot(
                        for: mode,
                        defaultTemplateID: defaultTemplateID,
                        templates: templates
                    ),
                    languageIdentifier: language,
                    mode: mode,
                    retainsAudio: retainsAudio
                ),
                context: modelContext
            )
        }
    }

    private func openRecordingSetup() {
        RecordingDestinationInbox.shared.submit(.newNote)
        openMainWindow()
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

enum RecordingTemplateResolver {
    static func snapshot(
        for mode: RecordingMode,
        defaultTemplateID: String,
        templates: [NoteTemplate]
    ) -> TemplateSnapshot {
        let builtIn = mode == .meeting
            ? BuiltInTemplate.meeting
            : BuiltInTemplate(rawValue: defaultTemplateID) ?? .summary
        if let stored = templates.first(where: { $0.builtInID == builtIn.rawValue }) {
            return stored.snapshot
        }
        return TemplateSnapshot(
            name: builtIn.name,
            symbol: builtIn.symbol,
            instructions: builtIn.instructions
        )
    }
}
