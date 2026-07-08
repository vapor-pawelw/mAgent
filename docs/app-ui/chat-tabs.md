# Chat Tabs

## User-facing behavior

- Chat tabs render agent messages, user prompts, attachments, model-change markers, and restored tool activity from Claude/Codex transcripts.
- Tool activity should read like concise actions first: `Run command`, `Read file`, `Search`, or `Tool output`.
- Successful tool output stays collapsed by default so long transcripts remain scannable.
- Failed tool output and still-running command output expand by default because those states usually need immediate attention.
- Tool details keep the raw command, arguments, output, and status available behind disclosure.

## Implementation Notes

- `PersistedChatMessage.toolEvent` is the optional first-class storage for structured tool activity. Keep it optional so older chat history that only has transcript text remains readable.
- `ChatToolTranscriptFormatter.event(for:)` normalizes persisted tool transcript text into `ChatTranscriptEvent.tool(ChatToolTranscriptEvent)` before presentation.
- `ChatToolTranscriptFormatter.presentation(for:)` is the presentation adapter from structured tool events to the disclosure UI copy/body.
- `ChatMessageBubbleView` prefers `PersistedChatMessage.toolEvent`, falls back to parsing transcript text, renders the formatter presentation as an assistant-side disclosure row, and hides the detail body while collapsed.
- `CodexChatTranscriptReconciler` and `ClaudeChatTranscriptReconciler` pair matching tool calls/results into one persisted message when transcript IDs are available, falling back to standalone output messages when a pair cannot be found.
  Restored tool messages should carry both backward-compatible transcript text and `toolEvent`.

## Gotchas

- Keep provider-specific transcript parsing out of the view layer. Normalize provider logs in the reconciler/runtime layer, then render via shared chat message presentation.
- Keep raw persisted transcript text as the compatibility boundary even when `toolEvent` is present. Existing IPC/read-tab flows and older app versions still rely on readable text.
- New UI code should consume `toolEvent`/`ChatTranscriptEvent` rather than reparsing display strings.
- Do not expand successful tool output by default. Long command logs quickly bury the conversation and make restored sessions hard to scan.
- Do not drop raw details from persisted tool messages; users still need to inspect exact commands, arguments, and output when debugging agent behavior.
