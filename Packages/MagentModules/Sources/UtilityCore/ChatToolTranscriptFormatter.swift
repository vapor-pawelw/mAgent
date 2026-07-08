import Foundation

public enum ChatToolTranscriptKind: String, Sendable, Equatable {
    case call
    case output
    case result
}

public struct ChatToolTranscriptPresentation: Sendable, Equatable {
    public var kind: ChatToolTranscriptKind
    public var title: String
    public var detail: String?
    public var body: String
    public var isExpandedByDefault: Bool

    public init(
        kind: ChatToolTranscriptKind,
        title: String,
        detail: String?,
        body: String,
        isExpandedByDefault: Bool = false
    ) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.body = body
        self.isExpandedByDefault = isExpandedByDefault
    }
}

public enum ChatTranscriptEvent: Sendable, Equatable {
    case message(role: ChatTranscriptMessageRole, text: String)
    case tool(ChatToolTranscriptEvent)
}

public enum ChatTranscriptMessageRole: String, Sendable, Equatable {
    case user
    case assistant
    case system
}

public struct ChatToolTranscriptEvent: Sendable, Equatable {
    public var kind: ChatToolTranscriptKind
    public var name: String?
    public var arguments: String?
    public var output: String?
    public var outputName: String?
    public var exitCode: String?
    public var runningSessionID: String?
    public var wallTime: String?
    public var outputLineCount: String?

    public init(
        kind: ChatToolTranscriptKind,
        name: String? = nil,
        arguments: String? = nil,
        output: String? = nil,
        outputName: String? = nil,
        exitCode: String? = nil,
        runningSessionID: String? = nil,
        wallTime: String? = nil,
        outputLineCount: String? = nil
    ) {
        self.kind = kind
        self.name = name
        self.arguments = arguments
        self.output = output
        self.outputName = outputName
        self.exitCode = exitCode
        self.runningSessionID = runningSessionID
        self.wallTime = wallTime
        self.outputLineCount = outputLineCount
    }
}

public enum ChatToolTranscriptFormatter {
    private struct ToolOutputEnvelope {
        var chunkID: String?
        var wallTime: String?
        var exitCode: String?
        var sessionID: String?
        var tokenCount: String?
        var outputLineCount: String?
        var output: String

        init(
            chunkID: String? = nil,
            wallTime: String? = nil,
            exitCode: String? = nil,
            sessionID: String? = nil,
            tokenCount: String? = nil,
            outputLineCount: String? = nil,
            output: String
        ) {
            self.chunkID = chunkID
            self.wallTime = wallTime
            self.exitCode = exitCode
            self.sessionID = sessionID
            self.tokenCount = tokenCount
            self.outputLineCount = outputLineCount
            self.output = output
        }
    }

    public static func event(for text: String) -> ChatTranscriptEvent? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let toolEvent = toolEvent(forTrimmedText: trimmed) {
            return .tool(toolEvent)
        }
        return nil
    }

    public static func toolCallText(name: String, arguments: String) -> String {
        "Tool call: \(name)\n\(arguments)"
    }

    public static func toolOutputText(_ output: String, name: String? = nil) -> String {
        if let cleanName = name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            return "Tool output: \(cleanName)\n\(output)"
        }
        return "Tool output:\n\(output)"
    }

    public static func toolResultText(name: String, arguments: String, output: String) -> String {
        """
        Tool result: \(name)
        Arguments:
        \(arguments)
        Output:
        \(output)
        """
    }

    public static func presentation(for text: String) -> ChatToolTranscriptPresentation? {
        guard let event = event(for: text),
              case .tool(let toolEvent) = event else { return nil }
        return presentation(for: toolEvent)
    }

    public static func presentation(for event: ChatToolTranscriptEvent) -> ChatToolTranscriptPresentation {
        switch event.kind {
        case .call:
            let name = event.name?.nilIfBlank ?? "tool"
            let rawBody = event.arguments ?? ""
            let formatted = formattedToolCallArguments(rawBody)
            let summary = toolActionSummary(name: name, arguments: rawBody)
            return ChatToolTranscriptPresentation(
                kind: .call,
                title: summary.title,
                detail: summary.detail ?? jsonSummary(from: rawBody),
                body: formatted
            )
        case .result:
            let name = event.name?.nilIfBlank ?? "tool"
            let arguments = event.arguments ?? ""
            let envelope = envelope(from: event, fallbackOutput: event.output ?? "")
            let outputBody = formattedToolOutput(envelope)
            let argumentsBody = formattedToolResultArguments(arguments, toolName: name)
            let actionSummary = toolActionSummary(name: name, arguments: arguments)
            let outputSummary = outputContentSummary(from: envelope, fallbackText: event.output ?? "")
            let title = outputSummary.map { "\(actionSummary.completedTitle): \($0)" } ?? actionSummary.completedTitle
            return ChatToolTranscriptPresentation(
                kind: .result,
                title: abbreviated(title, maxLength: 140),
                detail: statusSummary(from: envelope, fallbackText: event.output ?? "", prefix: actionSummary.detail),
                body: [outputBody, argumentsBody].filter { !$0.isEmpty }.joined(separator: "\n\n"),
                isExpandedByDefault: shouldExpandOutput(envelope)
            )
        case .output:
            let envelope = envelope(from: event, fallbackOutput: event.output ?? "")
            let formatted = formattedToolOutput(envelope)
            let summary = outputContentSummary(from: envelope, fallbackText: event.output ?? "")
            let status = statusSummary(from: envelope, fallbackText: event.output ?? "", prefix: event.outputName)
            return ChatToolTranscriptPresentation(
                kind: .output,
                title: abbreviated(summary.map { "Tool output: \($0)" } ?? event.outputName ?? "Tool output", maxLength: 140),
                detail: status,
                body: formatted,
                isExpandedByDefault: shouldExpandOutput(envelope)
            )
        }
    }

    private static func toolEvent(forTrimmedText trimmed: String) -> ChatToolTranscriptEvent? {
        if trimmed.hasPrefix("Tool call:") {
            let remainder = String(trimmed.dropFirst("Tool call:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = remainder.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            let name = parts.first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "tool"
            let rawBody = parts.count > 1 ? String(parts[1]) : ""
            return ChatToolTranscriptEvent(
                kind: .call,
                name: name,
                arguments: rawBody
            )
        }
        if trimmed.hasPrefix("Tool result:") {
            let remainder = String(trimmed.dropFirst("Tool result:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = remainder.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            let name = parts.first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "tool"
            let rawBody = parts.count > 1 ? String(parts[1]) : ""
            let split = splitToolResultBody(rawBody)
            let envelope = parseToolOutputEnvelope(split.output)
            return ChatToolTranscriptEvent(
                kind: .result,
                name: name,
                arguments: split.arguments,
                output: envelope.output,
                exitCode: envelope.exitCode,
                runningSessionID: envelope.sessionID,
                wallTime: envelope.wallTime,
                outputLineCount: envelope.outputLineCount
            )
        }
        if trimmed.hasPrefix("Tool output:") {
            let rawRemainder = String(trimmed.dropFirst("Tool output:".count))
            let remainder = rawRemainder.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = remainder.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            let outputName: String?
            let rawBody: String
            if !rawRemainder.hasPrefix("\n"),
               !rawRemainder.hasPrefix("\r\n"),
               parts.count > 1,
               let firstLine = parts.first.map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty {
                outputName = firstLine
                rawBody = String(parts[1])
            } else {
                outputName = nil
                rawBody = remainder
            }
            let envelope = parseToolOutputEnvelope(rawBody)
            return ChatToolTranscriptEvent(
                kind: .output,
                output: envelope.output,
                outputName: outputName,
                exitCode: envelope.exitCode,
                runningSessionID: envelope.sessionID,
                wallTime: envelope.wallTime,
                outputLineCount: envelope.outputLineCount
            )
        }
        return nil
    }

    private static func envelope(from event: ChatToolTranscriptEvent, fallbackOutput: String) -> ToolOutputEnvelope {
        ToolOutputEnvelope(
            wallTime: event.wallTime,
            exitCode: event.exitCode,
            sessionID: event.runningSessionID,
            outputLineCount: event.outputLineCount,
            output: event.output ?? fallbackOutput
        )
    }

    private static func splitToolResultBody(_ text: String) -> (arguments: String, output: String) {
        guard let outputRange = text.range(of: "\nOutput:\n") else {
            return ("", text)
        }
        var arguments = String(text[..<outputRange.lowerBound])
        if arguments.hasPrefix("Arguments:\n") {
            arguments = String(arguments.dropFirst("Arguments:\n".count))
        }
        let output = String(text[outputRange.upperBound...])
        return (arguments.trimmingCharacters(in: .whitespacesAndNewlines), output)
    }

    private static func formattedToolResultArguments(_ arguments: String, toolName: String) -> String {
        let trimmed = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if toolName == "apply_patch" {
            return section("Patch", trimmed)
        }
        return formattedToolCallArguments(trimmed)
    }

    private static func formattedToolCallArguments(_ text: String) -> String {
        guard let object = jsonObject(from: text) else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let dictionary = object as? [String: Any] else {
            return section("Arguments", friendlyValue(object))
        }

        var lines: [String] = []
        if let command = dictionary["cmd"] as? String ?? dictionary["command"] as? String {
            lines.append(section("Command", command))
        }
        if let workdir = dictionary["workdir"] as? String {
            lines.append(section("Working directory", workdir))
        }

        let primaryKeys = Set(["cmd", "command", "workdir"])
        let remaining = dictionary.keys
            .filter { !primaryKeys.contains($0) }
            .sorted()
            .map { formattedArgumentLine(key: $0, value: dictionary[$0]) }

        if !remaining.isEmpty {
            lines.append(section("Options", remaining.joined(separator: "\n")))
        }

        return lines.joined(separator: "\n\n")
    }

    private static func parseToolOutputEnvelope(_ text: String) -> ToolOutputEnvelope {
        var envelope = ToolOutputEnvelope(output: text)
        var remaining: [String] = []
        var hasEnvelope = false
        var isOutput = false

        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if isOutput {
                remaining.append(line)
                continue
            }
            if line == "Output:" {
                hasEnvelope = true
                isOutput = true
                continue
            }
            if let value = line.value(afterPrefix: "Chunk ID:") {
                envelope.chunkID = value
                hasEnvelope = true
            } else if let value = line.value(afterPrefix: "Wall time:") {
                envelope.wallTime = value
                hasEnvelope = true
            } else if let value = line.value(afterPrefix: "Original token count:") {
                envelope.tokenCount = value
                hasEnvelope = true
            } else if let value = line.value(afterPrefix: "Process exited with code") {
                envelope.exitCode = value
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else if let value = line.value(afterPrefix: "Process running with session ID") {
                envelope.sessionID = value
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else if let value = line.value(afterPrefix: "Total output lines:") {
                envelope.outputLineCount = value
                hasEnvelope = true
            } else {
                remaining.append(line)
            }
        }

        guard hasEnvelope else { return envelope }
        envelope.output = remaining.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if let firstLine = envelope.output.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first,
           let value = String(firstLine).value(afterPrefix: "Total output lines:") {
            envelope.outputLineCount = value
            envelope.output = envelope.output
                .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
                .dropFirst()
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return envelope
    }

    private static func formattedToolOutput(_ envelope: ToolOutputEnvelope) -> String {
        var sections: [String] = []
        var statusLines: [String] = []
        if let exitCode = envelope.exitCode, exitCode != "0" {
            statusLines.append("Exit code: \(exitCode)")
        }
        if let sessionID = envelope.sessionID {
            statusLines.append("Running session: \(sessionID)")
        }

        let output = envelope.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if let formattedOutput = friendlyJSONIfPossible(output) ?? output.nilIfEmpty {
            sections.append(section("Output", formattedOutput))
        }

        if !statusLines.isEmpty {
            sections.append(section("Status", statusLines.joined(separator: "\n")))
        }

        if sections.isEmpty {
            sections.append(section("Output", "(No output)"))
        }
        return sections.joined(separator: "\n\n")
    }

    private static func section(_ title: String, _ body: String) -> String {
        "\(title)\n\(body)"
    }

    private static func formattedArgumentLine(key: String, value: Any?) -> String {
        var formattedValue = friendlyValue(value)
        if key == "yield_time_ms", !formattedValue.hasSuffix("ms") {
            formattedValue += " ms"
        }
        return "\(humanizedKey(key)): \(formattedValue)"
    }

    private static func friendlyJSONIfPossible(_ text: String) -> String? {
        guard let object = jsonObject(from: text) else { return nil }
        if let dictionary = object as? [String: Any] {
            let fields = dictionary.keys.sorted().map { key in
                "\(humanizedKey(key)): \(friendlyValue(dictionary[key]))"
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
        case let bool as Bool:
            return bool ? "true" : "false"
        case let number as NSNumber:
            return number.stringValue
        case let dictionary as [String: Any]:
            guard !dictionary.isEmpty else { return "{}" }
            return dictionary.keys.sorted().map { key in
                "\(humanizedKey(key))=\(friendlyValue(dictionary[key]))"
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

    private static func toolActionSummary(name: String, arguments: String) -> (title: String, completedTitle: String, detail: String?) {
        guard let dictionary = jsonObject(from: arguments) as? [String: Any] else {
            let cleanName = humanizedToolName(name)
            return (cleanName, "\(cleanName) finished", nil)
        }

        if let command = dictionary["cmd"] as? String ?? dictionary["command"] as? String {
            let cleanCommand = command.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            return ("Run command", "Command finished", cleanCommand)
        }
        if let path = dictionary["file_path"] as? String ?? dictionary["path"] as? String {
            let cleanPath = path.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            let title = actionTitleForToolName(name, fallback: "Open file")
            return (title, "\(title) finished", cleanPath)
        }
        if let query = dictionary["query"] as? String ?? dictionary["pattern"] as? String {
            let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            let title = actionTitleForToolName(name, fallback: "Search")
            return (title, "\(title) finished", cleanQuery)
        }
        if let url = dictionary["url"] as? String {
            let cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            return ("Open URL", "URL request finished", cleanURL)
        }

        let cleanName = humanizedToolName(name)
        return (cleanName, "\(cleanName) finished", jsonSummary(from: arguments))
    }

    private static func actionTitleForToolName(_ name: String, fallback: String) -> String {
        let lowercased = name.lowercased()
        if lowercased.contains("read") || lowercased.contains("open") {
            return "Read file"
        }
        if lowercased.contains("write") || lowercased.contains("edit") || lowercased.contains("patch") {
            return "Edit file"
        }
        if lowercased.contains("grep") || lowercased.contains("search") || lowercased.contains("find") {
            return "Search"
        }
        return fallback
    }

    private static func humanizedToolName(_ name: String) -> String {
        let clean = name
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return "Tool call" }
        return clean
            .split(separator: " ")
            .map { word in
                guard let first = word.first else { return "" }
                return first.uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }

    private static func outputContentSummary(from envelope: ToolOutputEnvelope, fallbackText: String) -> String? {
        let output = (envelope.output.nilIfEmpty ?? fallbackText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else { return nil }

        if let dictionary = jsonObject(from: output) as? [String: Any] {
            let preferredKeys = ["changed", "files", "file", "path", "message", "error", "stdout", "stderr", "result"]
            let parts = preferredKeys.compactMap { key -> String? in
                guard let value = dictionary[key] else { return nil }
                return "\(humanizedKey(key)): \(friendlyValue(value))"
            }
            if !parts.isEmpty {
                return abbreviated(parts.joined(separator: " · "), maxLength: 120)
            }
            let allParts = dictionary.keys.sorted().prefix(2).compactMap { key -> String? in
                guard let value = dictionary[key] else { return nil }
                return "\(humanizedKey(key)): \(friendlyValue(value))"
            }
            if !allParts.isEmpty {
                return abbreviated(allParts.joined(separator: " · "), maxLength: 120)
            }
        }

        let firstLine = output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return firstLine.flatMap { abbreviated($0, maxLength: 120).nilIfEmpty }
    }

    private static func outputSummary(
        from envelope: ToolOutputEnvelope,
        fallbackText: String,
        prefix: String? = nil
    ) -> String? {
        var parts: [String] = []
        if let prefix {
            parts.append(prefix)
        }
        if let exitCode = envelope.exitCode, exitCode != "0" {
            parts.append("exit \(exitCode)")
        } else if let sessionID = envelope.sessionID {
            parts.append("running \(sessionID)")
        }
        if !parts.isEmpty, let wallTime = envelope.wallTime {
            parts.append(wallTime)
        }
        if !parts.isEmpty, let outputLineCount = envelope.outputLineCount {
            parts.append("\(outputLineCount) lines")
        } else {
            let textToCount = envelope.output.nilIfEmpty ?? fallbackText
            let lineCount = textToCount.split(separator: "\n", omittingEmptySubsequences: false).count
            if !parts.isEmpty, lineCount > 1 {
                parts.append("\(lineCount) lines")
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func statusSummary(
        from envelope: ToolOutputEnvelope,
        fallbackText: String,
        prefix: String? = nil
    ) -> String? {
        outputSummary(from: envelope, fallbackText: fallbackText, prefix: prefix)
    }

    private static func shouldExpandOutput(_ envelope: ToolOutputEnvelope) -> Bool {
        if let exitCode = envelope.exitCode, exitCode != "0" {
            return true
        }
        if envelope.sessionID != nil {
            return true
        }
        return false
    }

    private static func abbreviated(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        let end = text.index(text.startIndex, offsetBy: max(0, maxLength - 1))
        return String(text[..<end]) + "…"
    }

    private static func humanizedKey(_ key: String) -> String {
        switch key {
        case "cmd": return "Command"
        case "max_output_tokens": return "Max output tokens"
        case "yield_time_ms": return "Yield time"
        case "workdir": return "Working directory"
        case "file_path": return "File path"
        default: break
        }
        let spaced = key
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        guard let first = spaced.first else { return key }
        return first.uppercased() + spaced.dropFirst()
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func value(afterPrefix prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
