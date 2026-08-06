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
    case general
    case transcription
    case library

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .transcription: "Transcription"
        case .library: "Library & Calendar"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .transcription: "captions.bubble"
        case .library: "shippingbox"
        }
    }
}

struct BurritoSettingsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var calendarAccess: CalendarAccess
    let exportLibrary: () -> Void
    let importLibrary: () -> Void
    let ownershipStatus: OwnershipOperationStatus?
    @State private var selected = SettingsTab.general

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: 12)

                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Settings")
                            .font(.spline(size: 26, weight: 450))
                            .foregroundStyle(.primary)

                        Text("Preferences and data ownership on this Mac")
                            .font(.spline(size: 13, weight: .regular, relativeTo: .subheadline))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 20)

                    // Apple-Grade Segmented Control (Fixed single-line width)
                    HStack(spacing: 2) {
                        ForEach(SettingsTab.allCases) { tab in
                            Button {
                                BurritoHaptics.trigger(.alignment)
                                if reduceMotion {
                                    selected = tab
                                } else {
                                    withAnimation(.burritoSpring) {
                                        selected = tab
                                    }
                                }
                            } label: {
                                BurritoLabel(tab.title, systemImage: tab.symbol)
                                    .font(.spline(size: 12, weight: selected == tab ? 450 : 400))
                                    .foregroundStyle(selected == tab ? .primary : .secondary)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .padding(.horizontal, 14)
                                    .frame(height: 32)
                                    .background(
                                        selected == tab ? BurritoTheme.controlFill : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    )
                                    .burritoElevation(.control, isActive: selected == tab)
                                    .overlay {
                                        if selected == tab {
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .stroke(BurritoTheme.softBorder)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selected == tab ? .isSelected : [])
                        }
                    }
                    .padding(3)
                    .background(BurritoTheme.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .burritoElevation(.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(BurritoTheme.softBorder)
                    }
                    .layoutPriority(1)
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
            .frame(maxWidth: 820, alignment: .leading)
            .padding(.horizontal, 36)
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
            switch tab {
            case .general:
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 10) {
                        BurritoSectionLabel(title: "RECORDING & AUDIO")

                        // Apple-Style Grouped Form Card
                        VStack(spacing: 0) {
                            BurritoToggleRow(
                                title: "Include microphone by default",
                                subtitle: "Capture your microphone alongside system audio for every new recording.",
                                isOn: $microphoneDefault,
                                style: .settingsForm
                            )

                            Divider().padding(.leading, 16)

                            BurritoToggleRow(
                                title: "Keep audio backups",
                                subtitle: "Retain audio after successful transcription to allow regenerating notes later.",
                                isOn: $retainAudioDefault,
                                style: .settingsForm
                            )
                        }
                        .background(BurritoTheme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .burritoElevation(.surface)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(BurritoTheme.softBorder)
                        }

                        SettingsFootnote("System audio is always captured privately. Burrito never records screen frames.")
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        BurritoSectionLabel(title: "DEFAULT NOTE TEMPLATE")

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

                        SettingsFootnote("New recordings automatically generate notes using your default template.")
                    }
                }

            case .transcription:
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        BurritoSectionLabel(title: "RECORDING LANGUAGE")

                        BurritoLanguagePicker(selection: $transcriptionLanguage)
                            .frame(maxWidth: 340)
                            .padding(.bottom, 6)

                        LanguageCoverageCard(
                            language: TranscriptionLanguage.resolve(transcriptionLanguage)
                        )

                        SettingsFootnote(
                            "\(TranscriptionLanguage.supported.count) selectable languages. "
                                + "Burrito verifies the chosen engine before capture and never silently "
                                + "switches the recording language."
                        )
                    }
                }

            case .library:
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        BurritoSectionLabel(title: "CALENDAR INTEGRATION")

                        CalendarConnectionSettingsRow(calendarAccess: calendarAccess)

                        SettingsFootnote(
                            "Calendar access is optional and only reads upcoming event details on this Mac."
                        )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        BurritoSectionLabel(title: "DATA OWNERSHIP & BACKUPS")

                        OwnershipSettingsCard(
                            exportLibrary: exportLibrary,
                            importLibrary: importLibrary,
                            status: ownershipStatus
                        )
                    }
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct OwnershipSettingsCard: View {
    let exportLibrary: () -> Void
    let importLibrary: () -> Void
    let status: OwnershipOperationStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                BurritoIcon(name: "shippingbox", size: 15)
                    .foregroundStyle(BurritoTheme.accent)
                    .frame(width: 36, height: 36)
                    .background(BurritoTheme.accentSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .burritoElevation(.control)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Your library, in open files")
                        .font(.spline(size: 14, weight: 450))
                    Text("Export versioned JSON, readable Markdown, transcripts, templates, folders, and retained audio.")
                        .font(.spline(size: 11, weight: .regular, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                BurritoButton("Export Library", systemImage: "square.and.arrow.up") {
                    exportLibrary()
                }
                .buttonStyle(SettingsActionButtonStyle())
                .disabled(status?.isRunning == true)

                BurritoButton("Import Backup", systemImage: "square.and.arrow.down") {
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
                            .tint(.secondary)
                    } else {
                        BurritoIcon(name: status.symbol)
                    }
                    Text(status.message)
                }
                .font(.spline(size: 11, weight: .regular, relativeTo: .caption))
                .foregroundStyle(
                    status.isFailure ? Color.red : Color.secondary
                )
                .fixedSize(horizontal: false, vertical: true)
            }

            Text("Imports skip matching IDs and never overwrite local edits.")
                .font(.spline(size: 10, weight: .regular, relativeTo: .caption2))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(BurritoTheme.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .burritoElevation(.surface)
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(BurritoTheme.softBorder)
        }
        .padding(.top, 18)
    }
}

private struct LanguageCoverageCard: View {
    let language: TranscriptionLanguage

    var body: some View {
        HStack(spacing: 12) {
            BurritoIcon(name: "checkmark.shield", size: 15)
                .foregroundStyle(BurritoTheme.accent)
                .frame(width: 34, height: 34)
                .background(BurritoTheme.accentSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .burritoElevation(.control)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(language.title) · \(language.engineCoverage.title)")
                    .font(.spline(size: 13, weight: 450))
                Text(language.engineCoverage.detail)
                    .font(.spline(size: 11, weight: .regular, relativeTo: .caption))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(BurritoTheme.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .burritoElevation(.surface)
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(BurritoTheme.softBorder)
        }
        .padding(.bottom, 14)
    }
}

private struct CalendarConnectionSettingsRow: View {
    @Bindable var calendarAccess: CalendarAccess

    var body: some View {
        HStack(spacing: 14) {
            BurritoIcon(name: "calendar", size: 16)
                .foregroundStyle(
                    calendarAccess.state == .authorized ? BurritoTheme.accent : .secondary
                )
                .frame(width: 38, height: 38)
                .background(BurritoTheme.controlFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .burritoElevation(.control)

            VStack(alignment: .leading, spacing: 4) {
                Text("Apple Calendar")
                    .font(.spline(size: 14, weight: 450))
                Text(detail)
                    .font(.spline(size: 11, weight: .regular, relativeTo: .caption))
                    .foregroundStyle(.secondary)
            }

            Spacer()
            action
        }
        .padding(16)
        .background(BurritoTheme.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .burritoElevation(.surface)
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(BurritoTheme.softBorder)
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
            BurritoLabel("Connected", systemImage: "checkmark")
                .font(.spline(size: 13, weight: 450))
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.spline(size: 12, weight: 450))
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(BurritoTheme.controlFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .burritoElevation(.control)
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(BurritoTheme.softBorder)
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .animation(reduceMotion ? nil : .burritoSpring, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed { BurritoHaptics.trigger(.generic) }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            BurritoHaptics.trigger(.alignment)
            if reduceMotion {
                action()
            } else {
                withAnimation(.burritoSpring) {
                    action()
                }
            }
        } label: {
            HStack(spacing: 10) {
                BurritoIcon(name: symbol)
                    .foregroundStyle(isSelected ? BurritoTheme.accent : .secondary)
                Text(title)
                Spacer()
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isSelected ? BurritoTheme.accent : BurritoTheme.controlFill)
                    .frame(width: 20, height: 20)
                    .overlay {
                        if isSelected {
                            BurritoIcon(name: "checkmark", size: 9)
                                .foregroundStyle(.white)
                        }
                    }
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(BurritoTheme.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .burritoElevation(.surface)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? BurritoTheme.accent.opacity(0.55) : BurritoTheme.softBorder)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SettingsFootnote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        BurritoLabel(text, systemImage: "lock.shield")
            .font(.spline(size: 11, weight: .regular, relativeTo: .caption))
            .foregroundStyle(.secondary)
    }
}
