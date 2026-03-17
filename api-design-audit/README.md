# API 设计审计 — 用户偏好驱动的设计质量门禁

> v1.0 | 2026-03-15 | 源自 OrderBook Session Confirm 设计过程

## 问题

AG/CC/Codex 提出的 API 设计方案经常不符合用户的设计哲学。具体表现：

- 引入新 enum/struct 替换原始事件语义（用户要求保留 raw data）
- 堆砌 utility method 列表而没有统一的核心概念（用户要求一个 C 位）
- 假设统一的数据语义而忽略市场差异（如 SH Incremental Volume）
- 存储冗余状态而非在查询时推导

这些偏好不是显而易见的——两个顶级 AI 模型（CC 和 Codex）都未能一次性满足。

## 解决方案

将用户的设计偏好提炼为 **7 个可验证的检查项**，形成审计流程：

| # | 检查项 | 一句话 |
|---|--------|--------|
| C1 | Raw Data Preservation | 不改原始事件 |
| C2 | Metric Justification | 抽象必须服务指标 |
| C3 | Single Core Concept | 有且仅有一个 C 位 |
| C4 | Data Constraint Grounding | 基于数据约束设计 |
| C5 | Minimal Stored State | 能推导不存储 |
| C6 | Additive Not Replacement | 加方法不加类型 |
| C7 | Market Difference Transparency | 透明差异不掩盖 |

审计产出结构化报告（PASS / NEEDS WORK / FAIL），附逐项证据和改进建议。

## 设计决策

### 为什么是 7 项而不是 3 项或 20 项？

- 从 `docs/user_api_design_preferences.md`（CC 生成，用户确认）提取
- 5 条原则 + 4 个反模式 → 去重合并为 7 个正交检查项
- 每项都有来自真实案例（CC 方案 / Codex 方案 / 用户方案）的 PASS/FAIL 样本

### 为什么 C1 和 C3 是 hard gate？

用户明确表达的两个最强偏好：
- C1："保留最原始的event事件和信息" — 这是设计哲学的地基
- C3："所有接口设计的C位！你之前的那些都可有可无" — 用户亲口定义

### 为什么不委派给 subagent？

审计是轻量级的结构化判断（读设计 → 逐项打分），AG 自己做比委派更快更准确。Subagent 反而可能过度解读或遗漏检查项。

## 失败的方案

无（这是第一版）。

## FAQ

Q: 审计只适用于 HFT/OrderBook 设计吗？
A: 当前 7 项检查主要来自 HFT 领域案例，但 C1-C3、C5-C6 是通用的 API 设计原则。C4 和 C7 在单市场/单数据源场景下可标记为 N/A。

Q: 用户想违反某个检查项怎么办？
A: 支持用户 override。在审计报告中标注 "C{N}: ❌ (user override: {reason})"，不阻塞。

Q: 审计报告给谁看？
A: 给用户。AG 不应该默默审计后只展示设计，审计结果应一并呈现。

## 演进历史

| 日期 | 版本 | 变更 |
|------|------|------|
| 2026-03-15 | v1.0 | 初版：7 检查项，源自 Session Confirm 设计过程 |

## 文件索引

| 文件 | 用途 |
|------|------|
| `SKILL.md` | AG 操作指南（审计流程 + 判定标准） |
| `README.md` | 本文件（设计理念 + 演进记录） |
