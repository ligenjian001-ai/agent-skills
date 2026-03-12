#!/bin/bash
# task_monitor.sh — Monitor task-delegate task status
#
# Usage:
#   task_monitor.sh              # List all tasks
#   task_monitor.sh <task_id>    # Show detailed status for one task

set -euo pipefail

TASKS_DIR="${HOME}/.task-delegate"

# --- Color helpers ---
BOLD="\033[1m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
CYAN="\033[36m"
DIM="\033[2m"
RESET="\033[0m"

# --- No args: list all tasks ---
if [[ $# -eq 0 ]]; then
  echo -e "${BOLD}📋 Task Delegate — All Tasks${RESET}"
  echo "═══════════════════════════════════════════════════════"

  if [[ ! -d "$TASKS_DIR" ]] || [[ -z "$(ls -A "$TASKS_DIR" 2>/dev/null)" ]]; then
    echo "  (no tasks found)"
    exit 0
  fi

  printf "  %-35s %-10s %-12s %-12s %s\n" "TASK ID" "BACKEND" "STATUS" "DURATION" "SESSION"
  echo "  ─────────────────────────────────────────────────────────────────────"

  for task_dir in "$TASKS_DIR"/*/; do
    [[ -d "$task_dir" ]] || continue
    task_id=$(basename "$task_dir")
    session="task-${task_id}"

    # Determine backend from execution_record
    backend="?"
    if [[ -f "${task_dir}/execution_record.json" ]]; then
      backend=$(python3 -c "import json; print(json.load(open('${task_dir}/execution_record.json')).get('backend', '?'))" 2>/dev/null || echo "?")
    fi

    # Check status
    if [[ -f "${task_dir}/execution_record.json" ]]; then
      status=$(python3 -c "import json; print(json.load(open('${task_dir}/execution_record.json'))['status'])" 2>/dev/null || echo "unknown")
      duration=$(python3 -c "import json; print(json.load(open('${task_dir}/execution_record.json'))['duration_human'])" 2>/dev/null || echo "?")
      if [[ "$status" == "success" ]]; then
        status_display="${GREEN}✅ done${RESET}"
      else
        status_display="${RED}❌ fail${RESET}"
      fi
      session_display="ended"
    elif tmux has-session -t "$session" 2>/dev/null; then
      status_display="${YELLOW}⏳ running${RESET}"
      # Calculate running time
      if [[ -f "${task_dir}/live.log" ]]; then
        start_line=$(head -5 "${task_dir}/live.log" | grep -oP '\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}' | head -1)
        if [[ -n "${start_line:-}" ]]; then
          start_ts=$(date -d "$start_line" +%s 2>/dev/null || echo "0")
          now_ts=$(date +%s)
          elapsed_s=$((now_ts - start_ts))
          duration="${elapsed_s}s"
          if [[ $elapsed_s -ge 60 ]]; then
            duration="$((elapsed_s / 60))m $((elapsed_s % 60))s"
          fi
        else
          duration="..."
        fi
      else
        duration="..."
      fi
      session_display="${CYAN}${session}${RESET}"
    else
      status_display="${RED}💀 dead${RESET}"
      duration="?"
      session_display="none"
    fi

    printf "  %-35s %-10s %-25b %-12s %b\n" "$task_id" "$backend" "$status_display" "$duration" "$session_display"
  done

  echo ""
  echo "  Use: task_monitor.sh <task_id>  for details"
  exit 0
fi

# --- Single task detail ---
TASK_ID="$1"
TASK_DIR="${TASKS_DIR}/${TASK_ID}"
SESSION="task-${TASK_ID}"

if [[ ! -d "$TASK_DIR" ]]; then
  echo "ERROR: Task not found: ${TASK_ID}" >&2
  echo "Available tasks:" >&2
  ls "$TASKS_DIR" 2>/dev/null || echo "  (none)"
  exit 1
fi

echo -e "${BOLD}📋 Task: ${TASK_ID}${RESET}"
echo "═══════════════════════════════════════════════════════"

# --- Status ---
if [[ -f "${TASK_DIR}/execution_record.json" ]]; then
  echo -e "  Status:   ${GREEN}Completed${RESET}"
  python3 -c "
import json
r = json.load(open('${TASK_DIR}/execution_record.json'))
print(f\"  Backend:  {r.get('backend', '?')}\")
print(f\"  Result:   {r['status']}\")
print(f\"  Duration: {r['duration_human']}\")
print(f\"  Started:  {r.get('started_at', '?')}\")
print(f\"  Finished: {r.get('finished_at', '?')}\")
print(f\"  Exit:     {r.get('exit_code', '?')}\")
" 2>/dev/null || echo "  (could not parse execution_record.json)"
elif tmux has-session -t "$SESSION" 2>/dev/null; then
  echo -e "  Status:   ${YELLOW}Running${RESET}"
  echo "  Session:  ${SESSION}"
  echo ""
  echo -e "  ${CYAN}Commands:${RESET}"
  echo "    tmux attach -t ${SESSION}     # 实时观看 (Ctrl+B D 退出)"
  echo "    tmux send-keys -t ${SESSION} C-c  # 中断任务"
else
  echo -e "  Status:   ${RED}Dead (session gone, no completion record)${RESET}"
fi

echo ""

# --- Prompt preview ---
if [[ -f "${TASK_DIR}/prompt.txt" ]]; then
  echo -e "${BOLD}📝 Prompt (first 10 lines):${RESET}"
  echo "───────────────────────────────────────────────────────"
  head -10 "${TASK_DIR}/prompt.txt" | sed 's/^/  /'
  PROMPT_LINES=$(wc -l < "${TASK_DIR}/prompt.txt")
  if [[ $PROMPT_LINES -gt 10 ]]; then
    echo "  ... (${PROMPT_LINES} lines total)"
  fi
  echo ""
fi

# --- Recent output ---
if [[ -f "${TASK_DIR}/live.log" ]]; then
  LOG_LINES=$(wc -l < "${TASK_DIR}/live.log")
  echo -e "${BOLD}📺 Recent output (last 20 lines of ${LOG_LINES} total):${RESET}"
  echo "───────────────────────────────────────────────────────"
  tail -20 "${TASK_DIR}/live.log" | sed 's/^/  /'
  echo ""
  echo "  Full log: ${TASK_DIR}/live.log"
fi
