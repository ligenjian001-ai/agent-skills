---
name: task-delegate
description: Delegate tasks to any backend (CC, Codex, Gemini, DeepSeek). AG acts as orchestrator — prepares prompt, launches backend in tmux, monitors, and verifies results.
---

# Task Delegate Skill

> **ROLE**: When this skill is triggered, AG becomes the **orchestrator**.
> AG does NOT write application code itself — it prepares and dispatches the task to the chosen backend.

## When to Trigger

- User says "用 CC 写"、"交给 Claude Code"、"这个任务太大了"、"长任务"
- User says "用 Codex"、"用 Gemini"、"用 DeepSeek"
- User explicitly requests delegation to any backend
- AG judges a task is complex enough (multi-file, 30min+) that a backend would do better

### Backend Selection Guide

| Scenario | Best Backend | Why |
|----------|-------------|-----|
| Multi-file code changes | CC | Best at coordinated edits, native subagent |
| Multi-file analysis/audit | CC | Strong at reading many files |
| Focused single-file edit | CC or Gemini | Either works |
| Independent verification | Codex or Gemini | Separation of concerns |
| Simple text analysis | DeepSeek | Low cost, fast |
| Simple tasks | AG directly | Zero cost, no dispatch overhead |

## Workflow

### Step 1: Prompt Engineering (AG — MOST CRITICAL STEP)

Write `~/.task-delegate/{task_id}/prompt.txt` — this is the ENTIRE context the backend will receive.

**A good prompt MUST include:**

```markdown
# Task: {one-line description}

## Context
- Project root: {absolute path}
- Key files: {list relevant files with brief descriptions}
- Tech stack: {languages, frameworks, build tools}

## Requirements
{Detailed task description from user, expanded with AG's understanding}

## Constraints
- Do NOT modify: {files/modules that are off-limits}
- Follow existing code style in {reference file}
- {Any other constraints}

## Success Criteria
- [ ] {Specific, verifiable criterion 1}
- [ ] {Specific, verifiable criterion 2}

## Self-Test
After completing changes, run:
```

{exact test/build command}

```
Ensure all tests pass before finishing.

## Project Knowledge
{Paste content from CLAUDE.md / GEMINI.md if it exists, or key project conventions}
```

> [!CAUTION]
> **Prompt quality = task outcome.** The backend has ZERO prior context about the project.
> A vague prompt like "add authentication" will fail. AG MUST provide the full picture.
> Spend 2-5 minutes on prompt prep — it saves 30min+ of the backend wandering.

**Task ID convention**: `{short_desc}_{YYYYMMDD_HHMM}` e.g. `auth_refactor_20260305_0200`

### Step 2: Launch

```bash
# Create task directory
TASK_ID="{short_desc}_{YYYYMMDD_HHMM}"
mkdir -p ~/.task-delegate/${TASK_ID}

# Write prompt.txt (use write_to_file tool, NEVER send-keys)

# Launch via skill script
SKILL_DIR=$(dirname $(readlink -f $(find /home/lgj/agent-skills/task-delegate -name task_launch.sh)))
bash "$SKILL_DIR/task_launch.sh" ${TASK_ID} {project_dir} --backend cc
```

Supported backends: `cc`, `codex`, `gemini`, `deepseek`

The launcher:

- Creates dedicated tmux session `task-{task_id}`
- Runs the chosen backend headless with appropriate flags
- Streams output to `~/.task-delegate/{task_id}/live.log`
- Writes `execution_record.json` on completion

### Step 3: Tell User How to Monitor

After launching, AG MUST give the user these monitoring commands:

```
📋 任务已启动: {task_id}
🔧 后端: {backend}
⏱  预计耗时: {AG's estimate}

监控方式（选一种）:

1. 实时观看（推荐）:
   tmux attach -t task-{task_id}
   (按 Ctrl+B 然后按 D 退出观看，不会中断任务)

2. 查看实时日志:
   tail -f ~/.task-delegate/{task_id}/live.log

3. 一键查看状态:
   bash /home/lgj/agent-skills/task-delegate/scripts/task_monitor.sh {task_id}

4. 中断任务（如果需要）:
   tmux send-keys -t task-{task_id} C-c

⚠️  完成后会显示 TASK_DONE / TASK_FAIL 标记。
    完成后回来找我，我会 review diff 并验证结果。
```

### Step 3.5: Runtime Monitoring (AG — MANDATORY)

> [!IMPORTANT]
> AG MUST actively monitor the backend's progress during execution.
> Passive waiting is NOT acceptable.

**What to check in `live.log`:**

1. **Correct paths** — backend didn't "correct" or change paths from the prompt
2. **Correct tools/commands** — SSH hops, python paths, etc. match the prompt
3. **Progress** — backend making forward progress or stuck/looping?
4. **Error patterns** — permission denied, file not found, connection refused

**Monitoring cadence**: 30s first check → 60s interval → read `live.log` each time

```bash
# Read live output (non-blocking)
view_file ~/.task-delegate/{task_id}/live.log
```

#### Intervention — AG CAN interrupt backends

```bash
# INTERRUPT: Send Ctrl+C to kill the backend process
tmux send-keys -t task-{task_id} C-c

# VERIFY: Confirm backend stopped
tmux capture-pane -t task-{task_id} -p -S -5
```

| Trigger | Action |
| --- | --- |
| **Wrong direction** — wrong paths, misunderstanding | Ctrl+C → improve prompt → re-launch |
| **Stuck/looping** — no output for 5+ min | Ctrl+C → diagnose → re-launch or notify user |
| **Error cascade** — repeated failures | Ctrl+C → fix underlying issue → re-launch |
| **Budget concern** — simple task running too long | Ctrl+C → simplify prompt or use cheaper backend |

#### Timeout policy

| Backend | Default timeout | Action on timeout |
| --- | --- | --- |
| CC | 10 min | Ctrl+C → re-launch with tighter scope |
| Gemini | 10 min | Ctrl+C → re-launch |
| Codex | 5 min | Ctrl+C → re-launch |
| DeepSeek | 2 min | Check response, re-try |

### Step 4: Post-Completion Verification (when user returns)

When the user says the backend is done, or AG detects completion:

1. **Check completion status**:

   ```bash
   cat ~/.task-delegate/{task_id}/execution_record.json
   ```

2. **Review changes** (for code tasks):

   ```bash
   cd {project_dir} && git diff --stat
   cd {project_dir} && git diff
   ```

3. **Run tests**:

   ```bash
   # Run the same self-test from prompt.txt
   ```

4. **Report to user**: summarize what the backend did, what passed, what needs attention.

> [!CAUTION]
> **NEVER trust backend self-test alone.** AG MUST independently verify.

## Backend CLI Reference

| Backend | CLI | Auto-Approve | JSON Output | Budget Control |
|---------|-----|-------------|-------------|----------------|
| CC (Claude) | `claude -p` | `--permission-mode bypassPermissions` | `--output-format stream-json` | `--max-budget-usd N` (API only) |
| Gemini | `gemini -p ""` | `--approval-mode yolo` | `-o text` | N/A |
| Codex | `codex exec` | sandbox permissions | stdout | N/A |
| DeepSeek | HTTP API via `curl` | N/A | JSON response | N/A |

### CC Max vs API Billing

| Mode | Cost | Limit | Usage |
|------|------|-------|-------|
| Max (subscription) | Fixed monthly | Rate limited | Daily dev tasks — no `--max-budget-usd` |
| API (pay-per-use) | $0.003-0.015/1K tokens | Needs budget cap | Batch tasks — use `--api-billing` flag |

## Multi-Role Dispatch (Advanced)

For multi-agent scenarios (e.g. agent-panel-discussion), use `ag_dispatch.sh`:

```bash
SKILL_DIR=/home/lgj/agent-skills/task-delegate/scripts

# Create IPC directory
mkdir -p ~/.task-delegate/{task_id}/{role}
# Write prompt
write_to_file("~/.task-delegate/{task_id}/{role}/prompt.txt", ...)

# Dispatch in dedicated tmux session
tmux new-session -d -s {conv_id}-{role} -x 200 -y 50
tmux send-keys -t {conv_id}-{role} \
  "bash ${SKILL_DIR}/ag_dispatch.sh {executor} {role} ~/.task-delegate/{task_id}/{role}" Enter
```

### IPC Protocol

```text
~/.task-delegate/{task_id}/
├── prompt.txt              ← AG → Backend (task prompt)
├── live.log                ← Real-time backend output
├── runner.sh               ← Generated runner script
├── execution_record.json   ← Completion metadata
├── {role}/                 ← Multi-role subdirectories
│   ├── prompt.txt
│   ├── live.log
│   ├── raw_output.json
│   ├── result.json
│   ├── execution_record.json
│   └── feedback.json
```

## Retrospective (on demand)

```bash
# Run retrospective (last 7 days, all backends)
python3 /home/lgj/agent-skills/task-delegate/scripts/ag_retro.py

# Filter by executor or time range
python3 /home/lgj/agent-skills/task-delegate/scripts/ag_retro.py --days 3 --executor cc

# JSON output for programmatic analysis
python3 /home/lgj/agent-skills/task-delegate/scripts/ag_retro.py --json
```

## CLAUDE.md / GEMINI.md Integration

If the target project has a `CLAUDE.md` or `GEMINI.md` file, the backend CLI reads it automatically.
AG should still include critical context in `prompt.txt` because:

- Project knowledge files may be outdated
- The prompt needs task-specific focus
- AG may need to override or supplement instructions

## Anti-Patterns

```
❌ AG writes the code itself instead of delegating
   → If user asked for delegation, use a backend

❌ Vague prompt: "fix the bugs"
   → MUST specify which files, what behavior is wrong, expected behavior

❌ Launching backend in AG's own tmux session
   → ALWAYS use dedicated task-{task_id} session

❌ Forgetting to tell user how to monitor
   → Step 3 is MANDATORY, not optional

❌ Not reviewing backend's output after completion
   → Step 4 is MANDATORY — backends make mistakes, AG must verify

❌ Using --max-budget-usd on CC Max subscription
   → Unnecessary, may prematurely terminate the task
```

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Backend hangs at start | Check CLI version, ensure backend is installed |
| Backend exits immediately | Check prompt.txt is not empty, check live.log for errors |
| Backend makes wrong changes | Prompt was too vague — improve prompt, re-run |
| tmux session not found | Check `tmux ls`, session may have ended |
| Rate limited (CC Max) | Wait for rate limit reset, or reduce task scope |
| DeepSeek API error | Check `DEEPSEEK_API_KEY`, check API URL |
| Codex 401 Unauthorized | Run `codex login` to re-authenticate |

## Future: agent-panel-discussion Integration

> [!NOTE]
> `agent-panel-discussion/scripts/panel_launch.sh` currently duplicates ~80% of `task_launch.sh`'s logic.
> v2.0 will refactor `panel_launch.sh` to call `task_launch.sh` internally, adding `--session-name` and
> `--post-hook` extension points for panel-specific output extraction and session naming.
