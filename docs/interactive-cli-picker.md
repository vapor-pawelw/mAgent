# Interactive CLI Picker

This note covers the status-aware thread rows shown by `magent-cli` interactive mode and `magent-cli ls`.

## User-visible behavior

- Thread rows show live status badges such as `done`, `busy`, `input`, `dirty`, `limited`, and `delivered`.
- When ANSI colors are supported, the picker uses bright white for primary text and colors badges by meaning so completed threads stand out in green.
- The non-`fzf` fallback menu uses the same rendered labels, so status stays visible even when advanced picker tools are unavailable.

## Implementation notes

- The installed shell script lives inside `IPCSocketServer.installCLIScript()` and is versioned by `cliVersion`. Bump `cliVersion` whenever changing the embedded script so `/tmp/magent-cli` is reinstalled.
- `list-threads` now includes a `status` payload. The picker and `ls` should consume that payload directly instead of issuing one `thread-info` request per thread.
- Color output is optional. `MAGENT_USE_COLOR=0` or `NO_COLOR=1` disables ANSI styling, while `fzf` styling is enabled only when color support is active.

## Gotchas

- Keep the shell script POSIX `sh` compatible. Validate changes with `sh -n` against the extracted script body, not just Swift compilation.
- If you add new badges, update both the interactive picker formatter and the `ls` formatter so they stay in sync.
