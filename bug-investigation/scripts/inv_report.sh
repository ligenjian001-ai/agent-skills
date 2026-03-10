#!/bin/bash
# inv_report.sh — Generate a comprehensive investigation report from all collected analyses
#
# Usage: inv_report.sh <inv_dir>
#
# Reads: analysis_summary.md, rebuttal_summary.md (if exists), verdict.md (if exists)
# Produces: $inv_dir/investigation_report.md

set -euo pipefail

INV_DIR="${1:?Usage: inv_report.sh <inv_dir>}"
INV_ID=$(basename "$INV_DIR")
REPORT="${INV_DIR}/investigation_report.md"

{
  echo "# 🔍 Bug 调查报告"
  echo ""
  echo "> 调查 ID: \`${INV_ID}\`"
  echo "> 生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
  echo ""

  # Include bug context summary
  if [[ -f "${INV_DIR}/bug_context.txt" ]]; then
    echo "## 📋 Bug 描述"
    echo ""
    # Extract just the first section (现象 + 期望行为)
    head -30 "${INV_DIR}/bug_context.txt"
    echo ""
    echo "---"
    echo ""
  fi

  # Include initial analysis
  if [[ -f "${INV_DIR}/analysis_summary.md" ]]; then
    echo "## 📊 独立分析（初始轮）"
    echo ""
    cat "${INV_DIR}/analysis_summary.md"
    echo ""
    echo "---"
    echo ""
  fi

  # Include rebuttal if exists
  if [[ -f "${INV_DIR}/rebuttal_summary.md" ]]; then
    echo "## ⚔️ 交叉审查（反驳轮）"
    echo ""
    cat "${INV_DIR}/rebuttal_summary.md"
    echo ""
    echo "---"
    echo ""
  fi

  # Include AG verdict if exists
  if [[ -f "${INV_DIR}/verdict.md" ]]; then
    echo "## 🏛️ AG 综合判定"
    echo ""
    cat "${INV_DIR}/verdict.md"
    echo ""
  else
    echo "## 🏛️ AG 综合判定"
    echo ""
    echo "*[待 AG 写入]*"
    echo ""
  fi

} > "$REPORT"

echo "✅ Investigation report written to: ${REPORT}"
echo "   $(wc -l < "$REPORT") lines"
