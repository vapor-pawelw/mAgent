#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: bootstrap-ghosttykit.sh [--ref <git-ref>] [--work-dir <path>]

Builds GhosttyKit.xcframework from ghostty-org/ghostty and installs it into:
  Libraries/GhosttyKit.xcframework

Environment overrides:
  GHOSTTY_REF       Ghostty git ref to build (default: v1.3.0)
  GHOSTTY_WORK_DIR  Working directory for ghostty checkout (default: .build/ghostty-src)
EOF
}

patch_stale_iterm2_themes_dependency() {
  local zon_file="$1"
  local mirror_url="https://deps.files.ghostty.org/ghostty-themes-release-20260216-151611-fc73ce3.tgz"
  local mirror_hash="N-V-__8AABVbAwBwDRyZONfx553tvMW8_A2OKUoLzPUSRiLF"

  if [[ ! -f "$zon_file" ]]; then
    return 1
  fi

  if ! grep -q 'github.com/mbadolato/iTerm2-Color-Schemes/releases/download/.*/ghostty-themes.tgz' "$zon_file"; then
    return 1
  fi

  echo "Patching stale iTerm2 themes dependency to Ghostty mirror"
  GHOSTTY_ITERM2_THEMES_URL="$mirror_url" \
  GHOSTTY_ITERM2_THEMES_HASH="$mirror_hash" \
  perl -0777 -i -pe '
    s#(\.iterm2_themes\s*=\s*\.\{\s*\n\s*\.url\s*=\s*)"[^"]+"(,\s*\n\s*\.hash\s*=\s*)"[^"]+"#
      $1 . "\"" . $ENV{GHOSTTY_ITERM2_THEMES_URL} . "\"" . $2 . "\"" . $ENV{GHOSTTY_ITERM2_THEMES_HASH} . "\""
    #gsex
  ' "$zon_file"

  return 0
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

run_zig() {
  if command -v mise >/dev/null 2>&1; then
    mise x -- zig "$@"
  else
    zig "$@"
  fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

GHOSTTY_REF="${GHOSTTY_REF:-v1.3.0}"
WORK_DIR="${GHOSTTY_WORK_DIR:-$REPO_ROOT/.build/ghostty-src}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ref)
      if [[ $# -lt 2 ]]; then
        echo "--ref requires a value" >&2
        usage
        exit 1
      fi
      GHOSTTY_REF="$2"
      shift 2
      ;;
    --work-dir)
      if [[ $# -lt 2 ]]; then
        echo "--work-dir requires a value" >&2
        usage
        exit 1
      fi
      WORK_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

SOURCE_DIR="$WORK_DIR/ghostty"
OUTPUT_XCFRAMEWORK="$SOURCE_DIR/macos/GhosttyKit.xcframework"
DEST_XCFRAMEWORK="$REPO_ROOT/Libraries/GhosttyKit.xcframework"
DEST_REF_FILE="$DEST_XCFRAMEWORK/.ghostty-ref"

require_cmd git
require_cmd rsync
require_cmd plutil
if ! command -v mise >/dev/null 2>&1; then
  require_cmd zig
fi

mkdir -p "$WORK_DIR"

if [[ ! -d "$SOURCE_DIR/.git" ]]; then
  git init "$SOURCE_DIR" >/dev/null
  git -C "$SOURCE_DIR" remote add origin https://github.com/ghostty-org/ghostty.git
fi

echo "Fetching Ghostty ref: $GHOSTTY_REF"
git -C "$SOURCE_DIR" fetch --depth 1 origin "$GHOSTTY_REF"
git -C "$SOURCE_DIR" checkout --force FETCH_HEAD
git -C "$SOURCE_DIR" clean -fdx

echo "Building GhosttyKit.xcframework"
build_log="$(mktemp "${TMPDIR%/}/ghostty-build.XXXXXX")"
if ! (
  cd "$SOURCE_DIR"
  run_zig build -Doptimize=ReleaseFast -Dapp-runtime=none -Demit-xcframework -Dxcframework-target=universal 2>&1 | tee "$build_log"
); then
  if grep -q "ghostty-themes.tgz" "$build_log" && grep -q "404 Not Found" "$build_log"; then
    if patch_stale_iterm2_themes_dependency "$SOURCE_DIR/build.zig.zon"; then
      echo "Retrying build after patching stale iTerm2 themes dependency"
      (
        cd "$SOURCE_DIR"
        run_zig build -Doptimize=ReleaseFast -Dapp-runtime=none -Demit-xcframework -Dxcframework-target=universal
      )
    else
      echo "Build failed with stale themes 404, but automatic dependency patch was not applicable." >&2
      rm -f "$build_log"
      exit 1
    fi
  else
    rm -f "$build_log"
    exit 1
  fi
fi
rm -f "$build_log"

if [[ ! -d "$OUTPUT_XCFRAMEWORK" ]]; then
  echo "Expected output missing: $OUTPUT_XCFRAMEWORK" >&2
  exit 1
fi

rm -rf "$DEST_XCFRAMEWORK"
mkdir -p "$(dirname "$DEST_XCFRAMEWORK")"
rsync -a "$OUTPUT_XCFRAMEWORK/" "$DEST_XCFRAMEWORK/"

# Ghostty 1.3.0's "universal" xcframework now includes iOS slices too.
# Magent is macOS-only, so keep the installed xcframework trimmed to the
# tracked macOS layout and avoid leaving local iOS archives behind.
rm -rf "$DEST_XCFRAMEWORK/ios-arm64" "$DEST_XCFRAMEWORK/ios-arm64-simulator"
plutil -replace AvailableLibraries -json '[
  {
    "BinaryPath": "libghostty.a",
    "HeadersPath": "Headers",
    "LibraryIdentifier": "macos-arm64_x86_64",
    "LibraryPath": "libghostty.a",
    "SupportedArchitectures": ["arm64", "x86_64"],
    "SupportedPlatform": "macos"
  }
]' "$DEST_XCFRAMEWORK/Info.plist"

printf '%s\n' "$GHOSTTY_REF" > "$DEST_REF_FILE"

echo "Installed $DEST_XCFRAMEWORK from $GHOSTTY_REF"
