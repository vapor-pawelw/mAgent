import Foundation
import MagentCore

/// Owns PR detection, cache management, and sync logic.
/// Extracted from `ThreadManager+PullRequests`.
///
/// Mutates `store.threads` directly and returns changed thread IDs for the caller to fan out.
final class PullRequestService {

    struct PullRequestActionTarget {
        let url: URL
        let provider: GitHostingProvider
        let isCreation: Bool
    }

    let store: ThreadStore
    let persistence: PersistenceService
    let git: GitService

    /// Called when thread data changes and the delegate/UI should be notified.
    var onThreadsChanged: (() -> Void)?

    /// Resolves the base branch for a thread.
    /// Injected by ThreadManager so we don't pull in helpers that live there.
    var resolveBaseBranch: ((MagentThread) -> String)?

    /// Formats a sync failure summary string. Injected from ThreadManager.
    var formatFailureSummary: ((_ title: String, _ details: [String], _ totalCount: Int?) -> String)?

    // MARK: - State (moved from ThreadManager)

    var isPRSyncRunning = false
    var prCache: [String: PullRequestCacheEntry] = [:]
    var prCacheLoaded = false

    // MARK: - Init

    init(store: ThreadStore, persistence: PersistenceService, git: GitService) {
        self.store = store
        self.persistence = persistence
        self.git = git
    }

    // MARK: - Remote Cache

    /// `_cachedRemoteByProjectId` is shared with GitState (Phase 3 will handle it).
    /// For now, the caller passes a reference to the shared remote cache via this closure.
    var cachedRemoteResolver: ((UUID, String) async -> GitRemote?)?

    // MARK: - Lookup Helpers

    private func prCacheKey(projectId: UUID, branch: String) -> String {
        "\(projectId.uuidString)::\(branch)"
    }

    private func updatePullRequestLookup(_ result: PullRequestLookupResult, branch: String, forThreadId threadId: UUID) async {
        guard let index = store.threads.firstIndex(where: { $0.id == threadId }) else {
            return
        }

        let nextState = PullRequestLookupState(
            info: store.threads[index].pullRequestInfo,
            status: store.threads[index].pullRequestLookupStatus,
            confirmedBranch: store.threads[index].pullRequestInfoBranch
        ).applying(result, branch: branch)

        guard store.threads[index].pullRequestInfo != nextState.info
                || store.threads[index].pullRequestLookupStatus != nextState.status
                || store.threads[index].pullRequestInfoBranch != nextState.confirmedBranch else {
            return
        }

        store.threads[index].pullRequestInfo = nextState.info
        store.threads[index].pullRequestInfoBranch = nextState.confirmedBranch
        store.threads[index].pullRequestLookupStatus = nextState.status
        savePRInfoToCache(info: nextState.info, status: nextState.status, thread: store.threads[index])
        await MainActor.run {
            onThreadsChanged?()
            NotificationCenter.default.post(name: .magentPullRequestInfoChanged, object: nil)
        }
    }

    private func normalizedPullRequestTargetBranch(for thread: MagentThread, project: Project) -> String {
        let sourceBranch = thread.actualBranch ?? thread.branchName

        let baseCandidate = resolveBaseBranch?(thread) ?? ""
        let normalizedBase = baseCandidate.hasPrefix("origin/")
            ? String(baseCandidate.dropFirst("origin/".count))
            : baseCandidate
        if !normalizedBase.isEmpty, normalizedBase != sourceBranch {
            return normalizedBase
        }

        if let configuredDefault = project.defaultBranch?.trimmingCharacters(in: .whitespacesAndNewlines),
           !configuredDefault.isEmpty,
           configuredDefault != sourceBranch {
            return configuredDefault
        }

        return "main"
    }

    func resolvePullRequestActionTarget(for thread: MagentThread) async -> PullRequestActionTarget? {
        if let info = thread.pullRequestInfo {
            return PullRequestActionTarget(
                url: info.url,
                provider: info.provider,
                isCreation: false
            )
        }

        let settings = persistence.loadSettings()
        guard let project = settings.projects.first(where: { $0.id == thread.projectId }),
              let remote = await cachedRemoteResolver?(project.id, project.repoPath) else {
            return nil
        }

        guard !thread.isMain, thread.pullRequestLookupStatus == .notFound else {
            return nil
        }

        let sourceBranch = thread.actualBranch ?? thread.branchName
        let targetBranch = normalizedPullRequestTargetBranch(for: thread, project: project)
        let title = thread.taskDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = remote.createPullRequestURL(sourceBranch: sourceBranch, targetBranch: targetBranch, title: title) else {
            return nil
        }
        return PullRequestActionTarget(
            url: url,
            provider: remote.provider,
            isCreation: true
        )
    }

    /// Returns a summary of any PR sync failures encountered during the pass.
    @discardableResult
    func runPRSyncTick() async -> ThreadManager.StatusSyncResult {
        guard !isPRSyncRunning else { return .success }
        isPRSyncRunning = true
        defer { isPRSyncRunning = false }

        let settings = persistence.loadSettings()
        // Prime the shared remote cache for all projects.
        for project in settings.projects {
            _ = await cachedRemoteResolver?(project.id, project.repoPath)
        }

        let snapshot = store.threads.filter { !$0.isArchived && !$0.isMain }
        var changed = false
        var hadErrors = false
        var errorCount = 0
        var failureDetails: [String] = []
        for thread in snapshot {
            guard let project = settings.projects.first(where: { $0.id == thread.projectId }) else {
                continue
            }

            guard let remote = await cachedRemoteResolver?(project.id, project.repoPath) else {
                guard let i = store.threads.firstIndex(where: { $0.id == thread.id }) else {
                    continue
                }
                let branch = store.threads[i].actualBranch ?? store.threads[i].branchName
                let nextState = PullRequestLookupState(
                    info: store.threads[i].pullRequestInfo,
                    status: store.threads[i].pullRequestLookupStatus,
                    confirmedBranch: store.threads[i].pullRequestInfoBranch
                ).applying(.unavailable, branch: branch)
                if store.threads[i].pullRequestInfo != nextState.info
                    || store.threads[i].pullRequestLookupStatus != nextState.status
                    || store.threads[i].pullRequestInfoBranch != nextState.confirmedBranch {
                    store.threads[i].pullRequestInfo = nextState.info
                    store.threads[i].pullRequestInfoBranch = nextState.confirmedBranch
                    store.threads[i].pullRequestLookupStatus = .unavailable
                    changed = true
                }
                continue
            }

            let branch = thread.actualBranch ?? thread.branchName
            let lookupResult: PullRequestLookupResult
            do {
                lookupResult = try await git.lookupPullRequest(remote: remote, branch: branch)
            } catch {
                hadErrors = true
                errorCount += 1
                if failureDetails.count < 3 {
                    let trimmedMessage = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                    let message = trimmedMessage.isEmpty ? "Unknown error." : trimmedMessage
                    failureDetails.append("\(project.name) / \(branch): \(message)")
                }
                lookupResult = .unavailable
            }
            guard let i = store.threads.firstIndex(where: { $0.id == thread.id }) else { continue }
            let nextState = PullRequestLookupState(
                info: store.threads[i].pullRequestInfo,
                status: store.threads[i].pullRequestLookupStatus,
                confirmedBranch: store.threads[i].pullRequestInfoBranch
            ).applying(lookupResult, branch: branch)
            if store.threads[i].pullRequestInfo != nextState.info
                || store.threads[i].pullRequestLookupStatus != nextState.status
                || store.threads[i].pullRequestInfoBranch != nextState.confirmedBranch {
                store.threads[i].pullRequestInfo = nextState.info
                store.threads[i].pullRequestInfoBranch = nextState.confirmedBranch
                store.threads[i].pullRequestLookupStatus = nextState.status
                savePRInfoToCache(info: nextState.info, status: nextState.status, thread: store.threads[i])
                changed = true
            }

            // Yield between threads so the background pass doesn't starve other work.
            await Task.yield()
        }

        if changed {
            await MainActor.run {
                onThreadsChanged?()
                NotificationCenter.default.post(name: .magentPullRequestInfoChanged, object: nil)
            }
        }

        prunePRCache()
        guard hadErrors else { return .success }
        let summary = formatFailureSummary?("PR sync failed", failureDetails, errorCount)
            ?? "PR sync failed (\(errorCount) error\(errorCount == 1 ? "" : "s"))."
        return .failure(summary)
    }

    /// Refreshes PR status for a single thread (called on thread selection).
    func refreshPRForSelectedThread(_ thread: MagentThread) {
        guard !thread.isMain else { return }
        Task {
            // Skip if a bulk sync is already running — it will cover this thread.
            guard !isPRSyncRunning else { return }

            let settings = persistence.loadSettings()
            guard let project = settings.projects.first(where: { $0.id == thread.projectId }),
                  let remote = await cachedRemoteResolver?(project.id, project.repoPath) else {
                let branch = thread.actualBranch ?? thread.branchName
                await updatePullRequestLookup(.unavailable, branch: branch, forThreadId: thread.id)
                return
            }

            let branch = thread.actualBranch ?? thread.branchName
            do {
                let lookupResult = try await git.lookupPullRequest(remote: remote, branch: branch)
                await updatePullRequestLookup(lookupResult, branch: branch, forThreadId: thread.id)
            } catch {
                await updatePullRequestLookup(.unavailable, branch: branch, forThreadId: thread.id)
            }
        }
    }

    // MARK: - PR Cache

    func loadPRCacheIfNeeded() {
        guard !prCacheLoaded else { return }
        prCache = persistence.loadPRCache()
        prCacheLoaded = true
    }

    /// Populates `pullRequestInfo` on all active threads from the file cache.
    /// Called at startup before the first live PR sync tick, so PR indicators appear immediately.
    func populatePRInfoFromCache() {
        loadPRCacheIfNeeded()
        guard !prCache.isEmpty else { return }

        let branchReferenceCounts = Dictionary(
            grouping: store.threads.filter { !$0.isArchived },
            by: { $0.actualBranch ?? $0.branchName }
        ).mapValues(\.count)
        var changed = false
        var migratedLegacyCache = false
        for i in store.threads.indices where !store.threads[i].isArchived && store.threads[i].pullRequestInfo == nil {
            let branch = store.threads[i].actualBranch ?? store.threads[i].branchName
            let scopedKey = prCacheKey(projectId: store.threads[i].projectId, branch: branch)
            let legacyCached = branchReferenceCounts[branch] == 1 ? prCache[branch] : nil
            let cached = prCache[scopedKey] ?? legacyCached
            if let cached {
                store.threads[i].pullRequestInfo = cached.toPullRequestInfo()
                store.threads[i].pullRequestInfoBranch = branch
                store.threads[i].pullRequestLookupStatus = .found
                changed = true
                if prCache[scopedKey] == nil, legacyCached != nil {
                    prCache[scopedKey] = cached
                    migratedLegacyCache = true
                }
            }
        }
        if migratedLegacyCache {
            persistence.savePRCache(prCache)
        }
        if changed {
            Task { @MainActor in
                onThreadsChanged?()
                NotificationCenter.default.post(name: .magentPullRequestInfoChanged, object: nil)
            }
        }
    }

    private func savePRInfoToCache(info: PullRequestInfo?, status: PullRequestLookupStatus, thread: MagentThread) {
        loadPRCacheIfNeeded()
        let branch = thread.actualBranch ?? thread.branchName
        let key = prCacheKey(projectId: thread.projectId, branch: branch)
        if let info, status == .found {
            prCache[key] = PullRequestCacheEntry(from: info)
        } else if status == .notFound {
            prCache.removeValue(forKey: key)
            prCache.removeValue(forKey: branch)
        } else {
            return
        }
        persistence.savePRCache(prCache)
    }

    private func prunePRCache() {
        loadPRCacheIfNeeded()
        let activeKeys = Set(
            store.threads
                .filter { !$0.isArchived }
                .map { prCacheKey(projectId: $0.projectId, branch: $0.actualBranch ?? $0.branchName) }
        )
        let before = prCache.count
        prCache = prCache.filter { activeKeys.contains($0.key) }
        if prCache.count != before {
            persistence.savePRCache(prCache)
        }
    }
}
