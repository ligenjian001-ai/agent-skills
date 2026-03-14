# Jupyter Session — 持久化 Jupyter 内核会话

> 版本: 1.0.0 | 日期: 2026-03-15 | 作者: AG

## 问题

AG 在做数据分析时面临两个核心痛点：

1. **无状态执行**：每次 `python3 -c` 调用都是独立进程，无法保持变量、导入和数据状态。分析一个 CSV 需要在每次调用时重复加载数据。
2. **Jupyter MCP 不成熟**：Datalayer 的 `jupyter-mcp-server` 存在已知问题——图片输出（base64）会导致 AG 上下文溢出（[#200](https://github.com/datalayer/jupyter-mcp-server/issues/200)），错误处理也不完善（[#208](https://github.com/datalayer/jupyter-mcp-server/issues/208)）。

## 解决方案

绕过 MCP 层，直接通过 Jupyter Server REST API 与内核交互：

```
AG  →  jupyter_api.py (CLI, stdlib only)  →  Jupyter Server REST API  →  Python 内核
```

**关键设计选择**：

- **用户自管 Jupyter Server**：Server 作为长驻进程运行（tmux/systemd），技能只负责连接，不负责启停
- **jupyter-server-nbmodel 扩展**：提供 `POST /api/kernels/<id>/execute` 端点，支持服务端执行+轮询结果
- **零外部依赖**：`jupyter_api.py` 仅使用 Python 标准库（`urllib.request`, `json`, `argparse`）
- **自动截断输出**：默认 5000 字符上限，防止大 DataFrame 撑爆 AG 上下文
- **图片自动保存**：检测到 `image/png` 等 MIME 类型时，自动保存到 `/tmp/jupyter_plots/`，返回文件路径而非 base64

## 设计决策

### 为什么不用 Jupyter MCP？

| 维度 | MCP 方案 | REST API 方案（本技能） |
|------|----------|------------------------|
| 图片处理 | base64 内联，溢出 AG 上下文 | 自动存文件，返回路径 |
| 错误处理 | 异常未被正确捕获 | 完整的 traceback 格式化 |
| 依赖 | 需要 `jupyter-mcp-server` + 配置 | 仅 `jupyter-server-nbmodel`（~40KB） |
| 输出控制 | 无截断机制 | 可配置 `--max-output` |
| 成熟度 | 上游活跃开发中，API 不稳定 | REST API 稳定 |

### 为什么不管理 Server 生命周期？

Jupyter Server 是重量级进程（~150MB 基线内存），启停开销大。用户通常保持 Server 长期运行，技能不应干预其生命周期。这也避免了端口冲突、权限问题等复杂性。

### 为什么用轮询而非 WebSocket？

`jupyter-server-nbmodel` 的 execute 端点返回 202 + Location header，天然适合轮询模式。WebSocket 需要额外的连接管理和状态维护，增加 stdlib-only 约束下的实现复杂度。轮询的延迟（0.5s 间隔）对交互式分析完全可接受。

### 内核资源开销

| 状态 | 内存占用 |
|------|---------|
| 空闲 python3 内核 | ~55 MB RSS |
| 加载 pandas + 中型 DataFrame | ~200-400 MB |
| Jupyter Server 本身 | ~150 MB |

因此技能规则要求复用现有内核，避免无谓启动新内核。

## 技能设计哲学

1. **填补什么空缺？** — AG 缺少有状态的 Python 执行环境，且 Jupyter MCP 的图片溢出问题阻断了直接集成路径。
2. **什么会使它过时？** — 当 Jupyter MCP 修复图片溢出问题并提供输出截断机制时，可以考虑迁移回 MCP 方案。
3. **什么应该保留？** — 输出截断和图片文件化的模式应该保留，无论底层集成方式如何变化。

## FAQ

**Q: Server 重启后内核还在吗？**
A: 不在。内核状态纯内存，Server 重启后需要重新 `kernel start` 并重新加载数据。建议将数据加载步骤保存为 `.py` 文件，用 `execute-file` 快速恢复。

**Q: 可以同时运行多个内核吗？**
A: 可以，但每个空闲内核占 ~55MB。建议同时不超过 2-3 个活跃内核。

**Q: 图片保存在哪里？**
A: `/tmp/jupyter_plots/` 目录，文件名包含时间戳和内容哈希用于去重。该目录在系统重启后会清空。

**Q: 执行超时怎么办？**
A: 默认超时 120 秒，可通过 `--timeout` 调整。如果内核卡死，用 `kernel restart` 重启。

**Q: 支持 R、Julia 等其他语言吗？**
A: `kernel start --name ir` 或 `--name julia-1.9` 即可启动对应内核，前提是已安装对应 kernelspec。

## 演进历史

| 日期 | 版本 | 变更 |
|------|------|------|
| 2026-03-15 | 1.0.0 | 初始版本：REST API 方案，支持 kernel CRUD + execute + image 保存 |

## 文件清单

| 文件 | 用途 |
|------|------|
| `SKILL.md` | AG 运维指南（六段式标准） |
| `README.md` | 人类设计文档（本文件） |
| `scripts/jupyter_api.py` | CLI 包装器：status, kernel, execute, execute-file |
| `scripts/health_check.py` | 预检脚本：验证 Server 连通性和扩展安装 |
