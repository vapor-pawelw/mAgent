# Model & Reasoning Picker

Per-agent model and reasoning level selection when starting new threads or tabs.

## Overview

Users can pick a model and reasoning level from the agent launch sheet before starting a new thread or tab. Each agent type (Claude, Codex) maintains its own last-selected model, and reasoning is remembered per model (not per agent type). Codex also remembers the launch-sheet Fast mode toggle per agent. Selections persist across sessions and are reused by fast-path creation (Option+click, context menu).

## Data Source: `agent-models.json`

A JSON file defines available models and reasoning levels per agent. The file lives in two places:

- **Bundled resource** — `config/agent-models.json` in the app bundle (compiled from repo). Serves as the hardcoded fallback.
- **Remote** — `https://raw.githubusercontent.com/vapor-pawelw/mAgent/main/config/agent-models.json`. Fetched on app launch and cached locally in Application Support.
- **Local cache** — `~/Library/Application Support/Magent/agent-models.json`. Updated from remote; read at runtime. Falls back to bundled resource if missing or corrupt.

### JSON Structure

```json
{
  "version": 1,
  "agents": {
    "claude": {
      "models": [
        { "id": "fable", "label": "Fable" },
        { "id": "opus", "label": "Opus" },
        { "id": "sonnet", "label": "Sonnet" },
        { "id": "haiku", "label": "Haiku" }
      ],
      "reasoningLevels": ["low", "medium", "high", "max"]
    },
    "codex": {
      "models": [
        { "id": "gpt-5.6-sol", "label": "GPT 5.6 Sol", "reasoningLevels": ["none", "low", "medium", "high", "xhigh", "max"] },
        { "id": "gpt-5.6-terra", "label": "GPT 5.6 Terra", "reasoningLevels": ["none", "low", "medium", "high", "xhigh", "max"] },
        { "id": "gpt-5.6-luna", "label": "GPT 5.6 Luna", "reasoningLevels": ["none", "low", "medium", "high", "xhigh", "max"] },
        { "id": "gpt-5.5", "label": "GPT 5.5" },
        { "id": "gpt-5.4", "label": "GPT 5.4" },
        { "id": "gpt-5.4-mini", "label": "GPT 5.4 Mini" },
        { "id": "gpt-5.3-codex", "label": "GPT 5.3 Codex" }
      ],
      "reasoningLevels": ["low", "medium", "high", "xhigh"]
    }
  }
}
```

- **Agent-level `reasoningLevels`** — default reasoning options for all models under that agent.
- **Per-model `reasoningLevels` override** — optional. When present on a model object, replaces the agent-level list for that model. GPT 5.6 Codex models use this to expose `none` and `max` while older Codex models keep the default `low`/`medium`/`high`/`xhigh` set. Example:
  ```json
  { "id": "gpt-5.1-codex-mini", "label": "GPT 5.1 Codex Mini", "reasoningLevels": ["medium", "high"] }
  ```

### Remote Fetch Strategy

- **On app launch**: fetch remote JSON, update local cache if newer.
- **When showing launch sheet**: re-fetch if >10 minutes since last fetch.
- **On fetch failure**: silently use local cache (or bundled fallback if no cache).
- **`version` field**: reserved for future schema migrations. Current version: 1.

## Persistence: Per-Model Last Selection

Each agent independently remembers its last-selected model. Reasoning level is remembered **per model** (not just per agent), so switching between e.g. Opus and Sonnet restores each model's own last-used reasoning level.

When no previous Codex model/reasoning selection exists, Magent defaults Codex launches to `gpt-5.6-sol` with `low` reasoning. Saved user selections still take precedence after the first explicit picker or slash-command change.

Storage keys in `agent-last-selections.json`:
- `model:<agent>` — e.g. `model:claude` → `"fable"`
- `reasoning:<agent>:<model>` — e.g. `reasoning:claude:fable` → `"high"`
- `reasoning:<agent>` — fallback key when model is `nil` (Auto)
- `fastMode:codex` — `"true"` when the Codex Fast mode lightning toggle is filled, `"false"` when unfilled

Stored in `AgentLastSelectionStore`. **Not stored per-thread** for normal live sessions — model/reasoning/Fast mode are only used at fresh-start time, and resume inherits from the agent session itself.

Draft tabs are the exception: if the user checks `Draft` in the launch sheet, the selected model and reasoning are persisted alongside the saved prompt so `Start Agent` later launches with the same explicit configuration. Missing values remain `nil` and mean `Auto`, which keeps older persisted drafts backward-compatible.

The `Draft` checkbox state itself is also persisted with the saved launch-sheet draft, so reopening the sheet restores whether that prompt was meant to stay parked or launch immediately. The checkbox updates live while editing the sheet, which keeps the saved draft state aligned with what the user sees.

### Switching Agent or Model in Picker

Switching between Claude and Codex in the agent picker swaps the displayed model/reasoning to that agent's own last-selected values. **No cross-agent mapping** — each agent's selections are fully independent.

Switching models within the same agent restores that model's own last-used reasoning level. For example, if you set Claude Opus to "High" and Sonnet to "Low", switching between models in the picker restores each one's setting.

### Stale Selection Recovery

If the user's last-selected model no longer exists in the current JSON (after a remote update), silently fall back to "Auto."

When a new thread or agent tab is created without an explicit custom title, Magent keeps the default title focused on the agent name and appends a single suffix for any visible model label plus reasoning. Built-in reasoning labels are abbreviated to `L`, `M`, `H`, `xH`, and `Max`; any other value is left as-is.

## Auto-Sync Tab Name from `/model` Output

When a user runs `/model` inside Claude Code or Codex to switch models or effort, the terminal outputs a line like:

```
  ⎿  Set model to Opus 4.6
  ⎿  Set model to Sonnet 4.6 with high effort
  • Model changed to gpt-5.3-codex medium
  • Model changed to gpt-5.4-mini low
```

`ThreadManager+ModelDetection.swift` scans for these patterns on the session monitor's 10-tick cadence (~50 s) and updates the tab display name to match (e.g. `"Claude"` → `"Claude (Sonnet 4.6, H)"`, `"Codex"` → `"Codex (5.3-codex, M)"`), reusing `TmuxSessionNaming.defaultTabDisplayName(for:modelLabel:reasoningLevel:)`. For Codex, the parsed raw model id (e.g. `gpt-5.3-codex`) is resolved against `AgentModelsService` so the manifest label (`GPT 5.3 Codex`) feeds the compact formatter, which strips the `GPT` vendor prefix and hyphenates the remaining tokens. When the id isn't in the manifest, the raw id is spacified (`gpt 5.3 codex`) so the same stripping still applies.

Parsing scans the **entire capture window** (300 lines of scrollback + visible pane) from the bottom up. It deliberately does **not** scope to the latest block after the last horizontal separator the way rate-limit detection does: Claude Code renders a full-width `─` rule above and below its input box, so any "lines after the last separator" heuristic only ever sees the input box itself and drops every `Set model to …` line in the conversation history. Picking the last match from the full capture is correct because it reflects the most recent `/model` run, even if the user ran `/model` multiple times in the same session.

### Guard: `manuallyRenamedTabs`

`MagentThread` carries a persisted `manuallyRenamedTabs: Set<String>` field. Despite the legacy name, it is the protection set for tab labels that automatic model-name sync must not overwrite. The set is populated in three ways:

1. **On rename** — `renameTab()` inserts the session (both the display-name-only path and the full tmux rename path).
2. **Startup migration** — on first launch after this field was introduced, `ThreadManager` iterates all threads and inserts any session whose stored `customTabNames` entry doesn't match `TmuxSessionNaming.looksLikeDefaultTabName(_:for:)`. This protects tabs that were manually named before the feature shipped, with no separate migration flag needed (the set itself is idempotent once persisted).
3. **Prompt-based automatic naming** — a successfully generated task label inserts the session so later model/effort detection does not replace the more descriptive name.

The set is re-keyed on session rename and cleaned up on tab close, consistent with other per-session sets.

The default-on `autoRenameTabs` setting uses the first submitted prompt for each agent session to generate a 1-3 word display name. It writes only `customTabNames`, leaving the tmux session name unchanged so prompt injection and other session-keyed state are not disrupted. Only the first prompt-history transition from empty to non-empty can launch generation, so failures do not retry on every later prompt. The setting is checked before the background AI command and again before applying its result. Both state checks skip sessions in `manuallyRenamedTabs`, so a manual rename made while generation is in flight still wins.

## UI: Launch Sheet

Type, Model, and Reasoning pickers share a **single row** in `AgentLaunchPromptSheetController`:

```
Type [picker]  Model [picker]  Reasoning [picker]  [bolt]
```

The launch sheet uses a wider default content width so the three pickers have enough room to stay readable on one line without crowding the prompt field below.

- **Type picker**: built from `AgentType.capabilities` in `Packages/MagentModules/Sources/MagentModels/AgentType.swift` (single source of truth for agent/surface support). Agents with multiple surfaces render as separate rows (for example `Claude (Terminal)`, `Claude (Chat)`).
- **Model picker**: "Auto" + models from JSON for the selected agent.
- **Reasoning picker**: "Auto" + reasoning levels. Items update when:
  - Agent changes (load that agent's reasoning levels).
  - Model changes, if the selected model has a per-model `reasoningLevels` override.
- **Codex Fast mode button**: a lightning icon shown only when Codex is selected. Filled means launch fresh Codex terminal sessions with the Fast service tier; unfilled means no Fast override is passed. The button has a tooltip and saves immediately so fast-path creation reuses it.

Model and Reasoning pickers are **hidden** (individually, not the whole row) when agent is `.custom` or Terminal or Web. The Fast mode button is hidden for every non-Codex selection.

"Auto" means no flags are passed — the agent uses its own configured default.

### Chat Surface Runtime Gate

- Chat surfaces are selectable directly for supported agents (currently Claude and Codex).
- New-thread creation can start directly on a chat tab from the launch sheet or IPC/CLI by selecting the chat surface (`claude:chat` / `codex:chat` in CLI payloads). Chat-first thread creation must persist the typed prompt as the chat draft and skip fallback tmux session creation when the thread contains only non-terminal tabs.
- No separate Pi runtime install gate is used in the launch sheet.
- Chat message execution uses each agent's native non-interactive JSON stream path:
  - Claude: `claude -p --output-format stream-json` (resume via `--resume <session_id>`)
  - Codex: `codex app-server --listen stdio://` JSON-RPC stream (fallback: `codex exec --json`; resume fallback path: `codex exec resume <thread_id> --json`)
- Each chat tab persists the latest agent conversation/session id so subsequent messages continue in the same native agent context.
- Chat composer input must use a normal `NSTextView` initializer so AppKit creates the backing text system. Do not initialize the composer with `textContainer: nil`; that leaves the view editable but without text storage, which prevents normal typing.
- Chat attachment drops are accepted both on the composer and on the main chat surface. Composer drops may show the dashed "Drop files here" overlay, but main-surface drops intentionally reuse the same attachment ingestion path without extra visual chrome.
- Long chat histories must not be materialized as one synchronous AppKit layout pass when a tab is first selected. `ChatTabViewController.reloadMessages` progressively renders large full reloads in batches and cancels stale batches via `messageRenderGeneration` when a newer update arrives.
- Streaming chat updates should preserve user scroll intent: auto-scroll only when the chat was already near the bottom before the update, and coalesce post-layout scroll/button work instead of calling `scrollToBottom` for every delta.
- While a chat request is running, keep the pending assistant loading/working placeholder alive even after early streamed commentary or tool messages arrive. Completion cleanup removes it only when the request token finishes.
- Final response reconciliation must preserve separately streamed assistant items. Codex app-server completion can return aggregate turn text; do not replace the first streamed item with that aggregate, or final answers appear on earlier commentary/tool bubbles.
- Tool-call/tool-output transcript bubbles are collapsed by default. Collapsed tool calls should make the command the primary text, while collapsed tool outputs should summarize useful output content first and hide routine success metadata such as exit `0`, token count, chunk id, or wall time. Restored transcript reconciliation should pair a tool call with its matching result when the runtime exposes a call id, rendering one expanded result bubble with arguments and output instead of adjacent call/output bubbles. Expanded output may show unusual status metadata at the bottom.

### Chat Model-Change Notices

- Each persisted chat user message stores the model ID and reasoning level used for that turn.
- Before appending a newly sent user message from either the GUI composer or IPC `sendPrompt` chat path, compare its selected model/reasoning against the previous user message in that chat. If either value changed, insert a `system` chat message immediately before the new user message with the text `Model changed to <model name> (<reasoning>)`.
- Persist the inserted `system` message in the chat tab just like user and assistant messages so it survives tab switches, app relaunches, and transcript reconciliation.
- Render system chat messages as full-width separator rows with centered, timestamp-hidden metadata text and 8 pt spacing between the label and separator lines, so they read like session metadata without being confused for user or assistant content.
- Do not insert a marker before the first user message, and do not insert duplicates when the metadata is unchanged.

### Chat Slash Commands (GUI Chat Tabs)

- Chat-tab slash commands are app-handled convenience commands, not a passthrough of each agent's full interactive TUI slash surface.
- Codex chat autocomplete intentionally exposes only commands supported in this GUI surface: `/help`, `/clear`, `/model`, `/effort`.
- `/model` and `/effort` update persisted per-tab chat selections and next request flags; `/clear` resets visible messages and conversation resume id.
- Unsupported Codex slash commands should not be surfaced in chat autocomplete because Magent chat does not mirror the full interactive terminal slash-command surface.

### Model/Reasoning Source of Truth (Reliability)

- In chat tabs, the authoritative current model/reasoning is Magent's tab state (picker + slash-command updates), because requests are launched with explicit flags per turn.
- Output-based detection (`Set model to ...`, `Model changed to ...`) remains best-effort sync only; it is useful for convergence but should not be treated as a guaranteed session-introspection API.
- Terminal sessions still rely on output/process heuristics for passive detection and display updates.

### Fast Path (Option+click / Context Menu)

Uses last-selected model + reasoning + Codex Fast mode for the relevant agent. No sheet shown. Equivalent to accepting the sheet with last-used values.

The right-click context menu on the "+" (new tab) button and the sidebar "New Thread" submenu list agent types directly — the default agent appears first with a "(Default)" suffix. Each agent's menu item shows its last-used model and reasoning verbatim in a verbose form (e.g., `Claude (Sonnet, high) (Default)`, `Codex (GPT 5.3 Codex, xhigh)`, `Claude` when both are Auto). Any part set to Auto is omitted individually. This is intentionally different from the compact tab-name formatter in `TmuxSessionNaming.defaultTabDisplayName(for:modelLabel:reasoningLevel:)` — the compact form strips the `GPT` vendor prefix for Codex (so `GPT 5.3 Codex` becomes `5.3-codex`, `GPT 5.4 Mini` becomes `5.4-mini`) and abbreviates reasoning to single letters, producing tab titles like `Codex (5.3-codex, M)` or `Claude (Opus, H)`. The verbose form is built inline in `AgentMenuBuilder.populate` and must not be replaced with the compact helper.

### Draft Tabs

Draft tabs reuse the same picker semantics as the launch sheet:

- The draft editor shows `Model` and `Reasoning` pickers with the same `Auto` behavior.
- Changing the agent swaps the visible model/reasoning choices to that agent's own remembered values.
- Starting the draft later passes the persisted explicit selections into normal agent-tab creation, so the launched session matches the draft sheet state instead of re-reading the current global last-used values.

## Command Building

Flags are appended in `freshAgentCommand` only when the selection is not "Auto":

### Claude

```
claude --model <id> --effort <level>
```

- `--model` omitted when "Auto"
- `--effort` omitted when "Auto"

### Codex

```
codex -m <id> -c model_reasoning_effort=<level>
```

- `-m` omitted when "Auto"
- `-c model_reasoning_effort=...` omitted when "Auto"
- `-c service_tier="fast"` appended when the Codex Fast mode lightning toggle is filled

### Resume

No model/reasoning/Fast mode flags passed on resume. The agent session retains its own state.

### Custom Agent

Model and reasoning pickers are hidden. No flags appended. Custom agents manage their own configuration via `customAgentCommand`.

## New Types (MagentModels)

```swift
/// Decoded from agent-models.json
struct AgentModelsManifest: Codable {
    let version: Int
    let agents: [String: AgentModelConfig]
}

struct AgentModelConfig: Codable {
    let models: [AgentModel]
    let reasoningLevels: [String]
}

struct AgentModel: Codable {
    let id: String
    let label: String
    let reasoningLevels: [String]?  // overrides agent-level when present
}
```

## File Locations

| Concern | Path |
|---------|------|
| Source JSON (repo) | `config/agent-models.json` |
| Bundled resource | Embedded in app bundle via Tuist resource |
| Local cache | `~/Library/Application Support/Magent/agent-models.json` |
| Remote URL | `https://raw.githubusercontent.com/vapor-pawelw/mAgent/main/config/agent-models.json` |
| Persistence (last selection) | `AgentLastSelectionStore` (existing pattern) |
| Launch sheet UI | `AgentLaunchPromptSheetController` |
| Command building | `ThreadManager+Helpers.swift` (`freshAgentCommand`) |
