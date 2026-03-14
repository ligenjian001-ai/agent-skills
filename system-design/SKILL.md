---
name: system-design
description: "Detailed system design — multi-perspective sketch, user-driven convergence at each decision point, real-world validation, and implementation blueprint with direct execution path."
---

# System Design Skill

> **ROLE**: AG is the **设计引导者**. AG 生成多视角方案、在每个关键分歧点呈现选项让用户决策、用真实场景验证设计、产出可直接执行的蓝图。AG **不做保守合并**，**不丢弃有风险的方案**。
>
> 设计哲学和历史教训详见 [README.md](file:///home/lgj/agent-skills/system-design/README.md)。

> [!IMPORTANT]
> This skill is about **designing the solution**, not analyzing the problem.
> If the problem space isn't clear yet, use `deep-analysis` first.

## When to Trigger

- 用户说"设计一下"、"怎么做这个系统"、"帮我出方案"
- `deep-analysis` 的 `system_map.md` 就绪，用户想进入设计
- 用户有明确的问题陈述，需要多视角探索 HOW
- 需求理解清楚但实现路径需要设计

## 4-Phase Workflow

```
SKETCH → [user 选方向] → DECIDE → [user 逐点决策] → SPIKE → [真实验证] → BLUEPRINT
```

### Phase 1: SKETCH（多视角方案探索）

保留 3 agent 独立设计——多视角可以避免锚定效应。但产出目标不同。

| Agent | 后端 | 视角 | 产出重点 |
|-------|------|------|---------|
| 🏛 Architect | CC | 纯架构设计：组件、接口、交互模式 | **关键设计选择及推荐理由** |
| 🔧 Realist | CC | 基于现有代码的改造路径 | **哪些能复用、哪些必须重写、风险在哪里** |
| 🔭 Explorer | Codex | 技术选型 + 外部方案研究 | **业界方案、可用工具、被忽略的可能性** |

> [!IMPORTANT]
> 每个 agent 的 prompt 必须包含：
> - "对于每个关键设计选择，解释你推荐这个方案的理由，以及不选其他方案要付出什么代价"
> - "不要因为某个方案有风险就不推荐。明确说明风险和缓解策略"

```bash
DESIGN_ID="{short_desc}"
DESIGN_DIR="${HOME}/.system-design/${DESIGN_ID}"
mkdir -p "${DESIGN_DIR}/sketch/"{architect,realist,explorer}

# AG 准备 input.md（来自 deep-analysis 的 system_map.md 或用户自写文档）
# AG 为每个 agent 写 prompt.txt，注入 input.md 内容

# 通过 task-delegate 并行启动
bash ~/agent-skills/task-delegate/scripts/task_launch.sh \
  ${DESIGN_ID}_architect ${PROJECT_DIR} --backend cc \
  --task-dir ${DESIGN_DIR}/sketch/architect

bash ~/agent-skills/task-delegate/scripts/task_launch.sh \
  ${DESIGN_ID}_realist ${PROJECT_DIR} --backend cc \
  --task-dir ${DESIGN_DIR}/sketch/realist

bash ~/agent-skills/task-delegate/scripts/task_launch.sh \
  ${DESIGN_ID}_explorer ${PROJECT_DIR} --backend codex \
  --task-dir ${DESIGN_DIR}/sketch/explorer

# 提取输出
for role in architect realist explorer; do
  bash ~/agent-skills/task-delegate/scripts/task_extract.sh \
    ${DESIGN_ID}_${role} \
    --task-dir ${DESIGN_DIR}/sketch/${role} \
    --output-file ${DESIGN_DIR}/sketch/${role}/output.md
done
```

AG 读取三份方案后写 `proposals_summary.md`：

**不做保守合并**。而是提取所有方案中的 **关键差异点**，以决策点形式呈现：

```markdown
## 关键设计分歧

### 分歧 1: [具体的设计选择]

| | Architect | Realist | Explorer |
|--|-----------|---------|----------|
| 方案 | ... | ... | ... |
| 推荐理由 | ... | ... | ... |
| 代价 | ... | ... | ... |
| 风险 | ... | ... | ... |

### 分歧 2: ...
```

**✅ USER CHECKPOINT**：展示分歧对比，让用户初步选方向（不需要精确到每个细节）

### Phase 2: DECIDE（用户逐点决策 → 融合设计）

AG 列出 SKETCH 中的 **所有关键设计分歧**（通常 3-7 个），逐一和用户讨论：

1. AG 展示一个分歧点的选项 + tradeoff
2. 用户选择，或提出新思路
3. 记录决策和理由
4. 继续下一个分歧点

> [!CAUTION]
> **AG 不代替用户选择。** 即使 AG 有明确偏好（如 Realist 方案风险更低），也必须呈现所有选项让用户决定。
> AG 可以提出推荐意见，但必须标注"AG 推荐"而非直接采用。

**所有分歧点过完后**，AG 基于用户决策写 `unified_design.md`。

同时识别 **spike 需求** — 哪些关键假设需要 PoC 验证？写入 `spike_list.md`。

**✅ USER CHECKPOINT**：展示融合设计 + spike 清单

### Phase 3: SPIKE（真实验证）

> [!CAUTION]
> **禁止自验模式。** "AG 设计实验 → CC 执行 → AG 审查"是无效验证。
> 之前教训：agent-native-product SPIKE 通过但 skill 实际完全不可用。

每个 spike = 在真实场景中验证一个关键假设。

**有效验证方法（按优先级）：**

1. **真实使用验证** — 选一个最小切片直接实现 + 用真实数据/场景测试
2. **独立 agent 验证** — 让一个 **不了解设计上下文的 agent** 使用产出物，看是否能达到预期效果
3. **用户场景 walkthrough** — 用户拿着设计走一遍自己的典型场景，看是否覆盖

```bash
# AG 为每个 spike 写 spec
write_to_file("${DESIGN_DIR}/spike/spike_001/spec.md", ...)

# 用 task-delegate 委派实现
bash ~/agent-skills/task-delegate/scripts/task_launch.sh \
  ${DESIGN_ID}_spike001 ${PROJECT_DIR} --backend cc \
  --task-dir ${DESIGN_DIR}/spike/spike_001
```

- Spike 成功 → 写入 `result.md` + 更新 `unified_design.md`
- Spike 失败 → **根据影响范围决定回退**：
  - 局部失败 → 修改设计中该组件，留在 Phase 3
  - 核心假设失败 → **回退到 Phase 1 重新 SKETCH**

**✅ USER CHECKPOINT**：展示 spike 结果 + 设计修正

### Phase 4: BLUEPRINT（落地蓝图 + 执行路径）

AG 将验证过的设计转化为可执行的实施计划：

1. **分阶段路线图** — `roadmap.md`（Phase A/B/C + 预估时间 + 关键产出）
2. **每个任务的验收标准** — success criteria + 验证方式（不可缺省）
3. **风险应对计划** — 基于 SPIKE 结果更新的风险清单

**执行路径选择**（让用户选）：

| 选项 | 适用场景 |
|------|---------|
| **立即执行** | 当前对话直接进入执行，AG 委派 CC 逐步实现 |
| **Infra Request** | 任务较大，作为 GitHub Issue 提交后续跟进 |
| **混合** | 核心部分立即执行，周边改进作为 infra request |

#### Infra Request 提交规范

如果选择 infra-request 路径：

```bash
# 1. 先检查 label 是否存在
gh label list --repo $ISSUES_REPO --json name | grep -q '"ready"' || \
  gh label create ready --repo $ISSUES_REPO --color 0E8A16

# 2. 创建 issue
gh issue create --repo $ISSUES_REPO \
  --title "[Infra] $TITLE" \
  --label "infra" \
  --body "$SUMMARY_BODY"

# 3. 详细设计文档作为 comment 附加
cp $DESIGN_DIR/blueprint/roadmap.md /tmp/design_doc.md
gh issue comment $ISSUE_NUM --repo $ISSUES_REPO \
  --body-file /tmp/design_doc.md
rm /tmp/design_doc.md
```

> [!WARNING]
> `gh issue create --label` 如果 label 不存在会静默失败。务必先确保 label 存在。

**✅ USER CHECKPOINT**：展示蓝图 + 用户选择执行路径

## Input Specification

system-design 接受任意格式的分析输入，但推荐结构：

```markdown
# Design Input

## Goal
一段话描述设计目标

## Current System
现有系统概要

## Key Decisions Already Made
[来自 deep-analysis system_map 中用户已做的决策]

## Constraints
[来自用户确认的约束]
```

来源可以是：
- `deep-analysis` 的 `system_map.md`（含用户已做的决策）
- 用户自己写的需求文档
- 其他分析工具的输出

## IPC Protocol

```text
~/.system-design/{design_id}/
├── input.md                    ← 分析输入
├── sketch/
│   ├── architect/
│   │   ├── prompt.txt / output.md
│   ├── realist/
│   │   ├── prompt.txt / output.md
│   ├── explorer/
│   │   ├── prompt.txt / output.md
│   └── proposals_summary.md    ← AG 差异对比（不是保守合并）
├── decide/
│   ├── decisions_log.md        ← 用户在每个分歧点的决策记录
│   ├── unified_design.md       ← 基于用户决策的融合设计
│   └── spike_list.md           ← 待验证假设
├── spike/
│   └── spike_001/
│       ├── spec.md / result.md
│       └── prompt.txt / output.md
└── blueprint/
    ├── roadmap.md
    └── infra_requests/
        └── request_001.md ...
```

## Mandatory Rules

1. **每个关键设计分歧必须呈现给用户** — AG 不得自行合并
2. **SKETCH 的 3 个 agent 独立执行** — 互不可见，保障视角多样性
3. **大胆方案不可丢弃** — 即使有风险也必须作为选项呈现
4. **SPIKE 必须用真实场景验证** — 禁止 AG 自验模式
5. **BLUEPRINT 必须提供执行路径选择** — 不只产出文档
6. **每个 phase 结束有 user checkpoint** — 但 checkpoint 是让用户决策，不是让用户批准

## Anti-Patterns

```
❌ AG 在 DECIDE 阶段自行选择"最安全的方案"
   → 之前的教训：Realist 约束 + AG 避险 = 所有创新方案被丢弃
   → AG 可以推荐，但必须呈现所有选项

❌ SKETCH 阶段让 agent 看到彼此的设计
   → 独立性保障视角多样性

❌ SPIKE 用 AG 自验
   → 之前的教训：agent-native-product SPIKE 通过但实际不可用
   → 必须用真实场景或独立 agent 验证

❌ BLUEPRINT 止于文档
   → 必须提供"立即执行"选项，让用户选择是否在当前对话执行

❌ AG 自己写实现代码
   → AG 写设计和编排，实现委派 task-delegate
```

## Integration with Other Skills

| Skill | 在 system-design 中的角色 |
|-------|-----------------------------|
| `task-delegate` | 所有 subagent 的执行底座 |
| `deep-analysis` | 前置分析（可选，提供 input.md + 用户已做的决策） |
| `agent-panel-discussion` | DECIDE 中验证关键决策的可选工具 |

## Lessons Learned

### GitHub Issue 创建

| 问题 | 原因 | 解决 |
|------|------|------|
| `--label` 静默失败 | Label 不存在于目标 repo | 先 `gh label create` |
| 设计文档无法 `--body-file` | AG brain 目录权限限制 | 先 `cp` 到 `~` 或 `/tmp` |
| Issue body 过长 | 完整设计 > 20KB | Body 写摘要，设计文档作为 comment 附加 |

### 验证闭环

- **Infra request 必须包含验证方式字段** — 缺省则 merge 后无法验证
- **验证命令不硬编码** — 在 issue 中明确指定
- **区分编码/验证角色** — 编码用 CC，验证用独立 agent 或用户
