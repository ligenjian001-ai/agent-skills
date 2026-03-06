# Jenkins Operations — 设计文档

> **版本**: v1.1 | **日期**: 2026-03-06 | **作者**: lgj team

---

## 为什么需要 Jenkins Skill？

这个 skill 解决两个核心问题：

### 1. LLM 长任务的超时困境

很多数据处理、构建、部署任务需要 5-60 分钟。LLM agent 执行这些任务时：

- AG 的 `run_command` 有 10 秒 `WaitMsBeforeAsync` 硬上限——长任务必定 background
- Agent 需要持续轮询、等待、可能遇到 context 压缩——状态容易丢失
- 失败后重跑需要人工判断（该从哪步重试？数据状态是否干净？）

**Jenkins 天然解决了这些问题**：

- 定时调度不受 agent session 限制
- 完整的构建日志和历史记录
- 可以手动重跑/参数化重跑
- 人可以随时查看中间过程和进度

### 2. Jenkins MCP 的不可用

尝试过使用 Jenkins MCP（Model Context Protocol）直接集成，但发现**缺失的指令太多**——无法满足实际的 job 管理需求。因此做了 `jenkins_ops.py` 作为统一接口。

---

## 为什么是 Docker + SSH-to-host？

Jenkins 在 Docker 容器中运行，但**所有实际工作通过 SSH 在宿主机上执行**。这个看似奇怪的架构有明确的理由：

### Docker 容器的问题

如果让 Jenkins 在容器内执行任务（安装 python、conda、rsync 等），每次容器重建后这些都需要重装。而且容器文件系统和宿主机隔离，无法直接访问数据文件。

### SSH-to-host 的优势

| 维度 | 容器内执行 | SSH-to-host |
|------|-----------|-------------|
| 环境一致性 | 容器重建后丢失 | ✅ 宿主机环境永久 |
| 访问数据 | 需要 volume mount | ✅ 直接访问 |
| Conda 环境 | 需要容器内安装 | ✅ 使用宿主机 conda |
| 容器体积 | 越来越大 | ✅ 容器保持最小 |

**Jenkins 容器只负责调度**（cron、触发、日志记录），`ssh user@localhost` 在宿主机上执行一切。

---

## Skill 设计哲学

> jenkins-ops 属于**"弥补工具不足 + 人机协同"**类 skill：
>
> 1. **弥补工具不足**：Jenkins MCP 指令不全，无法直接使用→自建 jenkins_ops.py
> 2. **人机协同**：长任务的重跑和中间过程跟进，很适合由人来参与判断（该重跑吗？从哪步重跑？数据状态对不对？），Jenkins 的 Web UI 让这种协作变得自然
>
> 如果未来 AG 支持原生长任务调度、或 Jenkins MCP 补全了缺失指令，这个 skill 可以相应调整或简化。

---

## FAQ

### Q1: 容器重建后 Jenkins 配置丢失了吗？

**不会。** Jenkins 数据目录通过 Docker volume mount 持久化。容器重建只丢失容器内安装的工具——而我们的架构里容器内不安装任何工具，所以没有损失。

### Q2: 为什么 pipeline 里 python3 找不到？

非交互 SSH 不加载 `~/.bashrc`，所以 conda 环境不会自动激活。在 pipeline 中使用完整路径：`/home/user/miniconda3/bin/python3`。

### Q3: 怎么调试 pipeline 失败？

1. `python3 scripts/jenkins_ops.py log <job-name>` — 查看控制台日志
2. 检查 SSH 是否能正常连接：`ssh -o BatchMode=yes user@localhost echo ok`
3. 确认脚本在宿主机上手动执行正常

### Q4: 为什么不直接用 AG 的 tmux 跑长任务？

AG 的 tmux 操作有固有限制（10s 超时、background 机制、context 压缩）。长任务需要的是：可靠调度 + 完整日志 + 人工干预能力。Jenkins 在这三方面都比 tmux直接跑更成熟。

---

## 演进历史

| 日期 | 版本 | 变更 |
|------|------|------|
| 2026-03-03 | v0.1 | 初始版本 — 基础 trigger/status/log 功能 |
| 2026-03-04 | v0.2 | 新增 Library 模式、ensure_project_jobs、folder 管理 |
| 2026-03-06 | v1.0 | SKILL.md 标准化、Anti-Patterns 补充 |
| 2026-03-06 | **v1.1** | 补充长任务超时问题、Jenkins MCP 不可用背景、人机协同设计理念 |

## 文件清单

| 文件 | 作用 |
|------|------|
| `SKILL.md` | Agent 操作指南 — Architecture、CLI、Pipeline Pattern |
| `README.md` | 人类文档 — 长任务问题、Docker+SSH 架构、设计哲学 |
| `scripts/jenkins_ops.py` | 统一 Jenkins 操作脚本（CLI + Library） |
