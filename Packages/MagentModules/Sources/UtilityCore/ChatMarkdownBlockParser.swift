import Foundation

public enum ChatMarkdownBlock: Equatable, Sendable {
    case paragraph(String)
    case heading(level: Int, text: String)
    case unorderedListItem(String)
    case orderedListItem(number: Int, text: String)
    case blockQuote(String)
    case codeBlock(language: String?, code: String)
    case separator
    case blankLine
}

public enum ChatMarkdownBlockParser {
    public static func parse(_ source: String) -> [ChatMarkdownBlock] {
        let lines = source.components(separatedBy: .newlines)
        var blocks: [ChatMarkdownBlock] = []
        var isInCodeFence = false
        var codeLanguage: String?
        var codeLines: [String] = []

        for line in lines {
            if isInCodeFence {
                if line.trimmingCharacters(in: .whitespaces) == "```" {
                    blocks.append(.codeBlock(language: codeLanguage, code: codeLines.joined(separator: "\n")))
                    isInCodeFence = false
                    codeLanguage = nil
                    codeLines.removeAll(keepingCapacity: true)
                } else {
                    codeLines.append(line)
                }
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                isInCodeFence = true
                codeLanguage = language.isEmpty ? nil : language
                codeLines.removeAll(keepingCapacity: true)
                continue
            }
            if trimmed.isEmpty {
                blocks.append(.blankLine)
                continue
            }
            if isSeparator(trimmed) {
                blocks.append(.separator)
                continue
            }
            if let heading = heading(from: trimmed) {
                blocks.append(heading)
                continue
            }
            if let item = unorderedListItem(from: trimmed) {
                blocks.append(.unorderedListItem(item))
                continue
            }
            if let item = orderedListItem(from: trimmed) {
                blocks.append(item)
                continue
            }
            if trimmed.hasPrefix(">") {
                blocks.append(.blockQuote(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)))
                continue
            }
            blocks.append(.paragraph(line))
        }

        if isInCodeFence {
            blocks.append(.codeBlock(language: codeLanguage, code: codeLines.joined(separator: "\n")))
        }
        return blocks
    }

    private static func heading(from line: String) -> ChatMarkdownBlock? {
        let markerCount = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(markerCount) else { return nil }
        let markerEnd = line.index(line.startIndex, offsetBy: markerCount)
        guard markerEnd < line.endIndex, line[markerEnd].isWhitespace else { return nil }
        let text = line[markerEnd...].trimmingCharacters(in: .whitespaces)
        return .heading(level: markerCount, text: text)
    }

    private static func unorderedListItem(from line: String) -> String? {
        for prefix in ["- ", "* ", "+ "] where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count))
        }
        return nil
    }

    private static func orderedListItem(from line: String) -> ChatMarkdownBlock? {
        guard let punctuation = line.firstIndex(where: { $0 == "." || $0 == ")" }) else { return nil }
        let numberText = line[..<punctuation]
        guard let number = Int(numberText) else { return nil }
        let contentStart = line.index(after: punctuation)
        guard contentStart < line.endIndex, line[contentStart].isWhitespace else { return nil }
        return .orderedListItem(
            number: number,
            text: line[contentStart...].trimmingCharacters(in: .whitespaces)
        )
    }

    private static func isSeparator(_ line: String) -> Bool {
        guard line.count >= 3 else { return false }
        let characters = Set(line.filter { !$0.isWhitespace })
        return characters == Set("-") || characters == Set("*") || characters == Set("_")
    }
}
