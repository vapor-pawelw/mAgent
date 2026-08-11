## Unreleased

### Agents

#### Improvements

- Magent can now detect, skip, and install Codex CLI updates without Codex interrupting new terminal sessions with its own updater.

#### Bug Fixes

- New Codex threads now wait for startup activity to finish before submitting their initial prompt, preventing it from becoming a queued follow-up.
