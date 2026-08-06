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
        .scrollIndicators(.visible)
        .burritoThinScrollers()
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
    @AppStorage(BurritoColorTheme.storageKey) private var colorThemeRawValue =
        BurritoColorTheme.burrito.rawValue
    @AppStorage(BurritoFontChoice.storageKey) private var fontChoiceRawValue =
        BurritoFontChoice.burritoDefault.rawValue
    @AppStorage(BurritoInterfaceFontSize.storageKey) private var interfaceFontSizeRawValue =
        BurritoInterfaceFontSize.standard
    @AppStorage(BurritoFontSmoothing.storageKey) private var fontSmoothing = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch tab {
            case .general:
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 10) {
                        BurritoSectionLabel(title: "APPEARANCE & TYPOGRAPHY")

                        VStack(spacing: 0) {
                            BurritoThemePicker(selection: $colorThemeRawValue)

                            Divider().padding(.leading, 16)

                            BurritoFontPicker(
                                selection: $fontChoiceRawValue,
                                sizeSelection: $interfaceFontSizeRawValue
                            )

                            Divider().padding(.leading, 16)

                            BurritoToggleRow(
                                title: "Font smoothing",
                                subtitle: "Use thinner grayscale anti-aliasing. Restart Burrito after changing this setting.",
                                isOn: $fontSmoothing,
                                style: .settingsForm
                            )
                        }
                        .background(BurritoTheme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .burritoElevation(.surface)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(BurritoTheme.softBorder)
                        }

                        SettingsFootnote("Themes and typography apply across all windows and adapt to light or dark appearance.")
                    }

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
        .onChange(of: colorThemeRawValue, initial: true) { _, rawValue in
            BurritoStyleStore.shared.selectTheme(rawValue)
        }
        .onChange(of: fontChoiceRawValue, initial: true) { _, rawValue in
            BurritoStyleStore.shared.selectFont(rawValue)
        }
        .onChange(of: interfaceFontSizeRawValue, initial: true) { _, rawValue in
            BurritoStyleStore.shared.selectInterfaceFontSize(rawValue)
        }
        .onChange(of: fontSmoothing, initial: true) { _, isEnabled in
            BurritoFontSmoothing.apply(isEnabled)
        }
    }
}

private struct BurritoThemePicker: View {
    @Binding var selection: String
    @State private var isPresented = false
    @State private var query = ""

    private var selectedTheme: BurritoColorTheme {
        BurritoColorTheme.resolve(selection)
    }

    private var filteredThemes: [BurritoColorTheme] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return BurritoColorTheme.allCases }
        return BurritoColorTheme.allCases.filter {
            $0.title.localizedStandardContains(trimmed)
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            ThemeSwatches(colors: selectedTheme.previewColors)

            VStack(alignment: .leading, spacing: 3) {
                Text("Color theme")
                    .font(.spline(size: 13, weight: 450))
                    .foregroundStyle(.primary)
                Text("Choose a color palette for Burrito.")
                    .font(.spline(size: 11, weight: .regular, relativeTo: .caption))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                isPresented.toggle()
            } label: {
                HStack(spacing: 6) {
                    Text(selectedTheme.title)
                        .font(.spline(size: 12, weight: 450))
                        .foregroundStyle(BurritoTheme.accent)
                    BurritoIcon(name: "chevron.down", size: 8)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(BurritoTheme.controlFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isPresented ? BurritoTheme.accent.opacity(0.55) : BurritoTheme.softBorder)
                }
            }
            .buttonStyle(.plain)
            .popover(
                isPresented: $isPresented,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .top
            ) {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        BurritoIcon(name: "magnifyingglass", size: 11)
                            .foregroundStyle(.tertiary)
                        TextField("Find a theme…", text: $query)
                            .textFieldStyle(.plain)
                            .font(.spline(size: 12, weight: 400))
                        if !query.isEmpty {
                            Button {
                                query = ""
                            } label: {
                                BurritoIcon(name: "xmark.circle.fill", size: 10)
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(BurritoTheme.controlFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .burritoElevation(.control)

                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(filteredThemes) { theme in
                                Button {
                                    BurritoHaptics.trigger(.alignment)
                                    selection = theme.rawValue
                                    isPresented = false
                                } label: {
                                    HStack(spacing: 12) {
                                        ThemeSwatches(colors: theme.previewColors)
                                        Text(theme.title)
                                            .font(.spline(size: 12, weight: 450))
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        if selection == theme.rawValue {
                                            BurritoIcon(name: "checkmark", size: 10)
                                                .foregroundStyle(BurritoTheme.accent)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .frame(height: 36)
                                    .background(
                                        selection == theme.rawValue
                                            ? BurritoTheme.controlFill
                                            : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
                .padding(10)
                .frame(width: 250, height: 320)
                .background(BurritoTheme.raised)
                .presentationBackground(BurritoTheme.raised)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .onChange(of: isPresented) { _, presented in
            if !presented { query = "" }
        }
        .onAppear {
            selection = selectedTheme.rawValue
        }
    }
}

private struct BurritoFontPicker: View {
    @Binding var selection: String
    @Binding var sizeSelection: Int
    @State private var isPresented = false
    @State private var query = ""

    private var selectedFont: BurritoFontChoice {
        BurritoFontChoice.resolve(selection)
    }

    private var selectedSize: Int {
        BurritoInterfaceFontSize.resolve(sizeSelection)
    }

    private var sizeBinding: Binding<Int> {
        Binding(
            get: { selectedSize },
            set: { sizeSelection = BurritoInterfaceFontSize.resolve($0) }
        )
    }

    private var filteredFonts: [BurritoFontChoice] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return BurritoFontChoice.allCases }
        return BurritoFontChoice.allCases.filter {
            $0.title.localizedStandardContains(trimmed) ||
            $0.category.rawValue.localizedStandardContains(trimmed)
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Text("Ag")
                .font(selectedFont.font(size: 17, weight: 450))
                .foregroundStyle(BurritoTheme.accent)
                .frame(width: 32, height: 32)
                .background(BurritoTheme.accentSoft, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("App font")
                    .font(.spline(size: 13, weight: 450))
                    .foregroundStyle(.primary)
                Text("Choose a typeface for interface and notes.")
                    .font(.spline(size: 11, weight: .regular, relativeTo: .caption))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    isPresented.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Text(selectedFont.title)
                            .font(.spline(size: 12, weight: 450))
                            .foregroundStyle(BurritoTheme.accent)
                        BurritoIcon(name: "chevron.down", size: 8)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(BurritoTheme.controlFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(isPresented ? BurritoTheme.accent.opacity(0.55) : BurritoTheme.softBorder)
                    }
                }
                .buttonStyle(.plain)
                .popover(
                    isPresented: $isPresented,
                    attachmentAnchor: .rect(.bounds),
                    arrowEdge: .top
                ) {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        BurritoIcon(name: "magnifyingglass", size: 11)
                            .foregroundStyle(.tertiary)
                        TextField("Find a font…", text: $query)
                            .textFieldStyle(.plain)
                            .font(.spline(size: 12, weight: 400))
                        if !query.isEmpty {
                            Button {
                                query = ""
                            } label: {
                                BurritoIcon(name: "xmark.circle.fill", size: 10)
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(BurritoTheme.controlFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .burritoElevation(.control)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(BurritoFontCategory.allCases) { category in
                                let categoryFonts = filteredFonts.filter { $0.category == category }
                                if !categoryFonts.isEmpty {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(category.title)
                                            .font(.spline(size: 9, weight: 600))
                                            .tracking(0.8)
                                            .foregroundStyle(.tertiary)
                                            .padding(.horizontal, 10)
                                            .padding(.top, 4)

                                        ForEach(categoryFonts) { font in
                                            Button {
                                                BurritoHaptics.trigger(.alignment)
                                                selection = font.rawValue
                                                isPresented = false
                                            } label: {
                                                HStack(spacing: 12) {
                                                    Text("Ag")
                                                        .font(font.font(size: 15, weight: 450))
                                                        .foregroundStyle(BurritoTheme.accent)
                                                        .frame(width: 24)

                                                    Text(font.title)
                                                        .font(font.font(size: 12, weight: 450))
                                                        .foregroundStyle(.primary)

                                                    Spacer()

                                                    if selection == font.rawValue {
                                                        BurritoIcon(name: "checkmark", size: 10)
                                                            .foregroundStyle(BurritoTheme.accent)
                                                    }
                                                }
                                                .padding(.horizontal, 10)
                                                .frame(height: 34)
                                                .background(
                                                    selection == font.rawValue
                                                        ? BurritoTheme.controlFill
                                                        : Color.clear,
                                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
                .padding(10)
                .frame(width: 250, height: 320)
                .background(BurritoTheme.raised)
                .presentationBackground(BurritoTheme.raised)
                }

                HStack(spacing: 0) {
                    Button {
                        sizeSelection = BurritoInterfaceFontSize.resolve(selectedSize - 1)
                    } label: {
                        BurritoIcon(name: "minus", size: 9, accessibilityLabel: "Decrease interface font size")
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedSize == BurritoInterfaceFontSize.minimum)

                    Divider().frame(height: 16)

                    TextField("", value: sizeBinding, format: .number.grouping(.never))
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.center)
                        .font(.spline(size: 12, weight: 450))
                        .foregroundStyle(BurritoTheme.accent)
                        .frame(width: 34)
                        .accessibilityLabel("Interface font size in pixels")

                    Text("px")
                        .font(.spline(size: 10, weight: 450))
                        .foregroundStyle(.tertiary)
                        .padding(.trailing, 6)

                    Divider().frame(height: 16)

                    Button {
                        sizeSelection = BurritoInterfaceFontSize.resolve(selectedSize + 1)
                    } label: {
                        BurritoIcon(name: "plus", size: 9, accessibilityLabel: "Increase interface font size")
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedSize == BurritoInterfaceFontSize.maximum)
                }
                .background(BurritoTheme.controlFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(BurritoTheme.softBorder)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .onChange(of: isPresented) { _, presented in
            if !presented { query = "" }
        }
        .onChange(of: sizeSelection, initial: true) { _, value in
            let resolved = BurritoInterfaceFontSize.resolve(value)
            if resolved != value {
                sizeSelection = resolved
            }
        }
        .onAppear {
            selection = selectedFont.rawValue
        }
    }
}

private struct ThemeSwatches: View {
    let colors: [Color]

    var body: some View {
        HStack(spacing: -5) {
            ForEach(Array(colors.enumerated()), id: \.offset) { index, color in
                Circle()
                    .fill(color)
                    .frame(width: 22, height: 22)
                    .overlay {
                        Circle().stroke(BurritoTheme.softBorder)
                    }
                    .zIndex(Double(colors.count - index))
            }
        }
        .frame(width: 54)
        .accessibilityHidden(true)
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
                                .foregroundStyle(BurritoTheme.accentForeground)
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
