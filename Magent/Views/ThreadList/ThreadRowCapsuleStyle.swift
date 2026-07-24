import AppKit

enum ThreadRowCapsuleVisualState: Equatable {
    case selected
    case rateLimited
    case waiting
    case completed
    case poppedOut
    case idle

    static func resolve(
        isSelected: Bool,
        showsRateLimitHighlight: Bool,
        showsWaitingHighlight: Bool,
        showsCompletionHighlight: Bool,
        showsPopoutTint: Bool
    ) -> Self {
        if isSelected { return .selected }
        if showsRateLimitHighlight { return .rateLimited }
        if showsWaitingHighlight { return .waiting }
        if showsCompletionHighlight { return .completed }
        if showsPopoutTint { return .poppedOut }
        return .idle
    }
}

enum StandardThreadCapsuleBackgroundStyle {
    static func fill(
        isSelected: Bool,
        appearance: NSAppearance,
        accentColor: NSColor
    ) -> NSColor {
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        if isSelected {
            return accentColor.withAlphaComponent(isDark ? 0.1 : 0.2)
        }
        return isDark
            ? NSColor.white.withAlphaComponent(0.035)
            : NSColor.black.withAlphaComponent(0.03)
    }
}

enum ThreadCreationSourceCapsuleBackgroundStyle {
    static func fill(
        showsExpandedDetails: Bool,
        isSelected: Bool,
        appearance: NSAppearance,
        accentColor: NSColor
    ) -> NSColor {
        guard showsExpandedDetails else { return .controlBackgroundColor }
        return StandardThreadCapsuleBackgroundStyle.fill(
            isSelected: isSelected,
            appearance: appearance,
            accentColor: accentColor
        )
    }
}

enum CompletedCapsuleStyle {
    static let fillOpacity: CGFloat = 0.06
    static let borderOpacity: CGFloat = 0.5
    static let borderWidth: CGFloat = 1

    static func apply(to layer: CALayer, appearance: NSAppearance) {
        appearance.performAsCurrentDrawingAppearance {
            layer.backgroundColor = NSColor.systemGreen.withAlphaComponent(fillOpacity).cgColor
            layer.borderWidth = borderWidth
            layer.borderColor = NSColor.systemGreen.withAlphaComponent(borderOpacity).cgColor
        }
    }

    static func shouldPresentOnTab(
        isSelected: Bool,
        hasUnreadCompletion: Bool,
        hasTerminalCorruption: Bool,
        hasWaitingForInput: Bool,
        hasBusy: Bool,
        hasRateLimit: Bool,
        hasUnreadRateLimit: Bool
    ) -> Bool {
        hasUnreadCompletion
            && !isSelected
            && !hasTerminalCorruption
            && !hasWaitingForInput
            && !hasBusy
            && !hasRateLimit
            && !hasUnreadRateLimit
    }
}

enum ThreadCapsuleSectionMarkerStyle {
    static let capsuleCornerRadius: CGFloat = 8
    static let capsuleLeadingInset: CGFloat = 12
    static let capsuleTrailingInset: CGFloat = 12
    static let capsuleVerticalInset: CGFloat = 4
    static let markerWidth: CGFloat = 4
    static let cornerOffset: CGFloat = 12

    static func color(sectionColor: NSColor?, isSelected: Bool) -> NSColor {
        sectionColor?.withAlphaComponent(isSelected ? 1 : 0.40) ?? .clear
    }

    static func vertices(in capsuleRect: NSRect, isFlipped: Bool) -> [NSPoint] {
        let top = isFlipped ? capsuleRect.minY : capsuleRect.maxY
        let inwardDirection: CGFloat = isFlipped ? 1 : -1
        let edgeHalfSpan = markerWidth / sqrt(2)
        let nearOffset = cornerOffset - edgeHalfSpan
        let farOffset = cornerOffset + edgeHalfSpan
        return [
            NSPoint(x: capsuleRect.maxX - farOffset, y: top),
            NSPoint(x: capsuleRect.maxX - nearOffset, y: top),
            NSPoint(x: capsuleRect.maxX, y: top + (nearOffset * inwardDirection)),
            NSPoint(x: capsuleRect.maxX, y: top + (farOffset * inwardDirection)),
        ]
    }
}
