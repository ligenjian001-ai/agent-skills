# Agent Panel Discussion — 设计文档

> **版本**: v1.1 | **日期**: 2026-03-06 | **作者**: lgj team

---

## 为什么需要多 Agent 讨论？

在面对复杂决策（技术选型、开源授权策略、架构设计）时，单一 AI agent 容易产生**确认偏误**——它会倾向于论证自己第一直觉的正确性，而不是真正考虑替代方案。

Panel Discussion 通过**预设不同立场**的 agent，强制产生多角度分析。每个 agent 被锁定在特定的认知框架里，必须从自己的视角出发论证，产生真实的思想碰撞而非表面的"一方面...另一方面..."。

---

## 设计决策

### 为什么是 Skeptic / Pragmatist / Optimist 三角？

尝试过多种角色组合：

| 方案 | 问题 |
|------|------|
| Pro vs Con（正反方） | 二元对立，缺少中间路线，报告结论非此即彼 |
| 3个专家（如：法律/技术/商业） | 太依赖 topic 领域，不通用 |
| **Skeptic / Pragmatist / Optimist** | ✅ 覆盖风险/可行性/机会三维度，适用于任何话题 |

三角结构确保了：

- Skeptic 找风险（防盲目乐观）
- Pragmatist 评估可行性（防空中楼阁）
- Optimist 找机会（防过度保守）
- 三者的交集才是真正可行的方案

### 引擎选择的演进：从不可用到重新适配

初始设计时（v0.1）支持 CC/Codex/Gemini 三引擎混合。但实际运行中发现 **Codex 有 401 认证问题、Gemini 输出有 WARN 噪音**，都不稳定——因此 v1.0 暂时全部统一使用 CC。

**这不是设计选择，而是当时的能力约束。**

现在 Codex 已恢复可用，应当重新评估混合引擎方案。各引擎的特长：

| 引擎 | 核心能力 | 最适合的角色 |
|------|---------|-------------|
| **CC (Claude)** | 编码能力强 | 🔵 Pragmatist / 构建专家（评估可行性时可以引用实际代码模式） |
| **Codex (OpenAI)** | 推理能力强 | 🔴 Skeptic / 🟢 Optimist（正反方辩论需要强推理链） |
| Gemini | 多模态、搜索 | 信息收集辅助（但不稳定，暂缓） |

> **TODO**: 下一个迭代应该实验 CC + Codex 混合方案，利用各自的能力特长而非仅靠 prompt 差异。

### 为什么要信心评分？

在最终轮新增了 1-10 信心评分机制。这解决了一个问题：agents 在多轮辩论后立场经常模糊化（都开始"其实你说得也有道理"），信心评分**强制量化**每个 agent 对核心问题的最终判断，让分歧一目了然。

颜色编码：红≤4（强反对）、黄5-6（中立）、绿≥7（强支持）。

### 为什么 AG 需要做搜索？

Agents（CC/Codex）通过 CLI 运行时**无法上网**。但讨论需要事实支撑。解决方案：

```
Agent: "我需要 AGPL v3 的商业使用限制数据"
   ↓ [REQUEST] 标记
AG: search_web() + read_url_content() → research_supplement.md
   ↓ 注入下一轮 prompt
Agent: 基于真实数据继续论证
```

AG 作为信息中介，保留了 URL 溯源链，最终在 HTML 报告中生成可点击的引用。

---

## 已放弃方案

### 方案 A：实时辩论（agents 互相直接通信）

技术上不可行——CLI 模式的 agents 是独立进程，无法实时交互。改为回合制（每轮输出作为下一轮输入）。

### 方案 B：AG 参与讨论

违反了模块化原则。AG 有立场后就不再是中立的协调者，synthesis 的公正性受损。

### 方案 C：全部使用同一引擎（当前状态，待优化）

v1.0 因 Codex/Gemini 不可用而全部使用 CC。现在 Codex 已恢复，应该利用 CC 的编码能力和 Codex 的推理能力做差异化分工。

---

## FAQ

### Q1: 3 轮讨论够吗？

**默认 3 轮（Opening + 2 Rebuttal）在大多数话题上足够。** 实测发现第 4 轮开始观点趋同，产出递减。如果话题特别复杂，用户可以要求更多轮次。

### Q2: 立场变化声明是什么？

反驳轮中，`panel_prepare.sh` 会在 prompt 中注入要求：每个 agent 必须在回复开头声明"我修正了/坚持了/新增了哪些观点"。这让观点漂移**可追踪**。

### Q3: HTML 报告怎么在远程机器上查看？

`python3 -m http.server 8765 --bind 0.0.0.0` 然后从本地浏览器访问 `http://{server_ip}:8765/report.html`。

### Q4: 为什么 CC 擅长当 Pragmatist？

CC（Claude）在编码和技术细节方面很强，当被分配 Pragmatist / 构建专家角色时，它可以引用实际的代码模式、库选型、部署复杂度来评估可行性，不只是抽象讨论。

---

## 演进历史

| 日期 | 版本 | 变更 |
|------|------|------|
| 2026-03-05 | v0.1 | 初始版本 — 基础 3 角色辩论，CC/Codex/Gemini 混合设计 |
| 2026-03-05 | v0.2 | panel_prepare.sh + Codex/Gemini 不可用，暂时全部使用 CC |
| 2026-03-05 | v0.3 | 新增 AG 搜索中介 + research supplement |
| 2026-03-05 | v0.4 | 新增信心评分 + 立场变化声明 |
| 2026-03-06 | v1.0 | HTML 报告生成 + citation 系统 |
| 2026-03-06 | **v1.1** | 修正引擎选择记录（非设计选择，是能力约束）。Codex 已恢复，规划 CC+Codex 混合 |

## 文件清单

| 文件 | 作用 |
|------|------|
| `SKILL.md` | Agent 操作指南 — Phase 0~6 完整流程 |
| `README.md` | 人类文档 — 设计决策、角色选择、引擎演进、FAQ |
| `scripts/panel_prepare.sh` | 自动生成各 agent prompt |
| `scripts/panel_launch.sh` | 在 tmux session 中启动 agent（支持 CC/Codex/Gemini） |
| `scripts/panel_collect.sh` | 收集各 agent 输出 |
| `scripts/panel_report.sh` | 生成 Markdown 报告 |
| `scripts/panel_report_html.py` | 生成 HTML 报告（暗色 UI + 引用系统） |
| `prompts/skeptic.txt` | Skeptic 角色 prompt 模板 |
| `prompts/pragmatist.txt` | Pragmatist 角色 prompt 模板 |
| `prompts/optimist.txt` | Optimist 角色 prompt 模板 |
