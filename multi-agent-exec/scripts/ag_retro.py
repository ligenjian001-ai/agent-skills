#!/usr/bin/env python3
"""
ag_retro.py — Multi-Agent Retrospective via Langfuse traces.

Analyzes past executor traces to identify patterns, failures, and improvements.
Can be triggered anytime by AG or user.

Usage:
  python3 ag_retro.py [--days N] [--executor cc|gemini|codex] [--limit N]

Output:
  Prints a structured retrospective report to stdout.
  Saves detailed analysis to /tmp/ag_retro_report.json
"""

import argparse
import json
import os
import sys
from datetime import datetime, timedelta, timezone


def fetch_traces(days: int, executor: str | None, limit: int) -> list:
    """Fetch multi-agent traces from Langfuse (v3 SDK)."""
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

    # v3: use REST API wrapper to list traces
    traces_resp = lf.api.trace.list(
        tags="multi-agent",
        limit=limit,
    )

    results = []
    for t in traces_resp.data:
        if t.timestamp and t.timestamp < since:
            continue

        # v3: get full trace detail (includes observations)
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
                "input_tokens": meta.get("input_tokens", 0) if isinstance(meta, dict) else 0,
                "output_tokens": meta.get("output_tokens", 0) if isinstance(meta, dict) else 0,
                "input_preview": str(obs.input)[:200] if hasattr(obs, "input") and obs.input else "",
                "output_preview": str(obs.output)[:200] if hasattr(obs, "output") and obs.output else "",
            })

        results.append({
            "trace_id": t.id,
            "name": t.name,
            "timestamp": t.timestamp.isoformat() if t.timestamp else "",
            "tags": t.tags or [],
            "spans": spans,
        })

    lf.flush()
    return results


def analyze(traces: list) -> dict:
    """Analyze traces for patterns and improvements."""

    total = len(traces)
    if total == 0:
        return {"status": "no_data", "message": "No multi-agent traces found in the specified period."}

    # Aggregate stats
    executors = {}
    roles = {}
    failures = []
    total_cost = 0
    total_duration_ms = 0

    for t in traces:
        for s in t["spans"]:
            ex = s["executor"]
            executors.setdefault(ex, {"count": 0, "cost": 0, "duration_ms": 0, "failures": 0})
            executors[ex]["count"] += 1
            executors[ex]["cost"] += s.get("cost_usd", 0)
            executors[ex]["duration_ms"] += s.get("duration_ms", 0)

            role = s["role"]
            roles.setdefault(role, {"count": 0, "executors_used": set()})
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
                    "input_preview": s.get("input_preview", ""),
                    "output_preview": s.get("output_preview", ""),
                })

            total_cost += s.get("cost_usd", 0)
            total_duration_ms += s.get("duration_ms", 0)

    # Convert sets to lists for JSON serialization
    for r in roles.values():
        r["executors_used"] = list(r["executors_used"])

    # Identify patterns
    patterns = []

    # Check for repeated failures
    if failures:
        patterns.append({
            "type": "failure_pattern",
            "severity": "high" if len(failures) > 2 else "medium",
            "description": f"{len(failures)} executor failures detected",
            "recommendation": "Review failure inputs — are prompts clear enough? Are paths/env correct?",
        })

    # Check for cost efficiency
    for ex, stats in executors.items():
        if stats["count"] > 0:
            avg_cost = stats["cost"] / stats["count"]
            if avg_cost > 1.0:
                patterns.append({
                    "type": "cost_alert",
                    "severity": "medium",
                    "description": f"Executor '{ex}' averages ${avg_cost:.2f}/run",
                    "recommendation": "Consider simpler executor or tighter budget for routine tasks",
                })

    return {
        "status": "analyzed",
        "period_traces": total,
        "total_cost_usd": round(total_cost, 2),
        "total_duration_min": round(total_duration_ms / 60000, 1),
        "executor_stats": executors,
        "role_stats": roles,
        "failures": failures,
        "patterns": patterns,
    }


def print_report(analysis: dict):
    """Print human-readable retrospective report."""
    if analysis["status"] == "no_data":
        print("📊 No multi-agent traces found.")
        return

    print("=" * 60)
    print("📊 MULTI-AGENT RETROSPECTIVE REPORT")
    print("=" * 60)
    print(f"Traces analyzed: {analysis['period_traces']}")
    print(f"Total cost: ${analysis['total_cost_usd']}")
    print(f"Total duration: {analysis['total_duration_min']} min")
    print()

    print("── Executor Usage ──")
    for ex, stats in analysis["executor_stats"].items():
        fail_rate = stats["failures"] / stats["count"] * 100 if stats["count"] else 0
        print(f"  {ex}: {stats['count']} runs, ${stats['cost']:.2f} total, "
              f"{fail_rate:.0f}% failure rate")
    print()

    print("── Role Distribution ──")
    for role, stats in analysis["role_stats"].items():
        print(f"  {role}: {stats['count']} runs via {', '.join(stats['executors_used'])}")
    print()

    if analysis["failures"]:
        print("── Failures ──")
        for f in analysis["failures"]:
            print(f"  ❌ {f['trace']} / {f['role']} ({f['executor']}): {f['status']}")
            if f["output_preview"]:
                print(f"     Output: {f['output_preview'][:100]}")
        print()

    if analysis["patterns"]:
        print("── Improvement Patterns ──")
        for p in analysis["patterns"]:
            icon = "🔴" if p["severity"] == "high" else "🟡"
            print(f"  {icon} [{p['type']}] {p['description']}")
            print(f"     → {p['recommendation']}")
    print()


def main():
    parser = argparse.ArgumentParser(description="Multi-Agent Retrospective via Langfuse")
    parser.add_argument("--days", type=int, default=7, help="Analyze traces from last N days (default: 7)")
    parser.add_argument("--executor", choices=["cc", "gemini", "codex"], help="Filter by executor")
    parser.add_argument("--limit", type=int, default=50, help="Max traces to fetch (default: 50)")
    parser.add_argument("--json", action="store_true", help="Output JSON only (no human report)")
    args = parser.parse_args()

    traces = fetch_traces(args.days, args.executor, args.limit)
    analysis = analyze(traces)

    if args.json:
        print(json.dumps(analysis, indent=2, default=str))
    else:
        print_report(analysis)

    # Always save detailed JSON
    report_path = "/tmp/ag_retro_report.json"
    with open(report_path, "w") as f:
        json.dump(analysis, f, indent=2, default=str)
    print(f"📁 Detailed report saved to: {report_path}")


if __name__ == "__main__":
    main()
