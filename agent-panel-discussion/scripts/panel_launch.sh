#!/bin/bash
# panel_launch.sh — Launch one agent in a dedicated tmux session for panel discussion
#
# Usage: panel_launch.sh <executor> <agent_name> <task_dir> [project_dir]
#
# executor:   cc | gemini | codex | deepseek
# agent_name: skeptic | pragmatist | optimist (used for session naming)
# task_dir:   /tmp/panel/{task_id}/round_N/{agent_name}/
# project_dir: optional working directory (default: /tmp)
#
# Fallback: if codex is unavailable, automatically falls back to gemini
#
# Expects: $task_dir/prompt.txt
# Produces: $task_dir/live.log, $task_dir/output.md, $task_dir/execution_record.json
#
# This is a thin wrapper around task-delegate/scripts/task_launch.sh.

set -euo pipefail

EXECUTOR="${1:?Usage: panel_launch.sh <executor> <agent_name> <task_dir> [project_dir]}"
AGENT_NAME="${2:?Usage: panel_launch.sh <executor> <agent_name> <task_dir> [project_dir]}"
TASK_DIR="${3:?Usage: panel_launch.sh <executor> <agent_name> <task_dir> [project_dir]}"
PROJECT_DIR="${4:-/tmp}"

# Derive session name: /tmp/panel/task123/round_0/skeptic → panel-task123-r0-skeptic
TASK_ID=$(echo "$TASK_DIR" | grep -oP 'panel/\K[^/]+')
ROUND_NUM=$(echo "$TASK_DIR" | grep -oP 'round_\K\d+')
SESSION="panel-${TASK_ID}-r${ROUND_NUM}-${AGENT_NAME}"

# Locate task-delegate launcher
SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"
TASK_DELEGATE_DIR="$(dirname "$SKILL_DIR")/../task-delegate/scripts"
# Also check symlinked .agent/skills path
if [[ ! -f "${TASK_DELEGATE_DIR}/task_launch.sh" ]]; then
  TASK_DELEGATE_DIR="/home/lgj/agent-skills/task-delegate/scripts"
fi
TASK_LAUNCH="${TASK_DELEGATE_DIR}/task_launch.sh"

if [[ ! -f "$TASK_LAUNCH" ]]; then
  echo "ERROR: task_launch.sh not found at ${TASK_LAUNCH}" >&2
  echo "Ensure task-delegate skill is installed." >&2
  exit 1
fi

# Post-run hook: extract output.md from live.log
POST_RUN="${SKILL_DIR}/panel_extract_output.sh"

# Extra record fields for panel context
EXTRA_RECORD="{\"agent\": \"${AGENT_NAME}\", \"output_file\": \"${TASK_DIR}/output.md\"}"

# Determine fallback
FALLBACK_ARG=""
if [[ "$EXECUTOR" == "codex" ]]; then
  FALLBACK_ARG="--fallback gemini"
fi

# Launch via task-delegate with panel-specific overrides
bash "$TASK_LAUNCH" \
  "${TASK_ID}_r${ROUND_NUM}_${AGENT_NAME}" \
  "$PROJECT_DIR" \
  --backend "$EXECUTOR" \
  --task-dir "$TASK_DIR" \
  --session "$SESSION" \
  --post-run "$POST_RUN" \
  --extra-record "$EXTRA_RECORD" \
  --done-marker "PANEL_DONE" \
  $FALLBACK_ARG
