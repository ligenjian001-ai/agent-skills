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

> **核心原则**：AG 担任编排者，一旦涉及实际编码就委派。AG 只写验证代码和编排脚本。

| 任务类型 | Best Backend | Why |
|----------|-------------|-----|
| **编码实现** — 新功能、修复、重构 | CC | 最强编码能力，多文件协调编辑 |
| **推理 & 长链路思考** — 分析、调试、架构决策 | Codex | 强推理能力，适合深度思考 |
| **多模态** — 图片、浏览器、OCR | Gemini | 原生多模态支持 |
| **性价比** — 简单生成、快速分析 | DeepSeek | 低成本、快速 |
| **验证 & 编排** — 检查代码、协调任务 | AG 自身 | 保持上下文，零 dispatch 开销 |
| **多角色辩论** — 方案评估 | Codex / CC 混合 | 通过 panel-discussion 编排 |

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

**Task ID convention**: `YYYYMMDD_HHMM_{short_desc}` e.g. `20260305_0200_auth_refactor` — timestamp first for sortability

### Step 2: Launch

```bash
# Create task directory
TASK_ID="{YYYYMMDD_HHMM}_{short_desc}"
mkdir -p ~/.task-delegate/${TASK_ID}

# Write prompt.txt (use write_to_file tool, NEVER send-keys)

# Launch via skill script
SKILL_DIR=$(dirname $(readlink -f $(find /home/lgj/agent-skills/task-delegate -name task_launch.sh)))
bash "$SKILL_DIR/task_launch.sh" ${TASK_ID} {project_dir} --backend cc

# Resume a prior session (for multi-round workflows like panel discussions)
bash "$SKILL_DIR/task_launch.sh" ${TASK_ID} {project_dir} --backend cc --resume-session {prior_session_id}
```

Supported backends: `cc`, `codex`, `gemini`, `deepseek`

The launcher:

- Creates dedicated tmux session `task-{task_id}`
- Runs the chosen backend headless with appropriate flags
- Streams output to `~/.task-delegate/{task_id}/live.log`
- Writes `execution_record.json` on completion

### Step 3: Active Monitoring Loop (AG — MANDATORY, INLINE)

> [!CAUTION]
> AG MUST actively monitor the backend **immediately after launch** and stay engaged until completion.
> **"Dispatch and forget" is the #1 anti-pattern.** AG's job is NOT done after `task_launch.sh` returns.

**AG的完整职责**：Launch → Monitor → Extract → Verify → Follow-up。缺少任何一步都算失败。

#### 3a. Notify User + Start Monitoring

Launch 后立刻告知用户并开始监控：

```
📋 任务已启动: {task_id}
🔧 后端: {backend}
⏱  预计耗时: {AG's estimate}

我会持续监控执行情况。你也可以：
  tmux attach -t task-{task_id}    ← 实时观看
  Ctrl+B 然后 D                    ← 退出观看（不中断任务）
```

#### 3b. Polling Loop

AG 必须周期性检查 `live.log` 直到任务完成或超时：

```
首次检查: launch 后 30s
后续间隔: 60s
每次检查:
  1. view_file ~/.task-delegate/{task_id}/live.log  (看最后 50 行)
  2. 或 cat ~/.task-delegate/{task_id}/execution_record.json 2>/dev/null
     → 文件存在 = 任务已结束
```

**每次检查时 AG 必须评估：**

| 检查项 | 正常 | 异常 → 行动 |
|--------|------|-------------|
| 方向正确？ | 路径/工具与 prompt 一致 | Ctrl+C → 改 prompt → 重新 launch |
| 在推进？ | 有新输出 | 5 min 无输出 → Ctrl+C → 诊断 |
| 无错误？ | 正常运行 | 重复报错 → Ctrl+C → 修底层问题 |
| 未超时？ | 在预估时间内 | 超时 → Ctrl+C → 缩小范围或换后端 |

#### 3c. Intervention

```bash
# 中断
tmux send-keys -t task-{task_id} C-c
# 确认停止
tmux capture-pane -t task-{task_id} -p -S -5
```

#### Timeout Policy

| Backend | Default timeout | Action on timeout |
| --- | --- | --- |
| CC | 10 min | Ctrl+C → re-launch with tighter scope |
| Gemini | 10 min | Ctrl+C → re-launch |
| Codex | 5 min | Ctrl+C → re-launch |
| DeepSeek | 2 min | Check response, re-try |

### Step 4: Post-Completion (AG — MANDATORY, INLINE)

任务完成后 AG **立即执行**（不等用户指示）：

#### 4a. Extract Output

```bash
bash /home/lgj/agent-skills/task-delegate/scripts/task_extract.sh \
  {task_id} --output-file ~/.task-delegate/{task_id}/output.md
```

#### 4b. Verify

1. **Check completion status**:

   ```bash
   cat ~/.task-delegate/{task_id}/execution_record.json
   ```

2. **Read extracted output** — AG 必须理解 subagent 做了什么

3. **Review changes** (for code tasks):

   ```bash
   cd {project_dir} && git diff --stat
   ```

4. **Run tests** (if applicable):

   ```bash
   # Run the same self-test from prompt.txt
   ```

> [!CAUTION]
> **NEVER trust backend self-test alone.** AG MUST independently verify.
> **NEVER report "task done" without reading the output.** AG must understand what was produced.

#### 4c. Report to User

AG 向用户汇报：

- subagent 做了什么（关键产出摘要）
- 验证结果（通过/部分通过/失败）
- 发现的问题或值得注意的点

### Step 5: Follow-up（AG — MANDATORY）

AG 必须主动识别后续行动：

- **Output 需要进一步处理？** — 如 Analyst 输出需要 Challenger 复审
- **有 TODO 或遗留问题？** — 从 subagent 输出中提取
- **结果需要集成到其他产物？** — 如写入 system_map.md、更新 task.md
- **需要启动下一个任务？** — 如 spike 验证、后续实现

> [!IMPORTANT]
> AG 的工作在 **用户确认后续方向** 后才算完成，不是 subagent 退出就算完成。

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

For multi-agent scenarios (e.g. agent-panel-discussion), use `task_launch.sh` with `--role` and `--session`:

```bash
# Create IPC directory and write prompt
TASK_ID="YYYYMMDD_HHMM_{desc}_{role}"
mkdir -p ~/.task-delegate/${TASK_ID}
write_to_file("~/.task-delegate/${TASK_ID}/prompt.txt", ...)

# Launch in dedicated tmux session with role tracking
bash /home/lgj/agent-skills/task-delegate/scripts/task_launch.sh \
  ${TASK_ID} ${PROJECT_DIR} \
  --backend cc \
  --role {role} \
  --source {conversation_id} \
  --session {custom_session_name}
```

### IPC Protocol

```text
~/.task-delegate/{task_id}/
├── prompt.txt              ← AG → Backend (task prompt)
├── runner.sh               ← Auto-generated runner script
├── live.log                ← Real-time backend output
└── execution_record.json   ← Completion metadata
```

### Extracting Backend Output

Use `task_extract.sh` to get clean text from `live.log` (which is stream-JSON format):

```bash
# Extract all assistant text to stdout
bash /home/lgj/agent-skills/task-delegate/scripts/task_extract.sh {task_id}

# Save to file
bash /home/lgj/agent-skills/task-delegate/scripts/task_extract.sh {task_id} \
  --output-file /path/to/output.md

# Extract only the final result (faster, deduped)
bash /home/lgj/agent-skills/task-delegate/scripts/task_extract.sh {task_id} \
  --result-only
```

> [!NOTE]
> `live.log` contains very long JSON lines (50K+ chars). Do NOT use `bash read` or `jq` line-by-line — they truncate.
> `task_extract.sh` uses Python's `json` module for reliable parsing.

### execution_record.json Schema

```json
{
  "task_id": "20260308_0341_issue49_developer",
  "backend": "cc",
  "role": "developer",
  "source_conversation": "99c5cf61-...",
  "session_id": "3f2194fb-7bfa-46ab-8be7-bb68a3221b24",
  "project": "/home/lgj/hft_build",
  "status": "success",
  "exit_code": 0,
  "duration_seconds": 421,
  "started_at": "2026-03-08T01:58:13+08:00",
  "finished_at": "2026-03-08T02:05:14+08:00",
  "prompt_file": "...",
  "prompt_bytes": 2614,
  "api_billing": false,
  "live_log": "..."
}
```

`role`, `source_conversation`, `session_id`, and `resumed_from` are optional. `session_id` is auto-extracted from CC/Codex output; use it with `--resume-session` for multi-round workflows. `prompt_bytes` records the prompt size for token consumption tracking. Langfuse fields (`langfuse_trace_id`, `cost_usd`) are added by `ag_trace.py` when `--trace` is enabled.

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

❌ Dispatch and forget — launch 后不再跟进
   → AG 必须执行完整的 Launch → Monitor → Extract → Verify → Follow-up 链路

❌ Vague prompt: "fix the bugs"
   → MUST specify which files, what behavior is wrong, expected behavior

❌ Launching backend in AG's own tmux session
   → ALWAYS use dedicated task-{task_id} session

❌ Forgetting to tell user how to monitor
   → Step 3a is MANDATORY, not optional

❌ Not reading backend's output after completion
   → Step 4b requires AG to read and understand the extracted output

❌ Reporting "task done" without verification
   → Step 4b-4c: AG must independently verify before reporting
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

## Integration: panel-discussion

> [!NOTE]
> `agent-panel-discussion/scripts/panel_launch.sh` is a thin wrapper around `task_launch.sh`.
> Panel agent execution records are stored in `~/.task-delegate/` with task_ids like
> `YYYYMMDD_HHMM_panel_rN_agent`. The panel orchestration layer (`~/.panel-discussions/`)
> stores only topic, summaries, reports, and a `manifest.json` linking to task_ids.
