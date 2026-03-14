# 全局规则配置指南

> [!IMPORTANT]
> 仅 clone 本仓库 **不足以让 skill 正常工作**。
> 你需要在 AG Settings 中注册 skill 目录，并在全局规则中添加关键配置。

## 必须配置的规则

### 1. Skill 目录注册（AG Settings）

AG 现已支持在 Settings 中直接添加全局 skill 目录，**不再需要 symlink**。

**操作步骤**：
1. 打开 AG Settings
2. 找到 Skills 配置项
3. 添加你 clone 的 `agent-skills/` 目录路径

配置后，AG 会在所有 workspace 中自动发现本仓库的所有 skill。

### 2. 终端可靠性协议

tmux-protocol 是所有终端操作的基础。必须在 GEMINI.md 中 **内联** 关键规则：

```markdown
## 11. TERMINAL RELIABILITY — HARD GATE

**在任何对话的第一次 `run_command` 之前，必须先执行：**
\```bash
view_file("/path/to/agent-skills/tmux-protocol/SKILL.md")
\```

**所有终端命令通过 tmux：**
\```bash
bash /path/to/agent-skills/tmux-protocol/scripts/init_session.sh {id}
tmux send-keys -t {id} 'your_command_here' Enter
\```

**每次 `run_command` 必须设置：**
- `waitForPreviousTools=true`
- `SafeToAutoRun=true`
- `WaitMsBeforeAsync=3000`
```

**为什么需要**：不加这条规则，agent 会直接用 `run_command` 执行命令，遇到交互式程序或长时间运行的命令时 **会导致对话永久挂起**。

### 3. 对话归档自动启动

ag-archive skill 需要在每次对话开始时自动创建 journal：

```markdown
## 13. CONVERSATION JOURNAL & SUMMARY — AUTO-START/END

**每次对话开始时**，AG 必须：
1. 读取 `/path/to/agent-skills/ag-archive/SKILL.md`
2. 创建 `conversation_journal.md`，记录用户第一条消息

**对话结束时**，AG 必须写入 `conversation_summary.json`：
\```json
{ "title": "...", "summary": "...", "updated_at": "...", "tags": [...] }
\```
```

**为什么需要**：没有这条规则，conversation journal 和 daily-report 的数据链路断裂，日报无法生成。

### 4. AG 编排优先

确保 AG 在收到非平凡任务时主动建议委派方式：

```markdown
## 14. AG 编排优先 — DELEGATION CHECKPOINT

每次收到非平凡任务时，AG 必须主动询问：
> 📋 这个任务我建议 [自己做 / 通过编排 subagent 来做]，理由是 [xxx]。你怎么看？
```

**为什么需要**：没有这条规则，AG 会倾向于自己编码而不是委派给 CC/Codex 等后端，导致上下文被污染、任务链路无法延长。

## 建议配置的规则

以下规则非强制但强烈建议，能显著改善 skill 执行效果：

| 规则 | 作用 |
|------|------|
| Agent Manager 审批可见性 Bug（§12） | 防止 `SafeToAutoRun=false` 时对话无限等待 |
| GitHub 内容访问优先级（§15） | 确保 CLI 优先于浏览器访问 GitHub |
| 工程基础规则（§1-§9） | 通用工程纪律，防止 agent 吞异常、污染根目录等 |

## 快速上手

1. **AG Settings** 中注册 `agent-skills/` 目录（步骤 1）
2. **全局规则**中至少加入上述 3 条规则（§11, §13, §14），把 `/path/to/agent-skills/` 改为你自己的路径

> [!TIP]
> 完整的全局规则注册机制详见 [skill-creator/SKILL.md](skill-creator/SKILL.md) 中的 "GEMINI.md — Global Rule Registration" 章节。
