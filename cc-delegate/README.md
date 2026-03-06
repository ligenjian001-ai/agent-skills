# Claude Code Delegation — 设计文档

> **版本**: v1.1 | **日期**: 2026-03-06 | **作者**: lgj team

---

## 核心设计理念：AG 是 Copilot，CC 是施工团队

这个 skill 的设计出发点是一个关键发现：**AG 和 CC 的能力特长完全互补。**

| 能力 | AG (Antigravity) | CC (Claude Code) |
|------|-------------------|-------------------|
| 多模态理解 | ✅ 图片、视频、截图 | ❌ 纯文本 |
| Web 搜索 | ✅ search_web + read_url_content | ❌ 无网络 |
| Artifacts 讨论 | ✅ 结构化文档展示 | ❌ 无 |
| 与人类沟通 | ✅ 交互式、可视化 | ⚠️ CLI 模式 |
| Subagent 编排 | ❌ 无原生 Task 工具 | ✅ 内嵌 Task subagent |
| 多 Agent 协作 | ❌ 需要 tmux 手动编排 | ✅ 原生并行 Task |
| 长任务执行 | ⚠️ run_command 有 10s 超时+background | ✅ 自有终端，无限制 |
| 大规模代码修改 | ⚠️ 每次编辑走 tool call 链路 | ✅ 直接读写文件系统 |

**分工原则**：

- **AG 做人类的 Copilot** — 理解需求、搜索资料、规划方案、review 结果、与人讨论
- **CC 做具体任务的施工者** — 写代码、跑测试、重构、多文件修改

这不是简单的"AG 不行所以交给 CC"，而是让每个工具做它最擅长的事。

---

## 设计决策

### 为什么 prompt.txt 是独立文件？

1. **tmux 安全**：长 prompt 通过 send-keys 传会触发 heredoc hang（tmux-protocol 反模式）
2. **完整记录**：prompt 文件留在 `/tmp/cc_tasks/{task_id}/` 里，可回溯、可改进
3. **CC 原生支持**：`claude -p < prompt.txt` 天然支持文件输入

### 为什么用 bypassPermissions？

CC 默认每次修改文件/执行命令都会弹审批框。在无人值守的委派场景中，这等于永远卡住。`bypassPermissions` 让 CC 自主完成所有操作。

**安全通过 prompt 约束保证**——在 prompt.txt 的 `## Constraints` 里明确列出不可修改的文件/模块。

### Max vs API：什么时候用哪个？

| 模式 | 费用 | 限制 | 适用场景 |
|------|------|------|---------|
| Max（订阅） | 月费固定 | 有速率限制 | 日常开发任务 |
| API（按量） | $0.003-0.015/1K tokens | 需设 budget | 批量任务、超大上下文 |

**决策**：默认用 Max（无额外费用），只在 Max 被 rate limit 时考虑 API。launch 脚本中 Max 模式不加 `--max-budget-usd` 避免误杀。

### 为什么 AG 必须 review CC 的输出？

**CC 的准确率大约 70-85%。** 常见问题：

- 修改了不该改的文件
- 路径用错（用容器路径而非宿主机路径）
- 自测声称 pass 但实际有 edge case 失败

AG 的 Step 4 验证是必须的，不是可选的。这也体现了分工——CC 施工，AG review。

---

## Skill 设计哲学

> cc-delegate 属于**"适配能力互补"**类 skill——它不是因为 AG 不行才委派给 CC，而是识别到 AG 和 CC 各自的能力特长后，设计了一套让两者协同工作的模式。
>
> AG 的强项是多模态、搜索、与人对话——这让它天然适合做人类的 Copilot。
> CC 的强项是 subagent 编排、长任务自主执行——这让它天然适合做施工团队。
>
> 如果 AG 未来获得原生 subagent 能力和无限制终端访问，这个 skill 的 delegation 部分可能需要调整。
> 但 AG-as-copilot + CC-as-builder 的模式仍然可能是最优分工。

---

## FAQ

### Q1: CC 执行时 AG 能做什么？

**AG 可以做其他非终端工作**（编写文档、分析代码、回答问题），也可以等待。CC 在独立 tmux session 中运行，不占用 AG 的 session。

### Q2: CC 执行失败怎么办？

查看 `live.log` 和 `execution_record.json` 定位问题，改进 prompt，重新 dispatch。通常是 prompt 不够具体导致的。

### Q3: 怎么判断任务应该 AG 自己做还是委派？

| 条件 | 决策 |
|------|------|
| 单文件修改、简单重构 | AG 自己做 |
| 多文件、30min+、需要频繁编译测试 | 委派 CC |
| 用户明确说"用 CC" | 委派 CC |
| AG 的 tmux 操作反复 background | 考虑委派 |

---

## 演进历史

| 日期 | 版本 | 变更 |
|------|------|------|
| 2026-03-04 | v0.1 | 从 multi-agent-exec 拆分出单独 CC 委派 skill |
| 2026-03-05 | v0.2 | 新增 cc_launch.sh + cc_monitor.sh 脚本 |
| 2026-03-06 | v1.0 | Max vs API 区分、完整 SKILL.md 标准化 |
| 2026-03-06 | **v1.1** | 明确 AG=Copilot / CC=Builder 的分工理念、补充设计哲学 |

## 文件清单

| 文件 | 作用 |
|------|------|
| `SKILL.md` | Agent 操作指南 — 4 步委派流程 |
| `README.md` | 人类文档 — Copilot/Builder 分工理念、设计决策、FAQ |
| `scripts/cc_launch.sh` | CC 启动脚本（tmux session + streaming） |
| `scripts/cc_monitor.sh` | CC 状态监控脚本 |
