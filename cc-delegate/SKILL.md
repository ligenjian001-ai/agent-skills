---
name: cc-delegate
description: Delegate long-running programming tasks to Claude Code CLI. AG acts as orchestrator — prepares prompt, launches CC in tmux, and tells user how to monitor.
---

# Claude Code Delegation Skill

> **ROLE**: When this skill is triggered, AG becomes the **orchestrator**.
> AG does NOT write application code itself — it prepares and dispatches the task to Claude Code.

## When to Trigger

- User says "用 CC 写"、"交给 Claude Code"、"这个任务太大了"、"长任务"
- User explicitly requests delegation to Claude Code
- AG judges a task is complex enough (multi-file, 30min+) that CC would do better

## Workflow

### Step 1: Prompt Engineering (AG — MOST CRITICAL STEP)

Write `/tmp/cc_tasks/{task_id}/prompt.txt` — this is the ENTIRE context CC will receive.

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
{Paste content from CLAUDE.md if it exists, or key project conventions}
```

> [!CAUTION]
> **Prompt quality = task outcome.** CC has ZERO prior context about the project.
> A vague prompt like "add authentication" will fail. AG MUST provide the full picture.
> Spend 2-5 minutes on prompt prep — it saves 30min+ of CC wandering.

**Task ID convention**: `{short_desc}_{YYYYMMDD_HHMM}` e.g. `auth_refactor_20260305_0200`

### Step 2: Launch CC

```bash
# Create task directory
mkdir -p /tmp/cc_tasks/{task_id}

# Write prompt.txt (use write_to_file tool, NEVER send-keys)

# Launch via skill script
SKILL_DIR=$(dirname $(readlink -f $(find /home/lgj/agent-skills/cc-delegate -name cc_launch.sh)))
bash "$SKILL_DIR/cc_launch.sh" {task_id} {project_dir}
```

The launcher script:

- Creates dedicated tmux session `cc-{task_id}`
- Runs CC with `--permission-mode bypassPermissions` (auto-approve all file edits)
- Streams output to `/tmp/cc_tasks/{task_id}/live.log`
- Writes `execution_record.json` on completion

### Step 3: Tell User How to Monitor

After launching, AG MUST give the user these monitoring commands:

```
📋 CC 任务已启动: {task_id}
⏱  预计耗时: {AG's estimate}

监控方式（选一种）:

1. 实时观看 CC 工作（推荐）:
   tmux attach -t cc-{task_id}
   (按 Ctrl+B 然后按 D 退出观看，不会中断 CC)

2. 查看实时日志:
   tail -f /tmp/cc_tasks/{task_id}/live.log

3. 一键查看状态:
   bash /home/lgj/agent-skills/cc-delegate/scripts/cc_monitor.sh {task_id}

4. 中断任务（如果需要）:
   tmux send-keys -t cc-{task_id} C-c

⚠️  CC 完成后会显示 CC_DONE / CC_FAIL 标记。
    完成后回来找我，我会 review diff 并验证结果。
```

### Step 4: Post-Completion Verification (when user returns)

When the user says CC is done, or AG detects completion:

1. **Check completion status**:

   ```bash
   cat /tmp/cc_tasks/{task_id}/execution_record.json
   ```

2. **Review changes**:

   ```bash
   cd {project_dir} && git diff --stat
   cd {project_dir} && git diff
   ```

3. **Run tests**:

   ```bash
   # Run the same self-test from prompt.txt
   ```

4. **Report to user**: summarize what CC did, what passed, what needs attention.

## CC CLI Reference

### Claude Code Max (Subscription)

For Max subscribers, CC usage is included in the subscription. No `--max-budget-usd` needed.

```bash
# Standard launch (Max subscriber — no budget flag)
claude -p \
  --permission-mode bypassPermissions \
  --output-format stream-json \
  < prompt.txt
```

### API Billing

If the user is on API billing (not Max), add budget control:

```bash
claude -p \
  --permission-mode bypassPermissions \
  --output-format stream-json \
  --max-budget-usd 10.00 \
  < prompt.txt
```

### Key Flags

| Flag | Purpose |
|------|---------|
| `-p` | Print mode (non-interactive, headless) |
| `--permission-mode bypassPermissions` | Auto-approve all file edits/commands |
| `--output-format stream-json` | Streaming JSON output (parseable progress) |
| `--output-format json` | Final JSON only (less visibility during run) |
| `--max-budget-usd N` | Budget cap (API billing only, not needed for Max) |
| `--model` | Override model (default: best available) |

## CLAUDE.md Integration

If the target project has a `CLAUDE.md` file, CC will read it automatically.
AG should still include critical context in `prompt.txt` because:

- `CLAUDE.md` may be outdated
- The prompt needs task-specific focus
- AG may need to override or supplement CLAUDE.md instructions

## Anti-Patterns

```
❌ AG writes the code itself instead of delegating
   → If user asked for CC, use CC

❌ Vague prompt: "fix the bugs"
   → MUST specify which files, what behavior is wrong, expected behavior

❌ Launching CC in AG's own tmux session
   → ALWAYS use dedicated cc-{task_id} session

❌ Forgetting to tell user how to monitor
   → Step 3 is MANDATORY, not optional

❌ Not reviewing CC's output after completion
   → Step 4 is MANDATORY — CC makes mistakes, AG must verify

❌ Using --max-budget-usd on Max subscription
   → Unnecessary, may prematurely terminate the task
```

## Troubleshooting

| Problem | Fix |
|---------|-----|
| CC hangs at start | Check `claude --version`, ensure CC is installed |
| CC exits immediately | Check prompt.txt is not empty, check live.log for errors |
| CC makes wrong changes | Prompt was too vague — improve prompt, re-run |
| tmux session not found | Check `tmux ls`, session may have ended |
| Rate limited (Max plan) | Wait for rate limit reset, or reduce task scope |
