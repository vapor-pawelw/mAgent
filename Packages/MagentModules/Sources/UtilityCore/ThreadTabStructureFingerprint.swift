import Foundation
import MagentModels

/// Lightweight snapshot used to detect tab-structure changes coming from outside
/// the active `ThreadDetailViewController` instance (for example CLI tab creation).
///
/// This intentionally ignores transient state (busy, waiting, unread markers) and
/// tracks only tab identity/order/pinning across terminal, web, draft, and chat tabs.
public struct ThreadTabStructureFingerprint: Equatable, Sendable {
    public struct PersistedTab: Equatable, Sendable {
        public let identifier: String
        public let isPinned: Bool

        public init(identifier: String, isPinned: Bool) {
            self.identifier = identifier
            self.isPinned = isPinned
        }
    }

    public let terminalSessionNames: [String]
    public let pinnedTerminalSessions: [String]
    public let webTabs: [PersistedTab]
    public let draftTabs: [PersistedTab]
    public let chatTabs: [PersistedTab]
    public let tabDisplayOrder: [String]

    public init(thread: MagentThread) {
        self.terminalSessionNames = thread.tmuxSessionNames
        self.pinnedTerminalSessions = thread.pinnedTmuxSessions.sorted()
        self.webTabs = thread.persistedWebTabs.map { persisted in
            PersistedTab(identifier: persisted.identifier, isPinned: persisted.isPinned)
        }
        self.draftTabs = thread.persistedDraftTabs.map { persisted in
            PersistedTab(identifier: persisted.identifier, isPinned: persisted.isPinned)
        }
        self.chatTabs = thread.persistedChatTabs.map { persisted in
            PersistedTab(identifier: persisted.identifier, isPinned: persisted.isPinned)
        }
        self.tabDisplayOrder = thread.tabDisplayOrder
    }

    /// Returns whether a fingerprint change is the identity re-key performed by
    /// `renameTab`, rather than a tab being added, removed, reordered, or pinned.
    public static func isTabSessionRename(from previous: MagentThread, to updated: MagentThread) -> Bool {
        let previousFingerprint = Self(thread: previous)
        let updatedFingerprint = Self(thread: updated)

        guard previousFingerprint.webTabs == updatedFingerprint.webTabs,
              previousFingerprint.draftTabs == updatedFingerprint.draftTabs,
              previousFingerprint.chatTabs == updatedFingerprint.chatTabs,
              previous.tmuxSessionNames.count == updated.tmuxSessionNames.count,
              previous.tmuxSessionNames != updated.tmuxSessionNames else {
            return false
        }

        let previousNames = Set(previous.tmuxSessionNames)
        let updatedNames = Set(updated.tmuxSessionNames)
        var renameMap: [String: String] = [:]

        for (oldName, newName) in zip(previous.tmuxSessionNames, updated.tmuxSessionNames) where oldName != newName {
            // Existing names moving between positions are a reorder, not a rename.
            guard !updatedNames.contains(oldName),
                  !previousNames.contains(newName),
                  let previousCreatedAt = previous.sessionCreatedAts[oldName],
                  updated.sessionCreatedAts[newName] == previousCreatedAt,
                  updated.manuallyRenamedTabs.contains(newName),
                  updated.customTabNames[newName] != nil else {
                return false
            }
            renameMap[oldName] = newName
        }

        guard !renameMap.isEmpty else { return false }
        let remappedPins = previous.pinnedTmuxSessions.map { renameMap[$0] ?? $0 }
        return remappedPins == updated.pinnedTmuxSessions
    }
}

public enum TabDisplayOrderResolver {
    /// Restores known identifiers in their saved order, then appends tabs created
    /// after that order was recorded. Stale and duplicate identifiers are ignored.
    public static func resolve(currentIdentifiers: [String], persistedOrder: [String]) -> [String] {
        let currentSet = Set(currentIdentifiers)
        var seen = Set<String>()
        var resolved = persistedOrder.filter { currentSet.contains($0) && seen.insert($0).inserted }
        resolved.append(contentsOf: currentIdentifiers.filter { seen.insert($0).inserted })
        return resolved
    }

    public static func resolve(
        currentPinnedIdentifiers: [String],
        currentUnpinnedIdentifiers: [String],
        persistedOrder: [String]
    ) -> [String] {
        resolve(currentIdentifiers: currentPinnedIdentifiers, persistedOrder: persistedOrder)
            + resolve(currentIdentifiers: currentUnpinnedIdentifiers, persistedOrder: persistedOrder)
    }
}
