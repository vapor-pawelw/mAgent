#!/usr/bin/env bash

set -euo pipefail

RELEASE_WORKFLOW_NAME="Release"
DEFAULT_RELEASE_REPO="vapor-pawelw/mAgent"
DEFAULT_HOMEBREW_TAP_REPO="vapor-pawelw/homebrew-tap"
CHANGELOG_FILE="CHANGELOG.md"
CHANGELOG_UNRELEASED_FILE="docs/changelog/unreleased.md"
CHANGELOG_ARCHIVE_DIR="docs/changelog/archive"
CHANGELOG_UNRELEASED_PLACEHOLDER="- _No notable changes yet._"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

infer_owner_repo() {
  local remote_url
  remote_url="$(git config --get remote.origin.url || true)"
  if [[ -z "$remote_url" ]]; then
    return 1
  fi

  if [[ "$remote_url" =~ ^git@github\.com:([^/]+/[^/]+)(\.git)?$ ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi

  if [[ "$remote_url" =~ ^https://github\.com/([^/]+/[^/]+)(\.git)?$ ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi

  if [[ "$remote_url" =~ ^ssh://git@github\.com/([^/]+/[^/]+)(\.git)?$ ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi

  return 1
}

normalize_owner_repo() {
  local owner_repo="$1"
  owner_repo="${owner_repo%.git}"
  printf '%s\n' "$owner_repo"
}

release_workflow_status() {
  local owner_repo="$1"
  local total_count release_count

  total_count="$(gh api "repos/${owner_repo}/actions/workflows" --jq '.total_count' 2>/dev/null || true)"
  if [[ -z "$total_count" ]]; then
    return 2
  fi
  if [[ ! "$total_count" =~ ^[0-9]+$ ]]; then
    return 2
  fi

  if [[ "$total_count" -eq 0 ]]; then
    return 3
  fi

  release_count="$(gh api "repos/${owner_repo}/actions/workflows" --jq ".workflows | map(select(.name == \"${RELEASE_WORKFLOW_NAME}\")) | length" 2>/dev/null || true)"
  if [[ -z "$release_count" ]]; then
    return 2
  fi
  if [[ ! "$release_count" =~ ^[0-9]+$ ]]; then
    return 2
  fi
  if [[ "$release_count" -eq 0 ]]; then
    return 4
  fi

  return 0
}

default_next_patch() {
  local latest_tag="$1"
  local clean
  clean="${latest_tag#v}"
  if [[ "$clean" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    local major minor patch
    major="${BASH_REMATCH[1]}"
    minor="${BASH_REMATCH[2]}"
    patch="${BASH_REMATCH[3]}"
    echo "${major}.${minor}.$((patch + 1))"
    return 0
  fi
  return 1
}

extract_unreleased_notes() {
  local file="$1"
  awk '
    BEGIN { in_unreleased = 0; found = 0 }
    /^## Unreleased[[:space:]]*$/ {
      in_unreleased = 1
      found = 1
      next
    }
    /^## / {
      if (in_unreleased == 1) {
        exit
      }
    }
    in_unreleased == 1 {
      print
    }
    END {
      if (found == 0) {
        exit 2
      }
    }
  ' "$file"
}

extract_version_notes() {
  local file="$1"
  local version="$2"
  awk -v version="$version" '
    BEGIN { in_version = 0; found = 0 }
    $0 ~ ("^## " version " - ") {
      in_version = 1
      found = 1
      print
      next
    }
    /^## / {
      if (in_version == 1) {
        exit
      }
    }
    in_version == 1 {
      print
    }
    END {
      if (found == 0) {
        exit 2
      }
    }
  ' "$file"
}

latest_changelog_version() {
  local file="$1"
  awk '
    /^## [0-9]+\.[0-9]+\.[0-9]+ - / {
      print $2
      exit
    }
  ' "$file"
}

version_section_exists() {
  local file="$1"
  local version="$2"
  awk -v version="$version" '
    $0 ~ ("^## " version " - ") { found = 1; exit }
    END { exit(found ? 0 : 2) }
  ' "$file"
}

has_meaningful_changelog_notes() {
  local notes_file="$1"
  local count
  count="$(sed '/^[[:space:]]*$/d' "$notes_file" \
    | grep -Fvx -- "$CHANGELOG_UNRELEASED_PLACEHOLDER" \
    | grep -c '[^[:space:]]' || true)"
  [[ "${count:-0}" -gt 0 ]]
}

print_changelog_domain_order() {
  local notes_file="$1"
  awk '
    /^### / {
      domain = $0
      sub(/^### /, "", domain)
      if (domain != "") {
        print "- " domain
      }
    }
  ' "$notes_file"
}

promote_unreleased_changelog() {
  local changelog_file="$1"
  local version="$2"
  local release_date="$3"
  local notes_file="$4"
  local archive_dir="$5"
  local tmp_file
  tmp_file="$(mktemp)"

  local previous_version
  previous_version="$(latest_changelog_version "$changelog_file" || true)"
  if [[ -n "$previous_version" && "$previous_version" != "$version" ]]; then
    mkdir -p "$archive_dir"
    local archive_file="${archive_dir}/${previous_version}.md"
    if [[ -e "$archive_file" ]]; then
      echo "Archive file already exists: ${archive_file}" >&2
      rm -f "$tmp_file"
      return 1
    fi
    cp "$changelog_file" "$archive_file"
  fi

  if [[ "$previous_version" == "$version" ]]; then
    local existing_notes_file
    existing_notes_file="$(mktemp)"
    if ! extract_version_notes "$changelog_file" "$version" >"$existing_notes_file"; then
      rm -f "$tmp_file" "$existing_notes_file"
      return 1
    fi
    {
      printf '# Changelog\n\n'
      cat "$existing_notes_file"
      printf '\n'
      awk -v placeholder="$CHANGELOG_UNRELEASED_PLACEHOLDER" '$0 != placeholder { print }' "$notes_file"
      printf '\n'
    } >"$tmp_file"
    rm -f "$existing_notes_file"
  else
    {
      printf '# Changelog\n\n'
      printf '## %s - %s\n\n' "$version" "$release_date"
      awk -v placeholder="$CHANGELOG_UNRELEASED_PLACEHOLDER" '$0 != placeholder { print }' "$notes_file"
      printf '\n'
    } >"$tmp_file"
  fi

  mv "$tmp_file" "$changelog_file"
  rm -f "$CHANGELOG_UNRELEASED_FILE"
}

NON_INTERACTIVE=0

confirm() {
  local prompt="$1"
  if [[ "$NON_INTERACTIVE" -eq 1 ]]; then
    echo "$prompt [y/N]: y (non-interactive)"
    return 0
  fi
  local response
  read -r -p "$prompt [y/N]: " response
  case "$response" in
    [Yy]|[Yy][Ee][Ss]) return 0 ;;
    *) return 1 ;;
  esac
}

wait_for_release_run_id() {
  local owner_repo="$1"
  local tag="$2"
  local not_before="${3:-}"
  local run_id=""
  local attempt

  for attempt in $(seq 1 36); do
    local jq_filter
    jq_filter=".[] | select(.event == \"push\" and .headBranch == \"$tag\")"
    if [[ -n "$not_before" ]]; then
      jq_filter+=" | select(.createdAt > \"$not_before\")"
    fi
    jq_filter+=" | .databaseId"

    run_id="$(gh run list \
      --repo "$owner_repo" \
      --workflow "$RELEASE_WORKFLOW_NAME" \
      --limit 40 \
      --json databaseId,event,headBranch,createdAt \
      --jq "$jq_filter" | head -n1 || true)"

    if [[ -n "$run_id" ]]; then
      echo "$run_id"
      return 0
    fi

    sleep 5
  done

  return 1
}

verify_release_asset() {
  local owner_repo="$1"
  local tag="$2"

  if ! gh release view "$tag" --repo "$owner_repo" --json assets --jq '.assets[].name' | grep -qx "Magent.dmg"; then
    echo "Release exists but Magent.dmg was not found on $tag." >&2
    return 1
  fi

  if ! gh release view "$tag" --repo "$owner_repo" --json assets --jq '.assets[].name' | grep -qx "Magent.zip"; then
    echo "Release exists but compatibility asset Magent.zip was not found on $tag." >&2
    return 1
  fi
}

read_homebrew_cask() {
  local tap_repo="$1"
  gh api -H "Accept: application/vnd.github.raw" "repos/${tap_repo}/contents/Casks/magent.rb"
}

verify_homebrew_version() {
  local tap_repo="$1"
  local version="$2"
  local expected_url="${3:-}"
  local cask_content cask_version cask_sha cask_url

  cask_content="$(read_homebrew_cask "$tap_repo")"
  cask_version="$(printf '%s\n' "$cask_content" | sed -n 's/^[[:space:]]*version[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  cask_sha="$(printf '%s\n' "$cask_content" | sed -n 's/^[[:space:]]*sha256[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  cask_url="$(printf '%s\n' "$cask_content" | sed -n 's/^[[:space:]]*url[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"

  if [[ "$cask_version" != "$version" ]]; then
    echo "Homebrew cask is at version '$cask_version', expected '$version'." >&2
    return 1
  fi

  if [[ -z "$cask_sha" ]]; then
    echo "Homebrew cask has an empty sha256 field." >&2
    return 1
  fi

  if [[ -n "$expected_url" && "$cask_url" != "$expected_url" ]]; then
    echo "Homebrew cask URL is '$cask_url', expected '$expected_url'." >&2
    return 1
  fi

  echo "$cask_sha"
}

wait_for_homebrew_update() {
  local tap_repo="$1"
  local version="$2"
  local expected_url="${3:-}"
  local sha=""
  local attempt

  for attempt in $(seq 1 30); do
    if sha="$(verify_homebrew_version "$tap_repo" "$version" "$expected_url" 2>/dev/null)"; then
      printf '%s\n' "$sha"
      return 0
    fi
    sleep 10
  done

  return 1
}

main() {
  local version_arg=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version) version_arg="${2#v}"; shift 2 ;;
      --yes|-y) NON_INTERACTIVE=1; shift ;;
      *) echo "Unknown argument: $1" >&2; echo "Usage: $0 [--version X.Y.Z] [--yes]" >&2; exit 1 ;;
    esac
  done

  require_cmd git
  require_cmd gh
  require_cmd sed
  require_cmd grep
  require_cmd awk
  require_cmd date
  require_cmd mktemp

  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "Run this script from inside a git repository." >&2
    exit 1
  fi

  if ! gh auth status >/dev/null 2>&1; then
    echo "GitHub CLI is not authenticated. Run: gh auth login" >&2
    exit 1
  fi

  local source_repo
  source_repo="$(infer_owner_repo || true)"
  if [[ -z "$source_repo" ]]; then
    echo "Could not infer GitHub owner/repo from origin remote." >&2
    exit 1
  fi
  source_repo="$(normalize_owner_repo "$source_repo")"

  local release_repo
  release_repo="${MAGENT_RELEASE_REPO:-$DEFAULT_RELEASE_REPO}"

  local tap_repo
  tap_repo="${MAGENT_HOMEBREW_TAP_REPO:-$DEFAULT_HOMEBREW_TAP_REPO}"

  local branch latest_tag default_version version tag release_date
  branch="$(git branch --show-current)"
  if [[ -z "$branch" ]]; then
    echo "Detached HEAD is not supported for releases. Check out a branch first." >&2
    exit 1
  fi
  latest_tag="$(git tag --sort=-v:refname | head -n1 || true)"
  default_version=""
  if [[ -n "$latest_tag" ]]; then
    default_version="$(default_next_patch "$latest_tag" || true)"
  fi
  release_date="$(date +%Y-%m-%d)"

  echo "Source repository: $source_repo"
  echo "Release repository: $release_repo"
  echo "Current branch: ${branch:-detached}"
  if [[ -n "$latest_tag" ]]; then
    echo "Latest tag: $latest_tag"
  else
    echo "No tags found yet."
  fi

  if [[ -n "$version_arg" ]]; then
    version="$version_arg"
    echo "Version: $version"
  elif [[ -n "$default_version" ]]; then
    read -r -p "Version to release (e.g. 1.2.3) [$default_version]: " version
    version="${version:-$default_version}"
  else
    read -r -p "Version to release (e.g. 1.2.3): " version
  fi

  version="${version#v}"
  if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid version '$version'. Use semantic version format like 1.2.3." >&2
    exit 1
  fi

  tag="v${version}"

  if [[ "$branch" != "main" ]]; then
    echo "Warning: you are not on 'main' (current: ${branch:-detached})."
    if ! confirm "Continue anyway"; then
      echo "Aborted."
      exit 0
    fi
  fi

  if [[ -n "$(git status --porcelain)" ]]; then
    echo "Warning: working tree has uncommitted changes."
    if ! confirm "Continue anyway"; then
      echo "Aborted."
      exit 0
    fi
  fi

  if git rev-parse "$tag" >/dev/null 2>&1; then
    echo "Tag '$tag' already exists locally." >&2
    exit 1
  fi
  if git ls-remote --tags origin "refs/tags/${tag}" | grep -q .; then
    echo "Tag '$tag' already exists on origin." >&2
    exit 1
  fi

  if [[ ! -f "$CHANGELOG_FILE" ]]; then
    echo "Missing ${CHANGELOG_FILE}. Add it before creating a release." >&2
    exit 1
  fi

  local release_notes_file
  release_notes_file="$(mktemp)"
  local tag_notes_file
  tag_notes_file="$(mktemp)"
  trap 'rm -f "'"$release_notes_file"'" "'"$tag_notes_file"'"' EXIT

  if [[ -f "$CHANGELOG_UNRELEASED_FILE" ]]; then
    if ! extract_unreleased_notes "$CHANGELOG_UNRELEASED_FILE" >"$release_notes_file"; then
      echo "Could not read '## Unreleased' from ${CHANGELOG_UNRELEASED_FILE}." >&2
      echo "Expected format:"
      echo "## Unreleased"
      echo
      echo "- Bullet describing a user-visible change"
      exit 1
    fi
  else
    : >"$release_notes_file"
  fi

  local reuse_existing_version_notes=false
  if ! has_meaningful_changelog_notes "$release_notes_file"; then
    if version_section_exists "$CHANGELOG_FILE" "$version" &&
      extract_version_notes "$CHANGELOG_FILE" "$version" >"$release_notes_file"; then
      reuse_existing_version_notes=true
    else
      echo "${CHANGELOG_UNRELEASED_FILE} has no release notes under '## Unreleased'." >&2
      echo "Add at least one bullet before releasing."
      exit 1
    fi
  fi

  local commit
  commit="$(git rev-parse --short HEAD)"
  echo
  echo "Release plan:"
  if [[ "$reuse_existing_version_notes" == "true" ]]; then
    echo "- Reuse existing ${CHANGELOG_FILE} '## ${version} - <date>' notes"
    echo "- Push current branch '${branch}'"
  else
    echo "- Archive existing ${CHANGELOG_FILE} into ${CHANGELOG_ARCHIVE_DIR}/<old-version>.md"
    echo "- Promote ${CHANGELOG_UNRELEASED_FILE} notes into ${CHANGELOG_FILE} '## ${version} - ${release_date}'"
    echo "- Remove ${CHANGELOG_UNRELEASED_FILE}"
    echo "- Create and push changelog/archive commit on branch '${branch}'"
  fi
  echo "- Create and push annotated tag: $tag"
  echo "- Current source commit: $commit"
  echo "- Watch workflow in ${source_repo}: $RELEASE_WORKFLOW_NAME"
  echo "- Verify GitHub release in ${release_repo} contains Magent.dmg and Magent.zip"
  echo "- Verify Homebrew tap ${tap_repo} points to version ${version}"
  echo
  echo "Pending changelog domain order:"
  print_changelog_domain_order "$release_notes_file"
  echo
  echo "Review this order for release importance before proceeding; the script preserves it exactly."
  echo

  if ! confirm "Proceed with this release"; then
    echo "Aborted."
    exit 0
  fi

  local changelog_commit
  if [[ "$reuse_existing_version_notes" == "true" ]]; then
    changelog_commit="$(git rev-parse --short HEAD)"
  else
    local unreleased_was_tracked=false
    if git ls-files --error-unmatch "$CHANGELOG_UNRELEASED_FILE" >/dev/null 2>&1; then
      unreleased_was_tracked=true
    fi

    if ! promote_unreleased_changelog "$CHANGELOG_FILE" "$version" "$release_date" "$release_notes_file" "$CHANGELOG_ARCHIVE_DIR"; then
      echo "Failed to update ${CHANGELOG_FILE} for ${version}." >&2
      exit 1
    fi

    git add "$CHANGELOG_FILE" "$CHANGELOG_ARCHIVE_DIR"
    if [[ "$unreleased_was_tracked" == "true" ]]; then
      git add "$CHANGELOG_UNRELEASED_FILE"
    fi
    if git diff --cached --quiet -- "$CHANGELOG_FILE" "$CHANGELOG_UNRELEASED_FILE" "$CHANGELOG_ARCHIVE_DIR"; then
      echo "No changelog changes were staged for release ${version}." >&2
      exit 1
    fi

    if [[ "$unreleased_was_tracked" == "true" ]]; then
      git commit -m "Update changelog for ${tag}" -- "$CHANGELOG_FILE" "$CHANGELOG_UNRELEASED_FILE" "$CHANGELOG_ARCHIVE_DIR"
    else
      git commit -m "Update changelog for ${tag}" -- "$CHANGELOG_FILE" "$CHANGELOG_ARCHIVE_DIR"
    fi
    changelog_commit="$(git rev-parse --short HEAD)"
  fi

  if ! git push origin "$branch"; then
    echo "Failed to push branch '${branch}'. Tag was not created." >&2
    exit 1
  fi

  if ! extract_version_notes "$CHANGELOG_FILE" "$version" >"$tag_notes_file"; then
    echo "Could not read '## ${version} - <date>' notes from ${CHANGELOG_FILE} after promotion." >&2
    exit 1
  fi
  git tag -a "$tag" -F "$tag_notes_file"
  if ! git push origin "$tag"; then
    echo "Failed to push tag. Cleaning up local tag '$tag'." >&2
    git tag -d "$tag" >/dev/null 2>&1 || true
    exit 1
  fi

  if release_workflow_status "$source_repo"; then
    :
  else
    local workflow_status
    workflow_status="$?"
    case "$workflow_status" in
      2)
        echo "Tag pushed, but could not query GitHub Actions workflows for ${source_repo}."
        echo "Skipping workflow/release/Homebrew verification."
        exit 0
        ;;
      3)
        echo "Tag pushed. No GitHub Actions workflows are configured in ${source_repo}."
        echo "Skipping workflow/release/Homebrew verification."
        exit 0
        ;;
      4)
        echo "Tag pushed. Workflow '${RELEASE_WORKFLOW_NAME}' is not configured in ${source_repo}."
        echo "Skipping workflow/release/Homebrew verification."
        exit 0
        ;;
    esac
  fi

  local release_request_started_at
  release_request_started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  echo "Changelog commit ${changelog_commit} pushed. Waiting for GitHub Actions run..."
  local run_id
  run_id="$(wait_for_release_run_id "$source_repo" "$tag" "$release_request_started_at" || true)"
  if [[ -z "$run_id" ]]; then
    echo "Could not find the '${RELEASE_WORKFLOW_NAME}' run for tag ${tag}." >&2
    echo "Check manually with: gh run list --workflow \"${RELEASE_WORKFLOW_NAME}\" --repo ${source_repo}" >&2
    exit 1
  fi

  echo "Watching workflow run $run_id..."
  gh run watch "$run_id" --repo "$source_repo" --exit-status

  echo "Verifying GitHub release assets in ${release_repo}..."
  verify_release_asset "$release_repo" "$tag"

  local expected_cask_url
  expected_cask_url="https://github.com/${release_repo}/releases/download/${tag}/Magent.dmg"

  echo "Verifying Homebrew tap update in ${tap_repo}..."
  local cask_sha
  cask_sha="$(wait_for_homebrew_update "$tap_repo" "$version" "$expected_cask_url" || true)"
  if [[ -z "$cask_sha" ]]; then
    echo "Release completed, but Homebrew tap did not update to ${version} in time." >&2
    echo "Check manually: https://github.com/${tap_repo}/blob/main/Casks/magent.rb" >&2
    exit 1
  fi

  local release_url
  release_url="$(gh release view "$tag" --repo "$release_repo" --json url --jq '.url')"

  echo
  echo "Release complete."
  echo "- Changelog commit: ${changelog_commit}"
  echo "- Tag: ${tag}"
  echo "- GitHub release: ${release_url}"
  echo "- Homebrew cask: https://github.com/${tap_repo}/blob/main/Casks/magent.rb"
  echo "- Homebrew sha256: ${cask_sha}"
}

main "$@"
