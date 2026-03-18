import Foundation

public struct PullRequestCacheEntry: Codable, Sendable {
    public let number: Int
    public let url: URL
    public let provider: String
    public let isMerged: Bool
    public let isDraft: Bool
    public let cachedAt: Date

    public init(from info: PullRequestInfo, cachedAt: Date = Date()) {
        self.number = info.number
        self.url = info.url
        self.provider = info.provider.cacheKey
        self.isMerged = info.isMerged
        self.isDraft = info.isDraft
        self.cachedAt = cachedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        number = try container.decode(Int.self, forKey: .number)
        url = try container.decode(URL.self, forKey: .url)
        provider = try container.decode(String.self, forKey: .provider)
        isMerged = try container.decode(Bool.self, forKey: .isMerged)
        isDraft = try container.decodeIfPresent(Bool.self, forKey: .isDraft) ?? false
        cachedAt = try container.decode(Date.self, forKey: .cachedAt)
    }

    public func toPullRequestInfo() -> PullRequestInfo {
        PullRequestInfo(
            number: number,
            url: url,
            provider: GitHostingProvider.from(cacheKey: provider),
            isMerged: isMerged,
            isDraft: isDraft
        )
    }
}

extension GitHostingProvider {
    public var cacheKey: String {
        switch self {
        case .github: "github"
        case .gitlab: "gitlab"
        case .bitbucket: "bitbucket"
        case .unknown: "unknown"
        }
    }

    public static func from(cacheKey: String) -> GitHostingProvider {
        switch cacheKey {
        case "github": .github
        case "gitlab": .gitlab
        case "bitbucket": .bitbucket
        default: .unknown
        }
    }
}
