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

> [!IMPORTANT]
> **核心原则：传递 WHAT + WHERE，不传递 HOW。**
> CC/Codex/Gemini 本身有极强的代码理解和方案设计能力。
> AG 的职责是清晰定义**目标**和提供**必要上下文**，而不是替 executor 设计实现方案。
> 过度指定实现细节 = 浪费 AG 上下文 + 限制 executor 发挥 + 增加走偏风险。

**Prompt 模板（轻量级）：**

```markdown
# Task: {one-line description}

## Objective
{用户的原始需求，用 AG 的理解清晰重述。}
{重点说清楚「要达成什么效果」，而不是「怎么实现」。}

## Context
- Project root: {absolute path}
- Key files: {仅列出与任务直接相关的文件，附一句话说明其作用}
- {如有 CLAUDE.md / GEMINI.md，提醒 executor 自行阅读}

## Constraints (仅列出 executor 无法自行推断的约束)
- Do NOT modify: {明确禁止修改的文件/模块}
- {用户明确提出的非功能性要求，如性能、兼容性}

## Self-Test
After completing changes, run:
```

{exact test/build command}

```
Ensure all tests pass before finishing.
```

**什么该写、什么不该写：**

| ✅ AG 应该提供 | ❌ AG 不应该提供 |
|--------------|----------------|
| 用户的原始需求和意图 | 具体的代码修改方案 |
| 项目根目录和关键文件位置 | 详细的函数签名设计 |
| 明确的禁止修改区域 | 文件级别的实现步骤 |
| 验证命令（test/build） | 代码风格的逐条规范（executor 会自己看） |
| executor 无法自行获取的背景知识 | 能从代码中读出来的技术栈信息 |

> [!CAUTION]
> **Prompt 不是设计文档。** Executor 会自己读代码、理解架构、设计方案。
> AG 写得越多，executor 越容易被 AG 的错误假设带偏。
> **信任 executor 的理解力** — 它是 builder，AG 是 orchestrator。

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
> **DO NOT YIELD AFTER LAUNCH.**
> AG 在 launch 后必须**在同一个 turn 内**开始第一次 polling。
> 不可以发完通知就停下来等用户响应。
> "我会持续监控" 不是承诺 — 是 AG 必须**立刻兑现**的行动。

**AG的完整职责**：Launch → Monitor+播报 → Extract → Verify → Follow-up。缺少任何一步都算失败。

**正确的行为模式**：

```
1. task_launch.sh 完成
2. 立刻 view_file live.log（第一次 poll，30s 后）
3. 从 live.log 内容中提取简要进度 → 在对话中直接输出进度摘要
4. 更新 task_boundary（TaskStatus = 进度摘要）
5. 再次 view_file live.log（60-90s 间隔）
6. 重复 3-5 直到 execution_record.json 出现
7. 然后执行 Step 4（Extract + Verify）
8. 最后用 notify_user 向用户汇报最终结果

整个 Monitor 阶段在同一个 turn 内完成，不 yield 控制权。
AG 通过 task_boundary 更新 TaskStatus + 对话中输出文字来播报。
```

#### 3a. Launch Notification（嵌入，不是独立步骤）

向用户发一条简短通知（但**不要停在这里**）：

```
📋 任务已启动: {task_id} 🔧 后端: {backend} ⏱ 预计耗时: {estimate}
实时观看: tmux attach -t task-{task_id} (Ctrl+B D 退出)
我会持续监控执行情况，每轮读取 live.log 并在对话中播报进度。
```

#### 3b. Polling + 播报 Loop

AG 必须周期性检查 `live.log` 并**向用户播报进度**，直到任务完成或超时：

> [!IMPORTANT]
> **监控 = 读文件，不需要终端。** `live.log` 和 `execution_record.json` 是普通文件，
> 用 `view_file` 读取即可。**只有 Ctrl+C 干预才需要终端。**
> 这个区分至关重要 — 当 tmux 出问题时（如 user cancel 后），AG 仍然可以用 `view_file` 正常监控。

> [!CAUTION]
> **播报 ≠ 可选。** 每次 poll 之后 AG 必须在对话中输出进度摘要。
> 用户需要 **看到** AG 在持续跟踪，不是在后台沉默 polling。
> 沉默 = 用户以为 AG 掉线了 = 失败。
> **不要用 `notify_user` 播报中间进度** — 那会 yield 控制权、打断监控循环。
> 用普通对话消息 + `task_boundary` TaskStatus 更新即可。

**每轮 Poll 的具体步骤（在同一 turn 内循环）：**

```
1. view_file("~/.task-delegate/{task_id}/live.log", StartLine=最后100行)
   → 阅读最新输出，理解 subagent 当前在做什么

2. view_file("~/.task-delegate/{task_id}/execution_record.json")
   → 文件存在 = 任务已结束 → 跳到 Step 4
   → 文件不存在 = 任务仍在运行 → 继续

3. 评估健康状态（见下方检查表）

4. 在对话中输出进度摘要（格式见下方模板）
   → 这是普通 assistant 文本，不是 notify_user
   → 用户在对话框里直接看到

5. 更新 task_boundary（TaskStatus = 当前进度关键词）
   → 然后等待间隔后再次 view_file live.log → 重复
```

> [!IMPORTANT]
> **整个 Monitor 阶段不 yield 控制权。** AG 在同一个 turn 内完成所有 poll 轮次。
> `notify_user` 只在最终结果汇报时使用（Step 4c），不用于中间进度。

**播报间隔：**

| 阶段 | 间隔 | 说明 |
|------|------|------|
| 首次检查 | launch 后 30s | 确认 subagent 已启动 |
| 正常运行中 | 60-90s | 每轮读 log + 播报 |
| 检测到异常 | 立刻 | 先播报再干预 |

**播报模板：**

```
🔄 进度播报 [{task_id}] — 第 N 轮

**当前状态**: {running / stalled / error / completing}
**Subagent 正在**: {从 live.log 提取的一句话概括，例如 "正在编辑 src/auth.py 添加 JWT 验证"}
**已运行时间**: {M 分 S 秒}
**健康检查**: ✅ 方向正确 / ⚠️ 有偏离 / ❌ 需要干预

{如果有值得注意的细节，加 1-2 句}
```

> [!TIP]
> 播报要**简洁有信息量**。用户看播报是为了判断是否需要干预。
> 不要复制粘贴 live.log 原文 — 要**摘要和判断**。
> 每轮播报控制在 3-5 行以内。

**每次检查时 AG 必须评估（并在播报中体现）：**

| 检查项 | 正常 | 异常 → 行动 |
|--------|------|-------------|
| 方向正确？ | 路径/工具与 prompt 一致 | 播报 ⚠️ → Ctrl+C → 改 prompt → 重新 launch |
| 在推进？ | 有新输出 | 5 min 无输出 → 播报 ❌ → Ctrl+C → 诊断 |
| 无错误？ | 正常运行 | 重复报错 → 播报 ❌ → Ctrl+C → 修底层问题 |
| 未超时？ | 在预估时间内 | 超时 → 播报 ❌ → Ctrl+C → 缩小范围或换后端 |

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

❌ AG 在 prompt 中写详细实现方案（函数签名、代码结构、修改步骤）
   → Prompt 只传递目标+上下文+约束，executor 自己设计方案
   → AG 是 orchestrator，不是 architect

❌ AG 在 prompt 中重复 executor 能自己读到的信息（tech stack、代码风格）
   → Executor 会自己读代码和 CLAUDE.md/GEMINI.md
   → 只提供 executor 无法自行获取的背景知识

❌ Dispatch and forget — launch 后不再跟进
   → AG 必须执行完整的 Launch → Monitor+播报 → Extract → Verify → Follow-up 链路

❌ 沉默 polling — 只读 live.log 但不在对话中说明
   → 每轮 poll 后必须在对话中输出进度摘要
   → 沉默 = 用户以为 AG 掉线了 = 失败

❌ 用 notify_user 播报中间进度
   → notify_user 会 yield 控制权，打断监控循环
   → 用普通对话消息 + task_boundary 更新即可
   → notify_user 只在最终结果汇报时使用

❌ 用终端（tmux/run_command）读 live.log 或 execution_record.json
   → 这些是文件读取操作，用 view_file。终端只用于 Ctrl+C 干预
   → 特别是 user cancel 后 tmux 可能卡住，但 view_file 不受影响

❌ Vague prompt: "fix the bugs"（模糊到连目标都不清楚）
   → 必须说清楚要达成什么效果，以及相关文件在哪
   → 但不需要指定具体怎么修

❌ Launching backend in AG's own tmux session
   → ALWAYS use dedicated task-{task_id} session

❌ Forgetting to tell user how to monitor
   → Step 3a is MANDATORY, not optional

❌ Not reading backend's output after completion
   → Step 4b requires AG to read and understand the extracted output

❌ Reporting "task done" without verification
   → Step 4b-4c: AG must independently verify before reporting

❌ 播报时复制粘贴 live.log 原文
   → 播报要摘要和判断，不是 raw log dump
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
