---
name: skill-creator
description: "Standards and workflow for creating high-quality agent skills. Defines the documentation paradigm, quality checklist, and skill structure conventions."
---

# Skill Creator

> **ROLE**: This skill defines how to build, document, and maintain agent skills.
> Follow this standard when creating new skills or auditing existing ones.

## Skill Directory Structure

```
skill-name/
├── SKILL.md           ← REQUIRED: Agent-facing operational guide
├── README.md          ← RECOMMENDED: Human-facing deep documentation
├── DESIGN.md          ← OPTIONAL: Deep technical reference (constraints, failed approaches)
├── scripts/           ← As needed: helper scripts
├── prompts/           ← As needed: prompt templates
└── examples/          ← As needed: reference implementations
```

## SKILL.md — The Six-Section Standard

Every `SKILL.md` MUST follow this structure. Sections may be renamed but the intent must be preserved.

### ① YAML Frontmatter (REQUIRED)

```yaml
---
name: skill-name
description: "One-line description — what the skill does, when to use it."
---
```

The framework uses this to discover and match skills. A vague description = skill never gets triggered.

**Rules**:

- `name` MUST match the directory name
- `description` should answer: "What does this skill do?" + "When should the agent use it?"
- Include trigger keywords the user might say (e.g., "Manage Jenkins CI/CD jobs — trigger, monitor, configure")

### ② Core Principle / Role (REQUIRED)

A blockquote immediately after the title that defines the skill's identity in one sentence.

```markdown
> **ROLE**: AG is the **orchestrator**. AG does NOT write code — it dispatches to Claude Code.
```

**Purpose**: Prevents agent role drift. Without this, agents tend to "help" by doing the executor's job themselves. This is the most common failure mode in delegation skills.

**Rules**:

- Use `>` blockquote format with bold emphasis
- State what the agent IS and what it IS NOT
- For skills with clear role boundaries, add a STOP warning box (see tmux-protocol, cc-delegate)

### ③ Operational Workflow (REQUIRED)

Step-by-step instructions the agent can follow mechanically. Each step must include:

- **Exact commands** (copy-pasteable, with variable placeholders clearly marked)
- **Expected output** (so the agent knows what success looks like)
- **Decision points** (if X → do A, if Y → do B)

**Rules**:

- Use numbered phases/steps with descriptive headers
- Every bash command must be in a fenced code block with `bash` language tag
- Use `{variable}` syntax for placeholders, define them before first use
- Include timeout/cadence guidance for polling operations
- If workflow requires tmux: reference tmux-protocol rules explicitly

**Quality test**: Can the agent follow these steps without asking "what should I do here"? If not, the step is too vague.

### ④ Mandatory Rules (REQUIRED)

Hard constraints that must never be violated. Numbered list format.

```markdown
## Mandatory Rules

1. **ALWAYS set `waitForPreviousTools=true`** on EVERY tmux `run_command`.
2. **Keep commands SHORT.** For long sequences, write a script file first.
3. **For file creation**: Use `write_to_file`. NEVER use `send-keys` for file content.
```

**Rules**:

- Use bold for the rule statement
- Keep the list to 3-7 items (more = agent ignores them all)
- Each rule should be independently verifiable (not "be careful" — that's unverifiable)
- Prioritize rules by failure frequency (most violated rule first)

### ⑤ Anti-Patterns (REQUIRED)

Common mistakes marked with ❌. LLM compliance with negative examples is empirically higher than with positive-only rules.

```markdown
## Anti-Patterns

❌ AG writes the code itself instead of delegating
   → If user asked for CC, use CC

❌ Vague prompt: "fix the bugs"
   → MUST specify which files, what behavior is wrong, expected behavior
```

**Rules**:

- Use `❌` prefix (not just "Don't")
- Show the wrong behavior + the correct alternative with `→`
- Include real failure scenarios observed in practice, not hypothetical ones
- 3-8 items (enough to cover major pitfalls without overwhelming)

### ⑥ Troubleshooting (REQUIRED)

Problem → Fix table for known failure modes.

```markdown
## Troubleshooting

| Problem | Fix |
|---------|-----|
| Jenkins unresponsive | `docker ps --filter name=jenkins` / `docker restart jenkins` |
| CC hangs at start | Check `claude --version`, ensure CC is installed |
```

**Rules**:

- Use markdown table format
- "Problem" column = what the agent observes (symptom-based, not cause-based)
- "Fix" column = specific action, not "investigate further"
- 3-10 rows covering the most frequently encountered issues

---

## README.md — Human-Facing Deep Documentation

While `SKILL.md` tells the agent **what to do**, `README.md` tells humans **why it was built this way**.

> [!IMPORTANT]
> **README.md 必须用中文撰写。** 技能用户群体以中文为主，README 是给人看的设计文档，中文更高效。
> SKILL.md 保持中英混合（agent 消费），README.md 全中文（人类消费）。

### Structure

```markdown
# Skill Title — Human Readable

> Metadata: version, date, author

## The Problem
What problem does this skill solve? Why do existing solutions fail?

## The Solution
High-level architecture. What approach was chosen and WHY.

## Design Decisions
Key decisions with rationale. Document trade-offs explicitly.

## Failed Approaches (if any)
What was tried and abandoned. WHY it failed.
This section prevents future contributors from repeating known failures.

## FAQ
Q&A format. Use positive statements ("This IS normal behavior")
over negative conditions ("If you encounter X...").
LLMs comply better with positive framing.

## Evolution History
| Date | Version | Change |
|------|---------|--------|

## File Index
| File | Purpose |
|------|---------|
```

### README vs DESIGN.md

| Aspect | README.md | DESIGN.md |
|--------|-----------|-----------|
| Audience | Humans (users, contributors) | Humans (deep debugging) |
| Tone | Explanatory, friendly | Technical, exhaustive |
| When needed | Always recommended | Only for complex skills with platform constraints |
| Example | tmux-protocol/README.md | tmux-protocol/AG_TERMINAL_BEHAVIOR.md |

---

## Quality Checklist

Use this checklist when creating or auditing a skill:

### SKILL.md Checklist

- [ ] YAML frontmatter has descriptive `name` + `description`
- [ ] Core principle/role blockquote present
- [ ] Operational steps are copy-pasteable without guessing
- [ ] Mandatory rules numbered and bold
- [ ] Anti-patterns have ❌ markers with `→` corrections
- [ ] Troubleshooting table covers top 3+ failure modes
- [ ] All bash commands in fenced code blocks with language tag
- [ ] Variable placeholders use `{name}` syntax and are defined before use
- [ ] tmux operations reference tmux-protocol rules (if applicable)

### README.md Checklist

- [ ] Problem statement explains WHY the skill exists
- [ ] Design decisions documented with rationale
- [ ] Failed approaches listed (if any were tried)
- [ ] FAQ uses positive framing
- [ ] Evolution history table present
- [ ] File index lists all files in the skill directory

### General Checklist

- [ ] Skill directory name = YAML `name` field
- [ ] Scripts are executable and have usage comments
- [ ] No outdated/dead code in scripts
- [ ] Skill is registered in root `README.md` table
- [ ] Symlinks created in all relevant workspaces
- [ ] GEMINI.md registration evaluated (see decision matrix — not all skills need it)
- [ ] If registered in GEMINI.md: critical rules are **inlined**, not just referenced

---

## Skill Lifecycle Philosophy

Skills are created for specific reasons. **Recording those reasons is as important as recording how the skill works**, because when the reason no longer exists, the skill should be adjusted or removed.

### Two Categories of Skills

| Category | Purpose | Example | When to Retire/Adjust |
|----------|---------|---------|----------------------|
| **Gap-filling** | Compensate for platform/tool limitations | `jenkins-ops` (Jenkins MCP lacks commands), `ag-archive` (`.pb` files encrypted) | When the platform adds native support |
| **Information capture** | Record context that would otherwise be lost | `ag-archive` (conversation journal), `skill-creator` (design decisions) | When the platform provides native recording |

Some skills serve both purposes (e.g., `cc-delegate` fills AG's long-task gap AND captures the AG-as-copilot/CC-as-builder collaboration pattern).

### README.md Must Record "Why This Skill Exists"

Every README.md should include a **Skill Design Philosophy** section that answers:

1. **What gap does this fill?** — What tool/platform limitation motivated this skill?
2. **What would make it obsolete?** — Under what conditions should this skill be retired?
3. **What should survive retirement?** — Which patterns/learnings should be preserved even if the skill is deprecated?

This ensures that when a skill's raison d'être disappears, we know exactly what to do — adjust, simplify, or deprecate — instead of maintaining dead code.

> [!IMPORTANT]
> `multi-agent-exec` is a real example: it was built for AG tmux-based multi-agent orchestration, then deprecated when Claude Code's native Task subagent replaced the need. The SKILL.md now clearly says DEPRECATED and explains what replaced it. **This is the correct lifecycle.**

---

## Skill Creation Workflow

### Phase 1: Need Identification

1. Identify the repeating pattern (what do you keep doing manually?)
2. Define the scope: what's IN and OUT of this skill
3. Check: does this overlap with an existing skill? → Extend, don't duplicate

### Phase 2: Draft SKILL.md

1. Start with YAML frontmatter + Core Principle
2. Write the operational workflow from memory (what do you actually DO?)
3. For each step: make it copy-pasteable. If you can't — the step is unclear
4. Add 3-5 anti-patterns from real failures you've seen
5. Add troubleshooting table from real issues encountered

### Phase 3: Build Scripts

1. Extract repeated command sequences into scripts
2. Each script: self-contained, fail-fast (`set -euo pipefail`), clear usage
3. Scripts go in `scripts/` directory

### Phase 4: Write README.md

1. Explain the problem and why you built this skill
2. Document every non-obvious design decision
3. Record failed approaches (future you will thank past you)
4. Write FAQ from questions you'd ask if reading this for the first time

### Phase 5: Integration

1. Add entry to root `README.md` table
2. Create symlinks in active workspaces:

   ```bash
   for skill in /home/lgj/agent-skills/*/; do
     name=$(basename "$skill")
     [ "$name" = ".git" ] && continue
     ln -sfn "$skill" <workspace>/.agent/skills/"$name"
   done
   ```

3. Test: can the agent discover and use this skill in a fresh conversation?
4. Evaluate GEMINI.md registration need (see "GEMINI.md — Global Rule Registration" section):
   - Does this skill have rules whose violation causes irrecoverable failure? → Register
   - Does this skill need a conversation-start ritual? → Register
   - Is this skill purely on-demand? → Skip registration
5. **Review project README** — 检查 `/home/lgj/agent-skills/README.md`：
   - 技能清单表是否需要新增/更新条目
   - 技能协作架构图（mermaid）是否需要添加新节点或连线
   - 数据流表是否需要新增 IPC 目录
   - 技能间协作关系表是否需要新增条目

### Phase 6: Iterate

- After 2-3 real uses, update anti-patterns with new failure modes
- After 5+ uses, write README.md FAQ from real questions
- Version bump in evolution history for significant changes

### 编排类 Skill 的特殊考量

> [!IMPORTANT]
> 技能会越来越复杂，多数依赖大量 subagent 编排（如 deep-analysis, system-design, agent-native-product）。
> 编排类 skill 需要额外的设计约束和迭代机制。

**编排类 skill 的特征**：
- 多步骤 subagent 调用，每步有独立 prompt
- prompt 迭代频率远高于流程逻辑 → **必须将 prompt 放到 `prompts/` 目录**
- 需要通过日志进行持续反思调整

**日志驱动的持续反思**：

编排类 skill 的质量取决于 prompt 质量，而 prompt 质量只有通过实际执行才能验证。
每次 skill 被使用后，AG 应：

1. **回顾 subagent 输出**（`~/.task-delegate/{task_id}/` 中的执行记录）
2. **识别 prompt 不足**：subagent 遗漏了什么？产出了什么低质量内容？
3. **更新 prompt 文件**：直接改 `prompts/*.txt`，不需要动 SKILL.md
4. **记录改进原因**：在 README.md 的演进历史中记录为什么改

这形成一个**闭环**：使用 → 回顾日志 → 改 prompt → 再使用 → 再回顾。
SKILL.md 保持稳定（流程不变），prompt 文件持续进化。

### 跨 Skill 共享 Prompt 检测

创建或调整 skill 后，AG 应检查 `prompts/` 中的 sub-prompt 是否与其他 skill 的 prompt 高度重合。

**检测时机**：
- 创建新 skill 的 prompt 文件时
- 修改现有 prompt 文件时
- 用户手动 cue "检查 prompt 重复"

**检测方法**：
1. 扫描 `/home/lgj/agent-skills/*/prompts/` 下所有 prompt 文件
2. 比较功能意图（不是字面匹配）：是否有两个 prompt 在做本质相同的事？
3. 常见共享模式：
   - 评估类 prompt（多个 skill 都有 assess/audit 步骤）
   - 报告生成模板（maturity report, friction log）
   - 通用 subagent 角色定义（investigator, auditor）

**发现重合时**：
- AG **主动询问用户**："发现 `{skill_a}/prompts/{x}.txt` 和 `{skill_b}/prompts/{y}.txt` 功能高度重合，是否要抽取到公共 skill？"
- 如果用户同意：创建公共 prompt 文件（放 `common-prompts/` 或合适的共享位置），两个 skill 引用同一份
- 如果用户拒绝：在各自 README 中注明"与 {other_skill} 有类似 prompt，但因 {reason} 保持独立"

---

## GEMINI.md — Global Rule Registration

`~/.gemini/GEMINI.md` is AG's system prompt — its content **survives context compression** and is always visible to the agent. Some skills need to register critical rules here, not just in SKILL.md.

### When to Register in GEMINI.md

**Not every skill needs GEMINI.md registration.** Use this decision matrix:

| Condition | Register in GEMINI.md? | Example |
|-----------|:---:|---------|
| Rule violation causes **irrecoverable failure** (hang, data loss) | ✅ YES | tmux-protocol: all commands must go through tmux |
| Skill requires **pre-activation** before first use | ✅ YES | tmux-protocol: `view_file(SKILL.md)` before any terminal op |
| Skill has a **conversation-start ritual** | ✅ YES | ag-archive: create conversation journal at start |
| Skill is only triggered **on-demand** by user keywords | ❌ NO | agent-panel-discussion: triggered by "讨论一下" |
| Rules are **operational details** within a workflow | ❌ NO | cc-delegate: prompt.txt format |
| Bug/workaround that affects **all conversations** | ✅ YES | Agent Manager approval visibility bug |

**Rule of thumb**: If the agent forgetting this rule mid-conversation (after context compression) would cause a **catastrophic failure**, it belongs in GEMINI.md. If it would just cause a **suboptimal result**, it stays in SKILL.md.

### How to Register

GEMINI.md uses numbered sections. Add a new section following the existing pattern:

```markdown
## {N}. {SECTION TITLE} — {SCOPE INDICATOR}

{One-line summary of what this section enforces}

{Critical rules with bold + ❌ markers}
```

**Registration checklist**:

1. **Choose a section number** — append after the last existing section
2. **Write inline rules** — do NOT just say "read SKILL.md". Inline the critical rules directly, because SKILL.md content may be compressed away
3. **Use survival formatting** — bold, ❌ markers, explicit positive statements. The compressor tends to preserve emphasized content
4. **Keep it minimal** — only the rules that MUST survive compression. GEMINI.md is shared across ALL skills; bloating it dilutes all rules

### Current GEMINI.md Layout (as of v3.2)

| Section | Skill | Purpose |
|---------|-------|---------|
| §1-9 | (general) | Engineering, safety, documentation, honesty rules |
| §10 | (infrastructure) | Global skill auto-bootstrap (symlinks at conversation start) |
| §11 | `tmux-protocol` | Terminal reliability — inline tmux rules + pre-activation gate |
| §12 | `tmux-protocol` | Agent Manager approval bug — workaround |

### Registration Examples

**tmux-protocol** (§11) — the gold standard of GEMINI.md registration:

- Pre-activation gate: `view_file(SKILL.md)` before first terminal op
- Inline critical rules: tmux send-keys pattern, PS1 markers, three mandatory parameters
- Anti-patterns with ❌: heredoc hang, killing sessions on background
- Recovery protocol: what to do on hang, what to do on user cancel

**ag-archive** (in project GEMINI.md) — lighter registration:

- Conversation journal protocol: create journal at conversation start
- Only the trigger rule is registered; the actual archive workflow stays in SKILL.md

### Anti-Patterns for Registration

```
❌ Registering ALL skill rules in GEMINI.md
   → Only catastrophic-failure rules. GEMINI.md bloat = all rules get ignored

❌ "See SKILL.md for details" without inline rules
   → SKILL.md content gets compressed. Critical rules MUST be inlined

❌ Registering on-demand skills (user-triggered) in GEMINI.md
   → Wastes system prompt budget. These skills are read when triggered

❌ Not updating GEMINI.md when skill rules change
   → Stale GEMINI.md rules are worse than no rules (agent follows outdated behavior)
```

---

## Naming Conventions

| Item | Convention | Example |
|------|-----------|---------|
| Skill directory | `kebab-case` | `cc-delegate`, `tmux-protocol` |
| YAML `name` | Same as directory | `cc-delegate` |
| Scripts | `snake_case.sh` / `snake_case.py` | `ag_dispatch.sh`, `panel_report_html.py` |
| tmux sessions | `{skill}-{context}` | `cc-{task_id}`, `panel-{task_id}-r0-skeptic` |
| IPC directories | `/tmp/{skill_prefix}_tasks/` | `/tmp/cc_tasks/`, `/tmp/ag_ipc/` |

## Anti-Patterns

```
❌ Writing SKILL.md with only vague descriptions ("handle Jenkins stuff")
   → Every section must have concrete, actionable content

❌ Skipping README.md ("the code is self-documenting")
   → Design decisions and failed approaches are NOT in the code

❌ Copy-pasting tmux-protocol's structure without adapting
   → The six-section standard is a template, not a straitjacket

❌ Creating a skill for a one-off task
   → Skills are for REPEATING patterns. One-off = just do it directly

❌ Putting GEMINI.md rules in SKILL.md
   → GEMINI.md is for rules that must survive context compression
   → SKILL.md is for operational details read via view_file
```

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Skill not discovered by AG | Check YAML `name` matches dir name, check symlink exists in workspace |
| Agent ignores SKILL.md rules | Move critical rules to GEMINI.md (survives context compression) |
| Anti-patterns not followed | Add ❌ markers + positive restatement. Bold the key phrase |
| FAQ answers not helping | Rewrite as positive statements, not conditional ("This IS X" not "If you see X") |
| Skill too complex for one file | Split: SKILL.md (ops) + DESIGN.md (deep reference) |
