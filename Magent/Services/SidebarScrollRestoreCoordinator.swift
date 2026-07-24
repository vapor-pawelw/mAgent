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

struct SidebarInitialCenteringCoordinator {
    private(set) var shouldAttempt = true

    mutating func cancelForUserInteraction() {
        shouldAttempt = false
    }

    mutating func markCompleted() {
        shouldAttempt = false
    }
}

struct SidebarCenteringGeometry {
    static func targetOriginY(
        rowMinY: CGFloat,
        rowHeight: CGFloat,
        viewportHeight: CGFloat,
        documentHeight: CGFloat,
        topInset: CGFloat = 0,
        bottomInset: CGFloat = 0
    ) -> CGFloat? {
        guard rowMinY.isFinite,
              rowHeight.isFinite,
              viewportHeight.isFinite,
              documentHeight.isFinite,
              topInset.isFinite,
              bottomInset.isFinite,
              rowMinY >= 0,
              rowHeight > 0,
              viewportHeight > 0,
              documentHeight > 0,
              topInset >= 0,
              bottomInset >= 0,
              rowMinY + rowHeight <= documentHeight + 1 else {
            return nil
        }

        let unobscuredHeight = viewportHeight - topInset - bottomInset
        guard unobscuredHeight > 0 else { return nil }

        let targetY = rowMinY + (rowHeight / 2) - (unobscuredHeight / 2) - topInset
        let minimumY = -topInset
        let maximumY = max(
            minimumY,
            documentHeight - unobscuredHeight - topInset
        )
        return min(max(targetY, minimumY), maximumY)
    }

    static func isAtTarget(
        currentOriginY: CGFloat,
        targetOriginY: CGFloat,
        tolerance: CGFloat = 1
    ) -> Bool {
        abs(currentOriginY - targetOriginY) <= tolerance
    }
}
