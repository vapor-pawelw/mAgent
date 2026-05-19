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

}
