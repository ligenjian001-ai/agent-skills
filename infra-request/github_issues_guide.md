# GitHub Issues Infra Request 指南

## 背景

当你在研究或操作中发现缺陷、功能缺失或工具需求时，通过 **GitHub Issues** 向 Antigravity（基础设施 agent）提报 infra request。

**所有项目统一提交到 `$GITHUB_ISSUES_REPO`**（默认 `ligenjian001-ai/hft-sdk-issues`），通过 **project label** 区分项目来源。

## 配置

确认 `~/.hft/credentials.env` 包含：

```bash
GITHUB_ISSUES_REPO=ligenjian001-ai/hft-sdk-issues
```

`GITHUB_AGENT_NAME` 应设为当前项目名（如 `lgj_strategy_zoo`、`hft_build`、`agent-skills` 等），用于标记 issue 来源。

## 核心命令

```bash
# 发起 infra request（必须加 project label）
playground issues post "<标题>" "<正文>" --label <类型> --label <优先级> --label project:<project>

# 查看所有 open issues
playground issues list

# 查看待处理的 (等 Antigravity 评估)
playground issues triage

# 读取某个 issue 完整对话
playground issues read <issue_number>

# 回复 (补充信息/确认/验证)
playground issues reply <issue_number> "<内容>"

# 修改状态
playground issues status <issue_number> <状态>

# 关闭
playground issues close <issue_number>
```

## 项目标签（MANDATORY）

**每个 issue 必须打 `project:<name>` label**：

| Label | 项目 | 典型 issue 类型 |
|-------|------|-----------------|
| `project:hft_build` | HFT SDK 基建 | SDK 工具、数据管道、策略基建 |
| `project:workstation-ops` | 工作站运维 | 环境配置、依赖管理、系统服务 |
| `project:data` | 数据基建（预留） | 数据源、ETL、存储 |

用户后续可能将 issue 分发到不同 repo，project label 是路由依据。

## 提报模板

### 标题规范

- `[INFRA] xxx` — SDK 基础设施需求 (对应 `--label infra`)
- `[BUG] xxx` — Bug 报告 (对应 `--label bug`)
- `[FEATURE] xxx` — 新功能 (对应 `--label feature`)
- `[OPS] xxx` — 工作站运维/环境配置 (对应 `--label ops`)

### 正文模板

每个 infra request 的正文**必须**包含以下结构：

```markdown
## What I Need

{一句话描述需要的工具/能力}

### Deliverable 1: {工具名} (P0/P1/P2)

**What**: `{path/to/tool}` - {描述}

**Usage**:
\`\`\`bash
{命令行调用示例}
\`\`\`

**What it should do**:
1. {行为描述}
2. {输入输出}

### Deliverable 2: ... (如有多个交付物)

## Why I Need This

**Immediate blocker**: {什么流程被阻塞}
**Impact**: {如何影响日常操作}

## Environment Context (workstation-ops / 环境配置类)

> 仅当 issue 涉及机器环境、依赖安装、系统配置时需要填写。

**Target Machine**: {hostname / IP / "all workstations"}
**OS**: {Ubuntu 22.04 / CentOS 8 / etc.}
**Dependencies**: {需要安装的包/工具列表}
**Config Files**: {涉及的配置文件路径}
**Rollback Plan**: {配置失败时的回滚方案}

## Current Behavior (Bug only)

{Bug 报告：当前的错误行为，包含复现步骤}

## Expected Behavior

{期望的正确行为}

## Files Involved

- {涉及的文件路径}

## Verification Criteria

| # | Test Case | Expected Result | Tolerance |
|---|-----------|-----------------|-----------|
| 1 | {具体测试} | {预期输出} | {容差} |

## Success Definition

- [ ] {可执行的验收条件 1}
- [ ] {可执行的验收条件 2}
```

### 完整示例

```bash
playground issues post "[INFRA] 需要 playground eod-report 一键复盘命令" \
"## What I Need

一键完成交易日复盘：数据同步 → 指标计算 → 报告生成。

### Deliverable 1: \`playground eod-report\` 命令 (P0)

**What**: playground CLI 子命令，串联现有脚本

**Usage**:
\`\`\`bash
playground eod-report --date 20260213
playground eod-report --date 20260213 --skip-sync --json
\`\`\`

**What it should do**:
1. 调用 \`sync_eod_data.sh\` 同步交易服务器数据
2. 调用 \`metrics_lib\` 计算策略指标
3. 生成 Markdown + JSON 报告

### Deliverable 2: EOD Report Python API (P1)

**What**: \`sdk_tools.api\` 中添加 \`eod_report.generate()\`

## Why I Need This

**Immediate blocker**: 每日 EOD 复盘耗时 10-15 分钟，应该 30 秒完成
**Impact**: Agent 无法自动发现和执行这个流程

## Files Involved

- sdk_tools/bin/daily_report.py
- sdk_tools/lib/metrics_lib.py
- scripts/eod/sync_eod_data.sh

## Verification Criteria

| # | Test Case | Expected Result | Tolerance |
|---|-----------|-----------------|-----------|
| 1 | \`playground eod-report --date 20260213\` | 生成 MD + JSON 报告 | - |
| 2 | ScoreMaker PnL | ≈ ¥-108 | ±5% |
| 3 | \`--skip-sync\` 跳过同步 | 直接生成报告 | - |

## Success Definition

- [ ] 命令可一键执行，<60秒完成
- [ ] 报告包含策略概览 + 逐品种 PnL + EOD 持仓
- [ ] Python API 可在脚本中 programmatic 调用" \
--label infra --label P1
```

## 状态流转与协作

```
你提交 Issue (needs-triage)
    ↓
Antigravity 评估可行性、提问 (needs-triage → confirmed)
    ↓
你回复补充信息、确认需求
    ↓
用户 (_intelLigenJ) 在 GitHub 审批
    ↓
Antigravity 实现 (confirmed → in-progress → resolved)
    ↓
你验证交付物 (resolved)
    ↓
验证通过 → 关闭 Issue
```

### 你在各阶段的操作

| 阶段 | 你做什么 |
|------|---------|
| 提交后 | 等待，定期 `playground issues triage` 检查 |
| Antigravity 提问 | `playground issues read N` 然后 `reply` 补充信息 |
| 实现完成 (resolved) | 验证交付物，通过则 `close`，不通过则 `reply` 反馈 |

### 验证标准

**BEFORE claiming verified, MUST**:

1. 多 code 测试 (≥3 个代码)
2. 多日期测试 (≥2 天)
3. 对比 expected vs actual 数值
4. 报告覆盖率: "Verified: X/Y codes, Z/W dates"

## 优先级标签

| Label | 含义 |
|-------|------|
| `P0` | 阻塞当前工作，需立即处理 |
| `P1` | 影响效率，有 workaround |
| `P2` | 改进项，不紧急 |

## 注意事项

1. **每个需求一个 Issue** — 不合并不相关需求
2. **Request → Tool** — 每个 request 必须产出可执行工具，禁止纯文档需求
3. **提供复现信息** — Bug 必须包含复现命令和预期 vs 实际行为
4. **引用文件路径** — 帮助 Antigravity 快速定位代码
5. **Labels 自动管理** — 提交自动加 `needs-triage` + `agent:<项目名>`
