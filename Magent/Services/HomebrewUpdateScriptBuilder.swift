import MagentCore

enum HomebrewUpgradeFallbackDecision {
    static func shouldReinstall(installedVersion: String?, targetVersion: String) -> Bool {
        installedVersion != targetVersion
    }
}

struct HomebrewUpdateScriptMessages: Sendable {
    let waiting: String
    let refresh: String
    let upgrade: String
    let cleanup: String
    let relaunch: String
}

enum HomebrewUpdateScriptBuilder {
    static func script(
        shouldRefreshTap: Bool,
        targetVersion: String,
        messages: HomebrewUpdateScriptMessages
    ) -> String {
        let q = ShellExecutor.shellQuote
        let shouldRefreshTapValue = shouldRefreshTap ? "1" : "0"
        return """
        #!/bin/zsh
        set -euo pipefail

        pid="$1"
        log_path="$2"
        status_path="$3"
        PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        should_refresh_tap="\(shouldRefreshTapValue)"
        target_version=\(q(targetVersion))

        exec >>"$log_path" 2>&1

        echo "[magent-updater] homebrew flow started at $(date)"

        update_status() {
          phase="$1"
          message="$2"
          printf "%s\\t%s\\t%s\\n" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$phase" "$message" > "$status_path"
          /usr/bin/osascript \\
            -e 'on run argv' \\
            -e 'display notification (item 1 of argv) with title "Magent Update"' \\
            -e 'end run' \\
            "$message" >/dev/null 2>&1 || true
          echo "[magent-updater] $phase: $message"
        }

        installed_magent_version() {
          brew list --cask --versions magent 2>/dev/null | awk '{print $2; exit}'
        }

        update_status "waiting" \(q(messages.waiting))
        while /bin/kill -0 "$pid" 2>/dev/null; do
          /bin/sleep 0.1
        done

        if ! command -v brew >/dev/null 2>&1; then
          echo "[magent-updater] brew not found"
          exit 40
        fi

        if ! brew list --cask magent >/dev/null 2>&1; then
          echo "[magent-updater] magent cask is not installed"
          exit 41
        fi

        if [[ "$should_refresh_tap" == "1" ]]; then
          # Refresh the tap so `brew upgrade` sees the newest cask version.
          # The in-app prefetch normally did this moments ago, so skip it for
          # the common path to keep the relaunch gap short.
          update_status "refreshing-tap" \(q(messages.refresh))
          if ! brew update --quiet; then
            echo "[magent-updater] brew update failed (continuing anyway)"
          fi
        fi

        update_status "upgrading" \(q(messages.upgrade))
        if ! brew upgrade --cask magent; then
          installed_version="$(installed_magent_version)"
          if [[ "$installed_version" == "$target_version" ]]; then
            echo "[magent-updater] target version $target_version is already installed; skipping reinstall"
          else
            echo "[magent-updater] brew upgrade failed and installed version is '${installed_version:-unknown}', expected $target_version; trying reinstall"
            brew reinstall --cask magent
          fi
        fi

        update_status "cleaning" \(q(messages.cleanup))
        if [[ -d "/Applications/Magent.app" ]]; then
          /usr/bin/xattr -dr com.apple.quarantine "/Applications/Magent.app" >/dev/null 2>&1 || true
          /usr/bin/xattr -dr com.apple.provenance "/Applications/Magent.app" >/dev/null 2>&1 || true
        fi

        update_status "relaunching" \(q(messages.relaunch))
        /usr/bin/open -a Magent
        /bin/rm -f "$0"
        echo "[magent-updater] homebrew flow completed"
        """
    }
}
