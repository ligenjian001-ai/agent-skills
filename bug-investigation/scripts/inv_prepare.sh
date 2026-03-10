#!/bin/bash
# inv_prepare.sh — Prepare prompts for bug investigation from bug_context + analyst templates
#
# Usage: inv_prepare.sh <inv_dir> [--rebuttal]
#
# inv_dir:   ~/.bug-investigations/{inv_id}/
# --rebuttal: if set, prepare rebuttal round prompts (inject other analyst's report)
#
# For initial round: injects bug_context.txt into each analyst's template
# For rebuttal: injects bug_context.txt + other analyst's output as cross-review context
#
# Produces:
#   Initial:  $inv_dir/{code_analyst,logic_analyst}/prompt.txt
#   Rebuttal: $inv_dir/rebuttal/{code_analyst,logic_analyst}/prompt.txt

set -euo pipefail

INV_DIR="${1:?Usage: inv_prepare.sh <inv_dir> [--rebuttal]}"
REBUTTAL=false
if [[ "${2:-}" == "--rebuttal" ]]; then
  REBUTTAL=true
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="${SCRIPT_DIR}/../prompts"
TASK_DELEGATE_DIR="${HOME}/.task-delegate"

# Validate
if [[ ! -f "${INV_DIR}/bug_context.txt" ]]; then
  echo "ERROR: bug_context.txt not found at ${INV_DIR}/bug_context.txt" >&2
  exit 1
fi

if [[ ! -d "$TEMPLATE_DIR" ]]; then
  echo "ERROR: Template directory not found: ${TEMPLATE_DIR}" >&2
  exit 1
fi

BUG_CONTEXT=$(cat "${INV_DIR}/bug_context.txt")

# Analyst definitions: name -> template file
declare -A ANALYST_TEMPLATE=(
  [code_analyst]="code_analyst.txt"
  [logic_analyst]="logic_analyst.txt"
)

# For rebuttal: who reviews whom
declare -A CROSS_REVIEW=(
  [code_analyst]="logic_analyst"
  [logic_analyst]="code_analyst"
)
declare -A ANALYST_LABEL=(
  [code_analyst]="代码分析师 (CC)"
  [logic_analyst]="逻辑推理分析师 (Codex)"
)

if [[ "$REBUTTAL" == "true" ]]; then
  OUTPUT_BASE="${INV_DIR}/rebuttal"
else
  OUTPUT_BASE="${INV_DIR}"
fi

for analyst in code_analyst logic_analyst; do
  analyst_dir="${OUTPUT_BASE}/${analyst}"
  mkdir -p "$analyst_dir"

  template="${TEMPLATE_DIR}/${ANALYST_TEMPLATE[$analyst]}"
  if [[ ! -f "$template" ]]; then
    echo "WARN: Template not found for ${analyst}: ${template}" >&2
    continue
  fi

  prompt_file="${analyst_dir}/prompt.txt"

  {
    # Inject template (role definition)
    cat "$template"
    echo ""
    echo "---"
    echo ""

    # Inject bug context
    echo "$BUG_CONTEXT"
    echo ""

    if [[ "$REBUTTAL" == "true" ]]; then
      # Get the other analyst's output
      other="${CROSS_REVIEW[$analyst]}"
      other_label="${ANALYST_LABEL[$other]}"

      # Find the other analyst's output from task-delegate
      # Look in the initial round directories
      other_output=""
      other_dir="${INV_DIR}/${other}"
      if [[ -d "$other_dir" ]]; then
        # Try to find output.md via the task-delegate task_id
        inv_id=$(basename "$INV_DIR")
        inv_ts=$(echo "$inv_id" | grep -oP '\d{8}_\d{4}')
        other_task_id="${inv_ts}_inv_${other}"
        other_output_file="${TASK_DELEGATE_DIR}/${other_task_id}/output.md"
        if [[ -f "$other_output_file" ]]; then
          other_output=$(cat "$other_output_file")
        fi
      fi

      echo "# 交叉审查任务"
      echo ""
      echo "这是**反驳轮**。以下是 ${other_label} 对同一 bug 的独立分析："
      echo ""
      if [[ -n "$other_output" ]]; then
        echo "---"
        echo "$other_output"
        echo "---"
      else
        echo "> ⚠️ 对方分析报告未找到。仅基于 bug context 给出你的独立补充分析。"
      fi
      echo ""
      echo "## 你的任务"
      echo ""
      echo "1. **审查对方的假设** — 哪些你同意？哪些你认为有问题？"
      echo "2. **挑战薄弱论点** — 对方的哪些推理链路有逻辑漏洞？"
      echo "3. **补充遗漏** — 对方忽略了什么？"
      echo "4. **更新你的假设排名** — 结合对方的分析，重新排序你的假设"
      echo ""
      echo "不要写代码。不要使用工具。直接输出你的分析。"
    else
      echo "# 你的任务"
      echo ""
      echo "分析以上 bug，找出根因。"
      echo "按照你被分配的角色和格式要求输出分析。"
      echo "不要写任何代码。这是一个纯分析任务。"
      echo "不要使用任何工具。直接以文本形式输出你的分析。"
    fi
  } > "$prompt_file"

  echo "✅ Prepared: ${analyst} → ${prompt_file}"
done

echo ""
if [[ "$REBUTTAL" == "true" ]]; then
  echo "✅ Rebuttal prompts prepared in: ${OUTPUT_BASE}/"
else
  echo "✅ Initial prompts prepared in: ${OUTPUT_BASE}/"
fi
