#!/usr/bin/env python3
"""
generate_report.py — Daily Report Generator

Takes JSON from collect.py, matches items to projects, generates markdown report.

Usage:
    python3 collect.py --date 20260307 | python3 generate_report.py
    python3 generate_report.py --input collected.json --output report.md
    python3 generate_report.py --input collected.json  # prints to stdout
"""

import argparse
import json
import os
import sys
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path

import yaml

TZ_LOCAL = timezone(timedelta(hours=8))
SCRIPT_DIR = Path(__file__).parent.resolve()
PROJECTS_FILE = SCRIPT_DIR.parent / "projects.yaml"


def load_projects_config() -> dict:
    """Load projects.yaml configuration."""
    try:
        with open(PROJECTS_FILE, "r", encoding="utf-8") as f:
            return yaml.safe_load(f)
    except FileNotFoundError:
        print(f"Warning: {PROJECTS_FILE} not found, using defaults", file=sys.stderr)
        return {"projects": [], "default_project": "其他"}


def match_project(entry: dict, config: dict) -> str:
    """Match an entry to a project based on config rules.

    Priority: project field > path match > keyword match
    """
    projects = config.get("projects", [])
    default = config.get("default_project", "其他")

    # 1. Direct project field (task-delegate has this)
    project_path = entry.get("project", "")
    if project_path:
        for proj in projects:
            for path in proj["match"].get("paths", []):
                if project_path.startswith(path):
                    return proj["name"]

    # 2. Combine all text fields for keyword matching
    text_fields = [
        entry.get("title", ""),
        entry.get("summary", ""),
        entry.get("user_goal", ""),
        entry.get("task_description", ""),
    ]
    # Add metadata summaries
    text_fields.extend(entry.get("metadata_summaries", []))
    # Add decisions and errors
    text_fields.extend(entry.get("decisions", []))
    text_fields.extend(entry.get("errors", []))
    # Add latest_summary_preview for panels
    text_fields.append(entry.get("latest_summary_preview", ""))
    # Add topic_text for panels
    text_fields.append(entry.get("topic_text", ""))
    # Add conv_tags for project matching
    text_fields.extend(entry.get("conv_tags", []))

    combined_text = " ".join(text_fields).lower()

    # Score each project by keyword hits
    best_project = None
    best_score = 0

    for proj in projects:
        score = 0
        # Path match in text
        for path in proj["match"].get("paths", []):
            if path.lower() in combined_text:
                score += 10  # Strong signal

        # Keyword match
        for kw in proj["match"].get("keywords", []):
            if kw.lower() in combined_text:
                score += 1

        if score > best_score:
            best_score = score
            best_project = proj["name"]

    return best_project if best_project and best_score > 0 else default


def format_ag_conversation(entry: dict) -> str:
    """Format a single AG conversation entry — bold title + short path ref."""
    title = entry.get("title", "Untitled")
    conv_id = entry.get("conv_id", "")
    conv_id_short = conv_id[:8] if conv_id else ""

    # Build summary from best available source
    summary = entry.get("user_goal", "") or entry.get("summary", "")
    if not summary and entry.get("metadata_summaries"):
        summary = entry["metadata_summaries"][0]
    # Truncate long summaries
    if summary and len(summary) > 100:
        summary = summary[:100] + "..."

    # Bold title with short ID ref
    line = f"- **{title}**"

    # Append summary if different from title
    if summary and summary != title and not title.startswith(summary[:30]):
        line += f" — {summary}"

    # Compact annotations
    tags = []
    if conv_id_short:
        tags.append(conv_id_short)
    if entry.get("decisions"):
        tags.append(f"决策×{len(entry['decisions'])}")
    if entry.get("errors"):
        tags.append(f"错误×{len(entry['errors'])}")
    if entry.get("has_walkthrough"):
        tags.append("✅walkthrough")

    if tags:
        line += f"  `{' | '.join(tags)}`"

    return line


def format_panel_discussion(entry: dict) -> str:
    """Format a single panel discussion entry."""
    title = entry.get("title", "Untitled")
    panel_id = entry.get("panel_id", "")
    rounds = entry.get("num_rounds", 0)
    roles = entry.get("roles", [])
    roles_str = "/".join(roles) if roles else "?"
    has_final = " ✅最终报告" if entry.get("has_final_report") else ""

    line = f"- **{title}** — {rounds}轮 ({roles_str}){has_final}"
    if panel_id:
        line += f"  `{panel_id}`"
    return line


def format_task_delegate(entry: dict) -> str:
    """Format a single task delegate entry."""
    status_icon = "✅" if entry.get("status") == "success" else "❌"
    task_id = entry.get("task_id", "unknown")
    backend = entry.get("backend", "?").upper()
    duration = entry.get("duration_human", "?")
    desc = entry.get("task_description", task_id)

    return f"- {status_icon} **{desc}** `{backend} {duration}`"


def generate_improvement_suggestions(grouped: dict, data: dict) -> list:
    """Generate AI improvement suggestions based on data patterns."""
    suggestions = []

    # Check for conversations without walkthroughs
    no_walkthrough = []
    for project_entries in grouped.values():
        for entry in project_entries:
            if entry["type"] == "ag_conversation" and not entry.get("has_walkthrough"):
                no_walkthrough.append(entry.get("title", entry["conv_id"][:8]))

    if no_walkthrough:
        suggestions.append(
            f"今日 {len(no_walkthrough)} 个对话缺少 `walkthrough.md`（{', '.join(no_walkthrough[:3])}）→ 建议在任务完成后补充技术实现记录"
        )

    # Check for failed delegates
    failed = [e for e in data.get("task_delegates", []) if e.get("status") != "success"]
    if failed:
        suggestions.append(
            f"{len(failed)} 个 delegate 任务失败 → 检查失败原因并重试或调整 prompt"
        )

    # Check for errors in journals
    total_errors = sum(len(e.get("errors", [])) for e in data.get("ag_conversations", []))
    if total_errors > 0:
        suggestions.append(
            f"今日 journal 中记录了 {total_errors} 个 AG 错误 → 考虑是否需要更新 GEMINI.md 或 skill 文档以防复发"
        )

    # Check for panel discussions with only 1 round
    for entry in data.get("panel_discussions", []):
        if entry.get("num_rounds", 0) <= 1:
            suggestions.append(
                f"Panel \"{entry.get('title', 'Untitled')}\" 只进行了 {entry.get('num_rounds', 0)} 轮 → 后续讨论可增加到 2-3 轮获得更深入分析"
            )

    if not suggestions:
        suggestions.append("今日工作模式良好，暂无特别建议。")

    return suggestions


def generate_tomorrow_items(grouped: dict, data: dict) -> list:
    """Generate AI draft of tomorrow's action items based on today's work."""
    items = []

    # Extract incomplete tasks from task.md references
    for entry in data.get("ag_conversations", []):
        if entry.get("has_task"):
            items.append(f"继续推进: {entry.get('title', entry['conv_id'][:8])}（有未完成 task.md）")

    # Re-try failed delegates
    for entry in data.get("task_delegates", []):
        if entry.get("status") != "success":
            items.append(f"重试失败任务: `{entry.get('task_id', 'unknown')}` ({entry.get('task_description', '')})")

    # Follow up on panel discussions without final report
    for entry in data.get("panel_discussions", []):
        if not entry.get("has_final_report"):
            items.append(f"完成 Panel Discussion \"{entry.get('title', '')}\" 的最终报告")

    if not items:
        items.append("暂无自动推断的明日事项。")

    return items


def generate_report(data: dict) -> str:
    """Generate the full markdown daily report."""
    config = load_projects_config()

    # Parse date from data
    start_str = data["date_range"]["start"]
    start_dt = datetime.fromisoformat(start_str)
    date_str = start_dt.strftime("%Y-%m-%d")
    now_str = datetime.now(TZ_LOCAL).strftime("%Y-%m-%d %H:%M")

    stats = data.get("stats", {})

    # Match all entries to projects
    all_entries = []
    for entry in data.get("ag_conversations", []):
        entry["_project"] = match_project(entry, config)
        all_entries.append(entry)
    for entry in data.get("panel_discussions", []):
        entry["_project"] = match_project(entry, config)
        all_entries.append(entry)
    for entry in data.get("task_delegates", []):
        entry["_project"] = match_project(entry, config)
        all_entries.append(entry)

    # Group by project
    grouped = defaultdict(list)
    for entry in all_entries:
        grouped[entry["_project"]].append(entry)

    # Build project display name mapping
    proj_display = {p["name"]: p["display"] for p in config.get("projects", [])}
    default_proj = config.get("default_project", "其他")

    # Order: configured projects first, then default
    project_order = [p["name"] for p in config.get("projects", []) if p["name"] in grouped]
    if default_proj in grouped:
        project_order.append(default_proj)

    # --- Build report ---
    lines = []
    lines.append(f"# 个人日报 — {date_str}")
    lines.append("")
    lines.append(f"> 生成时间: {now_str}")
    lines.append(
        f"> 覆盖范围: AG对话 {stats.get('ag_conversations', 0)}个 "
        f"| Panel Discussion {stats.get('panel_discussions', 0)}个 "
        f"| Task Delegate {stats.get('task_delegates', 0)}个"
    )
    lines.append("")

    for project_name in project_order:
        display = proj_display.get(project_name, project_name)
        entries = grouped[project_name]

        lines.append(f"## {display}")
        lines.append("")

        # Group by type within project
        ag_entries = [e for e in entries if e["type"] == "ag_conversation"]
        panel_entries = [e for e in entries if e["type"] == "panel_discussion"]
        delegate_entries = [e for e in entries if e["type"] == "task_delegate"]

        if ag_entries:
            lines.append("### AG 对话")
            lines.append("")
            for e in ag_entries:
                lines.append(format_ag_conversation(e))
            lines.append("")

        if panel_entries:
            lines.append("### Panel Discussion")
            lines.append("")
            for e in panel_entries:
                lines.append(format_panel_discussion(e))
            lines.append("")

        if delegate_entries:
            lines.append("### Delegate Tasks")
            lines.append("")
            for e in delegate_entries:
                lines.append(format_task_delegate(e))
            lines.append("")

    # --- Improvement Suggestions ---
    lines.append("---")
    lines.append("")
    lines.append("## 📋 改进建议（AI 初稿）")
    lines.append("")
    for suggestion in generate_improvement_suggestions(grouped, data):
        lines.append(f"- {suggestion}")
    lines.append("")

    # --- Tomorrow Items ---
    lines.append("## 📅 明日事项建议（AI 初稿）")
    lines.append("")
    for item in generate_tomorrow_items(grouped, data):
        lines.append(f"- [ ] {item}")
    lines.append("")
    lines.append("> ⚠️ 以上为 AI 初稿，生成后可与 AG 进一步讨论修改。")
    lines.append("")

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Daily Report Generator")
    parser.add_argument("--input", default=None, help="Input JSON file (default: stdin)")
    parser.add_argument("--output", default=None, help="Output markdown file (default: stdout)")
    args = parser.parse_args()

    # Read input
    if args.input:
        with open(args.input, "r", encoding="utf-8") as f:
            data = json.load(f)
    else:
        data = json.load(sys.stdin)

    # Generate report
    report = generate_report(data)

    # Write output
    if args.output:
        os.makedirs(os.path.dirname(args.output) or ".", exist_ok=True)
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(report)
        print(f"Report written to: {args.output}", file=sys.stderr)
    else:
        print(report)


if __name__ == "__main__":
    main()
