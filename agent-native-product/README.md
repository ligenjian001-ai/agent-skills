# Agent-Native Product Transform

> 版本: 2.0 | 日期: 2026-03-14 | 来源: quant_trading 项目 smoke test（15 个 friction points）

## 要解决的问题

SDK/框架作者是为人类开发者设计的。当 AI agent 尝试使用这些项目时，会撞上人类无意识绕过的摩擦：
未文档化的数据目录结构、不一致的日期格式、缺少工具函数、有状态组件的生命周期陷阱。

现有工具（linter、文档生成器）只能发现**静态问题**。但最严重的 agent 摩擦——
运行时崩溃、文档与代码不一致、状态管理陷阱——是**静态分析看不到的**。
只有让 agent 真正跑一遍框架才能发现。

## 解决方案

3 阶段编排流程（ASSESS → TRANSFORM → AUDIT）：
- **维度评估** (A1-A6) 给 agent 友好度打分，A1 (API Quality) 是前置维度
- **模块化 prompt 文件** 每个子 agent 角色独立 prompt（Scout、Transformer、Auditor）
- **Agent Trial** (A6) 可选的实际运行测试，捕获运行时才暴露的问题

AG 编排，子 agent 通过 task-delegate 执行。

## 设计决策

### 为什么用模块化 prompt 文件？

v1 的 SKILL.md 有 372 行，所有 prompt 都内联。问题：
- 改一个 prompt 要重新读整个文件
- prompt 变更和流程逻辑变更混在 git 历史里
- agent 上下文窗口被不需要的 prompt 浪费

`prompts/` 目录沿用 `deep-analysis` 和 `system-design` 的模式。

### 为什么 A6 Agent Trial 是可选的？

静态评估（A2-A5）成本低、总是适用。Agent Trial 需要：
- 项目可本地运行（不是所有 SDK 都能在本地跑）
- 时间（agent 要跑完完整流程）
- 有明确的「最简工作流」可以跟

强制要求会阻塞那些不容易本地运行的项目的评估。

### 为什么 A5 有 6 个必检项？

每个检查项对应 quant_trading smoke test 中的真实失败：
- F-1 → Data Layout（agent 找不到数据文件）
- F-2 → Date/Format Conventions（YYYYMMDD vs YYYY-MM-DD 混淆）
- F-5 → Execution Semantics（LIMIT 订单撮合逻辑不可见）
- F-7 → Lifecycle Documentation（BarAgent 先检查后喂数据的语义）
- F-10 → Column Name Verification（文档写 'vol'，代码返回 'volume'）
- F-15 → Derived Fields（aggTrade dict 中未文档化的 'time' 字段）

不是假设——3 个独立的 Opus 4 agent 全部独立踩到了。

### 为什么 A2 增加 Missing Utility 检测？

3 个 agent 各自独立写了 ~80 行相同的性能分析代码。
这是框架缺少关键工具的最强信号。A2 prompt 现在主动搜索 4 类常用工具。

## 什么会让这个 skill 过时？

如果 AI agent 框架进化出内建的自评估工具（比如 Claude 的工具可以自动检测未文档化的 API
或缺失的工具），ASSESS 阶段就会变得多余。TRANSFORM 阶段会被框架自带的文档生成取代。

**应该保留的部分**：Friction log 模板和 A6 Agent Trial 方法论。
这些是框架无关的测试实践，无论工具如何进化都有价值。

## 编排复杂度说明

本 skill 是典型的**编排类 skill**——AG 不亲自做实现，而是编排多个 subagent 完成评估、改造、审计。
这类 skill 的特点：

- **多步骤 subagent 调用**：Scout → Transformer ×N → Auditor，每步有独立 prompt
- **日志驱动的持续反思**：每次实际使用后，通过 friction log 和 subagent 输出回顾改进 prompt
- **prompt 迭代频率高**：prompt 文件比流程逻辑变化快得多，所以必须分离

## 演进历史

| 日期 | 版本 | 变更 |
|------|------|------|
| 2026-03-13 | 1.0 | 初版：内联 prompt，A2-A5 维度 |
| 2026-03-14 | 2.0 | 模块化 prompt，A6 Agent Trial，A5 必检项，A2 Missing Utility，friction log 模板 |

## 文件索引

| 文件 | 用途 |
|------|------|
| `SKILL.md` | Agent 操作指南（编排流程） |
| `README.md` | 人类设计文档（本文件） |
| `prompts/scout.txt` | 评估 prompt 模板（A1-A5 + A6 占位符） |
| `prompts/scout_a6_agent_trial.txt` | A6 Agent Trial 段落（启用时注入 Scout） |
| `prompts/transform_a1_api_quality.txt` | API 质量审计（概念模型、正交性、便利层） |
| `prompts/transform_a5_docs.txt` | 文档生成 + 6 个必检项 |
| `prompts/transform_a2_api.txt` | API 审计 + Missing Utility 检测 |
| `prompts/transform_a4_observability.txt` | 可观测性基础设施 |
| `prompts/auditor.txt` | 独立审计（感知 A5/A6） |
| `prompts/friction_log_template.txt` | 标准化 F-N friction log 格式 |
