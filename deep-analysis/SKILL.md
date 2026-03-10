---
name: deep-analysis
description: "Multi-dimensional system analysis — AG discovers problem-specific aspects, dispatches Analyst + Challenger agents, and synthesizes findings into a system_map."
---

# Deep Analysis Skill

> **ROLE**: AG is the **分析引导者**. AG actively thinks about what dimensions matter for this specific problem, proposes aspects for user confirmation, dispatches subagents for deep analysis, and synthesizes findings.

> [!IMPORTANT]
> This skill is about **understanding the problem space**, not designing solutions.
> Output is a `system_map.md` that can feed into `system-design`, `panel-discussion`, or standalone research.

## When to Trigger

- User says "帮我梳理"、"分析一下"、"搞清楚这个系统"、"有什么问题"
- User wants to understand a system before designing or refactoring
- Complex codebase needs multi-perspective examination
- Any task where "figuring out the right questions" is the first step

## 3-Step Workflow

```
Aspect Discovery → [user ✓] → Dual-Agent Analysis → Synthesis → [user ✓]
```

### Step 1: Aspect Discovery（AG 主导思考 + 用户确认）

核心是 **根据具体问题提出分析维度**，而非机械套用固定框架。

**步骤：**

1. **深度理解目标** — 读取用户目标描述 + 现有代码结构（`view_file`、`list_dir`、`grep_search`）
2. **Propose Aspects** — AG 根据对问题的理解，提出 4-8 个 **问题相关** 的分析维度。每个 aspect 需说明：
   - 这个维度为什么对 **这个具体问题** 重要
   - 当前系统在这个维度的现状（一句话）
   - 建议分析的核心子问题
3. **6-Lens 完整性检查** — 用以下 6 个视角作为 checklist 扫一遍（但 **不是** 强制填表）：

   | Lens | 检查问题 |
   |------|----------|
   | 🔄 数据流 | 数据来源、流转、存储是否需要单独分析？ |
   | 🎮 控制流 | 决策链路、编排逻辑是否是核心问题？ |
   | 👤 人机触点 | 用户交互模式是否影响架构选择？ |
   | 💥 故障域 | 错误处理、容错是否是该领域的关键风险？ |
   | 🔗 外部依赖 | 外部系统/API 是否构成重大约束？ |
   | 📐 非功能约束 | 性能/成本/安全是否需要专门分析？ |

   如果某个 Lens 对当前问题不重要，说明理由并跳过。
   问题特有的维度（如 "Agent 反馈闭环"、"技术指标覆盖度验证"）应该被加入。

4. **产出 `aspects.md`** — 最终的 aspect 列表，带优先级标注

**✅ USER CHECKPOINT（必须）**：展示 proposed aspects，等待用户确认/修改/补充

### Step 2: Dual-Agent Analysis（Subagent 执行）

用 Analyst + Challenger 双 agent 对抗模式进行深度分析。

#### 准备 Context Bundle

AG 准备 `context_bundle.md`，包含：

- 分析目标（一段话）
- 代码结构概要（AG 已读过的摘要，**不是让 agent 自己重新读**）
- 关键方法/类的 API 签名和功能说明
- 用户确认的 aspect 列表

> [!CAUTION]
> **context_bundle 必须足够完整**，让 Analyst 无需自行读代码。
> 之前的教训：Agent 启动冗余 Explore subagent 重读 AG 已分析过的代码 = 浪费 36K tokens。

#### 启动 Analyst

```bash
ANALYSIS_ID="{short_desc}"
ANALYSIS_DIR="${HOME}/.deep-analysis/${ANALYSIS_ID}"
mkdir -p "${ANALYSIS_DIR}/analyst" "${ANALYSIS_DIR}/challenger"

# AG 写 context_bundle 和 analyst prompt（使用 write_to_file，不用 send-keys）
# Analyst prompt 必须包含：
#   1. 完整的 context_bundle 内容（或引用路径）
#   2. 用户确认的 aspect 列表
#   3. 明确指令：DO NOT read source files, use ONLY the context provided
#   4. 输出格式要求（per-aspect: Current State, Gap, Direction, Key Decisions）

# 用 task-delegate 发射
bash /home/lgj/agent-skills/task-delegate/scripts/task_launch.sh \
  ${ANALYSIS_ID}_analyst ${PROJECT_DIR} --backend cc \
  --task-dir ${ANALYSIS_DIR}/analyst
```

#### 提取 Analyst 输出

```bash
bash /home/lgj/agent-skills/task-delegate/scripts/task_extract.sh \
  ${ANALYSIS_ID}_analyst \
  --task-dir ${ANALYSIS_DIR}/analyst \
  --output-file ${ANALYSIS_DIR}/analyst/output.md
```

#### 启动 Challenger

Challenger 读取 Analyst 输出后做对抗性审查：

```bash
# Challenger prompt 包含：
#   1. context_bundle（同上）
#   2. Analyst 的完整输出
#   3. 角色：Devil's Advocate — 找盲点、挑战假设、提替代方案

bash /home/lgj/agent-skills/task-delegate/scripts/task_launch.sh \
  ${ANALYSIS_ID}_challenger ${PROJECT_DIR} --backend cc \
  --task-dir ${ANALYSIS_DIR}/challenger

# 提取
bash /home/lgj/agent-skills/task-delegate/scripts/task_extract.sh \
  ${ANALYSIS_ID}_challenger \
  --task-dir ${ANALYSIS_DIR}/challenger \
  --output-file ${ANALYSIS_DIR}/challenger/output.md
```

### Step 3: Synthesis（AG 综合）

AG 读取 Analyst + Challenger 两份输出，综合写 `system_map.md`：

- 每个 aspect 的关键发现（融合 Analyst 分析 + Challenger 质疑）
- 跨 aspect 的关联和冲突
- 设计约束汇总
- 建议的下一步行动（可直接输入 system-design）

**✅ USER CHECKPOINT**：展示 system_map 关键发现

## IPC Protocol

```text
~/.deep-analysis/{analysis_id}/
├── goal.md                     ← 分析目标
├── context_bundle.md           ← AG 准备的系统摘要
├── aspects.md                  ← 用户确认的 aspects
├── analyst/
│   ├── prompt.txt              ← Analyst prompt
│   └── output.md               ← Analyst 分析结果
├── challenger/
│   ├── prompt.txt              ← Challenger prompt（含 Analyst 输出引用）
│   └── output.md               ← Challenger 质疑结果
└── system_map.md               ← AG 综合产出
```

执行记录存储在 `~/.task-delegate/{task_id}/`（遵循 task-delegate 的集中式 IPC 协议）。

## Mandatory Rules

1. **Aspects 必须是问题驱动的** — 6-Lens 仅作为完整性 checklist，不是强制模板
2. **Aspects 必须和用户确认** — 用户可能有 AG 想不到的关注点
3. **Context bundle 必须足够完整** — Agent 不应需要自行读代码
4. **Analyst prompt 必须明确禁止重新读代码** — 防止冗余 Explore subagent
5. **必须用 task_extract.sh 提取输出** — 不要手动解析 live.log JSON
6. **AG 负责综合** — system_map.md 是 AG 写的融合产物，不是 copy-paste

## Anti-Patterns

```
❌ 机械套用 6-Lens 作为 aspects
   → 每个问题有自己独特的关键维度。6-Lens 是 checklist，不是模板

❌ 让 Analyst agent 自己读代码
   → AG 已经分析过代码了，context_bundle 应该包含全部必要信息

❌ 不等用户确认 aspects 就启动 subagent
   → 用户的关注点可能完全不同（如反馈闭环、覆盖度验证）

❌ 跳过 Challenger 直接综合
   → Challenger 的对抗性审查是发现盲点的关键机制

❌ 把 prompt/context 写到 /tmp
   → 用 ~/.deep-analysis/ 目录保存有价值的中间产物
```

## Composability

| 组合方式 | 说明 |
|----------|------|
| deep-analysis → system-design | `system_map.md` 作为 system-design 的输入 |
| deep-analysis → panel-discussion | system_map 的争议点可启动多角色辩论 |
| 独立使用 | 纯分析场景（竞品调研、技术选型、系统评估） |
