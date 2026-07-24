import Foundation
import MagentCore

extension ThreadManager {

    // MARK: - Model Change Detection

    /// Scans agent sessions for Claude's "Set model to …" / Codex's "• Model changed to …"
    /// output and updates tab display names to reflect the current model/effort — skipping
    /// any tab the user has manually renamed.
    ///
    /// Called on the session monitor's 10-tick cadence (~50 s). Not time-critical; a brief
    /// lag between the user switching models and the tab name updating is acceptable.
    func syncTabNamesFromModelChanges() async {
        var changed = false
        var changedThreadIds: Set<UUID> = []

        let threadSnapshot = threads.filter { !$0.isArchived }
        for thread in threadSnapshot {
            for session in thread.agentTmuxSessions {
                let agentType = thread.sessionAgentTypes[session]
                guard agentType == .claude || agentType == .codex else { continue }

                // Skip tabs the user has explicitly renamed — either via the rename dialog
                // after this feature shipped, or populated by the startup migration for tabs
                // that carried a non-default name before this feature existed.
                guard !thread.manuallyRenamedTabs.contains(session) else { continue }

                guard let paneContent = await tmux.cachedCapturePane(sessionName: session, lastLines: 300) else { continue }

                let modelLabel: String
                let effortLevel: String?
                switch agentType {
                case .claude:
                    guard let parsed = parseClaudeModelChange(from: paneContent) else { continue }
                    modelLabel = parsed.modelLabel
                    effortLevel = parsed.effortLevel
                case .codex:
                    guard let parsed = parseCodexModelChange(from: paneContent) else { continue }
                    // Prefer the human label from the manifest so the compact formatter can
                    // cleanly strip the "GPT" vendor prefix. If the id isn't in the manifest
                    // (stale cache, new release), fall back to a spacified raw id so
                    // displayModelLabel still recognises the "gpt" token to strip.
                    if let resolved = resolvedModelLabel(for: .codex, modelId: parsed.modelId) {
                        modelLabel = resolved
                    } else {
                        modelLabel = parsed.modelId.replacingOccurrences(of: "-", with: " ")
                    }
                    effortLevel = parsed.effortLevel
                default:
                    continue
                }

                let newName = TmuxSessionNaming.defaultTabDisplayName(
                    for: agentType,
                    modelLabel: modelLabel,
                    reasoningLevel: effortLevel
                )
                guard let currentThread = store.thread(byId: thread.id),
                      currentThread.agentTmuxSessions.contains(session),
                      currentThread.sessionAgentTypes[session] == agentType,
                      !currentThread.manuallyRenamedTabs.contains(session),
                      currentThread.customTabNames[session] != newName else {
                    continue
                }
                store.update(id: thread.id) {
                    $0.customTabNames[session] = newName
                }
                changed = true
                changedThreadIds.insert(thread.id)
            }
        }

        guard changed else { return }

        try? persistence.saveActiveThreads(threads)
        let updatedThreads = threads
        await MainActor.run {
            delegate?.threadManager(self, didUpdateThreads: updatedThreads)
        }
    }

    // MARK: - Parsing

    /// Extracts the last "Set model to <Model>" or "Set model to <Model> with <effort> effort"
    /// line from `paneContent` and returns the parsed model label and optional effort level.
    ///
    /// Scans the full capture window from the bottom up so the most recent `/model` run
    /// wins even when the user ran `/model` multiple times in the same session. Do NOT
    /// scope to the latest terminal block the way rate-limit detection does: Claude Code's
    /// input box is bordered by full-width `─` rules, so "lines after the last separator"
    /// only ever sees the input box itself and any `Set model to …` line in the conversation
    /// history above is silently dropped.
    ///
    /// Returns nil if no model-change line is found.
    func parseClaudeModelChange(from paneContent: String) -> (modelLabel: String, effortLevel: String?)? {
        AgentChatRuntime.parseClaudeModelChange(from: paneContent)
    }

    /// Extracts the last "• Model changed to <modelId> <effort>" line from `paneContent` and
    /// returns the parsed raw model id plus optional effort level.
    ///
    /// Codex writes this line after a `/model` switch (for example
    /// `• Model changed to gpt-5.3-codex medium`), so the id matches the entries in
    /// `agent-models.json` and can be looked up through `AgentModelsService`.
    ///
    /// Same whole-capture scan as `parseClaudeModelChange` — see that method for why we
    /// deliberately don't scope to the latest block.
    ///
    /// Returns nil if no model-change line is found.
    func parseCodexModelChange(from paneContent: String) -> (modelId: String, effortLevel: String?)? {
        AgentChatRuntime.parseCodexModelChange(from: paneContent)
    }
}
