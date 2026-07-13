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
}
