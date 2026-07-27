import AppKit
import SwiftUI

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
    static let cardRadius: CGFloat = 14

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
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(.tertiary)
    }
}

struct BurritoPill: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(BurritoTheme.controlFill, in: Capsule())
    }
}
