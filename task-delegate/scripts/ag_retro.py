#!/usr/bin/env python3
"""
ag_retro.py — Task Delegate Retrospective.

Analyzes past executor records to identify patterns, failures, and improvements.
Default: local mode (reads ~/.task-delegate/*/execution_record.json).
Optional: --langfuse mode (reads traces from Langfuse API).

Usage:
  python3 ag_retro.py [--days N] [--executor cc|gemini|codex|deepseek] [--json]
  python3 ag_retro.py --langfuse [--days N] [--limit N]    # Langfuse mode

Output:
  Prints a structured retrospective report to stdout.
  Saves detailed analysis to /tmp/ag_retro_report.json
"""

import argparse
import json
import os
import sys
from datetime import datetime, timedelta, timezone
from collections import defaultdict
from pathlib import Path


def fetch_local_records(days: int, executor: str | None) -> list:
    """Fetch task-delegate records from local filesystem."""
    td_dir = Path.home() / ".task-delegate"
    if not td_dir.exists():
        print(f"ERROR: {td_dir} not found", file=sys.stderr)
        return []

    since = datetime.now(timezone.utc) - timedelta(days=days)
    results = []

    for task_dir in sorted(td_dir.iterdir()):
        if not task_dir.is_dir():
            continue

        rec_path = task_dir / "execution_record.json"
        if not rec_path.exists():
            continue

        try:
            with open(rec_path) as f:
                rec = json.load(f)
        except (json.JSONDecodeError, OSError):
            continue

        # Filter by date
        started_at = rec.get("started_at", "")
        if started_at:
            try:
                ts = datetime.fromisoformat(started_at)
                if ts.tzinfo is None:
                    ts = ts.replace(tzinfo=timezone.utc)
                else:
                    ts = ts.astimezone(timezone.utc)
                if ts < since:
                    continue
            except (ValueError, TypeError):
                pass

        # Filter by executor
        backend = rec.get("backend", "unknown")
        if executor and backend != executor:
            continue

        results.append(rec)

    return results


def fetch_langfuse_traces(days: int, executor: str | None, limit: int) -> list:
    """Fetch task-delegate traces from Langfuse (v3 SDK)."""
    try:
        from langfuse import get_client
    except ImportError:
        print("ERROR: langfuse not installed. pip install langfuse", file=sys.stderr)
        sys.exit(1)

    if not os.environ.get("LANGFUSE_PUBLIC_KEY"):
        print("ERROR: LANGFUSE_PUBLIC_KEY not set", file=sys.stderr)
        sys.exit(1)

    lf = get_client()
    since = datetime.now(timezone.utc) - timedelta(days=days)

    traces_resp = lf.api.trace.list(
        tags="task-delegate",
        limit=limit,
    )

    results = []
    for t in traces_resp.data:
        if t.timestamp and t.timestamp < since:
            continue

        try:
            detail = lf.api.trace.get(t.id)
            observations = detail.observations if hasattr(detail, "observations") and detail.observations else []
        except Exception:
            observations = []

        spans = []
        for obs in observations:
            meta = obs.metadata if hasattr(obs, "metadata") and obs.metadata else {}
            spans.append({
                "name": obs.name if hasattr(obs, "name") else "unknown",
                "executor": meta.get("executor", "unknown") if isinstance(meta, dict) else "unknown",
                "role": meta.get("role", "unknown") if isinstance(meta, dict) else "unknown",
                "status": meta.get("status", "unknown") if isinstance(meta, dict) else "unknown",
                "duration_ms": meta.get("duration_ms", 0) if isinstance(meta, dict) else 0,
                "cost_usd": meta.get("cost_usd", 0) if isinstance(meta, dict) else 0,
            })

        results.append({
            "trace_id": t.id,
            "name": t.name,
            "timestamp": t.timestamp.isoformat() if t.timestamp else "",
            "spans": spans,
        })

    lf.flush()
    return results


def analyze_local(records: list) -> dict:
    """Analyze local execution records for patterns and improvements."""
    total = len(records)
    if total == 0:
        return {"status": "no_data", "message": "No task-delegate records found in the specified period."}

    executors = defaultdict(lambda: {"count": 0, "duration_s": 0, "failures": 0})
    roles = defaultdict(lambda: {"count": 0, "executors_used": set()})
    failures = []
    total_duration = 0
    prompt_sizes = []
    long_running = []

    for rec in records:
        backend = rec.get("backend", "unknown")
        status = rec.get("status", "unknown")
        duration = rec.get("duration_seconds", 0) or 0
        prompt_bytes = rec.get("prompt_bytes", 0) or 0
        role = rec.get("role", "default")
        task_id = rec.get("task_id", "unknown")

        executors[backend]["count"] += 1
        executors[backend]["duration_s"] += duration
        total_duration += duration

        roles[role]["count"] += 1
        roles[role]["executors_used"].add(backend)

        if prompt_bytes:
            prompt_sizes.append(prompt_bytes)

        if status in ("failed", "error"):
            executors[backend]["failures"] += 1
            failures.append({
                "task_id": task_id,
                "backend": backend,
                "role": role,
                "status": status,
                "exit_code": rec.get("exit_code", "?"),
                "duration": duration,
            })

        if duration > 600:
            long_running.append({
                "task_id": task_id,
                "backend": backend,
                "duration": duration,
            })

    # Convert sets to lists for JSON
    for r in roles.values():
        r["executors_used"] = sorted(r["executors_used"])

    # Identify patterns
    patterns = []

    if failures:
        patterns.append({
            "type": "failure_pattern",
            "severity": "high" if len(failures) > 2 else "medium",
            "description": f"{len(failures)} executor failures detected",
            "recommendation": "Review failure inputs — are prompts clear enough?",
        })

    if long_running:
        patterns.append({
            "type": "long_running",
            "severity": "medium",
            "description": f"{len(long_running)} tasks ran >10 minutes",
            "recommendation": "Consider adding --timeout or splitting into smaller tasks",
        })

    oversized = [s for s in prompt_sizes if s > 6000]
    if oversized:
        patterns.append({
            "type": "oversized_prompts",
            "severity": "medium" if len(oversized) < 5 else "high",
            "description": f"{len(oversized)} prompts exceed 6KB (max: {max(oversized)}b)",
            "recommendation": "Review prompt content — are you dictating HOW instead of WHAT?",
        })

    # Check backend diversity
    if len(executors) < 3 and total > 10:
        used = list(executors.keys())
        patterns.append({
            "type": "backend_concentration",
            "severity": "low",
            "description": f"Only {len(executors)} backend(s) used: {', '.join(used)}",
            "recommendation": "Consider DeepSeek for scout/audit tasks, Gemini for multimodal",
        })

    return {
        "status": "analyzed",
        "source": "local",
        "period_records": total,
        "total_duration_min": round(total_duration / 60, 1),
        "executor_stats": dict(executors),
        "role_stats": {k: {"count": v["count"], "executors_used": v["executors_used"]} for k, v in roles.items()},
        "failures": failures,
        "long_running": long_running,
        "prompt_stats": {
            "count": len(prompt_sizes),
            "avg_bytes": round(sum(prompt_sizes) / len(prompt_sizes)) if prompt_sizes else 0,
            "max_bytes": max(prompt_sizes) if prompt_sizes else 0,
            "oversized_count": len(oversized) if 'oversized' in dir() else 0,
        } if prompt_sizes else None,
        "patterns": patterns,
    }


def analyze_langfuse(traces: list) -> dict:
    """Analyze Langfuse traces for patterns."""
    total = len(traces)
    if total == 0:
        return {"status": "no_data", "message": "No task-delegate traces found."}

    executors = defaultdict(lambda: {"count": 0, "cost": 0, "duration_ms": 0, "failures": 0})
    roles = defaultdict(lambda: {"count": 0, "executors_used": set()})
    failures = []
    total_cost = 0
    total_duration_ms = 0

    for t in traces:
        for s in t["spans"]:
            ex = s["executor"]
            executors[ex]["count"] += 1
            executors[ex]["cost"] += s.get("cost_usd", 0)
            executors[ex]["duration_ms"] += s.get("duration_ms", 0)

            role = s["role"]
            roles[role]["count"] += 1
            roles[role]["executors_used"].add(ex)

            status = s.get("status", "unknown")
            if status in ("error", "parse_failed", "failed"):
                executors[ex]["failures"] += 1
                failures.append({
                    "trace": t["name"],
                    "role": role,
                    "executor": ex,
                    "status": status,
                })

            total_cost += s.get("cost_usd", 0)
            total_duration_ms += s.get("duration_ms", 0)

    for r in roles.values():
        r["executors_used"] = list(r["executors_used"])

    return {
        "status": "analyzed",
        "source": "langfuse",
        "period_traces": total,
        "total_cost_usd": round(total_cost, 2),
        "total_duration_min": round(total_duration_ms / 60000, 1),
        "executor_stats": dict(executors),
        "role_stats": {k: {"count": v["count"], "executors_used": v["executors_used"]} for k, v in roles.items()},
        "failures": failures,
        "patterns": [],
    }


def print_report(analysis: dict):
    """Print human-readable retrospective report."""
    if analysis["status"] == "no_data":
        print(f"📊 {analysis.get('message', 'No data found.')}")
        return

    source = analysis.get("source", "unknown")
    count_key = "period_records" if source == "local" else "period_traces"

    print("=" * 60)
    print(f"📊 TASK-DELEGATE RETROSPECTIVE ({source.upper()})")
    print("=" * 60)
    print(f"Records analyzed: {analysis.get(count_key, '?')}")
    if "total_cost_usd" in analysis:
        print(f"Total cost: ${analysis['total_cost_usd']}")
    print(f"Total duration: {analysis['total_duration_min']} min")
    print()

    print("── Executor Usage ──")
    for ex, stats in analysis["executor_stats"].items():
        count = stats["count"]
        fail_rate = stats.get("failures", 0) / count * 100 if count else 0
        dur_key = "duration_s" if "duration_s" in stats else "duration_ms"
        dur_val = stats.get(dur_key, 0)
        dur_label = f"{dur_val/60:.0f}min" if dur_key == "duration_s" else f"{dur_val/60000:.1f}min"
        extra = f", ${stats['cost']:.2f}" if "cost" in stats else ""
        print(f"  {ex}: {count} runs, {dur_label}{extra}, "
              f"{fail_rate:.0f}% failure rate")
    print()

    print("── Role Distribution ──")
    for role, stats in analysis["role_stats"].items():
        executors = ", ".join(stats["executors_used"]) if stats["executors_used"] else "unknown"
        print(f"  {role}: {stats['count']} runs via {executors}")
    print()

    if analysis.get("prompt_stats"):
        ps = analysis["prompt_stats"]
        print("── Prompt Stats ──")
        print(f"  avg={ps['avg_bytes']}b, max={ps['max_bytes']}b, oversized(>6KB)={ps.get('oversized_count', 0)}")
        print()

    if analysis.get("failures"):
        print("── Failures ──")
        for f in analysis["failures"]:
            task = f.get("task_id", f.get("trace", "?"))
            print(f"  ❌ {task} ({f.get('backend', f.get('executor', '?'))}): {f['status']}")
        print()

    if analysis.get("long_running"):
        print("── Long Running (>10min) ──")
        for lr in analysis["long_running"]:
            print(f"  ⏱️  {lr['task_id']} ({lr['backend']}): {lr['duration']}s")
        print()

    if analysis.get("patterns"):
        print("── Improvement Patterns ──")
        for p in analysis["patterns"]:
            icon = {"high": "🔴", "medium": "🟡", "low": "🟢"}.get(p["severity"], "⚪")
            print(f"  {icon} [{p['type']}] {p['description']}")
            print(f"     → {p['recommendation']}")
    print()


def main():
    parser = argparse.ArgumentParser(description="Task Delegate Retrospective")
    parser.add_argument("--days", type=int, default=7, help="Analyze records from last N days (default: 7)")
    parser.add_argument("--executor", choices=["cc", "gemini", "codex", "deepseek"], help="Filter by executor")
    parser.add_argument("--json", action="store_true", help="Output JSON only (no human report)")
    parser.add_argument("--langfuse", action="store_true", help="Use Langfuse API instead of local records")
    parser.add_argument("--limit", type=int, default=50, help="Max traces to fetch from Langfuse (default: 50)")
    args = parser.parse_args()

    if args.langfuse:
        traces = fetch_langfuse_traces(args.days, args.executor, args.limit)
        analysis = analyze_langfuse(traces)
    else:
        records = fetch_local_records(args.days, args.executor)
        analysis = analyze_local(records)

    if args.json:
        print(json.dumps(analysis, indent=2, default=str))
    else:
        print_report(analysis)

    # Always save detailed JSON
    report_path = "/tmp/ag_retro_report.json"
    with open(report_path, "w") as f:
        json.dump(analysis, f, indent=2, default=str)
    if not args.json:
        print(f"📁 Detailed report saved to: {report_path}")


if __name__ == "__main__":
    main()
