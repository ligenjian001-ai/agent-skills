# 系统设计 — 多视角架构技能

> **版本**: 1.1 | **更新**: 2026-03-12 | **作者**: AG

## 解决的问题

设计非平凡系统时，单一视角会产生盲点：

- **纯架构师** 过度抽象，脱离实际代码
- **纯实用主义者** 只做补丁式修改，缺乏长远设计
- **纯研究者** 追逐新工具，不考虑项目约束

AG 需要一种结构化方式来**生成多元观点、收敛融合、验证假设、产出可执行的 infra request** — 而不是留在文件夹里的设计文档。

## 解决方案

4 阶段流程，每个阶段都有用户确认门：

```
SKETCH → [用户 ✓] → DECIDE → [用户 ✓] → SPIKE → [用户 ✓] → BLUEPRINT
```

1. **SKETCH**: 3 个独立 agent（架构师/CC、务实者/Codex、探索者/Gemini）各自产出设计方案
2. **DECIDE**: AG 融合最佳元素，写出 `unified_design.md`
3. **SPIKE**: PoC 实验验证高风险假设
4. **BLUEPRINT**: 可执行的路线图 + infra request 提交为 GitHub Issue

## 技能存在哲学

### 填补了什么空白？

AG 单独工作时倾向于产出一个"最显然"的设计。通过强制 3 个独立视角（来自不同后端 CC/Codex/Gemini），这个技能从结构上防止隧道视野。用户确认门防止设计在没有反馈的情况下跑偏。

### 什么时候可以退役？

如果 AG 底层模型能够原生持有多个矛盾观点并以 3 个独立 agent 的严谨度自我论证，SKETCH 阶段可以简化。如果 GitHub Actions 原生编排 agent 会话，task-delegate 集成也不再必要。

### 退役后什么应该保留？

- **门控流程模式**（SKETCH → DECIDE → SPIKE → BLUEPRINT）
- **Infra request 提交标准**（issue body = 摘要，comment = 完整设计）
- **Label 安全协议**（`gh label create` 先于 `gh issue create --label`）

## 设计决策

### 为什么 3 个 agent，不是 2 个或 5 个？

三个提供了最小可行多样性（架构、代码实操、外部研究），又不会爆炸成本。两个只有一个对比维度；五个增加噪声但洞察收益不成比例。

### 为什么 CC 做架构、Codex 做实操？

- **CC Max**（Claude Code）擅长长篇推理和架构设计
- **Codex** 擅长代码落地分析 — 它天然会检查现有文件
- **Gemini** 擅长网络研究和外部工具发现

### 为什么每个阶段都要用户确认？

没有门控，AG 倾向于带着未验证假设一路冲到 BLUEPRINT。Phase 0 测试证实：用户审查设计很快（< 5 min），但能抓住 AG 遗漏的关键问题。

### 为什么用 GitHub Issue 作为输出格式？

Infra request 以 GitHub Issue 形式提交的好处：
- 异步审查（用户手机上扫一眼）
- 可关联 PR（agent-pipeline 自动认领）
- 评论线程用于设计讨论
- Label 状态机驱动自动化

## 失败的尝试

### 把完整设计文档塞进 issue body

**做法**: 500+ 行设计文档直接作为 issue body。

**为什么失败**: GitHub 在 body > 10KB 时渲染变慢，issue 列表预览也变得不可读。

**解决**: Issue body 写精简摘要；完整设计文档通过 `--body-file` 作为 follow-up comment 附加。

### 不检查 label 直接使用 `--label`

**做法**: `gh issue create --label "ready"` 假设 label 已存在。

**为什么失败**: `gh` 即使 label 不存在也返回 exit code 0 — issue 被创建但不带 label，只打印一行容易被忽略的警告。这在 Phase 0 自动化流程中导致了静默失败。

**解决**: 提交前先 `gh label list | grep` 或 `gh label create`。

### AG brain 目录作为 `--body-file` 源

**做法**: `gh issue comment --body-file /path/to/.gemini/antigravity/brain/.../file.md`

**为什么失败**: AG brain 目录有特殊权限限制。tmux shell（以 user 身份运行）可以 `ls` 但无法 `cat` 或传给 `gh`。

**解决**: 先 `cp` 到 `~/` 或 `/tmp/`，再 `--body-file`，完成后清理临时文件。

## FAQ

**Q: 如果我已经知道要怎么设计，可以跳过 SKETCH 吗？**

可以。直接写 `unified_design.md` 跳到 Phase 2（DECIDE），让 AG 识别哪些假设需要 spike 验证。多视角 sketch 在方案空间开放时最有价值。

**Q: 3 个 sketch agent 一定要用不同后端吗？**

不强制，但推荐。不同后端确实有不同的强项（CC 推理、Codex 代码分析、Gemini 网络研究）。用同一后端跑 3 次，视角多样性会打折。

**Q: Spike 失败了怎么办？**

Spike 失败是正常结果，不是错误。如果失败的是核心假设 → 回到 SKETCH 重新设计。如果是外围假设 → 局部调整设计，继续推进。

**Q: 这个技能和 agent-pipeline 怎么配合？**

BLUEPRINT 产出的 infra request 变成 GitHub Issue。如果 agent-pipeline 守护进程在运行，它会自动认领带 `ready` label 的 issue 并派 CC Max 实现。完整闭环：system-design 产出 issue → agent-pipeline 实现 → 用户 review PR。

## 版本历史

| 日期 | 版本 | 变更 |
|------|------|------|
| 2026-03-11 | 1.0 | 初始创建，4 阶段多视角工作流 |
| 2026-03-12 | 1.1 | 路径可移植化（`~/`）、BLUEPRINT infra request 标准、Lessons Learned |

## 文件索引

| 文件 | 用途 |
|------|------|
| `SKILL.md` | Agent 操作指南 — 工作流步骤、规则、反模式（英文） |
| `README.md` | 人类文档 — 设计决策、失败尝试、FAQ（中文） |
| `prompts/sketch_architect.txt` | 架构师 agent 的 prompt 模板（CC 后端） |
| `prompts/sketch_realist.txt` | 务实者 agent 的 prompt 模板（Codex 后端） |
| `prompts/sketch_explorer.txt` | 探索者 agent 的 prompt 模板（Gemini 后端） |
