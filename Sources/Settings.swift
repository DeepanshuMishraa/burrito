import AppKit
import Observation
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case capture
    case transcription
    case generation
    case storage

    var id: Self { self }

    var title: String {
        switch self {
        case .capture: "Capture"
        case .transcription: "Transcription"
        case .generation: "Generation"
        case .storage: "Storage"
        }
    }

    var symbol: String {
        switch self {
        case .capture: "waveform"
        case .transcription: "captions.bubble"
        case .generation: "apple.intelligence"
        case .storage: "internaldrive"
        }
    }
}

@MainActor
@Observable
final class SettingsNavigation {
    static let shared = SettingsNavigation()
    var selectedTab: SettingsTab? = .capture
    private init() {}
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private static var shared: SettingsWindowController?

    static func show(tab: SettingsTab? = nil) {
        if let tab {
            SettingsNavigation.shared.selectedTab = tab
        }
        if shared == nil {
            shared = SettingsWindowController()
        }
        shared?.showWindow(nil)
    }

    private init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: CGSize(width: 720, height: 540)),
            styleMask: [
                .titled,
                .closable,
                .resizable,
                .miniaturizable,
                .fullSizeContentView,
            ],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(BurritoTheme.canvas)
        window.minSize = NSSize(width: 640, height: 480)
        window.setFrameAutosaveName("BurritoSettingsWindow")
        window.center()
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: BurritoSettingsView())
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SettingsWindowController does not support storyboards.")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        Self.shared = nil
    }
}

private struct BurritoSettingsView: View {
    @State private var navigation = SettingsNavigation.shared

    private var selected: SettingsTab {
        navigation.selectedTab ?? .capture
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings")
                    .font(.system(size: 24, weight: .medium, design: .serif))
                    .padding(.bottom, 20)

                ForEach(SettingsTab.allCases) { tab in
                    Button {
                        navigation.selectedTab = tab
                    } label: {
                        Label(tab.title, systemImage: tab.symbol)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .frame(height: 38)
                            .background(
                                selected == tab ? BurritoTheme.controlFill : Color.clear,
                                in: Rectangle()
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(24)
            .frame(width: 210)
            .background(BurritoTheme.sidebar)

            SettingsPane(tab: selected)
        }
        .background(BurritoTheme.canvas)
        .frame(minWidth: 640, minHeight: 480)
    }
}

private struct SettingsPane: View {
    let tab: SettingsTab

    @AppStorage("defaultTemplateID") private var defaultTemplateID = BuiltInTemplate.summary.rawValue
    @AppStorage("transcriptionLanguage") private var transcriptionLanguage = "en-US"
    @AppStorage("microphoneDefault") private var microphoneDefault = false
    @AppStorage("retainAudioDefault") private var retainAudioDefault = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(tab.title)
                .font(.system(size: 30, weight: .medium, design: .serif))
                .padding(.bottom, 8)

            Text(subtitle)
                .foregroundStyle(.secondary)
                .padding(.bottom, 28)

            switch tab {
            case .capture:
                SettingsToggleRow(
                    title: "Include microphone",
                    detail: "Use your microphone for every new recording.",
                    isOn: $microphoneDefault
                )
                SettingsFootnote("System audio is always captured. Burrito never records screen frames.")
            case .transcription:
                BurritoLanguagePicker(selection: $transcriptionLanguage)
                    .frame(maxWidth: 330)
                    .padding(.bottom, 18)
                SettingsFootnote(
                    "Apple Speech remains available without a download. "
                        + "Manage optional Parakeet models from Models in the sidebar."
                )
            case .generation:
                SettingsChoiceGrid {
                    ForEach(BuiltInTemplate.allCases) { template in
                        SettingsChoice(
                            title: template.name,
                            symbol: template.symbol,
                            isSelected: defaultTemplateID == template.rawValue
                        ) {
                            defaultTemplateID = template.rawValue
                        }
                    }
                }
                SettingsFootnote("Generation stays private and runs through Apple Intelligence on this Mac.")
            case .storage:
                SettingsToggleRow(
                    title: "Keep recordings",
                    detail: "Retain audio after a successful transcription.",
                    isOn: $retainAudioDefault
                )
                SettingsFootnote("Audio is always preserved if capture or transcription fails.")
            }
            Spacer()
        }
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var subtitle: String {
        switch tab {
        case .capture: "Choose what Burrito listens to."
        case .transcription: "Set the language used for local transcription."
        case .generation: "Choose how new recordings become useful notes."
        case .storage: "Control what remains on your Mac."
        }
    }

}

private struct SettingsChoiceGrid<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            content
        }
        .padding(.bottom, 18)
    }
}

private struct SettingsChoice: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .foregroundStyle(isSelected ? BurritoTheme.accent : .secondary)
                Text(title)
                Spacer()
                Rectangle()
                    .fill(isSelected ? BurritoTheme.accent : BurritoTheme.controlFill)
                    .frame(width: 20, height: 20)
                    .overlay {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(BurritoTheme.raised, in: Rectangle())
            .overlay {
                Rectangle()
                    .stroke(isSelected ? BurritoTheme.accent.opacity(0.55) : BurritoTheme.softBorder)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Rectangle()
                    .fill(isOn ? BurritoTheme.accent : BurritoTheme.controlFill)
                    .frame(width: 42, height: 24)
                    .overlay(alignment: isOn ? .trailing : .leading) {
                        Rectangle()
                            .fill(.white)
                            .shadow(color: .black.opacity(0.16), radius: 2, y: 1)
                            .padding(3)
                    }
            }
            .padding(16)
            .background(BurritoTheme.raised, in: Rectangle())
            .overlay {
                Rectangle().stroke(BurritoTheme.softBorder)
            }
        }
        .buttonStyle(.plain)
        .padding(.bottom, 16)
    }
}

private struct SettingsFootnote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Label(text, systemImage: "lock.shield")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
