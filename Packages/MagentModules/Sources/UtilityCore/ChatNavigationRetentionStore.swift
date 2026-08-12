import Foundation

public struct ChatNavigationRetentionStore<Value: AnyObject> {
    private var valuesByThreadID: [UUID: Value] = [:]

    public init() {}

    public mutating func update(_ value: Value, for threadID: UUID, hasActiveWork: Bool) {
        if hasActiveWork {
            valuesByThreadID[threadID] = value
        } else {
            valuesByThreadID.removeValue(forKey: threadID)
        }
    }

    public mutating func take(for threadID: UUID) -> Value? {
        valuesByThreadID.removeValue(forKey: threadID)
    }

}
