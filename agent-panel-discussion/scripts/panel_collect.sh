#!/bin/bash
# panel_collect.sh — Collect outputs from all agents in a round and produce a summary
#
# Usage: panel_collect.sh <task_dir> <round_num>
#
# task_dir:  /tmp/panel/{task_id}/
# round_num: 0, 1, 2, ...
#
# Reads:   $task_dir/round_N/{agent}/output.md for each agent
# Produces: $task_dir/round_N_summary.md

set -euo pipefail

TASK_DIR="${1:?Usage: panel_collect.sh <task_dir> <round_num>}"
ROUND_NUM="${2:?Usage: panel_collect.sh <task_dir> <round_num>}"

ROUND_DIR="${TASK_DIR}/round_${ROUND_NUM}"
SUMMARY_FILE="${TASK_DIR}/round_${ROUND_NUM}_summary.md"

if [[ ! -d "$ROUND_DIR" ]]; then
  echo "ERROR: Round directory not found: ${ROUND_DIR}" >&2
  exit 1
fi

# Agent display config
declare -A AGENT_EMOJI=(
  [skeptic]="🔴"
  [pragmatist]="🔵"
  [optimist]="🟢"
)
declare -A AGENT_TITLE=(
  [skeptic]="怀疑论者（魔鬼代言人）"
  [pragmatist]="务实工程师"
  [optimist]="乐观派（愿景者）"
)

# Read actual executor from execution_record.json (dynamic, supports fallback)
get_executor_label() {
  local agent="$1"
  local record="${ROUND_DIR}/${agent}/execution_record.json"
  if [[ -f "$record" ]] && command -v python3 &>/dev/null; then
    python3 -c "
import json
d = json.load(open('${record}'))
exe = d.get('executor', 'unknown')
fb = d.get('fallback', '')
labels = {'cc': 'CC / Claude', 'gemini': 'Gemini / Google', 'codex': 'Codex / OpenAI', 'ag-fallback': 'AG (fallback)'}
label = labels.get(exe, exe)
if fb:
    label += f' (fallback: {fb})'
print(label)
" 2>/dev/null || echo "unknown"
  else
    # Fallback to default mapping
    case "$agent" in
      skeptic) echo "CC / Claude" ;;
      pragmatist) echo "CC / Claude" ;;
      optimist) echo "CC / Claude" ;;
      *) echo "unknown" ;;
    esac
  fi
}

# Check completion status
ALL_DONE=true
FAILED_AGENTS=()
for agent_dir in "$ROUND_DIR"/*/; do
  agent=$(basename "$agent_dir")
  record="${agent_dir}execution_record.json"
  output="${agent_dir}output.md"

  if [[ ! -f "$record" ]]; then
    echo "⏳ Agent ${agent}: still running (no execution_record.json)" >&2
    ALL_DONE=false
  elif [[ ! -f "$output" ]]; then
    echo "⚠️  Agent ${agent}: completed but no output.md" >&2
    FAILED_AGENTS+=("$agent")
  else
    status=$(python3 -c "import json; print(json.load(open('${record}'))['status'])" 2>/dev/null || echo "unknown")
    if [[ "$status" != "success" ]]; then
      echo "❌ Agent ${agent}: failed (status=${status})" >&2
      FAILED_AGENTS+=("$agent")
    else
      echo "✅ Agent ${agent}: done" >&2
    fi
  fi
done

if [[ "$ALL_DONE" == "false" ]]; then
  echo "" >&2
  echo "ERROR: Not all agents have completed. Wait for them to finish." >&2
  exit 2
fi

# Build summary — topic only in Round 0 header, not repeated
{
  if [[ "$ROUND_NUM" -eq 0 ]]; then
    echo "# 第 ${ROUND_NUM} 轮：开场陈述"
  else
    echo "# 第 ${ROUND_NUM} 轮：反驳"
  fi
  echo ""

  for agent in skeptic pragmatist optimist; do
    output="${ROUND_DIR}/${agent}/output.md"
    emoji="${AGENT_EMOJI[$agent]:-❓}"
    title="${AGENT_TITLE[$agent]:-$agent}"
    executor=$(get_executor_label "$agent")

    echo "---"
    echo ""
    echo "## ${emoji} ${title}"
    echo "*执行引擎: ${executor}*"
    echo ""

    if [[ -f "$output" ]]; then
      cat "$output"
    else
      echo "*[无输出 — agent 失败或未产生响应]*"
    fi
    echo ""
  done

  # Append failed agents warning if any
  if [[ ${#FAILED_AGENTS[@]} -gt 0 ]]; then
    echo "---"
    echo ""
    echo "> ⚠️ **警告**: 以下 agent 存在问题: ${FAILED_AGENTS[*]}"
    echo ""
  fi
} > "$SUMMARY_FILE"

echo ""
echo "✅ Round ${ROUND_NUM} summary written to: ${SUMMARY_FILE}"
echo "   $(wc -l < "$SUMMARY_FILE") lines"
