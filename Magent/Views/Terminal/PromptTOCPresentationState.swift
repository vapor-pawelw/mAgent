import AppKit
import MagentCore

struct PromptTOCEntry: Sendable {
    let lineIndex: Int
    let displayText: String
    let fullText: String
    let timing: SubmittedPromptTiming?

    init(
        lineIndex: Int,
        displayText: String,
        fullText: String,
        timing: SubmittedPromptTiming? = nil
    ) {
        self.lineIndex = lineIndex
        self.displayText = displayText
        self.fullText = fullText
        self.timing = timing
    }
}

enum PromptTOCTimingResolver {
    static func attaching(
        _ timings: [SubmittedPromptTiming],
        to entries: [PromptTOCEntry]
    ) -> [PromptTOCEntry] {
        var resolved = entries
        var nextTimingIndex = timings.endIndex

        for entryIndex in entries.indices.reversed() {
            guard let matchingIndex = timings.indices[..<nextTimingIndex].last(where: {
                timingText(timings[$0].text, matches: entries[entryIndex].fullText)
            }) else {
                continue
            }
            nextTimingIndex = matchingIndex
            resolved[entryIndex] = PromptTOCEntry(
                lineIndex: entries[entryIndex].lineIndex,
                displayText: entries[entryIndex].displayText,
                fullText: entries[entryIndex].fullText,
                timing: timings[matchingIndex]
            )
        }
        return resolved
    }

    private static func normalized(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func timingText(_ timingText: String, matches promptText: String) -> Bool {
        let normalizedTiming = normalized(timingText)
        let normalizedPrompt = normalized(promptText)
        if normalizedTiming == normalizedPrompt {
            return true
        }
        return normalizedTiming.count >= 80 && normalizedPrompt.hasSuffix(normalizedTiming)
    }
}

enum PromptTOCFooterState: Equatable {
    case inProgress(sentAt: Date)
    case completed(sentAt: Date, completedAt: Date)

    init?(timing: SubmittedPromptTiming?) {
        guard let timing else { return nil }
        if let completedAt = timing.completedAt {
            self = .completed(sentAt: timing.sentAt, completedAt: completedAt)
        } else {
            self = .inProgress(sentAt: timing.sentAt)
        }
    }
}

struct PromptTOCNavigationTarget: Equatable {
    let fullText: String
    let matchingOccurrenceFromNewest: Int

    init?(entryIndex: Int, entries: [PromptTOCEntry]) {
        guard entries.indices.contains(entryIndex) else { return nil }
        let selectedFullText = entries[entryIndex].fullText
        fullText = selectedFullText
        matchingOccurrenceFromNewest = entries[(entryIndex + 1)...]
            .filter { $0.fullText == selectedFullText }
            .count
    }

    func resolve(in entries: [PromptTOCEntry]) -> PromptTOCEntry? {
        entries.reversed()
            .filter { $0.fullText == fullText }
            .dropFirst(matchingOccurrenceFromNewest)
            .first
    }
}

enum PromptTOCRefreshPolicy {
    static let periodicInterval: TimeInterval = 3
    static let emptyCaptureRetryDelays: [TimeInterval] = [0, 0.2, 0.5, 1]

    static func shouldRetryEmptyEntries(knownPromptCount: Int) -> Bool {
        knownPromptCount > 0
    }
}

enum PromptTOCPinnedResizeStyle {
    static var dividerColor: NSColor { .tertiaryLabelColor }
    static var cursor: NSCursor { .resizeLeftRight }

    static func dividerRect(in bounds: CGRect) -> CGRect {
        CGRect(x: bounds.minX, y: bounds.minY, width: 1, height: bounds.height)
    }
}

enum PromptTOCOrdinalBadgeStyle {
    static let height: CGFloat = 16
    static let fontSize: CGFloat = 9

    static func width(for ordinalText: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let measuredWidth = (ordinalText as NSString).size(withAttributes: [.font: font]).width
        return max(height, ceil(measuredWidth) + 6)
    }

    static func numberColor(isDarkAppearance: Bool) -> NSColor {
        isDarkAppearance ? .white : .labelColor
    }
}

enum PromptTOCHeaderLayout {
    static let countFont = NSFont.systemFont(ofSize: 13, weight: .bold)
    static let countLabelHorizontalInset: CGFloat = 6
    static let countBadgeMinimumWidth: CGFloat = 20

    static func countBadgeWidth(for text: String) -> CGFloat {
        let measuredWidth = (text as NSString).size(withAttributes: [.font: countFont]).width
        return max(countBadgeMinimumWidth, ceil(measuredWidth) + (2 * countLabelHorizontalInset))
    }
}

struct PromptTOCRowPresentation: Equatable {
    let ordinalText: String
    let promptText: String
    let promptFontSize: CGFloat
    let maximumPromptLines: Int
    let ordinalBadgeWidth: CGFloat

    init(entryIndex: Int, promptText: String, isPinned: Bool) {
        let ordinalText = "\(entryIndex + 1)"
        self.ordinalText = ordinalText
        self.promptText = promptText
        self.promptFontSize = isPinned ? 12 : 11
        self.maximumPromptLines = isPinned ? 5 : 3
        self.ordinalBadgeWidth = PromptTOCOrdinalBadgeStyle.width(for: ordinalText)
    }
}

enum PromptTOCListPresentation {
    static func displayEntryIndexes(entryCount: Int) -> [Int] {
        Array((0..<max(0, entryCount)).reversed())
    }

    static func selectedEntryIndex(
        previousSelection: Int?,
        entryCount: Int,
        didAppendNewestEntry: Bool = false
    ) -> Int? {
        guard entryCount > 0 else { return nil }
        if didAppendNewestEntry {
            return entryCount - 1
        }
        if let previousSelection, previousSelection >= 0, previousSelection < entryCount {
            return previousSelection
        }
        return entryCount - 1
    }

    static func didAppendNewestEntry(
        previousEntryCount: Int,
        currentEntryCount: Int,
        previousNewestEntryIndex: Int?
    ) -> Bool {
        guard previousEntryCount > 0, currentEntryCount > 0 else { return false }
        if currentEntryCount > previousEntryCount {
            return true
        }
        guard let previousNewestEntryIndex else { return false }
        return previousNewestEntryIndex < currentEntryCount - 1
    }

    static func isAtNewestEdge(offsetY: CGFloat, tolerance: CGFloat) -> Bool {
        offsetY <= tolerance
    }

    static func preservedOlderOffset(
        previousOffsetY: CGFloat,
        insertedContentHeight: CGFloat
    ) -> CGFloat {
        previousOffsetY + max(0, insertedContentHeight)
    }
}

enum PromptTOCContentWidthMode: Equatable {
    case fullWidth
    case reservesTrailingTOC

    static func resolve(isPinned: Bool, isTOCVisible: Bool) -> Self {
        isPinned && isTOCVisible ? .reservesTrailingTOC : .fullWidth
    }
}

struct PromptTOCPresentationState: Equatable {
    var isPinned: Bool
    var isHovered: Bool

    var isExpanded: Bool {
        isPinned || isHovered
    }

    var showsPinButton: Bool {
        isPinned || isHovered
    }

    var showsCornerResizeHandles: Bool {
        !isPinned && isHovered
    }

    static func pinnedWidth(
        requestedWidth: CGFloat,
        availableWidth: CGFloat,
        minimumTOCWidth: CGFloat,
        minimumContentWidth: CGFloat
    ) -> CGFloat {
        let maximumWidth = max(minimumTOCWidth, availableWidth - minimumContentWidth)
        return min(max(minimumTOCWidth, requestedWidth), maximumWidth)
    }
}
