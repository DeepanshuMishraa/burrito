import Hugeicons
import SwiftUI

enum BurritoIconCatalog {
    private static let aliases: [String: String] = [
        "airplane": "airplane01", "apple.logo": "apple", "archivebox": "archive",
        "arrow.clockwise": "refresh", "arrow.down": "arrowDown01",
        "arrow.down.circle": "downloadCircle01", "arrow.left.to.line.compact": "sidebarLeft",
        "arrow.right": "arrowRight01", "arrow.right.to.line.compact": "sidebarRight",
        "arrow.up": "arrowUp01", "arrow.up.right": "arrowUpRight01",
        "arrow.uturn.backward": "arrowTurnBackward", "at": "at", "atom": "atom01",
        "bell": "bell", "bolt": "bolt", "book.closed": "book02", "bookmark": "bookmark01",
        "books.vertical": "books01", "brain.head.profile": "brain", "briefcase": "briefcase01",
        "bubble.left.and.bubble.right": "chat", "building.2": "building02",
        "apple.intelligence": "appleIntelligence", "calendar": "calendar03",
        "calendar.badge.checkmark": "calendarCheck", "calendar.badge.clock": "calendarClock",
        "calendar.badge.exclamationmark": "calendarX", "calendar.badge.plus": "calendarPlus",
        "camera": "camera01", "captions.bubble": "closedCaption", "car": "car01",
        "cart": "shoppingCart01", "character.bubble": "bubbleChatTranslate", "chart.bar": "barChart",
        "chart.line.uptrend.xyaxis": "chartLineData01", "chart.pie": "pieChart",
        "checklist": "checkList", "checkmark": "check", "checkmark.circle": "circleCheck",
        "checkmark.shield": "badgeCheck", "chevron.down": "chevronDown",
        "chevron.left": "chevronLeft", "chevron.left.forwardslash.chevron.right": "sourceCode",
        "chevron.right": "chevronRight", "circle.lefthalf.filled": "contrast",
        "clock": "clock01", "cpu": "cpu", "creditcard": "creditCard",
        "cross.case": "firstAidKit", "cup.and.saucer": "coffee01", "cylinder": "database",
        "doc.on.doc": "copy", "doc.text": "fileEmpty02", "dollarsign.circle": "dollarCircle",
        "ellipsis": "ellipsis",
        "exclamationmark.triangle": "alert02", "exclamationmark.triangle.fill": "alert02",
        "eye": "eye", "film": "film01", "flag": "flag01", "flame": "fire",
        "folder": "folder01", "folder.badge.plus": "folderAdd", "fork.knife": "spoonAndFork",
        "function": "function", "gearshape": "settings01", "globe": "globe",
        "graduationcap": "graduationCap", "hammer": "hammer", "handshake": "handshake",
        "heart": "heart", "highlighter": "highlighter", "hourglass": "hourglass",
        "house": "house01", "house.fill": "house01", "key": "key01", "leaf": "leaf01",
        "lightbulb": "bulb", "link": "link01", "list.bullet": "leftToRightListBullet",
        "location": "mapPin", "lock": "lock", "lock.fill": "lock",
        "internaldrive": "hardDrive", "lock.shield": "shield02", "macbook": "laptop",
        "macbook.and.iphone": "laptopPhoneSync", "macwindow": "appWindow",
        "magnifyingglass": "search01", "map": "maps", "megaphone": "megaphone01",
        "message": "bubbleChat", "mic": "mic01", "mic.fill": "mic01",
        "moon": "moon", "music.note": "musicNote01", "network": "neuralNetwork",
        "note.text": "note", "number": "hashtag", "paintpalette": "colors",
        "paperclip": "attachment01", "paperplane": "sent", "pencil": "pencilEdit01",
        "person.2": "userMultiple", "person.2.wave.2": "userGroup03", "person.3": "userGroup03",
        "person.crop.circle": "userCircle", "person.fill": "user", "phone": "telephone",
        "play.fill": "play", "plus": "add01", "questionmark.circle": "circleQuestionMark",
        "quote.bubble": "quotes", "record.circle": "record", "record.circle.fill": "record",
        "server.rack": "serverStack01", "shield": "shield01", "shippingbox": "package",
        "sidebar.left": "sidebarLeft", "slider.horizontal.3": "slidersHorizontal",
        "sparkles": "sparkles", "speaker.wave.2": "volumeHigh",
        "speaker.wave.2.fill": "volumeHigh", "square.and.arrow.down": "download01",
        "square.and.arrow.up": "upload01", "square.and.pencil": "noteEdit",
        "star": "star", "star.fill": "star", "star.slash": "starOff",
        "stop.fill": "stop", "sum": "summation01", "sun.max": "sun01", "tablecells": "table",
        "tag": "tag01", "target": "target01", "terminal": "terminal",
        "text.alignleft": "textAlignLeft", "text.bubble": "bubbleChat",
        "text.magnifyingglass": "fileSearch", "trash": "delete02", "trash.fill": "delete02",
        "tray": "inbox", "trophy": "award01", "video": "cameraVideo",
        "video.fill": "cameraVideo", "wand.and.stars": "magicWand02", "waveform": "audioWaveform",
        "waveform.and.mic": "cameraMicrophone01", "waveform.badge.magnifyingglass": "audioWave01",
        "waveform.badge.plus": "audioWave02",
        "wrench.and.screwdriver": "toolbox", "xmark": "cancel01", "xmark.circle.fill": "cancelCircle"
    ]

    static func icon(named name: String) -> HugeiconsAsset? {
        Hugeicons.asset(swiftIdentifier: aliases[name] ?? name)
    }

    static func supports(_ name: String) -> Bool {
        icon(named: name) != nil
    }

    static var allAliasesAreValid: Bool {
        aliases.values.allSatisfy { Hugeicons.asset(swiftIdentifier: $0) != nil }
    }
}

struct BurritoIcon: View {
    let name: String
    var size: CGFloat = 15
    var accessibilityLabel: String? = nil

    var body: some View {
        image
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(accessibilityLabel == nil)
            .accessibilityLabel(accessibilityLabel ?? "")
    }

    private var image: Image {
        guard let icon = BurritoIconCatalog.icon(named: name) else {
            return Hugeicons.question.image()
        }
        return icon.image()
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
