import AppKit
import CryptoKit
import Foundation
import MagentCore

// MARK: - BackgroundLocalSyncWorker (archive-time copy helper)

nonisolated enum BackgroundLocalSyncWorker {
    private enum ItemKind {
        case file
        case directory
    }

    private struct BaselineManifest: Codable {
        let fileHashes: [String: String]
    }

    static func syncConfiguredLocalPathsFromWorktree(
        projectRepoPath: String,
        worktreePath: String,
        syncPaths: [String]
    ) async throws {
        guard !syncPaths.isEmpty else { return }

        let baselineHashes = await loadBaselineFileHashes(worktreePath: worktreePath)
        for relativePath in syncPaths {
            let sourcePath = (worktreePath as NSString).appendingPathComponent(relativePath)
            guard sourceItemKind(atPath: sourcePath) != nil else { continue }

            let destinationPath = (projectRepoPath as NSString).appendingPathComponent(relativePath)
            do {
                try await mergeItem(
                    sourcePath: sourcePath,
                    destinationPath: destinationPath,
                    relativePath: relativePath,
                    destinationRootPath: projectRepoPath,
                    baselineFileHashes: baselineHashes
                )
            } catch let error as ThreadManagerError {
                throw error
            } catch {
                throw ThreadManagerError.localFileSyncFailed(
                    "Failed to sync \"\(relativePath)\" back to the main repo: \(error.localizedDescription)"
                )
            }
        }
    }

    private static func mergeItem(
        sourcePath: String,
        destinationPath: String,
        relativePath: String,
        destinationRootPath: String,
        baselineFileHashes: [String: String]?
    ) async throws {
        do {
            guard let sourceKind = sourceItemKind(atPath: sourcePath) else { return }
            let fm = FileManager.default

            switch sourceKind {
            case .directory:
                let children = (try fm.contentsOfDirectory(atPath: sourcePath)).sorted()
                for child in children {
                    try await mergeItem(
                        sourcePath: (sourcePath as NSString).appendingPathComponent(child),
                        destinationPath: (destinationPath as NSString).appendingPathComponent(child),
                        relativePath: (relativePath as NSString).appendingPathComponent(child),
                        destinationRootPath: destinationRootPath,
                        baselineFileHashes: baselineFileHashes
                    )
                }

            case .file:
                if try shouldSkipArchiveCopyForUnchangedFile(
                    sourcePath: sourcePath,
                    relativePath: relativePath,
                    baselineFileHashes: baselineFileHashes
                ) {
                    return
                }

                let parentRelativePath = (relativePath as NSString).deletingLastPathComponent
                if parentRelativePath != "." && !parentRelativePath.isEmpty {
                    let parentReady = ensureDirectoryTree(
                        destinationRootPath: destinationRootPath,
                        relativeDirectoryPath: parentRelativePath
                    )
                    guard parentReady else { return }
                }

                if let destinationKind = destinationItemKind(atPath: destinationPath) {
                    switch destinationKind {
                    case .directory:
                        return
                    case .file:
                        if try filesMatch(sourcePath: sourcePath, destinationPath: destinationPath) {
                            return
                        }
                        return
                    }
                }

                try fm.copyItem(atPath: sourcePath, toPath: destinationPath)
            }
        } catch let error as ThreadManagerError {
            throw error
        } catch {
            throw ThreadManagerError.localFileSyncFailed(
                "Local sync failed at \"\(relativePath)\": \(error.localizedDescription)"
            )
        }
    }

    private static func ensureDirectoryTree(
        destinationRootPath: String,
        relativeDirectoryPath: String
    ) -> Bool {
        let components = relativeDirectoryPath.split(separator: "/").map(String.init)
        guard !components.isEmpty else { return true }

        var currentRelativePath = ""
        for component in components {
            currentRelativePath = currentRelativePath.isEmpty
                ? component
                : (currentRelativePath as NSString).appendingPathComponent(component)

            let currentDestinationPath = (destinationRootPath as NSString).appendingPathComponent(currentRelativePath)
            guard ensureDirectoryExists(atPath: currentDestinationPath) else { return false }
        }
        return true
    }

    private static func ensureDirectoryExists(atPath destinationPath: String) -> Bool {
        let fm = FileManager.default
        if let existingKind = destinationItemKind(atPath: destinationPath) {
            switch existingKind {
            case .directory:
                return true
            case .file:
                return false
            }
        }

        do {
            try fm.createDirectory(atPath: destinationPath, withIntermediateDirectories: true)
            return true
        } catch {
            return false
        }
    }

    private static func sourceItemKind(atPath path: String) -> ItemKind? {
        let resolvedPath = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: resolvedPath, isDirectory: &isDirectory) else { return nil }
        return isDirectory.boolValue ? .directory : .file
    }

    private static func destinationItemKind(atPath path: String) -> ItemKind? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let type = attrs[.type] as? FileAttributeType else {
            return .file
        }
        return type == .typeDirectory ? .directory : .file
    }

    private static func filesMatch(sourcePath: String, destinationPath: String) throws -> Bool {
        let fm = FileManager.default
        guard let sourceAttrs = try? fm.attributesOfItem(atPath: sourcePath),
              let destinationAttrs = try? fm.attributesOfItem(atPath: destinationPath) else {
            return false
        }
        let sourceSize = (sourceAttrs[.size] as? NSNumber)?.int64Value
        let destinationSize = (destinationAttrs[.size] as? NSNumber)?.int64Value
        if sourceSize != destinationSize {
            return false
        }
        let sourceHash = try fileHash(atPath: sourcePath)
        let destinationHash = try fileHash(atPath: destinationPath)
        return sourceHash == destinationHash
    }

    private static func shouldSkipArchiveCopyForUnchangedFile(
        sourcePath: String,
        relativePath: String,
        baselineFileHashes: [String: String]?
    ) throws -> Bool {
        guard let baselineFileHashes,
              let baselineHash = baselineFileHashes[relativePath] else {
            return false
        }
        let currentHash = try fileHash(atPath: sourcePath)
        return currentHash == baselineHash
    }

    private static func fileHash(atPath path: String) throws -> String {
        let data = try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func loadBaselineFileHashes(worktreePath: String) async -> [String: String]? {
        guard let manifestPath = await baselineManifestPath(worktreePath: worktreePath) else {
            return nil
        }
        let url = URL(fileURLWithPath: manifestPath)
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let manifest = try? JSONDecoder().decode(BaselineManifest.self, from: data) else {
            return nil
        }
        return manifest.fileHashes
    }

    private static func baselineManifestPath(worktreePath: String) async -> String? {
        let preferred = await ShellExecutor.execute(
            "git rev-parse --path-format=absolute --git-path magent-local-sync-baseline.json",
            workingDirectory: worktreePath
        )
        var path = preferred.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if preferred.exitCode != 0 || path.isEmpty {
            let fallback = await ShellExecutor.execute(
                "git rev-parse --git-path magent-local-sync-baseline.json",
                workingDirectory: worktreePath
            )
            path = fallback.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard fallback.exitCode == 0, !path.isEmpty else { return nil }
        }
        if path.hasPrefix("/") {
            return path
        }
        return (worktreePath as NSString).appendingPathComponent(path)
    }
}

// MARK: - ThreadManager forwarding layer

extension ThreadManager {

    // MARK: - Base Branch Sync Target Resolution

    func resolveBaseBranchSyncTarget(for thread: MagentThread, project: Project) -> (path: String, label: String) {
        worktreeService.resolveBaseBranchSyncTarget(for: thread, project: project)
    }

    func resolveBaseBranchSyncTarget(baseBranch: String?, excludingThreadId: UUID, projectId: UUID, project: Project) -> (path: String, label: String) {
        worktreeService.resolveBaseBranchSyncTarget(baseBranch: baseBranch, excludingThreadId: excludingThreadId, projectId: projectId, project: project)
    }

    // MARK: - Local Sync In (Repo -> Worktree)

    func syncConfiguredLocalPathsIntoWorktree(
        project: Project,
        worktreePath: String,
        syncEntries: [LocalFileSyncEntry],
        promptForConflicts: Bool = false,
        sourceRootOverride: String? = nil
    ) async throws -> [String] {
        try await worktreeService.syncConfiguredLocalPathsIntoWorktree(
            project: project,
            worktreePath: worktreePath,
            syncEntries: syncEntries,
            promptForConflicts: promptForConflicts,
            sourceRootOverride: sourceRootOverride
        )
    }

    // MARK: - Local Sync Back (Worktree -> Repo)

    func syncConfiguredLocalPathsFromWorktree(
        project: Project,
        worktreePath: String,
        syncEntries: [LocalFileSyncEntry],
        promptForConflicts: Bool,
        destinationRootOverride: String? = nil
    ) async throws {
        try await worktreeService.syncConfiguredLocalPathsFromWorktree(
            project: project,
            worktreePath: worktreePath,
            syncEntries: syncEntries,
            promptForConflicts: promptForConflicts,
            destinationRootOverride: destinationRootOverride
        )
    }

    nonisolated func effectiveLocalSyncEntries(for thread: MagentThread, project: Project) -> [LocalFileSyncEntry] {
        // Pure value-type computation — implemented inline because nonisolated methods
        // cannot access the @MainActor-isolated worktreeService lazy var.
        let currentEntries = project.normalizedLocalFileSyncEntries
        if let snapshot = thread.localFileSyncEntriesSnapshot {
            let snapshotEntries = Project.normalizeLocalFileSyncEntries(snapshot)
            let currentPaths = Set(currentEntries.map(\.path))
            // Keep historical snapshot semantics for additions, but never sync paths
            // that are no longer configured in the project.
            return snapshotEntries.filter { currentPaths.contains($0.path) }
        }
        return currentEntries
    }
}
