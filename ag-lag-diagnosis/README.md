# AG IDE Lag 诊断 — 设计文档

> **版本**: v1.1 | **日期**: 2026-03-06 | **作者**: lgj team

---

## 问题的发现过程

AG IDE 在使用 Agent Manager 监控多个对话时，频繁出现以下症状：

1. 编辑操作显示「Working...」后永远不完成
2. Agent Manager 页面完全冻结，切回 Editor 页面则恢复正常
3. IDE 运行 18 小时后系统内存占用持续增长

通过分析 AG 的日志目录（`~/Library/Application Support/Antigravity/logs/`），逐步定位到了 4 层根因。

---

## 重要约束：仅限 macOS 端

> [!CAUTION]
> **此 skill 的诊断步骤只能在 macOS（AG IDE 运行的机器）上执行。**
> 远程服务器上无法获取完整的 AG IDE 日志（`agent-window-console.log`、`rendererPerf.log` 等）。
> 只有 Step 4（检查 .pb 文件大小）需要 SSH 到远程工作站。

AG 是桌面应用，日志在本地 macOS：`~/Library/Application Support/Antigravity/logs/`
工作空间和对话数据（.pb 文件）在远程 Linux 工作站：`~/.gemini/antigravity/conversations/`

诊断需要**同时检查两端**——这也是为什么这个 skill 比较特殊，无法完全自动化。

---

## 根因分析链

```
.pb 文件 >4MB
    ↓
gRPC 超过消息大小限制 → 传输失败
    ↓
streamAgentStateUpdates 重试（每 2s，无 backoff）
    ↓
前端事件循环被 polling 请求淹没
    ↓
"VERY LONG TASK" → UI 冻结
    ↓
Renderer 进程内存泄漏（18h+ 后 >1GB）
    ↓
GC 暂停叠加 → 多秒级卡顿
```

关键发现：**4 层问题同时存在时是乘法效应，不是加法。**

---

## 设计决策

### 为什么诊断步骤按这个顺序？

**按影响力排序，而非排查便利性排序。**

| 步骤 | 查的是什么 | 为什么放这个位置 |
|------|-----------|----------------|
| Step 1 | 日志目录（macOS） | 前置依赖——后续步骤都需要 `$AG_LOG` |
| Step 2 | polling storm（macOS） | #1 首要原因，几乎总是存在 |
| Step 3 | renderer blocking（macOS） | 与 polling 联动，确认 UI 影响 |
| Step 4 | .pb 文件大小（**远程服务器**） | 根因，需要 SSH 到工作站 |
| Step 5 | 进程资源（macOS） | 综合指标，确认严重程度 |

### 为什么 Fix 1 是 archive 而非 restart？

重启 AG 只清除内存中的 orphan 订阅，但 >4MB 的 .pb 文件仍在。下次 Agent Manager 轮询到这些对话时，polling storm 立即重新触发。**不移除根因，Fix 2 的效果只能维持几小时。**

### 为什么用 archive 目录而非删除？

用户可能需要恢复历史对话。`conversations_archive/` 保留了这个选项。磁盘空间通常不是瓶颈（.pb 文件一般 5-20MB）。

---

## FAQ

### Q1: 为什么 streamAgentStateUpdates 没有指数退避（exponential backoff）？

**这是 AG 框架的 bug，不是设计选择。** 正常的重试逻辑应该有 backoff，但当前实现是固定 ~2s 间隔重试，导致一个失败的对话就能产生每分钟 30 次的轮询。

### Q2: 远程服务器上能诊断吗？

**不完全能。** 远程服务器只有 .pb 文件（Step 4），没有 AG IDE 的日志（Steps 1-3, 5）。必须在 macOS 端运行完整诊断。

### Q3: GPU rasterization 有风险吗？

**大致安全。** Chromium-based 应用（VS Code、AG 都是）普遍支持 GPU 加速。在 macOS + Apple Silicon 上效果明显。如有渲染异常，删除 `argv.json` 中的配置即可恢复。

### Q4: 能自动化预防吗？

可以设置 cron job 或 Jenkins 定时任务来 archive >4MB 的 .pb 文件。但 archive 后必须重启 AG IDE，且诊断日志只在 macOS 本地——这让完全自动化不太现实。目前建议手动执行。

---

## 演进历史

| 日期 | 版本 | 变更 |
|------|------|------|
| 2026-03-06 | v1.0 | 初始版本 — 5 步诊断 + 5 级修复 + 4 层根因分析 |
| 2026-03-06 | **v1.1** | 明确 macOS-only 约束、补充双端诊断说明 |

## 文件清单

| 文件 | 作用 |
|------|------|
| `SKILL.md` | Agent 操作指南 — 5 步诊断流程 + 修复方案 |
| `README.md` | 人类文档 — 根因分析链、macOS 约束、FAQ |
| `scripts/archive_large_conversations.sh` | 自动 archive >4MB .pb 文件的脚本 |
