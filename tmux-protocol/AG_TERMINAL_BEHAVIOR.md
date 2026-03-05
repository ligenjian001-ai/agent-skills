# AG Terminal Behavior — Definitive Reference

> Last updated: 2026-03-05
> Source: empirical testing + CC research + community reports + AG system prompt analysis

---

## 1. `run_command` 工具参数

| Parameter | Type | Range | Behavior |
|-----------|------|-------|----------|
| `CommandLine` | string | — | 要执行的命令 |
| `Cwd` | string | — | 工作目录 |
| `SafeToAutoRun` | bool | — | true = 不弹审批框 |
| `WaitMsBeforeAsync` | int | **0–10000** | **硬上限 10 秒，不可配置** |
| `waitForPreviousTools` | bool | — | 等待前一个 tool call 完成。**可选参数，默认 false** |

> [!CAUTION]
> `waitForPreviousTools` 是**可选参数，默认 false**。模型必须在每次调用时显式设为 true。
> 没有全局开关、没有项目级配置、没有框架级强制。这是所有终端问题的根源。

---

## 2. Background 机制（核心问题）

```
run_command("some_cmd", WaitMsBeforeAsync=3000)
  │
  ├─ 3000ms 内有输出 → 返回输出给模型 ✅
  │
  └─ 3000ms 内无输出 → 框架判定"命令未完成"
       ├─ 将进程放入 background
       ├─ 返回 "Background command ID: xxx"
       └─ 模型拿到 ID 后可以用 command_status 查询
          但模型通常忽略 ID，直接发下一个命令 → 堆积 → 死锁
```

**关键事实**：

- Background 后，底层进程**仍在运行**
- 模型收到 Background ID 后，如果发新命令，两个命令**并行执行**
- 对于 tmux 操作：`send-keys` 几乎无 stdout → 短 WaitMs 必然 background
- `capture-pane` 有 stdout 但如果排队等锁也会被 background

---

## 3. 并行调用机制

当模型在一个 turn 中生成多个 tool call 时：

```
# waitForPreviousTools=false（默认）：
tool_call_1 ──启动──┐
tool_call_2 ──启动──┤  并行执行
tool_call_3 ──启动──┘

# waitForPreviousTools=true：
tool_call_1 ──启动── 完成 → tool_call_2 ──启动── 完成 → tool_call_3
```

**唯一的串行化手段就是 `waitForPreviousTools=true`**。没有其他方式。

---

## 4. 已验证的失败方案

| 方案 | 为什么失败 |
|------|-----------|
| **flock 串行化 wrapper** | flock 排队等锁 → 等待时间超过 WaitMsBeforeAsync → 触发 Background → 堆积更多 flock → 死锁放大器 |
| **增加 WaitMsBeforeAsync** | 硬上限 10000ms，无法增加。对长命令无用 |
| **全局设 waitForPreviousTools** | 不存在此配置项 |
| **PATH 别名 tmux → wrapper** | AG 可能直接用 `/usr/bin/tmux` 绕过 |
| **command_status 轮询** | 多个报告称此工具不可靠 |
| **read_terminal** | 协议已禁止使用，更不可靠 |

---

## 5. 已验证的有效措施

| 措施 | 效果 | 可靠度 |
|------|------|--------|
| **AG_START/AG_END marker 协议** | capture-pane 自感知状态（PENDING/RUNNING/DONE），不依赖 waitForPreviousTools 的时序保证 | **高**（协议级自同步） |
| **~/.bashrc 哑终端模式** | 跳过 conda/completion/color，防输出解析器中毒 | **100%**（OS 级，不依赖模型） |
| **GEMINI.md inline 规则 + ❌ 标记** | 提高规则在上下文压缩后存活概率 | ~70%（仍可能被压缩掉） |
| **SKILL.md 详细协议** | 提供完整参考 | ~60%（模型可能不读或忘记） |
| **短对话** | 减少上下文压缩频率 | 有效（但限制了任务复杂度） |
| **脚本模式**（write_to_file → bash script.sh） | 减少 tmux 交互次数 | 有效（但模型可能不用） |

---

## 6. 上下文压缩与规则遗忘

AG 使用上下文压缩（context compaction）来管理长对话：

- 当 token 数接近上限时，框架**自动压缩**对话历史
- 压缩器将早期对话总结为摘要
- **GEMINI.md 内容在压缩后仍存在**（作为 system prompt 注入）
- **但 SKILL.md 内容不一定存在**——它是通过 `view_file` 读取的对话内容，会被压缩
- 规则引用（如"去读 SKILL.md"）在压缩后变成模糊的摘要（如"使用 tmux 协议"）

**对策**：把最关键的规则**直接写在 GEMINI.md 里**，而不是引用外部文件。

---

## 7. 多 Conversation 并发

- 每个 conversation 有独立的 artifact 目录（`brain/{uuid}/`）
- 每个 conversation 创建自己的 tmux session（session ID = UUID 前 8 位 hex）
- **tmux session 级别是隔离的**——不同 conversation 不共享 pane
- **但 `$ANTIGRAVITY_AGENT` 环境变量在所有 conversation 间共享**（继承自 AG 进程）
- **框架的 `run_command` 不区分 conversation**——所有 conversation 的命令在同一个 shell 进程池中执行

---

## 8. 终端环境

AG 进程设置的环境变量（所有 tmux session 继承）：

| 变量 | 值 | 效果 |
|------|-----|------|
| `ANTIGRAVITY_AGENT` | `1` | ~/.bashrc 用来检测 agent 上下文 |
| `TERM_PROGRAM` | `tmux`（在 tmux 内） | — |
| `PAGER` | `cat` | 防止 less/more 阻塞 |

---

## 9. 不可改变的约束（平台限制）

1. `WaitMsBeforeAsync` **硬上限 10 秒**
2. `waitForPreviousTools` **没有全局默认值**
3. Background 机制**不可禁用**
4. 模型行为**本质不确定**——所有软规则只是提高概率，不能保证
5. 上下文压缩**不可控**——何时压缩、保留什么由框架决定

---

## 10. 远程开发环境的影响

AG 运行在远程 Linux 工作站上，用户从本地 Mac 通过网络连接。这意味着：

```
WaitMsBeforeAsync = 3000ms 的实际分配：
  网络往返延迟（Mac ↔ 远程机）: 50-500ms（正常）/ 1000ms+（网络抖动）
  AG 框架内部开销: 100-200ms
  实际留给命令执行: 2300-2850ms（正常）/ <2000ms（抖动时）
```

**网络卡顿 vs 任务超时**：在 `run_command` 的返回里，这两者**完全无法区分**——都是 "Background command ID"。

**Marker 协议解决了这个区分问题**：

- `capture-pane` 没看到 `AG_START` → **通讯层延迟**（send-keys 还没送达）
- `capture-pane` 看到 `AG_START` 没看到 `AG_END` → **任务层延迟**（命令在跑）

这让模型能做出正确的判断：通讯问题不需要重试任务，任务问题不需要重建通讯。
