import Foundation

public enum ChatMarkdownToken: Equatable, Sendable {
    case text(String)
    case code(String)
    case link(label: String, target: String)
    case bold(String)
}

public enum ChatMarkdownTokenizer {
    public static func tokenize(_ source: String) -> [ChatMarkdownToken] {
        guard !source.isEmpty else { return [.text("")] }

        var tokens: [ChatMarkdownToken] = []
        var buffer = ""

        func flushText() {
            guard !buffer.isEmpty else { return }
            tokens.append(.text(buffer))
            buffer.removeAll(keepingCapacity: true)
        }

        var index = source.startIndex
        while index < source.endIndex {
            let character = source[index]

            if character == "`" {
                var delimiterCount = 0
                var delimiterIndex = index
                while delimiterIndex < source.endIndex, source[delimiterIndex] == "`" {
                    delimiterCount += 1
                    delimiterIndex = source.index(after: delimiterIndex)
                }

                let delimiter = String(repeating: "`", count: delimiterCount)
                if let closeRange = source[delimiterIndex...].range(of: delimiter) {
                    flushText()
                    let codeText = String(source[delimiterIndex..<closeRange.lowerBound])
                    tokens.append(.code(codeText))
                    index = closeRange.upperBound
                    continue
                }

                buffer.append(delimiter)
                index = delimiterIndex
                continue
            }

            if character == "[" {
                if let closeBracket = source[index...].firstIndex(of: "]") {
                    let afterBracket = source.index(after: closeBracket)
                    if afterBracket < source.endIndex, source[afterBracket] == "(",
                       let closeParen = source[source.index(after: afterBracket)...].firstIndex(of: ")") {
                        let labelStart = source.index(after: index)
                        let targetStart = source.index(after: afterBracket)
                        let label = String(source[labelStart..<closeBracket])
                        let target = String(source[targetStart..<closeParen])
                        flushText()
                        tokens.append(.link(label: label, target: target))
                        index = source.index(after: closeParen)
                        continue
                    }
                }
            }

            if character == "*" {
                let afterFirstAsterisk = source.index(after: index)
                if afterFirstAsterisk < source.endIndex, source[afterFirstAsterisk] == "*" {
                    let contentStart = source.index(after: afterFirstAsterisk)
                    if let closeRange = source[contentStart...].range(of: "**"),
                       closeRange.lowerBound > contentStart {
                        flushText()
                        let boldText = String(source[contentStart..<closeRange.lowerBound])
                        tokens.append(.bold(boldText))
                        index = closeRange.upperBound
                        continue
                    }

                    buffer.append("**")
                    index = contentStart
                    continue
                }
            }

            buffer.append(character)
            index = source.index(after: index)
        }

        flushText()
        return tokens
    }
}
