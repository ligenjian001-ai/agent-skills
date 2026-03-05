#!/bin/bash
# cc_launch.sh — Launch Claude Code in a dedicated tmux session for long-running tasks
#
# Usage: cc_launch.sh <task_id> <project_dir> [--api-billing] [--budget N]
#
# Creates tmux session cc-<task_id>, runs CC headless, streams to live.log
# On completion: writes execution_record.json, prints CC_DONE / CC_FAIL

set -euo pipefail

TASK_ID="${1:?Usage: cc_launch.sh <task_id> <project_dir> [--api-billing] [--budget N]}"
PROJECT_DIR="${2:?Usage: cc_launch.sh <task_id> <project_dir> [--api-billing] [--budget N]}"
API_BILLING=false
BUDGET="10.00"

shift 2
while [[ $# -gt 0 ]]; do
  case "$1" in
    --api-billing) API_BILLING=true; shift ;;
    --budget) BUDGET="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

TASK_DIR="/tmp/cc_tasks/${TASK_ID}"
PROMPT_FILE="${TASK_DIR}/prompt.txt"
LIVE_LOG="${TASK_DIR}/live.log"
EXEC_RECORD="${TASK_DIR}/execution_record.json"
SESSION="cc-${TASK_ID}"

# --- Validate ---
if [[ ! -d "$TASK_DIR" ]]; then
  echo "ERROR: Task directory not found: ${TASK_DIR}" >&2
  echo "Create it first: mkdir -p ${TASK_DIR}" >&2
  exit 1
fi

if [[ ! -f "$PROMPT_FILE" ]]; then
  echo "ERROR: prompt.txt not found at ${PROMPT_FILE}" >&2
  exit 1
fi

if ! command -v claude &>/dev/null; then
  echo "ERROR: 'claude' CLI not found. Install Claude Code first." >&2
  echo "  npm install -g @anthropic-ai/claude-code" >&2
  exit 1
fi

if [[ ! -d "$PROJECT_DIR" ]]; then
  echo "ERROR: Project directory not found: ${PROJECT_DIR}" >&2
  exit 1
fi

# --- Build runner script ---
# We write a runner script to avoid heredoc/quoting issues with tmux send-keys
RUNNER="${TASK_DIR}/runner.sh"
cat > "$RUNNER" <<'RUNNER_SCRIPT'
#!/bin/bash
set -euo pipefail

TASK_DIR="$1"
PROJECT_DIR="$2"
API_BILLING="$3"
BUDGET="$4"

PROMPT_FILE="${TASK_DIR}/prompt.txt"
LIVE_LOG="${TASK_DIR}/live.log"
EXEC_RECORD="${TASK_DIR}/execution_record.json"

cd "$PROJECT_DIR"

> "$LIVE_LOG"
echo "[cc-launch] Starting Claude Code..." | tee -a "$LIVE_LOG"
echo "[cc-launch] Project: ${PROJECT_DIR}" | tee -a "$LIVE_LOG"
echo "[cc-launch] Prompt: ${PROMPT_FILE}" | tee -a "$LIVE_LOG"
echo "[cc-launch] Time: $(date -Iseconds)" | tee -a "$LIVE_LOG"
echo "---" | tee -a "$LIVE_LOG"

START_TS=$(date +%s)
EXIT_CODE=0

# Build CC command
CC_CMD=(claude -p --permission-mode bypassPermissions --output-format stream-json --verbose)
if [[ "$API_BILLING" == "true" ]]; then
  CC_CMD+=(--max-budget-usd "$BUDGET")
fi

# Run CC
if cat "$PROMPT_FILE" | "${CC_CMD[@]}" 2>&1 | tee -a "$LIVE_LOG"; then
  STATUS="success"
else
  EXIT_CODE=$?
  STATUS="failed"
fi

END_TS=$(date +%s)
DURATION_S=$((END_TS - START_TS))
DURATION_MIN=$((DURATION_S / 60))
DURATION_SEC=$((DURATION_S % 60))

echo "" | tee -a "$LIVE_LOG"
echo "---" | tee -a "$LIVE_LOG"
echo "[cc-launch] Status: ${STATUS}" | tee -a "$LIVE_LOG"
echo "[cc-launch] Duration: ${DURATION_MIN}m ${DURATION_SEC}s" | tee -a "$LIVE_LOG"
echo "[cc-launch] Exit code: ${EXIT_CODE}" | tee -a "$LIVE_LOG"

# Write execution record
cat > "$EXEC_RECORD" <<EOF
{
  "task_id": "$(basename "$TASK_DIR")",
  "project": "${PROJECT_DIR}",
  "status": "${STATUS}",
  "exit_code": ${EXIT_CODE},
  "duration_seconds": ${DURATION_S},
  "duration_human": "${DURATION_MIN}m ${DURATION_SEC}s",
  "started_at": "$(date -d @${START_TS} -Iseconds)",
  "finished_at": "$(date -Iseconds)",
  "prompt_file": "${PROMPT_FILE}",
  "api_billing": ${API_BILLING},
  "live_log": "${LIVE_LOG}"
}
EOF

if [[ "$STATUS" == "success" ]]; then
  echo "CC_DONE"
else
  echo "CC_FAIL"
fi
RUNNER_SCRIPT

chmod +x "$RUNNER"

# --- Kill existing session if any ---
tmux kill-session -t "$SESSION" 2>/dev/null || true

# --- Create dedicated tmux session and launch ---
tmux new-session -d -s "$SESSION" -x 220 -y 50
sleep 0.5
tmux send-keys -t "$SESSION" "bash ${RUNNER} ${TASK_DIR} ${PROJECT_DIR} ${API_BILLING} ${BUDGET}" Enter

echo ""
echo "✅ Claude Code task launched!"
echo ""
echo "  Task ID:    ${TASK_ID}"
echo "  Session:    ${SESSION}"
echo "  Project:    ${PROJECT_DIR}"
echo "  Prompt:     ${PROMPT_FILE}"
echo "  Live log:   ${LIVE_LOG}"
echo ""
echo "📺 Monitor:"
echo "  tmux attach -t ${SESSION}              # 实时观看 (Ctrl+B D 退出)"
echo "  tail -f ${LIVE_LOG}                    # 查看日志"
echo "  bash $(dirname "$0")/cc_monitor.sh ${TASK_ID}  # 状态概览"
echo ""
echo "🛑 中断: tmux send-keys -t ${SESSION} C-c"
