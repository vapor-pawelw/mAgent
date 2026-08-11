## Unreleased

### Thread

#### Bug Fixes

- Table of Contents history now survives terminal scrollback eviction, and prompt durations are refined from agent transcripts when available.

### Agents

#### Improvements

- Magent can now detect, skip, and install Codex CLI updates without Codex interrupting new terminal sessions with its own updater.

#### Bug Fixes

- Thread and tab busy indicators now remain visible when Codex keeps its composer open below an active Working status.
- Agent completion and input-needed alerts now play their configured sound once instead of sometimes playing it twice when system banners are enabled.
