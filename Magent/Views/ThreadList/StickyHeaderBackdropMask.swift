import Foundation

enum StickyHeaderBackdropMask {
    static let blurLayerAlphas: [CGFloat] = [0.42, 0.34, 0.28]
    static let defaultRampHeight: CGFloat = 44

    static func gradientStops(totalHeight: CGFloat, rampHeight: CGFloat, layerIndex: Int, layerCount: Int = blurLayerAlphas.count) -> [(location: CGFloat, opacity: CGFloat)] {
        guard totalHeight > 0 else {
            return [(0, 0), (1, 0)]
        }

        let clampedRampHeight = min(max(rampHeight, 0), totalHeight)
        guard clampedRampHeight > 0 else {
            return [(0, 1), (1, 1)]
        }

        let clampedLayerIndex = min(max(layerIndex, 0), max(layerCount - 1, 0))
        let layerProgress = CGFloat(clampedLayerIndex + 1) / CGFloat(max(layerCount, 1))
        let layerRampHeight = clampedRampHeight * (0.5 + layerProgress * 0.5)

        return [
            (0, 0),
            (layerRampHeight / totalHeight, 1),
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
