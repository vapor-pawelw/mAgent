import Foundation
import Testing

@Suite
struct DiffRendererResourceTests {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func rendererFile(_ path: String) -> URL {
        repositoryRoot.appendingPathComponent("Magent/Resources/DiffRenderer/\(path)")
    }

    @Test
    func builtRendererUsesRelativeFlatAssetURLsForBundleLoading() throws {
        let html = try String(contentsOf: rendererFile("dist/index.html"), encoding: .utf8)

        #expect(html.contains("src=\"./index.js\""))
        #expect(html.contains("href=\"./index.css\""))
        #expect(!html.contains("src=\"/assets/"))
        #expect(!html.contains("href=\"/assets/"))
        #expect(!html.contains("src=\"./assets/"))
        #expect(!html.contains("href=\"./assets/"))
    }

    @Test
    func builtRendererUsesSingleLineNumberColumn() throws {
        let builtFiles = try FileManager.default.contentsOfDirectory(
            at: rendererFile("dist"),
            includingPropertiesForKeys: nil
        )
        let javascript = try builtFiles
            .filter { $0.pathExtension == "js" }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        let css = try builtFiles
            .filter { $0.pathExtension == "css" }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")

        #expect(!javascript.contains("line-number old"))
        #expect(!javascript.contains("line-number new"))
        #expect(!javascript.contains("oldNumber"))
        #expect(!javascript.contains("newNumber"))
        #expect(css.contains("grid-template-columns:minmax(48px,max-content) 24px"))
    }

    @Test
    func syntaxHighlighterLanguagesStayLazyLoaded() throws {
        let builtFiles = try FileManager.default.contentsOfDirectory(
            at: rendererFile("dist"),
            includingPropertiesForKeys: nil
        )
        let javascript = try builtFiles
            .filter { $0.pathExtension == "js" }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        let packageJSON = try String(contentsOf: rendererFile("package.json"), encoding: .utf8)

        #expect(javascript.contains("https://esm.sh/highlight.js@11.11.1/lib/core"))
        #expect(javascript.contains("https://esm.sh/highlight.js@11.11.1/lib/languages/"))
        #expect(!packageJSON.contains("\"highlight.js\""))
    }

    @Test
    func builtRendererUsesFriendlyCollapsibleHunkHeaders() throws {
        let builtFiles = try FileManager.default.contentsOfDirectory(
            at: rendererFile("dist"),
            includingPropertiesForKeys: nil
        )
        let javascript = try builtFiles
            .filter { $0.pathExtension == "js" }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        let css = try builtFiles
            .filter { $0.pathExtension == "css" }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")

        #expect(javascript.contains("Edited around line"))
        #expect(javascript.contains("Added "))
        #expect(javascript.contains("Removed "))
        #expect(javascript.contains("hidden line"))
        #expect(javascript.contains("startLine"))
        #expect(javascript.contains("endLine"))
        #expect(javascript.contains("replaceWith"))
        #expect(!javascript.contains("Before:"))
        #expect(!javascript.contains("After:"))
        #expect(javascript.contains("hunk-chevron"))
        #expect(javascript.contains("aria-expanded"))
        #expect(css.contains(".hunk-title"))
    }

    @Test
    func rendererSetDiffAlwaysPostsRenderedMessage() throws {
        let source = try String(contentsOf: rendererFile("src/main.js"), encoding: .utf8)

        #expect(source.contains("setDiff(payload)"))
        #expect(source.contains("renderCurrent();"))
        #expect(source.contains("post({ type: \"rendered\", fileCount: 0, reviewedCount: 0 });"))
        #expect(source.contains("post({\n    type: \"rendered\",\n    fileCount: files.length"))
    }
}
