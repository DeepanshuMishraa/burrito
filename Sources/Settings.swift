import SwiftUI

enum OwnershipOperationStatus: Equatable {
    case running(String)
    case success(String)
    case failure(String)

    var message: String {
        switch self {
        case .running(let message), .success(let message), .failure(let message):
            message
        }
    }

    var symbol: String {
        switch self {
        case .running: "clock"
        case .success: "checkmark.circle"
        case .failure: "exclamationmark.triangle"
        }
    }

    var isFailure: Bool {
        if case .failure = self {
            return true
        }
        return false
    }

    var isRunning: Bool {
        if case .running = self {
            return true
        }
        return false
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case capture
    case connections
    case transcription
    case generation
    case storage

    var id: Self { self }

    var title: String {
        switch self {
        case .capture: "Capture"
        case .connections: "Connections"
        case .transcription: "Transcription"
        case .generation: "Generation"
        case .storage: "Storage"
        }
    }

    var symbol: String {
        switch self {
        case .capture: "waveform"
        case .connections: "link"
        case .transcription: "captions.bubble"
        case .generation: "apple.intelligence"
        case .storage: "internaldrive"
        }
    }
}

struct BurritoSettingsView: View {
    @Bindable var calendarAccess: CalendarAccess
    let exportLibrary: () -> Void
    let importLibrary: () -> Void
    let ownershipStatus: OwnershipOperationStatus?
    @State private var selected = SettingsTab.capture

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Settings")
                    .font(.burritoDisplay(size: 34, weight: .regular))
                    .tracking(-0.5)
                    .padding(.bottom, 22)

                HStack(spacing: 8) {
                    ForEach(SettingsTab.allCases) { tab in
                        Button {
                            selected = tab
                        } label: {
                            Label(tab.title, systemImage: tab.symbol)
                                .padding(.horizontal, 12)
                                .frame(height: 36)
                                .background(
                                    selected == tab ? BurritoTheme.controlFill : Color.clear,
                                    in: Rectangle()
                                )
                                .overlay {
                                    Rectangle().stroke(
                                        selected == tab
                                            ? BurritoTheme.softBorder
                                            : Color.clear
                                    )
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 28)

                SettingsPane(
                    tab: selected,
                    calendarAccess: calendarAccess,
                    exportLibrary: exportLibrary,
                    importLibrary: importLibrary,
                    ownershipStatus: ownershipStatus
                )
            }
            .frame(maxWidth: 780, alignment: .leading)
            .padding(.horizontal, 38)
            .padding(.top, 16)
            .padding(.bottom, 80)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(BurritoTheme.canvas)
    }
}

private struct SettingsPane: View {
    let tab: SettingsTab
    @Bindable var calendarAccess: CalendarAccess
    let exportLibrary: () -> Void
    let importLibrary: () -> Void
    let ownershipStatus: OwnershipOperationStatus?
    @AppStorage("defaultTemplateID") private var defaultTemplateID = BuiltInTemplate.summary.rawValue
    @AppStorage("transcriptionLanguage") private var transcriptionLanguage = "en-US"
    @AppStorage("microphoneDefault") private var microphoneDefault = false
    @AppStorage("retainAudioDefault") private var retainAudioDefault = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(tab.title)
                .font(.burritoDisplay(size: 30, weight: .medium))
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
            case .connections:
                CalendarConnectionSettingsRow(calendarAccess: calendarAccess)
                SettingsFootnote(
                    "Calendar access is optional and only reads upcoming event details on this Mac."
                )
            case .transcription:
                BurritoLanguagePicker(selection: $transcriptionLanguage)
                    .frame(maxWidth: 330)
                    .padding(.bottom, 14)
                LanguageCoverageCard(
                    language: TranscriptionLanguage.resolve(transcriptionLanguage)
                )
                SettingsFootnote(
                    "\(TranscriptionLanguage.supported.count) selectable languages. "
                        + "Burrito verifies the chosen engine before capture and never silently "
                        + "switches the recording language."
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
                OwnershipSettingsCard(
                    exportLibrary: exportLibrary,
                    importLibrary: importLibrary,
                    status: ownershipStatus
                )
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var subtitle: String {
        switch tab {
        case .capture: "Choose what Burrito listens to."
        case .connections: "Connect Burrito to your calendar."
        case .transcription: "Set the language used for local transcription."
        case .generation: "Choose how new recordings become useful notes."
        case .storage: "Control what remains on your Mac."
        }
    }

}

private struct OwnershipSettingsCard: View {
    let exportLibrary: () -> Void
    let importLibrary: () -> Void
    let status: OwnershipOperationStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(BurritoTheme.accent)
                    .frame(width: 36, height: 36)
                    .background(BurritoTheme.accentSoft, in: Rectangle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("Your library, in open files")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Export versioned JSON, readable Markdown, transcripts, templates, folders, and retained audio.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                Button("Export Library", systemImage: "square.and.arrow.up") {
                    exportLibrary()
                }
                .buttonStyle(SettingsActionButtonStyle())
                .disabled(status?.isRunning == true)

                Button("Import Backup", systemImage: "square.and.arrow.down") {
                    importLibrary()
                }
                .buttonStyle(SettingsActionButtonStyle())
                .disabled(status?.isRunning == true)
            }

            if let status {
                HStack(spacing: 7) {
                    if status.isRunning {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: status.symbol)
                    }
                    Text(status.message)
                }
                .font(.caption)
                .foregroundStyle(
                    status.isFailure ? Color.red : Color.secondary
                )
                .fixedSize(horizontal: false, vertical: true)
            }

            Text("Imports skip matching IDs and never overwrite local edits.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(BurritoTheme.raised, in: Rectangle())
        .overlay {
            Rectangle().stroke(BurritoTheme.softBorder)
        }
        .padding(.top, 18)
    }
}

private struct LanguageCoverageCard: View {
    let language: TranscriptionLanguage

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(BurritoTheme.accent)
                .frame(width: 34, height: 34)
                .background(BurritoTheme.accentSoft, in: Rectangle())
            VStack(alignment: .leading, spacing: 3) {
                Text("\(language.title) · \(language.engineCoverage.title)")
                    .font(.system(size: 13, weight: .semibold))
                Text(language.engineCoverage.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(BurritoTheme.raised, in: Rectangle())
        .overlay {
            Rectangle().stroke(BurritoTheme.softBorder)
        }
        .padding(.bottom, 14)
    }
}

private struct CalendarConnectionSettingsRow: View {
    @Bindable var calendarAccess: CalendarAccess

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "calendar")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(
                    calendarAccess.state == .authorized ? BurritoTheme.accent : .secondary
                )
                .frame(width: 38, height: 38)
                .background(BurritoTheme.controlFill, in: Rectangle())

            VStack(alignment: .leading, spacing: 4) {
                Text("Apple Calendar")
                    .font(.system(size: 14, weight: .semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            action
        }
        .padding(16)
        .background(BurritoTheme.raised, in: Rectangle())
        .overlay {
            Rectangle().stroke(BurritoTheme.softBorder)
        }
        .padding(.bottom, 16)
        .onAppear {
            calendarAccess.refresh()
        }
    }

    @ViewBuilder
    private var action: some View {
        switch calendarAccess.state {
        case .notDetermined, .failed:
            Button("Connect Calendar") {
                Task { await calendarAccess.requestAccess() }
            }
            .buttonStyle(SettingsActionButtonStyle())
        case .requesting:
            ProgressView()
                .controlSize(.small)
                .frame(width: 120)
        case .authorized:
            Label("Connected", systemImage: "checkmark")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(BurritoTheme.accent)
        case .denied:
            Button("Open System Settings") {
                calendarAccess.openSystemSettings()
            }
            .buttonStyle(SettingsActionButtonStyle())
        }
    }

    private var detail: String {
        switch calendarAccess.state {
        case .notDetermined:
            "Show upcoming meetings and attach their context to notes."
        case .requesting:
            "Waiting for macOS permission…"
        case .authorized:
            "Upcoming meetings are available in All Notes."
        case .denied:
            "Calendar access is off in Privacy & Security."
        case .failed(let message):
            "Couldn’t connect: \(message)"
        }
    }
}

private struct SettingsActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(BurritoTheme.controlFill, in: Rectangle())
            .overlay {
                Rectangle().stroke(BurritoTheme.softBorder)
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
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
                            .frame(width: 18, height: 18)
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
