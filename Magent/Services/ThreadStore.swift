import Foundation
import MagentCore

/// Centralized storage for the active thread collection and selection state.
/// Extracted from ThreadManager to provide a focused, testable container
/// for thread data that multiple services can share.
final class ThreadStore {

    var threads: [MagentThread] = []
    var activeThreadId: UUID?
    var pendingThreadIds: Set<UUID> = []
    /// When true, the next `didCreateThread` delegate call will skip sidebar auto-selection.
    /// Set by the IPC handler when `--select` is not passed; consumed and reset by the delegate.
    var skipNextAutoSelect: Bool = false

    // MARK: - Query Helpers

    func thread(byId id: UUID) -> MagentThread? {
        threads.first { $0.id == id }
    }

    func threadIndex(byId id: UUID) -> Int? {
        threads.firstIndex { $0.id == id }
    }

    func activeThread() -> MagentThread? {
        guard let id = activeThreadId else { return nil }
        return thread(byId: id)
    }

    func threads(forProject projectId: UUID) -> [MagentThread] {
        threads.filter { $0.projectId == projectId && !$0.isArchived }
    }

    func thread(owningSession sessionName: String) -> MagentThread? {
        threads.first { !$0.isArchived && $0.tmuxSessionNames.contains(sessionName) }
    }

    func threadIndex(owningSession sessionName: String) -> Int? {
        threads.firstIndex { !$0.isArchived && $0.tmuxSessionNames.contains(sessionName) }
    }

    // MARK: - Mutation Helpers

    @discardableResult
    func update(at index: Int, _ mutate: (inout MagentThread) -> Void) -> Bool {
        guard threads.indices.contains(index) else { return false }
        mutate(&threads[index])
        return true
    }

    @discardableResult
    func update(id: UUID, _ mutate: (inout MagentThread) -> Void) -> Bool {
        guard let index = threadIndex(byId: id) else { return false }
        mutate(&threads[index])
        return true
    }
}
