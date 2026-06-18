# Changelog

## 1.6.4 - 2026-05-29


### Updates

#### Bug Fixes
- Homebrew update relaunch now skips the slow reinstall fallback when the target version is already installed.

### Thread

#### Features
- Branch names can now use slashes and any valid git naming convention (e.g., `feature/my-feature`, `bugfix/issue-123`). Thread directory names remain auto-generated and slash-free for filesystem compatibility.
- Creating a new thread now automatically expands the section it's created in if that section was previously collapsed, making the newly created thread immediately visible.

#### Bug Fixes
- Removed incorrect validation that rejected branch names with slashes.

### Sidebar

#### Bug Fixes
- The CHANGES panel and Diff tab now show files inside newly added nested directories, with the parent path highlighted as a new folder instead of hiding those files behind a non-diffable directory row.
