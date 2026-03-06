#!/bin/bash
# panel_report.sh — Generate the final panel discussion report
#
# Usage: panel_report.sh <task_dir> <total_rounds>
#
# task_dir:       /tmp/panel/{task_id}/
# total_rounds:   total number of rounds (e.g. 3 for round_0, round_1, round_2)
#
# Reads:   $task_dir/round_*_summary.md, $task_dir/topic.txt
# Produces: $task_dir/final_report.md

set -euo pipefail

TASK_DIR="${1:?Usage: panel_report.sh <task_dir> <total_rounds>}"
TOTAL_ROUNDS="${2:?Usage: panel_report.sh <task_dir> <total_rounds>}"

REPORT_FILE="${TASK_DIR}/final_report.md"
TOPIC=""
if [[ -f "${TASK_DIR}/topic.txt" ]]; then
  TOPIC=$(cat "${TASK_DIR}/topic.txt")
fi

TIMESTAMP=$(date -Iseconds)

# Read actual executors from round 0 records (dynamic, supports fallback)
get_panelist_label() {
  local agent="$1"
  local record="${TASK_DIR}/round_0/${agent}/execution_record.json"
  if [[ -f "$record" ]] && command -v python3 &>/dev/null; then
    python3 -c "
import json
d = json.load(open('${record}'))
exe = d.get('executor', 'unknown')
fb = d.get('fallback', '')
labels = {'cc': 'CC (Claude)', 'gemini': 'Gemini (Google)', 'codex': 'Codex (OpenAI)', 'ag-fallback': 'AG (fallback)'}
label = labels.get(exe, exe)
if fb:
    label += f' [{fb}]'
print(label)
" 2>/dev/null || echo "?"
  else
    case "$agent" in
      skeptic) echo "CC (Claude)" ;;
      pragmatist) echo "CC (Claude)" ;;
      optimist) echo "CC (Claude)" ;;
      *) echo "?" ;;
    esac
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
      record="${TASK_DIR}/round_${r}/${agent}/execution_record.json"
      if [[ -f "$record" ]]; then
        status=$(python3 -c "import json; d=json.load(open('${record}')); print(f\"{d['status']} ({d['duration_human']})\")" 2>/dev/null || echo "?")
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
