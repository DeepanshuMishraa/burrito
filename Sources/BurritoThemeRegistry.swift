import SwiftUI

// Burrito's theme registry. Each entry maps an established community
// palette onto Burrito's semantic tokens using the palette's own source:
// Catppuccin (catppuccin.com), Rosé Pine (rosepinetheme.com), Kanagawa
// (github.com/rebelot/kanagawa.nvim), Tokyo Night
// (github.com/folke/tokyonight.nvim), Nord (nordtheme.com), Solarized
// (ethanschoonover.com/solarized), Gruvbox (github.com/morhetz/gruvbox),
// Dracula (draculatheme.com), One Light/Dark (github.com/atom/one-dark-
// syntax), and Vesper (github.com/raunofreiberg/vesper).
//
// Themes are fixed appearances: light and dark slots carry the theme's own
// colors, and the app forces the matching color scheme. Display accents are
// contrast-corrected for Burrito's text-and-icon usage, same as before.
extension BurritoColorTheme {
    private static let palettes = Dictionary(
        uniqueKeysWithValues: allCases.map { ($0, $0.makePalette()) }
    )

    var title: String {
        switch self {
        case .catppuccin: "Catppuccin"
        case .catppuccinLatte: "Catppuccin Latte"
        case .catppuccinMacchiato: "Catppuccin Macchiato"
        case .catppuccinMocha: "Catppuccin Mocha"
        case .dracula: "Dracula"
        case .gruvbox: "Gruvbox"
        case .gruvboxLight: "Gruvbox Light"
        case .kanagawa: "Kanagawa"
        case .kanagawaLotus: "Kanagawa Lotus"
        case .nord: "Nord"
        case .oneDark: "One Dark"
        case .oneLight: "One Light"
        case .rosePine: "Rosé Pine"
        case .rosePineDawn: "Rosé Pine Dawn"
        case .solarized: "Solarized"
        case .solarizedLight: "Solarized Light"
        case .terminal: "Terminal"
        case .tokyoNight: "Tokyo Night"
        case .tokyoNightDay: "Tokyo Night Day"
        case .vesper: "Vesper"
        }
    }

    var palette: BurritoThemePalette {
        Self.palettes[self] ?? Self.tokyoNight.makePalette()
    }

    private func makePalette() -> BurritoThemePalette {
        switch self {
        case .catppuccin, .catppuccinMocha:
            // Catppuccin's default flavor is Mocha.
            BurritoThemePalette.make(
                foreground: (0xCDD6F4, 0xCDD6F4),
                sidebarForeground: (0xBAC2DE, 0xBAC2DE),
                accent: (0xCBA6F7, 0xCBA6F7),
                accentForeground: (0x1E1E2E, 0x1E1E2E),
                accentSoft: (0x39324F, 0x39324F),
                canvas: (0x1E1E2E, 0x1E1E2E),
                sidebar: (0x181825, 0x181825),
                paper: (0x1E1E2E, 0x1E1E2E),
                raised: (0x313244, 0x313244),
                softBorder: (0x45475A, 0x45475A),
                sage: (0x94E2D5, 0x94E2D5)
            )
        case .catppuccinLatte:
            BurritoThemePalette.make(
                foreground: (0x4C4F69, 0x4C4F69),
                sidebarForeground: (0x5C5F77, 0x5C5F77),
                accent: (0x8839EF, 0x8839EF),
                accentForeground: (0xFFFFFF, 0xFFFFFF),
                accentSoft: (0xE3DBF4, 0xE3DBF4),
                canvas: (0xEFF1F5, 0xEFF1F5),
                sidebar: (0xE6E9EF, 0xE6E9EF),
                paper: (0xEFF1F5, 0xEFF1F5),
                raised: (0xCCD0DA, 0xCCD0DA),
                softBorder: (0xBCC0CC, 0xBCC0CC),
                sage: (0x179299, 0x179299)
            )
        case .catppuccinMacchiato:
            BurritoThemePalette.make(
                foreground: (0xCAD3F5, 0xCAD3F5),
                sidebarForeground: (0xB8C0E0, 0xB8C0E0),
                accent: (0xC6A0F6, 0xC6A0F6),
                accentForeground: (0x24273A, 0x24273A),
                accentSoft: (0x3A334F, 0x3A334F),
                canvas: (0x24273A, 0x24273A),
                sidebar: (0x1E2030, 0x1E2030),
                paper: (0x24273A, 0x24273A),
                raised: (0x363A4F, 0x363A4F),
                softBorder: (0x494D64, 0x494D64),
                sage: (0x8BD5CA, 0x8BD5CA)
            )
        case .dracula:
            BurritoThemePalette.make(
                foreground: (0xF8F8F2, 0xF8F8F2),
                sidebarForeground: (0x9699A3, 0x9699A3),
                accent: (0xBD93F9, 0xBD93F9),
                accentForeground: (0x191A21, 0x191A21),
                accentSoft: (0x3A2F50, 0x3A2F50),
                canvas: (0x282A36, 0x282A36),
                sidebar: (0x21222C, 0x21222C),
                paper: (0x282A36, 0x282A36),
                raised: (0x343746, 0x343746),
                softBorder: (0x44475A, 0x44475A),
                sage: (0x8BE9FD, 0x8BE9FD)
            )
        case .gruvbox:
            BurritoThemePalette.make(
                foreground: (0xEBDDB2, 0xEBDDB2),
                sidebarForeground: (0xBDAE93, 0xBDAE93),
                accent: (0xFE8019, 0xFE8019),
                accentForeground: (0x1D2021, 0x1D2021),
                accentSoft: (0x3E2F1E, 0x3E2F1E),
                canvas: (0x282828, 0x282828),
                sidebar: (0x1D2021, 0x1D2021),
                paper: (0x282828, 0x282828),
                raised: (0x3C3836, 0x3C3836),
                softBorder: (0x504945, 0x504945),
                sage: (0xB8BB26, 0xB8BB26)
            )
        case .gruvboxLight:
            BurritoThemePalette.make(
                foreground: (0x282828, 0x282828),
                sidebarForeground: (0x665C54, 0x665C54),
                accent: (0xAF3A03, 0xAF3A03),
                accentForeground: (0xFBF1C7, 0xFBF1C7),
                accentSoft: (0xF7E4C4, 0xF7E4C4),
                canvas: (0xFBF1C7, 0xFBF1C7),
                sidebar: (0xF9F5D7, 0xF9F5D7),
                paper: (0xFBF1C7, 0xFBF1C7),
                raised: (0xEBDDB2, 0xEBDDB2),
                softBorder: (0xD5C4A1, 0xD5C4A1),
                sage: (0x79740E, 0x79740E)
            )
        case .kanagawa:
            BurritoThemePalette.make(
                foreground: (0xDCD7BA, 0xDCD7BA),
                sidebarForeground: (0xC8C093, 0xC8C093),
                accent: (0x7E9CD8, 0x7E9CD8),
                accentForeground: (0x16161D, 0x16161D),
                accentSoft: (0x2B2F4B, 0x2B2F4B),
                canvas: (0x1F1F28, 0x1F1F28),
                sidebar: (0x181820, 0x181820),
                paper: (0x1F1F28, 0x1F1F28),
                raised: (0x2A2A37, 0x2A2A37),
                softBorder: (0x363646, 0x363646),
                sage: (0x76946A, 0x76946A)
            )
        case .kanagawaLotus:
            BurritoThemePalette.make(
                foreground: (0x545464, 0x545464),
                sidebarForeground: (0x545464, 0x545464),
                accent: (0x5D57A3, 0x5D57A3),
                accentForeground: (0xF2ECBC, 0xF2ECBC),
                accentSoft: (0xE9E4C6, 0xE9E4C6),
                canvas: (0xF2ECBC, 0xF2ECBC),
                sidebar: (0xDCD5AC, 0xDCD5AC),
                paper: (0xF2ECBC, 0xF2ECBC),
                raised: (0xE5DDB0, 0xE5DDB0),
                softBorder: (0xD5CEA3, 0xD5CEA3),
                sage: (0x6F894E, 0x6F894E)
            )
        case .nord:
            BurritoThemePalette.make(
                foreground: (0xD8DEE9, 0xD8DEE9),
                sidebarForeground: (0xD8DEE9, 0xD8DEE9),
                accent: (0x88C0D0, 0x88C0D0),
                accentForeground: (0x1A2433, 0x1A2433),
                accentSoft: (0x2E3A4C, 0x2E3A4C),
                canvas: (0x2E3440, 0x2E3440),
                sidebar: (0x3B4252, 0x3B4252),
                paper: (0x2E3440, 0x2E3440),
                raised: (0x3B4252, 0x3B4252),
                softBorder: (0x4C566A, 0x4C566A),
                sage: (0x81A1C1, 0x81A1C1)
            )
        case .oneDark:
            BurritoThemePalette.make(
                foreground: (0xABB2BF, 0xABB2BF),
                sidebarForeground: (0xABB2BF, 0xABB2BF),
                accent: (0x61AFEF, 0x61AFEF),
                accentForeground: (0x0D1B2A, 0x0D1B2A),
                accentSoft: (0x2E3949, 0x2E3949),
                canvas: (0x282C34, 0x282C34),
                sidebar: (0x21252B, 0x21252B),
                paper: (0x282C34, 0x282C34),
                raised: (0x2C313A, 0x2C313A),
                softBorder: (0x3E4451, 0x3E4451),
                sage: (0x98C379, 0x98C379)
            )
        case .oneLight:
            BurritoThemePalette.make(
                foreground: (0x383A42, 0x383A42),
                sidebarForeground: (0x383A42, 0x383A42),
                accent: (0x4078F2, 0x4078F2),
                accentForeground: (0x000000, 0x000000),
                accentSoft: (0xE2E4F8, 0xE2E4F8),
                canvas: (0xFAFAFA, 0xFAFAFA),
                sidebar: (0xF5F5F5, 0xF5F5F5),
                paper: (0xFAFAFA, 0xFAFAFA),
                raised: (0xF0F0F0, 0xF0F0F0),
                softBorder: (0xDFE1E5, 0xDFE1E5),
                sage: (0x50A14F, 0x50A14F)
            )
        case .rosePine:
            BurritoThemePalette.make(
                foreground: (0xE0DEF4, 0xE0DEF4),
                sidebarForeground: (0x908CAA, 0x908CAA),
                accent: (0xC4A7E7, 0xC4A7E7),
                accentForeground: (0x191724, 0x191724),
                accentSoft: (0x342F4D, 0x342F4D),
                canvas: (0x191724, 0x191724),
                sidebar: (0x1F1D2E, 0x1F1D2E),
                paper: (0x191724, 0x191724),
                raised: (0x26233A, 0x26233A),
                softBorder: (0x403D52, 0x403D52),
                sage: (0x9CCFD8, 0x9CCFD8)
            )
        case .rosePineDawn:
            BurritoThemePalette.make(
                foreground: (0x575279, 0x575279),
                sidebarForeground: (0x797593, 0x797593),
                accent: (0x907AA9, 0x907AA9),
                accentForeground: (0xFAF4ED, 0xFAF4ED),
                accentSoft: (0xE9E1E4, 0xE9E1E4),
                canvas: (0xFAF4ED, 0xFAF4ED),
                sidebar: (0xFFFAF3, 0xFFFAF3),
                paper: (0xFAF4ED, 0xFAF4ED),
                raised: (0xF2E9E1, 0xF2E9E1),
                softBorder: (0xDFDAD9, 0xDFDAD9),
                sage: (0x56949F, 0x56949F)
            )
        case .solarized:
            BurritoThemePalette.make(
                foreground: (0x839496, 0x839496),
                sidebarForeground: (0x93A1A1, 0x93A1A1),
                accent: (0x268BD2, 0x268BD2),
                accentForeground: (0x002B36, 0x002B36),
                accentSoft: (0x053E52, 0x053E52),
                canvas: (0x002B36, 0x002B36),
                sidebar: (0x073642, 0x073642),
                paper: (0x002B36, 0x002B36),
                raised: (0x073642, 0x073642),
                softBorder: (0x586E75, 0x586E75),
                sage: (0x2AA198, 0x2AA198)
            )
        case .solarizedLight:
            BurritoThemePalette.make(
                foreground: (0x657B83, 0x657B83),
                sidebarForeground: (0x839496, 0x839496),
                accent: (0x268BD2, 0x268BD2),
                accentForeground: (0xFDF6E3, 0xFDF6E3),
                accentSoft: (0xE5E1E1, 0xE5E1E1),
                canvas: (0xFDF6E3, 0xFDF6E3),
                sidebar: (0xEEE8D5, 0xEEE8D5),
                paper: (0xFDF6E3, 0xFDF6E3),
                raised: (0xEEE8D5, 0xEEE8D5),
                softBorder: (0x93A1A1, 0x93A1A1),
                sage: (0x859900, 0x859900)
            )
        case .terminal:
            BurritoThemePalette.make(
                foreground: (0xE4E4E4, 0xE4E4E4),
                sidebarForeground: (0x9E9E9E, 0x9E9E9E),
                accent: (0x33D17A, 0x33D17A),
                accentForeground: (0x04140A, 0x04140A),
                accentSoft: (0x12281D, 0x12281D),
                canvas: (0x0D0D0D, 0x0D0D0D),
                sidebar: (0x0A0A0A, 0x0A0A0A),
                paper: (0x151515, 0x151515),
                raised: (0x1C1C1C, 0x1C1C1C),
                softBorder: (0x2E2E2E, 0x2E2E2E),
                sage: (0xFFD866, 0xFFD866)
            )
        case .tokyoNight:
            BurritoThemePalette.make(
                foreground: (0xC0CAF5, 0xC0CAF5),
                sidebarForeground: (0xA9B1D6, 0xA9B1D6),
                accent: (0x7AA2F7, 0x7AA2F7),
                accentForeground: (0x16161E, 0x16161E),
                accentSoft: (0x2D324C, 0x2D324C),
                canvas: (0x1A1B26, 0x1A1B26),
                sidebar: (0x16161E, 0x16161E),
                paper: (0x1A1B26, 0x1A1B26),
                raised: (0x292E42, 0x292E42),
                softBorder: (0x3B4261, 0x3B4261),
                sage: (0x7DCFFF, 0x7DCFFF)
            )
        case .tokyoNightDay:
            BurritoThemePalette.make(
                foreground: (0x3760BF, 0x3760BF),
                sidebarForeground: (0x6172A9, 0x6172A9),
                accent: (0x2E7DE9, 0x2E7DE9),
                accentForeground: (0x0A1120, 0x0A1120),
                accentSoft: (0xC8D1E7, 0xC8D1E7),
                canvas: (0xE1E2E7, 0xE1E2E7),
                sidebar: (0xD6D7DD, 0xD6D7DD),
                paper: (0xE1E2E7, 0xE1E2E7),
                raised: (0xF4F4F4, 0xF4F4F4),
                softBorder: (0xA1A6C5, 0xA1A6C5),
                sage: (0x587539, 0x587539)
            )
        case .vesper:
            BurritoThemePalette.make(
                foreground: (0xFFFFFF, 0xFFFFFF),
                sidebarForeground: (0xA0A0A0, 0xA0A0A0),
                accent: (0xFFC799, 0xFFC799),
                accentForeground: (0x000000, 0x000000),
                accentSoft: (0x2D251F, 0x2D251F),
                canvas: (0x101010, 0x101010),
                sidebar: (0x0C0C0C, 0x0C0C0C),
                paper: (0x101010, 0x101010),
                raised: (0x161616, 0x161616),
                softBorder: (0x282828, 0x282828),
                sage: (0x99FFE4, 0x99FFE4)
            )
        }
    }

    var previewColors: [Color] {
        let palette = palette
        return [palette.accent.color, palette.canvas.color, palette.paper.color]
    }
}

private struct BurritoResolvedPalette {
    let foreground: BurritoThemeColor
    let sidebarForeground: BurritoThemeColor
    let accent: BurritoThemeColor
    let accentForeground: BurritoThemeColor
    let accentSoft: BurritoThemeColor
    let canvas: BurritoThemeColor
    let sidebar: BurritoThemeColor
    let paper: BurritoThemeColor
    let raised: BurritoThemeColor
    let controlFill: BurritoThemeColor
    let controlForeground: BurritoThemeColor
    let softBorder: BurritoThemeColor
    let sage: BurritoThemeColor
}

extension BurritoThemePalette {
    static func make(
        foreground: (light: UInt32, dark: UInt32),
        sidebarForeground: (light: UInt32, dark: UInt32),
        accent: (light: UInt32, dark: UInt32),
        accentForeground: (light: UInt32, dark: UInt32),
        accentSoft: (light: UInt32, dark: UInt32),
        canvas: (light: UInt32, dark: UInt32),
        sidebar: (light: UInt32, dark: UInt32),
        paper: (light: UInt32, dark: UInt32),
        raised: (light: UInt32, dark: UInt32),
        softBorder: (light: UInt32, dark: UInt32),
        sage: (light: UInt32, dark: UInt32)
    ) -> BurritoThemePalette {
        func resolve(isDark: Bool) -> BurritoResolvedPalette {
            func color(_ values: (light: UInt32, dark: UInt32)) -> BurritoThemeColor {
                .rgb(isDark ? values.dark : values.light)
            }

            let canvasColor = color(canvas)
            let sidebarColor = color(sidebar)
            let paperColor = color(paper)
            let raisedColor = color(raised)
            let contentSurfaces = [canvasColor, paperColor, raisedColor]
            let foregroundColor = color(foreground).ensuringContrast(
                against: contentSurfaces,
                minimum: 7.05
            )
            let controlFillColor = BurritoThemeColor(
                red: foregroundColor.red,
                green: foregroundColor.green,
                blue: foregroundColor.blue,
                alpha: isDark ? 0.085 : 0.05
            )
            let controlSurfaces = contentSurfaces.map { controlFillColor.composited(over: $0) }
            let accentSoftColor = color(accentSoft)
            let accentColor = color(accent).ensuringContrast(
                against: contentSurfaces + [sidebarColor, accentSoftColor],
                minimum: 4.55
            )
            let registryBorderColor = color(softBorder)
            let borderTintWeight = 0.65
            let softBorderColor = BurritoThemeColor(
                red: foregroundColor.red * (1 - borderTintWeight)
                    + registryBorderColor.red * borderTintWeight,
                green: foregroundColor.green * (1 - borderTintWeight)
                    + registryBorderColor.green * borderTintWeight,
                blue: foregroundColor.blue * (1 - borderTintWeight)
                    + registryBorderColor.blue * borderTintWeight,
                alpha: isDark ? 0.16 : 0.12
            )

            return BurritoResolvedPalette(
                foreground: foregroundColor,
                sidebarForeground: color(sidebarForeground).ensuringContrast(
                    against: [sidebarColor],
                    minimum: 7.05
                ),
                accent: accentColor,
                accentForeground: color(accentForeground).ensuringContrast(
                    against: [accentColor],
                    minimum: 4.55
                ),
                accentSoft: accentSoftColor,
                canvas: canvasColor,
                sidebar: sidebarColor,
                paper: paperColor,
                raised: raisedColor,
                controlFill: controlFillColor,
                controlForeground: foregroundColor.ensuringContrast(
                    against: controlSurfaces,
                    minimum: 4.55
                ),
                softBorder: softBorderColor,
                sage: color(sage).ensuringContrast(
                    against: contentSurfaces,
                    minimum: 4.55
                )
            )
        }

        let light = resolve(isDark: false)
        let dark = resolve(isDark: true)

        return BurritoThemePalette(
            foreground: adaptive(light.foreground, dark.foreground),
            sidebarForeground: adaptive(light.sidebarForeground, dark.sidebarForeground),
            accent: adaptive(light.accent, dark.accent),
            accentForeground: adaptive(light.accentForeground, dark.accentForeground),
            accentSoft: adaptive(light.accentSoft, dark.accentSoft),
            canvas: adaptive(light.canvas, dark.canvas),
            sidebar: adaptive(light.sidebar, dark.sidebar),
            paper: adaptive(light.paper, dark.paper),
            raised: adaptive(light.raised, dark.raised),
            controlFill: adaptive(light.controlFill, dark.controlFill),
            controlForeground: adaptive(light.controlForeground, dark.controlForeground),
            softBorder: adaptive(light.softBorder, dark.softBorder),
            sage: adaptive(light.sage, dark.sage)
        )
    }

    private static func adaptive(
        _ light: BurritoThemeColor,
        _ dark: BurritoThemeColor
    ) -> BurritoAdaptiveThemeColor {
        BurritoAdaptiveThemeColor(
            light: light,
            dark: dark
        )
    }
}
