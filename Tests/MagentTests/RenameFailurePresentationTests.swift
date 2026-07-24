import Foundation
import Testing

@Suite
struct RenameFailurePresentationTests {

    @Test
    func failureIsNotPresentedAfterThreadRemoval() {
        let threadId = UUID()
        var activeThreadIds: Set<UUID> = [threadId]
        var presentedMessages: [String] = []
        let lifecycle = RenameOperationLifecycle(
            isThreadActive: { activeThreadIds.contains($0) },
            present: { presentedMessages.append($0) }
        )
        let generation = lifecycle.begin(threadId: threadId)

        activeThreadIds.remove(threadId)
        lifecycle.presentIfNeeded(
            message: "Thread not found",
            threadId: threadId,
            generation: generation
        )

        #expect(presentedMessages.isEmpty)
    }

    @Test
    func activeThreadFailureIsPresentedOnlyOnce() {
        let threadId = UUID()
        var presentedMessages: [String] = []
        let lifecycle = RenameOperationLifecycle(
            isThreadActive: { $0 == threadId },
            present: { presentedMessages.append($0) }
        )
        let generation = lifecycle.begin(threadId: threadId)

        lifecycle.presentIfNeeded(
            message: "First failure",
            threadId: threadId,
            generation: generation
        )
        lifecycle.presentIfNeeded(
            message: "Repeated failure",
            threadId: threadId,
            generation: generation
        )

        #expect(presentedMessages == ["First failure"])
    }

    @Test
    func cancelledGenerationStaysInactiveAfterThreadReturns() {
        let threadId = UUID()
        var isActive = true
        var presentedMessages: [String] = []
        let lifecycle = RenameOperationLifecycle(
            isThreadActive: { _ in isActive },
            present: { presentedMessages.append($0) }
        )
        let archivedGeneration = lifecycle.begin(threadId: threadId)

        isActive = false
        lifecycle.cancel(threadId: threadId)
        isActive = true
        let restoredGeneration = lifecycle.begin(threadId: threadId)
        lifecycle.presentIfNeeded(
            message: "Stale archive failure",
            threadId: threadId,
            generation: archivedGeneration
        )
        lifecycle.presentIfNeeded(
            message: "Current failure",
            threadId: threadId,
            generation: restoredGeneration
        )

        #expect(presentedMessages == ["Current failure"])
    }
}
