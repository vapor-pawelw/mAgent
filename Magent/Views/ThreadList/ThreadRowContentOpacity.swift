import CoreGraphics

enum ThreadRowContentOpacity {
    static let dimmedContent: CGFloat = 0.5
    static let secondaryLine: CGFloat = 0.8
    static let inactiveContent: CGFloat = 0.8

    static func contentOpacity(isDimmed: Bool) -> CGFloat {
        isDimmed ? dimmedContent : 1
    }

    static func secondaryLineOpacity(isInactive: Bool) -> CGFloat {
        secondaryLine * (isInactive ? inactiveContent : 1)
    }

    static func effectiveSecondaryLineOpacity(isDimmed: Bool, isInactive: Bool = false) -> CGFloat {
        secondaryLineOpacity(isInactive: isInactive) * contentOpacity(isDimmed: isDimmed)
    }
}
