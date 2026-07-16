import AppKit

enum SectionHeaderStripStyle {
    static let verticalInset: CGFloat = 2
    static let contentLeadingInset: CGFloat = 12
    static let contentTrailingInset: CGFloat = 20

    static func badgeForegroundColor(sectionColor: NSColor, appearance: NSAppearance) -> NSColor {
        BadgeForegroundStyle.color(tintColor: sectionColor, appearance: appearance)
    }

}
