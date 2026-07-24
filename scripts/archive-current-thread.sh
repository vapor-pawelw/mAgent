#!/usr/bin/env bash

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
MAGENT_CLI="${MAGENT_CLI_PATH:-/tmp/magent-cli}"

THREAD_NAME=""
BASE_BRANCH_OVERRIDE=""
SKIP_LOCAL_SYNC=0
FORCE_ARCHIVE=0
PUSH_AFTER_MERGE=1
DRY_RUN=0

usage() {
  cat <<USAGE
Usage: ./$SCRIPT_NAME [options]

Merges the current Magent thread branch into its base branch from the base worktree,
then archives the thread through magent-cli.

Options:
  --thread <name>           Archive this thread name instead of current-thread
  --base-branch <name>      Override base branch (default: thread-info status.baseBranch or main)
  --skip-local-sync         Archive with --skip-local-sync
  --force-archive           Archive with --force
  --no-push                 Do not push base branch after merge
  --dry-run                 Print actions without changing git/thread state
  -h, --help                Show help

Notes:
- This script does not perform changelog/docs checks.
- Source thread worktree and base worktree must both be clean.
- Concurrent archive workflows for the same repository wait for one another.
USAGE
}

die() {
  echo "Error: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

run_cmd() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '[dry-run] '
    printf '%q ' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

json_ok() {
  printf '%s' "$1" | jq -e '.ok == true' >/dev/null 2>&1
}

find_worktree_for_branch() {
  local repo_path="$1"
  local branch_name="$2"
  local target_ref="refs/heads/${branch_name}"

  git -C "$repo_path" worktree list --porcelain | awk -v target="$target_ref" '
    BEGIN {
      found = 0
    }
    $1 == "worktree" {
      if (path != "" && branch == target) {
        found = 1
        print path
        exit
      }
      path = $2
      branch = ""
      next
    }
    $1 == "branch" {
      branch = $2
      next
    }
    /^$/ {
      if (path != "" && branch == target) {
        found = 1
        print path
        exit
      }
      path = ""
      branch = ""
      next
    }
    END {
      if (!found && path != "" && branch == target) {
        print path
      }
    }
  '
}

perform_archive_workflow() {
  local source_dirty
  local base_head_branch
  local base_dirty
  local source_ref
  local archive_cmd

  # The thread may have changed while this workflow waited behind another archive.
  source_dirty="$(git -C "$worktree_path" status --porcelain)"
  [[ -z "$source_dirty" ]] || die "Thread worktree has uncommitted changes. Commit/stash first."

  base_head_branch="$(git -C "$base_worktree_path" rev-parse --abbrev-ref HEAD)"
  [[ "$base_head_branch" == "$base_branch" ]] || die "Base worktree '$base_worktree_path' is on '$base_head_branch', expected '$base_branch'"

  base_dirty="$(git -C "$base_worktree_path" status --porcelain)"
  [[ -z "$base_dirty" ]] || die "Base worktree '$base_worktree_path' is dirty. Clean it before archiving."

  echo "Archive plan:"
  echo "- Project:       $project_name"
  echo "- Thread:        $THREAD_NAME"
  echo "- Source branch: $source_branch"
  echo "- Base branch:   $base_branch"
  echo "- Source path:   $worktree_path"
  echo "- Base path:     $base_worktree_path"
  if [[ "$PUSH_AFTER_MERGE" -eq 1 ]]; then
    echo "- Push:          origin/$base_branch"
  else
    echo "- Push:          skipped (--no-push)"
  fi
  if [[ "$SKIP_LOCAL_SYNC" -eq 1 ]]; then
    echo "- Archive sync:  skip local sync"
  fi

  # Use refs/heads/ to avoid ambiguity when branch name matches a worktree directory name.
  source_ref="refs/heads/$source_branch"

  echo "Merging '$source_branch' into '$base_branch'..."
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] Script will select already-merged, ff-only, or non-ff merge from ancestry."
  elif git -C "$base_worktree_path" merge-base --is-ancestor "$source_ref" HEAD; then
    echo "'$source_branch' is already contained in '$base_branch'; skipping merge."
  elif git -C "$base_worktree_path" merge-base --is-ancestor HEAD "$source_ref"; then
    git -C "$base_worktree_path" merge --ff-only "$source_ref" \
      || die "Fast-forward merge failed while the archive lock was held."
  else
    git -C "$base_worktree_path" merge --no-ff "$source_ref"
  fi

  if [[ "$PUSH_AFTER_MERGE" -eq 1 ]]; then
    run_cmd git -C "$base_worktree_path" push origin "$base_branch"
  fi

  archive_cmd=("$MAGENT_CLI" archive-thread --thread "$THREAD_NAME")
  if [[ "$FORCE_ARCHIVE" -eq 1 ]]; then
    archive_cmd+=(--force)
  fi
  if [[ "$SKIP_LOCAL_SYNC" -eq 1 ]]; then
    archive_cmd+=(--skip-local-sync)
  fi

  run_cmd "${archive_cmd[@]}"

  echo "Archive workflow completed for thread '$THREAD_NAME'."
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --thread)
      [[ $# -ge 2 ]] || die "--thread requires a value"
      THREAD_NAME="$2"
      shift 2
      ;;
    --base-branch)
      [[ $# -ge 2 ]] || die "--base-branch requires a value"
      BASE_BRANCH_OVERRIDE="$2"
      shift 2
      ;;
    --skip-local-sync)
      SKIP_LOCAL_SYNC=1
      shift
      ;;
    --force-archive)
      FORCE_ARCHIVE=1
      shift
      ;;
    --no-push)
      PUSH_AFTER_MERGE=0
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

require_cmd git
require_cmd jq
require_cmd awk

if [[ ! -x "$MAGENT_CLI" ]]; then
  if command -v magent-cli >/dev/null 2>&1; then
    MAGENT_CLI="$(command -v magent-cli)"
  else
    die "magent-cli not found. Expected $MAGENT_CLI or magent-cli in PATH"
  fi
fi

if [[ -z "$THREAD_NAME" ]]; then
  current_json="$($MAGENT_CLI current-thread 2>/dev/null || true)"
  json_ok "$current_json" || die "Failed to resolve current thread via magent-cli"
  THREAD_NAME="$(printf '%s' "$current_json" | jq -r '.thread.name // empty')"
fi

[[ -n "$THREAD_NAME" ]] || die "Could not determine thread name"

info_json="$($MAGENT_CLI thread-info --thread "$THREAD_NAME" 2>/dev/null || true)"
json_ok "$info_json" || die "Failed to load thread-info for '$THREAD_NAME'"

is_main="$(printf '%s' "$info_json" | jq -r '.thread.isMain // false')"
[[ "$is_main" != "true" ]] || die "Cannot archive the main thread with this script"

project_name="$(printf '%s' "$info_json" | jq -r '.thread.projectName // "unknown"')"
worktree_path="$(printf '%s' "$info_json" | jq -r '.thread.worktreePath // empty')"
source_branch="$(printf '%s' "$info_json" | jq -r '.thread.status.branchName // empty')"
base_branch="$(printf '%s' "$info_json" | jq -r '.thread.status.baseBranch // empty')"

[[ -n "$worktree_path" ]] || die "Thread worktree path is missing"
[[ -d "$worktree_path" ]] || die "Thread worktree path does not exist: $worktree_path"

if [[ -z "$source_branch" ]]; then
  source_branch="$(git -C "$worktree_path" rev-parse --abbrev-ref HEAD)"
fi
[[ -n "$source_branch" ]] || die "Could not determine source branch"

if [[ -n "$BASE_BRANCH_OVERRIDE" ]]; then
  base_branch="$BASE_BRANCH_OVERRIDE"
fi
if [[ -z "$base_branch" ]]; then
  base_branch="main"
  echo "Base branch missing in thread metadata; defaulting to 'main'."
fi

base_worktree_path="$(find_worktree_for_branch "$worktree_path" "$base_branch")"
[[ -n "$base_worktree_path" ]] || die "Could not find a checked-out worktree for base branch '$base_branch'"
[[ -d "$base_worktree_path" ]] || die "Base worktree path not found: $base_worktree_path"

common_git_dir="$(git -C "$base_worktree_path" rev-parse --path-format=absolute --git-common-dir)"
[[ -n "$common_git_dir" && -d "$common_git_dir" ]] || die "Could not resolve the repository git directory"
archive_lock_file="$common_git_dir/magent-archive.lock"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "[dry-run] Would acquire repository archive lock: $archive_lock_file"
  perform_archive_workflow
else
  require_cmd lockf
  echo "Waiting for the repository archive lock..."
  (
    lockf 9
    echo "Repository archive lock acquired."
    perform_archive_workflow
  ) 9>>"$archive_lock_file"
fi
