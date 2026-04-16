import Cocoa
import MagentCore

/// Orchestrates when the "What's New" sheet appears.
///
/// - Launch-time auto-present: `showIfNeededOnLaunch()` shows the current
///   entry iff the user has not already dismissed that version's popup.
/// - Menu-triggered re-show: `showCurrent()` opens the sheet on demand from
///   the `mAgent → What's New…` menu item, bypassing the "already seen"
///   check. Dismissing still persists the version as seen (idempotent).
///
/// The "seen" marker is `AppSettings.lastSeenWhatsNewVersion`. A dismissal
/// stores the current entry's version string; subsequent launches compare
/// stored version < entry version using `SemanticVersion`.
@MainActor
final class WhatsNewService {
    static let shared = WhatsNewService()

    private var isPresenting = false

    private init() {}

    /// Whether a popup is available to re-show via the menu item.
    var hasEntryToShow: Bool {
        WhatsNewContent.current != nil
    }

    /// Called once from `applicationDidFinishLaunching` after the main window
    /// is on screen. No-op when there is no entry, or when the user has
    /// already seen this version's popup.
    func showIfNeededOnLaunch(over parentWindow: NSWindow?) {
        guard let entry = WhatsNewContent.current else { return }
        guard let parentWindow else { return }

        let settings = PersistenceService.shared.loadSettings()
        if !shouldAutoShow(entry: entry, lastSeen: settings.lastSeenWhatsNewVersion) {
            return
        }
        present(entry: entry, over: parentWindow)
    }

    /// Always shows the current entry regardless of whether the user has seen
    /// it before. Used by the `mAgent → What's New…` menu item.
    func showCurrent(over parentWindow: NSWindow?) {
        guard let entry = WhatsNewContent.current, let parentWindow else {
            NSSound.beep()
            return
        }
        present(entry: entry, over: parentWindow)
    }

    // MARK: - Internals

    private func present(entry: WhatsNewEntry, over parentWindow: NSWindow) {
        if isPresenting { return }
        isPresenting = true
        WhatsNewSheetController.present(entry: entry, over: parentWindow) { [weak self] in
            self?.handleDismissal(of: entry)
        }
    }

    private func handleDismissal(of entry: WhatsNewEntry) {
        isPresenting = false
        persistAsSeen(entry: entry)
    }

    private func persistAsSeen(entry: WhatsNewEntry) {
        var settings = PersistenceService.shared.loadSettings()
        if settings.lastSeenWhatsNewVersion == entry.version { return }
        settings.lastSeenWhatsNewVersion = entry.version
        do {
            try PersistenceService.shared.saveSettings(settings)
        } catch {
            NSLog("[WhatsNewService] Failed to persist lastSeenWhatsNewVersion: %@", String(describing: error))
        }
    }

    private func shouldAutoShow(entry: WhatsNewEntry, lastSeen: String?) -> Bool {
        guard let entryVersion = entry.semanticVersion else {
            // Malformed entry version — fail closed so we don't spam the user.
            return false
        }
        guard let lastSeenRaw = lastSeen else {
            // Fresh install or upgrade from a pre-What's-New build — show the
            // current entry once.
            return true
        }
        guard let lastSeenVersion = SemanticVersion(lastSeenRaw) else {
            // Stored value can't be parsed; treat as never seen so the user
            // still gets the popup once.
            return true
        }
        return lastSeenVersion < entryVersion
    }
}
