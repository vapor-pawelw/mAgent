import Foundation

enum StickyHeaderBackdropMask {
    static let defaultRampHeight: CGFloat = 44

    static func gradientStops(totalHeight: CGFloat, rampHeight: CGFloat) -> [(location: CGFloat, opacity: CGFloat)] {
        guard totalHeight > 0 else {
            return [(0, 0), (1, 0)]
        }

        let clampedRampHeight = min(max(rampHeight, 0), totalHeight)
        guard clampedRampHeight > 0 else {
            return [(0, 1), (1, 1)]
        }

        return [
            (0, 0),
            (clampedRampHeight / totalHeight, 1),
            (1, 1),
        ]
    }
}

struct StickyHeaderProjectCandidate<Project> {
    let project: Project
    let rowMinY: CGFloat
}

enum StickyHeaderProjectResolver {
    static func stickyProject<Project>(
        from candidates: [StickyHeaderProjectCandidate<Project>],
        visibleTop: CGFloat,
        stickinessThreshold: CGFloat = 1
    ) -> Project? {
        candidates.last { candidate in
            candidate.rowMinY < visibleTop + stickinessThreshold
        }?.project
    }
}
