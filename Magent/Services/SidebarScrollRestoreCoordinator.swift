import Foundation

struct SidebarScrollRestoreCoordinator {
    private var generation = 0

    mutating func beginReload() -> Int {
        generation &+= 1
        return generation
    }

    mutating func cancelPendingRestore() {
        generation &+= 1
    }

    func canApplyRestore(for token: Int) -> Bool {
        token == generation
    }
}
