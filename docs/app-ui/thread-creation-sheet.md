# Thread Creation Sheet

The New Thread sheet is the single UI for creating from the main worktree, another active thread, or an arbitrary branch.

## User-facing behavior

- New Thread opens with the target project's `Main worktree` selected in the `Start from` picker.
- `New Thread from This Thread…` opens the same sheet with the contextual thread selected.
- The title follows the selection: `New thread from <description>`, falling back to the branch name. The source name is accent-colored.
- `Start from` sits immediately below the Type/Model/Reasoning controls.
- The collapsed picker is a standard-height, single-line control showing only the selected thread description, or `Branch` for a manually entered base. Base branch details remain in the dedicated field.
- Picker options use subtly outlined compact thread capsules: home/thread icon, sign plus description, branch, and the section-color corner marker. They intentionally omit the sidebar status row and all live status treatments.
- The selected expanded option uses an accent-tinted background and outline so the current source remains obvious while browsing.
- Leading icons follow the sidebar's `Show thread icons` setting and use the same normal-row tint: section color for sectioned threads, the app accent otherwise, and label color for Main worktree. When leading icons are hidden, Main worktree keeps its compact inline home glyph.
- Main worktree is always first and the invoking window's current thread is second. A 24 pt gap separates these contextual choices from the remaining threads, with no extra leading gap. Pop-out windows supply their own thread as the current context.
- Opening the picker scrolls the selected source to the vertical center where the available scroll range permits, clamping naturally at the beginning and end of the list.
- Selecting a non-main source thread sets Base branch to that thread's current branch. Until Section is manually changed, it also follows the selected source thread's section.
- Typing a Base branch that unambiguously matches an available thread branch immediately restores that thread as the selected source, including its title, picker highlight, section following, placement, and local-file-sync inheritance. Whitespace and an optional `origin/` prefix are ignored; exact spelling wins when normalized names collide.
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
