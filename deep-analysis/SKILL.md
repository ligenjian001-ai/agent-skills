---
name: deep-analysis
description: "Multi-dimensional system analysis — AG elicits user intent through dialogue, dispatches focused investigators, and surfaces decision points with tradeoffs for user judgment."
---

# Deep Analysis Skill

> **ROLE**: AG is the **分析引导者**. AG 通过对话理解用户意图，委派调查员做深入调查，综合产出带决策点和 tradeoff 的 system_map 让用户判断。AG **不替用户做决策**，**不丢弃有风险的选项**。
>
> 设计哲学和历史教训详见 [README.md](file:///home/lgj/agent-skills/deep-analysis/README.md)。

> [!IMPORTANT]
> This skill is about **understanding the problem space**, not designing solutions.
> Output is a `system_map.md` with decision points that can feed into `system-design`, `panel-discussion`, or standalone research.

## When to Trigger

- 用户说"帮我梳理"、"分析一下"、"搞清楚这个系统"、"有什么问题"
- 用户想在设计或重构之前理解系统现状
- 复杂系统需要深入调查
- "先搞清楚该问什么问题"的场景

## 3-Step Workflow

```
Intent Elicitation → Focused Investigation → Decision Surface → [user 逐点决策]
```

### Step 1: Intent Elicitation（对话式意图发现）

> [!CAUTION]
> **禁止跳过这一步。** AG 不得在未和用户充分对话的情况下直接启动分析。
> 之前的教训：AG 直接套框架生成 aspects，用户不满意因为根本没理解真实需求。

AG 通过多轮对话搞清楚用户的真实意图。**不套任何框架**。

**AG 必须搞清楚的问题（不是 checklist，是对话目标）：**

- 你想解决什么 **具体问题**？（不是"帮我看看"，而是具体的痛点）
- 你对当前状态 **最不满意** 的是什么？
- 分析完之后你想 **做什么**？（改造？决策？研究？评估？）
- 有哪些 **约束** 是我必须知道的？（时间、兼容性、团队能力等）
- 你之前尝试过什么？哪些 **没有奏效**？

**对话方式：**

- AG 就用户的回答继续追问，不要一次问完所有问题
- 每轮对话记录到 `conversation_journal.md`
- 如果用户意图模糊，AG 帮助 **澄清而非假设**：提出 2-3 种可能的解读让用户选
- 当 AG 和用户都清楚"分析要回答什么问题"时，这一步结束

**产出：**

用户确认的 **问题陈述 + 分析目标**。格式：

```markdown
## 分析目标

[一段话，用户确认过的]

## 核心问题

1. [用户最关心的具体问题]
2. [第二个问题]
3. ...

## 约束

- [用户提到的约束]

## 分析完成后的下一步

[改造/设计/决策/...]
```

### Step 2: Focused Investigation（聚焦调查）

> [!CAUTION]
> **HARD GATE — NON-NEGOTIABLE**
> 调查必须通过 `task-delegate` (CC subagent) 执行。AG 不得自己做调查。
> AG 的角色是准备 context、明确调查任务、提取结果。
> 如果 `task-delegate` 不可用或失败，STOP 并通知用户。

委派 **调查员**（不是辩论家）做深入调查。

#### 调查员与旧版 Analyst 的本质区别

| | 旧版 Analyst | 新版 Investigator |
|--|-------------|-------------------|
| 目标 | 产出"分析报告" | 回答用户的具体问题 |
| 产出格式 | 按 aspect 逐条分析 | 按用户问题逐条回答，每个回答带选项和 tradeoff |
| 对风险的态度 | 列出风险（等 Challenger 挑战） | 风险 = 需要用户决策的选项，给出缓解方案 |
| 责任感 | "我分析完了，后面不是我的事" | 每个建议必须说明"如果执行，代价是什么" |

#### 准备 Context Bundle

AG 准备 `context_bundle.md`，包含：

- 用户确认的分析目标（Step 1 产出，原文引用）
- 代码结构概要（AG 已读过的摘要）
- 关键方法/类的 API 签名和功能说明
- **明确的调查任务**：调查员需要回答哪些具体问题

#### 启动 Investigator

```bash
ANALYSIS_ID="{short_desc}"
ANALYSIS_DIR="${HOME}/.deep-analysis/${ANALYSIS_ID}"
mkdir -p "${ANALYSIS_DIR}/investigator"

# AG 写 context_bundle 和 investigator prompt（使用 write_to_file）
# Investigator prompt 必须包含：
#   1. 完整的 context_bundle 内容
#   2. 用户确认的具体问题列表
#   3. 产出要求：每个问题的回答必须包含
#      - 当前状态（事实）
#      - 2-3 个可选方案（包括大胆的）
#      - 每个方案的 tradeoff（收益 vs 代价 vs 风险）
#      - 风险的缓解策略
#   4. 明确指令：DO NOT drop bold options because they're risky.
#      Risk is information, not a reason to exclude.

bash /home/lgj/agent-skills/task-delegate/scripts/task_launch.sh \
  ${ANALYSIS_ID}_investigator ${PROJECT_DIR} --backend cc \
  --task-dir ${ANALYSIS_DIR}/investigator

# 提取
bash /home/lgj/agent-skills/task-delegate/scripts/task_extract.sh \
  ${ANALYSIS_ID}_investigator \
  --task-dir ${ANALYSIS_DIR}/investigator \
  --output-file ${ANALYSIS_DIR}/investigator/output.md
```

#### 可选：多调查员分域

如果问题域很大，可以分派 2 个调查员分别负责不同子域（例如一个调查代码架构，一个调查数据流）。但它们是 **协作关系，不是对抗关系**——各自负责各自的领域。

### Step 3: Decision Surface（决策面呈现）

> [!CAUTION]
> **PRE-FLIGHT GATE**: Before starting synthesis, AG MUST verify:
> ```bash
> ls -l ${ANALYSIS_DIR}/investigator/output.md
> ```
> File MUST exist and be non-empty. AG writing system_map without investigator output is a **protocol violation**.

AG 读取调查报告后综合写 `system_map.md`，但核心不是产出"共识文档"。

**system_map.md 结构：**

```markdown
# System Map: [主题]

## 关键发现

[每个发现用 1-2 句话概括事实]

## 决策点

### 决策 1: [需要用户判断的选择]

**背景**: [为什么这是一个需要决策的点]

| 选项 | 收益 | 代价 | 风险 | 缓解方案 |
|------|------|------|------|---------|
| A: [大胆选项] | ... | ... | ... | ... |
| B: [稳妥选项] | ... | ... | ... | ... |
| C: [折中选项] | ... | ... | ... | ... |

**调查员推荐**: [如果调查员有明确偏好]

**用户决定**: [留空，等用户填]

### 决策 2: ...

## 风险清单

| 风险 | 影响范围 | 概率 | 缓解方案 | 是否可接受？ |
|------|---------|------|---------|------------|
| ... | ... | ... | ... | [留空，等用户判断] |

## 下一步行动（基于用户决策后填写）

[用户在决策点做完选择后，AG 填写]
```

**AG 和用户逐一过决策点**：

1. AG 展示第一个决策点的选项和 tradeoff
2. 用户选择或提出新思路
3. 记录决策，继续下一个
4. 所有决策点过完后，AG 更新 system_map 的"下一步行动"部分

## IPC Protocol

```text
~/.deep-analysis/{analysis_id}/
├── goal.md                     ← 用户确认的分析目标（Step 1 产出）
├── context_bundle.md           ← AG 准备的系统摘要
├── investigator/
│   ├── prompt.txt              ← Investigator prompt
│   └── output.md               ← 调查结果
├── investigator_2/             ← 可选，第二个调查员
│   ├── prompt.txt
│   └── output.md
└── system_map.md               ← AG 综合产出（含决策点）
```

执行记录存储在 `~/.task-delegate/{task_id}/`（遵循 task-delegate 的集中式 IPC 协议）。

## Mandatory Rules

1. **先和用户对话搞清意图，再启动分析** — 不允许跳过 Step 1
2. **不套框架** — 分析维度来自用户意图，不来自 6-Lens 或任何预设模板
3. **每个发现必须带选项和 tradeoff** — 不允许只给结论不给选项
4. **风险必须呈现给用户** — 不允许 AG 自行决定"这个太危险就不做"
5. **AG 负责综合但不负责决策** — system_map 的决策点由用户填写
6. **context_bundle 必须足够完整** — 调查员无需自行读代码

## Anti-Patterns

```
❌ 跳过意图对话，直接套框架生成分析维度
   → 之前的教训：AG 用 6-Lens 生成 aspects，本质是 rewrite 用户需求

❌ 调查员产出只有结论没有选项
   → 每个发现必须给 2-3 个方案 + tradeoff，否则下游无法使用

❌ AG 综合时丢弃有风险的选项
   → 风险是用户需要知道的信息，不是 AG 帮用户回避的东西
   → 检测信号：system_map 里所有建议都是"安全"的 → 一定有问题

❌ 把 prompt/context 写到 /tmp
   → 用 ~/.deep-analysis/ 目录保存有价值的中间产物

❌ AG 自己做调查员的工作
   → 检测信号：~/.task-delegate/ 无记录、investigator 目录为空
   → 即使 AG 能产出质量不错的报告，也必须走 subagent 流程
```

## Composability

| 组合方式 | 说明 |
|----------|------|
| deep-analysis → system-design | `system_map.md`（含用户已做的决策）作为 system-design 的输入 |
| deep-analysis → 直接执行 | 如果分析结论足够明确，可以跳过 system-design 直接执行 |
| deep-analysis → panel-discussion | system_map 的争议点可启动多角色辩论 |
| 独立使用 | 纯分析场景（竞品调研、技术选型、系统评估） |

## Troubleshooting

| Problem | Fix |
|---------|-----|
| 调查员产出只有结论没有选项 | 检查 prompt 是否包含"每个发现必须带 2-3 个方案 + tradeoff"指令 |
| system_map 里的建议全是"安全"的 | AG 综合时丢弃了大胆选项 → 回看 investigator output，补回被移除的方案 |
| 用户对 aspects 不满意 | Step 1 对话不够深入 → 追问用户的具体痛点和期望产出 |
| 调查员重新读了代码（浪费 tokens） | context_bundle 不够完整 → 补充代码摘要和 API 签名 |
| task-delegate 启动失败 | 检查 tmux session、CC 安装状态、task-dir 权限 |

