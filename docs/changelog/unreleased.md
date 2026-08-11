## Unreleased

### Agents

#### Improvements

- Agent terminal sessions now start without user shell plugins, themes, aliases, or update checks, while standard terminal tabs continue using the user's normal shell setup.
- Magent can now detect, skip, and install Codex CLI updates without Codex interrupting new terminal sessions with its own updater.

#### Bug Fixes

- Agent completion and input-needed alerts now play their configured sound once instead of sometimes playing it twice when system banners are enabled.
