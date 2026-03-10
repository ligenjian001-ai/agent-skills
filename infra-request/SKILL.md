---
name: infra-request
description: MANDATORY when filing infra requests. Covers GitHub Issues submission (playground issues post), idempotency guard, post-submit 3-step verification, project-aware labeling, Tool Integration Plan, and Self-Verification Guide.
---

# Infra Request Skill

**Core Philosophy**: Every infra request MUST result in a **usable tool** that becomes part of the operational toolkit.

## Submission Method: GitHub Issues (Primary)

> [!IMPORTANT]
> Infra requests are submitted via **GitHub Issues** to `$GITHUB_ISSUES_REPO`（默认 `ligenjian001-ai/hft-sdk-issues`）。
> See `github_issues_guide.md` in this skill directory for full template, labels, and status flow.

```bash
# Submit new request（AG 自动加 project label）
playground issues post "[TYPE] 标题" "正文..." --label <type> --label <priority> --label project:<project>

# Check existing issues
playground issues list

# Read / reply / close
playground issues read <N>
playground issues reply <N> "..."
playground issues close <N>
```

## Project Label（MANDATORY）

> [!IMPORTANT]
> **每个 issue 必须打 `project:<name>` label**，用于区分项目来源。
> 用户后续可能将 issue 分发到不同 repo，project label 是路由依据。

| Label | 项目 | 典型 issue 类型 |
|-------|------|-----------------|
| `project:hft_build` | HFT SDK 基建 | SDK 工具、数据管道、策略基建 |
| `project:workstation-ops` | 工作站运维 | 环境配置、依赖管理、系统服务 |
| `project:data` | 数据基建（预留） | 数据源、ETL、存储 |

**AG 判断规则**：根据 issue 内容判断所属项目，不需要用户显式指定。判断依据：

- 涉及 SDK API / 策略工具 / playground CLI → `project:hft_build`
- 涉及机器环境 / 依赖安装 / 系统配置 / 服务部署 → `project:workstation-ops`
- 不确定时，标注为用户最近工作的项目

## ⚠️ Idempotency Guard (MANDATORY for Issue Creation)

> [!CAUTION]
> `command_status` is unreliable for `playground issues` commands (known platform bug).
> NEVER blindly retry issue creation.

### Pre-flight Check

Before creating a new issue, **MUST** check for duplicates:

```bash
playground issues list > /tmp/ag_issue_list.txt 2>&1
# view_file /tmp/ag_issue_list.txt — check if similar issue exists
```

### Post-submit Verification (HARD GATE — CANNOT SKIP)

> [!CAUTION]
> **FORBIDDEN**: Mentioning the issue number, URL, or claiming "filed/submitted/created"
> in ANY user-facing output (notify_user, TaskSummary, TaskStatus) UNTIL you have
> run `playground issues list` and confirmed the issue appears in the output.
> Violation = false success claim (Rule 7 + Rule 9).

**Step 1**: Run `playground issues post` with output capture:

```bash
playground issues post "..." "..." --label X > /tmp/ag_issue_post.txt 2>&1
```

**Step 2**: Read the output file. If it shows `✅ Created: #N`, proceed. If empty or error, the command failed.

```bash
cat /tmp/ag_issue_post.txt
```

**Step 3**: Even if Step 2 looks OK, verify with a **separate** command:

```bash
playground issues list --limit 3 > /tmp/ag_issue_verify.txt 2>&1
# view_file /tmp/ag_issue_verify.txt — confirm issue title appears
```

**Step 4**: Only AFTER seeing the issue in the list output, you may report it to the user with the issue number and URL.

**If `command_status` says "RUNNING" but `list` shows the issue exists → DO NOT retry.**
**If `list` does NOT show the issue → the post FAILED. Fix and retry.**

## Principle: Request → Tool → Integration

The infra request lifecycle:

1. **Identify gap**: Operational need blocks current workflow
2. **Request tool**: File infra request specifying the tool to build
3. **Infra delivers**: Working script/binary/documentation
4. **Integrate**: Tool becomes available for future use
5. **Iterate**: Tool gets refined based on actual usage

**FORBIDDEN**: Requests that only produce documentation without executable tools.

## How to Compose a Request

When filing an infra request:

1. **Identify the tool needed**
   - What executable will solve this problem?
   - What should the command-line interface be?
   - What inputs and outputs?

2. **Specify deliverables**
   - Request SPECIFIC tools (scripts, binaries, skills)
   - NOT just "fix X" or "improve Y"
   - Example: "Build `scripts/sync_eod_data.sh`" NOT "provide data access"

3. **Define integration**
   - Where will this tool live? (`scripts/`, `.agent/skills/`, `bin/`)
   - How will I invoke it in future sessions?
   - What other tools depend on this?

4. **Submit via GitHub Issues** (see `github_issues_guide.md` in this skill directory)

## MANDATORY: Verification Protocol

**BEFORE claiming "verified" or "success", MUST complete ALL of these:**

1. **Compute expected values manually** for ALL relevant test cases
2. **Run SDK on ALL test cases** (not just one)
3. **Compare EACH result** against manual calculation
4. **Show exact numbers** in verification output
5. **Only claim verified if ALL match** within tolerance

**FORBIDDEN**:

- Claiming success after checking only ONE scenario
- Saying "verified" without showing actual vs expected numbers
- Assuming a fix works without running the test

## MANDATORY: Full-Universe Verification Scope

**Single-code verification = "Partial ✅" NOT "✅ Verified"**

To claim **"✅ Verified"**, you MUST:

1. **Multiple Codes**: Test on **≥3 representative codes** (different liquidity levels)
2. **Multiple Dates**: Test on **≥2 dates** when data is available
3. **Show Coverage**: Report as "Verified: X/Y codes, Z/W dates"
4. **Aggregated Stats**: Show total pass/fail across entire test universe

**Status Ladder**:

| Scope | Status | Can Ship? |
|-------|--------|-----------|
| 1 code, 1 date | ⚠️ Partial | No |
| 3+ codes, 1 date | 🟡 Good Coverage | With approval |
| 3+ codes, 2+ dates | ✅ Verified | Yes |

**ON DISCREPANCY**: If single-code passes but batch fails, the fix is **BROKEN at aggregation level**. Do NOT claim verified - investigate the aggregation/edge-case logic.

## Template Format

```markdown
# {Tool/Feature Name}

**Date**: {YYYY-MM-DD}
**Priority**: {🔴 High / 🟡 Medium / 🟢 Low}
**Type**: {Feature / Bug / Tool}
**Project**: {hft_build / workstation-ops / data}
**Status**: Pending

---

## What I Need

{One-sentence description of the tool/capability needed}

### Deliverable 1: {Tool Name} (P0/P1/P2)

**What**: `{path/to/tool.sh}` - {Brief description}

**Usage**:
```bash
{exact command-line invocation}
# {expected output format}
```

**What it should do**:

1. {Step-by-step behavior}
2. {Input processing}
3. {Output generation}

### Deliverable 2: {Next Tool} (P0/P1/P2)

{Repeat for each tool needed}

## Environment Context (workstation-ops / 环境配置类)

> 仅当 issue 涉及机器环境、依赖安装、系统配置时需要填写此段。

**Target Machine**: {hostname / IP / "all workstations"}
**OS**: {Ubuntu 22.04 / CentOS 8 / etc.}
**Dependencies**: {需要安装的包/工具列表}
**Config Files**: {涉及的配置文件路径}
**Rollback Plan**: {配置失败时的回滚方案}

## Why I Need This

**Immediate blocker**: {What workflow is blocked without this tool}

**Impact**: {How this affects daily operations}

## Tool Integration Plan

**Location**: Where will this tool live?

- Script: `scripts/{name}.{sh|py}`
- Skill: `.agent/skills/{name}/SKILL.md`
- Binary: `bin/{name}`

**Dependencies**: What does this tool require?

- Inputs: {data sources, config files}
- External tools: {rsync, ssh, python packages}
- Environment: {variables, credentials}

**Usage pattern**: How will I invoke this in future sessions?

```bash
{example invocation from typical workflow}
```

## Verification Criteria

| # | Test Case | Expected Result | Tolerance |
|---|-----------|-----------------|-----------|
| 1 | {Specific test} | {Expected output} | {Acceptable variance} |
| 2 | {Next test} | {Expected output} | {Acceptable variance} |

## Success Definition

Tool is **ready for integration** when:

- [ ] Executable runs without errors on test cases
- [ ] Output format matches specification
- [ ] Documentation/usage examples provided
- [ ] Integrated into workflow (added to scripts/, documented in README, etc.)

---

## 📥 Infra Team Response

### Delivered Tools

- **Tool 1**: `{path/to/tool}`
  - Version: {version}
  - Location: {absolute path}
  - Usage: `{command}`

- **Tool 2**: `{next tool}`
  - ...

### Integration Instructions

{How to use the delivered tools in operational workflow}

### Known Limitations

{Any edge cases or constraints of the delivered tools}

---

## Verification Results

**MUST COMPLETE BEFORE CLAIMING SUCCESS:**

| Test | Expected | Actual | Match? |
|------|----------|--------|--------|
| Case 1 | ... | ... | ✅/❌ |
| Case 2 | ... | ... | ✅/❌ |

**Status**: ❌ Not Verified / ✅ ALL Cases Pass / 🟡 Partial Integration

---

## Status Log

| Date | Action | Status | Notes |
|------|--------|--------|-------|
| {YYYY-MM-DD} | Requested tooling | ⏳ Pending | Initial request filed |
| {YYYY-MM-DD} | Tool delivered | ✅ Integrated | Now available in `{path}` |

```

## Infra Self-Verification Guide

**Purpose**: Give infra a way to reproduce and debug the issue themselves.

### Step 1: Reproduce the Symptom

```bash
# Exact commands to reproduce the broken behavior
{commands}
```

**Expected symptom**: {what broken output looks like}
**Why it's wrong**: {explanation}

### Step 2: Investigate Root Cause

```python
# Python/bash script to debug the issue
{investigation script showing what to look for}
```

**What to observe**: {specific things to check}

### Step 3: Verify Fix

```bash
# Commands to run after applying fix
{verification commands}
```

**Success criteria**:

- {criterion 1}
- {criterion 2}

**If still failing → {what to investigate next}**

## Status Log

| Date | Version | Tester | Result | Notes |
|------|---------|--------|--------|-------|
| ... | ... | ... | ... | ... |

```
