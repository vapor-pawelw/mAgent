# Thread Creation Sheet

The New Thread sheet is the single UI for creating from the main worktree, another active thread, or an arbitrary branch.

## User-facing behavior

- New Thread opens with the target project's `Main worktree` selected in the `Start from` picker.
- `New Thread from This Thread…` opens the same sheet with the contextual thread selected.
- The title follows the selection: `New thread from <description>`, falling back to the branch name. The source name is accent-colored.
- Picker options use compact thread capsules: home/thread icon, sign plus description, branch, and the section-color corner marker. They intentionally omit the sidebar status row and all live status treatments.
- Selecting a non-main source thread sets Base branch to that thread's current branch. Until Section is manually changed, it also follows the selected source thread's section.
- Manually changing Base branch breaks the source-thread relationship and replaces the selected capsule with a synthetic Branch capsule. The new thread no longer inherits source placement or its local-file-sync snapshot.
- Selecting a thread again restores the linked source behavior.
- Changing Project resets the source to that project's main worktree and resets Section to the project's default.

## Creation semantics

- Main worktree is the visual representation of the ordinary, non-fork creation path. It supplies the base branch but does not count as a source thread for placement or local-file-sync inheritance.
- A linked non-main source supplies:
  - its current branch as the requested base branch;
  - its section, unless the user chose a section manually;
  - insertion immediately after the source when sidebar grouping permits;
  - its local-file-sync snapshot.
- A custom branch supplies only the requested base branch.
- Editing completion and final submission both reconcile the Base branch field with the source state. This prevents submitting with stale source inheritance when Return activates Create Thread directly from the branch field.

## Implementation notes

- `ThreadCreationSourceSelection` owns the testable linked-thread versus custom-branch state transition.
- `ThreadCreationSourcePicker` is an AppKit popover control rather than an `NSPopUpButton`, because native popup rows cannot represent the two-line miniature capsules.
- `ThreadCreationSourceOption` is presentation-only. Creation resolves the selected thread ID against the current active `ThreadManager` state before applying inheritance.
- Main worktree returns no `sourceThreadID`; this preserves the distinction between an ordinary main-based thread and a fork from a non-main thread.
