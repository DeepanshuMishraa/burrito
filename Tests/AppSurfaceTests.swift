import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Burrito

@Suite("App surfaces")
struct AppSurfaceTests {
    @Test("Color themes resolve persisted values safely")
    func colorThemesResolvePersistedValuesSafely() {
        #expect(BurritoColorTheme.resolve("ocean-breeze") == .oceanBreeze)
        #expect(BurritoColorTheme.resolve("unknown-theme") == .burrito)
        #expect(Set(BurritoColorTheme.allCases.map(\.title)).count == BurritoColorTheme.allCases.count)
    }

    @Test("Color themes include Burrito and every tweakcn registry preset")
    func colorThemesIncludeRegistryPresets() {
        #expect(BurritoColorTheme.allCases.count == 37)
        #expect(BurritoColorTheme.allCases.first == .burrito)
        #expect(BurritoColorTheme.allCases.last == .mono)
    }

    @Test("Every color theme preserves readable semantic contrast")
    func colorThemesPreserveSemanticContrast() {
        for theme in BurritoColorTheme.allCases {
            let palette = theme.palette

            verifyContrast(in: palette, theme: theme, mode: "light", color: \.light)
            verifyContrast(in: palette, theme: theme, mode: "dark", color: \.dark)
        }
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
        let accentSoft = palette.accentSoft[keyPath: color]
        let surfaces = [canvas, paper, raised]
        let context = "\(theme.rawValue) \(mode)"

        for surface in surfaces {
            #expect(foreground.contrastRatio(with: surface) >= 4.5, Comment(rawValue: context))
            #expect(accent.contrastRatio(with: surface) >= 4.5, Comment(rawValue: context))
            #expect(sage.contrastRatio(with: surface) >= 4.5, Comment(rawValue: context))
        }

        #expect(sidebarForeground.contrastRatio(with: sidebar) >= 4.5, Comment(rawValue: context))
        #expect(accent.contrastRatio(with: sidebar) >= 4.5, Comment(rawValue: context))
        #expect(accent.contrastRatio(with: accentSoft) >= 4.5, Comment(rawValue: context))
        #expect(accentForeground.contrastRatio(with: accent) >= 4.5, Comment(rawValue: context))
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
