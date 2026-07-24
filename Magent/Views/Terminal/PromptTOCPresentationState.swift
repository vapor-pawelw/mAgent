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

enum PromptTOCLatestBadgeStyle {
    static func backgroundColor(isDarkAppearance: Bool) -> NSColor {
        guard !isDarkAppearance else { return .systemGreen }
        return NSColor.systemGreen.blended(withFraction: 0.30, of: .black) ?? .systemGreen
    }

    static func textColor(isDarkAppearance: Bool) -> NSColor {
        isDarkAppearance ? .black : .white
    }
}

struct PromptTOCRowPresentation: Equatable {
    let ordinalText: String
    let promptText: String
    let promptFontSize: CGFloat
    let maximumPromptLines: Int
    let ordinalBadgeWidth: CGFloat
    let showsLatestMarker: Bool

    init(entryIndex: Int, promptText: String, isPinned: Bool, isLatest: Bool = false) {
        let ordinalText = "\(entryIndex + 1)"
        self.ordinalText = ordinalText
        self.promptText = promptText
        self.promptFontSize = isPinned ? 12 : 11
        self.maximumPromptLines = isPinned ? 5 : 3
        self.ordinalBadgeWidth = PromptTOCOrdinalBadgeStyle.width(for: ordinalText)
        self.showsLatestMarker = isLatest
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
