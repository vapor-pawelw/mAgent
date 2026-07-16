import CoreGraphics

enum ThreadRowContentOpacity {
    static let dimmedContent: CGFloat = 0.5
    static let secondaryLine: CGFloat = 0.8
    static let inactiveContent: CGFloat = 0.7

    static func contentOpacity(isDimmed: Bool) -> CGFloat {
        isDimmed ? dimmedContent : 1
    }

    static func contentGroupOpacity(isInactive: Bool) -> CGFloat {
        isInactive ? inactiveContent : 1
    }

    static func statusRowOpacity(isInactive: Bool) -> CGFloat {
        contentGroupOpacity(isInactive: isInactive)
    }

    static func effectivePrimaryLineOpacity(isDimmed: Bool, isInactive: Bool = false) -> CGFloat {
        contentGroupOpacity(isInactive: isInactive) * contentOpacity(isDimmed: isDimmed)
    }

    static func effectiveSecondaryLineOpacity(isDimmed: Bool, isInactive: Bool = false) -> CGFloat {
        secondaryLine * contentGroupOpacity(isInactive: isInactive) * contentOpacity(isDimmed: isDimmed)
    }

    static func effectiveStatusRowOpacity(isDimmed: Bool, isInactive: Bool = false) -> CGFloat {
        statusRowOpacity(isInactive: isInactive) * contentOpacity(isDimmed: isDimmed)
    }
}
