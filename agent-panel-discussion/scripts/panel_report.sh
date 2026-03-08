#!/bin/bash
# panel_report.sh — Generate the final panel discussion report
#
# Usage: panel_report.sh <panel_dir> <total_rounds>
#
# panel_dir:      ~/.panel-discussions/{panel_id}/
# total_rounds:   total number of rounds (e.g. 3 for round_0, round_1, round_2)
#
# Reads:   $panel_dir/round_*_summary.md, $panel_dir/topic.txt
#          ~/.task-delegate/{task_id}/execution_record.json (via manifest.json)
# Produces: $panel_dir/final_report.md

set -euo pipefail

TASK_DIR="${1:?Usage: panel_report.sh <panel_dir> <total_rounds>}"
TOTAL_ROUNDS="${2:?Usage: panel_report.sh <panel_dir> <total_rounds>}"

REPORT_FILE="${TASK_DIR}/final_report.md"
MANIFEST="${TASK_DIR}/manifest.json"
TASK_DELEGATE_DIR="${HOME}/.task-delegate"
TOPIC=""
if [[ -f "${TASK_DIR}/topic.txt" ]]; then
  TOPIC=$(cat "${TASK_DIR}/topic.txt")
fi

TIMESTAMP=$(date -Iseconds)

# Get task_id from manifest
get_task_id() {
  local agent="$1" round="$2"
  if [[ -f "$MANIFEST" ]] && command -v python3 &>/dev/null; then
    python3 -c "
import json
m = json.load(open('${MANIFEST}'))
print(m.get('tasks',{}).get('round_${round}',{}).get('${agent}',''))
" 2>/dev/null
  else
    local panel_id=$(basename "$TASK_DIR")
    local panel_ts=$(echo "$panel_id" | grep -oP '\d{8}_\d{4}')
    echo "${panel_ts}_panel_r${round}_${agent}"
  fi
}

# Read actual executors from execution records (via task-delegate)
get_panelist_label() {
  local agent="$1"
  local task_id=$(get_task_id "$agent" 0)
  local record="${TASK_DELEGATE_DIR}/${task_id}/execution_record.json"
  if [[ -f "$record" ]] && command -v python3 &>/dev/null; then
    python3 -c "
import json
d = json.load(open('${record}'))
exe = d.get('backend', d.get('executor', 'unknown'))
labels = {'cc': 'CC (Claude)', 'gemini': 'Gemini (Google)', 'codex': 'Codex (OpenAI)'}
print(labels.get(exe, exe))
" 2>/dev/null || echo "?"
  else
    echo "?"
  fi
}

{
  echo "# 🎙️ Panel 讨论报告"
  echo ""
  echo "> **主题**: ${TOPIC:-[未指定主题]}"
  echo ">"
  echo "> **生成时间**: ${TIMESTAMP}"
  echo ">"
  echo "> **轮次**: ${TOTAL_ROUNDS}（开场 + $((TOTAL_ROUNDS - 1)) 轮反驳）"
  echo ""

  # Panelists table — dynamic from execution records
  echo "## 讨论者"
  echo ""
  echo "| 角色 | 立场 | 执行引擎 |"
  echo "|------|------|----------|"
  echo "| 🔴 怀疑论者 | 魔鬼代言人 — 质疑假设、发现风险 | $(get_panelist_label skeptic) |"
  echo "| 🔵 务实工程师 | 工程师 — 关注可行性和权衡 | $(get_panelist_label pragmatist) |"
  echo "| 🟢 乐观派 | 愿景者 — 发现机会和上行空间 | $(get_panelist_label optimist) |"
  echo ""

  # Execution summary
  echo "## 执行概要"
  echo ""
  echo "| 轮次 | 怀疑论者 | 务实工程师 | 乐观派 |"
  echo "|-------|---------|------------|----------|"
  for ((r=0; r<TOTAL_ROUNDS; r++)); do
    ROW="| 第 ${r} 轮 |"
    for agent in skeptic pragmatist optimist; do
      task_id=$(get_task_id "$agent" "$r")
      record="${TASK_DELEGATE_DIR}/${task_id}/execution_record.json"
      if [[ -f "$record" ]]; then
        status=$(python3 -c "import json; d=json.load(open('${record}')); s=d['duration_seconds']; print(f\"{d['status']} ({s//60}m {s%60}s)\")" 2>/dev/null || echo "?")
        ROW+=" ${status} |"
      else
        ROW+=" ❌ missing |"
      fi
    done
    echo "$ROW"
  done
  echo ""

  # Include all round summaries (topic is only in report header, not repeated)
  echo "## 逐轮讨论内容"
  echo ""
  for ((r=0; r<TOTAL_ROUNDS; r++)); do
    summary="${TASK_DIR}/round_${r}_summary.md"
    if [[ -f "$summary" ]]; then
      cat "$summary"
      echo ""
    else
      echo "### Round ${r}"
      echo "*[Round summary not found]*"
      echo ""
    fi
  done

  # Closing section — placeholder for orchestrator synthesis
  echo "---"
  echo ""
  echo "## Synthesis"
  echo ""
  echo "*This section is populated by the orchestrator (AG) after reviewing all rounds.*"
  echo ""
  echo "### Areas of Agreement"
  echo ""
  echo "*(To be filled by AG)*"
  echo ""
  echo "### Key Points of Disagreement"
  echo ""
  echo "*(To be filled by AG)*"
  echo ""
  echo "### Final Recommendations"
  echo ""
  echo "*(To be filled by AG)*"
  echo ""

} > "$REPORT_FILE"

echo ""
echo "✅ Final report written to: ${REPORT_FILE}"
echo "   $(wc -l < "$REPORT_FILE") lines, $(wc -c < "$REPORT_FILE") bytes"
