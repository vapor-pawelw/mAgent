import Foundation

public nonisolated struct WorktreeInfo: Sendable {
    public let path: String
    public let branch: String
    public let isBareStem: Bool

    public init(path: String, branch: String, isBareStem: Bool) {
        self.path = path
        self.branch = branch
        self.isBareStem = isBareStem
    }
}

public enum GitError: LocalizedError {
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return "Git error: \(message)"
        }
    }
}

public nonisolated enum GitHostingProvider: Sendable {
    case github
    case gitlab
    case bitbucket
    case unknown
}

public nonisolated enum PullRequestLookupResult: Sendable, Equatable {
    case found(PullRequestInfo)
    case notFound
    case unavailable
}

public nonisolated struct BranchUpstreamStatus: Sendable {
    public let upstreamRef: String?
    public let aheadCount: Int?
    public let behindCount: Int?

    public init(upstreamRef: String? = nil, aheadCount: Int? = nil, behindCount: Int? = nil) {
        self.upstreamRef = upstreamRef
        self.aheadCount = aheadCount
        self.behindCount = behindCount
    }

    public var hasRemoteCounterpart: Bool {
        upstreamRef != nil
    }

    public var displayText: String {
        guard upstreamRef != nil else { return "Local" }
        guard let suffix = inlineSuffix else { return "Up to date with remote" }
        return suffix
    }

    public var inlineSuffix: String? {
        guard upstreamRef != nil else { return "(local)" }

        let ahead = max(0, aheadCount ?? 0)
        let behind = max(0, behindCount ?? 0)

        switch (ahead, behind) {
        case (0, 0):
            return nil
        case let (ahead, behind):
            var parts: [String] = []
            if ahead > 0 {
                parts.append("+\(ahead)")
            }
            if behind > 0 {
                parts.append("-\(behind)")
            }
            return "(\(parts.joined(separator: " ")) from remote)"
        default:
            return nil
        }
    }

    public var displayUpstreamRef: String? {
        guard let upstreamRef else { return nil }
        let displayUpstream = upstreamRef.hasPrefix("origin/")
            ? String(upstreamRef.dropFirst("origin/".count))
            : upstreamRef
        return displayUpstream
    }

    public var tooltipText: String {
        guard let upstreamRef else {
            return "This branch has no configured remote counterpart."
        }

        let displayUpstream = displayUpstreamRef ?? upstreamRef
        let ahead = max(0, aheadCount ?? 0)
        let behind = max(0, behindCount ?? 0)

        switch (ahead, behind) {
        case (0, 0):
            return "Upstream: \(displayUpstream)"
        case let (ahead, behind) where ahead > 0 && behind > 0:
            return "Upstream: \(displayUpstream) (\(ahead) ahead, \(behind) behind)"
        case let (ahead, 0) where ahead > 0:
            return "Upstream: \(displayUpstream) (\(ahead) ahead)"
        case let (0, behind) where behind > 0:
            return "Upstream: \(displayUpstream) (\(behind) behind)"
        default:
            return "Upstream: \(displayUpstream)"
        }
    }
}

public nonisolated struct GitRemote: Sendable {
    public let name: String
    public let host: String
    public let repoPath: String  // e.g. "owner/repo"
    public let provider: GitHostingProvider

    public var repoWebURL: URL? {
        URL(string: "https://\(host)/\(repoPath)")
    }

    /// URL to the open pull/merge requests listing page.
    public var openPullRequestsURL: URL? {
        switch provider {
        case .github:
            return URL(string: "https://\(host)/\(repoPath)/pulls?q=is%3Aopen+is%3Apr")
        case .gitlab:
            return URL(string: "https://\(host)/\(repoPath)/-/merge_requests?state=opened")
        case .bitbucket:
            return URL(string: "https://\(host)/\(repoPath)/pull-requests?state=OPEN")
        case .unknown:
            return repoWebURL
        }
    }

    public func pullRequestURL(for branch: String, defaultBranch: String?) -> URL? {
        // If on the default branch, show the open PRs listing
        if let defaultBranch, branch == defaultBranch {
            return openPullRequestsURL
        }

        let encodedBranch = branch.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? branch

        switch provider {
        case .github:
            return URL(string: "https://\(host)/\(repoPath)/pulls?q=is%3Aopen+is%3Apr+head%3A\(encodedBranch)")
        case .gitlab:
            return URL(string: "https://\(host)/\(repoPath)/-/merge_requests?state=opened&source_branch=\(encodedBranch)")
        case .bitbucket:
            return URL(string: "https://\(host)/\(repoPath)/pull-requests?state=OPEN&source=\(encodedBranch)")
        case .unknown:
            return openPullRequestsURL
        }
    }

    public func createPullRequestURL(sourceBranch: String, targetBranch: String?, title: String? = nil) -> URL? {
        let normalizedSource = sourceBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTarget = targetBranch?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedSource.isEmpty else { return nil }

        switch provider {
        case .github:
            guard let normalizedTarget, !normalizedTarget.isEmpty else { return nil }
            let encodedTarget = Self.encodePathComponent(normalizedTarget)
            let encodedSource = Self.encodePathComponent(normalizedSource)
            var components = URLComponents(string: "https://\(host)/\(repoPath)/compare/\(encodedTarget)...\(encodedSource)")
            var queryItems = [URLQueryItem(name: "expand", value: "1")]
            if let normalizedTitle, !normalizedTitle.isEmpty {
                queryItems.append(URLQueryItem(name: "title", value: normalizedTitle))
            }
            components?.queryItems = queryItems
            return components?.url
        case .gitlab:
            var components = URLComponents(string: "https://\(host)/\(repoPath)/-/merge_requests/new")
            var queryItems = [URLQueryItem(name: "merge_request[source_branch]", value: normalizedSource)]
            if let normalizedTarget, !normalizedTarget.isEmpty {
                queryItems.append(URLQueryItem(name: "merge_request[target_branch]", value: normalizedTarget))
            }
            if let normalizedTitle, !normalizedTitle.isEmpty {
                queryItems.append(URLQueryItem(name: "merge_request[title]", value: normalizedTitle))
            }
            components?.queryItems = queryItems
            return components?.url
        case .bitbucket:
            guard let normalizedTarget, !normalizedTarget.isEmpty else { return nil }
            var components = URLComponents(string: "https://\(host)/\(repoPath)/pull-requests/new")
            components?.queryItems = [
                URLQueryItem(name: "source", value: normalizedSource),
                URLQueryItem(name: "dest", value: normalizedTarget)
            ]
            return components?.url
        case .unknown:
            return nil
        }
    }

    public func directPullRequestURL(number: Int) -> URL? {
        switch provider {
        case .github:    URL(string: "https://\(host)/\(repoPath)/pull/\(number)")
        case .gitlab:    URL(string: "https://\(host)/\(repoPath)/-/merge_requests/\(number)")
        case .bitbucket: URL(string: "https://\(host)/\(repoPath)/pull-requests/\(number)")
        case .unknown:   nil
        }
    }

    public static func parse(name: String, rawURL: String) -> GitRemote? {
        let (host, repoPath) = parseRemoteURL(rawURL)
        guard let host, let repoPath else { return nil }
        let provider = detectProvider(host: host)
        return GitRemote(name: name, host: host, repoPath: repoPath, provider: provider)
    }

    private static func detectProvider(host: String) -> GitHostingProvider {
        let lower = host.lowercased()
        if lower.contains("github") { return .github }
        if lower.contains("gitlab") { return .gitlab }
        if lower.contains("bitbucket") { return .bitbucket }
        return .unknown
    }

    private static func encodePathComponent(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    /// Parses git remote URLs in various formats:
    /// - `git@host:owner/repo.git`
    /// - `https://host/owner/repo.git`
    /// - `ssh://git@host/owner/repo.git`
    /// - `ssh://git@host:port/owner/repo.git`
    private static func parseRemoteURL(_ url: String) -> (host: String?, repoPath: String?) {
        var url = url

        // SSH shorthand: git@host:owner/repo.git
        if let atIndex = url.firstIndex(of: "@"),
           let colonIndex = url.firstIndex(of: ":"),
           colonIndex > atIndex,
           !url.hasPrefix("ssh://"),
           !url.hasPrefix("http") {
            let host = String(url[url.index(after: atIndex)..<colonIndex])
            var path = String(url[url.index(after: colonIndex)...])
            path = stripGitSuffix(path)
            return (host, path)
        }

        // URL-based: https://, ssh://, git://
        // Strip scheme
        if let schemeEnd = url.range(of: "://") {
            url = String(url[schemeEnd.upperBound...])
        }

        // Strip user@ prefix
        if let atIndex = url.firstIndex(of: "@") {
            url = String(url[url.index(after: atIndex)...])
        }

        // Split host (possibly with port) from path
        guard let slashIndex = url.firstIndex(of: "/") else { return (nil, nil) }
        var host = String(url[url.startIndex..<slashIndex])
        // Strip port from host
        if let colonIndex = host.firstIndex(of: ":") {
            host = String(host[host.startIndex..<colonIndex])
        }
        var path = String(url[url.index(after: slashIndex)...])
        path = stripGitSuffix(path)

        guard !host.isEmpty, !path.isEmpty else { return (nil, nil) }
        return (host, path)
    }

    private static func stripGitSuffix(_ path: String) -> String {
        if path.hasSuffix(".git") {
            return String(path.dropLast(4))
        }
        return path
    }
}

// MARK: - Diff Types

public nonisolated enum FileWorkingStatus: Sendable {
    case committed   // only in committed diff, working tree clean
    case staged      // staged changes
    case unstaged    // unstaged modifications
    case untracked   // untracked file

    /// Sort priority: untracked (0) → unstaged (1) → staged (2) → committed (3).
    public var sortOrder: Int {
        switch self {
        case .untracked: 0
        case .unstaged: 1
        case .staged: 2
        case .committed: 3
        }
    }
}

public nonisolated struct FileDiffEntry: Sendable {
    public let relativePath: String
    public let additions: Int
    public let deletions: Int
    public let workingStatus: FileWorkingStatus

    public init(relativePath: String, additions: Int, deletions: Int, workingStatus: FileWorkingStatus) {
        self.relativePath = relativePath
        self.additions = additions
        self.deletions = deletions
        self.workingStatus = workingStatus
    }
}

public nonisolated struct BranchCommit: Sendable {
    public let shortHash: String
    public let subject: String
    public let authorName: String
    public let date: String
    public init(shortHash: String, subject: String, authorName: String, date: String) {
        self.shortHash = shortHash
        self.subject = subject
        self.authorName = authorName
        self.date = date
    }
}
