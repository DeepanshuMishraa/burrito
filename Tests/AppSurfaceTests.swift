import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Burrito

@Suite("App surfaces")
struct AppSurfaceTests {
    @Test("App fonts include every Apple system design with safe persistence")
    func appFontsIncludeAppleSystemDesigns() {
        #expect(BurritoFontChoice.allCases.count == 12)
        #expect(BurritoFontChoice.resolve("geist-mono") == .geistMono)
        #expect(BurritoFontChoice.resolve("unknown-font") == .burritoDefault)
        #expect(Set(BurritoFontChoice.allCases.map(\.title)).count == 12)
        #expect(
            Set(BurritoFontChoice.allCases.map(\.title)).isSuperset(
                of: ["SF Pro", "SF Pro Rounded", "SF Mono", "New York"]
            )
        )
        #expect(BurritoFontChoice.allCases.filter { $0.category == .mono }.count == 4)
        #expect(BurritoFontChoice.allCases.filter { $0.category == .apple }.count == 4)
        #expect(BurritoFontChoice.allCases.filter { $0.category == .sans }.count == 3)
        #expect(BurritoFontChoice.allCases.filter { $0.category == .serif }.count == 1)
        #expect(BurritoInterfaceFontSize.resolve(16) == 16)
        #expect(BurritoInterfaceFontSize.resolve(99) == BurritoInterfaceFontSize.maximum)
        #expect(BurritoInterfaceFontSize.resolve(1) == BurritoInterfaceFontSize.minimum)
        #expect(BurritoInterfaceFontSize.scale(for: BurritoInterfaceFontSize.standard) == 1)
    }

    @Test("Bundled app fonts register every declared face")
    func bundledAppFontsRegisterEveryDeclaredFace() {
        BurritoFontRegistrar.registerFontsIfNeeded()

        for font in BurritoFontChoice.allCases {
            for postScriptName in font.registeredPostScriptNames {
                #expect(
                    NSFont(name: postScriptName, size: 13) != nil,
                    Comment(rawValue: postScriptName)
                )
            }
        }
    }

    @Test("Bundled Spline Sans Mono includes its OFL notice")
    func bundledSplineSansMonoIncludesLicense() {
        #expect(
            Bundle.main.url(
                forResource: "splinesansmono-OFL",
                withExtension: "txt",
                subdirectory: "Licenses"
            ) != nil
        )
    }

    @Test("Color themes resolve persisted values safely")
    func colorThemesResolvePersistedValuesSafely() {
        #expect(BurritoColorTheme.resolve("ocean-breeze") == .oceanBreeze)
        #expect(BurritoColorTheme.resolve("unknown-theme") == .burrito)
        #expect(Set(BurritoColorTheme.allCases.map(\.title)).count == BurritoColorTheme.allCases.count)
    }

    @Test("Color themes include Burrito and every tweakcn registry preset")
    func colorThemesIncludeRegistryPresets() {
        let expected: Set<String> = [
            "burrito", "modern-minimal", "t3-chat", "twitter", "mocha-mousse",
            "bubblegum", "doom-64", "catppuccin", "graphite", "perpetuity",
            "kodama-grove", "cosmic-night", "tangerine", "quantum-rose", "nature",
            "bold-tech", "elegant-luxury", "amber-minimal", "supabase", "neo-brutalism",
            "solar-dusk", "claymorphism", "cyberpunk", "pastel-dreams", "clean-slate",
            "caffeine", "ocean-breeze", "retro-arcade", "midnight-bloom", "candyland",
            "northern-lights", "vintage-paper", "sunset-horizon", "starry-night", "claude",
            "vercel", "mono",
        ]

        #expect(Set(BurritoColorTheme.allCases.map(\.rawValue)) == expected)
        #expect(BurritoColorTheme.allCases.first == .burrito)
    }

    @Test("Every color theme preserves readable semantic contrast")
    func colorThemesPreserveSemanticContrast() {
        for theme in BurritoColorTheme.allCases {
            let palette = theme.palette

            verifyContrast(in: palette, theme: theme, mode: "light", color: \.light)
            verifyContrast(in: palette, theme: theme, mode: "dark", color: \.dark)
        }
    }

    @Test("App scrollbars use the compact overlay metrics")
    @MainActor
    func scrollbarsUseCompactOverlayMetrics() {
        #expect(BurritoThinScroller.isCompatibleWithOverlayScrollers)
        #expect(
            BurritoThinScroller.scrollerWidth(for: .mini, scrollerStyle: .overlay) == 4
        )

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        scrollView.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 400))
        scrollView.scrollerStyle = .overlay
        scrollView.hasVerticalScroller = true
        let scroller = BurritoThinScroller(frame: .zero)
        scroller.controlSize = .mini
        scrollView.verticalScroller = scroller
        scrollView.tile()

        #expect(scrollView.verticalScroller?.frame.width == 4)
    }

    private func verifyContrast(
        in palette: BurritoThemePalette,
        theme: BurritoColorTheme,
        mode: String,
        color: KeyPath<BurritoAdaptiveThemeColor, BurritoThemeColor>
    ) {
        let foreground = palette.foreground[keyPath: color]
        let sidebarForeground = palette.sidebarForeground[keyPath: color]
        let accent = palette.accent[keyPath: color]
        let accentForeground = palette.accentForeground[keyPath: color]
        let sage = palette.sage[keyPath: color]
        let canvas = palette.canvas[keyPath: color]
        let sidebar = palette.sidebar[keyPath: color]
        let paper = palette.paper[keyPath: color]
        let raised = palette.raised[keyPath: color]
        let controlFill = palette.controlFill[keyPath: color]
        let controlForeground = palette.controlForeground[keyPath: color]
        let softBorder = palette.softBorder[keyPath: color]
        let accentSoft = palette.accentSoft[keyPath: color]
        let surfaces = [canvas, paper, raised]
        let context = "\(theme.rawValue) \(mode)"

        #expect(
            softBorder.alpha == (mode == "dark" ? 0.16 : 0.12),
            Comment(rawValue: context)
        )

        for surface in surfaces {
            #expect(foreground.contrastRatio(with: surface) >= 7.05, Comment(rawValue: context))
            #expect(accent.contrastRatio(with: surface) >= 4.55, Comment(rawValue: context))
            #expect(sage.contrastRatio(with: surface) >= 4.55, Comment(rawValue: context))
            #expect(
                controlForeground.contrastRatio(with: controlFill.composited(over: surface)) >= 4.55,
                Comment(rawValue: context)
            )
        }

        #expect(sidebarForeground.contrastRatio(with: sidebar) >= 7.05, Comment(rawValue: context))
        #expect(accent.contrastRatio(with: sidebar) >= 4.55, Comment(rawValue: context))
        #expect(accent.contrastRatio(with: accentSoft) >= 4.55, Comment(rawValue: context))
        #expect(accentForeground.contrastRatio(with: accent) >= 4.55, Comment(rawValue: context))
    }

    @Test("Numeric Spline fonts scale relative to their text style")
    func numericSplineFontScalesRelativeToTextStyle() {
        #expect(
            BurritoFontMetrics.scaledSize(
                12,
                relativeTo: .caption,
                preferredPointSize: 20
            ) == 24
        )
    }

    @Test("Numeric system fonts preserve requested designs")
    func numericSystemFontPreservesDesign() {
        let rounded = BurritoFontMetrics.systemFont(
            size: 13,
            weight: .medium,
            design: .rounded
        )
        let serif = BurritoFontMetrics.systemFont(
            size: 13,
            weight: .medium,
            design: .serif
        )
        let monospaced = BurritoFontMetrics.systemFont(
            size: 13,
            weight: .medium,
            design: .monospaced
        )

        #expect(rounded.familyName?.contains("Rounded") == true)
        #expect(
            serif.familyName.map { $0.contains("Serif") || $0 == "New York" } == true
        )
        #expect(
            monospaced.familyName.map {
                $0.contains("Monospaced") || $0 == "SF Mono"
            } == true
        )
    }

    @Test("Calendar meeting links skip non-web links before a web link")
    func calendarMeetingLinkSkipsNonWebLinks() {
        let location = "Dial tel:+15551234 or join https://meet.example.com/weekly"

        #expect(
            MeetingLink.first(
                explicitURL: nil,
                location: location,
                notes: nil
            )?.absoluteString == "https://meet.example.com/weekly"
        )
    }

    @MainActor
    @Test("Menu recordings use the persisted built-in template edits")
    func menuRecordingUsesPersistedTemplateEdits() {
        let edited = NoteTemplate(
            builtInID: BuiltInTemplate.summary.rawValue,
            name: "My Summary",
            symbol: "sparkles",
            instructions: "Use my edited structure."
        )

        let snapshot = RecordingTemplateResolver.snapshot(
            for: .listenAlong,
            defaultTemplateID: BuiltInTemplate.summary.rawValue,
            templates: [edited]
        )

        #expect(snapshot == edited.snapshot)
    }

    @MainActor
    @Test("Recording destinations remain queued until the main window consumes them")
    func recordingDestinationRemainsQueued() {
        let inbox = RecordingDestinationInbox()

        inbox.submit(.newNote)

        #expect(inbox.pending == .newNote)
        #expect(inbox.consume() == .newNote)
        #expect(inbox.pending == nil)
    }

    @MainActor
    @Test("Menu note selections remain queued until the main window consumes them")
    func noteSelectionRemainsQueued() {
        let inbox = NoteSelectionInbox()
        let noteID = UUID()

        inbox.submit(noteID)

        #expect(inbox.pendingNoteID == noteID)
        #expect(inbox.consume() == noteID)
        #expect(inbox.pendingNoteID == nil)
    }

    @MainActor
    @Test("Main-window routing opens and activates the app")
    func mainWindowRoutingOpensAndActivates() {
        var events: [String] = []
        let router = MainWindowRouter(
            activateAction: { events.append("activate") }
        )
        router.configure { events.append("open") }

        router.open()

        #expect(events == ["open", "activate"])
    }

    @Test("Menu notes are grouped into today, yesterday, and earlier")
    func menuNotesUseRelativeDateSections() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 7, hour: 12))
        )
        let today = try #require(calendar.date(byAdding: .hour, value: -2, to: now))
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: now))
        let earlier = try #require(calendar.date(byAdding: .day, value: -2, to: now))

        #expect(MenuBarNoteSection.today.contains(today, relativeTo: now, calendar: calendar))
        #expect(MenuBarNoteSection.yesterday.contains(yesterday, relativeTo: now, calendar: calendar))
        #expect(MenuBarNoteSection.earlier.contains(earlier, relativeTo: now, calendar: calendar))
    }

    @MainActor
    @Test("Timeline excerpts show human notes when generated Markdown is empty")
    func timelineExcerptFallsBackToHumanNotes() {
        let note = Note(
            lifecycle: .ready,
            title: "Planning",
            userNotes: "## Remember\nCall Priya tomorrow.",
            languageIdentifier: "en-US",
            template: TemplateSnapshot(
                name: "Summary",
                symbol: "doc",
                instructions: "Summarize."
            ),
            retainsAudio: false
        )

        #expect(NoteExcerpt.text(for: note) == "Remember\nCall Priya tomorrow.")
    }

    @MainActor
    @Test("Ask Burrito keeps its chat session across navigation")
    func askBurritoKeepsChatSession() {
        let sessions = MemoryChatSessionStore()
        sessions.askBurrito.draft = "Continue this thought"
        sessions.askBurrito.messages.append(
            MemoryChatMessage(isUser: true, text: "Earlier context")
        )
        sessions.askBurrito.isAnswering = true

        let restored = sessions.askBurrito

        #expect(restored.draft == "Continue this thought")
        #expect(restored.messages.map(\.text) == ["Earlier context"])
        #expect(restored.isAnswering)
    }

    @MainActor
    @Test("Each note restores its own chat session")
    func notesRestoreIndependentChatSessions() {
        let sessions = MemoryChatSessionStore()
        let firstNoteID = UUID()
        let secondNoteID = UUID()
        let firstSession = sessions.session(for: firstNoteID)
        firstSession.messages.append(
            MemoryChatMessage(isUser: false, text: "Still streaming")
        )

        #expect(sessions.session(for: firstNoteID) === firstSession)
        #expect(sessions.session(for: firstNoteID).messages.map(\.text) == ["Still streaming"])
        #expect(sessions.session(for: secondNoteID) !== firstSession)
        #expect(sessions.askBurrito !== firstSession)
    }
}
