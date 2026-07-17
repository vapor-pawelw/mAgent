# Chat Tabs

## User-facing behavior

- Chat tabs render agent messages, user prompts, attachments, model-change markers, and restored tool activity from Claude/Codex transcripts.
- User prompts remain right-aligned bubbles, while ordinary assistant replies render unboxed at a wider readable measure. Status messages keep a contained treatment so errors, cancellations, and approval blockers remain distinct.
- In-progress assistant work uses an unboxed inline spinner and elapsed status text instead of an animated placeholder bubble.
- Message timestamps and sent model/reasoning metadata stay out of the transcript and remain available from the message hover tooltip.
- The composer uses one adaptive rounded surface: a multiline text area above an integrated footer containing attachment, model, reasoning, and send controls.
- Codex chat tabs expose fast mode from the bottom-left reasoning picker as `⚡ Fast`; it is stored and passed as Codex `reasoningLevel: "none"`.
- Tool activity should read like concise actions first: `Run command`, `Read file`, `Search`, or `Tool output`.
- Patch edits should read as `Apply patch` / `Patch applied` and summarize changed files instead of rendering the raw patch inline. Expanded filenames are links that open the thread's existing Diff tab focused on that file.
- Consecutive routine tool rows are compacted in the visible chat transcript into one collapsed assistant-side activity disclosure. Its header and expanded rows use tinted SF Symbols, while the saved transcript remains unmodified for export, restore, and agent handoff.
- Successful tool output stays collapsed by default so long transcripts remain scannable.
- Failed tool output and still-running command output expand by default because those states usually need immediate attention.
- Tool details keep the raw command, arguments, output, and status available behind disclosure.
- Completed command headers describe the command action, never the first output line. Transport-only arguments such as yield time, output-token limits, TTY, and login-shell flags are omitted from display.

## Implementation Notes

- `PersistedChatMessage.toolEvent` is the optional first-class storage for structured tool activity. Keep it optional so older chat history that only has transcript text remains readable.
- `ChatToolTranscriptFormatter.event(for:)` normalizes persisted tool transcript text into `ChatTranscriptEvent.tool(ChatToolTranscriptEvent)` before presentation.
- `ChatToolTranscriptFormatter.presentation(for:)` is the presentation adapter from structured tool events to the disclosure UI copy/body.
- Patch file summaries use `magent-diff://file?path=...` links. `ChatMarkdownLinkResolver` maps those to `.diffFile`, and `ThreadDetailViewController` posts a thread-scoped `magentShowDiffViewer` notification so main and pop-out windows route the focused diff correctly.
- `ChatMessageDisplayPlanner.plan(for:)` is the UI-facing classification boundary. It turns persisted messages into ordinary message, tool, or status display plans.
- `ChatTranscriptDisplayCompactor.compactedMessages(_:)` is display-only. It summarizes consecutive routine tool messages before rendering and exposes activity summaries through `ChatMessageDisplayPlanner` as collapsed disclosure rows; it must not compact statuses or tool presentations that expand by default, and must not be used for persistence, export, or resume context.
- `ChatMessageBubbleView` consumes `ChatMessageDisplayPlanner` output, renders ordinary assistant and tool plans without a bubble background, keeps user/status messages contained, renders tool plans as SF Symbol disclosure rows, and hides tool detail bodies while collapsed.
- `ChatFinalAssistantMessageReconciler` attaches `toolEvent` when final assistant text is itself a tool transcript, so live completions and restored transcripts follow the same presentation path.
- `CodexChatTranscriptReconciler` and `ClaudeChatTranscriptReconciler` pair matching tool calls/results into one persisted message when transcript IDs are available, falling back to standalone output messages when a pair cannot be found.
  Restored tool messages should carry both backward-compatible transcript text and `toolEvent`.
- Codex `/fast` is handled by Magent as a shortcut for setting the same `none` effort used by the `⚡ Fast` picker entry; `/effort fast` is accepted as an alias.

## Gotchas

- Keep provider-specific transcript parsing out of the view layer. Normalize provider logs in the reconciler/runtime layer, then render via shared chat message presentation.
- Keep raw persisted transcript text as the compatibility boundary even when `toolEvent` is present. Existing IPC/read-tab flows and older app versions still rely on readable text.
- New UI code should consume `ChatMessageDisplayPlanner` or `toolEvent`/`ChatTranscriptEvent` rather than reparsing display strings in view code.
- Do not expand successful tool output by default. Long command logs quickly bury the conversation and make restored sessions hard to scan.
- Do not surface successful exit-code metadata (`Exit code: 0`, `Process exited with code 0`) in titles or details; keep it as parsed metadata only.
- Do not promote command output into completed tool titles or show transport controls such as `yield_time_ms` and `max_output_tokens`. Failures and running commands may still show concise state metadata and expand automatically.
- Keep failed and running tools, errors, cancellations, and approval blockers outside compact Activity summaries so attention-required information remains immediately visible.
- Do not let display compaction change persisted chat messages. The compact activity row is only a view-layer artifact.
- Resolve all activity-summary icon insertion offsets against the immutable rendered text, then apply insertions from the end. Forward mutation invalidates later attributed-string ranges and can crash while restoring a chat tab.
- Do not drop raw details from persisted tool messages; users still need to inspect exact commands, arguments, and output when debugging agent behavior.
