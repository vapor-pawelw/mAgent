import AppKit

enum SectionHeaderStripStyle {
    static let horizontalInset: CGFloat = 12
    static let verticalInset: CGFloat = 2
    static let cornerRadius: CGFloat = 6
    static let railWidth: CGFloat = 3
    static let railVerticalInset: CGFloat = 5

    static func stripRect(in bounds: NSRect) -> NSRect {
        bounds.insetBy(dx: horizontalInset, dy: verticalInset)
    }

    static func railRect(in bounds: NSRect) -> NSRect {
        let strip = stripRect(in: bounds)
        return NSRect(
            x: strip.minX + 4,
            y: strip.minY + railVerticalInset,
            width: railWidth,
            height: max(0, strip.height - (railVerticalInset * 2))
        )
    }

    static func draw(in bounds: NSRect, color: NSColor, isHovered: Bool) {
        color.withAlphaComponent(isHovered ? 0.16 : 0.10).setFill()
        NSBezierPath(
            roundedRect: stripRect(in: bounds),
            xRadius: cornerRadius,
            yRadius: cornerRadius
        ).fill()

        color.withAlphaComponent(isHovered ? 0.95 : 0.78).setFill()
        NSBezierPath(
            roundedRect: railRect(in: bounds),
            xRadius: railWidth / 2,
            yRadius: railWidth / 2
        ).fill()
    }
}
