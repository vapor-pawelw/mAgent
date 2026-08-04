import Cocoa
import MagentCore

private struct CodexPackageRelease: Decodable, Sendable {
    let version: String
}

@MainActor
final class CodexUpdateService {
    static let shared = CodexUpdateService()

    private let persistence = PersistenceService.shared
    private let latestReleaseURL = URL(string: "https://registry.npmjs.org/@openai%2Fcodex/latest")!
    private var pollingTask: Task<Void, Never>?
    private var shownBannerVersion: String?

    private(set) var isInstalled = false
    private(set) var isChecking = false
    private(set) var isUpdating = false
    private(set) var pendingUpdateSummary: CodexCLIUpdateSummary?

    func checkOnLaunchIfEnabled() async {
        guard persistence.loadSettings().autoCheckForUpdates else { return }
        await check(manual: false)
    }

    func checkManually() async {
        await check(manual: true)
    }

    func startPeriodicChecks() {
        guard persistence.loadSettings().autoCheckForUpdates else { return }
        stopPeriodicChecks()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3600))
                guard !Task.isCancelled else { break }
                await self?.check(manual: false)
            }
        }
    }

    func stopPeriodicChecks() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func handleAutoCheckSettingChanged() {
        persistence.loadSettings().autoCheckForUpdates ? startPeriodicChecks() : stopPeriodicChecks()
    }

    func installAvailableUpdate() async {
        guard pendingUpdateSummary != nil, !isUpdating else { return }
        isUpdating = true
        notifyStateChanged()
        BannerManager.shared.show(
            message: String(localized: .UpdateStrings.codexUpdateInstalling),
            style: .info,
            duration: nil,
            isDismissible: false,
            showsSpinner: true
        )

        let result = await ShellExecutor.execute(codexShellCommand(arguments: "update"))
        isUpdating = false
        if result.exitCode == 0 {
            pendingUpdateSummary = nil
            var settings = persistence.loadSettings()
            settings.skippedCodexUpdateVersion = nil
            try? persistence.saveSettings(settings)
            await check(manual: false, showBanner: false)
            BannerManager.shared.show(
                message: String(localized: .UpdateStrings.codexUpdateSucceeded),
                style: .info,
                duration: 5
            )
        } else {
            let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            BannerManager.shared.show(
                message: String(localized: .UpdateStrings.codexUpdateFailed),
                style: .warning,
                duration: nil,
                details: detail.isEmpty ? nil : detail
            )
        }
        notifyStateChanged()
    }

    private func check(manual: Bool, showBanner: Bool = true) async {
        guard !isChecking, !isUpdating else { return }
        isChecking = true
        notifyStateChanged()
        defer {
            isChecking = false
            notifyStateChanged()
        }

        let versionResult = await ShellExecutor.execute(codexShellCommand(arguments: "--version"))
        guard versionResult.exitCode == 0,
              let installed = CodexCLIUpdatePolicy.version(from: versionResult.stdout) else {
            isInstalled = false
            pendingUpdateSummary = nil
            if manual {
                BannerManager.shared.show(message: String(localized: .UpdateStrings.codexNotInstalled), style: .warning, duration: 5)
            }
            return
        }
        isInstalled = true

        do {
            let (data, response) = try await URLSession.shared.data(from: latestReleaseURL)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let release = try JSONDecoder().decode(CodexPackageRelease.self, from: data)
            let summary = CodexCLIUpdatePolicy.updateSummary(
                installedVersion: installed,
                availableVersion: release.version,
                skippedVersion: persistence.loadSettings().skippedCodexUpdateVersion
            )
            pendingUpdateSummary = summary

            guard let summary else {
                if manual {
                    BannerManager.shared.show(
                        message: String(localized: .UpdateStrings.codexUpToDate(installed)),
                        style: .info,
                        duration: 5
                    )
                }
                return
            }
            guard showBanner, !summary.isSkipped, shownBannerVersion != summary.availableVersion else { return }
            shownBannerVersion = summary.availableVersion
            showUpdateBanner(summary)
        } catch {
            if manual {
                BannerManager.shared.show(message: error.localizedDescription, style: .warning, duration: 5)
            }
        }
    }

    private func showUpdateBanner(_ summary: CodexCLIUpdateSummary) {
        BannerManager.shared.show(
            message: String(localized: .UpdateStrings.codexUpdateAvailable(summary.installedVersion, summary.availableVersion)),
            style: .info,
            duration: nil,
            actions: [
                BannerAction(title: String(localized: .UpdateStrings.updateNow)) {
                    Task { @MainActor in await CodexUpdateService.shared.installAvailableUpdate() }
                },
                BannerAction(title: String(localized: .UpdateStrings.updateSkipVersion)) {
                    CodexUpdateService.shared.skip(summary.availableVersion)
                },
            ]
        )
    }

    private func skip(_ version: String) {
        var settings = persistence.loadSettings()
        settings.skippedCodexUpdateVersion = version
        try? persistence.saveSettings(settings)
        pendingUpdateSummary = pendingUpdateSummary.map {
            CodexCLIUpdateSummary(installedVersion: $0.installedVersion, availableVersion: $0.availableVersion, isSkipped: true)
        }
        BannerManager.shared.dismissCurrent()
        notifyStateChanged()
    }

    private func notifyStateChanged() {
        NotificationCenter.default.post(name: .magentCodexUpdateStateChanged, object: nil)
    }

    private func codexShellCommand(arguments: String) -> String {
        let configuredShell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shell = configuredShell.lowercased().hasSuffix("zsh") ? configuredShell : "/bin/zsh"
        let zdotdir = ThreadManager.shared.ensureManagedZdotdir()
        let innerCommand = "command codex \(arguments)"
        return "env ZDOTDIR=\(ShellExecutor.shellQuote(zdotdir)) \(ShellExecutor.shellQuote(shell)) -il -c \(ShellExecutor.shellQuote(innerCommand))"
    }
}
