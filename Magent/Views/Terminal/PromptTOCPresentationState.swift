import AppKit
import MagentCore

enum PromptTOCContextMenuAction: Equatable {
    case copyPrompt
    case renameThread
    case renameTab

    static let actions: [Self] = [.copyPrompt, .renameThread, .renameTab]
}

struct PromptTOCEntry: Sendable {
    let lineIndex: Int
    let displayText: String
    let fullText: String
    let timing: SubmittedPromptTiming?

    var isAvailableInTerminalHistory: Bool { lineIndex >= 0 }

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

enum PromptTOCCacheMerger {
    static func merge(cachedPrompts: [String], liveEntries: [PromptTOCEntry]) -> [PromptTOCEntry] {
        guard !cachedPrompts.isEmpty else { return liveEntries }
        guard !liveEntries.isEmpty else {
            return cachedPrompts.map { cachedEntry(text: $0) }
        }

        let cached = cachedPrompts.map(normalized(_:))
        let live = liveEntries.map { normalized($0.fullText) }
        var commonSuffixLengths = Array(
            repeating: Array(repeating: 0, count: live.count + 1),
            count: cached.count + 1
        )
        for cachedIndex in cached.indices.reversed() {
            for liveIndex in live.indices.reversed() {
                commonSuffixLengths[cachedIndex][liveIndex] = if cached[cachedIndex] == live[liveIndex] {
                    commonSuffixLengths[cachedIndex + 1][liveIndex + 1] + 1
                } else {
                    max(
                        commonSuffixLengths[cachedIndex + 1][liveIndex],
                        commonSuffixLengths[cachedIndex][liveIndex + 1]
                    )
                }
            }
        }

        var merged: [PromptTOCEntry] = []
        var cachedIndex = 0
        var liveIndex = 0
        while cachedIndex < cached.count, liveIndex < live.count {
            if cached[cachedIndex] == live[liveIndex],
               commonSuffixLengths[cachedIndex + 1][liveIndex]
                == commonSuffixLengths[cachedIndex][liveIndex] {
                // A shortened live tail with repeated text belongs to the newest
                // possible cached occurrence, not an older identical prompt.
                merged.append(cachedEntry(text: cachedPrompts[cachedIndex]))
                cachedIndex += 1
            } else if cached[cachedIndex] == live[liveIndex] {
                merged.append(liveEntries[liveIndex])
                cachedIndex += 1
                liveIndex += 1
            } else if commonSuffixLengths[cachedIndex + 1][liveIndex]
                >= commonSuffixLengths[cachedIndex][liveIndex + 1] {
                merged.append(cachedEntry(text: cachedPrompts[cachedIndex]))
                cachedIndex += 1
            } else {
                merged.append(liveEntries[liveIndex])
                liveIndex += 1
            }
        }
        merged.append(contentsOf: cachedPrompts[cachedIndex...].map { cachedEntry(text: $0) })
        merged.append(contentsOf: liveEntries[liveIndex...])
        return merged
    }

    private static func cachedEntry(text: String) -> PromptTOCEntry {
        PromptTOCEntry(lineIndex: -1, displayText: text, fullText: text)
    }

    private static func normalized(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

struct PromptTOCTimingPresentationState: Equatable {
    let sentAt: Date
    let completedAt: Date?

    init?(timing: SubmittedPromptTiming?) {
        guard let timing else { return nil }
        sentAt = timing.sentAt
        completedAt = timing.completedAt
    }

    func relativeStartComponents(now: Date) -> DateComponents? {
        let elapsed = max(0, now.timeIntervalSince(sentAt))
        switch elapsed {
        case ..<60:
            return nil
        case ..<3_600:
            return DateComponents(minute: -max(1, Int(elapsed / 60)))
        case ..<86_400:
            return DateComponents(hour: -max(1, Int(elapsed / 3_600)))
        default:
            return DateComponents(day: -max(1, Int(elapsed / 86_400)))
        }
    }

    var workedDuration: TimeInterval? {
        completedAt.map { max(0, $0.timeIntervalSince(sentAt)) }
    }

    func exactStartIncludesDate(now: Date, calendar: Calendar = .current) -> Bool {
        !calendar.isDate(sentAt, inSameDayAs: now)
    }

    static func shouldShowWorkedDuration(
        availableWidth: CGFloat,
        startWidth: CGFloat,
        durationWidth: CGFloat,
        spacing: CGFloat
    ) -> Bool {
        startWidth + spacing + durationWidth <= availableWidth
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
    static var cursor: NSCursor { .resizeLeftRight }

    static func dividerColor(appearance: NSAppearance) -> NSColor {
        PromptTOCHeaderLayout.backgroundColor(appearance: appearance)
    }

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
    static let listTopInset: CGFloat = 8

    static func backgroundColor(appearance: NSAppearance) -> NSColor {
        StandardThreadCapsuleBackgroundStyle.fill(
            isSelected: false,
            appearance: appearance,
            accentColor: .controlAccentColor
        )
    }

    static func loadingCountText(knownPromptCount: Int) -> String {
        "\(max(0, knownPromptCount))"
    }

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
