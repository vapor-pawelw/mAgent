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
}
