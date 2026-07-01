import Testing

@Suite
struct StickyHeaderBackdropMaskTests {
    @Test
    func fadesOnlyAcrossBottomFadeRegion() {
        let stops = StickyHeaderBackdropMask.gradientStops(totalHeight: 80, fadeHeight: 12)

        #expect(stops.count == 3)
        #expect(stops[0].location == 0)
        #expect(stops[0].opacity == 0)
        #expect(stops[1].location == 0.15)
        #expect(stops[1].opacity == 1)
        #expect(stops[2].location == 1)
        #expect(stops[2].opacity == 1)
    }

    @Test
    func zeroFadeKeepsBackdropFullyVisible() {
        let stops = StickyHeaderBackdropMask.gradientStops(totalHeight: 80, fadeHeight: 0)

        #expect(stops.count == 2)
        #expect(stops[0].opacity == 1)
        #expect(stops[1].opacity == 1)
    }

    @Test
    func fadeHeightIsClampedToAvailableHeight() {
        let stops = StickyHeaderBackdropMask.gradientStops(totalHeight: 8, fadeHeight: 12)

        #expect(stops[1].location == 1)
    }
}
