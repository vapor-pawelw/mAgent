import Foundation

final class RenameOperationLifecycle {
    private let isThreadActive: (UUID) -> Bool
    private let present: (String) -> Void
    private var generationByThreadId: [UUID: UUID] = [:]
    private var presentedGenerations: Set<UUID> = []

    init(
        isThreadActive: @escaping (UUID) -> Bool,
        present: @escaping (String) -> Void
    ) {
        self.isThreadActive = isThreadActive
        self.present = present
    }

    func begin(threadId: UUID) -> UUID {
        if let generation = generationByThreadId[threadId] {
            return generation
        }
        let generation = UUID()
        generationByThreadId[threadId] = generation
        return generation
    }

    func isCurrent(generation: UUID, threadId: UUID) -> Bool {
        generationByThreadId[threadId] == generation
    }

    func isCurrentAndActive(generation: UUID, threadId: UUID) -> Bool {
        isCurrent(generation: generation, threadId: threadId) && isThreadActive(threadId)
    }

    func presentIfNeeded(message: String, threadId: UUID, generation: UUID) {
        guard isCurrentAndActive(generation: generation, threadId: threadId) else { return }
        guard presentedGenerations.insert(generation).inserted else { return }
        present(message)
    }

    func cancel(threadId: UUID) {
        if let generation = generationByThreadId.removeValue(forKey: threadId) {
            presentedGenerations.remove(generation)
        }
    }
}
