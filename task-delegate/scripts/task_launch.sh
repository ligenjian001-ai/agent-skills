#!/bin/bash
# task_launch.sh — Launch a task in a dedicated tmux session with any backend
#
# Usage: task_launch.sh <task_id> <project_dir> [OPTIONS]
#
# Options:
#   --backend cc|codex|gemini|deepseek   Backend to use (default: cc)
#   --api-billing                         Enable API billing for CC (adds --max-budget-usd)
#   --budget N                            Budget cap (default: 10.00)
#   --task-dir DIR                        Override task directory (default: ~/.task-delegate/<task_id>)
#   --session NAME                        Override tmux session name (default: task-<task_id>)
#   --fallback BACKEND                    Fallback backend if primary unavailable
#   --post-run SCRIPT                     Script to run after backend completes (in-session, receives task_dir as $1)
#   --extra-record JSON                   Extra JSON fields to merge into execution_record.json
#   --done-marker TEXT                    Completion marker text (default: TASK_DONE / TASK_FAIL)
#
# Creates tmux session, runs the chosen backend headless, streams to live.log
# On completion: writes execution_record.json, prints done marker
#
# Default IPC directory: ~/.task-delegate/<task_id>/
# Expects: <task_dir>/prompt.txt

set -euo pipefail

TASK_ID="${1:?Usage: task_launch.sh <task_id> <project_dir> [OPTIONS]}"
PROJECT_DIR="${2:?Usage: task_launch.sh <task_id> <project_dir> [OPTIONS]}"
BACKEND="cc"
API_BILLING=false
BUDGET="10.00"
TASK_DIR=""
SESSION=""
FALLBACK=""
POST_RUN=""
EXTRA_RECORD=""
DONE_MARKER_OK="TASK_DONE"
DONE_MARKER_FAIL="TASK_FAIL"

shift 2
while [[ $# -gt 0 ]]; do
  case "$1" in
    --backend) BACKEND="$2"; shift 2 ;;
    --api-billing) API_BILLING=true; shift ;;
    --budget) BUDGET="$2"; shift 2 ;;
    --task-dir) TASK_DIR="$2"; shift 2 ;;
    --session) SESSION="$2"; shift 2 ;;
    --fallback) FALLBACK="$2"; shift 2 ;;
    --post-run) POST_RUN="$2"; shift 2 ;;
    --extra-record) EXTRA_RECORD="$2"; shift 2 ;;
    --done-marker) DONE_MARKER_OK="$2"; DONE_MARKER_FAIL="${2}_FAIL"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

# Defaults
[[ -z "$TASK_DIR" ]] && TASK_DIR="${HOME}/.task-delegate/${TASK_ID}"
[[ -z "$SESSION" ]] && SESSION="task-${TASK_ID}"

PROMPT_FILE="${TASK_DIR}/prompt.txt"
LIVE_LOG="${TASK_DIR}/live.log"
EXEC_RECORD="${TASK_DIR}/execution_record.json"

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

if [[ ! -d "$PROJECT_DIR" ]]; then
  echo "ERROR: Project directory not found: ${PROJECT_DIR}" >&2
  exit 1
fi

# --- Backend validation with fallback ---
check_backend() {
  local be="$1"
  case "$be" in
    cc) command -v claude &>/dev/null && claude --version &>/dev/null 2>&1 ;;
    codex) command -v codex &>/dev/null && codex --version &>/dev/null 2>&1 ;;
    gemini) command -v gemini &>/dev/null ;;
    deepseek) [[ -n "${DEEPSEEK_API_KEY:-}" ]] ;;
    *) return 1 ;;
  esac
}

ORIGINAL_BACKEND="$BACKEND"
FALLBACK_USED=""

if ! check_backend "$BACKEND"; then
  if [[ -n "$FALLBACK" ]] && check_backend "$FALLBACK"; then
    echo "⚠️  ${BACKEND} unavailable, falling back to ${FALLBACK}" >&2
    FALLBACK_USED="${BACKEND}→${FALLBACK}"
    BACKEND="$FALLBACK"
  else
    echo "ERROR: Backend '${BACKEND}' unavailable${FALLBACK:+ (fallback '${FALLBACK}' also unavailable)}" >&2
    exit 1
  fi
fi

# --- Build runner script ---
# Written as a file to avoid heredoc/quoting issues with tmux send-keys
RUNNER="${TASK_DIR}/runner.sh"
cat > "$RUNNER" <<'RUNNER_SCRIPT'
#!/bin/bash
set -euo pipefail

TASK_DIR="$1"
PROJECT_DIR="$2"
BACKEND="$3"
API_BILLING="$4"
BUDGET="$5"
DONE_MARKER_OK="$6"
DONE_MARKER_FAIL="$7"
POST_RUN="${8:-}"
EXTRA_RECORD="${9:-}"

PROMPT_FILE="${TASK_DIR}/prompt.txt"
LIVE_LOG="${TASK_DIR}/live.log"
EXEC_RECORD="${TASK_DIR}/execution_record.json"

cd "$PROJECT_DIR"

> "$LIVE_LOG"
echo "[task-launch] Starting backend: ${BACKEND}" | tee -a "$LIVE_LOG"
echo "[task-launch] Project: ${PROJECT_DIR}" | tee -a "$LIVE_LOG"
echo "[task-launch] Prompt: ${PROMPT_FILE}" | tee -a "$LIVE_LOG"
echo "[task-launch] Time: $(date -Iseconds)" | tee -a "$LIVE_LOG"
echo "---" | tee -a "$LIVE_LOG"

START_TS=$(date +%s)
EXIT_CODE=0

case "$BACKEND" in
  cc)
    CC_CMD=(claude -p --permission-mode bypassPermissions --output-format stream-json --verbose)
    if [[ "$API_BILLING" == "true" ]]; then
      CC_CMD+=(--max-budget-usd "$BUDGET")
    fi
    if cat "$PROMPT_FILE" | "${CC_CMD[@]}" 2>&1 | tee -a "$LIVE_LOG"; then
      STATUS="success"
    else
      EXIT_CODE=$?
      STATUS="failed"
    fi
    ;;
  codex)
    PROMPT_CONTENT=$(cat "$PROMPT_FILE")
    if codex exec --skip-git-repo-check \
        -c 'sandbox_permissions=["disk-full-read-access","disk-write"]' \
        "$PROMPT_CONTENT" 2>&1 | tee -a "$LIVE_LOG"; then
      STATUS="success"
    else
      EXIT_CODE=$?
      STATUS="failed"
    fi
    ;;
  gemini)
    PROMPT_CONTENT=$(cat "$PROMPT_FILE")
    if gemini -p "$PROMPT_CONTENT" \
        --approval-mode yolo \
        -o text 2> >(grep -v '^\[WARN\]' | grep -v '^Approval mode' >&2) | tee -a "$LIVE_LOG"; then
      STATUS="success"
    else
      EXIT_CODE=$?
      STATUS="failed"
    fi
    ;;
  deepseek)
    # DeepSeek via API — reads DEEPSEEK_API_KEY from env
    DEEPSEEK_MODEL="${DEEPSEEK_MODEL:-deepseek-chat}"
    DEEPSEEK_URL="${DEEPSEEK_API_URL:-https://api.deepseek.com/v1/chat/completions}"

    PAYLOAD=$(python3 -c "
import json, sys
prompt = sys.stdin.read()
print(json.dumps({
    'model': '${DEEPSEEK_MODEL}',
    'messages': [{'role': 'user', 'content': prompt}],
    'stream': False,
    'max_tokens': 8192
}))
" < "$PROMPT_FILE")

    RESPONSE=$(curl -s -X POST "$DEEPSEEK_URL" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer ${DEEPSEEK_API_KEY}" \
      -d "$PAYLOAD" 2>&1 | tee -a "$LIVE_LOG")

    if echo "$RESPONSE" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if 'choices' in data:
    print(data['choices'][0]['message']['content'])
else:
    print(json.dumps(data, indent=2))
    sys.exit(1)
" 2>/dev/null; then
      STATUS="success"
    else
      EXIT_CODE=1
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
echo "[task-launch] Status: ${STATUS}" | tee -a "$LIVE_LOG"
echo "[task-launch] Duration: ${DURATION_MIN}m ${DURATION_SEC}s" | tee -a "$LIVE_LOG"
echo "[task-launch] Exit code: ${EXIT_CODE}" | tee -a "$LIVE_LOG"

# Write execution record
cat > "$EXEC_RECORD" <<EOF
{
  "task_id": "$(basename "$TASK_DIR")",
  "backend": "${BACKEND}",
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

# Merge extra record fields if provided
if [[ -n "$EXTRA_RECORD" ]]; then
  python3 -c "
import json, sys
with open('$EXEC_RECORD') as f:
    rec = json.load(f)
extra = json.loads('$EXTRA_RECORD')
rec.update(extra)
with open('$EXEC_RECORD', 'w') as f:
    json.dump(rec, f, indent=2)
" 2>/dev/null || true
fi

# Run post-run script if provided
if [[ -n "$POST_RUN" && -f "$POST_RUN" ]]; then
  echo "[task-launch] Running post-run script: ${POST_RUN}" | tee -a "$LIVE_LOG"
  bash "$POST_RUN" "$TASK_DIR" "$BACKEND" "$STATUS" 2>&1 | tee -a "$LIVE_LOG" || true
fi

if [[ "$STATUS" == "success" ]]; then
  echo "$DONE_MARKER_OK"
else
  echo "$DONE_MARKER_FAIL"
fi
RUNNER_SCRIPT

chmod +x "$RUNNER"

# --- Kill existing session if any ---
tmux kill-session -t "$SESSION" 2>/dev/null || true

# --- Create dedicated tmux session and launch ---
tmux new-session -d -s "$SESSION" -x 220 -y 50
sleep 0.5

# Escape extra_record for shell argument passing
EXTRA_RECORD_ESC="${EXTRA_RECORD//\"/\\\"}"

tmux send-keys -t "$SESSION" "bash ${RUNNER} '${TASK_DIR}' '${PROJECT_DIR}' '${BACKEND}' '${API_BILLING}' '${BUDGET}' '${DONE_MARKER_OK}' '${DONE_MARKER_FAIL}' '${POST_RUN}' '${EXTRA_RECORD_ESC}'" Enter

echo ""
if [[ -n "$FALLBACK_USED" ]]; then
  echo "✅ Task launched! (${BACKEND}, fallback from ${ORIGINAL_BACKEND})"
else
  echo "✅ Task launched!"
fi
echo ""
echo "  Task ID:    ${TASK_ID}"
echo "  Backend:    ${BACKEND}"
echo "  Session:    ${SESSION}"
echo "  Project:    ${PROJECT_DIR}"
echo "  Prompt:     ${PROMPT_FILE}"
echo "  Live log:   ${LIVE_LOG}"
echo ""
echo "📺 Monitor:"
echo "  tmux attach -t ${SESSION}              # 实时观看 (Ctrl+B D 退出)"
echo "  tail -f ${LIVE_LOG}                    # 查看日志"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "  bash ${SCRIPT_DIR}/task_monitor.sh ${TASK_ID}  # 状态概览"
echo ""
echo "🛑 中断: tmux send-keys -t ${SESSION} C-c"
