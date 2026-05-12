#!/usr/bin/env bash

# Relaunch Magent without rebuilding.
# Only builds if no existing binary is found in DerivedData.

set -euo pipefail

SCHEME="${MAGENT_SCHEME:-Magent}"
CONFIGURATION="${MAGENT_CONFIGURATION:-Debug}"
APP_NAME="${MAGENT_APP_NAME:-Magent}"
WORKSPACE="${MAGENT_WORKSPACE:-Magent.xcworkspace}"

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

main() {
  local root build_dir app_path binary_path
  root="$(repo_root)"
  cd "$root"

  build_dir="$(build_dir_from_xcodebuild)"
  if [[ -z "$build_dir" ]]; then
    echo "Failed to resolve CONFIGURATION_BUILD_DIR for scheme '$SCHEME'." >&2
    exit 1
  fi

  app_path="$build_dir/$APP_NAME.app"
  binary_path="$app_path/Contents/MacOS/$APP_NAME"

  if [[ ! -f "$binary_path" ]]; then
    echo "No existing binary at $binary_path — building..."
    xcodebuild -workspace "$WORKSPACE" -scheme "$SCHEME" -configuration "$CONFIGURATION" build
    if [[ ! -f "$binary_path" ]]; then
      echo "Build did not produce expected binary at: $binary_path" >&2
      exit 1
    fi
  else
    echo "Found existing binary at $binary_path, skipping build."
  fi

  echo "Killing running $APP_NAME instances..."
  killall "$APP_NAME" 2>/dev/null || true
  wait_for_app_exit

  echo "Launching $app_path..."
  if ! open -n "$app_path"; then
    echo "open failed, launching binary directly..."
    "$binary_path" >/tmp/magent-relaunch.log 2>&1 &
  fi

  sleep 1
  verify_launched_binary "$binary_path"
}

main "$@"
