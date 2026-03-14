---
name: product-maturity-audit
description: "Shell-based product maturity checklist for strategy platform SDKs. Runs concrete commands with binary PASS/FAIL outcomes. Designed to avoid the bootstrapping paradox of Python-based checkers."
---

# Product Maturity Audit

> [!IMPORTANT]
> 这是一个**通用框架 skill**。项目特定的检查清单放在项目内的
> `.agent/maturity-checks.md` 中，本 skill 定义的是检查的结构、执行方式和输出格式。

## Design Philosophy

每条 maturity check 必须满足：
1. **一条 shell 命令**（`python -c "..."` 或 `bash -c "..."`）
2. **Exit code 0 = PASS, non-zero = FAIL**
3. **FAIL 信息包含用户可执行的修复建议**
4. **不 import 项目模块做检查逻辑** → 用 `python -c` 从外部测试（避免 bootstrapping 悖论）

### 为什么不用 Python 框架？

`agent-native-product` 失败的根因：Python checker 需要 import 被检项目 → 项目坏了 checker 也坏 → 无法区分"检查发现问题"和"检查工具自身崩溃"。Shell 命令从外部测试，完全避免这个问题。

## When to Trigger

- 项目声称"可以给别人用"时
- 重大重构后验证产品完整性
- 新用户入驻前的 pre-flight check
- 定期健康检查（CI/Jenkins 注册）
- 触发词：`审计产品成熟度`, `maturity audit`, `product check`

## Check Layers（通用框架）

每个项目的 `.agent/maturity-checks.md` 应按以下 5 层组织检查：

| Layer | 检查目标 | 示例 |
|-------|---------|------|
| **L1: Install** | 能不能装？能不能 import？ | `pip install -e .`, core module imports |
| **L2: Data** | 数据环境是否就绪？ | 数据目录存在？至少有一个可用数据集？ |
| **L3: Execution** | 核心工作流跑不跑得通？ | 端到端 backtest/serve/predict 能否成功？ |
| **L4: Quality** | 代码质量门控 | 测试通过？无硬编码路径？ |
| **L5: Docs** | Agent 能不能理解？ | CLAUDE.md 存在且包含必要章节？例子能编译？ |

## 项目端检查清单格式

在项目的 `.agent/maturity-checks.md` 中，按如下格式定义检查：

````markdown
# Maturity Checks: {项目名}

## L1: Install

```bash
# CHECK 1: {检查名称}
{shell 命令}
```

```bash
# CHECK 2: {检查名称}
{shell 命令}
```

## L2: Data
...
````

**每条检查的约束**:
- 命令必须在项目根目录下可执行
- PASS 时 stdout 包含 `PASS: {description}`
- FAIL 时 stdout 包含 `FAIL: {description}` 并以 non-zero 退出
- FAIL 信息必须告诉用户**怎么修**，不只是"坏了"

## Agent 执行流程

1. 读项目的 `.agent/maturity-checks.md`
2. 在 tmux session 中逐条执行检查
3. 收集所有 PASS/FAIL 到 summary 表
4. 对每个 FAIL，记录错误 + 修复建议
5. 产出格式：

```markdown
## Audit Results: {project_name}

| Layer | Check | Status | Detail |
|-------|-------|--------|--------|
| L1 | Package install | PASS | |
| L1 | Core imports | PASS | |
| L2 | Data directory | FAIL | QT_DATA_DIR not set |
| ... | ... | ... | ... |

**Score**: 7/10 PASS

### FAIL Items → Action Required
1. [L2] CHECK 3: QT_DATA_DIR not set
   **Fix**: `export QT_DATA_DIR=/path/to/data`
2. ...
```

6. 如果用户要求，将 FAIL 项转为 GitHub Issues：
```bash
gh issue create --title "[Maturity] {check_name}" \
  --body "**Layer**: {layer}\n**Expected**: {pass_condition}\n**Actual**: {fail_detail}\n**Fix**: {suggested_fix}" \
  --label "product-maturity"
```

## Composability

| 场景 | 用法 |
|------|------|
| 新用户入驻前 | 跑 L1-L2，确保环境就绪 |
| CI（Jenkins） | 跑全部，on fail → 通知 |
| 重构后验证 | 跑 L3-L4，确保功能+质量 |
| deep-analysis 输入 | audit 结果作为 system_map 事实依据 |

## Anti-Patterns

```
❌ 在 SKILL.md 里放项目特定的 import 路径
   → 放在项目 .agent/maturity-checks.md 里

❌ 检查逻辑依赖项目内部模块（bootstrapping 悖论）
   → 用 python -c 从外部调用

❌ FAIL 只说"失败了"不说怎么修
   → 每个 FAIL 必须附带 fix 命令

❌ 一次性写 30 条然后不维护
   → 从 5-10 条开始，随项目演进增加
```
