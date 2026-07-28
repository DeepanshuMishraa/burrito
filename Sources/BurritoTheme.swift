import AppKit
import SwiftUI

extension Font {
    static func burritoDisplay(
        size: CGFloat,
        weight: Font.Weight = .regular
    ) -> Font {
        .custom("Avenir Next", fixedSize: size)
            .weight(weight)
    }
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
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
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
            .background(BurritoTheme.controlFill, in: Rectangle())
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
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                }

                Spacer()

                Text(selectedLanguage.compactTitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(
                embedded ? Color.clear : BurritoTheme.controlFill,
                in: Rectangle()
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
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    TextField("Find a language", text: $query)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(BurritoTheme.controlFill, in: Rectangle())

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
            selection = language.identifier
            isPresented = false
        } label: {
            HStack(spacing: 9) {
                Text(language.title)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                Spacer()
                if selection == language.identifier {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(BurritoTheme.accent)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                selection == language.identifier
                    ? BurritoTheme.controlFill
                    : Color.clear,
                in: Rectangle()
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
