import Foundation

public struct ChatTranscriptRenderWindow: Equatable, Sendable {
    public let range: Range<Int>
    public let hasOlderMessages: Bool
    public let hasNewerMessages: Bool

    public init(messageCount: Int, pageSize: Int, endingAt requestedEnd: Int? = nil) {
        let count = max(0, messageCount)
        let size = max(1, pageSize)
        let end = min(max(0, requestedEnd ?? count), count)
        let start = max(0, end - size)

        range = start..<end
        hasOlderMessages = start > 0
        hasNewerMessages = end < count
    }

    public func previousPageEnd() -> Int? {
        hasOlderMessages ? range.lowerBound : nil
    }

    public func nextPageEnd(messageCount: Int, pageSize: Int) -> Int? {
        guard hasNewerMessages else { return nil }
        let nextEnd = min(max(0, messageCount), range.upperBound + max(1, pageSize))
        return nextEnd < messageCount ? nextEnd : nil
    }
}
