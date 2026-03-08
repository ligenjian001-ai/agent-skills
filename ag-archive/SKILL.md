---
name: ag-archive
description: "Conversation Journal protocol for preserving decision context, error patterns, and user intent across AG conversations."
---

# AG Archive Skill

> **PURPOSE**: 保存对话上下文用于持续复盘 — 追踪反复犯错的问题、拼凑工作日报、支撑战略改进。
> 所有数据保存在 brain artifacts 中，AG 跨对话可直接读取。

> [!CAUTION]
> **设计目标区分：**
>
> - `conversation_journal.md` — 记录**用户原始意图**、**关键决策**、**AG 犯的错**。**不是**用来吹嘘进展。
> - `walkthrough.md` — 记录技术实现细节和测试结果。**这才是**进展记录。

## Conversation Journal Protocol ⭐ 核心

> [!IMPORTANT]
> **每次对话的第一条用户消息是最重要的信息。** AG 在每次对话开始时必须自动记录它。

### 自动记录（对话开始时）

AG 在收到用户第一条消息后，**在做任何其他事情之前**，必须创建 `conversation_journal.md`：

```markdown
# Conversation Journal

> 对话 ID: `{conv_id}`
> 开始时间: {YYYYMMDD HH:MM}
> 初始目标: {user_first_message_summary}

## 用户原始请求

{完整的第一条用户消息，原文保留}

## 记录

### {YYYYMMDD HH:MM}
**[{决策|错误}]** {标题}
{内容}
```

**保存位置**: `<appDataDir>/brain/<conversation-id>/conversation_journal.md`（brain artifacts 内）

**为什么放 brain artifacts？**

- Brain artifacts **跨对话可读** — AG 在任何对话中都可以通过 `view_file` 直接读取
- Knowledge subagent 也会读 brain artifacts — 自动提炼到 knowledge items 里
- 人类也通过让 AG 检索获取信息，不需要单独的导出目录

### 记录格式

单一时间线，时间戳单独一行，标签 + 标题在下一行：

- `[决策]` — 用户意图变化、方向调整、选项抉择
- `[错误]` — AG 犯的错、用户纠正的点、返工原因
- `[subagent]` — AG dispatch 了 subagent（task-delegate / panel-discussion）

```markdown
### YYYYMMDD HH:MM
**[决策]** 移除 ~/ag-archive/ 导出
用户明确：所有数据消费者都是 agent。不需要单独的导出目录。

### YYYYMMDD HH:MM
**[错误]** AG 编造了设计动机
AG 凭推测写了 5 个 skill 的 README 设计动机，全部被用户纠正。
```

### Subagent Tracking（⭐ 新增）

AG 在 dispatch subagent 时，**必须**在 journal 中记录 `[subagent]` 条目：

```markdown
### YYYYMMDD HH:MM
**[subagent]** 委派 CC 修复 Issue #49
- task: 20260308_0341_issue49_developer

### YYYYMMDD HH:MM
**[subagent]** Panel Discussion: AI Poker 商业化
- panel: `~/.panel-discussions/panel_20260307_2326/`
- tasks: 20260307_2326_panel_r{0,1,2}_{skeptic,pragmatist,optimist}
```

**还原链路**：

- **正向**：journal `[subagent]` → task_id → `~/.task-delegate/{task_id}/execution_record.json`
- **反向**：`execution_record.json` → `source_conversation` → `brain/{conv_id}/`

Drill-down: `cat ~/.task-delegate/{task_id}/execution_record.json` 获取完整执行数据。

> [!IMPORTANT]
> 复盘（问题模式总结）由用户主动 cue，AG 不自动做。

### 存活机制：注入 + 唤醒

Journal 协议面临一个核心矛盾：**AG 在对话过程中很可能忘记记录。**

| 阶段 | 机制 | 可靠度 |
|------|------|--------|
| **对话开头** | GEMINI.md 注入执行 | ~90% |
| **对话中后期** | 用户主动唤醒 | 100% |

**设计哲学**：不信任 agent 的长期记忆，前期靠注入强制执行，后期靠人类主动唤醒。

### 手动触发追加

用户说 "记录一下" / "journal update" 时，在 `## 记录` 末尾追加新条目：

```markdown
### YYYYMMDD HH:MM — [决策|错误] 标题
内容
```

### 与 Walkthrough 的关系

| 文件 | 记录时机 | 内容侧重 |
|------|---------|---------|
| `conversation_journal.md` | 对话开始 + 中途补齐 | 用户目标、决策、错误 |
| `conversation_summary.json` | 对话结束 / 实质性工作完成后 | 标题 + 一句话摘要 |
| `walkthrough.md` | 任务完成后 | 技术实现细节、测试结果 |
| `task.md` | 任务执行中 | 进度跟踪 checklist |

## Conversation Summary Persistence ⭐ 日报数据源

> [!IMPORTANT]
> **对话结束时（或实质性工作完成后），AG 必须写入 `conversation_summary.json`。**
> 这是 daily-report skill 的核心数据来源。不写 = 日报中缺失这个对话。

当对话中有实质性操作（编辑了文件、运行了命令、完成了分析）时，AG 在最后一次 `notify_user` 或对话结束前写入：

```json
{
  "title": "对话标题（简短描述做了什么）",
  "summary": "一句话总结对话的核心产出",
  "updated_at": "2026-03-08T03:00:00+08:00",
  "tags": ["hft_build", "demo"]
}
```

**保存位置**: `<appDataDir>/brain/<conversation-id>/conversation_summary.json`

**写入规则**:

- **ALWAYS write** — 即使对话很短。没有 summary = 日报中彻底丢失这个对话
- `title`: 用中文，不超过 30 字。示例: "修复 CK Demo 数据加载问题"
- `summary`: 一句话，不超过 100 字。描述产出，不描述过程
- `tags`: 可选，帮助 daily-report 做项目匹配。用项目目录名或关键词
- `updated_at`: ISO 格式本地时间
- **可覆盖更新**: 对话中途写一次，结束前再更新也可以

**什么算「实质性操作」？** 编辑文件、运行命令、创建 artifact、完成分析。纯问答（"Python 怎么读 JSON？"）不需要写。

## When to Trigger

- **自动触发**: 每次对话开始时自动创建 `conversation_journal.md`
- **自动触发**: 实质性工作完成后写入 `conversation_summary.json`
- 用户说 "记录一下"、"journal update" → 追加记录
- 用户说 "导出当前对话" → 深度导出模式

## Deep Export (Current Conversation Only)

> [!CAUTION]
> This mode can ONLY run inside the conversation you want to export.

When the user says "导出当前对话":

1. AG reads its own conversation history
2. Writes the full transcript as structured markdown
3. If truncated, clearly note: `⚠️ 对话记录不完整 — 仅包含从 Step N 开始的内容`
4. Saves to `<appDataDir>/brain/<conversation-id>/chat_transcript.md`

## Anti-Patterns

```
❌ Skipping journal creation at conversation start "because the task is simple"
   → EVERY conversation gets a journal

❌ Deep Export from a DIFFERENT conversation
   → Only works inside the active conversation
```

### ❌ Journal 写成 Walkthrough（最常见的失败模式）

**自测方法**：如果你写的内容放进 walkthrough.md 也毫无违和感，那你就写错了。

```
❌ "完成 P1 refine：ag-archive 补了 Anti-Patterns + README"
✅ "AG 凭推测编造了 5 个 skill 的设计动机，全部被用户纠正"

❌ "创建了 skill-creator skill，定义六段黄金标准"
✅ "用户希望以 tmux-protocol 为金标准——不只是操作指南，而是系统化文档"
```

## Mandatory Rules

1. **Journal FIRST**: Create `conversation_journal.md` before doing ANY other work
2. **Summary LAST**: Write `conversation_summary.json` before conversation ends (if substantial work done)
3. **问题导向，非成果导向**: Journal 记录决策和错误，不记录成果清单
4. **复盘由用户 cue**: AG 不自动做问题模式总结
