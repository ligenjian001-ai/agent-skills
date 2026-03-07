#!/usr/bin/env python3
"""
collect.py — Daily Report Data Collector

Scans three data sources and outputs structured JSON:
1. AG Conversations (brain artifacts)
2. Panel Discussions (~/.panel-discussions/)
3. Task Delegates (~/.task-delegate/)

Usage:
    python3 collect.py --date 20260307
    python3 collect.py --date 20260307 --end-date 20260308
    python3 collect.py --date 20260307 --summaries summaries.json
"""

import argparse
import glob
import json
import os
import re
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

# --- Configuration ---
BRAIN_DIR = os.path.expanduser("~/.gemini/antigravity/brain")
PANEL_DIR = os.path.expanduser("~/.panel-discussions")
DELEGATE_DIR = os.path.expanduser("~/.task-delegate")

TZ_LOCAL = timezone(timedelta(hours=8))  # Asia/Shanghai


def parse_date(date_str: str) -> datetime:
    """Parse YYYYMMDD string to datetime at start of day in local TZ."""
    return datetime.strptime(date_str, "%Y%m%d").replace(tzinfo=TZ_LOCAL)


def in_date_range(ts: datetime, start: datetime, end: datetime) -> bool:
    """Check if timestamp falls within [start, end) day range."""
    return start <= ts < end


def safe_read(path: str, max_lines: int = 0) -> str:
    """Read file content safely. Returns empty string on failure."""
    try:
        with open(path, "r", encoding="utf-8") as f:
            if max_lines > 0:
                lines = []
                for i, line in enumerate(f):
                    if i >= max_lines:
                        break
                    lines.append(line)
                return "".join(lines)
            return f.read()
    except (FileNotFoundError, PermissionError, UnicodeDecodeError):
        return ""


def extract_journal_summary(journal_text: str) -> dict:
    """Extract key info from conversation_journal.md."""
    result = {"user_goal": "", "decisions": [], "errors": []}

    # Extract initial goal from "> 初始目标:" line
    for line in journal_text.split("\n"):
        if "初始目标:" in line:
            result["user_goal"] = line.split("初始目标:", 1)[1].strip()
            break

    # Extract [决策] and [错误] entries
    for line in journal_text.split("\n"):
        if "[决策]" in line:
            result["decisions"].append(line.split("[决策]", 1)[1].strip().lstrip("*").strip())
        elif "[错误]" in line:
            result["errors"].append(line.split("[错误]", 1)[1].strip().lstrip("*").strip())

    return result


def extract_first_heading(text: str) -> str:
    """Extract the first # heading from markdown text."""
    for line in text.split("\n"):
        line = line.strip()
        if line.startswith("# "):
            return line[2:].strip()
    return ""


# --- Collector: AG Conversations ---
def collect_ag_conversations(start: datetime, end: datetime, summaries: dict = None) -> list:
    """Collect AG conversations active within the date range."""
    results = []

    if not os.path.isdir(BRAIN_DIR):
        return results

    for conv_id in os.listdir(BRAIN_DIR):
        conv_dir = os.path.join(BRAIN_DIR, conv_id)
        if not os.path.isdir(conv_dir) or conv_id == "tempmediaStorage":
            continue

        # Find newest metadata timestamp in this conversation
        latest_ts = None
        metadata_files = glob.glob(os.path.join(conv_dir, "*.metadata.json"))
        for mf in metadata_files:
            try:
                with open(mf, "r") as f:
                    meta = json.load(f)
                ts_str = meta.get("updatedAt", "")
                if ts_str:
                    # Parse ISO format: "2026-03-07T15:22:45.696135542Z"
                    ts_str = re.sub(r"\.\d+Z$", "+00:00", ts_str)
                    ts_str = ts_str.replace("Z", "+00:00")
                    ts = datetime.fromisoformat(ts_str).astimezone(TZ_LOCAL)
                    if latest_ts is None or ts > latest_ts:
                        latest_ts = ts
            except (json.JSONDecodeError, ValueError, KeyError):
                continue

        # Fallback: use file mtime if no metadata timestamp found or not in range
        if latest_ts is None or not in_date_range(latest_ts, start, end):
            # Check mtime of all files in directory (not recursively)
            latest_mtime = None
            for fname in os.listdir(conv_dir):
                if fname.startswith("."):
                    continue
                fpath = os.path.join(conv_dir, fname)
                try:
                    mt = datetime.fromtimestamp(os.path.getmtime(fpath), tz=TZ_LOCAL)
                    if latest_mtime is None or mt > latest_mtime:
                        latest_mtime = mt
                except OSError:
                    pass
            if latest_mtime and in_date_range(latest_mtime, start, end):
                latest_ts = latest_mtime
            else:
                continue  # Neither metadata nor mtime in range

        # Read conversation artifacts
        journal_text = safe_read(os.path.join(conv_dir, "conversation_journal.md"))
        walkthrough_text = safe_read(os.path.join(conv_dir, "walkthrough.md"), max_lines=40)
        task_text = safe_read(os.path.join(conv_dir, "task.md"), max_lines=30)

        journal_info = extract_journal_summary(journal_text) if journal_text else {}

        # Priority 1: Read conversation_summary.json (written by AG per ag-archive protocol)
        title = ""
        summary_text = ""
        conv_tags = []
        summary_json_path = os.path.join(conv_dir, "conversation_summary.json")
        if os.path.isfile(summary_json_path):
            try:
                with open(summary_json_path, "r", encoding="utf-8") as f:
                    conv_summary = json.load(f)
                title = conv_summary.get("title", "")
                summary_text = conv_summary.get("summary", "")
                conv_tags = conv_summary.get("tags", [])
            except (json.JSONDecodeError, ValueError):
                pass

        # Priority 2: AG-injected summaries (via --summaries flag)
        if not title and summaries and conv_id in summaries:
            title = summaries[conv_id].get("title", "")
            summary_text = summary_text or summaries[conv_id].get("summary", "")

        # Collect metadata summaries early (needed for title fallback)
        all_summaries = []
        for mf in metadata_files:
            try:
                with open(mf, "r") as f:
                    meta = json.load(f)
                s = meta.get("summary", "")
                if s:
                    all_summaries.append(s)
            except (json.JSONDecodeError, ValueError):
                continue

        # Fallback: extract title from walkthrough, journal goal, or metadata
        if not title:
            if walkthrough_text:
                heading = extract_first_heading(walkthrough_text)
                # Skip generic headings
                if heading and heading.lower() not in ("conversation journal", "journal", "walkthrough"):
                    title = heading
            if not title and journal_info.get("user_goal"):
                # Use user goal as title (truncate if too long)
                goal = journal_info["user_goal"]
                title = goal[:80] + ("..." if len(goal) > 80 else "")
            if not title and all_summaries:
                # Use first metadata summary
                title = all_summaries[0][:80] + ("..." if len(all_summaries[0]) > 80 else "")

        entry = {
            "type": "ag_conversation",
            "conv_id": conv_id,
            "conv_dir": conv_dir,
            "title": title,
            "summary": summary_text,
            "user_goal": journal_info.get("user_goal", ""),
            "decisions": journal_info.get("decisions", []),
            "errors": journal_info.get("errors", []),
            "has_walkthrough": bool(walkthrough_text),
            "has_task": bool(task_text),
            "metadata_summaries": all_summaries,
            "conv_tags": conv_tags,
            "updated_at": latest_ts.isoformat(),
        }
        results.append(entry)

    # Sort by updated_at
    results.sort(key=lambda x: x["updated_at"])
    return results


# --- Collector: Panel Discussions ---
def collect_panel_discussions(start: datetime, end: datetime) -> list:
    """Collect panel discussions within the date range."""
    results = []

    if not os.path.isdir(PANEL_DIR):
        return results

    for panel_name in os.listdir(PANEL_DIR):
        panel_dir = os.path.join(PANEL_DIR, panel_name)
        if not os.path.isdir(panel_dir):
            continue

        # Parse date from directory name: panel_YYYYMMDD_HHMM
        match = re.match(r"panel_(\d{8})_(\d{4})", panel_name)
        if not match:
            continue

        date_str = match.group(1)
        time_str = match.group(2)
        try:
            panel_ts = datetime.strptime(f"{date_str}{time_str}", "%Y%m%d%H%M").replace(tzinfo=TZ_LOCAL)
        except ValueError:
            continue

        if not in_date_range(panel_ts, start, end):
            continue

        # Read topic
        topic_text = safe_read(os.path.join(panel_dir, "topic.txt"))
        topic_title = ""
        for line in topic_text.split("\n"):
            line = line.strip()
            if line.startswith("# "):
                topic_title = line[2:].strip()
                break

        # Count rounds and collect roles
        rounds = []
        round_idx = 0
        while True:
            round_dir = os.path.join(panel_dir, f"round_{round_idx}")
            if not os.path.isdir(round_dir):
                break
            roles = [d for d in os.listdir(round_dir) if os.path.isdir(os.path.join(round_dir, d))]
            rounds.append({"round": round_idx, "roles": roles})
            round_idx += 1

        # Read latest round summary (first 30 lines)
        latest_summary = ""
        if rounds:
            last_round = rounds[-1]["round"]
            latest_summary = safe_read(
                os.path.join(panel_dir, f"round_{last_round}_summary.md"), max_lines=30
            )

        # Check for final report
        has_final_report = os.path.isfile(os.path.join(panel_dir, "final_report.md"))

        # Count user inputs
        user_inputs = sorted(glob.glob(os.path.join(panel_dir, "user_input_r*.md")))

        entry = {
            "type": "panel_discussion",
            "panel_id": panel_name,
            "title": topic_title,
            "timestamp": panel_ts.isoformat(),
            "num_rounds": len(rounds),
            "roles": rounds[0]["roles"] if rounds else [],
            "has_final_report": has_final_report,
            "num_user_inputs": len(user_inputs),
            "latest_summary_preview": latest_summary[:500] if latest_summary else "",
            "topic_text": topic_text[:1000] if topic_text else "",  # For project matching
        }
        results.append(entry)

    results.sort(key=lambda x: x["timestamp"])
    return results


# --- Collector: Task Delegates ---
def collect_task_delegates(start: datetime, end: datetime) -> list:
    """Collect task delegate executions within the date range."""
    results = []

    if not os.path.isdir(DELEGATE_DIR):
        return results

    for task_id in os.listdir(DELEGATE_DIR):
        task_dir = os.path.join(DELEGATE_DIR, task_id)
        if not os.path.isdir(task_dir):
            continue

        record_path = os.path.join(task_dir, "execution_record.json")
        if not os.path.isfile(record_path):
            continue

        try:
            with open(record_path, "r") as f:
                record = json.load(f)
        except (json.JSONDecodeError, FileNotFoundError):
            continue

        # Parse started_at
        started_str = record.get("started_at", "")
        if not started_str:
            continue

        try:
            started_ts = datetime.fromisoformat(started_str).astimezone(TZ_LOCAL)
        except ValueError:
            continue

        if not in_date_range(started_ts, start, end):
            continue

        # Read prompt first line for task description
        prompt_text = safe_read(os.path.join(task_dir, "prompt.txt"), max_lines=5)
        task_desc = ""
        for line in prompt_text.split("\n"):
            line = line.strip()
            if line.startswith("# "):
                task_desc = line[2:].strip()
                break

        entry = {
            "type": "task_delegate",
            "task_id": record.get("task_id", task_id),
            "task_dir": task_dir,
            "backend": record.get("backend", "unknown"),
            "project": record.get("project", ""),
            "status": record.get("status", "unknown"),
            "exit_code": record.get("exit_code"),
            "duration_human": record.get("duration_human", ""),
            "started_at": started_ts.isoformat(),
            "finished_at": record.get("finished_at", ""),
            "task_description": task_desc,
        }
        results.append(entry)

    results.sort(key=lambda x: x["started_at"])
    return results


# --- Main ---
def main():
    parser = argparse.ArgumentParser(description="Daily Report Data Collector")
    parser.add_argument("--date", required=True, help="Start date in YYYYMMDD format")
    parser.add_argument("--end-date", default=None, help="End date (exclusive) in YYYYMMDD format. Default: date + 1 day")
    parser.add_argument("--summaries", default=None, help="Path to JSON file with AG conversation summaries")
    parser.add_argument("--json", action="store_true", help="Output JSON (default: pretty print)")
    args = parser.parse_args()

    start = parse_date(args.date)
    if args.end_date:
        end = parse_date(args.end_date)
    else:
        end = start + timedelta(days=1)

    # Load summaries if provided
    summaries = None
    if args.summaries:
        try:
            with open(args.summaries, "r") as f:
                summaries = json.load(f)
        except (json.JSONDecodeError, FileNotFoundError) as e:
            print(f"Warning: Could not load summaries: {e}", file=sys.stderr)

    # Collect from all sources
    data = {
        "date_range": {"start": start.isoformat(), "end": end.isoformat()},
        "ag_conversations": collect_ag_conversations(start, end, summaries),
        "panel_discussions": collect_panel_discussions(start, end),
        "task_delegates": collect_task_delegates(start, end),
    }

    data["stats"] = {
        "ag_conversations": len(data["ag_conversations"]),
        "panel_discussions": len(data["panel_discussions"]),
        "task_delegates": len(data["task_delegates"]),
    }

    if args.json:
        print(json.dumps(data, ensure_ascii=False, indent=2))
    else:
        print(json.dumps(data, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
