import Foundation

struct CodexCLIUpdateSummary: Equatable, Sendable {
    let installedVersion: String
    let availableVersion: String
    let isSkipped: Bool
}

enum CodexCLIUpdatePolicy {
    static func version(from output: String) -> String? {
        for line in output.split(whereSeparator: { $0.isNewline }) {
            let fields = line.split(whereSeparator: { $0.isWhitespace })
            guard let marker = fields.firstIndex(where: { $0 == "codex-cli" }),
                  fields.indices.contains(marker + 1) else { continue }
            if let version = normalizedVersion(String(fields[marker + 1])) {
                return version
            }
        }
        return nil
    }

    static func updateSummary(
        installedVersion: String,
        availableVersion: String,
        skippedVersion: String?
    ) -> CodexCLIUpdateSummary? {
        guard compare(availableVersion, installedVersion) == .orderedDescending else { return nil }
        return CodexCLIUpdateSummary(
            installedVersion: installedVersion,
            availableVersion: availableVersion,
            isSkipped: skippedVersion == availableVersion
        )
    }

    private static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsParts = numericComponents(lhs)
        let rhsParts = numericComponents(rhs)
        for index in 0..<max(lhsParts.count, rhsParts.count) {
            let left = index < lhsParts.count ? lhsParts[index] : 0
            let right = index < rhsParts.count ? rhsParts[index] : 0
            if left < right { return .orderedAscending }
            if left > right { return .orderedDescending }
        }
        return .orderedSame
    }

    private static func numericComponents(_ version: String) -> [Int] {
        normalizedVersion(version)?
            .split(separator: ".")
            .compactMap { Int($0) } ?? []
    }

    private static func normalizedVersion(_ version: String) -> String? {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrefix = trimmed.hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
        let stable = withoutPrefix.split(separator: "-", maxSplits: 1).first.map(String.init) ?? withoutPrefix
        guard !stable.isEmpty, stable.split(separator: ".").allSatisfy({ Int($0) != nil }) else { return nil }
        return stable
    }
}
