import Foundation
import os

public struct InitialThreadDescription: Equatable, Sendable {
    public static let promptPreviewMaximumLength = 160

    public let text: String
    public let isProvisional: Bool

    public init(text: String, isProvisional: Bool) {
        self.text = text
        self.isProvisional = isProvisional
    }

    public static func resolve(
        explicitDescription: String?,
        prompt: String?,
        fallback: String
    ) -> InitialThreadDescription {
        if let explicit = trimmedNonEmpty(explicitDescription) {
            return InitialThreadDescription(text: explicit, isProvisional: false)
        }

        if let prompt = trimmedNonEmpty(prompt) {
            return InitialThreadDescription(
                text: promptPreview(prompt),
                isProvisional: true
            )
        }

        return InitialThreadDescription(text: fallback, isProvisional: true)
    }

    public static func promptPreview(_ prompt: String) -> String {
        let singleLine = prompt
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard singleLine.count > promptPreviewMaximumLength else { return singleLine }

        let contentLimit = promptPreviewMaximumLength - 1
        let hardEnd = singleLine.index(singleLine.startIndex, offsetBy: contentLimit)
        let prefix = singleLine[..<hardEnd]
        let preferredEnd = prefix.lastIndex(of: " ").map { prefix.index(before: $0) }
        let end = preferredEnd ?? prefix.index(before: prefix.endIndex)
        return String(prefix[...end]).trimmingCharacters(in: .whitespaces) + "…"
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

public final class ThreadDisplayNumberAllocator: Sendable {
    private let highWaterMarks = OSAllocatedUnfairLock(initialState: [UUID: Int]())

    public init() {}

    public func allocate(projectId: UUID, existingNumbers: [Int]) -> Int {
        highWaterMarks.withLock { highWaterMarks in
            let highestExisting = existingNumbers.max() ?? 0
            let nextNumber = max(highestExisting, highWaterMarks[projectId] ?? 0) + 1
            highWaterMarks[projectId] = nextNumber
            return nextNumber
        }
    }
}
