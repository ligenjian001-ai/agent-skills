#!/bin/bash
# panel_prepare.sh — Auto-prepare prompts for a round from topic + templates + previous round summary
#
# Usage: panel_prepare.sh <task_dir> <round_num> [template_dir] [total_rounds]
#
# task_dir:      /tmp/panel/{task_id}/
# round_num:     0, 1, 2, ...
# template_dir:  path to prompts/ dir (default: script's sibling ../prompts/)
# total_rounds:  total number of rounds (default: 3). Used to detect final round.
#
# For round 0: injects topic.txt into each agent's template
# For round N>0: injects topic.txt + round_(N-1)_summary.md as "previous round" context
#   - Adds position drift tracking ("我修正/坚持以下立场")
#   - On final round: adds confidence scoring + suppresses research requests
#
# Produces: $task_dir/round_N/{agent}/prompt.txt for each agent

set -euo pipefail

TASK_DIR="${1:?Usage: panel_prepare.sh <task_dir> <round_num> [template_dir] [total_rounds]}"
ROUND_NUM="${2:?Usage: panel_prepare.sh <task_dir> <round_num> [template_dir] [total_rounds]}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="${3:-${SCRIPT_DIR}/../prompts}"
TOTAL_ROUNDS="${4:-3}"

ROUND_DIR="${TASK_DIR}/round_${ROUND_NUM}"
LAST_ROUND=$((TOTAL_ROUNDS - 1))
IS_FINAL_ROUND=false
if [[ "$ROUND_NUM" -eq "$LAST_ROUND" ]]; then
  IS_FINAL_ROUND=true
fi

# Validate
if [[ ! -f "${TASK_DIR}/topic.txt" ]]; then
  echo "ERROR: topic.txt not found at ${TASK_DIR}/topic.txt" >&2
  exit 1
fi

if [[ ! -d "$TEMPLATE_DIR" ]]; then
  echo "ERROR: Template directory not found: ${TEMPLATE_DIR}" >&2
  exit 1
fi

TOPIC=$(cat "${TASK_DIR}/topic.txt")

# Get previous round summary CONTENT for rebuttals (only used in fallback mode)
PREV_SUMMARY_CONTENT=""
SESSION_RESUME_AVAILABLE=false
if [[ "$ROUND_NUM" -gt 0 ]]; then
  PREV_ROUND=$((ROUND_NUM - 1))
  PREV_FILE="${TASK_DIR}/round_${PREV_ROUND}_summary.md"
  if [[ -f "$PREV_FILE" ]]; then
    PREV_SUMMARY_CONTENT=$(cat "$PREV_FILE")
  else
    echo "WARN: Previous round summary not found: ${PREV_FILE}" >&2
  fi

  # Check if session resume is available (any agent from previous round has session_id)
  TASK_DELEGATE_DIR="${HOME}/.task-delegate"
  PANEL_ID=$(basename "$TASK_DIR")
  PANEL_TS=$(echo "$PANEL_ID" | grep -oP '\d{8}_\d{4}')
  if [[ -n "$PANEL_TS" ]]; then
    for check_agent in skeptic pragmatist optimist; do
      PREV_TASK_ID="${PANEL_TS}_panel_r${PREV_ROUND}_${check_agent}"
      PREV_RECORD="${TASK_DELEGATE_DIR}/${PREV_TASK_ID}/execution_record.json"
      if [[ -f "$PREV_RECORD" ]]; then
        PREV_SID=$(python3 -c "import json; print(json.load(open('${PREV_RECORD}')).get('session_id',''))" 2>/dev/null || true)
        if [[ -n "$PREV_SID" ]]; then
          SESSION_RESUME_AVAILABLE=true
          break
        fi
      fi
    done
  fi

  if [[ "$SESSION_RESUME_AVAILABLE" == "true" ]]; then
    echo "[panel-prepare] Session resume available from R${PREV_ROUND} — lightweight prompts"
  else
    echo "[panel-prepare] No session resume — will inline truncated summary (fallback mode)"
  fi
fi

# Generate prompt for each agent
for agent in skeptic pragmatist optimist; do
  agent_dir="${ROUND_DIR}/${agent}"
  mkdir -p "$agent_dir"

  template="${TEMPLATE_DIR}/${agent}.txt"
  if [[ ! -f "$template" ]]; then
    echo "WARN: Template not found for ${agent}: ${template}" >&2
    continue
  fi

  prompt_file="${agent_dir}/prompt.txt"

  {
    # Inject template (role definition)
    cat "$template"
    echo ""
    echo "---"
    echo ""

    # Inline discussion topic content directly (Codex agents cannot read files without tools)
    echo "# 讨论主题"
    echo ""
    echo "$TOPIC"
    echo ""

    # For rebuttals, behavior depends on session resume availability
    if [[ "$ROUND_NUM" -gt 0 ]]; then
      if [[ "$SESSION_RESUME_AVAILABLE" == "true" ]]; then
        # === SESSION RESUME MODE: lightweight prompt ===
        # Backend already has context from previous round via session memory
        echo "# 上一轮已在对话历史中"
        echo ""
        echo "你已经在上一轮给出了分析。其他panelist的观点也已由AG汇总。"
        echo "下面是其他panelist的**核心结论摘要**（完整分析在你的对话历史中）："
        echo ""
        # Inline only a brief summary of other agents' conclusions (not full output)
        if [[ -n "$PREV_SUMMARY_CONTENT" ]]; then
          echo "$PREV_SUMMARY_CONTENT" | head -c 2000
          PREV_SIZE=${#PREV_SUMMARY_CONTENT}
          if [[ "$PREV_SIZE" -gt 2000 ]]; then
            echo ""
            echo "...[摘要已截断，完整内容在上一轮 session 中]"
          fi
        fi
        echo ""
      else
        # === FALLBACK MODE: inline truncated summary ===
        echo "# 上一轮讨论内容"
        echo ""
        if [[ -n "$PREV_SUMMARY_CONTENT" ]]; then
          # Truncate to ~10KB total (each of 3 agents gets ~3000 chars in summary)
          echo "$PREV_SUMMARY_CONTENT" | head -c 10000
          PREV_SIZE=${#PREV_SUMMARY_CONTENT}
          if [[ "$PREV_SIZE" -gt 10000 ]]; then
            echo ""
            echo "...[内容已截断，原始大小: ${PREV_SIZE} 字节]"
          fi
        fi
        echo ""
      fi

      echo "# 你的任务"
      echo ""
      echo "这是**第 ${ROUND_NUM} 轮（反驳轮）**。"
      echo ""

      # === 观点漂移追踪 ===
      echo "## ⚡ 立场变化声明（必填）"
      echo ""
      echo "在回复的**最开头**，你必须先声明立场变化。格式如下："
      echo ""
      echo '```'
      echo "### 立场变化"
      echo "- ✅ 我现在**同意**: [列出你改变立场、接受对方观点的具体点]"
      echo "- ❌ 我仍然**反对**: [列出你坚持反对的具体点]"
      echo "- 🆕 我**新增**的关注点: [本轮研究数据引发的新论点]"
      echo '```'
      echo ""

      echo "然后再展开详细分析。具体要求："
      echo "1. 回应具体观点 — 同意或用证据反驳"
      echo "2. 更新、加强或修正你上一轮的立场"
      echo "3. 标注小组正在趋于共识的点 vs 仍有分歧的点"
      echo ""

      # === 最终轮特殊指令 ===
      if [[ "$IS_FINAL_ROUND" == "true" ]]; then
        echo "## 🏁 最终轮特殊要求"
        echo ""
        echo "这是**最后一轮**讨论。除了常规分析外，你必须在回复末尾添加："
        echo ""
        echo "### 📊 信心评分"
        echo ""
        echo "对以下核心问题打分（1-10），并用一句话解释理由："
        echo ""
        echo "| 问题 | 评分(1-10) | 理由 |"
        echo "|------|-----------|------|"
        echo "| 这个项目值得做吗？ | ? | ... |"
        echo "| 技术方案可行吗？ | ? | ... |"
        echo "| 能在6个月内达到PMF吗？ | ? | ... |"
        echo ""
        echo "> 注意：本轮是最后一轮，**不要**再提出资料搜索请求（📡 Research Requests）。"
        echo "> 集中精力总结你的最终立场和评分。"
        echo ""
      fi

      echo "保持你的角色。不要写代码。不要使用工具。只输出分析文本。"
    else
      echo "# 你的任务"
      echo ""
      echo "这是**第 0 轮（开场陈述）**。"
      echo "从你被分配的角色视角，对讨论主题给出初始分析。"
      echo "按照上方指定的格式撰写回复。"
      echo "不要写任何代码。这是一个纯分析/讨论任务。"
      echo "不要使用任何工具。直接以文本形式输出你的分析。"
    fi
  } > "$prompt_file"

  echo "✅ Prepared: ${agent} → ${prompt_file}"
done

echo ""
echo "✅ All prompts prepared for Round ${ROUND_NUM} (total: ${TOTAL_ROUNDS}, final: ${IS_FINAL_ROUND})"
echo "   Directory: ${ROUND_DIR}/"
