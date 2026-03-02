import Foundation

extension ThreadManager {

    // MARK: - Base Branch & Dirty State

    func resolveBaseBranch(for thread: MagentThread) -> String {
        if let base = thread.baseBranch, !base.isEmpty {
            return base
        }
        let settings = persistence.loadSettings()
        if let project = settings.projects.first(where: { $0.id == thread.projectId }),
           let defaultBranch = project.defaultBranch, !defaultBranch.isEmpty {
            return defaultBranch
        }
        return "main"
    }

    func refreshDirtyStates() async {
        var changed = false
        for i in threads.indices where !threads[i].isArchived && !threads[i].isMain {
            let dirty = await git.isDirty(worktreePath: threads[i].worktreePath)
            if threads[i].isDirty != dirty {
                threads[i].isDirty = dirty
                changed = true
            }
        }
        if changed {
            await MainActor.run {
                delegate?.threadManager(self, didUpdateThreads: threads)
            }
        }
    }

    func refreshDeliveredStates() async {
        // Load metadata caches per-project to pass fork points
        let settings = persistence.loadSettings()
        var cacheByProjectId: [UUID: WorktreeMetadataCache] = [:]
        for project in settings.projects {
            cacheByProjectId[project.id] = persistence.loadWorktreeCache(
                worktreesBasePath: project.resolvedWorktreesBasePath()
            )
        }

        var changed = false
        for i in threads.indices where !threads[i].isArchived && !threads[i].isMain {
            let baseBranch = resolveBaseBranch(for: threads[i])
            let forkPoint = cacheByProjectId[threads[i].projectId]?.worktrees[threads[i].name]?.forkPointCommit
            let delivered = await git.isFullyDelivered(
                worktreePath: threads[i].worktreePath,
                baseBranch: baseBranch,
                forkPointCommit: forkPoint
            )
            if threads[i].isFullyDelivered != delivered {
                threads[i].isFullyDelivered = delivered
                changed = true
            }
        }
        if changed {
            await MainActor.run {
                delegate?.threadManager(self, didUpdateThreads: threads)
            }
        }
    }

    /// Refreshes the delivered state for a single thread. Returns true if the value changed.
    @discardableResult
    func refreshDeliveredState(for threadId: UUID) async -> Bool {
        guard let i = threads.firstIndex(where: { $0.id == threadId }),
              !threads[i].isArchived, !threads[i].isMain else { return false }
        let baseBranch = resolveBaseBranch(for: threads[i])
        let settings = persistence.loadSettings()
        let forkPoint: String? = settings.projects
            .first(where: { $0.id == threads[i].projectId })
            .flatMap { persistence.loadWorktreeCache(worktreesBasePath: $0.resolvedWorktreesBasePath()).worktrees[threads[i].name]?.forkPointCommit }
        let delivered = await git.isFullyDelivered(
            worktreePath: threads[i].worktreePath,
            baseBranch: baseBranch,
            forkPointCommit: forkPoint
        )
        guard threads[i].isFullyDelivered != delivered else { return false }
        threads[i].isFullyDelivered = delivered
        return true
    }

    /// Removes stale entries from the worktree metadata cache for a project.
    func pruneWorktreeCache(for project: Project) {
        let activeNames = Set(
            threads
                .filter { $0.projectId == project.id && !$0.isArchived && !$0.isMain }
                .map(\.name)
        )
        persistence.pruneWorktreeCache(
            worktreesBasePath: project.resolvedWorktreesBasePath(),
            activeNames: activeNames
        )
    }

    func refreshBranchStates() async {
        let settings = persistence.loadSettings()
        var changed = false
        for i in threads.indices where !threads[i].isArchived {
            let worktreePath = threads[i].worktreePath
            guard FileManager.default.fileExists(atPath: worktreePath) else { continue }

            let actual = await git.getCurrentBranch(workingDirectory: worktreePath)

            let expected: String?
            if threads[i].isMain {
                if let project = settings.projects.first(where: { $0.id == threads[i].projectId }),
                   let defaultBranch = project.defaultBranch, !defaultBranch.isEmpty {
                    expected = defaultBranch
                } else if let detected = await git.detectDefaultBranch(repoPath: worktreePath) {
                    expected = detected
                } else {
                    expected = nil
                }
            } else {
                expected = threads[i].branchName
            }

            let mismatch: Bool
            if let expected, let actual {
                mismatch = actual != expected
            } else {
                mismatch = false
            }
            if threads[i].actualBranch != actual || threads[i].expectedBranch != expected || threads[i].hasBranchMismatch != mismatch {
                threads[i].actualBranch = actual
                threads[i].expectedBranch = expected
                threads[i].hasBranchMismatch = mismatch
                changed = true
            }
        }
        if changed {
            await MainActor.run {
                delegate?.threadManager(self, didUpdateThreads: threads)
            }
        }
    }

    func resolveExpectedBranch(for thread: MagentThread) -> String? {
        // Prefer the cached expected branch from the polling cycle
        if let cached = thread.expectedBranch, !cached.isEmpty {
            return cached
        }
        if thread.isMain {
            let settings = persistence.loadSettings()
            if let project = settings.projects.first(where: { $0.id == thread.projectId }),
               let defaultBranch = project.defaultBranch, !defaultBranch.isEmpty {
                return defaultBranch
            }
            return nil
        }
        return thread.branchName
    }

    func switchToExpectedBranch(threadId: UUID) async throws {
        guard let index = threads.firstIndex(where: { $0.id == threadId }) else {
            throw ThreadManagerError.threadNotFound
        }
        let thread = threads[index]
        guard let expected = resolveExpectedBranch(for: thread) else {
            throw ThreadManagerError.noExpectedBranch
        }
        try await git.checkoutBranch(workingDirectory: thread.worktreePath, branchName: expected)

        // Refresh branch state immediately
        let actual = await git.getCurrentBranch(workingDirectory: thread.worktreePath)
        threads[index].actualBranch = actual
        threads[index].hasBranchMismatch = actual != nil && actual != expected
        await MainActor.run {
            delegate?.threadManager(self, didUpdateThreads: threads)
        }
    }


    func refreshDiffStats(for threadId: UUID) async -> [FileDiffEntry] {
        guard let thread = threads.first(where: { $0.id == threadId }) else { return [] }
        let baseBranch = resolveBaseBranch(for: thread)
        return await git.diffStats(worktreePath: thread.worktreePath, baseBranch: baseBranch)
    }

    // MARK: - Move Worktrees Base Path

    func moveWorktreesBasePath(for project: Project, from oldBase: String, to newBase: String) async throws {
        let fm = FileManager.default

        // Collect active (non-archived, non-main) threads for this project
        let affectedIndices = threads.indices.filter { i in
            threads[i].projectId == project.id && !threads[i].isArchived && !threads[i].isMain
        }

        // Build list of worktree directory names to move
        let worktreeNames: [(index: Int, dirName: String)] = affectedIndices.compactMap { i in
            let dirName = URL(fileURLWithPath: threads[i].worktreePath).lastPathComponent
            // Only include if the worktree actually lives under oldBase
            let expectedPath = (oldBase as NSString).appendingPathComponent(dirName)
            guard threads[i].worktreePath == expectedPath else { return nil }
            return (i, dirName)
        }

        // Check for conflicts in destination
        var conflicts: [String] = []
        for (_, dirName) in worktreeNames {
            let destPath = (newBase as NSString).appendingPathComponent(dirName)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: destPath, isDirectory: &isDir) {
                // Allow if it's a symlink (rename compatibility symlink)
                let url = URL(fileURLWithPath: destPath)
                if let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]),
                   values.isSymbolicLink == true {
                    continue
                }
                conflicts.append(dirName)
            }
        }
        if !conflicts.isEmpty {
            throw ThreadManagerError.worktreePathConflict(conflicts)
        }

        // Create destination directory if needed
        try fm.createDirectory(atPath: newBase, withIntermediateDirectories: true)

        // Move each worktree using `git worktree move`
        for (index, dirName) in worktreeNames {
            let oldPath = (oldBase as NSString).appendingPathComponent(dirName)
            let newPath = (newBase as NSString).appendingPathComponent(dirName)

            guard fm.fileExists(atPath: oldPath) else { continue }

            do {
                try await git.moveWorktree(repoPath: project.repoPath, oldPath: oldPath, newPath: newPath)
            } catch {
                // If git worktree move fails (e.g. already moved manually), try a filesystem move
                do {
                    try fm.moveItem(atPath: oldPath, toPath: newPath)
                } catch {
                    // Skip this worktree — it may have been moved manually already
                    continue
                }
            }

            threads[index].worktreePath = newPath

            // Update MAGENT_WORKTREE_PATH on live tmux sessions
            for sessionName in threads[index].tmuxSessionNames {
                try? await tmux.setEnvironment(sessionName: sessionName, key: "MAGENT_WORKTREE_PATH", value: newPath)
            }
        }

        // Move rename symlinks: entries in old base that are symlinks pointing into old base
        if let entries = try? fm.contentsOfDirectory(atPath: oldBase) {
            for entry in entries {
                let fullPath = (oldBase as NSString).appendingPathComponent(entry)
                let url = URL(fileURLWithPath: fullPath)
                guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]),
                      values.isSymbolicLink == true else { continue }

                // Read the symlink target
                guard let target = try? fm.destinationOfSymbolicLink(atPath: fullPath) else { continue }

                // Check if target points to something now under newBase
                let movedNames = Set(worktreeNames.map(\.dirName))
                let targetBaseName = URL(fileURLWithPath: target).lastPathComponent
                guard movedNames.contains(targetBaseName) else { continue }

                // Create updated symlink in newBase pointing to new location
                let newSymlinkPath = (newBase as NSString).appendingPathComponent(entry)
                let newTarget = (newBase as NSString).appendingPathComponent(targetBaseName)
                try? fm.removeItem(atPath: newSymlinkPath)
                try? fm.createSymbolicLink(atPath: newSymlinkPath, withDestinationPath: newTarget)
                try? fm.removeItem(atPath: fullPath)
            }
        }

        // Move .magent-cache.json: merge old cache into destination
        let oldCache = persistence.loadWorktreeCache(worktreesBasePath: oldBase)
        if !oldCache.worktrees.isEmpty {
            var newCache = persistence.loadWorktreeCache(worktreesBasePath: newBase)
            for (key, value) in oldCache.worktrees {
                // Old cache entries take precedence (they're the ones being moved)
                newCache.worktrees[key] = value
            }
            persistence.saveWorktreeCache(newCache, worktreesBasePath: newBase)
            // Remove old cache file
            let oldCacheURL = URL(fileURLWithPath: oldBase).appendingPathComponent(".magent-cache.json")
            try? fm.removeItem(at: oldCacheURL)
        }

        // Save updated thread records
        try persistence.saveThreads(threads)

        // Try to remove old base directory if empty
        if let remaining = try? fm.contentsOfDirectory(atPath: oldBase), remaining.isEmpty {
            try? fm.removeItem(atPath: oldBase)
        }
    }
}
