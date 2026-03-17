---
name: infra-intake
description: "MANDATORY when user sends a GitHub issue URL or says '处理 issue'. AG confirms the problem, then delegates design and implementation to CC through multi-round dialogue. Covers hft_build C++/Python SDK, scripts, CMake."
---

# /infra-intake Skill

> **ROLE**: AG 是 orchestrator——确认问题、审核方案、编排执行。AG **不是** coder，**不是** architect。
> CC 的方案设计能力显著强于 AG。AG 不要替 CC 设计方案。

AG 确认问题 → CC 设计方案 → AG 审核 → CC 执行 → Verifier 验证。

## When to Trigger

- 用户发了 GitHub Issue URL（`https://github.com/.../issues/N`）
- 用户说 "处理 issue"、"fix issue"、"看这个 issue"
- 用户直接描述了一个 hft_build 的 bug 或 feature request

## Principles

1. **AG 确认问题，CC 设计方案**: AG 只做问题确认，方案 + 实现全部交 CC
2. **Separation**: Executor ≠ Verifier (use task-delegate to spawn independent verifier)
3. **Multi-round Dialogue**: 用 `--resume-session` 实现 CC 多轮协作（设计 → 审核 → 执行）
4. **Release Verification**: Verifier tests **release SDK**, not debug build
5. **Issue-Driven**: All progress synced back to GitHub Issue

## Steps

### 1. Find and Read Request

**GitHub Issue (primary):**

User provides an issue URL: `https://github.com/ligenjian001-ai/hft-sdk-issues/issues/N`

1. Extract issue number `N` from URL
2. Read issue content:

   ```bash
   playground issues read N
   ```

3. Set issue status to in-progress:

   ```bash
   playground issues status N in-progress
   ```

**Remote requests (CK workstation):**

If the user provides a path containing `/data/share/`, it lives on CK workstation (`lgj@39.173.176.131`):

1. Fetch via SSH:

   ```bash
   ssh -o StrictHostKeyChecking=no -o BatchMode=yes lgj@39.173.176.131 \
     'cat <remote_path>' > /tmp/ag_ck_infra_request.txt 2>&1
   ```

2. Read `/tmp/ag_ck_infra_request.txt` completely
3. Create a GitHub Issue from the content:

   ```bash
   playground issues post "[INFRA] <title>" "<body>" --label infra --label P1
   ```

4. Continue with the newly created issue number

**Local requests (legacy fallback):**

1. List `/home/lgj/lgj_strategy_zoo/research/infra_requests/`
2. Find **Status: Pending**
3. Read completely
4. Create a GitHub Issue from the content, then continue with issue number

### 2. Confirm Problem ⚠️ MANDATORY

> [!CAUTION]
> **AG 在这一步只做问题确认，不要开始想方案。**
> 如果你发现自己在想"怎么实现"——停下来，那是 CC 的工作。

AG 确认自己理解了问题，向用户 / issue 发确认：

```bash
playground issues reply N "🛸 **[Antigravity]**

## 🧠 My Understanding

**Problem**: {对问题的理解，不是解法}
**Scope**: {影响范围}
**Constraints**: {不能改什么、兼容性要求}
**Verification Type**: LOCAL / RELEASE_SDK / TRADING_MACHINE

**Do you confirm?**"
```

**AG 在这一步应该确认的：**
- 用户遇到了什么问题？
- 边界条件是什么？
- 有哪些约束？（不能修改哪些接口、兼容性要求）
- 验证方式是什么？

**AG 在这一步不应该做的：**
- ❌ 设计 API 签名
- ❌ 规划实现步骤
- ❌ 读代码想方案
- ❌ 写 implementation_plan.md 的技术细节

**→ Wait for user confirmation**

### 3. Spawn Baseline Verifier (task-delegate)

After user confirms, spawn the baseline verifier:

```bash
playground issues reply N "🛸 **[Antigravity]**

⚙️ Confirmed. Spawning baseline verifier to confirm the problem exists."
```

#### 3a. Write Verifier Prompt

```python
# Use write_to_file tool — NEVER send-keys for file content
TASK_ID = "YYYYMMDD_HHMM_issueN_baseline"
# Write to: ~/.task-delegate/{TASK_ID}/prompt.txt
```

**Prompt template:**

```markdown
# Task: Verify Issue #N — {title} (BASELINE)

## Objective
Confirm the reported problem exists in the CURRENT release SDK.

## Context
- Project root: /home/lgj/hft_build
- Release SDK: ~/.local/opt/hft_sdk/ (this is what you test, NOT build_release/)
- Issue: {problem description from Step 2}

## Verification Criteria
{criteria from Step 2 discussion}

## Self-Test
Run the following and report results:
```
playground {test_command}
```
Report: "BASELINE CONFIRMED: {error}" or "PROBLEM NOT FOUND: {what you observed}"
```

#### 3b. Launch

```bash
SKILL_DIR=$(dirname $(readlink -f $(find /home/lgj/agent-skills/task-delegate -name task_launch.sh)))
bash "$SKILL_DIR/task_launch.sh" ${TASK_ID} /home/lgj/hft_build --backend codex
```

**Backend selection for verification:**

| Backend | Use When |
|---------|----------|
| `codex` | **Default** — sandbox isolation, good for SDK verification |
| `cc` | When verifier needs to read/write multiple files or do complex analysis |

#### 3c. Monitor (Active Monitoring Loop — MANDATORY)

Follow the **task-delegate Step 3** monitoring protocol exactly. **DO NOT YIELD AFTER LAUNCH.**

### 4. Confirm Baseline

Extract verifier output:

```bash
bash /home/lgj/agent-skills/task-delegate/scripts/task_extract.sh ${TASK_ID}
```

Post baseline result to issue:

```bash
playground issues reply N "🛸 **[Antigravity]**

✅ **Baseline confirmed**: {error description}. Proceeding with design."
```

- ✅ `BASELINE CONFIRMED` → Proceed to Step 5
- ❌ `PROBLEM NOT FOUND` → Reply to issue asking for clarification

### 5. CC Design Dialogue ⭐ 核心改动

> [!IMPORTANT]
> **AG 不要自己设计方案。通过 task-delegate 的 `--resume-session` 把 CC 当成设计专家进行多轮协作。**

#### 判断路径

| 类型 | 做法 | 说明 |
|------|------|------|
| **简单 bug**（路径清晰） | CC Direct Execute | 一轮搞定 |
| **需要方案设计的 feature** | CC Design Dialogue | Round 1 设计 → 审核 → Round 2 执行 |
| **跨模块/架构级变更** | CC Design Dialogue + 用户审批 | 方案需用户确认 |

#### Round 1: CC 设计方案

AG 只传 **问题 + 约束**（WHAT），不传实现方案（HOW）。

```python
TASK_ID = "YYYYMMDD_HHMM_issueN_design"
# Write to: ~/.task-delegate/{TASK_ID}/prompt.txt
```

**Design prompt template:**

```markdown
# Task: Design solution for Issue #N — {title}

## Problem
{AG 在 Step 2 确认后的问题描述}

## Constraints
- {约束 1: 不能修改的接口}
- {约束 2: 兼容性要求}
- {约束 3: 其他}

## Context
- Project root: /home/lgj/hft_build
- Key files: {仅列出用户提到的或 issue 中提到的文件}

## Deliverable
请分析代码库，设计实现方案，输出到 /home/lgj/hft_build/design_report.md。
方案应包含：
1. 你对问题的理解和代码分析
2. 涉及的关键文件和当前实现
3. 推荐的实现方案（含 API 设计）
4. 备选方案（如有）
5. 风险点

不要做任何代码修改。
```

Launch:

```bash
bash "$SKILL_DIR/task_launch.sh" ${TASK_ID} /home/lgj/hft_build --backend cc
```

Monitor until complete → extract output → read `design_report.md`。

#### AG 审核方案

AG 读 CC 的 `design_report.md`，审核标准：

1. **方案是否解决了用户描述的问题？**（对齐用户意图）
2. **是否违反了约束条件？**（不改不该改的东西）
3. **是否需要用户确认？**（高风险/架构级变更）

如果需要用户确认 → `notify_user` 附 design_report.md 让用户审核。

#### Round 2: CC 执行实现

用 `--resume-session` 继续同一个 CC 会话：

```python
TASK_ID_EXEC = "YYYYMMDD_HHMM_issueN_execute"
# prompt.txt 内容很短——CC 已经有完整上下文
```

**Execute prompt template:**

```markdown
方案审核通过。请按你在 design_report.md 中的方案执行实现。

{如有调整: 方案需要调整：{具体反馈}}

## Self-Test
{验证命令}
```

Launch with `--resume-session`:

```bash
# 从 Round 1 的 execution_record.json 中提取 session_id
SESSION_ID=$(python3 -c "import json; print(json.load(open('$HOME/.task-delegate/YYYYMMDD_HHMM_issueN_design/execution_record.json'))['session_id'])")

bash "$SKILL_DIR/task_launch.sh" ${TASK_ID_EXEC} /home/lgj/hft_build \
  --backend cc --resume-session "$SESSION_ID"
```

### Checkpoint Sync Rule (MANDATORY)

> [!IMPORTANT]
> Long tasks can span hours with multiple intermediate releases. The submitter must not be left in the dark.

**Post a progress checkpoint to the issue whenever:**

1. **An intermediate SDK version is released** (even if not the final fix):

   ```bash
   playground issues reply N "📌 **Checkpoint** (v1.9.XX)

   Progress:
   - ✅ Fixed {component A}
   - ✅ Added {feature B}
   - 🔄 Still working on: {remaining item}

   Intermediate release deployed. Not yet ready for final verification."
   ```

2. **A significant finding or design change occurs** during investigation:

   ```bash
   playground issues reply N "🔍 **Investigation Update**

   Found additional issue: {description}.
   Adjusting approach: {new plan}.
   ETA: {estimate}."
   ```

3. **A blocker is encountered** that requires input from the submitter:

   ```bash
   playground issues reply N "⚠️ **Blocked — Need Input**

   {question or clarification needed}
   Please reply so I can continue."
   ```

**Rule of thumb**: if more than 30 minutes have passed since the last issue update, post a checkpoint.

### 6. Release & Trigger Verification

After CC completes implementation:

1. Build and release:
   ```bash
   cmake --build build_release
   bash scripts/release_sdk.sh
   ```

2. Spawn verify task (same as Step 3, but testing the fix):

```python
VERIFY_TASK_ID = "YYYYMMDD_HHMM_issueN_verify_K"  # K = iteration number
```

**Verify prompt template:**

```markdown
# Task: Verify Issue #N — {title} (VERIFY round K)

## Objective
Verify that the fix in SDK v1.9.XX resolves the reported problem.

## Context
- Project root: /home/lgj/hft_build
- Release SDK: ~/.local/opt/hft_sdk/ (just updated via release_sdk.sh)
- Baseline: {baseline error from Step 4}

## Verification Criteria
{same criteria as baseline}

## Self-Test
Run the following and report results:
```
playground {test_command}
```
Report: "PASS: {what works now}" or "FAIL: {what's still broken + details}"
```

### Key: Debug vs Release

| Who | Build | Path | Purpose |
|-----|-------|------|---------|
| CC (Executor) | Debug | `build_release/` | Quick iteration, sanity check |
| Verifier (task-delegate) | Release | `~/.local/opt/hft_sdk/` | Final verification |

**Verifier NEVER tests debug build.** Always waits for `release_sdk.sh`.

### 7. Process Result & Sync to Issue

Extract output via `task_extract.sh`, read `execution_record.json`.

**PASS → post to issue and trigger /infra-release:**

```bash
playground issues reply N "🛸 **[Antigravity]**

✅ **Verification PASSED** (independent verifier via task-delegate).
Proceeding to /infra-release (deploy to all environments)."
```

**Auto-release gate**: If the issue has **low-risk labels** (`bug`, `P2`, `documentation`, `test`), proceed directly to `/infra-release` without user confirmation. For **high-risk** issues (`P0`, `P1`, `infra` modifying core physics, or any label not in the low-risk set), notify user and wait for approval before releasing.

**FAIL → post feedback and iterate (max 3 rounds):**

```bash
playground issues reply N "🛸 **[Antigravity]**

❌ **Verification FAILED** (iteration K/3).
Feedback: {extracted feedback from task_extract.sh}
Sending feedback to executor for fix..."
```

Use `--resume-session` to send failure feedback to CC, CC fixes, re-release, re-verify.

## Workflow

```
User sends Issue URL
         │
         ▼
Read Issue (playground issues read N)
Set in-progress (playground issues status N in-progress)
         │
         ▼
AG Confirms Problem → Issue Comment
         │ User confirms
         ▼
Spawn Baseline Verifier (Codex via task-delegate)
  └─ task_launch.sh → live.log → execution_record.json
         │
         ▼
BASELINE (current release SDK)
Post result → Issue Comment
         │ Confirmed
         ▼
┌─────────────────────────────────────┐
│  CC Design Dialogue (Round 1)       │
│  CC analyzes code + outputs         │
│  design_report.md                   │
└──────────────┬──────────────────────┘
               │
               ▼
AG Reviews design_report.md
  ├─ Simple → approve
  └─ Complex → user confirms
               │
               ▼
┌─────────────────────────────────────┐
│  CC Execute (Round 2)               │
│  --resume-session continues         │
│  Same CC session, full context      │
└──────────────┬──────────────────────┘
               │
               ▼
release_sdk.sh
               │
               ▼
Spawn Verify Task (Codex via task-delegate)
Post result → Issue Comment
               │
    ┌──────────┴──────────┐
   PASS                  FAIL ─→ feedback to CC
    │                         (--resume-session)
    ▼                          (max 3 rounds)
/infra-release
Post release notification → Issue
Set resolved (playground issues status N resolved)
Close issue (gh issue close N)
```

### 8. Close Issue ⚠️ MANDATORY

> [!IMPORTANT]
> **Every completed issue MUST be closed with a summary comment.** An issue without a closing comment is not "done" — the submitter has no record of what was delivered.

#### 8a. Post Closing Summary

Write a closing comment summarizing what was delivered, verified, and any follow-up issues:

```bash
gh issue comment N --repo ligenjian001-ai/hft-sdk-issues --body-file /tmp/issueN_close.md
```

**Closing comment template** (write to `/tmp/issueN_close.md` via `write_to_file`):

```markdown
🛸 **[Antigravity]**

## ✅ Issue #N 完成总结

### 交付内容
1. {deliverable 1}
2. {deliverable 2}

### 验证结果
- {test results}
- {service status}

### 关联 Issue
- {any follow-up issues filed}
```

#### 8b. Close the Issue

```bash
gh issue close N --repo ligenjian001-ai/hft-sdk-issues --reason completed
```

**Closure rules:**
- **completed** = all deliverables verified and deployed
- **not-planned** = issue determined to be invalid or out of scope
- Never close without a summary comment
- If partial completion, leave the issue open with a checkpoint comment explaining what's done and what remains

## Mandatory Rules

1. **AG 不设计方案。** AG 的工作到 "确认问题边界" 为止。方案设计 + 实现全部交 CC。
2. **Design prompt 只传 WHAT，不传 HOW。** prompt 中出现代码片段/函数签名/实现步骤 = 越权。
3. **每个重要步骤同步到 Issue。** 超过 30 分钟无 issue 更新 = 违规。
4. **Launch 后不 yield。** AG 在同一 turn 内 inline polling，不交还控制权。
5. **Verifier 只测 release SDK。** 禁止测试 debug build。
6. **失败反馈用 `--resume-session`。** 验证失败时把反馈发回同一个 CC 会话，不开新会话。
7. **完成后必须关闭 Issue。** 写总结 comment (`--body-file`) 后 `gh issue close N --reason completed`。未写 closing comment 就关闭 = 违规。

## Anti-Patterns

❌ AG 自己设计实现方案
   → AG 只确认问题，方案交 CC

❌ AG 在 prompt 中写代码片段、函数签名、实现步骤
   → 只传 WHAT + 约束，不传 HOW

❌ AG 读代码来想怎么修复
   → 需要代码分析的 → 发给 CC

❌ AG 写 implementation_plan.md 包含技术实现细节
   → AG 的 plan 只写问题确认和编排策略

❌ Verifier tests debug build → Must use release SDK
❌ Skip release_sdk.sh → Manual lib copy breaks ABI
❌ Self-verify → Use independent verifier via task-delegate
❌ Hand-roll Codex invocation → Always use `task_launch.sh` from task-delegate
❌ Forget to sync to issue → Every major step MUST be posted as issue comment
❌ Yield after launch → AG must monitor inline (task-delegate Step 3 protocol)

## Hazard: Verification Environment Mismatch (#16)

> [!CAUTION]
> **Verifier runs on the local dev machine.** If verification criteria require infrastructure not available locally (SSH tunnel to trading server, remote binaries, production data), the verifier CANNOT verify the core feature path.
>
> **Incident**: Issue #16 — Verifier reported PASS for DualRunner `--backtest` detection, but only verified help text and dry-run-without-SSH (trivial edge cases). The actual SSH-based detection was never tested. Real E2E testing later revealed the detection approach was fundamentally flawed.

**Mandatory pre-flight check before spawning verifier:**

1. List each verification criterion
2. For each, answer: **"Can the verifier execute this on the local dev machine?"**
3. If ANY criterion requires remote infra → mark it as **"LOCAL UNVERIFIABLE"**
4. After verifier returns PASS, explicitly state which criteria were actually tested vs skipped
5. Run real E2E tests on the appropriate environment for any unverifiable criteria

**Never present partial verification as complete verification.**

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Skill 不触发（用户发 issue URL 但 AG 没激活 infra-intake） | 检查 YAML description 是否包含 "GitHub issue" 等触发词；检查 skill 是否在 AG Settings 中注册 |
| CC design round 后没有 `session_id` | 检查 `execution_record.json` — CC 可能未正常完成。查看 `live.log` 末尾错误 |
| `--resume-session` 报错 session not found | Session 可能过期。重新启动 fresh CC session |
| Baseline verifier 报 PROBLEM NOT FOUND | 确认 verifier 测的是 release SDK（`~/.local/opt/hft_sdk/`），不是 debug build |
| Issue sync 中断（playground issues reply 失败） | 检查 `playground issues list` 连通性；`> /tmp/ag_issue_debug.txt 2>&1` 抓输出 |
| CC prompt > 4KB 警告 | AG 在 prompt 中塞了 HOW。精简到只有问题描述 + 约束 |
