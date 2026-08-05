import PhosphorSwift
import SwiftUI

enum BurritoIconCatalog {
    private static let aliases: [String: String] = [
        "airplane": "airplane", "apple.logo": "apple-logo", "archivebox": "archive",
        "arrow.clockwise": "arrow-clockwise", "arrow.down": "arrow-down",
        "arrow.down.circle": "arrow-circle-down", "arrow.left.to.line.compact": "sidebar-simple",
        "arrow.right": "arrow-right", "arrow.right.to.line.compact": "sidebar-simple",
        "arrow.up": "arrow-up", "arrow.up.right": "arrow-up-right",
        "arrow.uturn.backward": "arrow-counter-clockwise", "at": "at", "atom": "atom",
        "bell": "bell", "bolt": "lightning", "book.closed": "book", "bookmark": "bookmark",
        "books.vertical": "books", "brain.head.profile": "brain", "briefcase": "briefcase",
        "bubble.left.and.bubble.right": "chats-circle", "building.2": "buildings",
        "apple.intelligence": "sparkle", "calendar": "calendar",
        "calendar.badge.checkmark": "calendar-check", "calendar.badge.clock": "calendar-dots",
        "calendar.badge.exclamationmark": "calendar-x", "calendar.badge.plus": "calendar-plus",
        "camera": "camera", "captions.bubble": "closed-captioning", "car": "car",
        "cart": "shopping-cart", "character.bubble": "translate", "chart.bar": "chart-bar",
        "chart.line.uptrend.xyaxis": "trend-up", "chart.pie": "chart-pie",
        "checklist": "checks", "checkmark": "check", "checkmark.circle": "check-circle",
        "checkmark.shield": "shield-check", "chevron.down": "caret-down",
        "chevron.left": "caret-left", "chevron.left.forwardslash.chevron.right": "code",
        "chevron.right": "caret-right", "circle.lefthalf.filled": "circle-half",
        "clock": "clock", "cpu": "cpu", "creditcard": "credit-card",
        "cross.case": "first-aid-kit", "cup.and.saucer": "coffee", "cylinder": "database",
        "doc.on.doc": "copy", "doc.text": "file-text", "dollarsign.circle": "currency-dollar",
        "ellipsis": "dots-three",
        "exclamationmark.triangle": "warning", "exclamationmark.triangle.fill": "warning",
        "eye": "eye", "film": "film-strip", "flag": "flag", "flame": "fire",
        "folder": "folder", "folder.badge.plus": "folder-plus", "fork.knife": "fork-knife",
        "function": "function", "gearshape": "gear-six", "globe": "globe",
        "graduationcap": "graduation-cap", "hammer": "hammer", "handshake": "handshake",
        "heart": "heart", "highlighter": "highlighter", "hourglass": "hourglass",
        "house": "house", "house.fill": "house", "key": "key", "leaf": "leaf",
        "lightbulb": "lightbulb", "link": "link", "list.bullet": "list-bullets",
        "location": "map-pin", "lock": "lock", "lock.fill": "lock",
        "internaldrive": "hard-drive", "lock.shield": "shield-check", "macbook": "laptop",
        "macbook.and.iphone": "devices", "macwindow": "app-window",
        "magnifyingglass": "magnifying-glass", "map": "map-trifold", "megaphone": "megaphone",
        "message": "chat-circle", "mic": "microphone", "mic.fill": "microphone",
        "moon": "moon", "music.note": "music-note", "network": "network",
        "note.text": "note", "number": "hash", "paintpalette": "palette",
        "paperclip": "paperclip", "paperplane": "paper-plane-tilt", "pencil": "pencil-simple",
        "person.2": "users", "person.2.wave.2": "users-three", "person.3": "users-three",
        "person.crop.circle": "user-circle", "person.fill": "user", "phone": "phone",
        "play.fill": "play", "plus": "plus", "questionmark.circle": "question",
        "quote.bubble": "quotes", "record.circle": "record", "record.circle.fill": "record",
        "server.rack": "hard-drives", "shield": "shield", "shippingbox": "package",
        "sidebar.left": "sidebar", "slider.horizontal.3": "sliders-horizontal",
        "sparkles": "sparkle", "speaker.wave.2": "speaker-high",
        "speaker.wave.2.fill": "speaker-high", "square.and.arrow.down": "download-simple",
        "square.and.arrow.up": "upload-simple", "square.and.pencil": "note-pencil",
        "star": "star", "star.fill": "star", "star.slash": "star-half",
        "stop.fill": "stop", "sum": "sigma", "sun.max": "sun", "tablecells": "table",
        "tag": "tag", "target": "target", "terminal": "terminal-window",
        "text.alignleft": "text-align-left", "text.bubble": "chat-text",
        "text.magnifyingglass": "file-magnifying-glass", "trash": "trash", "trash.fill": "trash",
        "tray": "tray", "trophy": "trophy", "video": "video-camera",
        "video.fill": "video-camera", "wand.and.stars": "magic-wand", "waveform": "waveform",
        "waveform.and.mic": "microphone-stage", "waveform.badge.magnifyingglass": "waveform",
        "waveform.badge.plus": "waveform",
        "wrench.and.screwdriver": "toolbox", "xmark": "x", "xmark.circle.fill": "x-circle"
    ]

    static func icon(named name: String) -> Ph? {
        Ph(rawValue: aliases[name] ?? name)
    }

    static func supports(_ name: String) -> Bool {
        icon(named: name) != nil
    }

    static var allAliasesAreValid: Bool {
        aliases.values.allSatisfy { Ph(rawValue: $0) != nil }
    }
}

struct BurritoIcon: View {
    let name: String
    var size: CGFloat = 15

    var body: some View {
        image
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private var image: Image {
        guard let icon = BurritoIconCatalog.icon(named: name) else {
            return Ph.question.regular
        }
        return name.hasSuffix(".fill") ? icon.fill : icon.regular
    }
}

struct BurritoLabel: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            BurritoIcon(name: systemImage, size: 13)
        }
    }
}

struct BurritoButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    init(_ title: String, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            BurritoLabel(title, systemImage: systemImage)
        }
    }
}

struct BurritoMenu<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: () -> Content

    init(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content
    }

    var body: some View {
        Menu(content: content) {
            BurritoLabel(title, systemImage: systemImage)
        }
    }
}

struct BurritoContentUnavailable: View {
    let title: String
    let systemImage: String
    let description: Text

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(title)
            } icon: {
                BurritoIcon(name: systemImage, size: 42)
            }
        } description: {
            description
        }
    }
}
