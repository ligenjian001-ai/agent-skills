# Agent Skills — Project Rules

## CONVERSATION JOURNAL — AUTO-START

**NON-NEGOTIABLE**: At the START of every conversation, after skill bootstrap, AG MUST:

1. Read `/home/lgj/agent-skills/ag-archive/SKILL.md` → Conversation Journal Protocol
2. Create `<appDataDir>/brain/<conversation-id>/conversation_journal.md` with the user's first message recorded **verbatim**
3. This takes priority over all other actions — **record first, then work**

The journal is NOT for celebrating progress (that's `walkthrough.md`'s job). The journal exists to:

- **Preserve the user's original intent** — the first message defines the objective
- **Track recurring errors and pain points** — patterns of repeated mistakes are the most valuable data
- **Enable daily/weekly work report compilation** — conversations are the raw material for structured retrospectives
- **Support continuous strategic improvement** — decision context that is otherwise lost when conversations truncate

## AG 编排优先 — DELEGATION CHECKPOINT

**每次收到非平凡任务时，AG 必须在 planning 阶段主动询问用户：**

> 📋 这个任务我建议 [自己做 / 通过编排 subagent 来做]，理由是 [xxx]。你怎么看？

**判断框架**：

| 信号 | 建议方式 |
|------|---------|
| 涉及多文件编码实现 | 🔀 编排 → CC |
| 需要深度推理/长链路分析 | 🔀 编排 → Codex |
| 涉及多模态（图片/浏览器/OCR） | 🔀 编排 → Gemini |
| 性价比优先的批量任务 | 🔀 编排 → DeepSeek |
| 简单单步操作（移动、重命名、配置调整） | ✅ AG 自己做 |
| 纯文档撰写 / 问答 / 快速验证 | ✅ AG 自己做 |

**编排收益**：AG 上下文不被实现细节污染 → 任务链路可以无限延长 → 每次委派通过 `[subagent]` tag 记录 → 全程可追溯。

**注意**：AG 给出建议但**用户有最终决定权**。AG 不得跳过 checkpoint 直接开始编码。
