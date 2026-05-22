import Foundation

public enum ChatToolTranscriptKind: String, Sendable, Equatable {
    case call
    case output
}

public struct ChatToolTranscriptPresentation: Sendable, Equatable {
    public var kind: ChatToolTranscriptKind
    public var title: String
    public var detail: String?
    public var body: String

    public init(kind: ChatToolTranscriptKind, title: String, detail: String?, body: String) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.body = body
    }
}

public enum ChatToolTranscriptFormatter {
    public static func toolCallText(name: String, arguments: String) -> String {
        "Tool call: \(name)\n\(arguments)"
    }

    public static func toolOutputText(_ output: String) -> String {
        "Tool output:\n\(output)"
    }

    public static func presentation(for text: String) -> ChatToolTranscriptPresentation? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("Tool call:") {
            let remainder = String(trimmed.dropFirst("Tool call:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = remainder.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            let name = parts.first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "tool"
            let rawBody = parts.count > 1 ? String(parts[1]) : ""
            let formatted = friendlyJSONIfPossible(rawBody) ?? rawBody.trimmingCharacters(in: .whitespacesAndNewlines)
            return ChatToolTranscriptPresentation(
                kind: .call,
                title: "Tool call: \(name)",
                detail: jsonSummary(from: rawBody),
                body: formatted
            )
        }
        if trimmed.hasPrefix("Tool output:") {
            let rawBody = String(trimmed.dropFirst("Tool output:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            let formatted = friendlyJSONIfPossible(rawBody) ?? rawBody
            return ChatToolTranscriptPresentation(
                kind: .output,
                title: "Tool output",
                detail: outputSummary(from: rawBody),
                body: formatted
            )
        }
        return nil
    }

    private static func friendlyJSONIfPossible(_ text: String) -> String? {
        guard let object = jsonObject(from: text) else { return nil }
        if let dictionary = object as? [String: Any] {
            let fields = dictionary.keys.sorted().map { key in
                "\(key): \(friendlyValue(dictionary[key]))"
            }
            return fields.joined(separator: "\n")
        }
        if let array = object as? [Any] {
            return array.enumerated().map { index, value in
                "\(index + 1). \(friendlyValue(value))"
            }.joined(separator: "\n")
        }
        return formattedJSONIfPossible(text)
    }

    private static func formattedJSONIfPossible(_ text: String) -> String? {
        guard let object = jsonObject(from: text),
              JSONSerialization.isValidJSONObject(object),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: pretty, encoding: .utf8) else { return nil }
        return string.replacingOccurrences(of: "\\/", with: "/")
    }

    private static func jsonObject(from text: String) -> Any? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return object
    }

    private static func friendlyValue(_ value: Any?) -> String {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let dictionary as [String: Any]:
            guard !dictionary.isEmpty else { return "{}" }
            return dictionary.keys.sorted().map { key in
                "\(key)=\(friendlyValue(dictionary[key]))"
            }.joined(separator: ", ")
        case let array as [Any]:
            guard !array.isEmpty else { return "[]" }
            return array.map(friendlyValue).joined(separator: ", ")
        case .some:
            return String(describing: value!)
        case .none:
            return "null"
        }
    }

    private static func jsonSummary(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let dictionary = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let preferred = ["cmd", "command", "query", "path", "file_path", "url", "target"]
        for key in preferred {
            if let value = dictionary[key] as? String, !value.isEmpty { return value }
        }
        if let firstKey = dictionary.keys.sorted().first { return "\(dictionary.count) field\(dictionary.count == 1 ? "" : "s") · \(firstKey)" }
        return nil
    }

    private static func outputSummary(from text: String) -> String? {
        let lineCount = text.split(separator: "\n", omittingEmptySubsequences: false).count
        guard lineCount > 1 else { return nil }
        return "\(lineCount) lines"
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
