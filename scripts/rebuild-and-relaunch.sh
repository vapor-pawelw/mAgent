#!/usr/bin/env bash

set -euo pipefail

SCHEME="${MAGENT_SCHEME:-Magent}"
CONFIGURATION="${MAGENT_CONFIGURATION:-Debug}"
APP_NAME="${MAGENT_APP_NAME:-Magent}"
WORKSPACE="${MAGENT_WORKSPACE:-Magent.xcworkspace}"
LOG_ROOT="${MAGENT_RELAUNCH_LOG_ROOT:-$HOME/Library/Logs/Magent/relaunch}"
GHOSTTY_LIB_REL="Libraries/GhosttyKit.xcframework/macos-arm64_x86_64/libghostty.a"
GHOSTTY_REF_METADATA_REL="Libraries/GhosttyKit.xcframework/.ghostty-ref"
PINNED_GHOSTTY_REF="${MAGENT_GHOSTTY_REF:-v1.3.1}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/.."
  pwd
}

build_dir_from_xcodebuild() {
  xcodebuild -workspace "$WORKSPACE" -scheme "$SCHEME" -configuration "$CONFIGURATION" -showBuildSettings 2>/dev/null \
    | sed -n 's/^[[:space:]]*CONFIGURATION_BUILD_DIR = //p' \
    | head -n1
}

running_app_pids() {
  pgrep -x "$APP_NAME" 2>/dev/null || true
}

wait_for_app_exit() {
  local deadline pids
  deadline=$((SECONDS + 10))
  while [[ "$SECONDS" -lt "$deadline" ]]; do
    pids="$(running_app_pids)"
    if [[ -z "$pids" ]]; then
      return 0
    fi
    sleep 0.2
  done

  pids="$(running_app_pids)"
  if [[ -n "$pids" ]]; then
    echo "Running $APP_NAME instance(s) did not exit after SIGTERM; forcing:" >&2
    echo "$pids" >&2
    kill -9 $pids 2>/dev/null || true
  fi

  deadline=$((SECONDS + 5))
  while [[ "$SECONDS" -lt "$deadline" ]]; do
    pids="$(running_app_pids)"
    if [[ -z "$pids" ]]; then
      return 0
    fi
    sleep 0.2
  done

  echo "Failed to stop existing $APP_NAME process(es):" >&2
  running_app_pids >&2
  return 1
}

verify_launched_binary() {
  local expected_binary="$1"
  local pids pid command_line matched
  pids="$(running_app_pids)"
  if [[ -z "$pids" ]]; then
    echo "Launch failed: no running '$APP_NAME' process found." >&2
    return 1
  fi

  matched=0
  echo "Running PID(s):"
  for pid in $pids; do
    command_line="$(ps -ww -p "$pid" -o command= 2>/dev/null || true)"
    echo "$pid $command_line"
    if [[ "$command_line" == "$expected_binary"* ]]; then
      matched=1
    fi
  done

  if [[ "$matched" -ne 1 ]]; then
    echo "Launched process is not using expected binary:" >&2
    echo "  $expected_binary" >&2
    return 1
  fi
}

create_run_log_dir() {
  local timestamp run_dir
  timestamp="$(date +"%Y%m%d-%H%M%S")"
  run_dir="$LOG_ROOT/$timestamp"
  mkdir -p "$run_dir"
  ln -sfn "$run_dir" "$LOG_ROOT/latest"
  printf '%s\n' "$run_dir"
}

write_launch_metadata() {
  local run_dir="$1"
  local app_path="$2"
  local binary_path="$3"
  {
    echo "timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo "repo=$(pwd)"
    echo "branch=$(git branch --show-current 2>/dev/null || true)"
    echo "head=$(git rev-parse HEAD 2>/dev/null || true)"
    echo "scheme=$SCHEME"
    echo "configuration=$CONFIGURATION"
    echo "app_path=$app_path"
    echo "binary_path=$binary_path"
    echo "log_dir=$run_dir"
    echo
    echo "git status:"
    git status --short --branch 2>/dev/null || true
  } >"$run_dir/metadata.txt"
}

start_unified_log_capture() {
  local run_dir="$1"
  local predicate
  predicate="process == \"$APP_NAME\" OR process == \"com.apple.WebKit.WebContent\" OR eventMessage CONTAINS[c] \"DiffViewer\" OR eventMessage CONTAINS[c] \"DiffPanel\" OR eventMessage CONTAINS[c] \"DiffRenderer\" OR eventMessage CONTAINS[c] \"CRASH\""
  log stream --style compact --level debug --predicate "$predicate" >"$run_dir/unified.log" 2>&1 &
  printf '%s\n' "$!"
}

monitor_launched_app() {
  local binary_path="$1"
  local log_pid="$2"
  local run_dir="$3"
  local start_epoch="$4"

  (
    set +e
    MAGENT_RELAUNCH_LOG_DIR="$run_dir" "$binary_path" >"$run_dir/stdout-stderr.log" 2>&1 &
    local app_pid=$!
    echo "$app_pid" >"$run_dir/pid.txt"

    wait "$app_pid"
    local exit_code=$?
    local ended_at
    ended_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    {
      echo "ended_at=$ended_at"
      echo "exit_code=$exit_code"
    } >"$run_dir/exit.txt"

    sleep 2

    log show --style compact --info --debug --start "@$start_epoch" \
      --predicate "process == \"$APP_NAME\" OR process == \"com.apple.WebKit.WebContent\" OR eventMessage CONTAINS[c] \"DiffViewer\" OR eventMessage CONTAINS[c] \"DiffPanel\" OR eventMessage CONTAINS[c] \"DiffRenderer\" OR eventMessage CONTAINS[c] \"CRASH\"" \
      >"$run_dir/unified-after-exit.log" 2>&1

    find "$HOME/Library/Logs/DiagnosticReports" /Library/Logs/DiagnosticReports \
      -maxdepth 1 -type f -newer "$run_dir/metadata.txt" \
      \( -iname "*$APP_NAME*" -o -iname "*magent*" -o -iname "JetsamEvent-*.ips" \) \
      -print -exec cp {} "$run_dir/" \; >"$run_dir/diagnostic-reports.txt" 2>&1

    kill "$log_pid" >/dev/null 2>&1 || true
  ) &
}

launch_with_logging() {
  local app_path="$1"
  local binary_path="$2"
  local run_dir="${3:-}"
  local log_pid start_epoch

  if [[ -z "$run_dir" ]]; then
    run_dir="$(create_run_log_dir)"
  fi
  write_launch_metadata "$run_dir" "$app_path" "$binary_path"
  start_epoch="$(date +%s)"
  log_pid="$(start_unified_log_capture "$run_dir")"

  echo "Logs: $run_dir"
  echo "Launching $binary_path..."
  echo "$log_pid" >"$run_dir/log-stream.pid"
  monitor_launched_app "$binary_path" "$log_pid" "$run_dir" "$start_epoch"
}

refresh_workspace_with_tuist() {
  local workspace="$1"

  echo "Refreshing $workspace via Tuist..."
  if mise x -- tuist generate --no-open; then
    return
  fi

  echo "Tuist generate failed. Running tuist install and retrying..."
  mise x -- tuist install
  echo "Refreshing $workspace via Tuist (retry)..."
  mise x -- tuist generate --no-open
}

ensure_build_prerequisites() {
  local root="$1"
  local ghostty_lib="$root/$GHOSTTY_LIB_REL"
  local ghostty_ref_file="$root/$GHOSTTY_REF_METADATA_REL"
  local needs_mise=0
  local installed_ghostty_ref=""

  if [[ ! -f "$ghostty_lib" ]]; then
    echo "Missing $GHOSTTY_LIB_REL"
    needs_mise=1
  fi

  if [[ "$needs_mise" -eq 0 ]]; then
    if [[ ! -f "$ghostty_ref_file" ]]; then
      echo "Missing Ghostty ref metadata at $GHOSTTY_REF_METADATA_REL"
      needs_mise=1
    else
      installed_ghostty_ref="$(tr -d '\n' < "$ghostty_ref_file")"
      if [[ "$installed_ghostty_ref" != "$PINNED_GHOSTTY_REF" ]]; then
        echo "GhosttyKit is built from $installed_ghostty_ref, expected $PINNED_GHOSTTY_REF"
        needs_mise=1
      fi
    fi
  fi

  if [[ "$needs_mise" -eq 0 ]]; then
    if command -v mise >/dev/null 2>&1; then
      refresh_workspace_with_tuist "$WORKSPACE"
      return
    fi

    if [[ ! -d "$root/$WORKSPACE" ]]; then
      echo "Missing $WORKSPACE and mise is not installed. Cannot generate project files." >&2
      exit 1
    fi

    return
  fi

  require_cmd mise

  echo "Installing toolchain with mise..."
  mise install

  if [[ ! -f "$ghostty_lib" ]]; then
    if [[ ! -x "$root/scripts/bootstrap-ghosttykit.sh" ]]; then
      echo "Missing bootstrap script: scripts/bootstrap-ghosttykit.sh" >&2
      exit 1
    fi

    echo "Bootstrapping GhosttyKit.xcframework..."
    mise x -- env GHOSTTY_REF="$PINNED_GHOSTTY_REF" "$root/scripts/bootstrap-ghosttykit.sh"
  fi

  refresh_workspace_with_tuist "$WORKSPACE"

  if [[ ! -f "$ghostty_lib" ]]; then
    echo "Still missing $GHOSTTY_LIB_REL after bootstrap." >&2
    exit 1
  fi

  if [[ ! -d "$root/$WORKSPACE" ]]; then
    echo "Still missing $WORKSPACE after Tuist generate." >&2
    exit 1
  fi
}

main() {
  require_cmd xcodebuild
  require_cmd sed
  require_cmd pgrep

  local root build_dir app_path binary_path
  root="$(repo_root)"
  cd "$root"
  ensure_build_prerequisites "$root"

  build_dir="$(build_dir_from_xcodebuild)"
  if [[ -z "$build_dir" ]]; then
    echo "Failed to resolve CONFIGURATION_BUILD_DIR for scheme '$SCHEME'." >&2
    exit 1
  fi

  app_path="$build_dir/$APP_NAME.app"
  binary_path="$app_path/Contents/MacOS/$APP_NAME"

  echo "Build products: $build_dir"
  local run_dir
  run_dir="$(create_run_log_dir)"
  write_launch_metadata "$run_dir" "$app_path" "$binary_path"

  echo "Logs: $run_dir"
  echo "Building $SCHEME ($CONFIGURATION)..."
  xcodebuild -workspace "$WORKSPACE" -scheme "$SCHEME" -configuration "$CONFIGURATION" build 2>&1 | tee "$run_dir/build.log"

  if [[ ! -d "$app_path" ]]; then
    echo "Built app not found at: $app_path" >&2
    exit 1
  fi

  echo "Killing running $APP_NAME instances..."
  killall "$APP_NAME" 2>/dev/null || true
  wait_for_app_exit

  launch_with_logging "$app_path" "$binary_path" "$run_dir"

  sleep 1
  verify_launched_binary "$binary_path"
}

main "$@"
