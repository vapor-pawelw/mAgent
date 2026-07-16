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
