#!/bin/bash
# panel_launch.sh — Launch one agent in a dedicated tmux session for panel discussion
#
# Usage: panel_launch.sh <executor> <agent_name> <task_dir> [project_dir]
#
# executor:   cc | gemini | codex
# agent_name: skeptic | pragmatist | optimist (used for session naming)
# task_dir:   /tmp/panel/{task_id}/round_N/{agent_name}/
# project_dir: optional working directory (default: /tmp)
#
# Fallback: if codex is unavailable, automatically falls back to gemini
#
# Expects: $task_dir/prompt.txt
# Produces: $task_dir/live.log, $task_dir/output.md, $task_dir/execution_record.json

set -euo pipefail

EXECUTOR="${1:?Usage: panel_launch.sh <executor> <agent_name> <task_dir> [project_dir]}"
AGENT_NAME="${2:?Usage: panel_launch.sh <executor> <agent_name> <task_dir> [project_dir]}"
TASK_DIR="${3:?Usage: panel_launch.sh <executor> <agent_name> <task_dir> [project_dir]}"
PROJECT_DIR="${4:-/tmp}"

PROMPT_FILE="${TASK_DIR}/prompt.txt"
LIVE_LOG="${TASK_DIR}/live.log"
EXEC_RECORD="${TASK_DIR}/execution_record.json"
OUTPUT_FILE="${TASK_DIR}/output.md"

# --- Executor pre-check + fallback ---
check_executor() {
  local exe="$1"
  case "$exe" in
    cc)
      if ! command -v claude &>/dev/null; then
        echo "WARN: claude CLI not found" >&2; return 1
      fi
      # Quick version check (non-interactive)
      claude --version &>/dev/null 2>&1 || { echo "WARN: claude CLI not working" >&2; return 1; }
      ;;
    gemini)
      if ! command -v gemini &>/dev/null; then
        echo "WARN: gemini CLI not found" >&2; return 1
      fi
      ;;
    codex)
      if ! command -v codex &>/dev/null; then
        echo "WARN: codex CLI not found" >&2; return 1
      fi
      if ! codex --version &>/dev/null 2>&1; then
        echo "WARN: codex CLI not working" >&2; return 1
      fi
      ;;
    *) echo "ERROR: Unknown executor '$exe'" >&2; return 1 ;;
  esac
  return 0
}

ORIGINAL_EXECUTOR="$EXECUTOR"
FALLBACK_USED=""

if ! check_executor "$EXECUTOR"; then
  if [[ "$EXECUTOR" == "codex" ]]; then
    echo "⚠️  Codex unavailable, falling back to Gemini" >&2
    EXECUTOR="gemini"
    FALLBACK_USED="codex→gemini"
    if ! check_executor "$EXECUTOR"; then
      echo "ERROR: Fallback executor gemini also unavailable" >&2
      exit 1
    fi
  else
    echo "ERROR: Executor $EXECUTOR unavailable and no fallback configured" >&2
    exit 1
  fi
fi

# Derive session name from task_dir: /tmp/panel/task123/round_0/skeptic → panel-task123-r0-skeptic
TASK_ID=$(echo "$TASK_DIR" | grep -oP 'panel/\K[^/]+')
ROUND_NUM=$(echo "$TASK_DIR" | grep -oP 'round_\K\d+')
SESSION="panel-${TASK_ID}-r${ROUND_NUM}-${AGENT_NAME}"

# --- Validate ---
if [[ ! -f "$PROMPT_FILE" ]]; then
  echo "ERROR: prompt.txt not found at ${PROMPT_FILE}" >&2
  exit 1
fi

# --- Build runner script ---
RUNNER="${TASK_DIR}/runner.sh"
cat > "$RUNNER" <<'RUNNER_SCRIPT'
#!/bin/bash
set -euo pipefail

EXECUTOR="$1"
TASK_DIR="$2"
PROJECT_DIR="$3"
AGENT_NAME="$4"
ORIGINAL_EXECUTOR="${5:-$EXECUTOR}"
FALLBACK_USED="${6:-}"

PROMPT_FILE="${TASK_DIR}/prompt.txt"
LIVE_LOG="${TASK_DIR}/live.log"
EXEC_RECORD="${TASK_DIR}/execution_record.json"
OUTPUT_FILE="${TASK_DIR}/output.md"

cd "$PROJECT_DIR"
> "$LIVE_LOG"

echo "[panel-launch] Agent: ${AGENT_NAME} (${EXECUTOR}${FALLBACK_USED:+, fallback from ${ORIGINAL_EXECUTOR}})" | tee -a "$LIVE_LOG"
echo "[panel-launch] Time: $(date -Iseconds)" | tee -a "$LIVE_LOG"
echo "---" | tee -a "$LIVE_LOG"

START_TS=$(date +%s)
EXIT_CODE=0

case "$EXECUTOR" in
  cc)
    if cat "$PROMPT_FILE" | claude -p \
        --permission-mode bypassPermissions \
        --output-format stream-json \
        --verbose 2>&1 | tee -a "$LIVE_LOG"; then
      STATUS="success"
    else
      EXIT_CODE=$?
      STATUS="failed"
    fi
    ;;
  gemini)
    PROMPT_CONTENT=$(cat "$PROMPT_FILE")
    # Filter stderr noise: redirect WARN messages to /dev/null
    if gemini -p "$PROMPT_CONTENT" \
        --approval-mode plan \
        -o text 2> >(grep -v '^\[WARN\]' | grep -v '^Approval mode' >&2) | tee -a "$LIVE_LOG"; then
      STATUS="success"
    else
      EXIT_CODE=$?
      STATUS="failed"
    fi
    ;;
  codex)
    PROMPT_CONTENT=$(cat "$PROMPT_FILE")
    if codex exec --skip-git-repo-check \
        -c 'sandbox_permissions=["disk-full-read-access"]' \
        "$PROMPT_CONTENT" 2>&1 | tee -a "$LIVE_LOG"; then
      STATUS="success"
    else
      EXIT_CODE=$?
      STATUS="failed"
    fi
    ;;
esac

END_TS=$(date +%s)
DURATION_S=$((END_TS - START_TS))
DURATION_MIN=$((DURATION_S / 60))
DURATION_SEC=$((DURATION_S % 60))

echo "" | tee -a "$LIVE_LOG"
echo "---" | tee -a "$LIVE_LOG"
echo "[panel-launch] Status: ${STATUS}" | tee -a "$LIVE_LOG"
echo "[panel-launch] Duration: ${DURATION_MIN}m ${DURATION_SEC}s" | tee -a "$LIVE_LOG"

# Extract output — strip JSON wrapper for CC, keep text for gemini/codex
if [[ "$EXECUTOR" == "cc" ]]; then
  # Extract text content from CC stream-json output
  if command -v python3 &>/dev/null; then
    python3 -c "
import json, sys
text_parts = []
for line in open('${LIVE_LOG}'):
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
        if obj.get('type') == 'result':
            text_parts.append(obj.get('result', ''))
        elif obj.get('type') == 'assistant' and 'content' in obj:
            for block in obj['content']:
                if block.get('type') == 'text':
                    text_parts.append(block['text'])
    except (json.JSONDecodeError, KeyError, TypeError):
        pass
# Use result if available, otherwise concatenate assistant text
if text_parts:
    print(text_parts[-1] if any(True for l in open('${LIVE_LOG}') if '\"type\":\"result\"' in l) else '\n'.join(text_parts))
else:
    print('[No structured output extracted. Check live.log]')
" > "$OUTPUT_FILE" 2>/dev/null || cp "$LIVE_LOG" "$OUTPUT_FILE"
  else
    cp "$LIVE_LOG" "$OUTPUT_FILE"
  fi
else
  # For gemini/codex, strip log lines + WARN noise
  grep -v '^\[panel-launch\]' "$LIVE_LOG" \
    | grep -v '^---$' \
    | grep -v '^\[WARN\]' \
    | grep -v '^Approval mode' \
    > "$OUTPUT_FILE" || cp "$LIVE_LOG" "$OUTPUT_FILE"
fi

# Write execution record
FALLBACK_NOTE=""
if [[ -n "$FALLBACK_USED" ]]; then
  FALLBACK_NOTE=", \"fallback\": \"${FALLBACK_USED}\", \"original_executor\": \"${ORIGINAL_EXECUTOR}\""
fi

cat > "$EXEC_RECORD" <<EOF
{
  "agent": "${AGENT_NAME}",
  "executor": "${EXECUTOR}",
  "status": "${STATUS}",
  "exit_code": ${EXIT_CODE},
  "duration_seconds": ${DURATION_S},
  "duration_human": "${DURATION_MIN}m ${DURATION_SEC}s",
  "started_at": "$(date -d @${START_TS} -Iseconds)",
  "finished_at": "$(date -Iseconds)",
  "prompt_file": "${PROMPT_FILE}",
  "output_file": "${OUTPUT_FILE}"${FALLBACK_NOTE}
}
EOF

if [[ "$STATUS" == "success" ]]; then
  echo "PANEL_DONE"
else
  echo "PANEL_FAIL"
fi
RUNNER_SCRIPT

chmod +x "$RUNNER"

# --- Kill existing session if any ---
tmux kill-session -t "$SESSION" 2>/dev/null || true

# --- Create dedicated tmux session and launch ---
tmux new-session -d -s "$SESSION" -x 220 -y 50
sleep 0.3
tmux send-keys -t "$SESSION" "bash ${RUNNER} ${EXECUTOR} ${TASK_DIR} ${PROJECT_DIR} ${AGENT_NAME} ${ORIGINAL_EXECUTOR} '${FALLBACK_USED}'" Enter

echo ""
if [[ -n "$FALLBACK_USED" ]]; then
  echo "✅ Panel agent launched: ${AGENT_NAME} (${EXECUTOR}, fallback from ${ORIGINAL_EXECUTOR})"
else
  echo "✅ Panel agent launched: ${AGENT_NAME} (${EXECUTOR})"
fi
echo "   Session:  ${SESSION}"
echo "   Live log: ${LIVE_LOG}"
echo "   Output:   ${OUTPUT_FILE}"
