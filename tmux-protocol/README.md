# Antigravity 远程终端可靠性指南

> **适用场景**: 在远程 Linux 工作站上使用 Antigravity (AG) 进行 AI 辅助开发  
> **版本**: 2026-03-05 | **作者**: lgj team

---

## 问题：AG 的终端为什么总卡死？

AG 通过 `run_command` 工具执行终端命令。这个工具有几个**无法修改的设计限制**，在远程环境下尤其致命：

| 限制 | 说明 | 影响 |
|------|------|------|
| `WaitMsBeforeAsync` 硬上限 10s | 命令在这个时间内没输出 → 被转为 "Background" | tmux `send-keys` 永远没有 stdout → 必定 background |
| `waitForPreviousTools` 默认 false | 多个 tool call 默认**并行**执行 | send-keys 和 capture-pane 同时发出 → 读到旧状态 |
| Background ≠ 失败 | 框架把超时和失败用同一个机制处理 | 模型看到 "Background" 就恐慌 → 杀 session → 雪崩 |
| 远程网络延迟 | 本地 Mac ↔ 远程 Linux 有 50-500ms 延迟 | 吃掉 WaitMs 预算 → 更容易 background |

**核心矛盾**：AG 的 `run_command` 是为快速返回的命令设计的（如 `ls`、`cat`），但通过 tmux 操作终端时命令本身（`send-keys`）不产生输出，只有 pane 内容有输出——两者在不同的 channel 上。

---

## 解决方案：三层防御体系

### 第一层：Bashrc 哑终端模式（OS 级，100% 可靠）

在 `~/.bashrc` 中加入 agent 检测和环境隔离：

```bash
# 放在 conda init 之前，检测 agent 上下文
_ag_detected=0
if [[ -n "$ANTIGRAVITY_AGENT" ]] || [[ -n "$ANTIGRAVITY_WORKSPACE" ]] || \
   [[ "$TERM_PROGRAM" == "antigravity" ]]; then
    _ag_detected=1
elif [[ -n "$TMUX" ]]; then
    _tmux_sess=$(tmux display-message -p '#S' 2>/dev/null)
    if [[ "$_tmux_sess" =~ ^[0-9a-f]{8}$ ]]; then
        _ag_detected=1
    fi
fi

if [[ $_ag_detected -eq 1 ]]; then
    export TERM=dumb
    export DEBIAN_FRONTEND=noninteractive
    export PYTHONUNBUFFERED=1
    PS1='AG_READY:${?}:$ '          # ← 核心：自动 marker + exit code
    unset PROMPT_COMMAND
    unalias -a 2>/dev/null
    stty -ixon -ixoff 2>/dev/null
    export PATH="/home/lgj/miniconda3/bin:$PATH"   # conda binary 保留
    unset _ag_detected _tmux_sess
    return  # 跳过所有后续配置
fi
unset _ag_detected _tmux_sess
```

**效果**：

- 跳过 conda init、bash completion、color 等可能"毒化"输出的配置
- PS1 自动在每条命令执行完后打印 `AG_READY:{exit_code}:$`
- 模型**不需要做任何额外操作**即可判断命令状态

### 第二层：SKILL.md 协议文档（模型行为引导）

创建 `/home/lgj/agent-skills/tmux-protocol/SKILL.md`，在 GEMINI.md 中强制模型在首次使用终端前读取。

协议核心：所有命令通过 tmux send-keys 发送，通过 capture-pane 读取结果，通过 PS1 中的 `AG_READY` 标记判断命令状态。

### 第三层：GEMINI.md 内联规则（上下文压缩后仍存活）

在 `~/.gemini/GEMINI.md` 中用粗体、❌ 标记、明确正面陈述的方式写入关键规则。即使上下文被压缩，这些规则仍作为 system prompt 保留。

---

## 快速部署指南

### 1. 安装 bashrc 配置

把上面的 agent 检测代码块加到你的 `~/.bashrc` 中，**放在 `conda init` 之前**。

### 2. 创建 agent skill

```bash
mkdir -p /home/lgj/agent-skills/tmux-protocol
# 复制 SKILL.md 到这个目录（内容见下方 "SKILL.md 模板"）
```

### 3. 在 GEMINI.md 中添加规则

在 `~/.gemini/GEMINI.md` 添加 Section 11（详见下方 "GEMINI.md 模板"）。

### 4. 链接到工作目录

```bash
mkdir -p <workspace>/.agent/skills
ln -sfn /home/lgj/agent-skills/tmux-protocol <workspace>/.agent/skills/tmux-protocol
```

---

## PS1 Marker 通信协议详解

### 原理

```
AG_READY:0:$ ls -la                   ← 旧命令 exit 0 + 新命令输入
file1.txt  file2.txt
AG_READY:0:$                          ← ls 完成，exit 0
```

### 状态判断

| capture-pane 最后一行 | 状态 | 含义 |
|----------------------|------|------|
| `AG_READY:0:$` | **完成 ✅** | 命令成功，exit code 0 |
| `AG_READY:N:$` (N≠0) | **完成 ❌** | 命令失败，exit code N |
| 命令文本可见但无 `AG_READY` | **运行中** | 命令还没执行完 |
| 命令文本不可见 | **未送达** | send-keys 还没到达 pane |

### 为什么不需要 AG_START/AG_END 手动包裹？

我们最初设计了手动包裹方案（`echo AG_START; cmd; echo AG_END`），但发现模型在上下文压缩后**经常忘了包裹**，导致状态不可知。

PS1 版本把 marker 放在 shell prompt 里，**一次配置终身有效**，不依赖模型记忆。灵感来自 [TmuxAI](https://github.com/alvinunreal/tmuxai) 的 Prepare Mode。

---

## FAQ

### Q1: 为什么 `tmux send-keys` 总是返回 "Background command ID"？

**正常行为。** `send-keys` 只是往 pane 里注入按键，它本身不产生任何输出。AG 框架等不到输出，超时后标记为 background。Exit code 0 = 成功，直接继续。

### Q2: 模型看到 "Background" 就 kill session 重建，怎么办？

在 GEMINI.md 中明确写：

```markdown
**"Background command ID" is NORMAL BEHAVIOR, not an error.**
❌ NEVER kill or recreate a tmux session because you got a background ID.
```

注意用**正面陈述**（"这是正常的"）而不是**负面条件**（"如果你碰到了..."）。LLM 对正面陈述的遵从度更高。

### Q3: 为什么 flock 串行化方案行不通？

flock 让命令排队等锁 → 等待时间超过 `WaitMsBeforeAsync` → 触发更多 Background → 堆积更多 flock → 死锁放大。flock 解决的是 tmux 层的并行，但 AG 的问题在框架层，flock 反而加重了问题。

### Q4: `waitForPreviousTools=true` 是什么？为什么必须设？

AG 模型可以在一个 turn 里生成多个 tool call。默认并行执行。`waitForPreviousTools=true` 让 tool call 串行执行。不设的话，`send-keys` 和 `capture-pane` 可能同时发出 → capture 读到旧状态。

### Q5: 远程环境（SSH/VPN）下延迟很高，怎么办？

PS1 marker 协议自带状态感知：

- `AG_READY` 没出现 → 只是还在跑/网络延迟，不需要重试
- `AG_READY` 出现 → 完成了

通讯延迟和任务超时**可以区分**，不会误判。

### Q6: 模型在 fallback/错误恢复时绕过了 tmux，直接 `run_command`，怎么办？

这是最常见的违规场景。在 GEMINI.md 末尾加：

```markdown
### 🛡️ FALLBACK & RECOVERY DIRECTIVE
NEVER abandon the tmux protocol during error recovery.
ALL commands MUST continue to go through tmux send-keys.
There are NO exceptions for "quick fixes".
```

### Q7: 上下文压缩后模型忘了规则怎么办？

这是 AG 的固有限制，无法完全解决。对策：

1. 把最关键的规则**内联在 GEMINI.md 中**（不只是引用 SKILL.md）
2. 使用 ❌ 标记和粗体（压缩器倾向保留强调格式）
3. 保持对话简短（减少压缩频率）

### Q8: 能用 Claude Code / Codex CLI 代替 AG 的终端方案吗？

可以参考，但架构不同：

- Claude Code 有自己的 Remote Control（HTTPS proxy），不走 tmux
- Codex CLI 用沙箱执行，不涉及 PTY 管理
- AG 的 `run_command` 是框架级 API，不能替换

### Q9: 多个 conversation 同时跑会冲突吗？

不会。每个 conversation 用不同的 tmux session ID（UUID 前 8 位）。不同 session 之间完全隔离。

---

## 文件清单

| 文件 | 作用 |
|------|------|
| `~/.bashrc` | Agent 检测 + 哑终端模式 + PS1 marker |
| `~/.gemini/GEMINI.md` | Section 11：终端规则（内联，抗压缩） |
| `agent-skills/tmux-protocol/SKILL.md` | 完整协议文档 |
| `agent-skills/tmux-protocol/AG_TERMINAL_BEHAVIOR.md` | AG 行为参考（已验证的失败/成功方案） |

---

## 演进历史

| 日期 | 版本 | 变更 |
|------|------|------|
| 2026-03-02 | v1 | 基础 tmux 协议 + bashrc 哑终端 |
| 2026-03-05 AM | v2 | AG_START/AG_END 手动 marker |
| 2026-03-05 PM | v2.1 | flock 串行化（失败，已回滚） |
| 2026-03-05 PM | **v3** | **PS1 自动 marker（当前版本）** |
