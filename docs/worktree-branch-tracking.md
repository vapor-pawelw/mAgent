# Worktree Branch Tracking

## User Behavior

- For non-main threads, Magent now treats the branch currently checked out in the worktree as the source of truth.
- After first-prompt auto-rename, `magent-cli auto-rename-thread`, `magent-cli rename-branch`, or any manual `git checkout` / `git switch`, the sidebar and `CHANGES` footer should show the new branch without requiring the user to accept a mismatch banner.
- The main thread still keeps its separate "expected branch" behavior based on the project's configured default branch.

## Implementation Notes

- `ThreadManager.refreshBranchStates()` updates `actualBranch` for all threads, but for non-main threads it also persists `branchName = actualBranch` when Git reports a different checked-out branch.
- Branch-mismatch UI remains meaningful only for the main thread. Non-main worktrees now adopt the current branch instead of treating that state as drift.
- Worktree discovery in `ThreadManager.syncThreadsWithWorktrees(for:)` must seed `branchName` from `git branch --show-current` rather than assuming the directory name or rename symlink matches the checked-out branch.
- The sidebar diff footer is fed from the latest thread-manager snapshot, not from a stale `MagentThread` captured before rename/switch operations completed.

## Changed In This Thread

- Fixed stale `thread.branchName` after auto-rename and branch switches.
- Fixed `CHANGES` footer branch labels so they refresh from live thread state after rename/switch operations.
- Fixed imported/recovered worktrees to record their real checked-out branch on discovery.

## Gotchas

- Thread name, worktree directory basename, and git branch are no longer interchangeable. Rename symlinks intentionally let the thread name differ from the real worktree path, and manual branch switches can make the branch differ from both.
- When refreshing UI after rename or branch changes, resolve the current thread again from `ThreadManager.threads` by `id` before reading `branchName` or `actualBranch`. Using the pre-refresh `MagentThread` snapshot can leave footer/tooltips one update behind.
