import Foundation

enum StickyHeaderBackdropMask {
    static func gradientStops(totalHeight: CGFloat, fadeHeight: CGFloat) -> [(location: CGFloat, opacity: CGFloat)] {
        guard totalHeight > 0 else {
            return [(0, 0), (1, 0)]
        }

        let clampedFadeHeight = min(max(fadeHeight, 0), totalHeight)
        guard clampedFadeHeight > 0 else {
            return [(0, 1), (1, 1)]
        }

        return [
            (0, 0),
            (clampedFadeHeight / totalHeight, 1),
            (1, 1),
        ]
    }
}
