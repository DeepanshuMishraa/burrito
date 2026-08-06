import AppKit
import SwiftUI

enum BurritoFontCategory: String, CaseIterable, Identifiable {
    case mono = "MONO"
    case sans = "SANS"
    case serif = "SERIF"

    var id: Self { self }
}

enum BurritoFontChoice: String, CaseIterable, Identifiable {
    case burritoDefault = "burrito-default"
    case geistMono = "geist-mono"
    case jetBrainsMono = "jetbrains-mono"
    case ibmPlexMono = "ibm-plex-mono"
    case systemSans = "system-sans"
    case geistSans = "geist-sans"
    case inter
    case ibmPlexSans = "ibm-plex-sans"
    case systemSerif = "system-serif"
    case sourceSerif = "source-serif-4"

    static let storageKey = "appFont"

    var id: Self { self }

    static var selected: BurritoFontChoice {
        let rawValue = UserDefaults.standard.string(forKey: storageKey)
            ?? BurritoFontChoice.burritoDefault.rawValue
        return resolve(rawValue)
    }

    static func resolve(_ rawValue: String) -> BurritoFontChoice {
        BurritoFontChoice(rawValue: rawValue) ?? .burritoDefault
    }

    var title: String {
        switch self {
        case .burritoDefault: "Default"
        case .geistMono: "Geist Mono"
        case .jetBrainsMono: "JetBrains Mono"
        case .ibmPlexMono: "IBM Plex Mono"
        case .systemSans: "System Sans"
        case .geistSans: "Geist Sans"
        case .inter: "Inter"
        case .ibmPlexSans: "IBM Plex Sans"
        case .systemSerif: "System Serif"
        case .sourceSerif: "Source Serif 4"
        }
    }

    var category: BurritoFontCategory {
        switch self {
        case .burritoDefault, .geistMono, .jetBrainsMono, .ibmPlexMono: .mono
        case .systemSans, .geistSans, .inter, .ibmPlexSans: .sans
        case .systemSerif, .sourceSerif: .serif
        }
    }

    var resourceFileNames: [String] {
        switch self {
        case .burritoDefault:
            ["SplineSansMono-Variable.ttf", "SplineSansMono-Italic-Variable.ttf"]
        case .geistMono:
            ["GeistMono-Variable.ttf"]
        case .jetBrainsMono:
            ["JetBrainsMono-Variable.ttf"]
        case .ibmPlexMono:
            [
                "IBMPlexMono-Regular.ttf",
                "IBMPlexMono-Medium.ttf",
                "IBMPlexMono-SemiBold.ttf",
                "IBMPlexMono-Bold.ttf",
            ]
        case .systemSans, .systemSerif:
            []
        case .geistSans:
            ["Geist-Variable.ttf"]
        case .inter:
            ["Inter-Variable.ttf"]
        case .ibmPlexSans:
            ["IBMPlexSans-Variable.ttf"]
        case .sourceSerif:
            ["SourceSerif4-Variable.ttf"]
        }
    }

    var registeredPostScriptNames: [String] {
        switch self {
        case .burritoDefault: ["SplineSansMono-Regular", "SplineSansMono-Italic"]
        case .geistMono: ["GeistMono-Regular"]
        case .jetBrainsMono: ["JetBrainsMono-Regular"]
        case .ibmPlexMono:
            ["IBMPlexMono-Regular", "IBMPlexMono-Medium", "IBMPlexMono-SemiBold", "IBMPlexMono-Bold"]
        case .systemSans, .systemSerif: []
        case .geistSans: ["Geist-Regular"]
        case .inter: ["Inter-Regular"]
        case .ibmPlexSans: ["IBMPlexSans-Regular"]
        case .sourceSerif: ["SourceSerif4Roman-Regular"]
        }
    }

    func font(
        size: CGFloat,
        weight: Font.Weight,
        relativeTo textStyle: Font.TextStyle? = nil
    ) -> Font {
        BurritoFontRegistrar.registerFontsIfNeeded()
        if let design = systemDesign {
            let resolvedSize = textStyle.map {
                BurritoFontMetrics.scaledSize(size, relativeTo: $0)
            } ?? size
            return .system(size: resolvedSize, weight: weight, design: design)
        }

        let base = if let textStyle {
            Font.custom(familyName, size: size, relativeTo: textStyle)
        } else {
            Font.custom(familyName, fixedSize: size)
        }
        return base.weight(weight)
    }

    func font(size: CGFloat, weight: CGFloat) -> Font {
        BurritoFontRegistrar.registerFontsIfNeeded()
        if let design = systemDesign {
            return Font(BurritoFontMetrics.systemFont(
                size: size,
                weight: BurritoFontMetrics.platformWeight(for: weight),
                design: design
            ))
        }

        let postScriptName = postScriptName(for: weight)
        let descriptor = CTFontDescriptorCreateWithNameAndSize(postScriptName as CFString, size)
        let resolvedDescriptor = supportsVariableWeight
            ? CTFontDescriptorCreateCopyWithVariation(
                descriptor,
                NSNumber(value: 0x7767_6874),
                weight
            )
            : descriptor
        let font = CTFontCreateWithFontDescriptor(resolvedDescriptor, size, nil)
        return Font(font as NSFont)
    }

    private var familyName: String {
        switch self {
        case .burritoDefault: "Spline Sans Mono"
        case .geistMono: "Geist Mono"
        case .jetBrainsMono: "JetBrains Mono"
        case .ibmPlexMono: "IBM Plex Mono"
        case .geistSans: "Geist"
        case .inter: "Inter"
        case .ibmPlexSans: "IBM Plex Sans"
        case .sourceSerif: "Source Serif 4"
        case .systemSans, .systemSerif: ""
        }
    }

    private var systemDesign: Font.Design? {
        switch self {
        case .systemSans: .default
        case .systemSerif: .serif
        default: nil
        }
    }

    private var supportsVariableWeight: Bool {
        self != .ibmPlexMono
    }

    private func postScriptName(for weight: CGFloat) -> String {
        switch self {
        case .burritoDefault:
            return "SplineSansMono-Regular"
        case .geistMono:
            return "GeistMono-Regular"
        case .jetBrainsMono:
            return "JetBrainsMono-Regular"
        case .geistSans:
            return "Geist-Regular"
        case .inter:
            return "Inter-Regular"
        case .ibmPlexSans:
            return "IBMPlexSans-Regular"
        case .sourceSerif:
            return "SourceSerif4Roman-Regular"
        case .systemSans, .systemSerif:
            return ""
        case .ibmPlexMono:
            if weight >= 650 { return "IBMPlexMono-Bold" }
            if weight >= 550 { return "IBMPlexMono-SemiBold" }
            if weight >= 450 { return "IBMPlexMono-Medium" }
            return "IBMPlexMono-Regular"
        }
    }
}

enum BurritoFontRegistrar {
    private static let registrationLock = NSLock()
    private nonisolated(unsafe) static var hasRegistered = false

    nonisolated static func registerFontsIfNeeded() {
        registrationLock.lock()
        defer { registrationLock.unlock() }

        guard !hasRegistered else { return }
        hasRegistered = true

        let fontNames = BurritoFontChoice.allCases.flatMap(\.resourceFileNames)
        
        for fontName in fontNames {
            if let fontURL = Bundle.main.url(forResource: fontName, withExtension: nil) ??
                             Bundle.main.url(forResource: fontName, withExtension: nil, subdirectory: "Fonts") {
                CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
            }
        }
    }
}

extension Font {
    static func burritoDisplay(
        size: CGFloat,
        weight: Font.Weight = .regular
    ) -> Font {
        BurritoFontChoice.selected.font(size: size, weight: weight)
    }

    static func burritoDisplay(size: CGFloat, weight: CGFloat) -> Font {
        spline(size: size, weight: weight)
    }

    static func spline(
        size: CGFloat,
        weight: Font.Weight = .regular
    ) -> Font {
        BurritoFontChoice.selected.font(size: size, weight: weight)
    }

    static func spline(size: CGFloat, weight: CGFloat) -> Font {
        BurritoFontChoice.selected.font(size: size, weight: weight)
    }

    static func spline(
        size: CGFloat,
        weight: Font.Weight = .regular,
        relativeTo textStyle: Font.TextStyle
    ) -> Font {
        BurritoFontChoice.selected.font(size: size, weight: weight, relativeTo: textStyle)
    }

    static func spline(
        size: CGFloat,
        weight: CGFloat,
        relativeTo textStyle: Font.TextStyle
    ) -> Font {
        BurritoFontChoice.selected.font(
            size: BurritoFontMetrics.scaledSize(size, relativeTo: textStyle),
            weight: weight
        )
    }

    static func system(
        size: CGFloat,
        weight: CGFloat,
        design: Font.Design = .default
    ) -> Font {
        return Font(BurritoFontMetrics.systemFont(
            size: size,
            weight: BurritoFontMetrics.platformWeight(for: weight),
            design: design
        ))
    }
}

enum BurritoFontMetrics {
    static func platformWeight(for value: CGFloat) -> NSFont.Weight {
        let stops: [(value: CGFloat, weight: NSFont.Weight)] = [
            (100, .ultraLight),
            (200, .thin),
            (300, .light),
            (400, .regular),
            (500, .medium),
            (600, .semibold),
            (700, .bold),
            (800, .heavy),
            (900, .black),
        ]
        let clamped = min(900, max(100, value))
        guard let upperIndex = stops.firstIndex(where: { $0.value >= clamped }) else {
            return .black
        }
        guard upperIndex > 0 else { return stops[upperIndex].weight }

        let lower = stops[upperIndex - 1]
        let upper = stops[upperIndex]
        let fraction = (clamped - lower.value) / (upper.value - lower.value)
        return NSFont.Weight(
            rawValue: lower.weight.rawValue
                + ((upper.weight.rawValue - lower.weight.rawValue) * fraction)
        )
    }

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

struct BurritoThemeColor: Hashable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    static func rgb(_ value: UInt32, alpha: Double = 1) -> BurritoThemeColor {
        BurritoThemeColor(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255,
            alpha: alpha
        )
    }

    fileprivate var nsColor: NSColor {
        NSColor(
            calibratedRed: red,
            green: green,
            blue: blue,
            alpha: alpha
        )
    }

    var relativeLuminance: Double {
        func linearize(_ component: Double) -> Double {
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }

        return (0.2126 * linearize(red))
            + (0.7152 * linearize(green))
            + (0.0722 * linearize(blue))
    }

    func contrastRatio(with other: BurritoThemeColor) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    func ensuringContrast(
        against backgrounds: [BurritoThemeColor],
        minimum: Double
    ) -> BurritoThemeColor {
        guard backgrounds.contains(where: { contrastRatio(with: $0) < minimum }) else {
            return self
        }

        let candidates = [BurritoThemeColor.rgb(0x000000), .rgb(0xFFFFFF)].compactMap { target in
            guard backgrounds.allSatisfy({ target.contrastRatio(with: $0) >= minimum }) else {
                return Optional<(color: BurritoThemeColor, amount: Double)>.none
            }

            var lower = 0.0
            var upper = 1.0
            for _ in 0..<32 {
                let amount = (lower + upper) / 2
                let candidate = mixed(with: target, amount: amount)
                if backgrounds.allSatisfy({ candidate.contrastRatio(with: $0) >= minimum }) {
                    upper = amount
                } else {
                    lower = amount
                }
            }
            return (mixed(with: target, amount: upper), upper)
        }

        return candidates.min(by: { $0.amount < $1.amount })?.color ?? self
    }

    private func mixed(with other: BurritoThemeColor, amount: Double) -> BurritoThemeColor {
        BurritoThemeColor(
            red: red + ((other.red - red) * amount),
            green: green + ((other.green - green) * amount),
            blue: blue + ((other.blue - blue) * amount),
            alpha: alpha
        )
    }
}

struct BurritoAdaptiveThemeColor {
    let light: BurritoThemeColor
    let dark: BurritoThemeColor

    var color: Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? dark.nsColor
                    : light.nsColor
            }
        )
    }
}

struct BurritoThemePalette {
    let foreground: BurritoAdaptiveThemeColor
    let sidebarForeground: BurritoAdaptiveThemeColor
    let accent: BurritoAdaptiveThemeColor
    let accentForeground: BurritoAdaptiveThemeColor
    let accentSoft: BurritoAdaptiveThemeColor
    let canvas: BurritoAdaptiveThemeColor
    let sidebar: BurritoAdaptiveThemeColor
    let paper: BurritoAdaptiveThemeColor
    let raised: BurritoAdaptiveThemeColor
    let controlFill: BurritoAdaptiveThemeColor
    let softBorder: BurritoAdaptiveThemeColor
    let sage: BurritoAdaptiveThemeColor
}

enum BurritoColorTheme: String, CaseIterable, Identifiable {
    case burrito
    case modernMinimal = "modern-minimal"
    case t3Chat = "t3-chat"
    case twitter
    case mochaMousse = "mocha-mousse"
    case bubblegum
    case doom64 = "doom-64"
    case catppuccin
    case graphite
    case perpetuity
    case kodamaGrove = "kodama-grove"
    case cosmicNight = "cosmic-night"
    case tangerine
    case quantumRose = "quantum-rose"
    case nature
    case boldTech = "bold-tech"
    case elegantLuxury = "elegant-luxury"
    case amberMinimal = "amber-minimal"
    case supabase
    case neoBrutalism = "neo-brutalism"
    case solarDusk = "solar-dusk"
    case claymorphism
    case cyberpunk
    case pastelDreams = "pastel-dreams"
    case cleanSlate = "clean-slate"
    case caffeine
    case oceanBreeze = "ocean-breeze"
    case retroArcade = "retro-arcade"
    case midnightBloom = "midnight-bloom"
    case candyland
    case northernLights = "northern-lights"
    case vintagePaper = "vintage-paper"
    case sunsetHorizon = "sunset-horizon"
    case starryNight = "starry-night"
    case claude
    case vercel
    case mono

    static let storageKey = "appColorTheme"

    var id: Self { self }

    static func resolve(_ rawValue: String) -> BurritoColorTheme {
        BurritoColorTheme(rawValue: rawValue) ?? .burrito
    }
}

enum BurritoTheme {
    private static var palette: BurritoThemePalette {
        let rawValue = UserDefaults.standard.string(forKey: BurritoColorTheme.storageKey)
            ?? BurritoColorTheme.burrito.rawValue
        return BurritoColorTheme.resolve(rawValue).palette
    }

    static var foreground: Color { palette.foreground.color }
    static var sidebarForeground: Color { palette.sidebarForeground.color }
    static var accent: Color { palette.accent.color }
    static var accentForeground: Color { palette.accentForeground.color }
    static var accentSoft: Color { palette.accentSoft.color }
    static var canvas: Color { palette.canvas.color }
    static var sidebar: Color { palette.sidebar.color }
    static var paper: Color { palette.paper.color }
    static var raised: Color { palette.raised.color }
    static var controlFill: Color { palette.controlFill.color }
    static var softBorder: Color { palette.softBorder.color }
    static var sage: Color { palette.sage.color }

    static let sidebarWidth: CGFloat = 216
    static let listWidth: CGFloat = 340
    static let editorWidth: CGFloat = 760
}

enum BurritoElevation {
    case control
    case surface
    case floating
}

private struct BurritoElevationModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let elevation: BurritoElevation
    let isActive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        let metrics = shadowMetrics
        if isActive {
            content.shadow(
                color: .black.opacity(metrics.opacity),
                radius: metrics.radius,
                y: metrics.offset
            )
        } else {
            content
        }
    }

    private var shadowMetrics: (opacity: Double, radius: CGFloat, offset: CGFloat) {
        let contrastBoost = colorSchemeContrast == .increased ? 1.2 : 1
        switch (elevation, colorScheme) {
        case (.control, .light):
            return (0.07 * contrastBoost, 2.5, 1)
        case (.control, .dark):
            return (0.24 * contrastBoost, 3.5, 1.5)
        case (.surface, .light):
            return (0.09 * contrastBoost, 9, 3)
        case (.surface, .dark):
            return (0.32 * contrastBoost, 11, 4)
        case (.floating, .light):
            return (0.18 * contrastBoost, 24, 12)
        case (.floating, .dark):
            return (0.48 * contrastBoost, 28, 14)
        @unknown default:
            return (0.09 * contrastBoost, 9, 3)
        }
    }
}

extension View {
    func burritoElevation(
        _ elevation: BurritoElevation = .surface,
        isActive: Bool = true
    ) -> some View {
        modifier(BurritoElevationModifier(elevation: elevation, isActive: isActive))
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
            .burritoElevation(.control)
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
                        .fill(BurritoTheme.accentForeground)
                        .frame(width: 16, height: 16)
                        .burritoElevation(.control)
                        .padding(3)
                }
        } else {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Rectangle()
                    .fill(isOn ? BurritoTheme.accent : BurritoTheme.controlFill)
                    .frame(width: 38, height: 22)
                Rectangle()
                    .fill(BurritoTheme.accentForeground)
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
            .burritoElevation(.control, isActive: !embedded)
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
                .burritoElevation(.control)

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
            .burritoElevation(.control, isActive: selection == language.identifier)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
