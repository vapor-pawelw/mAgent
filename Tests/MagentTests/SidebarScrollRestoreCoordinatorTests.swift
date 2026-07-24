import Testing

@Suite
struct SidebarScrollRestoreCoordinatorTests {
    @Test
    func latestReloadRestoreCanApplyUntilInvalidated() {
        var coordinator = SidebarScrollRestoreCoordinator()

        let token = coordinator.beginReload()

        #expect(coordinator.canApplyRestore(for: token))
    }

    @Test
    func newerReloadInvalidatesOlderDeferredRestore() {
        var coordinator = SidebarScrollRestoreCoordinator()

        let olderToken = coordinator.beginReload()
        let newerToken = coordinator.beginReload()

        #expect(!coordinator.canApplyRestore(for: olderToken))
        #expect(coordinator.canApplyRestore(for: newerToken))
    }

    @Test
    func explicitNavigationInvalidatesDeferredRestoreFromReload() {
        var coordinator = SidebarScrollRestoreCoordinator()

        let token = coordinator.beginReload()
        coordinator.cancelPendingRestore()

        #expect(!coordinator.canApplyRestore(for: token))
    }

    @Test
    func initialCenteringStopsAfterExplicitSidebarInteraction() {
        var coordinator = SidebarInitialCenteringCoordinator()

        #expect(coordinator.shouldAttempt)
        coordinator.cancelForUserInteraction()

        #expect(!coordinator.shouldAttempt)
    }

    @Test
    func completedInitialCenteringDoesNotRunAgain() {
        var coordinator = SidebarInitialCenteringCoordinator()

        coordinator.markCompleted()

        #expect(!coordinator.shouldAttempt)
    }

    @Test
    func centeringWaitsForValidRowAndViewportGeometry() {
        #expect(SidebarCenteringGeometry.targetOriginY(
            rowMinY: 300,
            rowHeight: 0,
            viewportHeight: 400,
            documentHeight: 1_000
        ) == nil)
        #expect(SidebarCenteringGeometry.targetOriginY(
            rowMinY: 300,
            rowHeight: 40,
            viewportHeight: 0,
            documentHeight: 1_000
        ) == nil)
        #expect(SidebarCenteringGeometry.targetOriginY(
            rowMinY: 900,
            rowHeight: 40,
            viewportHeight: 400,
            documentHeight: 600
        ) == nil)
        #expect(SidebarCenteringGeometry.targetOriginY(
            rowMinY: .nan,
            rowHeight: 40,
            viewportHeight: 400,
            documentHeight: 1_000
        ) == nil)
        #expect(SidebarCenteringGeometry.targetOriginY(
            rowMinY: 300,
            rowHeight: 40,
            viewportHeight: 400,
            documentHeight: .infinity
        ) == nil)
    }

    @Test
    func centeringClampsRowsNearDocumentEdges() {
        #expect(SidebarCenteringGeometry.targetOriginY(
            rowMinY: 20,
            rowHeight: 40,
            viewportHeight: 400,
            documentHeight: 1_000
        ) == 0)
        #expect(SidebarCenteringGeometry.targetOriginY(
            rowMinY: 940,
            rowHeight: 40,
            viewportHeight: 400,
            documentHeight: 1_000
        ) == 600)
    }

    @Test
    func initialCenteringOnlyCompletesAtTheRequestedScrollTarget() {
        #expect(SidebarCenteringGeometry.isAtTarget(
            currentOriginY: 299.5,
            targetOriginY: 300
        ))
        #expect(!SidebarCenteringGeometry.isAtTarget(
            currentOriginY: 250,
            targetOriginY: 300
        ))
    }
}
