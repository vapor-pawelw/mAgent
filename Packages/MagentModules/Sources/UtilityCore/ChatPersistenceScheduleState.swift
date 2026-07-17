import Foundation

public nonisolated struct ChatPersistenceScheduleState: Sendable {
    public enum DraftAction: Equatable, Sendable {
        case wait(until: Date)
        case persist
    }

    public let draftDebounceInterval: TimeInterval
    public let streamCheckpointInterval: TimeInterval
    private var draftDeadlines: [String: Date] = [:]

    public init(draftDebounceInterval: TimeInterval = 0.5, streamCheckpointInterval: TimeInterval = 5) {
        self.draftDebounceInterval = draftDebounceInterval
        self.streamCheckpointInterval = streamCheckpointInterval
    }

    public mutating func recordDraftChange(identifier: String, now: Date) -> Bool {
        let shouldStartWorker = draftDeadlines[identifier] == nil
        draftDeadlines[identifier] = now.addingTimeInterval(draftDebounceInterval)
        return shouldStartWorker
    }

    public mutating func draftAction(identifier: String, now: Date) -> DraftAction? {
        guard let deadline = draftDeadlines[identifier] else { return nil }
        guard now >= deadline else { return .wait(until: deadline) }
        draftDeadlines.removeValue(forKey: identifier)
        return .persist
    }

    public mutating func cancelDraft(identifier: String) {
        draftDeadlines.removeValue(forKey: identifier)
    }
}
