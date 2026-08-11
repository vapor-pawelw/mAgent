## Unreleased

### Thread

#### Bug Fixes

- Table of Contents history now survives terminal scrollback eviction, and prompt durations are refined from agent transcripts when available.

### Agents

#### Improvements

- Agent tabs that return to an idle shell now offer a one-click **Start Agent** action without interrupting other running commands.
- Agent terminal sessions now start without user shell plugins, themes, aliases, or update checks, while standard terminal tabs continue using the user's normal shell setup.
- Magent can now detect, skip, and install Codex CLI updates without Codex interrupting new terminal sessions with its own updater.

#### Bug Fixes

- Thread and tab busy indicators now remain visible when Codex keeps its composer open below an active Working status.
- Agent completion and input-needed alerts now play their configured sound once instead of sometimes playing it twice when system banners are enabled.
