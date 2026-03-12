---
name: task-delegate
description: Delegate tasks to any backend (CC, Codex, Gemini, DeepSeek). AG acts as orchestrator — prepares prompt, launches backend in tmux, monitors, and verifies results.
---

# Task Delegate Skill

> **AG 的默认身份是 orchestrator（编排者），不是 coder。**
> 遇到编码任务，AG 的第一反应是**委派**，不是自己写。

## When to Trigger

**默认行为 = 委派。** 满足任意一条即应委派：

- 任务涉及**编写或修改应用代码**（新功能、bug 修复、重构）
- 任务涉及**多文件协调编辑**
- 任务预计需要 **10 分钟以上**的编码工作
- 用户明确要求委派（"用 CC 写"、"交给 Codex"等）

**例外 — AG 可以自己做的：** 改一行配置、简单重命名/移动文件、写验证脚本、编排脚本、纯文档编辑。

**判断标准**：如果需要理解代码逻辑才能修改 → 委派。

### Backend Selection

| 任务类型 | Backend | Why |
|----------|---------|-----|
| 编码实现（新功能、修复、重构） | CC | 最强编码能力，多文件协调 |
| 推理 & 长链路思考 | Codex | 强推理，深度分析 |
| 多模态（图片、浏览器、OCR） | Gemini | 原生多模态 |
| 性价比（简单生成、快速分析） | DeepSeek | 低成本快速 |
| 验证 & 编排 | AG 自身 | 保持上下文 |
| 多角色辩论 | Codex/CC 混合 | panel-discussion |

### Scout-Before-Execute（侦察-再-执行）

> [!IMPORTANT]
> **把 subagent 当作对代码细节非常了解的技术骨干。** AG 不理解代码，不应该自己 `view_file` 去读代码然后设计方案。需要代码层面的判断时，**直接问 subagent**。

**两种模式：**

| 场景 | 模式 | 说明 |
|------|------|------|
| 需求清晰，路径明确 | **Direct Execute** | 直接写 prompt 委派执行 |
| 需要先理解代码才能做决策 | **Scout → Execute** | 先派侦察任务，再决定怎么做 |

**Scout 任务的 prompt 模板：**

```markdown
# Task: Analyze {scope} for {goal}

## Objective
分析 {project} 中 {scope} 的当前实现，回答以下问题：
1. {specific question about the codebase}
2. {specific question about feasibility}
3. 你认为实现 {goal} 的最佳方案是什么？

## Context
- Project root: {path}
- Focus area: {key files/modules}

## Output
把分析结果写入 {project}/scout_report.md。不要做任何代码修改。
```

**Scout 回来后 AG 做什么：**
1. 读 `scout_report.md`
2. 基于 CC 的分析做编排决策（拆任务？选 backend？需要用户确认？）
3. 写精简的执行 prompt（不重复 CC 已知的细节）

**判断标准：** 如果 AG 写 prompt 时想要 `view_file` 看代码 → 不要看，发 scout 任务让 CC 看。

---

## Step 1: Write Prompt

写 `~/.task-delegate/{task_id}/prompt.txt`。

**核心原则：传递 WHAT + WHERE，不传递 HOW。** Executor 有极强的代码理解和方案设计能力，AG 不要替它设计实现方案。

> [!CAUTION]
> **AG Plan ≠ CC Prompt。** `implementation_plan.md` 是给人审批的设计文档，可以包含技术细节。`prompt.txt` 是给 executor 的任务描述，只传目标和约束。**绝对不能把 plan 直接复制进 prompt。**

```markdown
# Task: {one-line description}

## Objective
{用户的原始需求，用 AG 的理解清晰重述。说清楚「要达成什么效果」。}

## Context
- Project root: {absolute path}
- Key files: {仅列出与任务直接相关的文件，附一句话说明}

## Constraints (仅列出 executor 无法自行推断的约束)
- Do NOT modify: {禁止修改的文件/模块}

## Self-Test
{exact test/build command}
```

**AG 应该提供**：用户需求和意图、项目路径和关键文件、禁止修改区域、验证命令、executor 无法自行获取的背景知识。
**AG 不应该提供**：具体代码修改方案、函数签名设计、实现步骤、代码风格规范（executor 自己看）、能从代码中读出的技术栈信息。

**Prompt 大小基准**：好的 prompt 在 1.5-3KB。超过 4KB 说明可能 over-specified。`task_launch.sh` 会在 >4KB 时警告，>6KB 时红色告警。

### Prompt Anti-Patterns ⛔

```
❌ 在 prompt 中写代码片段或函数体
   → executor 自己设计实现

❌ 在 prompt 中指定函数签名 ("def foo(bar: str) -> bool")
   → executor 读代码后自行决定 API

❌ 在 prompt 中列实现步骤 ("Step 1: modify X, Step 2: add Y")
   → 只给目标，不给路径

❌ 在 prompt 中指定行号 ("修改 line 42")
   → 代码会变，行号会失效

❌ 把 implementation_plan.md 的技术方案塞进 prompt
   → plan 给人看，prompt 给 executor 看

✅ 好的 prompt: "实现 per-stock PnL 细分，关键文件 backtest_report.py"
✅ 好的 prompt: "修复 Issue #55 的 4 个 deliverable（详见 issue body）"
❌ 差的 prompt: "Rewrite cdp_type_text() to use Input.insertText, add cdp_press_key(page, key, code='', delay_ms=20)..."
```

Task ID 格式：`YYYYMMDD_HHMM_{short_desc}`

---

## Step 2: Launch

```bash
TASK_ID="{YYYYMMDD_HHMM}_{short_desc}"
mkdir -p ~/.task-delegate/${TASK_ID}
# Write prompt.txt (use write_to_file tool, NEVER send-keys)

SKILL_DIR=$(dirname $(readlink -f $(find /home/lgj/agent-skills/task-delegate -name task_launch.sh)))
bash "$SKILL_DIR/task_launch.sh" ${TASK_ID} {project_dir} --backend cc

# Resume prior session:
bash "$SKILL_DIR/task_launch.sh" ${TASK_ID} {project_dir} --backend cc --resume-session {prior_session_id}
```

Backends: `cc`, `codex`, `gemini`, `deepseek`

Launcher 会创建 tmux session `task-{task_id}`，输出流到 `live.log`，完成后写 `execution_record.json`。

---

## Step 3: Monitor (MANDATORY — DO NOT YIELD)

Launch 后 AG **在同一个 turn 内**立刻开始 polling，不 yield 控制权。

**Polling Loop（每 60-90s 执行一次，直到完成）：**

```bash
bash /home/lgj/agent-skills/task-delegate/scripts/task_status.sh {task_id}
```

这个脚本会自动：解析 `live.log` 的 stream-JSON → 提取最近的 subagent 动作（文件编辑、命令执行）→ 显示最新 assistant 文本 → 检测错误和卡住 → 检查是否已完成。

AG 拿到输出后：**把进度摘要直接写在对话中** + 更新 `task_boundary` TaskStatus，然后等 60-90s 再查一次。

**输出示例：**

```
⏳ RUNNING | log_lines=639 | last_update=12s ago
🔧 Recent actions (15 total):
   ✏️  edit_file: pipeline.py
   🔧 bash: pytest tests/ -v
   ✏️  edit_file: config.yaml
💬 Latest assistant text:
   Adding input validation to the pipeline processing function...
```

```
✅ COMPLETED | status=success | duration=331s | exit_code=0
```

**异常处理：** 输出含 `⚠️ WARNING`（卡住）或 `❌ ERRORS` → 用 Ctrl+C 干预：

```bash
tmux send-keys -t task-{task_id} C-c
```

---

## Step 4: Verify (MANDATORY)

任务完成后 AG 立即执行：

```bash
# Extract output
bash /home/lgj/agent-skills/task-delegate/scripts/task_extract.sh {task_id} \
  --output-file ~/.task-delegate/{task_id}/output.md

# Check status
cat ~/.task-delegate/{task_id}/execution_record.json

# Review changes
cd {project_dir} && git diff --stat

# Run self-test from prompt.txt
```

AG 必须**读取并理解** executor 产出，独立验证，然后向用户汇报：产出摘要、验证结果、发现的问题。

---

## Step 5: Follow-up

AG 主动识别后续行动：需要进一步处理？有遗留 TODO？需要集成到其他产物？需要启动下一个任务？

AG 的工作在**用户确认后续方向**后才算完成。

---

## Reference

### IPC Protocol

```text
~/.task-delegate/{task_id}/
├── prompt.txt              ← AG → Backend
├── runner.sh               ← Auto-generated
├── live.log                ← Real-time output
└── execution_record.json   ← Completion metadata
```

### Backend CLI

| Backend | CLI | Auto-Approve | JSON Output |
|---------|-----|-------------|-------------|
| CC | `claude -p` | `--permission-mode bypassPermissions` | `--output-format stream-json` |
| Gemini | `gemini -p ""` | `--approval-mode yolo` | `-o text` |
| Codex | `codex exec` | sandbox | stdout |
| DeepSeek | `curl` API | N/A | JSON |

CC Max（月付）用于日常开发；CC API（按量）用于批量任务，需 `--api-billing` + `--max-budget-usd`。

### Extracting Output

```bash
bash /home/lgj/agent-skills/task-delegate/scripts/task_extract.sh {task_id}
bash /home/lgj/agent-skills/task-delegate/scripts/task_extract.sh {task_id} --output-file /path/to/output.md
bash /home/lgj/agent-skills/task-delegate/scripts/task_extract.sh {task_id} --result-only
```

`live.log` 包含超长 JSON 行（50K+ chars），不要用 `jq` 逐行解析，`task_extract.sh` 使用 Python `json` 模块。

### execution_record.json

关键字段：`task_id`, `backend`, `status`, `exit_code`, `duration_seconds`, `started_at`, `finished_at`, `prompt_bytes`。
可选字段：`role`, `source_conversation`, `session_id`（用于 `--resume-session`），`resumed_from`。

### Multi-Role Dispatch

```bash
TASK_ID="YYYYMMDD_HHMM_{desc}_{role}"
mkdir -p ~/.task-delegate/${TASK_ID}
bash /home/lgj/agent-skills/task-delegate/scripts/task_launch.sh \
  ${TASK_ID} ${PROJECT_DIR} --backend cc --role {role} --source {conversation_id} --session {session_name}
```

### Retrospective

```bash
python3 /home/lgj/agent-skills/task-delegate/scripts/ag_retro.py             # last 7 days
python3 /home/lgj/agent-skills/task-delegate/scripts/ag_retro.py --days 3 --executor cc
python3 /home/lgj/agent-skills/task-delegate/scripts/ag_retro.py --json
```

### Integration: panel-discussion

`panel_launch.sh` is a wrapper around `task_launch.sh`. Panel records stored in `~/.task-delegate/` with IDs like `YYYYMMDD_HHMM_panel_rN_agent`.

### Troubleshooting

| Problem | Fix |
|---------|-----|
| Backend hangs at start | Check CLI version |
| Backend exits immediately | Check prompt.txt not empty, check live.log |
| Backend makes wrong changes | Improve prompt, re-run |
| tmux session not found | `tmux ls`, session may have ended |
| Rate limited (CC Max) | Wait for reset or reduce scope |
