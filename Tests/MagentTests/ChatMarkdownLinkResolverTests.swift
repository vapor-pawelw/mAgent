import Foundation
import MagentCore
import Testing

@Suite("ChatMarkdownLinkResolver")
struct ChatMarkdownLinkResolverTests {
    @Test("Resolves explicit https URL as web target")
    func resolvesHTTPSURL() throws {
        let resolved = ChatMarkdownLinkResolver.resolve("https://example.com/path?q=1", workingDirectory: nil)
        let target = try #require(resolved)
        #expect(target == .web(URL(string: "https://example.com/path?q=1")!))
    }

    @Test("Resolves file markdown link fragment to local file")
    func resolvesFileURLWithFragment() throws {
        let resolved = ChatMarkdownLinkResolver.resolve("file:///Users/me/ChatTabViewController.swift#L42C3", workingDirectory: nil)
        let target = try #require(resolved)
        #expect(
            target == .localFile(
                ChatMarkdownFileLocation(
                    url: URL(fileURLWithPath: "/Users/me/ChatTabViewController.swift"),
                    line: 42,
                    column: 3
                )
            )
        )
    }

    @Test("Resolves absolute local path with line and column suffix")
    func resolvesAbsolutePathWithLineColumn() throws {
        let resolved = ChatMarkdownLinkResolver.resolve("/Users/me/Thread.swift:12:4", workingDirectory: nil)
        let target = try #require(resolved)
        #expect(
            target == .localFile(
                ChatMarkdownFileLocation(
                    url: URL(fileURLWithPath: "/Users/me/Thread.swift"),
                    line: 12,
                    column: 4
                )
            )
        )
    }

    @Test("Resolves absolute local path with line suffix")
    func resolvesAbsolutePathWithLineOnly() throws {
        let resolved = ChatMarkdownLinkResolver.resolve("/Users/me/Thread.swift:761", workingDirectory: nil)
        let target = try #require(resolved)
        #expect(
            target == .localFile(
                ChatMarkdownFileLocation(
                    url: URL(fileURLWithPath: "/Users/me/Thread.swift"),
                    line: 761,
                    column: nil
                )
            )
        )
    }

    @Test("Resolves relative paths against working directory")
    func resolvesRelativePathAgainstWorkingDirectory() throws {
        let resolved = ChatMarkdownLinkResolver.resolve("Magent/Views/Terminal/ChatTabViewController.swift", workingDirectory: "/repo/worktree")
        let target = try #require(resolved)
        #expect(
            target == .localFile(
                ChatMarkdownFileLocation(
                    url: URL(fileURLWithPath: "/repo/worktree/Magent/Views/Terminal/ChatTabViewController.swift"),
                    line: nil,
                    column: nil
                )
            )
        )
    }

    @Test("Resolves an internal focused diff target without requiring the file to exist")
    func resolvesFocusedDiffTarget() {
        let resolved = ChatMarkdownLinkResolver.resolve(
            "magent-diff://file?path=Packages%2FMagentModules%2FSources%2FChat%20UI.swift",
            workingDirectory: nil
        )

        #expect(resolved == .diffFile("Packages/MagentModules/Sources/Chat UI.swift"))
    }

    @Test("Rejects unsupported non-web URL schemes")
    func rejectsUnsupportedSchemes() {
        #expect(ChatMarkdownLinkResolver.resolve("mailto:test@example.com", workingDirectory: nil) == nil)
    }

    @Test("Rejects relative paths without working directory")
    func rejectsRelativePathsWithoutWorkingDirectory() {
        #expect(ChatMarkdownLinkResolver.resolve("Magent/file.swift", workingDirectory: nil) == nil)
    }
}
