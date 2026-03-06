# Task Delegate — 设计文档

> **版本**: v1.0 | **日期**: 2026-03-06 | **作者**: lgj team

---

## 核心设计理念：AG 是 Copilot，后端 Agent 是施工团队

这个 skill 的设计出发点是一个关键发现：**AG 和执行后端的能力特长完全互补。**

| 能力 | AG (Antigravity) | 执行后端 (CC/Codex/Gemini/DeepSeek) |
|------|-------------------|--------------------------------------|
| 多模态理解 | ✅ 图片、视频、截图 | ❌ 纯文本 |
| Web 搜索 | ✅ search_web + read_url_content | ❌ 无网络 |
| Artifacts 讨论 | ✅ 结构化文档展示 | ❌ 无 |
| 与人类沟通 | ✅ 交互式、可视化 | ⚠️ CLI 模式 |
| 长任务执行 | ⚠️ run_command 有 10s 超时+background | ✅ 自有终端，无限制 |
| 大规模代码修改 | ⚠️ 每次编辑走 tool call 链路 | ✅ 直接读写文件系统 |

**分工原则**：

- **AG 做人类的 Copilot** — 理解需求、搜索资料、规划方案、review 结果、与人讨论
- **后端 Agent 做具体任务的施工者** — 写代码、跑测试、重构、多文件修改

---

## 设计决策

### 为什么整合 cc-delegate 和 multi-agent-exec？

| 之前 | 问题 |
|------|------|
| `cc-delegate` | 只支持 CC 一个后端 |
| `multi-agent-exec` | 已 DEPRECATED，但有好的多后端架构和 Langfuse 追踪 |
| `panel_launch.sh` | 又独立实现了一遍 executor dispatch |

**整合后**：一个 `task-delegate` skill，统一管理所有后端的委派、监控、验证和复盘。

### 为什么 IPC 放 ~/.task-delegate/ 而不是 /tmp/？

1. **持久化**：任务数据后续用于分析（复盘、成本追踪、prompt 改进）
2. **跨重启存活**：/tmp 重启后丢失
3. **集中管理**：所有任务记录一个地方，方便 `task_monitor.sh` 扫描

### 为什么保留 ag_dispatch.sh？

`task_launch.sh`（单任务委派）和 `ag_dispatch.sh`（多角色分发）是两个不同场景：

| 脚本 | 场景 | 特点 |
|------|------|------|
| `task_launch.sh` | 单任务：用户说"用 CC 写这个" | 创建 tmux session、runner 模式、stream 输出 |
| `ag_dispatch.sh` | 多角色：panel discussion、审计+修复 | 轻量 CLI wrapper、Langfuse 追踪、role-based |

### 后端选择准则

| 后端 | 强项 | 弱项 | 适用 |
|------|------|------|------|
| CC (Claude) | 多文件协调、subagent、长推理 | 速率限制 | 大型代码任务 |
| Codex | 沙箱安全、独立验证 | 权限需显式声明 | 验证、审计 |
| Gemini | 大 context、免费额度 | 代码质量不稳定 | 分析、轻任务 |
| DeepSeek | 低成本、快速 | API 模式（无文件访问） | 文本分析、翻译 |

---

## FAQ

### Q1: 后端执行时 AG 能做什么？

AG 可以做其他非终端工作（编写文档、分析代码、回答问题），也可以等待。后端在独立 tmux session 中运行，不占用 AG 的 session。

### Q2: 怎么判断任务应该 AG 自己做还是委派？

| 条件 | 决策 |
|------|------|
| 单文件修改、简单重构 | AG 自己做 |
| 多文件、30min+、需要频繁编译测试 | 委派后端 |
| 用户明确指定后端 | 委派 |
| AG 的 tmux 操作反复 background | 考虑委派 |

### Q3: DeepSeek 和 CLI 后端有什么区别？

DeepSeek 是纯 HTTP API 调用（无法访问本地文件系统），适合文本分析、翻译等不需要文件操作的任务。CC/Codex/Gemini 是 CLI 工具，可以直接读写文件。

---

## 演进历史

| 日期 | 版本 | 变更 |
|------|------|------|
| 2026-03-04 | — | `cc-delegate` v0.1 从 multi-agent-exec 拆分 |
| 2026-03-06 | — | `cc-delegate` v1.1 完善 Copilot/Builder 理念 |
| 2026-03-06 | **v1.0** | 整合 `cc-delegate` + `multi-agent-exec` → `task-delegate`，支持 cc/codex/gemini/deepseek，IPC 持久化至 `~/.task-delegate/` |

## 文件清单

| 文件 | 作用 |
|------|------|
| `SKILL.md` | Agent 操作指南 — 4 步委派 + 多后端选择 + 运行时监控 |
| `README.md` | 人类文档 — Copilot/Builder 分工理念、设计决策、FAQ |
| `scripts/task_launch.sh` | 统一启动器（tmux session + runner + 多后端） |
| `scripts/task_monitor.sh` | 任务状态监控（列表 + 详情） |
| `scripts/ag_dispatch.sh` | 多角色 CLI 分发器（for panel discussion 等） |
| `scripts/ag_trace.py` | Langfuse 异步追踪（fire-and-forget） |
| `scripts/ag_retro.py` | 复盘分析报告 |
