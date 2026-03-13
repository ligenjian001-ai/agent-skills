#!/bin/bash
# panel_collect.sh — Collect outputs from all agents in a round and produce a summary
#
# Usage: panel_collect.sh <panel_dir> <round_num>
#
# panel_dir:  ~/.panel-discussions/{panel_id}/
# round_num:  0, 1, 2, ...
#
# Reads execution records and outputs from ~/.task-delegate/{task_id}/
# Uses manifest.json to find task_ids for each agent in the round.
# Produces: $panel_dir/round_N_summary.md

set -euo pipefail

PANEL_DIR="${1:?Usage: panel_collect.sh <panel_dir> <round_num>}"
ROUND_NUM="${2:?Usage: panel_collect.sh <panel_dir> <round_num>}"

MANIFEST="${PANEL_DIR}/manifest.json"
SUMMARY_FILE="${PANEL_DIR}/round_${ROUND_NUM}_summary.md"
TASK_DELEGATE_DIR="${HOME}/.task-delegate"

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

# Get task_id for an agent from manifest, or derive from panel_id
get_task_id() {
  local agent="$1"
  if [[ -f "$MANIFEST" ]] && command -v python3 &>/dev/null; then
    python3 -c "
import json
m = json.load(open('${MANIFEST}'))
tasks = m.get('tasks', {}).get('round_${ROUND_NUM}', {})
print(tasks.get('${agent}', ''))
" 2>/dev/null
  else
    # Derive from panel_id convention: YYYYMMDD_HHMM_panel_rN_agent
    local panel_id=$(basename "$PANEL_DIR")
    local panel_ts=$(echo "$panel_id" | grep -oP '\d{8}_\d{4}')
    echo "${panel_ts}_panel_r${ROUND_NUM}_${agent}"
  fi
}

# Read executor label from execution_record.json
get_executor_label() {
  local task_id="$1"
  local record="${TASK_DELEGATE_DIR}/${task_id}/execution_record.json"
  if [[ -f "$record" ]] && command -v python3 &>/dev/null; then
    python3 -c "
import json
d = json.load(open('${record}'))
exe = d.get('backend', d.get('executor', 'unknown'))
labels = {'cc': 'CC / Claude', 'gemini': 'Gemini / Google', 'codex': 'Codex / OpenAI'}
print(labels.get(exe, exe))
" 2>/dev/null || echo "unknown"
  else
    echo "unknown"
  fi
}

# Check completion status
ALL_DONE=true
FAILED_AGENTS=()
for agent in skeptic pragmatist optimist; do
  task_id=$(get_task_id "$agent")
  if [[ -z "$task_id" ]]; then
    echo "⚠️  Agent ${agent}: task_id not found in manifest" >&2
    FAILED_AGENTS+=("$agent")
    continue
  fi

  task_dir="${TASK_DELEGATE_DIR}/${task_id}"
  record="${task_dir}/execution_record.json"
  output="${task_dir}/output.md"

  if [[ ! -f "$record" ]]; then
    echo "⏳ Agent ${agent}: still running (no execution_record.json in ${task_dir})" >&2
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
      echo "✅ Agent ${agent}: done (${task_id})" >&2
    fi
  fi
done

if [[ "$ALL_DONE" == "false" ]]; then
  echo "" >&2
  echo "ERROR: Not all agents have completed. Wait for them to finish." >&2
  exit 2
fi

# Build summary
{
  if [[ "$ROUND_NUM" -eq 0 ]]; then
    echo "# 第 ${ROUND_NUM} 轮：开场陈述"
  else
    echo "# 第 ${ROUND_NUM} 轮：反驳"
  fi
  echo ""

  for agent in skeptic pragmatist optimist; do
    task_id=$(get_task_id "$agent")
    task_dir="${TASK_DELEGATE_DIR}/${task_id}"
    output="${task_dir}/output.md"
    emoji="${AGENT_EMOJI[$agent]:-❓}"
    title="${AGENT_TITLE[$agent]:-$agent}"
    executor=$(get_executor_label "$task_id")

    echo "---"
    echo ""
    echo "## ${emoji} ${title}"
    echo "*执行引擎: ${executor}*"
    echo ""

    if [[ -f "$output" ]]; then
      # Truncation guard: limit each agent output to 4000 chars in summary
      OUTPUT_SIZE=$(wc -c < "$output" 2>/dev/null || echo 0)
      if [[ "$OUTPUT_SIZE" -gt 4000 ]]; then
        head -c 4000 "$output"
        echo ""
        echo ""
        echo "> *[输出已截断: 原始 ${OUTPUT_SIZE} 字节 → 4000 字节。完整内容见 ${task_dir}/output.md]*"
      else
        cat "$output"
      fi
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
