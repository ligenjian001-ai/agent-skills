# Concept Model Review — 概念模型审计

> 版本: 1.0 | 日期: 2026-03-14 | 来源: agent-native-product smoke test 中的关键发现

## 要解决的问题

我们在审计 quant_trading 框架的 agent 友好度时发现，最根本的问题不在 API 表面或文档，
而在于**核心概念模型**：

- `order` / `fill` / `round-trip` 概念混淆（F-3）
- `BarAgent` 的生命周期语义不透明（F-7）
- `SessionAgent` 的 EOD 行为是隐式的（F-13）
- `aggTrade` dict 有 framework 注入的隐式字段（F-15）

这些问题用「改文档」「加参数」解决不了——它们是**概念架构**层面的问题。

更进一步：**一个产品的竞争力，取决于它的概念模型能否有效地 fill 理念和实现之间的 gap。**
概念模型好的产品，用户能快速从想法映射到代码；概念模型差的产品，用户要写大量样板代码来
弥补框架的抽象缺失。

## 解决方案

独立的 3 阶段审计 skill：

1. **DISCOVER** — 从代码和文档中提取概念模型（显式 + 隐式概念）
2. **EVALUATE** — 评估模型质量（完整性、正交性、分层、承诺-实现 gap）
3. **PATH DESIGN** — 设计概念打开路径（用户从零到精通的学习序列）

AG 编排，subagent 执行，用户在每个阶段 checkpoint。

## 设计决策

### 为什么从 agent-native-product 独立出来？

agent-native-product 关注的是「让 agent 更好用」，scope 是 API surface + 文档 + 可观测性。
但概念模型审计是更根本的问题：

- **适用范围更广**：不只是 agent 友好度，也用于评估产品竞争力
- **深度不同**：agent-native-product 的 A1 维度太浅，无法做好概念发现和 gap 分析
- **产出不同**：concept_map + 打开路径是独立有价值的产物，可供多个下游 skill 使用

### 为什么要识别「隐式概念」？

代码中大量存在但未显式命名的抽象（比如 quant_trading 的 `time` 字段被 `load_agg_trades`
默默注入，`SessionAgent.on_eod` 隐式清空内存）。这些是最大的概念债务——用户不知道它们
存在，直到撞上 bug。

### 为什么需要 PRODUCT_PROMISE？

评估概念模型需要一个标准。如果产品说自己「让量化交易变简单」，但写一个 MA 交叉策略
需要 50 行样板代码 + 理解 BarAgent 生命周期 + 手动分析 trade records，那就是
概念模型没有兑现承诺。没有 PRODUCT_PROMISE 就没法做 gap 分析。

## 什么会让这个 skill 过时？

如果 AI agent 进化到能完全自主理解任何代码库的概念模型（不需要人类辅助确认），
DISCOVER 阶段可以自动化。但 EVALUATE 和 PATH DESIGN 仍然需要人类判断——
因为「产品定位是否正确」和「学习路径是否自然」是主观判断。

**应该保留的部分**：承诺-实现 gap 分析框架。这是评估任何产品竞争力的通用方法。

## 演进历史

| 日期 | 版本 | 变更 |
|------|------|------|
| 2026-03-14 | 1.0 | 初版：从 agent-native-product A1 独立出来 |

## 文件索引

| 文件 | 用途 |
|------|------|
| `SKILL.md` | Agent 操作指南（编排流程） |
| `README.md` | 人类设计文档（本文件） |
| `prompts/concept_discoverer.txt` | 概念发现 prompt |
| `prompts/model_evaluator.txt` | 模型评估 prompt |
| `prompts/path_designer.txt` | 打开路径设计 prompt |
