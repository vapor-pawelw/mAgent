import CoreGraphics
import Foundation
import Testing

@Suite("App launch")
struct AppLaunchTests {
    @Test("Debug app presents its main window after startup")
    func debugAppPresentsMainWindowAfterStartup() async throws {
        let testBundle = try #require(Bundle.allBundles.first {
            $0.bundleIdentifier == "com.magent.app.tests"
        })
        let executableURL = testBundle.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("Magent.app/Contents/MacOS/Magent")
        let process = Process()
        let output = Pipe()
        let sandboxURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("magent-launch-smoke-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sandboxURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandboxURL) }
        process.executableURL = executableURL
        process.arguments = ["-ApplePersistenceIgnoreState", "YES"]
        process.environment = ProcessInfo.processInfo.environment.merging(
            [
                "MAGENT_APP_LAUNCH_SMOKE_TEST": "1",
                "HOME": sandboxURL.path,
                "CFFIXED_USER_HOME": sandboxURL.path,
                "TMPDIR": sandboxURL.path,
            ],
            uniquingKeysWith: { _, testValue in testValue }
        )
        process.standardOutput = output
        process.standardError = output

        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }

        var presentedMainWindow = false
        for _ in 0..<50 where process.isRunning && !presentedMainWindow {
            let windows = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]] ?? []
            presentedMainWindow = windows.contains { window in
                let ownerPID = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
                let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue
                return ownerPID == process.processIdentifier && layer == 0
            }
            if !presentedMainWindow {
                try await Task.sleep(for: .milliseconds(100))
            }
        }
        let remainedRunning = process.isRunning
        if remainedRunning {
            process.terminate()
            process.waitUntilExit()
        }
        let diagnostics = String(
            data: output.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        #expect(remainedRunning, "Magent exited during startup:\n\(diagnostics)")
        #expect(presentedMainWindow, "Magent did not present an on-screen main window:\n\(diagnostics)")
    }
}
