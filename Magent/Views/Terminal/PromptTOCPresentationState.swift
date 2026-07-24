import AppKit

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
