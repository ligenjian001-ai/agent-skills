#!/usr/bin/env python3
"""Jupyter Server REST API CLI wrapper.

Provides subcommands for kernel lifecycle and code execution via
the Jupyter Server REST API + jupyter-server-nbmodel execute endpoint.

Dependencies: Python stdlib only (urllib, json, argparse).

Environment variables:
    JUPYTER_URL   - Jupyter Server URL (default: http://localhost:8888)
    JUPYTER_TOKEN - Authentication token (default: empty)
"""

import argparse
import json
import os
import sys
import time
import urllib.request
import urllib.error
import urllib.parse
import base64
import hashlib
from pathlib import Path

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

JUPYTER_URL = os.environ.get("JUPYTER_URL", "http://localhost:8888").rstrip("/")
JUPYTER_TOKEN = os.environ.get("JUPYTER_TOKEN", "")

DEFAULT_MAX_OUTPUT = 5000
POLL_INTERVAL = 0.5       # seconds between poll requests
POLL_TIMEOUT = 120        # max seconds to wait for execution result
IMAGE_DIR = Path("/tmp/jupyter_plots")

# ---------------------------------------------------------------------------
# HTTP helpers (stdlib only)
# ---------------------------------------------------------------------------


def _headers():
    """Return common headers with auth token."""
    h = {"Content-Type": "application/json"}
    if JUPYTER_TOKEN:
        h["Authorization"] = f"token {JUPYTER_TOKEN}"
    return h


def _request(method, path, body=None, timeout=30):
    """Make an HTTP request to the Jupyter Server.

    Returns (status_code, headers, parsed_json_or_None).
    Raises SystemExit on connection failure.
    """
    url = f"{JUPYTER_URL}{path}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, headers=_headers(), method=method)
    try:
        resp = urllib.request.urlopen(req, timeout=timeout)
        raw = resp.read().decode()
        parsed = json.loads(raw) if raw.strip() else None
        return resp.status, resp.headers, parsed
    except urllib.error.HTTPError as e:
        raw = e.read().decode() if e.fp else ""
        try:
            parsed = json.loads(raw) if raw.strip() else None
        except json.JSONDecodeError:
            parsed = {"error": raw}
        return e.code, e.headers, parsed
    except urllib.error.URLError as e:
        print(f"❌ Connection failed: {e.reason}", file=sys.stderr)
        print(f"   URL: {url}", file=sys.stderr)
        print(f"   Is Jupyter Server running at {JUPYTER_URL}?", file=sys.stderr)
        sys.exit(1)


def _get(path, timeout=15):
    return _request("GET", path, timeout=timeout)


def _post(path, body=None, timeout=30):
    return _request("POST", path, body=body, timeout=timeout)


def _delete(path, timeout=15):
    return _request("DELETE", path, timeout=timeout)


# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------


def _truncate(text, max_chars):
    """Truncate text with indicator if too long."""
    if len(text) <= max_chars:
        return text
    half = max_chars // 2 - 30
    return (
        text[:half]
        + f"\n\n... [TRUNCATED: {len(text)} chars total, showing first {half} + last {half}] ...\n\n"
        + text[-half:]
    )


def _save_image(data_b64, mime_type="image/png"):
    """Save base64-encoded image to file, return path."""
    IMAGE_DIR.mkdir(parents=True, exist_ok=True)
    ext = mime_type.split("/")[-1]
    if ext == "svg+xml":
        ext = "svg"
    # Use hash of content for dedup
    digest = hashlib.md5(data_b64.encode()).hexdigest()[:10]
    ts = time.strftime("%H%M%S")
    fname = f"plot_{ts}_{digest}.{ext}"
    fpath = IMAGE_DIR / fname
    with open(fpath, "wb") as f:
        f.write(base64.b64decode(data_b64))
    return str(fpath)


def _format_outputs(outputs, max_chars):
    """Format execution outputs into a readable string.

    Handles text, error, and image outputs. Images are saved to files.
    """
    parts = []
    for out in outputs:
        output_type = out.get("output_type", "")

        if output_type == "stream":
            text = out.get("text", "")
            if isinstance(text, list):
                text = "".join(text)
            parts.append(text)

        elif output_type == "execute_result":
            data = out.get("data", {})
            if "text/plain" in data:
                text = data["text/plain"]
                if isinstance(text, list):
                    text = "".join(text)
                parts.append(text)
            # Check for images in execute_result
            for mime in ("image/png", "image/jpeg", "image/svg+xml"):
                if mime in data:
                    fpath = _save_image(data[mime], mime)
                    parts.append(f"[Image saved: {fpath}]")

        elif output_type == "display_data":
            data = out.get("data", {})
            for mime in ("image/png", "image/jpeg", "image/svg+xml"):
                if mime in data:
                    fpath = _save_image(data[mime], mime)
                    parts.append(f"[Image saved: {fpath}]")
                    break
            else:
                if "text/plain" in data:
                    text = data["text/plain"]
                    if isinstance(text, list):
                        text = "".join(text)
                    parts.append(text)

        elif output_type == "error":
            ename = out.get("ename", "Error")
            evalue = out.get("evalue", "")
            tb = out.get("traceback", [])
            # Strip ANSI escape codes from traceback
            import re
            ansi_re = re.compile(r"\x1b\[[0-9;]*m")
            tb_clean = [ansi_re.sub("", line) for line in tb]
            parts.append(f"❌ {ename}: {evalue}\n" + "\n".join(tb_clean))

    result = "\n".join(parts)
    return _truncate(result, max_chars)


# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------


def cmd_status(args):
    """Check Jupyter Server status."""
    status, _, data = _get("/api/status")
    if status == 200:
        started = data.get("started", "unknown")
        kernels = data.get("kernels", "?")
        connections = data.get("connections", 0)
        print(f"✅ Jupyter Server is running")
        print(f"   URL:         {JUPYTER_URL}")
        print(f"   Started:     {started}")
        print(f"   Kernels:     {kernels}")
        print(f"   Connections: {connections}")
    else:
        print(f"❌ Jupyter Server returned status {status}", file=sys.stderr)
        if data:
            print(f"   {json.dumps(data, indent=2)}", file=sys.stderr)
        sys.exit(1)


def cmd_kernel(args):
    """Kernel lifecycle management."""
    action = args.kernel_action

    if action == "list":
        status, _, data = _get("/api/kernels")
        if status != 200:
            print(f"❌ Failed to list kernels (HTTP {status})", file=sys.stderr)
            sys.exit(1)
        if not data:
            print("No active kernels.")
            return
        print(f"{'ID':<40} {'Name':<15} {'State':<12} {'Connections'}")
        print("-" * 80)
        for k in data:
            kid = k.get("id", "?")
            name = k.get("name", "?")
            state = k.get("execution_state", "?")
            conns = k.get("connections", 0)
            print(f"{kid:<40} {name:<15} {state:<12} {conns}")

    elif action == "start":
        kernel_name = args.kernel_name or "python3"
        status, _, data = _post("/api/kernels", {"name": kernel_name})
        if status in (200, 201):
            kid = data.get("id", "?")
            print(f"✅ Kernel started: {kid}")
            print(f"   Name: {data.get('name', '?')}")
        else:
            print(f"❌ Failed to start kernel (HTTP {status})", file=sys.stderr)
            if data:
                print(f"   {json.dumps(data)}", file=sys.stderr)
            sys.exit(1)

    elif action == "stop":
        if not args.kernel_id:
            print("❌ kernel_id required for stop", file=sys.stderr)
            sys.exit(1)
        status, _, _ = _delete(f"/api/kernels/{args.kernel_id}")
        if status == 204:
            print(f"✅ Kernel stopped: {args.kernel_id}")
        else:
            print(f"❌ Failed to stop kernel (HTTP {status})", file=sys.stderr)
            sys.exit(1)

    elif action == "restart":
        if not args.kernel_id:
            print("❌ kernel_id required for restart", file=sys.stderr)
            sys.exit(1)
        status, _, data = _post(f"/api/kernels/{args.kernel_id}/restart")
        if status == 200:
            print(f"✅ Kernel restarted: {args.kernel_id}")
        else:
            print(f"❌ Failed to restart kernel (HTTP {status})", file=sys.stderr)
            sys.exit(1)
    else:
        print(f"❌ Unknown kernel action: {action}", file=sys.stderr)
        sys.exit(1)


def _poll_execution(kernel_id, request_uid, timeout, max_chars):
    """Poll for execution result via nbmodel requests endpoint."""
    path = f"/api/kernels/{kernel_id}/requests/{request_uid}"
    deadline = time.time() + timeout
    interval = POLL_INTERVAL

    while time.time() < deadline:
        status, _, data = _get(path, timeout=15)

        if status == 200 and data:
            # Check if execution is complete
            exec_status = data.get("status", "")

            if exec_status in ("ok", "error", "abort"):
                outputs_raw = data.get("outputs", [])
                # outputs may be a JSON string — parse if needed
                if isinstance(outputs_raw, str):
                    try:
                        outputs = json.loads(outputs_raw)
                    except json.JSONDecodeError:
                        outputs = []
                else:
                    outputs = outputs_raw
                result_text = _format_outputs(outputs, max_chars)

                if exec_status == "ok":
                    # Include execute_result if present at top level
                    execute_result = data.get("execute_result", {})
                    if execute_result and execute_result.get("data"):
                        er_data = execute_result["data"]
                        if "text/plain" in er_data:
                            extra = er_data["text/plain"]
                            if isinstance(extra, list):
                                extra = "".join(extra)
                            if extra and extra not in result_text:
                                result_text = (result_text + "\n" + extra).strip()
                    if result_text:
                        print(result_text)
                    else:
                        print("(no output)")
                    return

                elif exec_status == "error":
                    if result_text:
                        print(result_text, file=sys.stderr)
                    else:
                        ename = data.get("ename", "Error")
                        evalue = data.get("evalue", "unknown")
                        print(f"❌ {ename}: {evalue}", file=sys.stderr)
                    sys.exit(1)

                elif exec_status == "abort":
                    print("❌ Execution aborted.", file=sys.stderr)
                    sys.exit(1)

            # Still running — continue polling
        elif status == 404:
            # Request not found — may still be initializing
            pass

        time.sleep(interval)
        # Gradual backoff up to 2s
        interval = min(interval * 1.2, 2.0)

    print(f"❌ Execution timed out after {timeout}s", file=sys.stderr)
    sys.exit(1)


def cmd_execute(args):
    """Execute code on a kernel."""
    kernel_id = args.kernel_id
    code = args.code
    max_chars = args.max_output
    timeout = args.timeout

    # Submit code for execution
    status, headers, data = _post(
        f"/api/kernels/{kernel_id}/execute",
        {"code": code},
        timeout=30,
    )

    if status == 202:
        # Accepted — extract request UID from Location header or response
        location = headers.get("Location", "")
        if location:
            # Location: /api/kernels/<id>/requests/<uid>
            request_uid = location.rstrip("/").split("/")[-1]
        elif data and "id" in data:
            request_uid = data["id"]
        else:
            print("❌ Execute accepted but no request ID returned", file=sys.stderr)
            sys.exit(1)
        _poll_execution(kernel_id, request_uid, timeout, max_chars)

    elif status == 200:
        # Some versions return result directly
        if data:
            outputs = data.get("outputs", [])
            result = _format_outputs(outputs, max_chars)
            if result:
                print(result)
            else:
                print("(no output)")
        else:
            print("(no output)")

    else:
        print(f"❌ Execute failed (HTTP {status})", file=sys.stderr)
        if data:
            print(f"   {json.dumps(data)}", file=sys.stderr)
        sys.exit(1)


def cmd_execute_file(args):
    """Execute a Python file on a kernel."""
    kernel_id = args.kernel_id
    file_path = args.file_path

    try:
        with open(file_path, "r") as f:
            code = f.read()
    except FileNotFoundError:
        print(f"❌ File not found: {file_path}", file=sys.stderr)
        sys.exit(1)
    except IOError as e:
        print(f"❌ Cannot read file: {e}", file=sys.stderr)
        sys.exit(1)

    print(f"Executing {file_path} ({len(code)} chars)...")
    # Reuse execute logic
    args.code = code
    cmd_execute(args)


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------


def main():
    global JUPYTER_URL, JUPYTER_TOKEN

    parser = argparse.ArgumentParser(
        description="Jupyter Server REST API CLI",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--url", default=None,
        help=f"Jupyter Server URL (env: JUPYTER_URL, default: {JUPYTER_URL})",
    )
    parser.add_argument(
        "--token", default=None,
        help="Jupyter Server token (env: JUPYTER_TOKEN)",
    )

    sub = parser.add_subparsers(dest="command", help="Subcommand")

    # status
    sub.add_parser("status", help="Check Jupyter Server status")

    # kernel
    kernel_p = sub.add_parser("kernel", help="Kernel lifecycle management")
    kernel_p.add_argument(
        "kernel_action", choices=["list", "start", "stop", "restart"],
        help="Kernel action",
    )
    kernel_p.add_argument("kernel_id", nargs="?", default=None, help="Kernel ID (for stop/restart)")
    kernel_p.add_argument("--name", dest="kernel_name", default=None, help="Kernel spec name (for start, default: python3)")

    # execute
    exec_p = sub.add_parser("execute", help="Execute code on a kernel")
    exec_p.add_argument("kernel_id", help="Kernel ID")
    exec_p.add_argument("code", help="Python code to execute")
    exec_p.add_argument(
        "--max-output", type=int, default=DEFAULT_MAX_OUTPUT,
        help=f"Max output chars (default: {DEFAULT_MAX_OUTPUT})",
    )
    exec_p.add_argument(
        "--timeout", type=int, default=POLL_TIMEOUT,
        help=f"Execution timeout in seconds (default: {POLL_TIMEOUT})",
    )

    # execute-file
    execf_p = sub.add_parser("execute-file", help="Execute a Python file on a kernel")
    execf_p.add_argument("kernel_id", help="Kernel ID")
    execf_p.add_argument("file_path", help="Path to Python file")
    execf_p.add_argument(
        "--max-output", type=int, default=DEFAULT_MAX_OUTPUT,
        help=f"Max output chars (default: {DEFAULT_MAX_OUTPUT})",
    )
    execf_p.add_argument(
        "--timeout", type=int, default=POLL_TIMEOUT,
        help=f"Execution timeout in seconds (default: {POLL_TIMEOUT})",
    )

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    # Override globals from CLI args
    if args.url:
        JUPYTER_URL = args.url.rstrip("/")
    if args.token:
        JUPYTER_TOKEN = args.token

    # Dispatch
    handlers = {
        "status": cmd_status,
        "kernel": cmd_kernel,
        "execute": cmd_execute,
        "execute-file": cmd_execute_file,
    }
    handlers[args.command](args)


if __name__ == "__main__":
    main()
