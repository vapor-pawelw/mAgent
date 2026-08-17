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

struct MagentProjectRepositoryResolution: Equatable {
    let projectID: UUID
    let repositoryIdentity: String
    let canonicalProjectPath: String
}

struct MagentProjectDeduplicationPlan {
    let projects: [Project]
    let projectIDReplacements: [UUID: UUID]
    let canonicalProjectPathsByProjectID: [UUID: String]
}

enum MagentProjectDeduplicator {
    static func plan(
        projects: [Project],
        resolutions: [MagentProjectRepositoryResolution]
    ) -> MagentProjectDeduplicationPlan {
        let resolutionByProjectID = Dictionary(
            resolutions.map { ($0.projectID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let projectCountByIdentity = Dictionary(grouping: resolutions, by: \.repositoryIdentity)
            .mapValues(\.count)
        var canonicalProjectIDByIdentity: [String: UUID] = [:]
        var replacements: [UUID: UUID] = [:]
        var canonicalPaths: [UUID: String] = [:]
        var deduplicatedProjects: [Project] = []

        for project in projects {
            guard let resolution = resolutionByProjectID[project.id] else {
                deduplicatedProjects.append(project)
                continue
            }

            if let canonicalProjectID = canonicalProjectIDByIdentity[resolution.repositoryIdentity] {
                replacements[project.id] = canonicalProjectID
                if let canonicalProject = deduplicatedProjects.first(where: { $0.id == canonicalProjectID }) {
                    canonicalPaths[project.id] = canonicalProject.repoPath
                }
                if let canonicalIndex = deduplicatedProjects.firstIndex(where: { $0.id == canonicalProjectID }) {
                    deduplicatedProjects[canonicalIndex] = merge(
                        duplicate: project,
                        into: deduplicatedProjects[canonicalIndex]
                    )
                }
                continue
            }

            canonicalProjectIDByIdentity[resolution.repositoryIdentity] = project.id
            let shouldCanonicalizePath = (projectCountByIdentity[resolution.repositoryIdentity] ?? 0) > 1
                || normalizedPath(project.repoPath) == normalizedPath(resolution.canonicalProjectPath)
            let selectedProjectPath = shouldCanonicalizePath
                ? resolution.canonicalProjectPath
                : project.repoPath
            canonicalPaths[project.id] = selectedProjectPath
            var canonicalProject = project
            canonicalProject.repoPath = selectedProjectPath
            deduplicatedProjects.append(canonicalProject)
        }

        return MagentProjectDeduplicationPlan(
            projects: deduplicatedProjects,
            projectIDReplacements: replacements,
            canonicalProjectPathsByProjectID: canonicalPaths
        )
    }

    private static func merge(duplicate: Project, into canonical: Project) -> Project {
        var merged = canonical
        merged.defaultBranch = merged.defaultBranch ?? duplicate.defaultBranch
        merged.agentType = merged.agentType ?? duplicate.agentType
        merged.terminalInjectionCommand = preferred(merged.terminalInjectionCommand, duplicate.terminalInjectionCommand)
        merged.preAgentInjectionCommand = preferred(merged.preAgentInjectionCommand, duplicate.preAgentInjectionCommand)
        merged.agentContextInjection = preferred(merged.agentContextInjection, duplicate.agentContextInjection)
        merged.autoRenameSlugPrompt = preferred(merged.autoRenameSlugPrompt, duplicate.autoRenameSlugPrompt)
        merged.isPinned = merged.isPinned || duplicate.isPinned
        merged.isHidden = merged.isHidden && duplicate.isHidden
        merged.useThreadSectionsOverride = merged.useThreadSectionsOverride ?? duplicate.useThreadSectionsOverride
        merged.defaultSectionId = merged.defaultSectionId ?? duplicate.defaultSectionId
        merged.threadSections = mergedSections(merged.threadSections, duplicate.threadSections)
        merged.jiraProjectKey = preferred(merged.jiraProjectKey, duplicate.jiraProjectKey)
        merged.jiraBoardId = merged.jiraBoardId ?? duplicate.jiraBoardId
        merged.jiraBoardName = preferred(merged.jiraBoardName, duplicate.jiraBoardName)
        merged.jiraSyncEnabled = merged.jiraSyncEnabled || duplicate.jiraSyncEnabled
        merged.jiraSiteURL = preferred(merged.jiraSiteURL, duplicate.jiraSiteURL)
        merged.jiraExcludedTicketKeys.formUnion(duplicate.jiraExcludedTicketKeys)
        merged.jiraAssigneeAccountId = preferred(merged.jiraAssigneeAccountId, duplicate.jiraAssigneeAccountId)
        merged.jiraAcknowledgedStatuses = merged.jiraAcknowledgedStatuses ?? duplicate.jiraAcknowledgedStatuses

        var knownEntries = Set(merged.localFileSyncEntries)
        for entry in duplicate.localFileSyncEntries where knownEntries.insert(entry).inserted {
            merged.localFileSyncEntries.append(entry)
        }
        return merged
    }

    private static func preferred(_ primary: String?, _ secondary: String?) -> String? {
        guard let primary, !primary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return secondary
        }
        return primary
    }

    private static func mergedSections(
        _ primary: [ThreadSection]?,
        _ secondary: [ThreadSection]?
    ) -> [ThreadSection]? {
        guard primary != nil || secondary != nil else { return nil }
        var result = primary ?? []
        var knownIDs = Set(result.map(\.id))
        for section in secondary ?? [] where knownIDs.insert(section.id).inserted {
            result.append(section)
        }
        return result
    }

    private static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }
}

enum MagentProjectThreadMigrator {
    static func migrate(
        _ thread: MagentThread,
        projectsByID: [UUID: Project],
        plan: MagentProjectDeduplicationPlan
    ) -> MagentThread {
        let originalProjectID = thread.projectId
        var migrated = plan.projectIDReplacements[originalProjectID]
            .map { thread.withProjectId($0) } ?? thread
        if let oldProjectPath = projectsByID[originalProjectID]?.repoPath,
           let canonicalProjectPath = plan.canonicalProjectPathsByProjectID[originalProjectID],
           normalizedPath(thread.worktreePath) == normalizedPath(oldProjectPath) {
            if normalizedPath(oldProjectPath) != normalizedPath(canonicalProjectPath) {
                migrated.isMain = false
            } else {
                migrated.worktreePath = canonicalProjectPath
            }
        }
        return migrated
    }

    private static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }
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
