# Chat Tabs

## User-facing behavior

- Chat tabs render agent messages, user prompts, attachments, model-change markers, and restored tool activity from Claude/Codex transcripts.
- Codex transcript restoration merges agent JSONL with locally-authored UI messages. `PersistedChatMessage.origin == .localUI` marks slash-command replies and model-change notices that must survive reconciliation; legacy system/status/known slash-command messages remain supported.
- User prompts remain right-aligned bubbles, while ordinary assistant replies render unboxed at a wider readable measure. Status messages keep a contained treatment so errors, cancellations, and approval blockers remain distinct.
- The transcript and composer share a centered 920-point maximum reading column. Empty chats offer starter prompts, while a floating jump control reports how many messages arrived when the reader is away from the latest response.
- Assistant Markdown renders headings, ordered and unordered lists, block quotes, separators, fenced code blocks, inline code, bold text, and links instead of exposing their source markers.
- Completed fenced code blocks render as dedicated language-labeled cards with horizontal scrolling and one-click copying. Streaming text stays lightweight until the final block is available.
- In-progress assistant work uses an unboxed inline spinner and elapsed status text instead of an animated placeholder bubble.
- Codex chat status changes from startup to active work as soon as app-server confirms the turn, even when the turn begins with reasoning or tool calls instead of assistant text.
- Message timestamps and sent model/reasoning metadata stay out of the transcript and appear in a borderless, high-contrast action row with a copy action when hovering a message.
- Right-clicking a message offers copy and can generate a concise tab name from that message, even when automatic tab naming is disabled. Message-based names are treated as manual names, so later model changes and automatic naming do not overwrite them.
- The composer uses the same rounded prompt surface styling as new thread and new tab sheets: a multiline text area above an integrated footer containing attachment, model, reasoning, and send controls.
- The composer shows an input hint, disables empty submissions, distinguishes normal sending from Codex steering, and exposes working, queued-prompt, and Stop states without relying on terminal shortcuts.
- Collapsed Agent activity summaries show both action count and elapsed duration; expanded steps use a subtle timeline rail and human-readable labels instead of provider tool names.
- Codex chat tabs show app-server activity as it happens, including parallel-agent lifecycle updates and any command, file-change, MCP, or dynamic-tool items emitted for related subagent threads.
- Chat color settings include a live preview of user, ordinary assistant, and status treatments, plus WCAG-style contrast warnings for each configured foreground/background pair.
- Codex chat tabs expose the `None` reasoning effort from the bottom-left picker and store/pass it as Codex `reasoningLevel: "none"`.
- Codex chat tab titles mirror terminal tab naming from the selected model and reasoning effort, with ` (Chat)` appended. On the first submitted prompt, the regular automatic tab-naming setting can replace that default with a concise task name. Automatic updates preserve manually renamed chat tabs.
- Long transcripts retain a bounded 160-message view window. Use Earlier/Newer to navigate older pages without keeping every AppKit message hierarchy alive.
- Chat tabs keep their chosen position relative to terminal, web, and draft tabs when switching threads or renaming a tab.
- Closing and restoring a chat tab preserves its pinned state, and closing a background chat does not move the active selection.
- Tool activity should read like concise actions first: `Run command`, `Read file`, `Search`, or `Tool output`.
- Patch edits should read as `Apply patch` / `Patch applied` and summarize changed files instead of rendering the raw patch inline. Expanded filenames are links that open the thread's existing Diff tab focused on that file.
- Consecutive routine tool rows are compacted in the visible chat transcript into one collapsed assistant-side activity disclosure. Its header and expanded rows use tinted SF Symbols, while the saved transcript remains unmodified for export, restore, and agent handoff.
- Successful tool output stays collapsed by default so long transcripts remain scannable.
- Failed tool output and still-running command output expand by default because those states usually need immediate attention.
- Tool details keep the raw command, arguments, output, and status available behind disclosure.
- Every tool disclosure uses the same stable readable measure in collapsed and expanded states. Header details stay on one truncated headline so narrow intrinsic button measurements cannot collapse the disclosure into a character-wide column.
- Completed command headers describe the command action, never the first output line. Transport-only arguments such as yield time, output-token limits, TTY, and login-shell flags are omitted from display.

## Implementation Notes

- `PersistedChatMessage.toolEvent` is the optional first-class storage for structured tool activity. Keep it optional so older chat history that only has transcript text remains readable.
- `ChatToolTranscriptFormatter.event(for:)` normalizes persisted tool transcript text into `ChatTranscriptEvent.tool(ChatToolTranscriptEvent)` before presentation.
- `ChatToolTranscriptFormatter.presentation(for:)` is the presentation adapter from structured tool events to the disclosure UI copy/body.
- Patch file summaries use `magent-diff://file?path=...` links. `ChatMarkdownLinkResolver` maps those to `.diffFile`, and `ThreadDetailViewController` posts a thread-scoped `magentShowDiffViewer` notification so main and pop-out windows route the focused diff correctly.
- `ChatMessageDisplayPlanner.plan(for:)` is the UI-facing classification boundary. It turns persisted messages into ordinary message, tool, or status display plans.
- `ChatMarkdownBlockParser` handles block structure before `ChatMarkdownTokenizer` adds inline emphasis and links. Keep block syntax out of the AppKit layout code so parsing behavior remains independently testable.
- `ChatMessageBubbleView` splits finalized ordinary Markdown around fenced code blocks, preserving source order while using `ChatCodeBlockView` for copyable, independently scrollable code. A streamed message containing code must trigger an authoritative bubble rebuild when it becomes final.
- `ChatContentLayoutPolicy`, `ChatComposerPresentation`, and `ChatColorContrastPolicy` keep width, action-state, and accessibility decisions independently testable outside AppKit.
- The transcript and composer rail width constraints are updated from the chat view's current bounds in `viewWillLayout`. They must describe available space, not advertise the 920-point cap as a preferred intrinsic width to the enclosing split view. Keep those constants above default compression resistance but below required priority, so the intended rail wins ordinary content ties while the document or root-stack upper bounds still win when AppKit reserves a few points for scrolling chrome.
- `ChatToolDisclosureLayoutPolicy` gives all tool disclosures a stable available width; ordinary messages may still size to their content up to the readable maximum.
- `ChatTranscriptDisplayCompactor.compactedMessages(_:)` is display-only. It summarizes consecutive routine tool messages before rendering and exposes activity summaries through `ChatMessageDisplayPlanner` as collapsed disclosure rows; it must not compact statuses or tool presentations that expand by default, and must not be used for persistence, export, or resume context.
- `ChatMessageBubbleView` consumes `ChatMessageDisplayPlanner` output, renders ordinary assistant and tool plans without a bubble background, keeps user/status messages contained, renders tool plans as SF Symbol disclosure rows, and hides tool detail bodies while collapsed.
- Codex app-server deltas are coalesced to roughly 15 UI deliveries per second. Existing assistant bubbles append the delivered delta directly, re-style only a bounded Markdown tail, and perform one authoritative full render on completion.
- `CodexAppServerLiveItemUpdate` normalizes live app-server tool items into the same structured `PersistedChatToolEvent` representation used by restored transcripts. A `collabAgentToolCall` records its receiver thread IDs so later tool items from those subagent threads can be routed into the parent chat while subagent assistant messages remain excluded.
- Successful Codex turns keep a bounded pool of app-server processes warm by conversation ID, avoiding repeated MCP startup before later prompts. Reuse requires the same worktree, developer instructions, and permission mode; incomplete or failed turns are never pooled.
- Every Codex app-server turn explicitly reapplies the current Agent Permissions mode. Full Access and Sandbox Auto use `approvalPolicy: "never"` because chat tabs cannot answer app-server approval requests; Sandbox Auto still confines tools with the workspace-write sandbox. Ask mode leaves Codex's approval policy intact and surfaces an approval blocker instead of replaying the prompt.
- Codex app-server image attachments use the camel-cased `localImage` input variant. The snake-cased `local_image` spelling belongs to older event/transcript shapes and is not accepted by `turn/start`.
- `ChatTranscriptRenderWindow` bounds compaction, diffing, text systems, and constraints to one navigable page. Streaming updates for an older, offscreen page update model state without rebuilding that page.
- Draft edits are staged in memory immediately, while disk writes use a trailing debounce. Active streams use one periodic checkpoint task so uninterrupted output remains recoverable without allocating a persistence task per delta.
- `ChatFinalAssistantMessageReconciler` attaches `toolEvent` when final assistant text is itself a tool transcript, so live completions and restored transcripts follow the same presentation path.
- `CodexChatTranscriptReconciler` and `ClaudeChatTranscriptReconciler` pair matching tool calls/results into one persisted message when transcript IDs are available, falling back to standalone output messages when a pair cannot be found.
  Restored tool messages should carry both backward-compatible transcript text and `toolEvent`.
- Transcript reconciliation matches repeated text by occurrence, not by a single text dictionary entry. Each legitimate repeated prompt/reply must retain its own UUID, timestamp, attachments, and model metadata.
- Codex `/effort none` selects the `none` reasoning effort.
- `MagentThread.tabDisplayOrder` preserves the unified movable-tab order across tab types. Restoration reconciles it against the current tab set separately within pinned and unpinned groups, so stale identifiers are ignored and newly created tabs append safely.
- IPC tab indexes resolve through the same pinned/unpinned `tabDisplayOrder` groups as the GUI, so drag reordering remains authoritative for `list-tabs`, `read-tab`, `send-prompt`, and `close-tab`.
- `ChatPromptCoordinator` is the shared GUI/IPC reservation boundary for chat turns. Steering is accepted only from the client that owns the active turn; the other client receives a busy result instead of launching a concurrent request against stale history.
- A model/reasoning fallback selected while materializing a legacy chat tab is propagated back to persisted parent state before the next request.

## Gotchas

- Claude Code chat implementation remains in the codebase for possible future development, but the surface is intentionally excluded from `AgentType.capabilities` and must not be offered even by the debug chat feature flag until it is ready.

- Keep provider-specific transcript parsing out of the view layer. Normalize provider logs in the reconciler/runtime layer, then render via shared chat message presentation.
- Keep raw persisted transcript text as the compatibility boundary even when `toolEvent` is present. Existing IPC/read-tab flows and older app versions still rely on readable text.
- New UI code should consume `ChatMessageDisplayPlanner` or `toolEvent`/`ChatTranscriptEvent` rather than reparsing display strings in view code.
- Do not expand successful tool output by default. Long command logs quickly bury the conversation and make restored sessions hard to scan.
- Do not surface successful exit-code metadata (`Exit code: 0`, `Process exited with code 0`) in titles or details; keep it as parsed metadata only.
- Do not promote command output into completed tool titles or show transport controls such as `yield_time_ms` and `max_output_tokens`. Failures and running commands may still show concise state metadata and expand automatically.
- `Continue in...` must offer every enabled terminal agent, including the chat's current provider, and initially select the project/global default agent.
- `Continue in...` must route the exported context to the selected surface. Terminal targets use tmux prompt injection; supported chat targets use `openChatTab`.
- Keep failed and running tools, errors, cancellations, and approval blockers outside compact Activity summaries so attention-required information remains immediately visible.
- Do not let display compaction change persisted chat messages. The compact activity row is only a view-layer artifact.
- Resolve all activity-summary icon insertion offsets against the immutable rendered text, then apply insertions from the end. Forward mutation invalidates later attributed-string ranges and can crash while restoring a chat tab.
- Do not drop raw details from persisted tool messages; users still need to inspect exact commands, arguments, and output when debugging agent behavior.
- Hidden disclosure bodies must not participate in width measurement. Tool rows take the available readable width directly, capped by the transcript measure and current view width.
- Do not restore preferred equal-width rail constraints against the document or root stack. During lazy chat materialization, AppKit can propagate that fitting-width request through the split view and resize the window.
- Keep hover actions in their reserved row so showing them never reflows message text, and keep raw Markdown as the copied message payload.
- Resolve theme-preview layer colors and their derived alpha variants inside `performAsCurrentDrawingAppearance`; otherwise a preview created in one appearance can retain stale light/dark CGColors.
- Warm app-server readers must switch to an idle drainer between turns. Handler swaps must quiesce the previous reader, and a new active lease must discard any partial idle notification before parsing the next turn. Per-turn handlers must never remain attached while a process is available for reuse.
- Treat fallback to `codex exec --json` as prompt replay. It is allowed only when app-server failed before `turn/start`; approval blockers, failed/completed turns, and no-response outcomes may already have produced side effects and must be returned without replay.
- Keep Codex app-server request variants distinct from transcript field names: requests use `localImage`, while restored Codex JSONL can still expose `local_images`.
- `AgentChatSteerChannel` owns unacknowledged steering inputs until app-server acknowledges them. Rejected, completion-raced, or fallback-time inputs are returned as deferred work and queued as the next turn. Closing a chat or `/clear` uses destructive cancellation and discards both queued and unacknowledged inputs before cancelling the active task.
- Tab-structure restoration must retain in-flight `ChatTabEntry` instances. Replacing them from a lagging persistence snapshot can cancel a request the user did not stop and leave a newly materialized view showing stale elapsed work.
- A terminal-session rename must re-key its `terminal:<session>` entry in `tabDisplayOrder` together with the other session-keyed state, or restoration treats the renamed tab as new and appends it.
