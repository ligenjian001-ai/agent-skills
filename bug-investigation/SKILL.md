---
name: bug-investigation
description: "Multi-agent bug investigation — dispatch bug to two independent Codex analysts (code + logic) for root cause analysis, AG synthesizes the verdict."
---

# Bug Investigation Skill

> **ROLE**: AG is the **调查官 (investigator)**. AG does NOT analyze the bug itself — it prepares context, dispatches two Codex analysts independently, collects their reports, and synthesizes the final verdict.

## When to Trigger

- User says "调查 bug"、"分析问题"、"investigation"、"两边看看"
- User reports a bug that's hard to diagnose with a single analysis pass
- User explicitly requests multi-agent bug analysis
- AG judges a bug is complex enough (could have multiple root causes) to benefit from cross-validation

## Analyst Roster

| Analyst | Executor | Focus | Strength |
|---------|----------|-------|----------|
| 🔧 Code Analyst | Codex (OpenAI) | 代码路径追踪、数据流分析 | 深度代码分析、trace 调用链 |
| 🧠 Logic Analyst | Codex (OpenAI) | 逻辑推理、假设推翻、边界条件 | 深度推理、找隐含假设 |

> [!NOTE]
> 两个 Codex agent 独立分析，互不可见。差异化靠 prompt 保障（不同角色模板）。
> 未来可按需加入 Gemini（多模态分析）或 DeepSeek（快速初筛）。

## Workflow

### Phase 1: 场景收集 (AG ↔ User)

从用户获取 bug 的关键信息。如果信息不足，AG 必须追问：

```markdown
📋 收集 Bug 场景信息:

1. **现象描述**: 具体发生了什么？期望行为是什么？
2. **复现步骤**: 如何触发？每次都能触发吗？
3. **相关文件/模块**: 你怀疑哪些文件有关？
4. **已有线索**: 数据、报错信息、日志片段？
5. **项目路径**: 代码在哪个目录？
```

### Phase 2: Context 准备 (AG — CRITICAL)

AG 读取相关代码和日志，组装分析 prompt：

```bash
# 创建调查目录
INV_ID="inv_$(date +%Y%m%d_%H%M)_{short_desc}"
INV_DIR="${HOME}/.bug-investigations/${INV_ID}"
SKILL_DIR="/home/lgj/agent-skills/bug-investigation"

mkdir -p "${INV_DIR}"
# Write bug_context.txt containing: user description, relevant file contents, error logs
write_to_file("${INV_DIR}/bug_context.txt", ...)
```

> [!CAUTION]
> **Context 质量 = 分析质量。** AG 必须把相关文件内容、错误日志、复现步骤都粘贴到 bug_context.txt 里。
> 不要只给文件路径——Codex 没有文件系统访问权，所有代码必须内联到 context 中。

**bug_context.txt 模板：**

```markdown
# Bug 调查

## 现象
{用户描述的 bug 现象}

## 期望行为
{正确行为应该是什么}

## 复现步骤
{如何触发}

## 报错 / 日志
{粘贴错误信息/日志片段}

## 相关代码
### {filename_1}
```{language}
{file contents or relevant snippets}
```

### {filename_2}

...

## 项目结构

{项目目录结构或关键文件列表}

## 已有线索

{用户的猜测、已排除的假设}

```

### Phase 3: 并行分析 (AG dispatches Codex × 2)

```bash
# Step 3a: 生成两份分析 prompt
bash ${SKILL_DIR}/scripts/inv_prepare.sh ${INV_DIR}
# Produces:
#   ${INV_DIR}/code_analyst/prompt.txt
#   ${INV_DIR}/logic_analyst/prompt.txt

# Step 3b: 并行启动两个分析师
bash ${SKILL_DIR}/scripts/inv_launch.sh codex code_analyst  ${INV_DIR}/code_analyst  ${PROJECT_DIR}
bash ${SKILL_DIR}/scripts/inv_launch.sh codex logic_analyst ${INV_DIR}/logic_analyst ${PROJECT_DIR}
```

**监控（与 task-delegate 相同）：**

```bash
# 查看实时进度
tail -f ~/.task-delegate/${TASK_ID}/live.log

# 或 tmux attach
tmux attach -t inv-${INV_ID}-code_analyst
tmux attach -t inv-${INV_ID}-logic_analyst
```

超时策略：

| Analyst | Timeout | Action |
|---------|---------|--------|
| Codex (Code Analyst) | 5 min | Ctrl+C → 部分结果可用 |
| Codex (Logic Analyst) | 5 min | Ctrl+C → 部分结果可用 |

### Phase 4: 综合判定 (AG — MOST VALUABLE STEP)

两个 analyst 都完成后：

```bash
# 收集两份报告
bash ${SKILL_DIR}/scripts/inv_collect.sh ${INV_DIR}
# Produces: ${INV_DIR}/analysis_summary.md

# AG 手动读取 summary
view_file ${INV_DIR}/analysis_summary.md
```

AG 读取两份分析后，写出综合判定（直接写入 `${INV_DIR}/verdict.md`）：

```markdown
# 综合判定

## 一致结论
{两个分析师都指向的根因}

## 分歧点
{两方不同意的地方 — 这里通常隐藏真正的答案}

## AG 判定
**根因**: {AG 综合后的最终判断}
**依据**: {为什么选这个而不是另一个}
**信心**: {高/中/低}

## 建议修复方案
{具体修哪里、改什么}

## （可选）反驳轮
{如果 AG 犹豫不决，可以把代码分析师的分析给逻辑分析师看、逻辑分析师的分析给代码分析师看，让他们交叉挑战}
```

> [!IMPORTANT]
> **判定时 AG 必须关注分歧点。** 两个 agent 意见一致的地方容易处理；
> 意见分歧的地方才是最有价值的——通常某个 agent 看到了另一个遗漏的角度。

#### 可选：反驳轮 (Rebuttal)

AG 在综合判定后**询问用户**是否需要反驳轮：

```markdown
⚔️ 两位分析师有分歧：
- 代码分析师认为: {代码分析师的结论}
- 逻辑分析师认为: {逻辑分析师的结论}

是否要让它们交叉审查？（把代码分析师的分析给逻辑分析师、逻辑分析师的分析给代码分析师，让它们互相挑战）
```

如果用户同意：

```bash
# 准备反驳轮
bash ${SKILL_DIR}/scripts/inv_prepare.sh ${INV_DIR} --rebuttal
# 启动反驳轮（同 Phase 3）
bash ${SKILL_DIR}/scripts/inv_launch.sh codex code_analyst  ${INV_DIR}/rebuttal/code_analyst  ${PROJECT_DIR}
bash ${SKILL_DIR}/scripts/inv_launch.sh codex logic_analyst ${INV_DIR}/rebuttal/logic_analyst ${PROJECT_DIR}
```

### Phase 5: 修复委派 (Optional)

如果根因明确，AG 可直接用 `task-delegate` 委派 Codex 修复：

```bash
# 使用 task-delegate skill 委派修复
# AG 把 verdict.md 的根因和修复方案写入 prompt.txt
```

## IPC Protocol

```text
~/.bug-investigations/{inv_id}/
├── bug_context.txt             ← AG 准备的 bug 上下文
├── code_analyst/
│   └── prompt.txt              ← Code Analyst 的分析提示词
├── logic_analyst/
│   └── prompt.txt              ← Logic Analyst 的分析提示词
├── rebuttal/                   ← 可选反驳轮
│   ├── code_analyst/
│   │   └── prompt.txt
│   └── logic_analyst/
│       └── prompt.txt
├── analysis_summary.md         ← 收集的两份分析报告
└── verdict.md                  ← AG 综合判定
```

执行记录仍存储在 `~/.task-delegate/{task_id}/`（遵循 task-delegate 的集中式 IPC 协议）。

## Mandatory Rules

1. **AG 不做分析** — AG 只负责收集 context、dispatch、综合判定。不要在 dispatch 前就给结论。
2. **Context 必须包含代码内容** — 不能只给文件路径，必须粘贴关键代码到 bug_context.txt。
3. **两路独立** — 两个 Codex agent 看到相同的 bug_context.txt，但看不到对方的分析。
4. **关注分歧** — 综合判定时，分歧点比一致点更有价值。
5. **反驳轮由用户决定** — AG 建议但不自动启动反驳轮。

## Anti-Patterns

```
❌ AG 自己分析 bug 然后只用一个 agent "验证"
   → 两路必须独立分析，AG 只做综合

❌ bug_context.txt 只写 "看一下 xyz.cpp 的问题"
   → 必须包含完整的现象描述、错误日志、相关代码片段

❌ 把一个分析师的结果放进另一个的初始 prompt（破坏独立性）
   → 初始轮必须独立。交叉审查只在反驳轮进行

❌ 忽略两方的分歧直接选一个
   → 分歧点必须明确记录，并给出 AG 选择的理由

❌ 不收集就直接给用户结论
   → 必须先运行 inv_collect.sh，基于完整报告做判定
```

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Codex 超时或 401 | 检查 Codex 登录状态，或改用 Gemini 替代 |
| Codex 分析方向偏离 | bug_context.txt 太模糊 — 补充更多代码和日志 |
| 两方结论完全一致 | 好事！高信心根因。但仍需 AG 验证逻辑链路 |
| 两方结论完全矛盾 | 启动反驳轮让它们交叉挑战，或 AG 做更深入 code review |
| 分析师没有输出 output.md | 检查 live.log，可能需要手动从 raw output 提取 |
| bug_context.txt 太大导致 Codex 截断 | 精简到关键代码片段，去掉不相关的文件 |
