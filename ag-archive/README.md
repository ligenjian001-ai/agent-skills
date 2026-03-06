# AG Archive — 对话知识保全

> **版本**: v2.0 | **日期**: 2026-03-06 | **作者**: lgj team

---

## 为什么需要这个 Skill？

AG 的对话数据有一个根本性限制：**`.pb` 文件是加密的，跨对话不可读。**

但 brain artifacts（`~/.gemini/antigravity/brain/{conv-id}/`）是跨对话可读的。ag-archive 的核心就是确保**关键信息保存在 artifacts 里**，而不是只存在于 `.pb` 中。

核心机制：**Conversation Journal** — 每次对话自动记录用户原始意图和决策上下文。

---

## 设计决策

### 为什么不导出到 ~/ag-archive/？

v1.0 曾设计了 `~/ag-archive/` 作为离线浏览目录。**v2.0 移除了这个设计**，原因：

1. 所有数据的消费者都是 AG（agent 跨对话读取）
2. 人类也通过让 AG 检索来获取信息，不需要单独的导出目录
3. Brain artifacts 已经跨对话可读，再拷贝一份是多余的

**简化后**：Journal 和 Deep Export 都直接保存在 brain artifacts 内。

### Journal 的存活机制：注入 + 唤醒

Journal 协议面临一个核心矛盾：**AG 在对话过程中很可能忘记记录。**

| 阶段 | 机制 | 可靠度 |
|------|------|--------|
| **对话开头** | GEMINI.md 注入执行 | ~90% |
| **对话中后期** | 用户主动唤醒 | 100% |

**设计哲学**：不信任 agent 的长期记忆，前期靠注入强制执行，后期靠人类主动唤醒。

### Journal 模板为什么用问题导向而非时间线？

v1.0 用的是 `## 进展记录`（时间线格式），实测发现 AG 把它写成了 walkthrough——列成果清单。

v2.0 改为三个问题导向 section：

- `## 关键决策点` — 意图变化、方向调整
- `## 错误与修正记录` — AG 犯的错、用户纠正
- `## 反复出现的问题模式` — 系统性弱点

**结构本身就防止了写成成果清单。**

---

## Skill 设计哲学

> ag-archive 属于**"弥补工具不足"**类 skill——AG 框架不提供对话数据的持久化和跨对话可读性（`.pb` 加密），Journal 协议填补了这个空白。
>
> 当 AG 框架未来原生支持跨对话数据共享时，batch archive 类功能可以退役（v2.0 已退役）。
> 但 Journal 协议作为「确保决策上下文不丢失」的机制，即使平台更新也仍有价值。

---

## 已放弃方案

### ~/ag-archive/ 离线导出（v1.0 → v2.0 移除）

曾设计 `ag_archive.sh` 增量导出所有 brain artifacts 到 `~/ag-archive/`，含 `index.md` 时间排序索引。移除原因：消费者是 agent 不是人类，brain artifacts 已足够。

### "进展记录" 时间线格式（v1.0 → v2.0 改为问题导向）

时间线格式让 AG 天然写成 walkthrough。改为决策点/错误/模式三段式结构后，内容质量显著提升。

---

## 演进历史

| 日期 | 版本 | 变更 |
|------|------|------|
| 2026-03-06 AM | v0.1 | 初始版本 — 基础 batch archive 功能 |
| 2026-03-06 PM | v1.0 | 新增 Journal Protocol、Deep Export、GEMINI.md 注册 |
| 2026-03-06 PM | v1.1 | 补充注入+唤醒存活机制 |
| 2026-03-06 PM | **v2.0** | **移除 ~/ag-archive/ 导出**。Journal 模板改为问题导向三段式。所有数据保存在 brain artifacts |

## 文件清单

| 文件 | 作用 |
|------|------|
| `SKILL.md` | Agent 操作指南 — Journal 协议、Deep Export |
| `README.md` | 人类文档 — 设计决策、已放弃方案、演进历史 |
