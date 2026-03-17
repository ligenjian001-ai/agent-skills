#!/bin/bash
# inv_collect.sh — Collect outputs from both analysts and produce a comparison summary
#
# Usage: inv_collect.sh <inv_dir> [--rebuttal]
#
# inv_dir:    ~/.bug-investigations/{inv_id}/
# --rebuttal: if set, collect rebuttal round outputs instead
#
# Reads execution records and outputs from ~/.task-delegate/{task_id}/
# Produces: $inv_dir/analysis_summary.md (or rebuttal_summary.md)

set -euo pipefail

INV_DIR="${1:?Usage: inv_collect.sh <inv_dir> [--rebuttal]}"
IS_REBUTTAL=false
if [[ "${2:-}" == "--rebuttal" ]]; then
  IS_REBUTTAL=true
fi

TASK_DELEGATE_DIR="${HOME}/.task-delegate"
INV_ID=$(basename "$INV_DIR")
INV_TS=$(echo "$INV_ID" | grep -oP '\d{8}_\d{4}')

if [[ "$IS_REBUTTAL" == "true" ]]; then
  SUMMARY_FILE="${INV_DIR}/rebuttal_summary.md"
else
  SUMMARY_FILE="${INV_DIR}/analysis_summary.md"
fi

# Analyst display config
declare -A ANALYST_EMOJI=(
  [code_analyst]="🔧"
  [logic_analyst]="🧠"
)
declare -A ANALYST_TITLE=(
  [code_analyst]="代码分析师 (Code Analyst)"
  [logic_analyst]="逻辑推理分析师 (Logic Analyst)"
)
declare -A ANALYST_ENGINE=(
  [code_analyst]="Codex / OpenAI"
  [logic_analyst]="Codex / OpenAI"
)

# Build task_id for each analyst
get_task_id() {
  local analyst="$1"
  if [[ "$IS_REBUTTAL" == "true" ]]; then
    echo "${INV_TS}_inv_rebuttal_${analyst}"
  else
    echo "${INV_TS}_inv_${analyst}"
  fi
}

# Read executor label from execution_record.json
get_executor_label() {
  local task_id="$1"
  local analyst="$2"
  local record="${TASK_DELEGATE_DIR}/${task_id}/execution_record.json"
  if [[ -f "$record" ]] && command -v python3 &>/dev/null; then
    python3 -c "
import json
d = json.load(open('${record}'))
exe = d.get('backend', d.get('executor', 'unknown'))
labels = {'cc': 'CC / Claude', 'gemini': 'Gemini / Google', 'codex': 'Codex / OpenAI'}
print(labels.get(exe, exe))
" 2>/dev/null || echo "${ANALYST_ENGINE[$analyst]:-unknown}"
  else
    echo "${ANALYST_ENGINE[$analyst]:-unknown}"
  fi
}

# Check completion status
ALL_DONE=true
FAILED_ANALYSTS=()
for analyst in code_analyst logic_analyst; do
  task_id=$(get_task_id "$analyst")
  task_dir="${TASK_DELEGATE_DIR}/${task_id}"
  record="${task_dir}/execution_record.json"
  output="${task_dir}/output.md"

  if [[ ! -f "$record" ]]; then
    echo "⏳ Analyst ${analyst}: still running (no execution_record.json in ${task_dir})" >&2
    ALL_DONE=false
  elif [[ ! -f "$output" ]]; then
    echo "⚠️  Analyst ${analyst}: completed but no output.md" >&2
    FAILED_ANALYSTS+=("$analyst")
  else
    status=$(python3 -c "import json; print(json.load(open('${record}'))['status'])" 2>/dev/null || echo "unknown")
    if [[ "$status" != "success" ]]; then
      echo "❌ Analyst ${analyst}: failed (status=${status})" >&2
      FAILED_ANALYSTS+=("$analyst")
    else
      echo "✅ Analyst ${analyst}: done (${task_id})" >&2
    fi
  fi
done

if [[ "$ALL_DONE" == "false" ]]; then
  echo "" >&2
  echo "ERROR: Not all analysts have completed. Wait for them to finish." >&2
  exit 2
fi

# Build summary
{
  if [[ "$IS_REBUTTAL" == "true" ]]; then
    echo "# Bug 调查 — 反驳轮交叉审查"
  else
    echo "# Bug 调查 — 独立分析报告"
  fi
  echo ""
  echo "> 调查 ID: \`${INV_ID}\`"
  echo ""

  for analyst in code_analyst logic_analyst; do
    task_id=$(get_task_id "$analyst")
    task_dir="${TASK_DELEGATE_DIR}/${task_id}"
    output="${task_dir}/output.md"
    emoji="${ANALYST_EMOJI[$analyst]:-❓}"
    title="${ANALYST_TITLE[$analyst]:-$analyst}"
    executor=$(get_executor_label "$task_id" "$analyst")

    echo "---"
    echo ""
    echo "## ${emoji} ${title}"
    echo "*执行引擎: ${executor}*"
    echo ""

    if [[ -f "$output" ]]; then
      cat "$output"
    else
      echo "*[无输出 — analyst 失败或未产生响应]*"
    fi
    echo ""
  done

  # Append failed analysts warning
  if [[ ${#FAILED_ANALYSTS[@]} -gt 0 ]]; then
    echo "---"
    echo ""
    echo "> ⚠️ **警告**: 以下 analyst 存在问题: ${FAILED_ANALYSTS[*]}"
    echo ""
  fi
} > "$SUMMARY_FILE"

echo ""
echo "✅ Analysis summary written to: ${SUMMARY_FILE}"
echo "   $(wc -l < "$SUMMARY_FILE") lines"
