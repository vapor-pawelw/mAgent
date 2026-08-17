import Foundation
import MagentCore

struct CodexAppThreadProjectAssignment: Equatable {
    let threadID: String
    let projectPath: String
}

struct CodexAppProjectStateReconciliation {
    let state: [String: Any]
    let importedRepositoryPaths: [String]
    let didChange: Bool
}

struct CodexAppProjectStateFingerprint: Equatable {
    let fileSize: UInt64
    let modifiedAt: TimeInterval
}

enum CodexAppProjectStateReconciler {
    private static let savedRootsKey = "electron-saved-workspace-roots"
    private static let projectOrderKey = "project-order"
    private static let workspaceHintsKey = "thread-workspace-root-hints"
    private static let projectlessThreadIDsKey = "projectless-thread-ids"

    static func hasSupportedShape(_ state: [String: Any]) -> Bool {
        isStringArray(state[savedRootsKey])
            && isStringArray(state[projectOrderKey])
            && isStringDictionary(state[workspaceHintsKey])
            && isStringArray(state[projectlessThreadIDsKey])
    }

    static func reconcile(
        state originalState: [String: Any],
        magentProjectPaths: [String],
        assignments: [CodexAppThreadProjectAssignment]
    ) -> CodexAppProjectStateReconciliation {
        var state = originalState
        let normalizedMagentPaths = uniqueNormalizedPaths(magentProjectPaths)
        let magentPathSet = Set(normalizedMagentPaths)

        let existingRoots = stringArray(state[savedRootsKey])
        let normalizedExistingRoots = uniqueNormalizedPaths(existingRoots)
        let importedRepositoryPaths = normalizedExistingRoots.filter { !magentPathSet.contains($0) }

        let mergedRoots = appendMissingNormalized(normalizedMagentPaths, to: existingRoots)
        if mergedRoots != existingRoots {
            state[savedRootsKey] = mergedRoots
        }

        let existingOrder = stringArray(state[projectOrderKey])
        let mergedOrder = appendMissingNormalized(
            mergedRoots.compactMap(normalizedPath),
            to: existingOrder
        )
        if mergedOrder != existingOrder {
            state[projectOrderKey] = mergedOrder
        }

        var workspaceHints = stringDictionary(state[workspaceHintsKey])
        for assignment in assignments {
            let threadID = assignment.threadID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !threadID.isEmpty,
                  let projectPath = normalizedPath(assignment.projectPath) else { continue }
            workspaceHints[threadID] = projectPath
        }
        if workspaceHints != stringDictionary(originalState[workspaceHintsKey]) {
            state[workspaceHintsKey] = workspaceHints
        }

        let assignedThreadIDs = Set(assignments.map { assignment in
            assignment.threadID.trimmingCharacters(in: .whitespacesAndNewlines)
        })
        let existingProjectlessIDs = stringArray(state[projectlessThreadIDsKey])
        let filteredProjectlessIDs = existingProjectlessIDs.filter { !assignedThreadIDs.contains($0) }
        if filteredProjectlessIDs != existingProjectlessIDs {
            state[projectlessThreadIDsKey] = filteredProjectlessIDs
        }

        return CodexAppProjectStateReconciliation(
            state: state,
            importedRepositoryPaths: importedRepositoryPaths,
            didChange: !NSDictionary(dictionary: state).isEqual(to: originalState)
        )
    }

    private static func stringArray(_ value: Any?) -> [String] {
        value as? [String] ?? []
    }

    private static func isStringArray(_ value: Any?) -> Bool {
        value == nil || value is [String]
    }

    private static func stringDictionary(_ value: Any?) -> [String: String] {
        value as? [String: String] ?? [:]
    }

    private static func isStringDictionary(_ value: Any?) -> Bool {
        value == nil || value is [String: String]
    }

    private static func normalizedPath(_ path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: trimmed).standardizedFileURL.path
    }

    private static func uniqueNormalizedPaths(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.compactMap { path in
            guard let normalized = normalizedPath(path), seen.insert(normalized).inserted else { return nil }
            return normalized
        }
    }

    private static func appendMissingNormalized(_ paths: [String], to existing: [String]) -> [String] {
        var result = existing
        var seen = Set(existing.compactMap(normalizedPath))
        for path in paths where seen.insert(path).inserted {
            result.append(path)
        }
        return result
    }
}

final class CodexAppProjectSyncService {
    static let shared = CodexAppProjectSyncService()

    private let stateFileURL: URL

    init(stateFileURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/.codex-global-state.json")) {
        self.stateFileURL = stateFileURL
    }

    func stateFingerprint() -> CodexAppProjectStateFingerprint? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: stateFileURL.path),
              let fileSize = (attributes[.size] as? NSNumber)?.uint64Value,
              let modifiedAt = attributes[.modificationDate] as? Date else { return nil }
        return CodexAppProjectStateFingerprint(
            fileSize: fileSize,
            modifiedAt: modifiedAt.timeIntervalSince1970
        )
    }

    func synchronize(
        projects: [Project],
        assignments: [CodexAppThreadProjectAssignment]
    ) throws -> [String] {
        try synchronize(projects: projects, assignments: assignments, retriesRemaining: 3)
    }

    private func synchronize(
        projects: [Project],
        assignments: [CodexAppThreadProjectAssignment],
        retriesRemaining: Int
    ) throws -> [String] {
        guard FileManager.default.fileExists(atPath: stateFileURL.path) else { return [] }

        let originalData = try Data(contentsOf: stateFileURL)
        guard let originalState = try JSONSerialization.jsonObject(with: originalData) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        guard CodexAppProjectStateReconciler.hasSupportedShape(originalState) else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }

        let reconciliation = CodexAppProjectStateReconciler.reconcile(
            state: originalState,
            magentProjectPaths: projects.map(\.repoPath),
            assignments: assignments
        )
        guard reconciliation.didChange else { return reconciliation.importedRepositoryPaths }

        let currentData = try Data(contentsOf: stateFileURL)
        guard currentData == originalData else {
            guard retriesRemaining > 0 else { throw CocoaError(.fileWriteFileExists) }
            return try synchronize(
                projects: projects,
                assignments: assignments,
                retriesRemaining: retriesRemaining - 1
            )
        }

        let updatedData = try JSONSerialization.data(
            withJSONObject: reconciliation.state,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        let originalAttributes = try? FileManager.default.attributesOfItem(atPath: stateFileURL.path)
        try updatedData.write(to: stateFileURL, options: .atomic)
        if let permissions = originalAttributes?[.posixPermissions] {
            try? FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: stateFileURL.path)
        }
        return reconciliation.importedRepositoryPaths
    }
}
