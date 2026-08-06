import AppKit
import SwiftUI

enum BurritoFontRegistrar {
    private static let registrationLock = NSLock()
    private nonisolated(unsafe) static var hasRegistered = false

    nonisolated static func registerFontsIfNeeded() {
        registrationLock.lock()
        defer { registrationLock.unlock() }

        guard !hasRegistered else { return }
        hasRegistered = true

        let fontNames = ["SplineSansMono-Variable.ttf", "SplineSansMono-Italic-Variable.ttf"]
        
        for fontName in fontNames {
            if let fontURL = Bundle.main.url(forResource: fontName, withExtension: nil) ??
                             Bundle.main.url(forResource: fontName, withExtension: nil, subdirectory: "Fonts") {
                CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
            }
        }
    }
}

extension Font {
    private static let splineWeightAxis = NSNumber(value: 0x7767_6874)

    static func burritoDisplay(
        size: CGFloat,
        weight: Font.Weight = .regular
    ) -> Font {
        BurritoFontRegistrar.registerFontsIfNeeded()
        return .custom("Spline Sans Mono", fixedSize: size).weight(weight)
    }

    static func burritoDisplay(size: CGFloat, weight: CGFloat) -> Font {
        spline(size: size, weight: weight)
    }

    static func spline(
        size: CGFloat,
        weight: Font.Weight = .regular
    ) -> Font {
        BurritoFontRegistrar.registerFontsIfNeeded()
        return .custom("Spline Sans Mono", fixedSize: size).weight(weight)
    }

    static func spline(size: CGFloat, weight: CGFloat) -> Font {
        BurritoFontRegistrar.registerFontsIfNeeded()
        let descriptor = CTFontDescriptorCreateWithNameAndSize(
            "Spline Sans Mono" as CFString,
            size
        )
        let variedDescriptor = CTFontDescriptorCreateCopyWithVariation(
            descriptor,
            splineWeightAxis,
            weight
        )
        let font = CTFontCreateWithFontDescriptor(variedDescriptor, size, nil)
        return Font(font as NSFont)
    }

    static func spline(
        size: CGFloat,
        weight: Font.Weight = .regular,
        relativeTo textStyle: Font.TextStyle
    ) -> Font {
        BurritoFontRegistrar.registerFontsIfNeeded()
        return .custom("Spline Sans Mono", size: size, relativeTo: textStyle).weight(weight)
    }

    static func spline(
        size: CGFloat,
        weight: CGFloat,
        relativeTo textStyle: Font.TextStyle
    ) -> Font {
        spline(
            size: BurritoFontMetrics.scaledSize(size, relativeTo: textStyle),
            weight: weight
        )
    }

    static func system(
        size: CGFloat,
        weight: CGFloat,
        design: Font.Design = .default
    ) -> Font {
        let regular = NSFont.Weight.regular.rawValue
        let medium = NSFont.Weight.medium.rawValue
        let fraction = min(1, max(0, (weight - 400) / 100))
        let platformWeight = NSFont.Weight(
            rawValue: regular + ((medium - regular) * fraction)
        )
        return Font(BurritoFontMetrics.systemFont(
            size: size,
            weight: platformWeight,
            design: design
        ))
    }
}

enum BurritoFontMetrics {
    static func scaledSize(
        _ size: CGFloat,
        relativeTo textStyle: Font.TextStyle,
        preferredPointSize: CGFloat? = nil
    ) -> CGFloat {
        let metrics = textMetrics(for: textStyle)
        let preferred = preferredPointSize
            ?? NSFont.preferredFont(forTextStyle: metrics.style).pointSize
        return size * preferred / metrics.defaultPointSize
    }

    static func systemFont(
        size: CGFloat,
        weight: NSFont.Weight,
        design: Font.Design
    ) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        let systemDesign: NSFontDescriptor.SystemDesign
        if design == .rounded {
            systemDesign = .rounded
        } else if design == .serif {
            systemDesign = .serif
        } else if design == .monospaced {
            systemDesign = .monospaced
        } else {
            return base
        }
        guard let descriptor = base.fontDescriptor.withDesign(systemDesign),
              let font = NSFont(descriptor: descriptor, size: size)
        else {
            return base
        }
        return font
    }

    private static func textMetrics(
        for textStyle: Font.TextStyle
    ) -> (style: NSFont.TextStyle, defaultPointSize: CGFloat) {
        if textStyle == .largeTitle { return (.largeTitle, 26) }
        if textStyle == .title { return (.title1, 22) }
        if textStyle == .title2 { return (.title2, 17) }
        if textStyle == .title3 { return (.title3, 15) }
        if textStyle == .headline { return (.headline, 13) }
        if textStyle == .subheadline { return (.subheadline, 11) }
        if textStyle == .callout { return (.callout, 12) }
        if textStyle == .footnote { return (.footnote, 10) }
        if textStyle == .caption { return (.caption1, 10) }
        if textStyle == .caption2 { return (.caption2, 10) }
        return (.body, 13)
    }
}

enum BurritoHaptics {
    @MainActor
    static func trigger(_ pattern: NSHapticFeedbackManager.FeedbackPattern = .generic) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}

extension Animation {
    static let burritoSpring = Animation.spring(response: 0.22, dampingFraction: 0.78)
    static let burritoSubtleSpring = Animation.spring(response: 0.3, dampingFraction: 0.85)
    static let burritoBouncySpring = Animation.spring(response: 0.25, dampingFraction: 0.68)
}

enum BurritoAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "appAppearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var systemImage: String {
        switch self {
        case .system: "computer"
        case .light: "sun02"
        case .dark: "moon02"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    static func resolve(_ rawValue: String) -> BurritoAppearance {
        BurritoAppearance(rawValue: rawValue) ?? .system
    }

}

enum BurritoTheme {
    static let accent = adaptive(
        light: NSColor(calibratedRed: 0.88, green: 0.30, blue: 0.10, alpha: 1),
        dark: NSColor(calibratedRed: 1.00, green: 0.43, blue: 0.20, alpha: 1)
    )
    static let accentSoft = adaptive(
        light: NSColor(calibratedRed: 0.98, green: 0.88, blue: 0.80, alpha: 1),
        dark: NSColor(calibratedRed: 0.25, green: 0.14, blue: 0.10, alpha: 1)
    )
    static let canvas = adaptive(
        light: NSColor(calibratedRed: 0.95, green: 0.94, blue: 0.91, alpha: 1),
        dark: NSColor(calibratedRed: 0.145, green: 0.14, blue: 0.13, alpha: 1)
    )
    static let sidebar = adaptive(
        light: NSColor(calibratedRed: 0.92, green: 0.91, blue: 0.88, alpha: 1),
        dark: NSColor(calibratedRed: 0.115, green: 0.112, blue: 0.105, alpha: 1)
    )
    static let paper = adaptive(
        light: NSColor(calibratedRed: 0.97, green: 0.96, blue: 0.93, alpha: 1),
        dark: NSColor(calibratedRed: 0.17, green: 0.165, blue: 0.155, alpha: 1)
    )
    static let raised = adaptive(
        light: NSColor(calibratedRed: 0.99, green: 0.985, blue: 0.965, alpha: 1),
        dark: NSColor(calibratedRed: 0.205, green: 0.20, blue: 0.19, alpha: 1)
    )
    static let controlFill = adaptive(
        light: NSColor(calibratedWhite: 0.0, alpha: 0.055),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.075)
    )
    static let softBorder = adaptive(
        light: NSColor(calibratedWhite: 0.0, alpha: 0.09),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.10)
    )
    static let sage = adaptive(
        light: NSColor(calibratedRed: 0.31, green: 0.47, blue: 0.37, alpha: 1),
        dark: NSColor(calibratedRed: 0.51, green: 0.68, blue: 0.56, alpha: 1)
    )

    static let sidebarWidth: CGFloat = 216
    static let listWidth: CGFloat = 340
    static let editorWidth: CGFloat = 760
    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            }
        )
    }
}

struct BurritoSectionLabel: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.spline(size: 10, weight: 450))
            .tracking(0.7)
            .foregroundStyle(.tertiary)
    }
}

struct BurritoPill: View {
    let title: String
    let systemImage: String

    var body: some View {
        BurritoLabel(title, systemImage: systemImage)
            .font(.spline(size: 11, weight: .regular, relativeTo: .caption))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(BurritoTheme.controlFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct BurritoToggleRow: View {
    enum Style {
        case standard
        case settingsForm
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    let style: Style

    init(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        style: Style = .standard
    ) {
        self.title = title
        self.subtitle = subtitle
        _isOn = isOn
        self.style = style
    }

    var body: some View {
        Button {
            BurritoHaptics.trigger(.alignment)
            withAnimation(reduceMotion ? nil : .burritoSpring) {
                isOn.toggle()
            }
        } label: {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(titleFont)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(subtitleFont)
                        .foregroundStyle(style == .settingsForm ? .secondary : .tertiary)
                }
                Spacer()
                switchControl
            }
            .padding(.horizontal, style == .settingsForm ? 18 : 14)
            .padding(.vertical, style == .settingsForm ? 14 : 0)
            .frame(height: style == .standard ? 58 : nil)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "On" : "Off")
    }

    private var titleFont: Font {
        style == .settingsForm
            ? .spline(size: 13, weight: 450)
            : .system(size: 13, weight: 450)
    }

    private var subtitleFont: Font {
        style == .settingsForm
            ? .spline(size: 11, weight: .regular, relativeTo: .caption)
            : .caption
    }

    @ViewBuilder
    private var switchControl: some View {
        if style == .settingsForm {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isOn ? BurritoTheme.accent : BurritoTheme.controlFill)
                .frame(width: 40, height: 22)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(.white)
                        .frame(width: 16, height: 16)
                        .shadow(color: .black.opacity(0.16), radius: 2, y: 1)
                        .padding(3)
                }
        } else {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Rectangle()
                    .fill(isOn ? BurritoTheme.accent : BurritoTheme.controlFill)
                    .frame(width: 38, height: 22)
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .padding(3)
            }
        }
    }
}

struct BurritoLanguagePicker: View {
    @Binding var selection: String
    var showsLabel = true
    var embedded = false

    @State private var isPresented = false
    @State private var query = ""

    private var selectedLanguage: TranscriptionLanguage {
        TranscriptionLanguage.resolve(selection)
    }

    private var filteredLanguages: [TranscriptionLanguage] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return TranscriptionLanguage.supported }
        return TranscriptionLanguage.supported.filter {
            $0.title.localizedStandardContains(trimmedQuery)
        }
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 12) {
                if showsLabel {
                    Text("Language")
                        .font(.spline(size: 13, weight: 450))
                        .foregroundStyle(.primary)
                }

                Spacer()

                Text(selectedLanguage.compactTitle)
                    .font(.spline(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)

                BurritoIcon(name: "chevron.down", size: 8)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(
                embedded ? Color.clear : BurritoTheme.controlFill,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .contentShape(Rectangle())
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
                    TextField("Find a language", text: $query)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(BurritoTheme.controlFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredLanguages) { language in
                            languageRow(language)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            .padding(8)
            .frame(width: 250, height: 330)
            .background(BurritoTheme.raised)
            .presentationBackground(BurritoTheme.raised)
        }
        .onChange(of: isPresented) { _, presented in
            if !presented { query = "" }
        }
        .accessibilityLabel("Transcription language")
        .accessibilityValue(selectedLanguage.title)
    }

    private func languageRow(_ language: TranscriptionLanguage) -> some View {
        Button {
            BurritoHaptics.trigger(.alignment)
            selection = language.identifier
            isPresented = false
        } label: {
            HStack(spacing: 9) {
                Text(language.title)
                    .font(.spline(size: 12, weight: .regular))
                    .foregroundStyle(.primary)
                Spacer()
                if selection == language.identifier {
                    BurritoIcon(name: "checkmark", size: 10)
                        .foregroundStyle(BurritoTheme.accent)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                selection == language.identifier
                    ? BurritoTheme.controlFill
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
