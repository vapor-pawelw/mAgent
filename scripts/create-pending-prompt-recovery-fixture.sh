#!/usr/bin/env bash

# Creates a Magent pending-prompt recovery fixture in /tmp for manual UI testing.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/create-pending-prompt-recovery-fixture.sh [options]

Options:
  --scope newThread|newTab     Recovery scope to create. Default: newThread.
  --project-id UUID            Project id for newThread recovery. Defaults to first configured project.
  --thread-id UUID             Thread id for newTab recovery. Defaults to first active thread.
  --prompt TEXT                Prompt text to recover.
  --description TEXT           Optional thread description for newThread recovery.
  --branch-name TEXT           Optional branch name for newThread recovery.
  --selection TEXT             Original picker selection. Default: terminal.
  --agent-type TYPE            Optional agent type raw value, e.g. claude or codex.
  --settings PATH              Magent settings.json path.
  --threads PATH               Magent threads.json path.
  --dry-run                    Print JSON instead of writing /tmp file.
  -h, --help                   Show this help.

Examples:
  scripts/create-pending-prompt-recovery-fixture.sh
  scripts/create-pending-prompt-recovery-fixture.sh --prompt "Recover me" --dry-run
  scripts/create-pending-prompt-recovery-fixture.sh --scope newTab --thread-id <UUID>
EOF
}

scope="newThread"
project_id=""
thread_id=""
prompt="TEST lost prompt recovery toolbar button. You can discard this."
description="Lost prompt reminder test"
branch_name="test/lost-prompt-reminder"
selection_raw="terminal"
agent_type=""
settings_path="${MAGENT_SETTINGS_PATH:-$HOME/Library/Application Support/Magent/settings.json}"
threads_path="${MAGENT_THREADS_PATH:-$HOME/Library/Application Support/Magent/threads.json}"
dry_run=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scope)
      scope="${2:?Missing value for --scope}"
      shift 2
      ;;
    --project-id)
      project_id="${2:?Missing value for --project-id}"
      shift 2
      ;;
    --thread-id)
      thread_id="${2:?Missing value for --thread-id}"
      shift 2
      ;;
    --prompt)
      prompt="${2:?Missing value for --prompt}"
      shift 2
      ;;
    --description)
      description="${2:?Missing value for --description}"
      shift 2
      ;;
    --branch-name)
      branch_name="${2:?Missing value for --branch-name}"
      shift 2
      ;;
    --selection)
      selection_raw="${2:?Missing value for --selection}"
      shift 2
      ;;
    --agent-type)
      agent_type="${2:?Missing value for --agent-type}"
      shift 2
      ;;
    --settings)
      settings_path="${2:?Missing value for --settings}"
      shift 2
      ;;
    --threads)
      threads_path="${2:?Missing value for --threads}"
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "$scope" in
  newThread|newTab) ;;
  *)
    echo "--scope must be newThread or newTab" >&2
    exit 2
    ;;
esac

export MAGENT_FIXTURE_SCOPE="$scope"
export MAGENT_FIXTURE_PROJECT_ID="$project_id"
export MAGENT_FIXTURE_THREAD_ID="$thread_id"
export MAGENT_FIXTURE_PROMPT="$prompt"
export MAGENT_FIXTURE_DESCRIPTION="$description"
export MAGENT_FIXTURE_BRANCH_NAME="$branch_name"
export MAGENT_FIXTURE_SELECTION_RAW="$selection_raw"
export MAGENT_FIXTURE_AGENT_TYPE="$agent_type"
export MAGENT_FIXTURE_SETTINGS_PATH="$settings_path"
export MAGENT_FIXTURE_THREADS_PATH="$threads_path"
export MAGENT_FIXTURE_DRY_RUN="$dry_run"

/usr/bin/python3 <<'PY'
import json
import os
import sys
import time
import uuid
from pathlib import Path


def load_enveloped_json(path: Path):
    try:
        payload = json.loads(path.read_text())
    except FileNotFoundError:
        raise SystemExit(f"Missing file: {path}")
    return payload.get("data", payload)


def first_configured_project_id(settings_path: Path) -> str:
    settings = load_enveloped_json(settings_path)
    projects = settings.get("projects", [])
    if not projects:
        raise SystemExit(f"No projects found in {settings_path}")
    project_id = projects[0].get("id")
    if not project_id:
        raise SystemExit(f"First project in {settings_path} has no id")
    return project_id


def first_active_thread_id(threads_path: Path) -> str:
    threads = load_enveloped_json(threads_path)
    if not isinstance(threads, list):
        raise SystemExit(f"Expected thread list in {threads_path}")
    for thread in threads:
        if not thread.get("isArchived", False):
            thread_id = thread.get("id")
            if thread_id:
                return thread_id
    raise SystemExit(f"No active threads found in {threads_path}")


scope = os.environ["MAGENT_FIXTURE_SCOPE"]
settings_path = Path(os.environ["MAGENT_FIXTURE_SETTINGS_PATH"]).expanduser()
threads_path = Path(os.environ["MAGENT_FIXTURE_THREADS_PATH"]).expanduser()
project_id = os.environ["MAGENT_FIXTURE_PROJECT_ID"].strip()
thread_id = os.environ["MAGENT_FIXTURE_THREAD_ID"].strip()
agent_type = os.environ["MAGENT_FIXTURE_AGENT_TYPE"].strip()
dry_run = os.environ["MAGENT_FIXTURE_DRY_RUN"] == "1"

if scope == "newThread":
    project_id = project_id or first_configured_project_id(settings_path)
    thread_id_for_record = None
elif scope == "newTab":
    thread_id = thread_id or first_active_thread_id(threads_path)
    project_id = None
    thread_id_for_record = thread_id
else:
    raise SystemExit(f"Unsupported scope: {scope}")

record = {
    "scopeKind": scope,
    "projectId": project_id,
    "threadId": thread_id_for_record,
    "prompt": os.environ["MAGENT_FIXTURE_PROMPT"],
    "description": os.environ["MAGENT_FIXTURE_DESCRIPTION"] or None,
    "branchName": os.environ["MAGENT_FIXTURE_BRANCH_NAME"] or None,
    "agentType": agent_type or None,
    # Swift JSONEncoder's default Date encoding is seconds since 2001-01-01.
    "createdAt": time.time() - 978307200,
    "modelId": None,
    "reasoningLevel": None,
    "selectionRaw": os.environ["MAGENT_FIXTURE_SELECTION_RAW"] or None,
}

if dry_run:
    print(json.dumps(record, indent=2, sort_keys=True))
    sys.exit(0)

path = Path("/tmp") / f"magent-pending-prompt-manual-{uuid.uuid4()}.json"
path.write_text(json.dumps(record, indent=2, sort_keys=True))
print(path)
PY
