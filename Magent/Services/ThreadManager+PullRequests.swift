import Foundation

extension ThreadManager {

    func runPRSyncTick() async {
        // Build per-project remote cache (prefer origin, must be known provider)
        let settings = persistence.loadSettings()
        for project in settings.projects where _cachedRemoteByProjectId[project.id] == nil {
            let remotes = await git.getRemotes(repoPath: project.repoPath)
            let chosen = remotes.first(where: { $0.name == "origin" && $0.provider != .unknown })
                      ?? remotes.first(where: { $0.provider != .unknown })
            if let chosen { _cachedRemoteByProjectId[project.id] = chosen }
        }

        var changed = false
        for i in threads.indices where !threads[i].isArchived && !threads[i].isMain {
            guard let remote = _cachedRemoteByProjectId[threads[i].projectId] else {
                if threads[i].pullRequestInfo != nil { threads[i].pullRequestInfo = nil; changed = true }
                continue
            }
            let branch = threads[i].actualBranch ?? threads[i].branchName
            let info = await git.fetchPullRequest(remote: remote, branch: branch)
            if threads[i].pullRequestInfo != info { threads[i].pullRequestInfo = info; changed = true }
        }

        if changed {
            await MainActor.run {
                delegate?.threadManager(self, didUpdateThreads: threads)
                NotificationCenter.default.post(name: .magentPullRequestInfoChanged, object: nil)
            }
        }
    }
}
