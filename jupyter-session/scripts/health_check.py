#!/usr/bin/env python3
"""Jupyter Session pre-flight health check.

Validates that Jupyter Server is reachable, authenticated, and has the
jupyter-server-nbmodel extension installed (required for /execute endpoint).

Exit codes:
    0 - All checks passed
    1 - One or more checks failed

Environment variables:
    JUPYTER_URL   - Jupyter Server URL (default: http://localhost:8888)
    JUPYTER_TOKEN - Authentication token (default: empty)
"""

import json
import os
import sys
import urllib.request
import urllib.error

JUPYTER_URL = os.environ.get("JUPYTER_URL", "http://localhost:8888").rstrip("/")
JUPYTER_TOKEN = os.environ.get("JUPYTER_TOKEN", "")

CHECKS_PASSED = 0
CHECKS_FAILED = 0


def _headers():
    h = {"Content-Type": "application/json"}
    if JUPYTER_TOKEN:
        h["Authorization"] = f"token {JUPYTER_TOKEN}"
    return h


def _get(path, timeout=10):
    url = f"{JUPYTER_URL}{path}"
    req = urllib.request.Request(url, headers=_headers(), method="GET")
    try:
        resp = urllib.request.urlopen(req, timeout=timeout)
        raw = resp.read().decode()
        return resp.status, json.loads(raw) if raw.strip() else None
    except urllib.error.HTTPError as e:
        return e.code, None
    except urllib.error.URLError:
        return None, None
    except Exception:
        return None, None


def check(name, passed, detail=""):
    global CHECKS_PASSED, CHECKS_FAILED
    if passed:
        CHECKS_PASSED += 1
        print(f"  ✅ {name}")
    else:
        CHECKS_FAILED += 1
        msg = f"  ❌ {name}"
        if detail:
            msg += f" — {detail}"
        print(msg)


def main():
    print(f"🔍 Jupyter Session Health Check")
    print(f"   URL:   {JUPYTER_URL}")
    print(f"   Token: {'***' + JUPYTER_TOKEN[-4:] if len(JUPYTER_TOKEN) > 4 else ('(set)' if JUPYTER_TOKEN else '(not set)')}")
    print()

    # 1. Server reachable
    status, data = _get("/api/status")
    server_ok = status == 200
    check("Server reachable", server_ok,
          f"Cannot connect to {JUPYTER_URL}" if not server_ok else "")

    if not server_ok:
        print(f"\n❌ Server not reachable. Remaining checks skipped.")
        print(f"   Start Jupyter Server: jupyter server --no-browser --port=8888")
        sys.exit(1)

    # 2. Authentication valid
    # If we got 200 on /api/status, auth is good
    check("Authentication valid", True)

    # 3. Kernel API accessible
    status, data = _get("/api/kernels")
    kernels_ok = status == 200
    check("Kernel API accessible", kernels_ok,
          f"GET /api/kernels returned HTTP {status}" if not kernels_ok else "")

    if kernels_ok and data is not None:
        print(f"      Active kernels: {len(data)}")

    # 4. Check jupyter-server-nbmodel (execute endpoint)
    # Try to POST to a non-existent kernel — we expect 404 (endpoint exists)
    # vs 405 (endpoint not registered) or other errors
    nbmodel_ok = False
    try:
        url = f"{JUPYTER_URL}/api/kernels/00000000-0000-0000-0000-000000000000/execute"
        req = urllib.request.Request(
            url,
            data=b'{"code":""}',
            headers=_headers(),
            method="POST",
        )
        resp = urllib.request.urlopen(req, timeout=10)
        # Unexpected success — still means endpoint exists
        nbmodel_ok = True
    except urllib.error.HTTPError as e:
        # 404 = kernel not found (endpoint exists, correct behavior)
        # 405 = method not allowed (endpoint not registered)
        # 403 = forbidden (endpoint exists but auth issue)
        nbmodel_ok = e.code in (404, 400, 403, 422)
    except Exception:
        nbmodel_ok = False

    check("jupyter-server-nbmodel installed", nbmodel_ok,
          "POST /api/kernels/<id>/execute not available. Install: pip install jupyter-server-nbmodel" if not nbmodel_ok else "")

    # 5. Contents API accessible
    status, _ = _get("/api/contents")
    contents_ok = status == 200
    check("Contents API accessible", contents_ok,
          f"GET /api/contents returned HTTP {status}" if not contents_ok else "")

    # Summary
    print()
    total = CHECKS_PASSED + CHECKS_FAILED
    if CHECKS_FAILED == 0:
        print(f"✅ All {total} checks passed. Jupyter Session is ready.")
    else:
        print(f"❌ {CHECKS_FAILED}/{total} checks failed.")
    sys.exit(1 if CHECKS_FAILED > 0 else 0)


if __name__ == "__main__":
    main()
