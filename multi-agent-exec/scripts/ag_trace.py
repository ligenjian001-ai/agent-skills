#!/usr/bin/env python3
"""
ag_trace.py — Async Langfuse logger for multi-agent executor traces.

Called by ag_dispatch.sh AFTER executor completes. Fire-and-forget.
Failures are silently ignored — tracing never blocks execution.

Expects Langfuse env vars:
  LANGFUSE_PUBLIC_KEY, LANGFUSE_SECRET_KEY, LANGFUSE_HOST (optional)
"""

import argparse
import json
import os
import sys
from datetime import datetime, timezone


def parse_cc_output(raw_output_path: str) -> dict:
    """Parse CC's --output-format json response."""
    try:
        with open(raw_output_path) as f:
            data = json.load(f)
        return {
            "cost_usd": data.get("total_cost_usd", 0),
            "duration_ms": data.get("duration_ms", 0),
            "num_turns": data.get("num_turns", 0),
            "input_tokens": data.get("usage", {}).get("input_tokens", 0),
            "output_tokens": data.get("usage", {}).get("output_tokens", 0),
            "result_preview": str(data.get("result", ""))[:500],
            "is_error": data.get("is_error", False),
            "status": "error" if data.get("is_error") else "completed",
        }
    except Exception:
        return {"status": "parse_failed"}


def parse_gemini_output(raw_output_path: str) -> dict:
    """Parse Gemini's --output-format json response."""
    try:
        with open(raw_output_path) as f:
            data = json.load(f)
        # Gemini JSON format may differ — adapt as needed
        return {
            "cost_usd": data.get("total_cost_usd", 0),
            "duration_ms": data.get("duration_ms", 0),
            "num_turns": data.get("num_turns", 0),
            "input_tokens": data.get("usage", {}).get("input_tokens", 0),
            "output_tokens": data.get("usage", {}).get("output_tokens", 0),
            "result_preview": str(data.get("result", ""))[:500],
            "status": "completed",
        }
    except Exception:
        return {"status": "parse_failed"}


def parse_codex_output(raw_output_path: str) -> dict:
    """Parse Codex exec stdout (plain text)."""
    try:
        with open(raw_output_path) as f:
            content = f.read()
        return {
            "result_preview": content[:500],
            "output_length": len(content),
            "status": "completed",
        }
    except Exception:
        return {"status": "parse_failed"}


def log_to_langfuse(args, parsed: dict, prompt_content: str):
    """Send trace to Langfuse (v3 SDK — OpenTelemetry-based)."""
    try:
        from langfuse import get_client
    except ImportError:
        return  # silently skip if langfuse not installed

    if not os.environ.get("LANGFUSE_PUBLIC_KEY"):
        return  # silently skip if not configured

    try:
        lf = get_client()

        # Derive task_id from IPC dir structure: /tmp/ag_ipc/{task_id}/{role}/
        ipc_parts = args.ipc_dir.rstrip("/").split("/")
        task_id = ipc_parts[-2] if len(ipc_parts) >= 2 else "unknown"

        # v3: context manager pattern — spans auto-end when exiting `with` block
        with lf.start_as_current_span(
            name=f"multi-agent:{task_id}",
            input=prompt_content[:2000],
        ):
            # Set trace-level attributes (tags, metadata)
            lf.update_current_trace(
                tags=["multi-agent", args.executor, args.role],
                metadata={
                    "project": args.project,
                    "task_id": task_id,
                },
            )

            # Create child span for the executor role
            with lf.start_as_current_span(
                name=args.role,
                input=prompt_content[:2000],
                output=parsed.get("result_preview", ""),
                metadata={
                    "executor": args.executor,
                    "role": args.role,
                    "duration_ms": args.duration_ms,
                    "cost_usd": parsed.get("cost_usd", 0),
                    "num_turns": parsed.get("num_turns", 0),
                    "input_tokens": parsed.get("input_tokens", 0),
                    "output_tokens": parsed.get("output_tokens", 0),
                    "status": parsed.get("status", "unknown"),
                },
            ):
                trace_id = lf.get_current_trace_id()

        # Update execution_record.json with trace ID
        exec_record_path = os.path.join(args.ipc_dir, "execution_record.json")
        if os.path.exists(exec_record_path) and trace_id:
            with open(exec_record_path) as f:
                record = json.load(f)
            record["langfuse_trace_id"] = trace_id
            record.update({k: v for k, v in parsed.items() if k != "result_preview"})
            with open(exec_record_path, "w") as f:
                json.dump(record, f, indent=2)

        lf.flush()
    except Exception as e:
        # Log error to stderr for debugging, but never block execution
        import sys
        print(f"[ag_trace] Langfuse error (non-fatal): {e}", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description="Log executor trace to Langfuse")
    parser.add_argument("--executor", required=True, choices=["cc", "claude", "gemini", "codex"])
    parser.add_argument("--role", required=True)
    parser.add_argument("--ipc-dir", required=True)
    parser.add_argument("--project", required=True)
    parser.add_argument("--duration-ms", type=int, default=0)
    args = parser.parse_args()

    raw_output = os.path.join(args.ipc_dir, "raw_output.json")
    prompt_file = os.path.join(args.ipc_dir, "prompt.txt")

    # Parse executor output
    parsers = {
        "cc": parse_cc_output,
        "claude": parse_cc_output,
        "gemini": parse_gemini_output,
        "codex": parse_codex_output,
    }
    parsed = parsers.get(args.executor, parse_codex_output)(raw_output)

    # Read prompt
    prompt_content = ""
    try:
        with open(prompt_file) as f:
            prompt_content = f.read()
    except Exception:
        pass

    # Log to Langfuse
    log_to_langfuse(args, parsed, prompt_content)


if __name__ == "__main__":
    main()
