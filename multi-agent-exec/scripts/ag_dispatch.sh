#!/bin/bash
# ag-dispatch: Transparent executor dispatch wrapper with tracing
# Usage: ag-dispatch <executor> <role> <ipc_dir> [--budget N] [--project-dir DIR]
#
# Dispatches a task to an executor (cc/gemini/codex), captures output,
# and logs execution metadata to Langfuse (async, non-blocking).
#
# The executor receives the prompt via stdin from <ipc_dir>/prompt.txt
# Raw output is saved to <ipc_dir>/raw_output.json
# Execution record is saved to <ipc_dir>/execution_record.json

set -euo pipefail

EXECUTOR="${1:?Usage: ag-dispatch <executor> <role> <ipc_dir>}"
ROLE="${2:?Usage: ag-dispatch <executor> <role> <ipc_dir>}"
IPC_DIR="${3:?Usage: ag-dispatch <executor> <role> <ipc_dir>}"
BUDGET="${AG_DISPATCH_BUDGET:-5.00}"
PROJECT_DIR="${AG_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

# Parse optional args
shift 3
while [[ $# -gt 0 ]]; do
  case "$1" in
    --budget) BUDGET="$2"; shift 2 ;;
    --project-dir) PROJECT_DIR="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

PROMPT_FILE="${IPC_DIR}/prompt.txt"
RAW_OUTPUT="${IPC_DIR}/raw_output.json"
EXEC_RECORD="${IPC_DIR}/execution_record.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Validate
if [[ ! -f "$PROMPT_FILE" ]]; then
  echo "ERROR: prompt.txt not found at ${PROMPT_FILE}" >&2
  exit 1
fi

echo "[ag-dispatch] executor=${EXECUTOR} role=${ROLE} project=${PROJECT_DIR}"
START_TS=$(date +%s%N)

# Dispatch based on executor type
cd "$PROJECT_DIR"
case "$EXECUTOR" in
  cc|claude)
    cat "$PROMPT_FILE" | claude -p \
      --output-format json \
      --max-budget-usd "$BUDGET" \
      --permission-mode bypassPermissions \
      2>&1 | tee "$RAW_OUTPUT"
    ;;
  gemini)
    cat "$PROMPT_FILE" | gemini -p "" \
      --output-format json \
      --approval-mode yolo \
      2>&1 | tee "$RAW_OUTPUT"
    ;;
  codex)
    cat "$PROMPT_FILE" | codex exec \
      -c 'sandbox_permissions=["disk-full-read-access","disk-write"]' \
      2>&1 | tee "$RAW_OUTPUT"
    ;;
  *)
    echo "ERROR: Unknown executor '${EXECUTOR}'. Use: cc, gemini, codex" >&2
    exit 1
    ;;
esac

END_TS=$(date +%s%N)
DURATION_MS=$(( (END_TS - START_TS) / 1000000 ))

echo "[ag-dispatch] completed in ${DURATION_MS}ms"

# Write lean execution record (always succeeds)
cat > "$EXEC_RECORD" <<EOF
{
  "executor": "${EXECUTOR}",
  "role": "${ROLE}",
  "project": "${PROJECT_DIR}",
  "duration_ms": ${DURATION_MS},
  "timestamp": "$(date -Iseconds)",
  "prompt_file": "${PROMPT_FILE}",
  "raw_output_file": "${RAW_OUTPUT}"
}
EOF

# Async Langfuse trace (fire-and-forget, never blocks)
if command -v python3 &>/dev/null && [[ -f "${SCRIPT_DIR}/ag_trace.py" ]]; then
  python3 "${SCRIPT_DIR}/ag_trace.py" \
    --executor "$EXECUTOR" \
    --role "$ROLE" \
    --ipc-dir "$IPC_DIR" \
    --project "$PROJECT_DIR" \
    --duration-ms "$DURATION_MS" \
    &>/dev/null &
  disown
fi

echo "EXEC_DONE"
