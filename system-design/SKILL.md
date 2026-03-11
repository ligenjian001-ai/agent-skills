---
name: system-design
description: "Detailed system design — multi-perspective sketch, convergence, spike validation, and implementation blueprint. Works standalone or with deep-analysis output."
---

# System Design Skill

> **ROLE**: AG is the **设计引导者**. AG dispatches multiple perspective agents, converges their proposals, validates key assumptions via spikes, and produces an actionable implementation blueprint.

> [!IMPORTANT]
> This skill is about **designing the solution**, not analyzing the problem.
> If the problem space isn't clear yet, use `deep-analysis` first.

## When to Trigger

- User says "设计一下"、"怎么做这个系统"、"帮我出方案"
- A `system_map.md` from `deep-analysis` is ready and user wants to proceed
- User has a clear problem statement and wants architecture + implementation plan
- Requirements are understood but the HOW needs multi-perspective exploration

## 4-Phase Workflow

```
SKETCH → [user ✓] → DECIDE → [user ✓] → SPIKE → [user ✓] → BLUEPRINT
```

### Phase 1: SKETCH（多视角方案生成）

Dispatch 3 个独立 agent，各自基于输入文档设计方案：

| Agent | 后端 | 视角 | 产出 |
|-------|------|------|------|
| 🏛 Architect | CC | 纯架构设计：组件、接口、交互模式 | `architect/output.md` |
| 🔧 Realist | Codex | 基于现有代码的改造路径：哪些能复用、哪些要重写 | `realist/output.md` |
| 🔭 Explorer | Gemini | 技术选型 + 外部方案研究：业界怎么做、有什么工具 | `explorer/output.md` |

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
  ${DESIGN_ID}_realist ${PROJECT_DIR} --backend codex \
  --task-dir ${DESIGN_DIR}/sketch/realist

bash ~/agent-skills/task-delegate/scripts/task_launch.sh \
  ${DESIGN_ID}_explorer ${PROJECT_DIR} --backend gemini \
  --task-dir ${DESIGN_DIR}/sketch/explorer

# 提取输出
for role in architect realist explorer; do
  bash ~/agent-skills/task-delegate/scripts/task_extract.sh \
    ${DESIGN_ID}_${role} \
    --task-dir ${DESIGN_DIR}/sketch/${role} \
    --output-file ${DESIGN_DIR}/sketch/${role}/output.md
done
```

AG 读取三份方案后写 `proposals_summary.md`：关键差异对比表

**✅ USER CHECKPOINT**：展示三方方案摘要 + 差异对比，询问用户倾向

### Phase 2: DECIDE（收敛融合）

AG 主导设计融合：

1. **基于用户倾向 + AG 判断**，取各方案最佳元素
2. **写 `unified_design.md`** — 融合后的统一设计方案
3. **识别 spike 需求** — 哪些关键假设需要 PoC 验证？写入 `spike_list.md`
4. **（可选）Panel 验证** — 对关键决策点可触发 `agent-panel-discussion` 做快速辩论

**✅ USER CHECKPOINT**：展示融合设计 + spike 清单

### Phase 3: SPIKE（关键验证）

每个 spike = 最小实验验证一个关键假设

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

### Phase 4: BLUEPRINT（落地蓝图）

AG 将验证过的设计转化为可执行的实施计划：

1. **分阶段路线图** — `roadmap.md`（Phase A/B/C + 预估时间 + 关键产出）
2. **Infra Request 草案** — 每个关键任务写成 `infra-request` 模板格式的 `request_NNN.md`
3. **验收标准** — 每个任务的 success criteria
4. **验证方式** — 每个任务 merge 后如何验证（不可缺省）

#### Infra Request 提交规范

BLUEPRINT 产出最终以 GitHub Issue 形式提交。注意以下要点：

```bash
# 1. 先检查 label 是否存在，不存在则创建
gh label list --repo $ISSUES_REPO --json name | grep -q '"ready"' || \
  gh label create ready --repo $ISSUES_REPO --color 0E8A16

# 2. 创建 issue
gh issue create --repo $ISSUES_REPO \
  --title "[Infra] $TITLE" \
  --label "infra" \
  --body "$SUMMARY_BODY"

# 3. 将详细设计文档作为 comment 附加（避免 issue body 过长）
# 注意：如果设计文档在权限受限目录，先 cp 到可读路径
cp $DESIGN_DIR/blueprint/roadmap.md /tmp/design_doc.md
gh issue comment $ISSUE_NUM --repo $ISSUES_REPO \
  --body-file /tmp/design_doc.md
rm /tmp/design_doc.md
```

> [!WARNING]
> **`gh issue create --label` 如果 label 不存在会静默失败（issue 创建但不带 label），不会报错退出码非零。**
> 务必先用 `gh label list` 检查或 `gh label create` 确保 label 存在。

**✅ USER CHECKPOINT**：展示蓝图 + infra-request 草案

## Input Specification

system-design 接受任意格式的分析输入，但推荐结构：

```markdown
# System Map / Design Input

## Goal
一段话描述设计目标

## Current System
现有系统概要（架构、关键组件、已知限制）

## Analysis Findings
每个维度的关键发现和约束
```

来源可以是：

- `deep-analysis` 的 `system_map.md`
- 用户自己写的需求文档
- 其他分析工具的输出

## IPC Protocol

```text
~/.system-design/{design_id}/
├── input.md                    ← 分析输入（system_map.md 或其他）
├── sketch/
│   ├── architect/
│   │   ├── prompt.txt / output.md
│   ├── realist/
│   │   ├── prompt.txt / output.md
│   ├── explorer/
│   │   ├── prompt.txt / output.md
│   └── proposals_summary.md    ← AG 对比
├── decide/
│   ├── unified_design.md       ← 融合设计
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

1. **每个 phase 结束必须有 user checkpoint** — 不可自动推进
2. **SKETCH 的 3 个 agent 独立执行** — 互不可见，保障视角多样性
3. **AG 负责设计融合** — DECIDE 是 AG 主动写 `unified_design.md`，不是让 agent 写
4. **Spike 失败可以回退** — 不要硬着头皮推进到 BLUEPRINT
5. **BLUEPRINT 产出应为可执行的任务描述** — 可通过 infra-request 提交

## Anti-Patterns

```
❌ SKETCH 阶段让 agent 看到彼此的设计
   → 独立性保障视角多样性，交叉审查在 DECIDE 阶段进行

❌ 没有 spike 就写 BLUEPRINT
   → 未验证的关键假设进入蓝图 = 技术债

❌ AG 自己写实现代码
   → AG 写设计和编排，实现委派 task-delegate
```

## Composability

| 组合方式 | 说明 |
|----------|------|
| deep-analysis → system-design | `system_map.md` → `input.md` |
| panel-discussion → system-design | 辩论结论可作为输入 |
| system-design → infra-request | blueprint → GitHub Issues |
| 独立使用 | 用户自带需求文档直接进入设计 |

## Integration with Other Skills

| Skill | 在 system-design 中的角色 |
|-------|--------------------------|
| `task-delegate` | 所有 subagent 的执行底座 |
| `deep-analysis` | 前置分析（可选，提供 input.md） |
| `agent-panel-discussion` | DECIDE 中验证关键决策的可选工具 |

## Lessons Learned

以下是实际使用中积累的经验教训：

### GitHub Issue 创建

| 问题 | 原因 | 解决 |
|------|------|------|
| `--label` 静默失败 | Label 不存在于目标 repo | 先 `gh label create` |
| 设计文档无法 `--body-file` | AG brain 目录权限限制 | 先 `cp` 到 `~` 或 `/tmp` |
| Issue body 过长 | 完整设计 > 20KB | Body 写摘要，设计文档作为 comment 附加 |

### 验证闭环

- **Infra request 必须包含验证方式字段** — 如果缺省，merge 后无法自动验证
- **验证命令不硬编码** — 不同任务的验证方式不同，应在 issue 中明确指定
- **区分编码/验证角色** — 编码用 CC Max，验证用 Codex（或其他），角色分离提高可靠性
