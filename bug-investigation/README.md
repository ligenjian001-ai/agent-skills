# Bug Investigation — Multi-Agent Bug Root Cause Analysis

> v1.0 | 2026-03-09 | Author: AG

## The Problem

单一 AI agent 分析 bug 时容易陷入思路固定（tunnel vision）。CC 可能过于关注代码层面的表象，忽略逻辑层面的假设错误；反之亦然。实际使用中观察到，CC 独立分析 bug 给出错误答案的概率不低。

## The Solution

**双分析师独立诊断 + AG 综合裁决**：

1. CC 作为**代码分析师**——擅长代码路径追踪、数据流分析
2. Codex 作为**逻辑推理分析师**——擅长假设挑战、边界条件分析
3. AG 作为**调查官**——收集 context、对比两方报告、交叉验证假设、写最终判定

两个分析师看到相同的 bug context，但互相看不到对方的分析（保证独立性）。AG 关注两方的**分歧点**——这往往是单一 agent 容易遗漏的盲点。

## Design Decisions

### 为什么只用两路而不是三路？

两路已经覆盖了最主要的分析维度（代码 vs 逻辑）。三路会增加延迟和成本，但边际收益递减。未来如果需要多模态分析（比如 UI bug 需要看截图），可以加 Gemini 作为第三路。

### 为什么 CC 做代码分析、Codex 做逻辑分析？

CC 擅长读文件和代码操作，适合代码级别的追踪；Codex 的推理能力强，适合逻辑层面的深度思考。Prompt 进一步强化了这种分工。

### 为什么反驳轮是可选的？

大多数 bug 场景下，两方独立分析 + AG 综合就足够了。只有当两方结论严重矛盾时，才需要反驳轮来进一步交叉验证。强制反驳轮会增加不必要的延迟。

### 与 panel-discussion 的区别？

Panel-discussion 适用于**开放话题讨论**（3 角色、多轮反驳、信心评分）。
Bug-investigation 适用于**定向问题诊断**（2 分析师、单轮 + 可选反驳、代码级定位）。
两者共享底层基础设施（task-delegate）但服务于不同场景。

## File Index

| File | Purpose |
|------|---------|
| `SKILL.md` | Agent 操作指南——工作流、规则、反模式 |
| `README.md` | 人类文档——设计决策、架构 |
| `prompts/code_analyst.txt` | CC 代码分析师角色模板 |
| `prompts/logic_analyst.txt` | Codex 逻辑推理分析师角色模板 |
| `scripts/inv_prepare.sh` | 从 bug context + 模板生成分析 prompt |
| `scripts/inv_launch.sh` | 通过 task-delegate 启动 analyst（thin wrapper） |
| `scripts/inv_collect.sh` | 收集两份报告，生成对比摘要 |
| `scripts/inv_report.sh` | 组装完整调查报告 |

## Evolution History

| Date | Version | Change |
|------|---------|--------|
| 2026-03-09 | v1.0 | Initial creation — dual analyst (CC + Codex) investigation |
