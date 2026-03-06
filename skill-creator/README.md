# Agent Skill 构建标准

> **版本**: v1.0 | **日期**: 2026-03-06 | **作者**: lgj team

---

## 为什么需要这个标准？

在构建 agent-skills 的过程中，我们发现 **文档质量直接决定了 skill 的可靠性**。

以 `tmux-protocol` 为例——它经历了 v1→v3.2 共 5 个版本的演进，每次迭代都是因为 agent 在实际使用中违反规则或遇到新的边界情况。最终沉淀出来的不仅仅是一份操作手册，而是一个包含设计决策、失败方案、平台约束和 FAQ 的**知识体系**。

其他 skill 的文档质量参差不齐：有些只有操作步骤没有设计背景，有些缺少 anti-patterns 导致 agent 反复犯同样的错误。

**skill-creator 的目标**：提炼 tmux-protocol 的文档范式为通用标准，让每个 skill 都能达到同样的文档质量。

---

## 核心设计原则

### 1. 两层文档分离

| 文档 | 受众 | 内容 | 特点 |
|------|------|------|------|
| `SKILL.md` | **Agent** | 操作步骤、规则、anti-patterns | 简洁、可执行、六段结构 |
| `README.md` | **Human** | 设计背景、失败方案、演进历史 | 详细、叙事性、知识密度高 |

**为什么分两层？**

- Agent 不需要知道"为什么设计成这样"——它只需要知道"怎么做"
- 但人类维护者需要知道设计背景，否则会做出破坏性修改（"这行代码看起来多余，删了吧"）
- 上下文压缩时，SKILL.md 的内容可能被丢弃，但如果关键规则已内联到 GEMINI.md 就不怕
- README.md 永远不会被 agent 自动读取，因此可以写得很详细而不浪费 token

### 2. 六段结构（从 tmux-protocol 提炼）

SKILL.md 的六段结构不是随意选择的。每一段都对应 agent 行为中的一个具体失败模式：

| 段 | 对应的失败模式 | 解决方式 |
|---|---|---|
| ① YAML frontmatter | Skill 不被发现/匹配 | 精确的 description + trigger 关键词 |
| ② Core Principle | Agent 角色漂移（该协调的去写代码了） | 开篇就锚定身份 |
| ③ 操作流程 | Agent 猜测下一步该做什么 | 可复制粘贴的精确命令 |
| ④ 硬规则 | Agent 忽略重要约束 | 显式编号 + 粗体强调 |
| ⑤ Anti-Patterns | Agent 重复犯已知错误 | ❌ 负面示例（LLM 遵从度更高） |
| ⑥ Troubleshooting | Agent 遇到错误盲目重试 | 症状→方案 查找表 |

### 3. 演进记录不是可选的

tmux-protocol 的演进历史（从 v1 到 v3.2）记录了：

- v2 的 AG_START/AG_END 手动 marker 为什么被 PS1 自动 marker 替代
- v2.1 的 flock 串行化为什么是死锁放大器
- v3.1 的 User Cancel Recovery 是从真实 bug 中发现的

**没有这些记录**，下一个维护者(或下一个 AI model)可能会重新"发明" flock 方案，然后重新发现它不工作。

---

## 已放弃的方案

### 方案 A：单一 SKILL.md 包含一切

最初考虑把设计背景、FAQ、演进历史都放在 SKILL.md 里。

**放弃原因**：

- SKILL.md 会变得巨大（tmux-protocol 的 README 有 242 行，DESIGN 有 228 行）
- Agent 读 SKILL.md 时会消耗大量 token 在它不需要的信息上
- 上下文窗口是有限资源，操作信息和背景信息争夺同一个空间

### 方案 B：使用 JSON Schema 定义 SKILL.md 结构

考虑用 JSON Schema 来强制 SKILL.md 的结构。

**放弃原因**：

- Markdown 的灵活性更适合叙述性内容
- 过于刚性的结构会导致"为了填写而填写"
- 实践中 SKILL.md 的结构变化（如 tmux-protocol 的 Background Recovery 独立成段）需要灵活性

---

## FAQ

### Q1: 每个 skill 都必须有 README.md 吗？

**推荐有，但不强制。** 判断标准：

- 如果 skill 有非显而易见的设计决策 → 需要 README
- 如果 skill 经历过重大迭代 → 需要 README 记录历史
- 如果 skill 是纯操作性的（如 ag-archive）→ SKILL.md 足够

### Q2: GEMINI.md 和 SKILL.md 的规则重复怎么办？

**这是故意的，不是 bug。** GEMINI.md 的规则在上下文压缩后仍然存活（作为 system prompt），SKILL.md 的内容可能被压缩掉。关键规则需要在两处都存在，形成冗余保护。

### Q3: 六段结构可以调整吗？

**可以调整段名和顺序，但不能删除任何一段。** 每段对应一个具体的 agent 失败模式，删除任何一段都会导致对应的失败模式重新出现。

### Q4: 已废弃的 skill（如 multi-agent-exec）需要遵循标准吗？

**不需要重构，但需要清晰标注 DEPRECATED。** 保留作为历史参考即可。当前标注方式（YAML description + 开头 blockquote）已经足够。

---

## 演进历史

| 日期 | 版本 | 变更 |
|------|------|------|
| 2026-03-06 | **v1.0** | **初始版本** — 从 tmux-protocol 提炼六段标准，定义 SKILL.md + README.md 双层文档体系 |

## 文件清单

| 文件 | 作用 |
|------|------|
| `SKILL.md` | Agent 操作指南 — 六段标准、质量检查清单、创建工作流 |
| `README.md` | 人类文档 — 设计原理、已放弃方案、FAQ、演进历史 |
