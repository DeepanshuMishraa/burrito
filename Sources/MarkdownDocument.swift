import Foundation

struct MarkdownDocument: Equatable, Sendable {
    enum QuoteKind: Equatable, Sendable {
        case informational
        case warning
    }

    enum Block: Equatable, Sendable {
        case heading(level: Int, text: String)
        case paragraph(String)
        case unorderedList([String])
        case orderedList([String])
        case quote(kind: QuoteKind, text: String)
        case code(String)
        case divider
    }

    let blocks: [Block]

    static func parse(_ markdown: String) -> MarkdownDocument {
        let lines = normalized(markdown).components(separatedBy: .newlines)
        var blocks: [Block] = []
        var paragraph: [String] = []
        var unorderedItems: [String] = []
        var orderedItems: [String] = []
        var codeLines: [String] = []
        var isInsideCodeBlock = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph.removeAll(keepingCapacity: true)
        }

        func flushLists() {
            if !unorderedItems.isEmpty {
                blocks.append(.unorderedList(unorderedItems))
                unorderedItems.removeAll(keepingCapacity: true)
            }
            if !orderedItems.isEmpty {
                blocks.append(.orderedList(orderedItems))
                orderedItems.removeAll(keepingCapacity: true)
            }
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                flushParagraph()
                flushLists()
                if isInsideCodeBlock {
                    blocks.append(.code(codeLines.joined(separator: "\n")))
                    codeLines.removeAll(keepingCapacity: true)
                }
                isInsideCodeBlock.toggle()
                continue
            }
            if isInsideCodeBlock {
                codeLines.append(line)
                continue
            }
            if trimmed.isEmpty {
                flushParagraph()
                continue
            }
            if ["---", "***", "___"].contains(trimmed) {
                flushParagraph()
                flushLists()
                blocks.append(.divider)
                continue
            }
            if let heading = heading(from: trimmed) {
                flushParagraph()
                flushLists()
                blocks.append(heading)
                continue
            }
            if let item = unorderedItem(from: trimmed) {
                flushParagraph()
                if !orderedItems.isEmpty { flushLists() }
                unorderedItems.append(item)
                continue
            }
            if let item = orderedItem(from: trimmed) {
                flushParagraph()
                if !unorderedItems.isEmpty { flushLists() }
                orderedItems.append(item)
                continue
            }
            if trimmed.hasPrefix(">") {
                flushParagraph()
                flushLists()
                let quote = quote(from: trimmed)
                blocks.append(.quote(kind: quote.kind, text: quote.text))
                continue
            }
            flushLists()
            paragraph.append(trimmed)
        }

        if isInsideCodeBlock, !codeLines.isEmpty {
            blocks.append(.code(codeLines.joined(separator: "\n")))
        }
        flushParagraph()
        flushLists()
        return MarkdownDocument(blocks: blocks)
    }

    private static func normalized(_ markdown: String) -> String {
        var value = markdown
        for level in stride(from: 6, through: 1, by: -1) {
            let marker = String(repeating: "#", count: level)
            value = value.replacingOccurrences(
                of: " \(marker) ",
                with: "\n\n\(marker) "
            )
        }
        value = value.replacingOccurrences(of: " * ", with: "\n* ")
        value = value.replacingOccurrences(of: " - ", with: "\n- ")

        return value
            .components(separatedBy: .newlines)
            .flatMap(splitGeneratedHeading)
            .joined(separator: "\n")
    }

    private static func splitGeneratedHeading(_ line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let markerCount = trimmed.prefix { $0 == "#" }.count
        guard (1...6).contains(markerCount),
              trimmed.dropFirst(markerCount).first == " "
        else {
            return [line]
        }

        let contentStart = trimmed.index(trimmed.startIndex, offsetBy: markerCount + 1)
        let content = String(trimmed[contentStart...])
        guard let colon = content.firstIndex(of: ":"),
              content.distance(from: content.startIndex, to: colon) <= 40
        else {
            return [line]
        }

        let title = String(content[..<colon]).trimmingCharacters(in: .whitespaces)
        let body = String(content[content.index(after: colon)...])
            .trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return [line] }
        let marker = String(repeating: "#", count: markerCount)
        guard !body.isEmpty else { return ["\(marker) \(title)"] }
        return ["\(marker) \(title)", "", body]
    }

    private static func heading(from line: String) -> Block? {
        let markerCount = line.prefix { $0 == "#" }.count
        guard (1...6).contains(markerCount),
              line.dropFirst(markerCount).first == " "
        else {
            return nil
        }
        return .heading(
            level: markerCount,
            text: String(line.dropFirst(markerCount + 1))
        )
    }

    private static func unorderedItem(from line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        return nil
    }

    private static func orderedItem(from line: String) -> String? {
        guard let period = line.firstIndex(of: "."),
              period != line.startIndex,
              line.index(after: period) < line.endIndex,
              line[line.index(after: period)] == " ",
              line[..<period].allSatisfy(\.isNumber)
        else {
            return nil
        }
        return String(line[line.index(period, offsetBy: 2)...])
    }

    private static func quote(from line: String) -> (kind: QuoteKind, text: String) {
        let content = String(line.dropFirst())
            .trimmingCharacters(in: .whitespaces)
        let warningMarker = "[!WARNING]"
        guard content.hasPrefix(warningMarker) else {
            return (.informational, content)
        }
        return (
            .warning,
            String(content.dropFirst(warningMarker.count))
                .trimmingCharacters(in: .whitespaces)
        )
    }
}
