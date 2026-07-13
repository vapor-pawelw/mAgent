import Testing

@Suite
struct ThreadRowContentOpacityTests {

    @Test("Secondary metadata remains 20% dimmer than the primary line")
    func secondaryLineUsesReducedOpacity() {
        #expect(ThreadRowContentOpacity.effectiveSecondaryLineOpacity(isDimmed: false) == 0.8)
    }

    @Test("Hidden rows compound their row dimming with the secondary-line dimming")
    func hiddenSecondaryLineCompoundsOpacity() {
        #expect(ThreadRowContentOpacity.effectiveSecondaryLineOpacity(isDimmed: true) == 0.4)
    }

    @Test("Inactive metadata compounds its secondary and inactive dimming")
    func inactiveSecondaryLineCompoundsOpacity() {
        #expect(abs(ThreadRowContentOpacity.effectiveSecondaryLineOpacity(isDimmed: false, isInactive: true) - 0.64) < 0.0001)
        #expect(abs(ThreadRowContentOpacity.effectiveSecondaryLineOpacity(isDimmed: true, isInactive: true) - 0.32) < 0.0001)
    }
}
