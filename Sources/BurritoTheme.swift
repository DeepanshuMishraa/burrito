import AppKit
import Observation
import OSLog
import SwiftUI

enum BurritoFontCategory: String, CaseIterable, Identifiable {
    case apple = "APPLE"
    case mono = "MONO"
    case sans = "SANS"
    case serif = "SERIF"

    var id: Self { self }

    var title: String {
        switch self {
        case .apple: "Apple"
        case .mono: "Mono"
        case .sans: "Sans"
        case .serif: "Serif"
        }
    }
}

enum BurritoInterfaceFontSize {
    static let storageKey = "interfaceFontSize"
    static let minimum = 8
    static let standard = 13
    static let maximum = 18

    static func resolve(_ value: Int) -> Int {
        min(maximum, max(minimum, value))
    }

    static func scale(for value: Int) -> CGFloat {
        CGFloat(resolve(value)) / CGFloat(standard)
    }
}

@MainActor
enum BurritoFontSmoothing {
    static let storageKey = "fontSmoothing"
    private static let renderingPreferenceKey = "CGFontRenderingFontSmoothingDisabled"

    static func apply(_ usesThinGrayscaleRendering: Bool, defaults: UserDefaults = .standard) {
        if usesThinGrayscaleRendering {
            defaults.set(true, forKey: renderingPreferenceKey)
        } else {
            defaults.removeObject(forKey: renderingPreferenceKey)
        }

    }
}

enum BurritoFontChoice: String, CaseIterable, Identifiable {
    case burritoDefault = "burrito-default"
    case systemSans = "system-sans"
    case systemRounded = "system-rounded"
    case systemMono = "system-mono"
    case systemSerif = "system-serif"
    case geistMono = "geist-mono"
    case jetBrainsMono = "jetbrains-mono"
    case ibmPlexMono = "ibm-plex-mono"
    case geistSans = "geist-sans"
    case inter
    case ibmPlexSans = "ibm-plex-sans"
    case sourceSerif = "source-serif-4"

    static let storageKey = "appFont"

    var id: Self { self }

    @MainActor static var selected: BurritoFontChoice { BurritoStyleStore.shared.font }

    static func resolve(_ rawValue: String) -> BurritoFontChoice {
        BurritoFontChoice(rawValue: rawValue) ?? .burritoDefault
    }

    var title: String {
        switch self {
        case .burritoDefault: "Default"
        case .systemSans: "SF Pro"
        case .systemRounded: "SF Pro Rounded"
        case .systemMono: "SF Mono"
        case .systemSerif: "New York"
        case .geistMono: "Geist Mono"
        case .jetBrainsMono: "JetBrains Mono"
        case .ibmPlexMono: "IBM Plex Mono"
        case .geistSans: "Geist Sans"
        case .inter: "Inter"
        case .ibmPlexSans: "IBM Plex Sans"
        case .sourceSerif: "Source Serif 4"
        }
    }

    var category: BurritoFontCategory {
        switch self {
        case .systemSans, .systemRounded, .systemMono, .systemSerif: .apple
        case .burritoDefault, .geistMono, .jetBrainsMono, .ibmPlexMono: .mono
        case .geistSans, .inter, .ibmPlexSans: .sans
        case .sourceSerif: .serif
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
        case .systemSans, .systemRounded, .systemMono, .systemSerif:
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
        case .systemSans, .systemRounded, .systemMono, .systemSerif: []
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
        case .systemSans, .systemRounded, .systemMono, .systemSerif: ""
        }
    }

    private var systemDesign: Font.Design? {
        switch self {
        case .systemSans: .default
        case .systemRounded: .rounded
        case .systemMono: .monospaced
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
        case .systemSans, .systemRounded, .systemMono, .systemSerif:
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
    private static let logger = Logger(subsystem: "com.local.burrito", category: "Fonts")

    nonisolated static func registerFontsIfNeeded() {
        registrationLock.lock()
        defer { registrationLock.unlock() }

        guard !hasRegistered else { return }
        hasRegistered = true

        let fontNames = BurritoFontChoice.allCases.flatMap(\.resourceFileNames)

        for fontName in fontNames {
            guard let fontURL = Bundle.main.url(forResource: fontName, withExtension: nil) ??
                    Bundle.main.url(forResource: fontName, withExtension: nil, subdirectory: "Fonts")
            else {
                logger.error("Unable to register font \(fontName, privacy: .public): resource was not found in the app bundle.")
                continue
            }

            var registrationError: Unmanaged<CFError>?
            guard CTFontManagerRegisterFontsForURL(
                fontURL as CFURL,
                .process,
                &registrationError
            ) else {
                let errorDescription = registrationError?
                    .takeRetainedValue()
                    .localizedDescription ?? "Core Text did not provide an error."
                logger.error("Unable to register font \(fontName, privacy: .public): \(errorDescription, privacy: .public)")
                continue
            }
        }
    }
}

extension Font {
    @MainActor
    static func burritoDisplay(
        size: CGFloat,
        weight: Font.Weight = .regular
    ) -> Font {
        BurritoFontChoice.selected.font(
            size: BurritoStyleStore.shared.scaledFontSize(size),
            weight: weight
        )
    }

    @MainActor static func burritoDisplay(size: CGFloat, weight: CGFloat) -> Font {
        burritoUI(size: size, weight: weight)
    }

    @MainActor
    static func burritoUI(
        size: CGFloat,
        weight: Font.Weight = .regular
    ) -> Font {
        BurritoFontChoice.selected.font(
            size: BurritoStyleStore.shared.scaledFontSize(size),
            weight: weight
        )
    }

    @MainActor static func burritoUI(size: CGFloat, weight: CGFloat) -> Font {
        BurritoFontChoice.selected.font(
            size: BurritoStyleStore.shared.scaledFontSize(size),
            weight: weight
        )
    }

    @MainActor
    static func burritoUI(
        size: CGFloat,
        weight: Font.Weight = .regular,
        relativeTo textStyle: Font.TextStyle
    ) -> Font {
        BurritoFontChoice.selected.font(
            size: BurritoStyleStore.shared.scaledFontSize(size),
            weight: weight,
            relativeTo: textStyle
        )
    }

    @MainActor
    static func burritoUI(
        size: CGFloat,
        weight: CGFloat,
        relativeTo textStyle: Font.TextStyle
    ) -> Font {
        BurritoFontChoice.selected.font(
            size: BurritoFontMetrics.scaledSize(
                BurritoStyleStore.shared.scaledFontSize(size),
                relativeTo: textStyle
            ),
            weight: weight
        )
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

struct BurritoThemeColor: Hashable, Sendable {
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
            srgbRed: red,
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

    func composited(over background: BurritoThemeColor) -> BurritoThemeColor {
        let outputAlpha = alpha + (background.alpha * (1 - alpha))
        guard outputAlpha > 0 else { return .rgb(0x000000, alpha: 0) }

        return BurritoThemeColor(
            red: ((red * alpha) + (background.red * background.alpha * (1 - alpha))) / outputAlpha,
            green: ((green * alpha) + (background.green * background.alpha * (1 - alpha))) / outputAlpha,
            blue: ((blue * alpha) + (background.blue * background.alpha * (1 - alpha))) / outputAlpha,
            alpha: outputAlpha
        )
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

struct BurritoAdaptiveThemeColor: Sendable {
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

struct BurritoThemePalette: Sendable {
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
    let controlForeground: BurritoAdaptiveThemeColor
    let softBorder: BurritoAdaptiveThemeColor
    let sage: BurritoAdaptiveThemeColor
}

enum BurritoColorTheme: String, CaseIterable, Identifiable, Sendable {
    case catppuccin
    case catppuccinLatte = "catppuccin-latte"
    case catppuccinMacchiato = "catppuccin-macchiato"
    case dracula
    case gruvbox
    case gruvboxLight = "gruvbox-light"
    case kanagawa
    case kanagawaLotus = "kanagawa-lotus"
    case nord
    case oneDark = "one-dark"
    case oneLight = "one-light"
    case rosePine = "rose-pine"
    case rosePineDawn = "rose-pine-dawn"
    case solarized
    case solarizedLight = "solarized-light"
    case terminal
    case tokyoNight = "tokyo-night"
    case tokyoNightDay = "tokyo-night-day"
    case vesper

    static let storageKey = "appColorTheme"

    var id: Self { self }

    /// Themes are fixed appearances: the app forces the matching color
    /// scheme so native controls render on the theme's own palette instead
    /// of following the system's light/dark setting.
    var isDark: Bool {
        switch self {
        case .catppuccin, .catppuccinMacchiato,
             .dracula, .gruvbox, .kanagawa, .nord, .oneDark,
             .rosePine, .solarized, .terminal, .tokyoNight, .vesper:
            true
        case .catppuccinLatte, .gruvboxLight, .kanagawaLotus,
             .oneLight, .rosePineDawn, .solarizedLight, .tokyoNightDay:
            false
        }
    }

    static func resolve(_ rawValue: String) -> BurritoColorTheme {
        if let theme = BurritoColorTheme(rawValue: rawValue) {
            return theme
        }
        if let migrated = migratedValue(from: rawValue),
           let theme = BurritoColorTheme(rawValue: migrated) {
            return theme
        }
        return .tokyoNight
    }

    /// Maps a persisted raw value from the pre-curation 39-theme set to a
    /// curated equivalent, so returning users keep a theme close to their
    /// previous selection instead of silently landing on the new default.
    /// Themes whose raw value still exists (e.g. "catppuccin") resolve
    /// directly and never pass through here.
    static let legacyMigrationMap: [String: String] = [
        "burrito": "gruvbox-light",
        "modern-minimal": "one-light",
        "t3-chat": "rose-pine-dawn",
        "twitter": "one-light",
        "mocha-mousse": "gruvbox-light",
        "bubblegum": "rose-pine-dawn",
        "doom-64": "dracula",
        "graphite": "vesper",
        "perpetuity": "solarized",
        "kodama-grove": "gruvbox",
        "cosmic-night": "tokyo-night",
        "tangerine": "tokyo-night",
        "quantum-rose": "rose-pine",
        "nature": "gruvbox",
        "bold-tech": "tokyo-night",
        "elegant-luxury": "vesper",
        "amber-minimal": "gruvbox-light",
        "supabase": "one-dark",
        "neo-brutalism": "terminal",
        "solar-dusk": "gruvbox",
        "claymorphism": "nord",
        "cyberpunk": "tokyo-night",
        "pastel-dreams": "rose-pine-dawn",
        "clean-slate": "one-light",
        "caffeine": "gruvbox",
        "ocean-breeze": "nord",
        "retro-arcade": "tokyo-night",
        "midnight-bloom": "tokyo-night",
        "candyland": "rose-pine",
        "northern-lights": "nord",
        "vintage-paper": "gruvbox-light",
        "sunset-horizon": "rose-pine-dawn",
        "starry-night": "tokyo-night",
        "claude": "vesper",
        "vercel": "terminal",
        "mono": "one-dark",
        // The duplicate catppuccin-mocha entry shipped only on the
        // pre-release branch; fold any persisted selection into the base
        // Catppuccin theme (which is Mocha).
        "catppuccin-mocha": "catppuccin",
    ]

    static func migratedValue(from rawValue: String) -> String? {
        legacyMigrationMap[rawValue]
    }
}

@MainActor
@Observable
final class BurritoStyleStore {
    static let shared = BurritoStyleStore()

    private(set) var theme: BurritoColorTheme
    private(set) var font: BurritoFontChoice
    private(set) var interfaceFontSize: Int
    private(set) var palette: BurritoThemePalette

    /// Each theme is a fixed appearance; the app forces this scheme so
    /// native controls render on the theme's palette.
    var colorScheme: ColorScheme {
        theme.isDark ? .dark : .light
    }

    private init(defaults: UserDefaults = .standard) {
        // One-time migration: a persisted pre-curation theme value is
        // rewritten as its curated equivalent so the settings UI shows the
        // theme the user actually gets.
        if let stored = defaults.string(forKey: BurritoColorTheme.storageKey),
           let migrated = BurritoColorTheme.migratedValue(from: stored) {
            defaults.set(migrated, forKey: BurritoColorTheme.storageKey)
        }
        let theme = BurritoColorTheme.resolve(
            defaults.string(forKey: BurritoColorTheme.storageKey)
                ?? BurritoColorTheme.tokyoNight.rawValue
        )
        self.theme = theme
        font = BurritoFontChoice.resolve(
            defaults.string(forKey: BurritoFontChoice.storageKey)
                ?? BurritoFontChoice.burritoDefault.rawValue
        )
        let storedInterfaceFontSize = defaults.object(
            forKey: BurritoInterfaceFontSize.storageKey
        ) as? Int ?? BurritoInterfaceFontSize.standard
        interfaceFontSize = BurritoInterfaceFontSize.resolve(storedInterfaceFontSize)
        palette = theme.palette
    }

    func selectTheme(_ rawValue: String) {
        let resolved = BurritoColorTheme.resolve(rawValue)
        guard resolved != theme else { return }
        theme = resolved
        palette = resolved.palette
    }

    func selectFont(_ rawValue: String) {
        let resolved = BurritoFontChoice.resolve(rawValue)
        guard resolved != font else { return }
        font = resolved
    }

    func selectInterfaceFontSize(_ rawValue: Int) {
        let resolved = BurritoInterfaceFontSize.resolve(rawValue)
        guard resolved != interfaceFontSize else { return }
        interfaceFontSize = resolved
    }

    func scaledFontSize(_ size: CGFloat) -> CGFloat {
        size * BurritoInterfaceFontSize.scale(for: interfaceFontSize)
    }
}

@MainActor
enum BurritoTheme {
    private static var palette: BurritoThemePalette { BurritoStyleStore.shared.palette }

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
    static var controlForeground: Color { palette.controlForeground.color }
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
        if isActive {
            let (key, ambient) = shadowLayers
            content
                .shadow(
                    color: .black.opacity(key.opacity),
                    radius: key.radius,
                    x: 0,
                    y: key.offset
                )
                .shadow(
                    color: .black.opacity(ambient.opacity),
                    radius: ambient.radius,
                    x: 0,
                    y: ambient.offset
                )
        } else {
            content
        }
    }

    private typealias ShadowLayer = (opacity: Double, radius: CGFloat, offset: CGFloat)

    private var shadowLayers: (key: ShadowLayer, ambient: ShadowLayer) {
        let contrastBoost = colorSchemeContrast == .increased ? 1.25 : 1.0
        let isDark = colorScheme == .dark

        switch elevation {
        case .control:
            let key: ShadowLayer = (isDark ? 0.10 * contrastBoost : 0.03 * contrastBoost, 1.5, 0.5)
            let ambient: ShadowLayer = (isDark ? 0.16 * contrastBoost : 0.05 * contrastBoost, 4, 1.5)
            return (key, ambient)
        case .surface:
            let key: ShadowLayer = (isDark ? 0.14 * contrastBoost : 0.04 * contrastBoost, 2.5, 1)
            let ambient: ShadowLayer = (isDark ? 0.22 * contrastBoost : 0.07 * contrastBoost, 12, 5)
            return (key, ambient)
        case .floating:
            let key: ShadowLayer = (isDark ? 0.18 * contrastBoost : 0.06 * contrastBoost, 5, 2)
            let ambient: ShadowLayer = (isDark ? 0.28 * contrastBoost : 0.11 * contrastBoost, 28, 12)
            return (key, ambient)
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
            .font(.burritoUI(size: 10, weight: 450))
            .tracking(0.7)
            .foregroundStyle(.tertiary)
    }
}

struct BurritoPill: View {
    let title: String
    let systemImage: String

    var body: some View {
        BurritoLabel(title, systemImage: systemImage)
            .font(.burritoUI(size: 11, weight: .regular, relativeTo: .caption))
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
    let symbol: String?
    @Binding var isOn: Bool
    let style: Style

    init(
        title: String,
        subtitle: String,
        symbol: String? = nil,
        isOn: Binding<Bool>,
        style: Style = .standard
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
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
                if let symbol {
                    BurritoIcon(name: symbol, size: 14)
                        .foregroundStyle(BurritoTheme.accent)
                        .frame(width: 28, height: 28)
                        .background(BurritoTheme.accentSoft, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }

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
            .padding(.horizontal, style == .settingsForm ? 16 : 14)
            .padding(.vertical, style == .settingsForm ? 12 : 0)
            .frame(height: style == .standard ? 58 : nil)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "On" : "Off")
    }

    private var titleFont: Font {
        .burritoUI(size: 13, weight: 450)
    }

    private var subtitleFont: Font {
        .burritoUI(size: 11, weight: .regular, relativeTo: .caption)
    }

    @ViewBuilder
    private var switchControl: some View {
        if style == .settingsForm {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isOn ? BurritoTheme.accent : BurritoTheme.controlFill)
                .frame(width: 40, height: 22)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isOn ? BurritoTheme.accentForeground : BurritoTheme.controlForeground)
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
                    .fill(isOn ? BurritoTheme.accentForeground : BurritoTheme.controlForeground)
                    .frame(width: 16, height: 16)
                    .padding(3)
            }
        }
    }
}

final class BurritoThinScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool {
        self == BurritoThinScroller.self
    }

    override class func scrollerWidth(
        for controlSize: NSControl.ControlSize,
        scrollerStyle: NSScroller.Style
    ) -> CGFloat {
        4
    }
}

private struct BurritoThinScrollerConfigurator: NSViewRepresentable {
    final class ProbeView: NSView {
        private var isConfigurationScheduled = false
        private var hasConfiguredScrollViews = false

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            hasConfiguredScrollViews = false
            scheduleConfiguration()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            hasConfiguredScrollViews = false
            scheduleConfiguration()
        }

        override func layout() {
            super.layout()
            guard !hasConfiguredScrollViews else { return }
            configureScrollViews()
        }

        func scheduleConfiguration() {
            guard !isConfigurationScheduled else { return }
            isConfigurationScheduled = true
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.configureScrollViews()
                try? await Task.sleep(for: .milliseconds(100))
                self?.configureScrollViews()
                try? await Task.sleep(for: .milliseconds(400))
                self?.configureScrollViews()
                self?.isConfigurationScheduled = false
            }
        }

        func configureScrollViews() {
            if let contentView = window?.contentView {
                hasConfiguredScrollViews = configureScrollViews(in: contentView)
                return
            }

            var ancestor = superview
            while let view = ancestor {
                if let scrollView = view as? NSScrollView {
                    configure(scrollView)
                    hasConfiguredScrollViews = true
                    return
                }
                ancestor = view.superview
            }
        }

        private func configureScrollViews(in view: NSView) -> Bool {
            var foundScrollView = false
            if let scrollView = view as? NSScrollView {
                configure(scrollView)
                foundScrollView = true
            }
            for subview in view.subviews {
                foundScrollView = configureScrollViews(in: subview) || foundScrollView
            }
            return foundScrollView
        }

        private func configure(_ scrollView: NSScrollView) {
            scrollView.scrollerStyle = .overlay
            scrollView.autohidesScrollers = true

            if scrollView.hasVerticalScroller,
               !(scrollView.verticalScroller is BurritoThinScroller) {
                let existingScroller = scrollView.verticalScroller
                let scroller = BurritoThinScroller(frame: .zero)
                scroller.controlSize = .mini
                scroller.isHidden = existingScroller?.isHidden ?? false
                scroller.alphaValue = existingScroller?.alphaValue ?? 1
                scrollView.verticalScroller = scroller
            }

            if scrollView.hasHorizontalScroller,
               !(scrollView.horizontalScroller is BurritoThinScroller) {
                let existingScroller = scrollView.horizontalScroller
                let scroller = BurritoThinScroller(frame: .zero)
                scroller.controlSize = .mini
                scroller.isHidden = existingScroller?.isHidden ?? false
                scroller.alphaValue = existingScroller?.alphaValue ?? 1
                scrollView.horizontalScroller = scroller
            }
        }
    }

    func makeNSView(context: Context) -> ProbeView {
        ProbeView()
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        nsView.scheduleConfiguration()
    }
}

extension View {
    func burritoThinScrollers() -> some View {
        background {
            BurritoThinScrollerConfigurator()
                .frame(width: 0, height: 0)
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
                        .font(.burritoUI(size: 13, weight: 450))
                        .foregroundStyle(.primary)
                }

                Spacer()

                Text(selectedLanguage.compactTitle)
                    .font(.burritoUI(size: 12, weight: .regular))
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
                    .font(.burritoUI(size: 12, weight: .regular))
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
