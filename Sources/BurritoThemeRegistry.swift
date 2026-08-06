import SwiftUI

// Adapted from the tweakcn theme registry's semantic color tokens.
// Display accents are contrast-corrected for Burrito's text-and-icon usage.
// https://github.com/jnsahaj/tweakcn/blob/main/public/r/registry.json
extension BurritoColorTheme {
    private static let palettes = Dictionary(
        uniqueKeysWithValues: allCases.map { ($0, $0.makePalette()) }
    )

    var title: String {
        switch self {
        case .burrito: "Burrito"
        case .modernMinimal: "Modern Minimal"
        case .t3Chat: "T3 Chat"
        case .twitter: "Twitter"
        case .mochaMousse: "Mocha Mousse"
        case .bubblegum: "Bubblegum"
        case .doom64: "Doom 64"
        case .catppuccin: "Catppuccin"
        case .graphite: "Graphite"
        case .perpetuity: "Perpetuity"
        case .kodamaGrove: "Kodama Grove"
        case .cosmicNight: "Cosmic Night"
        case .tangerine: "Tangerine"
        case .quantumRose: "Quantum Rose"
        case .nature: "Nature"
        case .boldTech: "Bold Tech"
        case .elegantLuxury: "Elegant Luxury"
        case .amberMinimal: "Amber Minimal"
        case .supabase: "Supabase"
        case .neoBrutalism: "Neo Brutalism"
        case .solarDusk: "Solar Dusk"
        case .claymorphism: "Claymorphism"
        case .cyberpunk: "Cyberpunk"
        case .pastelDreams: "Pastel Dreams"
        case .cleanSlate: "Clean Slate"
        case .caffeine: "Caffeine"
        case .oceanBreeze: "Ocean Breeze"
        case .retroArcade: "Retro Arcade"
        case .midnightBloom: "Midnight Bloom"
        case .candyland: "Candyland"
        case .northernLights: "Northern Lights"
        case .vintagePaper: "Vintage Paper"
        case .sunsetHorizon: "Sunset Horizon"
        case .starryNight: "Starry Night"
        case .claude: "Claude"
        case .vercel: "Vercel"
        case .mono: "Mono"
        }
    }

    var palette: BurritoThemePalette {
        Self.palettes[self] ?? Self.burrito.makePalette()
    }

    private func makePalette() -> BurritoThemePalette {
        switch self {
        case .burrito:
            BurritoThemePalette.make(
                foreground: (0x2D251F, 0xF2EEE9),
                sidebarForeground: (0x2D251F, 0xF2EEE9),
                accent: (0xB94016, 0xFF6E33),
                accentForeground: (0xFFFFFF, 0x2B160F),
                accentSoft: (0xEFE7DD, 0x452E24),
                canvas: (0xF2F0E8, 0x252321),
                sidebar: (0xEBE8E0, 0x1D1C1B),
                paper: (0xF7F5ED, 0x2B2A27),
                raised: (0xFCFBF6, 0x343330),
                softBorder: (0xDAD8D2, 0x4A4844),
                sage: (0x4E765D, 0x82AD8F)
            )
        case .modernMinimal:
            BurritoThemePalette.make(
                foreground: (0x333333, 0xE4E4E4),
                sidebarForeground: (0x333333, 0xE4E4E4),
                accent: (0x3170D5, 0x488AF7),
                accentForeground: (0xFFFFFF, 0x262626),
                accentSoft: (0xF6F9FD, 0x1D2736),
                canvas: (0xFFFFFF, 0x161616),
                sidebar: (0xF8F8F8, 0x161616),
                paper: (0xFFFFFF, 0x262626),
                raised: (0xFFFFFF, 0x262626),
                softBorder: (0xE4E8EF, 0x404040),
                sage: (0x2463EF, 0x488AF7)
            )
        case .t3Chat:
            BurritoThemePalette.make(
                foreground: (0x521856, 0xD2C4DF),
                sidebarForeground: (0x941259, 0xE0CAD6),
                accent: (0xA74370, 0xCD719B),
                accentForeground: (0xFFFFFF, 0x2F262A),
                accentSoft: (0xF1E0EA, 0x312431),
                canvas: (0xFCF6FC, 0x221D27),
                sidebar: (0xF5E5F8, 0x191118),
                paper: (0xFCF6FC, 0x2B2631),
                raised: (0xFFFFFF, 0x0E0A0D),
                softBorder: (0xEFBFEB, 0x3D3138),
                sage: (0x6B07BA, 0xAD78D7)
            )
        case .twitter:
            BurritoThemePalette.make(
                foreground: (0x101418, 0xE8E8E8),
                sidebarForeground: (0x101418, 0xDBDBDB),
                accent: (0x1778B8, 0x1E9CF0),
                accentForeground: (0xFFFFFF, 0x2F2F2F),
                accentSoft: (0xF5F9FC, 0x051C2B),
                canvas: (0xFFFFFF, 0x000000),
                sidebar: (0xF8F8F8, 0x17181D),
                paper: (0xF8F8F8, 0x17181D),
                raised: (0xFFFFFF, 0x000000),
                softBorder: (0xE2E9ED, 0x262626),
                sage: (0x008356, 0x00B879)
            )
        case .mochaMousse:
            BurritoThemePalette.make(
                foreground: (0x59453E, 0xEFEFE7),
                sidebarForeground: (0x524039, 0xEFEFE7),
                accent: (0x78594B, 0xC2A08B),
                accentForeground: (0xFFFFFF, 0x2B2522),
                accentSoft: (0xDFDAD1, 0x453B35),
                canvas: (0xEFEFE7, 0x2B2522),
                sidebar: (0xECD6CA, 0x1E1916),
                paper: (0xEFEFE7, 0x3E332C),
                raised: (0xFFFFFF, 0x3E332C),
                softBorder: (0xBBAC92, 0x59453E),
                sage: (0x88645A, 0xBBAC92)
            )
        case .bubblegum:
            BurritoThemePalette.make(
                foreground: (0x4D4D4D, 0xF3E3EA),
                sidebarForeground: (0x333333, 0xF5F5F5),
                accent: (0xA33E78, 0xFBE2A7),
                accentForeground: (0xFFFFFF, 0x12242E),
                accentSoft: (0xF0DAE5, 0x3C4644),
                canvas: (0xF6E6EE, 0x12242E),
                sidebar: (0xF5D7E8, 0x0E1F29),
                paper: (0xFDEDC9, 0x1C2E38),
                raised: (0xFFFFFF, 0x1C2E38),
                softBorder: (0xD04F99, 0x324859),
                sage: (0x477179, 0xE4A2B1)
            )
        case .doom64:
            BurritoThemePalette.make(
                foreground: (0x1F1F1F, 0xE1E1E1),
                sidebarForeground: (0x1F1F1F, 0xE1E1E1),
                accent: (0x891314, 0xEC6764),
                accentForeground: (0xFFFFFF, 0x2B2B2B),
                accentSoft: (0xC4B3B4, 0x3A2626),
                canvas: (0xCECECE, 0x1B1B1B),
                sidebar: (0xB1B1B1, 0x141414),
                paper: (0xB1B1B1, 0x2B2B2B),
                raised: (0xB1B1B1, 0x2B2B2B),
                softBorder: (0x505050, 0x4A4A4A),
                sage: (0x3B4A21, 0x69A037)
            )
        case .catppuccin:
            BurritoThemePalette.make(
                foreground: (0x3B3D4F, 0xD9DFF5),
                sidebarForeground: (0x484B61, 0xCED7F3),
                accent: (0x7430CD, 0xCCA7F9),
                accentForeground: (0xFFFFFF, 0x1D1D2D),
                accentSoft: (0xDDD7F3, 0x39324E),
                canvas: (0xEEF2F9, 0x191928),
                sidebar: (0xE4E8EF, 0x10101A),
                paper: (0xFFFFFF, 0x1D1D2D),
                raised: (0xCED1D8, 0x444658),
                softBorder: (0xBCC1CE, 0x303142),
                sage: (0x0F6085, 0x8DDDEB)
            )
        case .graphite:
            BurritoThemePalette.make(
                foreground: (0x333333, 0xDBDBDB),
                sidebarForeground: (0x333333, 0xDBDBDB),
                accent: (0x606060, 0xA1A1A1),
                accentForeground: (0xFFFFFF, 0x1B1B1B),
                accentSoft: (0xDDDDDD, 0x333333),
                canvas: (0xF2F2F2, 0x1B1B1B),
                sidebar: (0xEBEBEB, 0x1F1F1F),
                paper: (0xF5F5F5, 0x1F1F1F),
                raised: (0xF5F5F5, 0x1F1F1F),
                softBorder: (0xD1D1D1, 0x353535),
                sage: (0x456868, 0x819B9E)
            )
        case .perpetuity:
            BurritoThemePalette.make(
                foreground: (0x0F4B55, 0x45E8E8),
                sidebarForeground: (0x0F4B55, 0x45E8E8),
                accent: (0x15747C, 0x45E8E8),
                accentForeground: (0xFFFFFF, 0x0E1A1F),
                accentSoft: (0xDEEBEB, 0x183F43),
                canvas: (0xE7F1F1, 0x0E1A1F),
                sidebar: (0xD9ECEE, 0x0E1A1F),
                paper: (0xEEF7F7, 0x0A2026),
                raised: (0xEEF7F7, 0x0A2026),
                softBorder: (0xCCDFE1, 0x114A57),
                sage: (0x1D787E, 0x31A5A5)
            )
        case .kodamaGrove:
            BurritoThemePalette.make(
                foreground: (0x4D4035, 0xEBE4D6),
                sidebarForeground: (0x483C32, 0xEBE4D6),
                accent: (0x555F2D, 0x99AD8B),
                accentForeground: (0xFEFCF4, 0x2A2522),
                accentSoft: (0xDCD1AC, 0x403D30),
                canvas: (0xE3D7B3, 0x3A352A),
                sidebar: (0xE0D0A5, 0x3A352A),
                paper: (0xE6DABD, 0x423C31),
                raised: (0xF3EBD5, 0x423C31),
                softBorder: (0xAF9683, 0x585246),
                sage: (0x55634B, 0x9BB089)
            )
        case .cosmicNight:
            BurritoThemePalette.make(
                foreground: (0x2A294B, 0xE2E2F8),
                sidebarForeground: (0x2A294B, 0xE2E2F8),
                accent: (0x6E55CF, 0xA590FF),
                accentForeground: (0xFFFFFF, 0x0E0E18),
                accentSoft: (0xEAE8F8, 0x292641),
                canvas: (0xF4F4FC, 0x0E0E18),
                sidebar: (0xF1F1F8, 0x1A1A2F),
                paper: (0xFFFFFF, 0x1A1A2F),
                raised: (0xFFFFFF, 0x1A1A2F),
                softBorder: (0xE0E0EE, 0x313153),
                sage: (0x7265B7, 0x7A87C9)
            )
        case .tangerine:
            BurritoThemePalette.make(
                foreground: (0x333333, 0xE4E4E4),
                sidebarForeground: (0x333333, 0xE4E4E4),
                accent: (0xA4452A, 0xE4785A),
                accentForeground: (0xFFFFFF, 0x303030),
                accentSoft: (0xE5DCDA, 0x342E37),
                canvas: (0xEBEBEB, 0x1C2433),
                sidebar: (0xDEDEDE, 0x2A3040),
                paper: (0xFFFFFF, 0x2A3040),
                raised: (0xFFFFFF, 0x272B36),
                softBorder: (0xD9DFE4, 0x3C4253),
                sage: (0x8A6155, 0xE7A08E)
            )
        case .quantumRose:
            BurritoThemePalette.make(
                foreground: (0x92125B, 0xFEB2FE),
                sidebarForeground: (0x92125B, 0xFEB2FE),
                accent: (0xD50971, 0xFD6AED),
                accentForeground: (0xFFFFFF, 0x180518),
                accentSoft: (0xFEECF6, 0x421B46),
                canvas: (0xFFF0F8, 0x190A21),
                sidebar: (0xFDEDF5, 0x1B0C24),
                paper: (0xFDF6FB, 0x2B1336),
                raised: (0xFDF6FB, 0x2B1336),
                softBorder: (0xFDC9E6, 0x4B1C60),
                sage: (0xB4488B, 0xC457E4)
            )
        case .nature:
            BurritoThemePalette.make(
                foreground: (0x402622, 0xEFEAE4),
                sidebarForeground: (0x402622, 0xEFEAE4),
                accent: (0x2F7933, 0x54B158),
                accentForeground: (0xFFFFFF, 0x09210B),
                accentSoft: (0xEBECE1, 0x233C26),
                canvas: (0xF9F5EE, 0x1C2B1F),
                sidebar: (0xEFEAE4, 0x1C2B1F),
                paper: (0xF9F5EE, 0x2B3A2C),
                raised: (0xF9F5EE, 0x2B3A2C),
                softBorder: (0xE0D6C9, 0x3C493B),
                sage: (0x367F39, 0x67BB6B)
            )
        case .boldTech:
            BurritoThemePalette.make(
                foreground: (0x312D84, 0xE1E7FD),
                sidebarForeground: (0x312D84, 0xE1E7FD),
                accent: (0x7F54E0, 0x986EF9),
                accentForeground: (0xFFFFFF, 0x222222),
                accentSoft: (0xF6F3FD, 0x1C203E),
                canvas: (0xFFFFFF, 0x0F182B),
                sidebar: (0xF5F3FF, 0x0F182B),
                paper: (0xFFFFFF, 0x1F1B4E),
                raised: (0xFFFFFF, 0x1F1B4E),
                softBorder: (0xE1E7FD, 0x2E0C66),
                sage: (0x7C38EE, 0x986EF9)
            )
        case .elegantLuxury:
            BurritoThemePalette.make(
                foreground: (0x1B1B1B, 0xF5F5F5),
                sidebarForeground: (0x1B1B1B, 0xF5F5F5),
                accent: (0x9E2C2C, 0xD36F6E),
                accentForeground: (0xFFFFFF, 0x262626),
                accentSoft: (0xECDCDC, 0x322320),
                canvas: (0xF8F8F8, 0x1E1916),
                sidebar: (0xF1E9E5, 0x1E1916),
                paper: (0xF8F8F8, 0x2B2523),
                raised: (0xF8F8F8, 0x2B2523),
                softBorder: (0xF6EAD5, 0x433F3A),
                sage: (0x9E2C2C, 0xF25656)
            )
        case .amberMinimal:
            BurritoThemePalette.make(
                foreground: (0x262626, 0xE4E4E4),
                sidebarForeground: (0x262626, 0xE4E4E4),
                accent: (0x9E6713, 0xF49F1E),
                accentForeground: (0xF8F8F8, 0x000000),
                accentSoft: (0xFBF8F4, 0x3E2F17),
                canvas: (0xFFFFFF, 0x161616),
                sidebar: (0xF8F8F8, 0x0F0F0F),
                paper: (0xFFFFFF, 0x262626),
                raised: (0xFFFFFF, 0x262626),
                softBorder: (0xE4E8EF, 0x404040),
                sage: (0xB36200, 0xDB7800)
            )
        case .supabase:
            BurritoThemePalette.make(
                foreground: (0x161616, 0xE4E8EF),
                sidebarForeground: (0x575757, 0x9E9E9E),
                accent: (0x408162, 0x5C967B),
                accentForeground: (0xFCFCFC, 0x232424),
                accentSoft: (0xFCFCFC, 0x1D2622),
                canvas: (0xFCFCFC, 0x121212),
                sidebar: (0xFCFCFC, 0x121212),
                paper: (0xFCFCFC, 0x161616),
                raised: (0xFCFCFC, 0x242424),
                softBorder: (0xDEDEDE, 0x292929),
                sage: (0x3272D9, 0x61A4F7)
            )
        case .neoBrutalism:
            BurritoThemePalette.make(
                foreground: (0x000000, 0xFFFFFF),
                sidebarForeground: (0x000000, 0xFFFFFF),
                accent: (0xD42829, 0xFF6969),
                accentForeground: (0xFFFFFF, 0x000000),
                accentSoft: (0xFCEFEF, 0x2E1313),
                canvas: (0xFFFFFF, 0x000000),
                sidebar: (0xF2F2F2, 0x000000),
                paper: (0xFFFFFF, 0x333333),
                raised: (0xFFFFFF, 0x333333),
                softBorder: (0x000000, 0xFFFFFF),
                sage: (0x7B7B07, 0xFFFF35)
            )
        case .solarDusk:
            BurritoThemePalette.make(
                foreground: (0x4D3B32, 0xF5F5F5),
                sidebarForeground: (0x4D3B32, 0xF5F5F5),
                accent: (0xAE4F01, 0xF97007),
                accentForeground: (0xFFFFFF, 0x323232),
                accentSoft: (0xF6E9DA, 0x462914),
                canvas: (0xFFFBF4, 0x1E1916),
                sidebar: (0xF2EADD, 0x2B2523),
                paper: (0xF9F4EE, 0x2B2523),
                raised: (0xF9F4EE, 0x2B2523),
                softBorder: (0xE5DABD, 0x433F3A),
                sage: (0x76706B, 0x00A4E9)
            )
        case .claymorphism:
            BurritoThemePalette.make(
                foreground: (0x1D293D, 0xE4E8EF),
                sidebarForeground: (0x1D293D, 0xE4E8EF),
                accent: (0x4D50B8, 0x8E98FA),
                accentForeground: (0xFFFFFF, 0x1E1A16),
                accentSoft: (0xD3D3DF, 0x32303F),
                canvas: (0xE4E4E4, 0x1E1A16),
                sidebar: (0xD4D4D4, 0x3C3733),
                paper: (0xF5F5F5, 0x2D2824),
                raised: (0xF5F5F5, 0x2D2824),
                softBorder: (0xD4D4D4, 0x3C3733),
                sage: (0x4F46E5, 0x8083F3)
            )
        case .cyberpunk:
            BurritoThemePalette.make(
                foreground: (0x0B0A1E, 0xEBEFF5),
                sidebarForeground: (0x0B0A1E, 0xEBEFF5),
                accent: (0xCE00A1, 0xFE00C7),
                accentForeground: (0xFFFFFF, 0x232323),
                accentSoft: (0xF7EFF5, 0x37093C),
                canvas: (0xF8F8F8, 0x0B0A1E),
                sidebar: (0xF0F0FF, 0x0B0A1E),
                paper: (0xFFFFFF, 0x1D1D3D),
                raised: (0xFFFFFF, 0x1D1D3D),
                softBorder: (0xDEE6EA, 0x2F2F5D),
                sage: (0x900DFD, 0xB35BFE)
            )
        case .pastelDreams:
            BurritoThemePalette.make(
                foreground: (0x364050, 0xE1E7FD),
                sidebarForeground: (0x364050, 0xE1E7FD),
                accent: (0x6A589F, 0xC1AAFF),
                accentForeground: (0xFFFFFF, 0x1E1916),
                accentSoft: (0xE4DDED, 0x3C3440),
                canvas: (0xF8F3FA, 0x1E1916),
                sidebar: (0xE9D9FC, 0x3E3248),
                paper: (0xFFFFFF, 0x2D2535),
                raised: (0xFFFFFF, 0x2D2535),
                softBorder: (0xE9D9FC, 0x3E3248),
                sage: (0x7F54E1, 0xA78BFB)
            )
        case .cleanSlate:
            BurritoThemePalette.make(
                foreground: (0x1D293D, 0xE4E8EF),
                sidebarForeground: (0x1D293D, 0xE4E8EF),
                accent: (0x5E61E0, 0x818CF9),
                accentForeground: (0xFFFFFF, 0x0F182B),
                accentSoft: (0xF5F5F8, 0x242C50),
                canvas: (0xF8F8F8, 0x0F182B),
                sidebar: (0xF5F5F5, 0x1D293D),
                paper: (0xFFFFFF, 0x1D293D),
                raised: (0xFFFFFF, 0x1D293D),
                softBorder: (0xD0D4DB, 0x4B5666),
                sage: (0x4F46E5, 0x8083F3)
            )
        case .caffeine:
            BurritoThemePalette.make(
                foreground: (0x1F1F1F, 0xEEEEEE),
                sidebarForeground: (0x242424, 0xF5F5F5),
                accent: (0x63493F, 0xFCDFC2),
                accentForeground: (0xFFFFFF, 0x0A191A),
                accentSoft: (0xE3E0DE, 0x3C3631),
                canvas: (0xF8F8F8, 0x121212),
                sidebar: (0xFCFCFC, 0x18181D),
                paper: (0xFCFCFC, 0x181818),
                raised: (0xFCFCFC, 0x181818),
                softBorder: (0xD7D7D7, 0x211F1A),
                sage: (0x817059, 0x857F7A)
            )
        case .oceanBreeze:
            BurritoThemePalette.make(
                foreground: (0x364050, 0xD0D4DB),
                sidebarForeground: (0x364050, 0xD0D4DB),
                accent: (0x177D3C, 0x39D199),
                accentForeground: (0xFFFFFF, 0x0F182B),
                accentSoft: (0xE5F1F2, 0x17393E),
                canvas: (0xF3F9FF, 0x0F182B),
                sidebar: (0xDCF2FF, 0x1D293D),
                paper: (0xFFFFFF, 0x1D293D),
                raised: (0xFFFFFF, 0x1D293D),
                softBorder: (0xE4E8EF, 0x4B5666),
                sage: (0x0B835B, 0x32D2BD)
            )
        case .retroArcade:
            BurritoThemePalette.make(
                foreground: (0x0A3642, 0xB5C1C1),
                sidebarForeground: (0x0A3642, 0xA7B5B5),
                accent: (0xBB3173, 0xE075A9),
                accentForeground: (0xFFFFFF, 0x313131),
                accentSoft: (0xF7E5D6, 0x193444),
                canvas: (0xFDF5DF, 0x002C37),
                sidebar: (0xFDF5DF, 0x002C37),
                paper: (0xEFE8D2, 0x0A3642),
                raised: (0xEFE8D2, 0x0A3642),
                softBorder: (0x829395, 0x566D75),
                sage: (0x20746E, 0x3EA8A0)
            )
        case .midnightBloom:
            BurritoThemePalette.make(
                foreground: (0x333333, 0xE4E4E4),
                sidebarForeground: (0x333333, 0xE4E4E4),
                accent: (0x6D5DE7, 0x998EEE),
                accentForeground: (0xFFFFFF, 0x333333),
                accentSoft: (0xF7F7F8, 0x313146),
                canvas: (0xF8F8F8, 0x1B1D22),
                sidebar: (0xF8F8F8, 0x1B1D22),
                paper: (0xFFFFFF, 0x2E3437),
                raised: (0xFFFFFF, 0x2E3437),
                softBorder: (0xD4D4D4, 0x454545),
                sage: (0x8F45AE, 0xB889CC)
            )
        case .candyland:
            BurritoThemePalette.make(
                foreground: (0x333333, 0xE4E4E4),
                sidebarForeground: (0x333333, 0xE4E4E4),
                accent: (0x8B6A70, 0xFF97CC),
                accentForeground: (0xF8F8F8, 0x000000),
                accentSoft: (0xF8F8F8, 0x443340),
                canvas: (0xF8F8F8, 0x1B1D22),
                sidebar: (0xF8F8F8, 0x1B1D22),
                paper: (0xFFFFFF, 0x2E3437),
                raised: (0xFFFFFF, 0x2E3437),
                softBorder: (0xD4D4D4, 0x454545),
                sage: (0x507889, 0x2FCD30)
            )
        case .northernLights:
            BurritoThemePalette.make(
                foreground: (0x333333, 0xE4E4E4),
                sidebarForeground: (0x333333, 0xE4E4E4),
                accent: (0x2C8247, 0x46AE67),
                accentForeground: (0xFFFFFF, 0x333333),
                accentSoft: (0xF8F8F8, 0x22372E),
                canvas: (0xF8F8F8, 0x1B1D22),
                sidebar: (0xF8F8F8, 0x1B1D22),
                paper: (0xFFFFFF, 0x2E3437),
                raised: (0xFFFFFF, 0x2E3437),
                softBorder: (0xD4D4D4, 0x454545),
                sage: (0x4D72B6, 0x709FC6)
            )
        case .vintagePaper:
            BurritoThemePalette.make(
                foreground: (0x4A4037, 0xEBE4D6),
                sidebarForeground: (0x4A4037, 0xEBE4D6),
                accent: (0x81603E, 0xC2A180),
                accentForeground: (0xFFFFFF, 0x2A2522),
                accentSoft: (0xECE4D3, 0x453B32),
                canvas: (0xF7F2E3, 0x2A2522),
                sidebar: (0xEBE4D6, 0x2A2522),
                paper: (0xFFFCF4, 0x3B3129),
                raised: (0xFFFCF4, 0x3B3129),
                softBorder: (0xDAD0BB, 0x4B4038),
                sage: (0x866A4A, 0xB49475)
            )
        case .sunsetHorizon:
            BurritoThemePalette.make(
                foreground: (0x3D3637, 0xF1E9E5),
                sidebarForeground: (0x3D3637, 0xF1E9E5),
                accent: (0xAD5743, 0xFF8163),
                accentForeground: (0xFFFFFF, 0x3C3C3C),
                accentSoft: (0xFBF2ED, 0x523230),
                canvas: (0xFFFAF5, 0x2C2025),
                sidebar: (0xFFF1EB, 0x2C2025),
                paper: (0xFFFFFF, 0x3A2F36),
                raised: (0xFFFFFF, 0x3A2F36),
                softBorder: (0xFFE0D5, 0x453940),
                sage: (0x966B4B, 0xFDB57E)
            )
        case .starryNight:
            BurritoThemePalette.make(
                foreground: (0x1C2338, 0xE8EBF2),
                sidebarForeground: (0x1C2338, 0xE8EBF2),
                accent: (0x395AA1, 0x748CBD),
                accentForeground: (0xFFFDE6, 0x2B2612),
                accentSoft: (0xDDE2EC, 0x212533),
                canvas: (0xF8F8F8, 0x181A24),
                sidebar: (0xE3E8EE, 0x23243A),
                paper: (0xE3E8EE, 0x23243A),
                raised: (0xFFFDE6, 0x23243A),
                softBorder: (0xAEB9C4, 0x2E2F3F),
                sage: (0x7D6539, 0xFEE06B)
            )
        case .claude:
            BurritoThemePalette.make(
                foreground: (0x3D3826, 0xC3C1BA),
                sidebarForeground: (0x3E3E38, 0xC3C1BA),
                accent: (0xB15739, 0xDA7F61),
                accentForeground: (0xFFFFFF, 0x303030),
                accentSoft: (0xF9F5ED, 0x372E2C),
                canvas: (0xFAF8F1, 0x262626),
                sidebar: (0xF7F5EE, 0x1F1F1F),
                paper: (0xFAF8F1, 0x262626),
                raised: (0xFFFFFF, 0x303030),
                softBorder: (0xD9D8D0, 0x3E3E38),
                sage: (0x7766BB, 0x9C87F6)
            )
        case .vercel:
            BurritoThemePalette.make(
                foreground: (0x000000, 0xFFFFFF),
                sidebarForeground: (0x000000, 0xFFFFFF),
                accent: (0x000000, 0xFFFFFF),
                accentForeground: (0xFFFFFF, 0x000000),
                accentSoft: (0xD8D8D8, 0x2E2E2E),
                canvas: (0xFCFCFC, 0x000000),
                sidebar: (0xFCFCFC, 0x121212),
                paper: (0xFFFFFF, 0x090909),
                raised: (0xFCFCFC, 0x121212),
                softBorder: (0xE4E4E4, 0x242424),
                sage: (0x2D62EF, 0x2E76F4)
            )
        case .mono:
            BurritoThemePalette.make(
                foreground: (0x090909, 0xFCFCFC),
                sidebarForeground: (0x090909, 0xFCFCFC),
                accent: (0x747474, 0x8C8C8C),
                accentForeground: (0xFCFCFC, 0x262626),
                accentSoft: (0xFBFBFB, 0x212121),
                canvas: (0xFFFFFF, 0x090909),
                sidebar: (0xFCFCFC, 0x161616),
                paper: (0xFFFFFF, 0x181818),
                raised: (0xFFFFFF, 0x262626),
                softBorder: (0xE4E4E4, 0x383838),
                sage: (0x747474, 0x8C8C8C)
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
                alpha: isDark ? 0.075 : 0.055
            )
            let controlSurfaces = contentSurfaces.map { controlFillColor.composited(over: $0) }
            let accentSoftColor = color(accentSoft)
            let accentColor = color(accent).ensuringContrast(
                against: contentSurfaces + [sidebarColor, accentSoftColor],
                minimum: 4.55
            )
            let registryBorderColor = color(softBorder)
            let borderTintWeight = 0.2
            let softBorderColor = BurritoThemeColor(
                red: foregroundColor.red * (1 - borderTintWeight)
                    + registryBorderColor.red * borderTintWeight,
                green: foregroundColor.green * (1 - borderTintWeight)
                    + registryBorderColor.green * borderTintWeight,
                blue: foregroundColor.blue * (1 - borderTintWeight)
                    + registryBorderColor.blue * borderTintWeight,
                alpha: isDark ? 0.38 : 0.32
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
