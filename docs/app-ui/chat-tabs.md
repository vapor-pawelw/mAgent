# Chat Tabs

## User-facing behavior

- Chat tabs render agent messages, user prompts, attachments, model-change markers, and restored tool activity from Claude/Codex transcripts.
- Tool activity should read like concise actions first: `Run command`, `Read file`, `Search`, or `Tool output`.
- Successful tool output stays collapsed by default so long transcripts remain scannable.
- Failed tool output and still-running command output expand by default because those states usually need immediate attention.
- Tool details keep the raw command, arguments, output, and status available behind disclosure.

## Implementation Notes

- `ChatToolTranscriptFormatter.event(for:)` normalizes persisted tool transcript text into `ChatTranscriptEvent.tool(ChatToolTranscriptEvent)` before presentation.
- `ChatToolTranscriptFormatter.presentation(for:)` is the presentation adapter from structured tool events to the disclosure UI copy/body.
- `ChatMessageBubbleView` parses the structured tool event first, renders the formatter presentation as an assistant-side disclosure row, and hides the detail body while collapsed.
- `CodexChatTranscriptReconciler` and `ClaudeChatTranscriptReconciler` pair matching tool calls/results into one persisted message when transcript IDs are available, falling back to standalone output messages when a pair cannot be found.

## Gotchas

- Keep provider-specific transcript parsing out of the view layer. Normalize provider logs in the reconciler/runtime layer, then render via shared chat message presentation.
- Keep raw persisted transcript text as the compatibility boundary until chat-tab persistence grows first-class event storage. New UI code should consume `ChatTranscriptEvent` rather than reparsing display strings.
- Do not expand successful tool output by default. Long command logs quickly bury the conversation and make restored sessions hard to scan.
- Do not drop raw details from persisted tool messages; users still need to inspect exact commands, arguments, and output when debugging agent behavior.
