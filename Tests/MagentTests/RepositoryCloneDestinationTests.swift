import MagentCore
import Testing

@Suite
struct RepositoryCloneDestinationTests {
    @Test(arguments: [
        ("https://github.com/owner/repo.git", "repo"),
        ("git@github.com:owner/repo.git", "repo"),
        ("ssh://git@github.com/owner/repo.git", "repo"),
        ("https://github.com/owner/repo", "repo"),
        ("https://github.com/owner/repo.git?depth=1", "repo"),
    ])
    func suggestsDirectoryNameFromCommonRemoteURLForms(remoteURL: String, expectedName: String) {
        #expect(RepositoryCloneDestination.suggestedDirectoryName(from: remoteURL) == expectedName)
    }

    @Test
    func rejectsEmptyRemoteURL() {
        #expect(RepositoryCloneDestination.suggestedDirectoryName(from: "  \n ") == nil)
    }
}
