import Testing

@Suite
struct DiscreteScrollSmoothingTests {
    @Test
    func wheelNotchesAccumulateFromThePendingDestination() {
        let firstDestination = DiscreteScrollSmoothing.destination(
            currentDestination: nil,
            currentOrigin: 100,
            scrollingDeltaY: -1,
            allowedRange: 0...500
        )
        let secondDestination = DiscreteScrollSmoothing.destination(
            currentDestination: firstDestination,
            currentOrigin: 105,
            scrollingDeltaY: -1,
            allowedRange: 0...500
        )

        #expect(firstDestination == 144)
        #expect(secondDestination == 188)
    }

    @Test
    func coarseMousePacketsStillRepresentOneWheelNotch() {
        let regularPacket = DiscreteScrollSmoothing.destination(
            currentDestination: nil,
            currentOrigin: 100,
            scrollingDeltaY: -1,
            allowedRange: 0...500
        )
        let coarsePacket = DiscreteScrollSmoothing.destination(
            currentDestination: nil,
            currentOrigin: 100,
            scrollingDeltaY: -15,
            allowedRange: 0...500
        )

        #expect(coarsePacket == regularPacket)
    }

    @Test
    func destinationDoesNotMovePastEitherScrollBoundary() {
        #expect(DiscreteScrollSmoothing.destination(
            currentDestination: nil,
            currentOrigin: 10,
            scrollingDeltaY: 1,
            allowedRange: 0...500
        ) == 0)
        #expect(DiscreteScrollSmoothing.destination(
            currentDestination: nil,
            currentOrigin: 490,
            scrollingDeltaY: -1,
            allowedRange: 0...500
        ) == 500)
    }

    @Test
    func pendingDestinationIsReclampedWhenScrollableContentShrinks() {
        #expect(DiscreteScrollSmoothing.clampedDestination(
            544,
            allowedRange: 0...520
        ) == 520)
    }

    @Test
    func animationApproachesDestinationWithoutJumpingOrOvershooting() {
        let nextOrigin = DiscreteScrollSmoothing.nextOrigin(
            currentOrigin: 100,
            destination: 144,
            elapsed: 1.0 / 60.0
        )

        #expect(nextOrigin > 100)
        #expect(nextOrigin < 144)
    }

    @Test
    func animationStopsWhenPixelSnappingPreventsFurtherProgress() {
        #expect(!DiscreteScrollSmoothing.shouldStop(
            appliedOrigin: 519.7,
            destination: 520,
            consecutiveStalledTicks: 2,
            elapsedSinceStart: 0.2
        ))
        #expect(DiscreteScrollSmoothing.shouldStop(
            appliedOrigin: 519.7,
            destination: 520,
            consecutiveStalledTicks: 3,
            elapsedSinceStart: 0.2
        ))
    }

    @Test
    func animationHasAHardDeadline() {
        #expect(DiscreteScrollSmoothing.shouldStop(
            appliedOrigin: 100,
            destination: 144,
            consecutiveStalledTicks: 0,
            elapsedSinceStart: 1
        ))
    }
}
