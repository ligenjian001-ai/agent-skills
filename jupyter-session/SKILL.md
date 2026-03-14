---
name: jupyter-session
description: "Persistent Jupyter kernel sessions for data analysis. Execute Python code, manage kernels, handle image outputs via Jupyter Server REST API. Use when user needs data exploration, plotting, or interactive computation."
---

# Jupyter Session

> **ROLE**: AG uses a **long-running Jupyter kernel** for stateful data analysis. AG sends code to the kernel via a CLI wrapper and reads the output. AG does NOT use Jupyter MCP — it uses the REST API directly via `jupyter_api.py`.

## Architecture

```
┌──────────┐    CLI (tmux)     ┌──────────────┐   REST API    ┌─────────────────┐
│    AG    │ ──────────────► │ jupyter_api.py │ ──────────► │ Jupyter Server  │
│          │ ◄────── stdout   │  (stdlib only) │ ◄──────────  │ + nbmodel ext   │
└──────────┘                  └──────────────┘               └─────────────────┘
                                                                    │
                                                              ┌─────┴─────┐
                                                              │  Kernel   │
                                                              │ (python3) │
                                                              └───────────┘
```

- **Jupyter Server**: User-managed, long-running process (not started by this skill)
- **jupyter-server-nbmodel**: Provides `POST /api/kernels/<id>/execute` endpoint
- **jupyter_api.py**: Stdlib-only CLI wrapper, called via tmux

## Variables

```
{SCRIPT}       = /home/lgj/agent-skills/jupyter-session/scripts/jupyter_api.py
{HEALTH}       = /home/lgj/agent-skills/jupyter-session/scripts/health_check.py
{KERNEL_ID}    = kernel UUID (from `kernel start` or `kernel list`)
```

Environment (must be set before use):
```bash
export JUPYTER_URL=http://localhost:8888    # Jupyter Server URL
export JUPYTER_TOKEN=<token>                # Auth token
```

## Phase 0 — Pre-Flight Check

Before first use in a conversation, run the health check:

```bash
python3 {HEALTH}
```

**Expected output**: All 5 checks pass (✅). If any fail, fix before proceeding.

If `jupyter-server-nbmodel` check fails:
```bash
pip install jupyter-server-nbmodel
# Then restart Jupyter Server
```

## Phase 1 — Kernel Lifecycle

### List existing kernels
```bash
python3 {SCRIPT} kernel list
```

### Start a new kernel
```bash
python3 {SCRIPT} kernel start
```
Output includes kernel ID — save it as `{KERNEL_ID}` for subsequent commands.

### Reuse existing kernel
If `kernel list` shows an active kernel, reuse it instead of starting a new one. Kernel state (variables, imports) persists across execute calls.

### Restart kernel (clear state)
```bash
python3 {SCRIPT} kernel restart {KERNEL_ID}
```

### Stop kernel (cleanup)
```bash
python3 {SCRIPT} kernel stop {KERNEL_ID}
```

## Phase 2 — Code Execution

### Execute inline code
```bash
python3 {SCRIPT} execute {KERNEL_ID} "import pandas as pd; df = pd.read_csv('data.csv'); print(df.head())"
```

### Execute a Python file
```bash
python3 {SCRIPT} execute-file {KERNEL_ID} /path/to/script.py
```

### Execution options
```bash
# Custom output limit (default: 5000 chars)
python3 {SCRIPT} execute {KERNEL_ID} "print('x' * 10000)" --max-output 2000

# Custom timeout (default: 120s)
python3 {SCRIPT} execute {KERNEL_ID} "import time; time.sleep(60); print('done')" --timeout 180
```

### Multi-step analysis pattern
Kernel state persists — use multiple execute calls for iterative analysis:

```bash
# Step 1: Load data
python3 {SCRIPT} execute {KERNEL_ID} "import pandas as pd; df = pd.read_csv('sales.csv')"

# Step 2: Explore
python3 {SCRIPT} execute {KERNEL_ID} "print(df.shape); print(df.dtypes)"

# Step 3: Analyze
python3 {SCRIPT} execute {KERNEL_ID} "print(df.groupby('region').sum())"
```

### Image output handling
When code produces plots, images are auto-saved to `/tmp/jupyter_plots/` and the file path is returned:

```bash
python3 {SCRIPT} execute {KERNEL_ID} "
import matplotlib.pyplot as plt
plt.figure(figsize=(10,6))
plt.plot([1,2,3,4], [1,4,2,3])
plt.title('Test Plot')
plt.savefig('/tmp/jupyter_plots/my_plot.png')
plt.show()
"
```

Output: `[Image saved: /tmp/jupyter_plots/plot_143022_a1b2c3d4e5.png]`

**Best practice**: Always call `plt.savefig()` explicitly before `plt.show()` for reliable image capture.

## Mandatory Rules

1. **ALWAYS run health check** (`{HEALTH}`) before first kernel operation in a conversation.
2. **REUSE existing kernels** — check `kernel list` before starting a new one. Each idle kernel uses ~55 MB RAM.
3. **TRUNCATE large DataFrames** — use `df.head(20)` or `df.describe()`, never print a raw large DataFrame.
4. **SAVE plots explicitly** — use `plt.savefig('/tmp/jupyter_plots/name.png')` before `plt.show()`. Do not rely on inline base64 capture alone.
5. **QUOTE code properly** — when passing multi-line code via CLI, use proper shell quoting to avoid parsing issues.
6. **STOP kernel when done** — if the user's analysis task is complete, offer to stop the kernel to free resources.

## Anti-Patterns

❌ Starting a new kernel when one already exists
   → Run `kernel list` first and reuse the active kernel

❌ Printing entire DataFrame: `print(df)` on a 10k-row dataset
   → Use `print(df.head(20))` or `print(df.describe())`; set `--max-output` for safety

❌ Passing base64 image data back to AG context
   → Images are auto-saved to `/tmp/jupyter_plots/`; reference the file path only

❌ Running long code strings without `execute-file`
   → For code > 5 lines, write to a temp `.py` file and use `execute-file`

❌ Skipping health check and assuming server is running
   → Always verify with `health_check.py` at conversation start

❌ Using Jupyter MCP tools instead of this CLI wrapper
   → MCP layer has image overflow and error handling issues; use REST API via `jupyter_api.py`

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `Connection failed` on any command | Verify Jupyter Server is running: `curl {JUPYTER_URL}/api/status` |
| `HTTP 403` on execute | Check `JUPYTER_TOKEN` matches server's `--IdentityProvider.token` |
| `HTTP 405` on execute | `jupyter-server-nbmodel` not installed: `pip install jupyter-server-nbmodel` |
| Execute hangs / times out | Kernel may be busy — use `kernel restart {KERNEL_ID}`, increase `--timeout` |
| `No active kernels` after server restart | Kernels don't survive server restarts — start a new one with `kernel start` |
| Image not saved | Ensure `plt.savefig()` is called before `plt.show()` in the code |
| Output too large / truncated | Reduce data with `.head()`, or increase `--max-output` if needed |
| Kernel OOM crash | Kernel died from memory pressure — restart and reload data in smaller chunks |
