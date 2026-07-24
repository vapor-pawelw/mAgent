import AppKit

enum PromptTOCPinnedResizeStyle {
    static var dividerColor: NSColor { .tertiaryLabelColor }
    static var cursor: NSCursor { .resizeLeftRight }

    static func dividerRect(in bounds: CGRect) -> CGRect {
        CGRect(x: bounds.minX, y: bounds.minY, width: 1, height: bounds.height)
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
        self.ordinalBadgeWidth = max(20, CGFloat(ordinalText.count * 6 + 8))
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
