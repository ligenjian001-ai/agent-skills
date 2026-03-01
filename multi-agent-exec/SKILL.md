---
name: multi-agent-exec
description: "AG orchestrates CC/Codex/Gemini as implementation executors. Use for any task that benefits from multi-agent decomposition. AG handles planning, context engineering, task decomposition, and verification. Executors handle implementation. Cross-project — no project-specific paths."
---

# Multi-Agent Execution Skill

## Core Principle: Dynamic Role Planning

> [!IMPORTANT]
> Agent roles are **NOT fixed**. AG must think about what roles are needed for each
> specific task, then discuss the proposed team composition with the user before proceeding.

Every task is different. AG decides roles, user approves.

## Available Executors

All executors are dispatched via CLI through `ag-dispatch` wrapper. AG is the orchestrator —
which model AG itself runs on is irrelevant.

| Executor | CLI | Auto-Approve | JSON Output | Budget Control |
|----------|-----|-------------|-------------|----------------|
| CC (Claude) | `claude -p` | `--permission-mode bypassPermissions` | `--output-format json` | `--max-budget-usd N` |
| Gemini | `gemini -p ""` | `--approval-mode yolo` | `--output-format json` | N/A |
| Codex | `codex exec` | sandbox permissions | stdout | N/A |

### Selection Guide

| Scenario | Best Executor | Why |
|----------|--------------|-----|
| Multi-file analysis/audit | CC | Best at reading many files |
| Multi-file code changes | CC | Strong at coordinated edits |
| Focused single-file edit | CC or Gemini | Either works |
| Independent verification | Codex or Gemini | Separation of concerns |
| Simple tasks | AG directly | Zero cost, no dispatch overhead |

## Workflow

### Phase 0: Role Planning (AG thinks → User discusses)

1. Read the task/issue thoroughly
2. Think: what roles? which executors? is dispatch even warranted?
3. Propose team composition to user → wait for approval

### Phase 1: Context Preparation (AG)

```bash
mkdir -p /tmp/ag_ipc/{task_id}/{role}
# Write prompt to /tmp/ag_ipc/{task_id}/{role}/prompt.txt
```

`prompt.txt` must include: role description, task, relevant files, scope constraints,
success criteria, self-test command, and instructions to write result.json.

### Phase 2: Dispatch & Execute

> [!CAUTION]
> **SESSION ISOLATION — NON-NEGOTIABLE**
>
> Executors MUST run in a **dedicated tmux session**, NEVER in AG's main session.
> Executor runs take 2-5 minutes and will completely block the tmux session.

#### Dispatch via `ag-dispatch` wrapper

```bash
# 1. Create dedicated executor session
tmux new-session -d -s {conv_id}-{role} -x 200 -y 50

# 2. Dispatch (one command — handles everything)
SKILL_DIR=$(find .agent/skills/multi-agent-exec -name ag_dispatch.sh -printf '%h' 2>/dev/null)
tmux send-keys -t {conv_id}-{role} \
  "bash ${SKILL_DIR}/ag_dispatch.sh {executor} {role} /tmp/ag_ipc/{task_id}/{role}" Enter
```

`ag-dispatch` automatically:

- Reads `prompt.txt`, invokes correct executor CLI with correct flags
- Captures raw output to `raw_output.json`
- Writes `execution_record.json` (cost, duration, metadata)
- Logs to Langfuse asynchronously (fire-and-forget, never blocks)
- Prints `EXEC_DONE` on completion

**Environment variables** (optional):

- `AG_DISPATCH_BUDGET` — override budget (default: 5.00)
- `AG_PROJECT_DIR` — override project directory (default: git root)

#### AG polls from MAIN session (not blocked)

```bash
# PRIMARY: Read live execution log (real-time, updated as executor runs)
view_file /tmp/ag_ipc/{task_id}/{role}/live.log

# Check for result.json (completion indicator)
ls -la /tmp/ag_ipc/{task_id}/{role}/result.json

# Check if executor modified files (early indicator)
git diff --stat

# Read executor pane for completion marker
tmux capture-pane -t {conv_id}-{role} -p -S -20
# Look for "EXEC_DONE"
```

**Polling cadence**: 60s first check → 30s interval → 5min read errors → 10min timeout

### Phase 2.5: Runtime Monitoring & Intervention (AG — MANDATORY)

> [!IMPORTANT]
> AG MUST actively monitor the executor's progress during execution.
> Passive waiting is NOT acceptable. AG can and should intervene when needed.

**Monitoring — what to check in `live.log`:**

1. **Correct paths** — executor didn't "correct" or change paths from the prompt
2. **Correct tools/commands** — SSH hops, python paths, etc. match the prompt
3. **Progress** — executor making forward progress or stuck/looping?
4. **Error patterns** — permission denied, file not found, connection refused

**Monitoring cadence**: 30s first check → 60s interval → read `live.log` each time

```bash
# Read live output (non-blocking, uses view_file not tmux)
view_file /tmp/ag_ipc/{task_id}/{role}/live.log
```

#### Intervention — AG CAN interrupt executors

AG is not powerless during execution. Executors run in a dedicated tmux session:

```bash
# INTERRUPT: Send Ctrl+C to kill the executor process
tmux send-keys -t {conv_id}-{role} C-c

# VERIFY: Confirm executor stopped
tmux capture-pane -t {conv_id}-{role} -p -S -5
```

#### When to intervene

| Trigger | Action |
| --- | --- |
| **Wrong direction** — live.log shows executor using wrong paths, wrong SSH hop, or completely misunderstanding the task | Ctrl+C → write `feedback.json` → re-dispatch with corrected prompt |
| **Stuck/looping** — no new output in live.log for 5+ minutes | Ctrl+C → diagnose → re-dispatch or notify user |
| **Error cascade** — repeated failures (permission denied, connection refused) with no self-recovery | Ctrl+C → fix the underlying issue first → re-dispatch |
| **Budget concern** — simple task running too long (>$2 for a routine check) | Ctrl+C → simplify prompt or use cheaper executor |

#### When NOT to intervene

- Executor is making progress but slower than expected → let it run
- Executor tries a slightly different approach than prompted but it's working → let it run
- Minor errors that executor self-recovers from → let it run

#### Timeout policy

| Executor | Default timeout | Action on timeout |
| --- | --- | --- |
| CC | 10 min | Ctrl+C → re-dispatch with tighter scope |
| Gemini | 10 min | Ctrl+C → re-dispatch |
| Codex | 5 min | Ctrl+C → re-dispatch |

After intervention, **always** write `{role}/feedback.json` documenting why:

### Phase 3: Result Collection (AG)

**Fallback chain** (check in order):

1. `result.json` — executor wrote structured result (preferred)
2. `raw_output.json` — parse executor's stdout JSON
3. `tmux capture-pane` — last resort

> [!CAUTION]
> **NEVER trust executor self-test alone.** AG MUST independently verify:
>
> - Run the self-test command yourself
> - `git diff` to review actual changes
> - `grep` for dangling references to removed functions

### Phase 4: Verify & Iterate (AG)

If FAIL → write feedback to `{role}/feedback.json` → retry (max 3 attempts)
If PASS → proceed to next role or complete

### Phase 5: Report to User

AG summarizes all role outputs, verification results, costs, and final status.

### Phase 6: Retrospective (AG — triggered on demand)

> [!TIP]
> Can be triggered anytime — after a task, periodically, or when user requests "复盘/reflect".
> Uses Langfuse traces accumulated from past dispatches.

```bash
# Run retrospective (last 7 days, all executors)
python3 /home/lgj/agent-skills/multi-agent-exec/scripts/ag_retro.py

# Filter by executor or time range
python3 /home/lgj/agent-skills/multi-agent-exec/scripts/ag_retro.py --days 3 --executor cc

# JSON output for programmatic analysis
python3 /home/lgj/agent-skills/multi-agent-exec/scripts/ag_retro.py --json
```

**What it analyzes:**

- Failure patterns: recurring errors, wrong paths, prompt problems
- Cost efficiency: avg cost per executor, per role
- Executor selection: is the right executor being used for each role?
- Duration trends: are tasks getting faster or slower?

**Actions based on findings:**

| Finding | Action |
| --- | --- |
| High failure rate for an executor | Review prompt templates, add more constraints |
| Repeated path/env errors | Update relevant skill (e.g. trading-server) |
| Cost spikes | Tighten budget or switch to cheaper executor |
| Same role dispatched repeatedly | Consider automating as Jenkins job |

## Tracing & Recording

Tracing is handled by `ag-dispatch` + `ag_trace.py` — **fully transparent** to both
AG (orchestrator) and executors. No extra context overhead.

### What gets recorded

| Record | Location | Purpose |
|--------|----------|---------|
| `raw_output.json` | IPC dir | Full executor stdout (CC JSON / Gemini JSON / text) |
| `execution_record.json` | IPC dir | Lean metadata: executor, role, duration, cost, tokens |
| Langfuse trace | Langfuse cloud | Structured spans with input/output/metadata per role |

### Langfuse setup

Set env vars (e.g. in `~/.bashrc`):

```bash
export LANGFUSE_PUBLIC_KEY="pk-..."
export LANGFUSE_SECRET_KEY="sk-..."
export LANGFUSE_HOST="https://cloud.langfuse.com"  # or self-hosted
```

If not configured, tracing silently degrades to local `execution_record.json` only.

## tmux Rules

### Session naming: `{conv_id_8chars}-{role}`

Example: `21c0c32c-auditor`, `21c0c32c-fixer`

### Sequencing: ALWAYS `waitForPreviousTools=true`

Never send capture-pane in parallel with send-keys.

### Cascading bg failure recovery

If 3+ consecutive capture-pane go to background:

```bash
tmux kill-session -t {id}; sleep 1; tmux new-session -d -s {id} -x 200 -y 50
```

## IPC Protocol

```text
/tmp/ag_ipc/{task_id}/
├── {role}/
│   ├── prompt.txt           ← AG → Executor (task prompt)
│   ├── live.log             ← Real-time executor output (tee'd by ag-dispatch)
│   ├── result.json          ← Executor → AG (structured result)
│   ├── raw_output.json      ← Executor stdout (captured by ag-dispatch)
│   ├── execution_record.json← ag-dispatch metadata (cost, duration, trace ID)
│   └── feedback.json        ← AG → Executor (retry feedback)
```

## Anti-Patterns

❌ Fixed role templates — every task gets fresh role analysis
❌ Dispatching without user-approved team composition
❌ Skipping AG independent verification after executor "success"
❌ Using `$(cat file.json)` in dispatch — use `ag-dispatch` wrapper
❌ Running executor in AG's main tmux session
❌ Using `--permission-mode plan` — use `bypassPermissions`
❌ Polling too frequently (<30s interval)
