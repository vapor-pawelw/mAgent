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

        let snapshot = threads.filter { !$0.isArchived && !$0.isMain }
        var changed = false
        for thread in snapshot {
            guard let remote = _cachedRemoteByProjectId[thread.projectId] else {
                if let i = threads.firstIndex(where: { $0.id == thread.id }),
                   threads[i].pullRequestInfo != nil {
                    threads[i].pullRequestInfo = nil; changed = true
                }
                continue
            }
            let branch = thread.actualBranch ?? thread.branchName
            let info = await git.fetchPullRequest(remote: remote, branch: branch)
            guard let i = threads.firstIndex(where: { $0.id == thread.id }) else { continue }
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
