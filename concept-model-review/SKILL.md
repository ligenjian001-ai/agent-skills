---
name: concept-model-review
description: "Review a product/SDK/framework's core conceptual model — assess completeness, orthogonality, layering, and design the opening path. Trigger: '概念模型审计', 'concept review', '产品架构评估', 'API 概念梳理'."
---

# Concept Model Review

> **ROLE**: AG is the **review orchestrator**. AG dispatches Discoverer (concept extraction),
> Evaluator (model assessment), and Path Designer (opening path) subagents via task-delegate.
> AG synthesizes findings into a concept_map for user review.

> [!IMPORTANT]
> This skill reviews the **conceptual architecture** of a product — not its code quality,
> not its documentation, not its API surface. A good product bridges the gap between ideas
> and implementation through its conceptual model. This skill assesses how well it does that.

## When to Trigger

- 用户说"帮我梳理概念模型"、"审计一下这个 SDK 的架构"、"概念模型 review"
- 评估一个产品/框架的竞争力（概念模型是否足以支撑其定位）
- agent-native-product 的前置步骤（A1 维度的深度版本）
- 在做 system-design 之前，先理解现有概念模型的问题

## Core Thesis

> **好的产品 = 用正确的概念模型来 fill 理念和实现之间的 gap。**

评估一个产品的概念模型，本质上在回答三个问题：

1. **模型是什么？** — 产品把领域抽象成了哪些概念，它们之间是什么关系
2. **模型好不好？** — 完整性、正交性、分层、是否兑现产品承诺
3. **模型怎么打开？** — 用户/agent 从零开始如何理解和使用这套模型

## Prompt Files

All subagent prompts live in `prompts/`. AG reads, fills `{{PLACEHOLDERS}}`, dispatches.

| File | Phase | Placeholders |
|------|-------|-------------|
| `concept_discoverer.txt` | 1: DISCOVER | `PROJECT_PATH`, `LANGUAGE`, `PRODUCT_DESCRIPTION`, `OUTPUT_PATH` |
| `model_evaluator.txt` | 2: EVALUATE | `PROJECT_PATH`, `CONCEPT_MAP`, `PRODUCT_PROMISE`, `OUTPUT_PATH` |
| `path_designer.txt` | 3: PATH DESIGN | `PROJECT_PATH`, `CONCEPT_MAP`, `EVALUATION`, `TOP_WORKFLOWS`, `OUTPUT_PATH` |

## 3-Phase Workflow

```
DISCOVER (概念发现) → [user ✓] → EVALUATE (模型评估) → [user ✓] → PATH DESIGN (打开路径)
```

### Phase 1: DISCOVER — 概念发现

AG 准备项目上下文，dispatch Discoverer 提取概念模型。

1. AG 检测项目元数据：语言、模块结构、README/CLAUDE.md
2. AG 准备 Discoverer prompt（from `prompts/concept_discoverer.txt`）：
   - `{{PRODUCT_DESCRIPTION}}`: 用户或 README 提供的产品定位
   - `{{PROJECT_PATH}}`, `{{LANGUAGE}}`
3. Dispatch via task-delegate（read-only）
4. AG 读取 Discoverer 输出 → 整理为 `concept_map.md`
5. **✅ USER CHECKPOINT**: 用户确认概念图，补充遗漏的概念

```bash
REVIEW_ID="{YYYYMMDD_HHMM}_{project_name}"
REVIEW_DIR="${HOME}/.concept-model-review/${REVIEW_ID}"
mkdir -p "${REVIEW_DIR}/discover"

# AG reads prompts/concept_discoverer.txt, fills placeholders
bash ~/agent-skills/task-delegate/scripts/task_launch.sh \
  ${REVIEW_ID}_discoverer ${PROJECT_DIR} --backend codex
```

**Discoverer 产出**（`concept_map.md`）：

```markdown
## 显式概念（代码中有明确命名的抽象）
| 概念 | 类型 | 所在模块 | 职责 |
|------|------|---------|------|

## 隐式概念（代码中存在但未显式命名的抽象）
| 行为描述 | 在哪里出现 | 建议命名 |
|----------|-----------|----------|

## 概念关系图
[mermaid or text-based graph]

## 分层结构
- Foundation layer: ...
- Convenience layer: ...
- Missing layer: ...
```

### Phase 2: EVALUATE — 模型评估

基于 concept_map，评估模型质量。

1. AG 准备 Evaluator prompt（from `prompts/model_evaluator.txt`）：
   - `{{CONCEPT_MAP}}`: Phase 1 产出
   - `{{PRODUCT_PROMISE}}`: 产品宣称能做什么（用户提供或从 README 提取）
2. Dispatch via task-delegate
3. AG 读取评估结果
4. **✅ USER CHECKPOINT**: 用户确认评估，讨论关键 gap

**评估维度**：

| 维度 | 评估什么 | 差的表现 | 好的表现 |
|------|---------|---------|---------|
| **完整性** | 概念是否覆盖了所有用户需求 | 用户频繁需要"从零构建"本应框架提供的抽象 | 用户需求都能映射到已有概念 |
| **正交性** | 概念之间是否有不必要的耦合 | 改一个概念会意外影响另一个 | 每个概念独立可变 |
| **分层** | 是否有 foundation → convenience 自然层次 | 用户必须理解所有底层才能做简单的事 | 常用操作 1-3 行，底层可按需深入 |
| **命名** | 概念命名是否准确反映其职责 | 名字误导（如 `vol` 实际是 `volume`） | 名字即文档 |
| **承诺-实现 gap** | 概念模型是否真的兑现了产品定位 | 产品说"简单易用"但概念模型需要 50 行样板代码 | 概念模型设计直接体现产品价值主张 |

### Phase 3: PATH DESIGN — 打开路径设计

设计用户/agent 从零开始理解概念模型的最佳路径。

1. AG 准备 Path Designer prompt（from `prompts/path_designer.txt`）：
   - `{{CONCEPT_MAP}}`: Phase 1 产出
   - `{{EVALUATION}}`: Phase 2 产出
   - `{{TOP_WORKFLOWS}}`: 用户最常用的 Top-5 工作流（用户提供或从文档推断）
2. Dispatch via task-delegate
3. AG 读取路径设计
4. **✅ USER CHECKPOINT**: 用户确认路径，可直接用于文档生成

**Path Designer 产出**：

```markdown
## 入口概念
[从哪个概念开始最自然？为什么？]

## 学习序列
1. [第一个概念] — 因为 [理由]
   → 能做到：[此阶段用户能完成什么]
2. [第二个概念] — 因为 [理由]
   → 能做到：[此阶段用户能完成什么]
...

## Top-5 工作流与概念映射
| 工作流 | 涉及概念 | 当前需要的行数 | 理想行数 |
|--------|---------|-------------|---------|

## 概念打开路径图
[mermaid: 概念节点 + 推荐探索顺序]
```

## IPC Protocol

```text
~/.concept-model-review/{review_id}/
├── discover/
│   ├── prompt.txt
│   └── output.md           ← concept_map
├── evaluate/
│   ├── prompt.txt
│   └── output.md           ← 模型评估报告
├── path_design/
│   ├── prompt.txt
│   └── output.md           ← 打开路径设计
└── concept_map.md           ← AG 综合的最终概念图
```

## Mandatory Rules

1. **DISCOVER before EVALUATE** — 不能跳过概念发现直接评估
2. **User checkpoint after DISCOVER** — 用户确认概念图，因为 Discoverer 可能遗漏领域专家才知道的概念
3. **User provides PRODUCT_PROMISE** — 承诺-实现 gap 分析需要用户说明产品定位
4. **Discoverer is read-only** — 不修改任何文件
5. **隐式概念必须识别** — 代码中存在但未命名的抽象往往是最大的概念债务
6. **打开路径必须可执行** — 序列中每一步都要说明"此阶段用户能做到什么"

## Anti-Patterns

```
❌ 只看 API 签名不看概念模型
   → API 是概念模型的载体，审的是概念不是签名

❌ 把概念发现等同于类图
   → 隐式概念（代码中存在但未命名的抽象）往往更重要

❌ 评估时只说"不好"不说"gap 在哪"
   → 每个评估维度必须指出具体的 gap 和改进方向

❌ 打开路径按代码结构排序而不是按用户需求排序
   → 路径应从用户最常用的工作流出发，不是从代码目录结构出发

❌ 跳过 PRODUCT_PROMISE 直接评估
   → 没有产品定位就没法评估 gap，评估会变成没有标准的泛泛而谈

❌ AG 自己做概念发现
   → 必须 dispatch subagent，AG 负责综合和与用户对话
```

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Discoverer 产出太多细节 | 调整 prompt 强调"概念级别，不是类级别" |
| 用户不知道 PRODUCT_PROMISE 怎么写 | AG 从 README 提取一段，让用户确认/修改 |
| 概念关系图太复杂 | 分层展示：先 foundation，再 convenience |
| 评估全是"L1" | 可能是正常的——新项目概念模型通常不成熟 |
| 打开路径设计的"理想行数"不现实 | 标注哪些需要新 API，哪些需要重构 |

## Composability

| Combination | Description |
|-------------|-------------|
| concept-model-review → agent-native-product | 概念图 feeds A1 评估，打开路径 feeds A5 文档 |
| concept-model-review → system-design | 概念 gap 分析 feeds 重构设计 |
| concept-model-review (standalone) | 纯评估场景：判断产品竞争力 |
| deep-analysis → concept-model-review | system_map 的发现可以 cue 概念审计 |
