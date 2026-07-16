import Testing

@Suite
struct StickyHeaderBackdropMaskTests {
    @Test
    func rampsAcrossLowerPartOfBlurRegion() {
        let stops = StickyHeaderBackdropMask.gradientStops(totalHeight: 80, rampHeight: 48)

        #expect(stops.count == 3)
        #expect(stops[0].location == 0)
        #expect(stops[0].opacity == 0)
        #expect(stops[1].location == 0.6)
        #expect(stops[1].opacity == 1)
        #expect(stops[2].location == 1)
        #expect(stops[2].opacity == 1)
    }

    @Test
    func zeroRampKeepsBackdropFullyVisible() {
        let stops = StickyHeaderBackdropMask.gradientStops(totalHeight: 80, rampHeight: 0)

        #expect(stops.count == 2)
        #expect(stops[0].opacity == 1)
        #expect(stops[1].opacity == 1)
    }

    @Test
    func rampHeightIsClampedToAvailableHeight() {
        let stops = StickyHeaderBackdropMask.gradientStops(totalHeight: 8, rampHeight: 12)

        #expect(stops[1].location == 1)
    }

    @Test
    func stickyProjectContinuesThroughGapsUntilNextProjectCrossesTop() {
        let candidates = [
            StickyHeaderProjectCandidate(project: "First", rowMinY: 0),
            StickyHeaderProjectCandidate(project: "Second", rowMinY: 420),
        ]

        #expect(StickyHeaderProjectResolver.stickyProject(from: candidates, visibleTop: 390) == "First")
        #expect(StickyHeaderProjectResolver.stickyProject(from: candidates, visibleTop: 433) == "Second")
    }

    @Test
    func stickyProjectStaysHiddenAtTopUntilActivationOffsetIsPassed() {
        let candidates = [StickyHeaderProjectCandidate(project: "First", rowMinY: 0)]

        #expect(StickyHeaderProjectResolver.stickyProject(from: candidates, visibleTop: 0) == nil)
        #expect(StickyHeaderProjectResolver.stickyProject(from: candidates, visibleTop: 12) == nil)
        #expect(StickyHeaderProjectResolver.stickyProject(from: candidates, visibleTop: 13) == "First")
    }
}
