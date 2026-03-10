import Cocoa
import MagentCore

private struct UpdateReleaseAsset: Decodable, Sendable {
    let name: String
    let browserDownloadURL: String

    private enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

private struct UpdateReleaseResponse: Decodable, Sendable {
    let tagName: String
    let draft: Bool
    let prerelease: Bool
    let body: String?
    let assets: [UpdateReleaseAsset]

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case draft
        case prerelease
        case body
        case assets
    }
}

private struct SemanticVersion: Comparable, Sendable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ raw: String) {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("v") || value.hasPrefix("V") {
            value.removeFirst()
        }
        let core = value.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? value
        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        guard let major = parts.indices.contains(0) ? Int(parts[0]) : nil else { return nil }
        let minor = parts.indices.contains(1) ? Int(parts[1]) : 0
        let patch = parts.indices.contains(2) ? Int(parts[2]) : 0
        guard let minor, let patch else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }

    var displayString: String {
        "\(major).\(minor).\(patch)"
    }
}

private struct AvailableUpdate: Sendable {
    let version: SemanticVersion
    let releaseNotes: String?
    let assetURL: URL
    let assetKind: ReleaseAssetKind
}

struct PendingUpdateSummary: Sendable {
    let currentVersion: String
    let availableVersion: String
    let releaseNotes: String?
    let isSkipped: Bool
}

private enum UpdateAvailability: Sendable {
    case available(AvailableUpdate)
    case upToDate
    case noPublishedRelease
}

private enum ReleaseAssetKind: String, Sendable {
    case dmg
    case zip
}

private enum UpdateError: LocalizedError {
    case invalidHTTPStatus(Int)
    case invalidLatestVersion(String)
    case invalidCurrentVersion(String)
    case missingReleaseAsset
    case unwritableInstallLocation(String)
    case failedToStartUpdater(String)

    var errorDescription: String? {
        switch self {
        case .invalidHTTPStatus(let status):
            return "Update server returned HTTP \(status)."
        case .invalidLatestVersion(let version):
            return "Latest release version is invalid: \(version)."
        case .invalidCurrentVersion(let version):
            return "Current app version is invalid: \(version)."
        case .missingReleaseAsset:
            return "Latest release is missing a Magent.dmg or Magent.zip asset."
        case .unwritableInstallLocation(let path):
            return "Install location is not writable: \(path)."
        case .failedToStartUpdater(let message):
            return "Could not start updater: \(message)"
        }
    }
}

@MainActor
final class UpdateService {

    static let shared = UpdateService()

    private let persistence = PersistenceService.shared
    private let releasesURL = URL(string: "https://api.github.com/repos/vapor-pawelw/magent-releases/releases?per_page=10")!
    private let updaterLogPath = "/tmp/magent-self-update.log"

    private var isChecking = false
    private var isUpdating = false
    private var detectedUpdate: AvailableUpdate?

    private enum InstallStrategy {
        case homebrewCask
        case bundleReplacement
    }

    private enum CheckTrigger {
        case launch
        case manual
    }

    func checkForUpdatesOnLaunchIfEnabled() async {
        let settings = persistence.loadSettings()
        guard settings.autoCheckForUpdates else { return }
        await checkForUpdates(trigger: .launch)
    }

    func checkForUpdatesManually() async {
        await checkForUpdates(trigger: .manual)
    }

    var pendingUpdateSummary: PendingUpdateSummary? {
        guard let detectedUpdate else { return nil }
        let availableVersion = detectedUpdate.version.displayString
        return PendingUpdateSummary(
            currentVersion: currentVersionString(),
            availableVersion: availableVersion,
            releaseNotes: normalizedReleaseNotes(detectedUpdate.releaseNotes),
            isSkipped: isVersionSkipped(availableVersion)
        )
    }

    func installDetectedUpdateIfAvailable() async {
        guard let detectedUpdate else { return }
        await installUpdate(detectedUpdate)
    }

    private func checkForUpdates(trigger: CheckTrigger) async {
        guard !isChecking else {
            if trigger == .manual {
                BannerManager.shared.show(message: String(localized: .UpdateStrings.updateCheckAlreadyInProgress), style: .info)
            }
            return
        }

        isChecking = true
        defer { isChecking = false }
        pruneSkippedVersionIfCurrentOrOlder()

        do {
            switch try await fetchUpdateAvailability() {
            case .noPublishedRelease:
                setDetectedUpdate(nil)
                if trigger == .manual {
                    BannerManager.shared.show(
                        message: String(localized: .UpdateStrings.updateNoNewReleases),
                        style: .info
                    )
                }
            case .upToDate:
                setDetectedUpdate(nil)
                if trigger == .manual {
                    BannerManager.shared.show(
                        message: String(localized: .UpdateStrings.updateUpToDate(currentVersionString())),
                        style: .info
                    )
                }
            case .available(let available):
                setDetectedUpdate(available)
                let availableVersion = available.version.displayString
                guard !isVersionSkipped(availableVersion) else {
                    if trigger == .manual {
                        BannerManager.shared.show(
                            message: String(localized: .UpdateStrings.updateVersionSkipped(availableVersion)),
                            style: .info
                        )
                    }
                    return
                }
                showAvailableUpdateBanner(available)
            }
        } catch {
            if trigger == .manual {
                BannerManager.shared.show(
                    message: error.localizedDescription,
                    style: .warning,
                    duration: 5
                )
            }
        }
    }

    private func showAvailableUpdateBanner(_ available: AvailableUpdate) {
        let availableVersion = available.version.displayString
        let currentVersion = currentVersionString()
        BannerManager.shared.show(
            message: String(localized: .UpdateStrings.updateAvailable(currentVersion, availableVersion)),
            style: .info,
            duration: nil,
            isDismissible: true,
            actions: [
                BannerAction(title: String(localized: .UpdateStrings.updateNow)) {
                    Task { @MainActor in
                        await UpdateService.shared.installUpdate(available)
                    }
                },
                BannerAction(title: String(localized: .UpdateStrings.updateSkipVersion)) {
                    Task { @MainActor in
                        UpdateService.shared.skipVersion(availableVersion)
                    }
                },
            ],
            details: normalizedReleaseNotes(available.releaseNotes),
            detailsCollapsedTitle: String(localized: .UpdateStrings.updateShowChanges),
            detailsExpandedTitle: String(localized: .UpdateStrings.updateHideChanges)
        )
    }

    private func skipVersion(_ version: String) {
        var settings = persistence.loadSettings()
        settings.skippedUpdateVersion = version
        try? persistence.saveSettings(settings)
        notifyUpdateStateChanged()
        BannerManager.shared.dismissCurrent()
    }

    private func setDetectedUpdate(_ update: AvailableUpdate?) {
        let previousVersion = detectedUpdate?.version.displayString
        let nextVersion = update?.version.displayString
        let previousNotes = detectedUpdate?.releaseNotes
        let nextNotes = update?.releaseNotes
        detectedUpdate = update

        guard previousVersion != nextVersion || previousNotes != nextNotes else { return }
        notifyUpdateStateChanged()
    }

    private func notifyUpdateStateChanged() {
        NotificationCenter.default.post(name: .magentUpdateStateChanged, object: nil)
    }

    private func isVersionSkipped(_ version: String) -> Bool {
        persistence.loadSettings().skippedUpdateVersion == version
    }

    private func pruneSkippedVersionIfCurrentOrOlder() {
        let currentVersionRaw = currentVersionString()
        guard let currentVersion = SemanticVersion(currentVersionRaw) else { return }

        var settings = persistence.loadSettings()
        guard let skippedVersionRaw = settings.skippedUpdateVersion,
              let skippedVersion = SemanticVersion(skippedVersionRaw),
              skippedVersion <= currentVersion else {
            return
        }

        settings.skippedUpdateVersion = nil
        try? persistence.saveSettings(settings)
        notifyUpdateStateChanged()
    }

    private func normalizedReleaseNotes(_ notes: String?) -> String? {
        guard let notes else { return nil }
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func fetchUpdateAvailability() async throws -> UpdateAvailability {
        var request = URLRequest(url: releasesURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Magent-Updater", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateError.invalidHTTPStatus(-1)
        }
        guard (200...299).contains(http.statusCode) else {
            throw UpdateError.invalidHTTPStatus(http.statusCode)
        }

        let releases = try JSONDecoder().decode([UpdateReleaseResponse].self, from: data)
        guard let latest = releases.first(where: { !$0.draft && !$0.prerelease }) else {
            return .noPublishedRelease
        }

        guard let latestVersion = SemanticVersion(latest.tagName) else {
            throw UpdateError.invalidLatestVersion(latest.tagName)
        }
        let currentVersionRaw = currentVersionString()
        guard let currentVersion = SemanticVersion(currentVersionRaw) else {
            throw UpdateError.invalidCurrentVersion(currentVersionRaw)
        }
        guard latestVersion > currentVersion else { return .upToDate }

        let preferredAsset: (asset: UpdateReleaseAsset, kind: ReleaseAssetKind)? =
            latest.assets.first(where: { $0.name == "Magent.dmg" }).map { ($0, .dmg) }
            ?? latest.assets.first(where: { $0.name == "Magent.zip" }).map { ($0, .zip) }
            ?? latest.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }).map { ($0, .dmg) }
            ?? latest.assets.first(where: { $0.name.lowercased().hasSuffix(".zip") }).map { ($0, .zip) }
        guard let preferredAsset,
              let assetURL = URL(string: preferredAsset.asset.browserDownloadURL) else {
            throw UpdateError.missingReleaseAsset
        }

        return .available(
            AvailableUpdate(
                version: latestVersion,
                releaseNotes: latest.body,
                assetURL: assetURL,
                assetKind: preferredAsset.kind
            )
        )
    }

    private func installUpdate(_ update: AvailableUpdate) async {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }

        do {
            try await startDetachedUpdater(for: update)
            clearSkippedVersion(matching: update.version.displayString)
            BannerManager.shared.show(
                message: "Updating to \(update.version.displayString). Magent will restart...",
                style: .info,
                duration: nil,
                isDismissible: false
            )

            // Give the background updater process a brief head-start before termination.
            try? await Task.sleep(nanoseconds: 900_000_000)
            NSApp.terminate(nil)
        } catch {
            BannerManager.shared.show(
                message: error.localizedDescription,
                style: .error,
                duration: 6
            )
        }
    }

    private func startDetachedUpdater(for update: AvailableUpdate) async throws {
        let appBundlePath = Bundle.main.bundlePath
        let updaterScriptPath = "/tmp/magent-self-update-\(UUID().uuidString).sh"
        let strategy = await resolveInstallStrategy(appBundlePath: appBundlePath)

        let q = ShellExecutor.shellQuote
        let command: String
        switch strategy {
        case .homebrewCask:
            try writeHomebrewUpdaterScript(at: updaterScriptPath)
            command = """
            /usr/bin/nohup /bin/zsh \(q(updaterScriptPath)) \(q(String(ProcessInfo.processInfo.processIdentifier))) \(q(updaterLogPath)) >/dev/null 2>&1 &
            """
        case .bundleReplacement:
            let installDirectory = URL(fileURLWithPath: appBundlePath).deletingLastPathComponent().path
            guard FileManager.default.isWritableFile(atPath: installDirectory) else {
                throw UpdateError.unwritableInstallLocation(installDirectory)
            }
            try writeBundleReplacementUpdaterScript(at: updaterScriptPath)
            command = """
            /usr/bin/nohup /bin/zsh \(q(updaterScriptPath)) \(q(String(ProcessInfo.processInfo.processIdentifier))) \(q(appBundlePath)) \(q(update.assetURL.absoluteString)) \(q(update.assetKind.rawValue)) \(q(updaterLogPath)) >/dev/null 2>&1 &
            """
        }

        let result = await ShellExecutor.execute(command)
        guard result.exitCode == 0 else {
            let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw UpdateError.failedToStartUpdater(message.isEmpty ? "unknown error" : message)
        }
    }

    private func resolveInstallStrategy(appBundlePath: String) async -> InstallStrategy {
        let normalizedBundlePath = URL(fileURLWithPath: appBundlePath).standardizedFileURL.path
        guard normalizedBundlePath == "/Applications/Magent.app" else {
            return .bundleReplacement
        }

        let result = await ShellExecutor.execute("""
        PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
        command -v brew >/dev/null 2>&1 || exit 1
        brew list --cask magent >/dev/null 2>&1
        """)
        return result.exitCode == 0 ? .homebrewCask : .bundleReplacement
    }

    private func writeBundleReplacementUpdaterScript(at path: String) throws {
        let script = """
        #!/bin/zsh
        set -euo pipefail

        pid="$1"
        target_app="$2"
        asset_url="$3"
        asset_kind="$4"
        log_path="$5"

        exec >>"$log_path" 2>&1

        echo "[magent-updater] started at $(date)"

        tmp_dir="$(/usr/bin/mktemp -d /tmp/magent-update.XXXXXX)"
        mount_dir="$tmp_dir/mount"
        cleanup() {
          if [[ -d "$mount_dir" ]]; then
            /usr/bin/hdiutil detach "$mount_dir" -quiet >/dev/null 2>&1 || true
          fi
          /bin/rm -rf "$tmp_dir"
        }
        trap cleanup EXIT

        archive_path="$tmp_dir/Magent.${asset_kind}"
        /usr/bin/curl --fail --location --silent --show-error "$asset_url" -o "$archive_path"

        case "$asset_kind" in
          dmg)
            /bin/mkdir -p "$mount_dir"
            /usr/bin/hdiutil attach "$archive_path" -nobrowse -readonly -mountpoint "$mount_dir" -quiet
            mounted_app="$(
              /usr/bin/find "$mount_dir" -maxdepth 3 -type d -name "Magent.app" \
              | /usr/bin/head -n 1
            )"
            if [[ -z "$mounted_app" ]]; then
              echo "[magent-updater] Magent.app not found in disk image"
              exit 20
            fi
            new_app="$tmp_dir/Magent.app"
            /usr/bin/ditto "$mounted_app" "$new_app"
            ;;
          zip)
            /bin/mkdir -p "$tmp_dir/unpacked"
            /usr/bin/ditto -x -k "$archive_path" "$tmp_dir/unpacked"
            new_app="$(
              /usr/bin/find "$tmp_dir/unpacked" -maxdepth 3 -type d -name "Magent.app" \
              | /usr/bin/head -n 1
            )"
            ;;
          *)
            echo "[magent-updater] Unsupported update asset type: $asset_kind"
            exit 19
            ;;
        esac

        if [[ -z "$new_app" ]]; then
          echo "[magent-updater] Magent.app not found in archive"
          exit 21
        fi

        while /bin/kill -0 "$pid" 2>/dev/null; do
          /bin/sleep 0.2
        done

        if [[ ! -d "$target_app" ]]; then
          echo "[magent-updater] Target app path does not exist: $target_app"
          exit 22
        fi

        backup_app="${target_app}.magent-backup"
        /bin/rm -rf "$backup_app"

        if ! /bin/mv "$target_app" "$backup_app"; then
          echo "[magent-updater] Failed to move current app to backup"
          exit 30
        fi

        if ! /bin/mv "$new_app" "$target_app"; then
          echo "[magent-updater] Failed to install new app, restoring backup"
          /bin/mv "$backup_app" "$target_app" || true
          exit 31
        fi

        /bin/rm -rf "$backup_app"
        /usr/bin/open "$target_app"
        /bin/rm -f "$0"
        echo "[magent-updater] update completed"
        """

        try script.write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
    }

    private func writeHomebrewUpdaterScript(at path: String) throws {
        let script = """
        #!/bin/zsh
        set -euo pipefail

        pid="$1"
        log_path="$2"
        PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

        exec >>"$log_path" 2>&1

        echo "[magent-updater] homebrew flow started at $(date)"

        while /bin/kill -0 "$pid" 2>/dev/null; do
          /bin/sleep 0.2
        done

        if ! command -v brew >/dev/null 2>&1; then
          echo "[magent-updater] brew not found"
          exit 40
        fi

        if ! brew list --cask magent >/dev/null 2>&1; then
          echo "[magent-updater] magent cask is not installed"
          exit 41
        fi

        if ! brew upgrade --cask magent; then
          echo "[magent-updater] brew upgrade failed, trying reinstall"
          brew reinstall --cask magent
        fi

        /usr/bin/open -a Magent
        /bin/rm -f "$0"
        echo "[magent-updater] homebrew flow completed"
        """

        try script.write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
    }

    private func currentVersionString() -> String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    }

    private func clearSkippedVersion(matching version: String) {
        var settings = persistence.loadSettings()
        guard settings.skippedUpdateVersion == version else { return }
        settings.skippedUpdateVersion = nil
        try? persistence.saveSettings(settings)
        notifyUpdateStateChanged()
    }
}
