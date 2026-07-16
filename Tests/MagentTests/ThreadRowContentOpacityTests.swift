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
        #expect(abs(ThreadRowContentOpacity.effectiveSecondaryLineOpacity(isDimmed: false, isInactive: true) - 0.56) < 0.0001)
        #expect(abs(ThreadRowContentOpacity.effectiveSecondaryLineOpacity(isDimmed: true, isInactive: true) - 0.28) < 0.0001)
    }

    @Test("Inactive primary text dims emoji and text less than hidden rows")
    func inactivePrimaryLineUsesDistinctOpacity() {
        #expect(ThreadRowContentOpacity.effectivePrimaryLineOpacity(isDimmed: false, isInactive: true) == 0.7)
        #expect(ThreadRowContentOpacity.effectivePrimaryLineOpacity(isDimmed: true, isInactive: false) == 0.5)
        #expect(ThreadRowContentOpacity.effectivePrimaryLineOpacity(isDimmed: true, isInactive: true) == 0.35)
    }

    @Test("Status badges follow hidden and inactive content opacity")
    func statusRowCompoundsOpacity() {
        #expect(ThreadRowContentOpacity.effectiveStatusRowOpacity(isDimmed: false) == 1)
        #expect(ThreadRowContentOpacity.effectiveStatusRowOpacity(isDimmed: true) == 0.5)
        #expect(ThreadRowContentOpacity.effectiveStatusRowOpacity(isDimmed: false, isInactive: true) == 0.7)
        #expect(ThreadRowContentOpacity.effectiveStatusRowOpacity(isDimmed: true, isInactive: true) == 0.35)
    }

    @Test("Pinned favorite and hidden symbols keep the description opacity")
    func leadingStatusSymbolsMatchDescriptionOpacity() {
        #expect(ThreadRowContentOpacity.effectiveStatusRowOpacity(isDimmed: false, isInactive: true)
            == ThreadRowContentOpacity.effectivePrimaryLineOpacity(isDimmed: false, isInactive: true))
    }
}
