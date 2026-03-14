# 系统设计 — 多视角架构技能

> **版本**: 2.0 | **更新**: 2026-03-14 | **作者**: AG

## 解决的问题

设计非平凡系统时，单一视角会产生盲点。但 v1 的"多视角生成 + AG 保守合并"模式在实际使用中暴露了严重问题：

- **AG 保守合并系统性丢弃大胆方案** — Realist 提出约束 → AG 选 Realist → Architect/Explorer 的创新方案被标为"后续考虑"
- **SPIKE 自验无效** — AG 设计实验、CC 执行、AG 审查 = 自己验自己。`agent-native-product` 的 SPIKE 通过了但产出 skill 实际完全不可用
- **BLUEPRINT 止于文档** — 产出 infra-request 草案后无人跟进，设计与执行断裂

6 次使用 deep-analysis + system-design，仅 1 次真正交付功能（17%）。

## 解决方案

4 阶段流程，核心变化在于 **用户在每个关键设计分歧做决策，AG 不保守合并**：

```
SKETCH → [用户选方向] → DECIDE → [用户逐点决策] → SPIKE → [真实验证] → BLUEPRINT
```

1. **SKETCH**: 3 独立 agent 产出设计方案（保留，视角多样性有价值）
2. **DECIDE**: AG 提取关键分歧，**用户逐点选择**，AG 基于用户决策写融合设计
3. **SPIKE**: **真实场景验证**（不是自验），或让独立 agent 使用产出验证
4. **BLUEPRINT**: 可执行路线图 + **立即执行选项**（不只产出文档）

## 技能设计哲学

### 核心信念

> **设计的目标是产出用户认可的可执行方案，每个关键决策由用户判断——而不是产出一份 AG 保守合并的中间文档。**

| 原则 | 含义 |
|------|------|
| **决策归属用户** | AG 呈现选项和 tradeoff，用户在分歧点做选择 |
| **大胆选项不可丢弃** | 有风险的方案 = 有价值的选项，由用户判断是否采用 |
| **真实验证 > 自验** | SPIKE 用真实场景验证，不是 AG 自己检查自己 |
| **通向执行** | 设计的终点不是文档，是可以开始执行的计划 |

### 填补了什么空白？

AG 单独设计时倾向于产出一个"最安全"的方案——遇到风险就保守回避。通过强制 3 个独立视角 + 用户逐点决策，这个技能确保大胆方案不被系统性消除，同时让用户（而非 AG）承担风险判断的责任。

### 什么时候可以退役？

如果 AG 底层模型能原生做到：(1) 持有多个矛盾观点并严谨论证、(2) 不自行避险而是呈现所有选项 + tradeoff、(3) 主动追问用户偏好——那么 SKETCH 阶段可以简化。如果 GitHub Actions 原生编排 agent 会话，task-delegate 集成也不再必要。

### 退役后什么应该保留？

- **用户逐点决策模式**（DECIDE phase）：分歧 → 选项 → tradeoff → 用户选
- **真实验证模式**（SPIKE phase）：禁止自验，用真实场景或独立 agent 验证
- **Infra request 提交标准**（issue body = 摘要，comment = 完整设计）
- **Label 安全协议**（`gh label create` 先于 `gh issue create --label`）

## 设计决策

### 为什么保留 3 agent SKETCH？

多视角本身有价值——避免锚定效应。v1 的问题不在于 SKETCH，而在于 DECIDE 阶段 AG 如何处理分歧。v2 保留 SKETCH 的独立探索，但把合并权交给用户。

### 为什么从 "AG 合并" 改为 "用户逐点决策"？

**v1 做法**: AG 读取 3 份方案后"融合"为 unified_design。实际是选了最保守的组合。

**为什么失败**: 在 `692b1f28`（strategy_zoo）中，AG 融合时选择了"scripts/ 不重组，只加 README 索引"（Realist 方案）、"现有 output/ 不动"（Realist 约束）。结果核心改造全部没做，只做了删垃圾文件。

**v2 做法**: AG 列出分歧项，逐一展示选项 + tradeoff，用户选择或提出新思路。AG 基于用户选择而非自己判断写 unified_design。

### 为什么废弃 SPIKE 自验模式？

**v1 做法**: AG 设计 spike、CC 执行、AG 审查结果。

**为什么失败**: `a15109cc` 的 SPIKE 在 quant-agent-gateway 上跑了一轮 ASSESS→TRANSFORM→AUDIT，报告"通过"。但后续 3 个对话中实际使用 `agent-native-product` skill 时发现完全不可用——checklist 方法论本身就不对。SPIKE 验证的是"流程能跑通吗"，但没验证"产出有用吗"。用户原话："过程过于粗糙而难以被执行"。

**v2 做法**: (1) 在真实场景中实现最小切片验证、(2) 让不了解上下文的独立 agent 使用产出物验证、(3) 用户场景 walkthrough。

### 为什么增加 "立即执行" 路径？

v1 的 BLUEPRINT 只产出 infra-request 草案。但 infra-request 的生命周期是另一条路径——提交后可能长期没人跟进。唯一成功交付的 `d6e89379`（QuantTrading 改造）是因为在同一对话中直接执行了，没走 infra-request 路径。

v2 增加"立即执行"选项：用户可以选择在当前对话直接委派 CC 开始实现。

### 为什么 3 个 agent，不是 2 个或 5 个？

（与 v1 相同）三个提供了最小可行多样性（架构、代码实操、外部研究），又不会爆炸成本。

## 失败的尝试

### v1: AG 保守合并 SKETCH 方案

已在"设计决策"部分详述。核心教训：**AG 在分歧中选最安全的 = 系统性消灭创新方案。**

### v1: SPIKE 自验模式

已在"设计决策"部分详述。核心教训：**自己验自己不算验证。SPIKE 通过 ≠ 产出可用。**

### 把完整设计文档塞进 issue body

（v1 教训保留）GitHub 在 body > 10KB 时渲染变慢。解决：body 写摘要，完整设计作为 comment 附加。

### 不检查 label 直接使用 `--label`

（v1 教训保留）`gh` 即使 label 不存在也返回 exit code 0。解决：先 `gh label create`。

### AG brain 目录作为 `--body-file` 源

（v1 教训保留）brain 目录有权限限制。解决：先 `cp` 到 `/tmp/`。

## FAQ

**Q: 如果我已经知道要怎么设计，可以跳过 SKETCH 吗？**

可以。直接写 `unified_design.md` 跳到 DECIDE，让 AG 识别哪些假设需要 spike 验证。多视角 sketch 在方案空间开放时最有价值。

**Q: DECIDE 阶段的分歧通常有多少个？**

通常 3-7 个核心设计选择。如果超过 10 个，可能说明 SKETCH 的粒度太细了——应该关注架构级选择，不是实现细节。

**Q: "真实验证" 具体怎么做？**

优先级：(1) 选一个最小切片直接实现 + 用真实数据跑；(2) 让一个对设计上下文零了解的 agent 使用产出物；(3) 用户拿设计 walkthrough 自己的典型场景。关键是验证"产出有用吗"而不是"流程跑通吗"。

**Q: "立即执行" 和 "infra-request" 怎么选？**

如果改造在 1-2 个 CC session 内能完成 → 立即执行。如果改造大到需要多天多人 → infra-request。混合模式最常用：核心部分立即执行，周边改进作为 infra-request。

**Q: 这个技能和 agent-pipeline 怎么配合？**

BLUEPRINT 产出的 infra request 变成 GitHub Issue。如果 agent-pipeline 守护进程在运行，它会自动认领带 `ready` label 的 issue 并派 CC 实现。

## 版本历史

| 日期 | 版本 | 变更 |
|------|------|------|
| 2026-03-11 | 1.0 | 初始创建——3 agent SKETCH + AG 合并 + SPIKE + BLUEPRINT |
| 2026-03-12 | 1.1 | 路径可移植化、BLUEPRINT infra request 标准、Lessons Learned |
| 2026-03-14 | 2.0 | **重新设计**: 用户逐点决策替代 AG 保守合并、真实验证替代自验、增加立即执行路径 |

## 文件索引

| 文件 | 用途 |
|------|------|
| `SKILL.md` | Agent 操作指南 — 工作流步骤、规则、反模式 |
| `README.md` | 人类文档 — 设计哲学、设计决策、失败尝试、FAQ |
| `prompts/sketch_architect.txt` | 架构师 agent 的 prompt 模板（CC 后端） |
| `prompts/sketch_realist.txt` | 务实者 agent 的 prompt 模板（CC 后端） |
| `prompts/sketch_explorer.txt` | 探索者 agent 的 prompt 模板（Codex 后端） |
