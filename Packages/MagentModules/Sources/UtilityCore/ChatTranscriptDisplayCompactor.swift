import Foundation
import MagentModels

public enum ChatTranscriptDisplayCompactor {
    private static let minimumRunLength = 2
    private static let maximumVisibleItems = 12
    private static let maximumSummaryLineLength = 96

    public static func compactedMessages(_ messages: [PersistedChatMessage]) -> [PersistedChatMessage] {
        var compacted: [PersistedChatMessage] = []
        var index = messages.startIndex

        while index < messages.endIndex {
            let runStart = index
            var run: [PersistedChatMessage] = []
            while index < messages.endIndex, isCompactable(messages[index]) {
                run.append(messages[index])
                index = messages.index(after: index)
            }

            if run.count >= minimumRunLength {
                compacted.append(summaryMessage(for: run))
            } else if !run.isEmpty {
                compacted.append(contentsOf: run)
            } else {
                compacted.append(messages[runStart])
                index = messages.index(after: runStart)
            }
        }

        return compacted
    }

    private static func isCompactable(_ message: PersistedChatMessage) -> Bool {
        guard message.role == .assistant, message.attachments.isEmpty else { return false }
        switch ChatMessageDisplayPlanner.plan(for: message).kind {
        case .tool, .status:
            return true
        case .message:
            return false
        }
    }

    private static func summaryMessage(for run: [PersistedChatMessage]) -> PersistedChatMessage {
        let visibleSummaries = run.prefix(maximumVisibleItems).map(summaryLine(for:))
        let hiddenCount = max(0, run.count - visibleSummaries.count)
        var lines = [
            "Activity",
            "\(run.count) internal \(run.count == 1 ? "step" : "steps") completed.",
        ]
        lines.append(contentsOf: visibleSummaries.map { "\($0.symbol) \($0.text)" })
        if hiddenCount > 0 {
            lines.append("ellipsis.circle \(hiddenCount) more \(hiddenCount == 1 ? "step" : "steps")")
        }

        return PersistedChatMessage(
            id: run.first?.id ?? UUID(),
            role: .assistant,
            text: lines.joined(separator: "\n"),
            createdAt: run.first?.createdAt ?? Date(),
            modelId: run.last?.modelId,
            reasoningLevel: run.last?.reasoningLevel
        )
    }

    private static func summaryLine(for message: PersistedChatMessage) -> (symbol: String, text: String) {
        if let toolEvent = message.toolEvent {
            return summaryLine(for: toolEvent)
        }
        switch ChatMessageDisplayPlanner.plan(for: message).kind {
        case .tool(let presentation):
            return (
                symbol: symbolName(for: presentation.kind),
                text: [presentation.title, presentation.detail]
                    .compactMap { normalizedNonEmpty($0) }
                    .joined(separator: ": ")
            )
        case .status(let presentation):
            return (
                symbol: symbolName(for: presentation.kind),
                text: [presentation.title, presentation.detail]
                    .compactMap { normalizedNonEmpty($0) }
                    .joined(separator: ": ")
            )
        case .message:
            return (symbol: "message", text: normalizedNonEmpty(message.text) ?? "Message")
        }
    }

    private static func summaryLine(for event: PersistedChatToolEvent) -> (symbol: String, text: String) {
        let presentation = ChatToolTranscriptFormatter.presentation(for: event)
        switch event.kind {
        case .call, .result:
            return (
                symbol: symbolName(for: presentation.kind),
                text: [presentation.kind == .result ? completedTitle(for: event) : presentation.title, presentation.detail]
                    .compactMap { normalizedNonEmpty($0) }
                    .joined(separator: ": ")
            )
        case .output:
            return (
                symbol: symbolName(for: presentation.kind),
                text: [presentation.title, presentation.detail]
                    .compactMap { normalizedNonEmpty($0) }
                    .joined(separator: ": ")
            )
        }
    }

    private static func completedTitle(for event: PersistedChatToolEvent) -> String {
        let callPresentation = ChatToolTranscriptFormatter.presentation(
            for: PersistedChatToolEvent(
                kind: .call,
                name: event.name,
                arguments: event.arguments
            )
        )
        if callPresentation.title.hasPrefix("Run command") {
            return "Command finished"
        }
        if callPresentation.title.hasPrefix("Edit file") {
            return "Edit finished"
        }
        if callPresentation.title.hasPrefix("Read file") {
            return "Read finished"
        }
        return "\(callPresentation.title) finished"
    }

    private static func symbolName(for kind: ChatToolTranscriptKind) -> String {
        switch kind {
        case .call: return "play.circle"
        case .output: return "text.alignleft"
        case .result: return "checkmark.circle"
        }
    }

    private static func symbolName(for kind: ChatMessageStatusKind) -> String {
        switch kind {
        case .cancellation: return "xmark.circle"
        case .approvalRequired: return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        }
    }

    public static func sfSymbolName(fromActivitySummaryLine line: String) -> (symbolName: String, text: String)? {
        let knownSymbols = [
            "play.circle",
            "text.alignleft",
            "checkmark.circle",
            "xmark.circle",
            "exclamationmark.triangle",
            "xmark.octagon",
            "message",
            "ellipsis.circle",
        ]
        for symbolName in knownSymbols {
            let prefix = "\(symbolName) "
            guard line.hasPrefix(prefix) else { continue }
            let text = String(line.dropFirst(prefix.count))
            return (symbolName: symbolName, text: text)
        }
        return nil
    }

    public static func isActivitySummary(_ message: PersistedChatMessage) -> Bool {
        message.role == .assistant && message.text.hasPrefix("Activity\n")
    }

    public static func plainText(fromActivitySummary text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let string = String(line)
                return sfSymbolName(fromActivitySummaryLine: string)?.text ?? string
            }
            .joined(separator: "\n")
    }

    public static func activityPresentation(for message: PersistedChatMessage) -> ChatToolTranscriptPresentation? {
        guard isActivitySummary(message) else { return nil }
        let lines = message.text.components(separatedBy: "\n")
        let detail = lines.dropFirst().first?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rows = lines.dropFirst(2).compactMap(abbreviatedActivityRow)
        return ChatToolTranscriptPresentation(
            kind: .output,
            title: "Activity",
            detail: detail?.isEmpty == false ? detail : nil,
            body: rows.isEmpty ? "No activity details." : rows.joined(separator: "\n"),
            isExpandedByDefault: false
        )
    }

    private static func normalizedNonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func abbreviatedActivityRow(from line: String) -> String? {
        let parsed = sfSymbolName(fromActivitySummaryLine: line)
        let rawText = parsed?.text ?? line
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let parsed else { return abbreviatedActivityText(trimmed) }
        return "\(parsed.symbolName) \(abbreviatedActivityText(trimmed))"
    }

    private static func abbreviatedActivityText(_ text: String) -> String {
        guard text.count > maximumSummaryLineLength else { return text }
        let end = text.index(text.startIndex, offsetBy: max(0, maximumSummaryLineLength - 1))
        return String(text[..<end]) + "…"
    }
}
