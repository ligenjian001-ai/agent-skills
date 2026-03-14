---
name: agent-native-product
description: "Transform an SDK/CLI/API project's interface to be agent-friendly. Assess maturity, generate documentation, audit quality. Trigger: 'agent化改造', 'make API agent-friendly', 'improve agent usability'."
---

# Agent-Native Product Transform

> **ROLE**: AG is the **transformation orchestrator**. AG dispatches Scout (assessment),
> Transformer (generation), and Auditor (verification) subagents via task-delegate.
> AG does NOT generate project files itself — all generation is done by subagents.

> [!IMPORTANT]
> This skill transforms a project's **agent-facing interface** — API design, documentation,
> environment abstraction, observability. It does NOT modify application logic or
> development process infrastructure. For dev-process changes, use `agent-native-devflow`.

## When to Trigger

- User says "让 agent 更好用这个 SDK"、"改造 API"、"agent-friendly"
- User wants to improve API/CLI usability for LLM agents
- User wants to generate AGENTS.md / CLAUDE.md for an existing project
- After `deep-analysis` reveals product-layer gaps (A2-A5)

## Maturity Model

| Level | Name | Signature |
|-------|------|-----------|
| **L0** | Absent | No agent-facing docs, no structured output, no health check |
| **L1** | Ad-hoc | README exists, CLI has some --help, basic logging |
| **L2** | Structured | CLAUDE.md + AGENTS.md, consistent CLI, structured errors, health check |
| **L3** | Enforced | Executable doc-tests, --json on all commands, discovery API, error catalog |

## Dimensions

| ID | Dimension | What It Means |
|----|-----------|---------------|
| A2 | **API Surface** | CLI/API consistency, structured output, error design |
| A3 | **Environment Abstraction** | Portability, setup automation, env detection |
| A4 | **Observability** | Health checks, discovery APIs, structured logging |
| A5 | **Documentation** | CLAUDE.md, AGENTS.md, anti-patterns, executable doc-tests |

## 3-Phase Workflow

```
ASSESS (Scout) → [user ✓] → TRANSFORM (per-dim) → [user ✓] → AUDIT (独立验证)
```

### Phase 1: ASSESS

1. AG detects project metadata: language, build system, entry points
2. AG dispatches **Scout** via task-delegate (read-only assessment)
3. AG reads Scout output → writes `maturity_report.md` (L0-L3 per dimension)
4. **✅ USER CHECKPOINT**: present maturity scores, ask which dimensions to transform

```bash
TRANSFORM_ID="{YYYYMMDD_HHMM}_{project_name}"
TRANSFORM_DIR="${HOME}/.agent-native-transform/${TRANSFORM_ID}/product"
mkdir -p "${TRANSFORM_DIR}/assess"

# Write Scout prompt (see SCOUT PROMPT below)
# Launch
bash ~/agent-skills/task-delegate/scripts/task_launch.sh \
  ${TRANSFORM_ID}_scout ${PROJECT_DIR} --backend cc
```

#### SCOUT PROMPT

```markdown
# Task: Assess Agent-Native Product Maturity

## Objective
Examine this project and assess its agent-facing interface maturity.
DO NOT modify any files. Read-only assessment.

## Project
- Path: {project_path}
- Language: {lang}

## Dimensions to Assess

### A2: API Surface
- L0: No CLI or API entry point
- L1: CLI exists, some --help
- L2: Consistent --help on all commands, standard exit codes
- L3: --json output on all commands, structured error objects, machine-parseable
Evidence: entry points, CLI frameworks, --help coverage, output formats

### A3: Environment Abstraction
- L0: Hardcoded paths, no setup
- L1: setup.sh or requirements.txt exists
- L2: Env vars for config, portable across machines
- L3: Auto-detect environment, declarative config, capability query
Evidence: setup scripts, hardcoded paths (grep /home/ /opt/ /data/), env vars

### A4: Observability
- L0: print() only
- L1: Logging framework present
- L2: Structured logging + health check command
- L3: Discovery APIs (list_*), error catalog, agent-queryable metrics
Evidence: logging config, health commands, list/discover functions

### A5: Documentation
- L0: No agent-facing docs
- L1: README exists
- L2: CLAUDE.md with module guide + anti-patterns
- L3: AGENTS.md + per-module docs + executable doc-tests + negative knowledge
Evidence: CLAUDE.md, AGENTS.md, docstrings, anti-pattern documentation

## Output Format
Write to {output_path}:

### {ID}: {Name}
**Level**: L{0-3}
**Evidence**: {specific files/patterns}
**Quick Win**: {easiest improvement}
**Key Gap**: {what's missing for next level}

## Summary Matrix
| Dimension | Current | Quick Win Available |
|-----------|---------|-------------------|
```

### Phase 2: TRANSFORM

AG processes selected dimensions. Recommended order: **A5 first** (docs are foundation),
then A2 (API), A4 (observability), A3 (environment).

Per dimension, AG:
1. Selects dimension-specific prompt
2. Injects project context + assessment findings
3. Dispatches Transformer via task-delegate
4. Reads output, verifies generated files
5. **✅ USER CHECKPOINT** per dimension

#### A5 TRANSFORM: Documentation

```markdown
# Task: Generate Agent-Facing Documentation

## Objective
Create CLAUDE.md and AGENTS.md for this project so that any AI coding agent
can immediately understand and work with the codebase.

## Project
- Path: {project_path}
- Language: {lang}
- Build system: {build}

## Assessment Findings
{A5 assessment from Scout}

## Actions

### 1. Generate CLAUDE.md (≤80 lines for complex, ≤40 for simple)
Structure:
- Project Overview (1-2 sentences)
- Module Hierarchy (table: Module | Role | Key Rule)
- Build Commands (exact, copy-pasteable)
- Critical Rules (2-5 items, include protected paths)
- File Conventions (auto-detect from project structure)

### 2. Generate AGENTS.md (cross-tool standard)
Same content adapted for AGENTS.md format. This is the emerging industry
standard (40K+ projects). Keep concise — closest-file-wins proximity rule.

### 3. Embed executable doc-tests
For every command listed in CLAUDE.md/AGENTS.md, add verify directives:
<!-- verify: {command} --dry-run -->
or
<!-- verify: command -v {tool} -->

These enable automated staleness detection.

## Constraints
- DO NOT modify application code
- Every path/command referenced must exist (verify with ls/test -f/command -v)
- Keep CLAUDE.md under {line_limit} lines
- Anti-patterns: use <!-- TODO: Add after real failures --> for section ⑤ if no incidents exist
- DO NOT fabricate anti-patterns or troubleshooting entries

## Output
Write generated files to the project directory. Write a summary to {output_path}:
- Files created (with purpose)
- Doc-test directives embedded (count)
- Paths verified (count)
- Anything that needs user input (protected paths, etc.)
```

#### A2 TRANSFORM: API Surface

```markdown
# Task: Audit and Improve API Surface for Agent Usability

## Objective
Audit this project's CLI/API for agent-friendliness and generate improvement
recommendations + quick fixes.

## Project
- Path: {project_path}
- Entry point: {detected_entry}

## Assessment Findings
{A2 assessment from Scout}

## Actions

### 1. CLI Audit (if CLI exists)
- Run {entry} --help and all subcommands --help
- Check: flag naming consistency, output format, exit codes, error messages
- Score each subcommand: consistent? structured output? good errors?

### 2. API Audit (if Python API exists)
- Check: unified entry point (api.py/__init__.py), type hints, docstrings
- Check: return type consistency (DataFrame? dict? mixed?)
- Check: error handling (unified exception hierarchy?)
- Check: smart defaults vs required params

### 3. Generate improvement plan
For each finding, categorize:
- 🟢 Quick fix (1-line change, e.g., add --json flag)
- 🟡 Medium effort (add structured error class)
- 🔴 Architectural (redesign return types)

### 4. Implement quick fixes (🟢 only)
If the fix is safe and obvious, implement it. Otherwise, document it.

## Constraints
- DO NOT change application logic
- DO NOT change function signatures without user approval
- Quick fixes only — document everything else as recommendations

## Output
Write to {output_path}:
- Audit results per command/function
- Improvement plan (categorized green/yellow/red)
- Files modified (if any quick fixes applied)
- Recommended next steps
```

#### A4 TRANSFORM: Observability

```markdown
# Task: Bootstrap Observability for Agent Self-Diagnosis

## Objective
Add minimal observability infrastructure so agents can self-diagnose issues.

## Actions
### 1. Health check command (if none exists)
- Create a `doctor` or `check` subcommand that verifies:
  * Dependencies installed
  * Config files present
  * Connectivity (if applicable)
- Output: structured (JSON verdict + per-check pass/fail)

### 2. Discovery functions (if Python API exists)
- Create `list_*()` functions for discovering available resources
- At minimum: list what data/configs/plugins exist

### 3. Error catalog (documentation)
- Document top-10 most common errors with: cause + fix
- Add to CLAUDE.md or separate error_catalog.md

## Constraints
- Keep health check lightweight (< 5s)
- Discovery functions must return structured data (list/dict), not print()
```

### Phase 3: AUDIT

**Executor ≠ Verifier**: Auditor runs on a DIFFERENT backend than Transformer.

```markdown
# Task: Independent Audit of Agent-Native Product Quality

## Rules
- DO NOT read transformation prompts or logs
- DO NOT trust claims — verify by execution
- You are a NEW agent encountering this project for the first time
- ONLY use the project's own docs and --help as guides

## Audit Checklist

### Documentation (A5)
- [ ] CLAUDE.md exists and correctly describes module structure
- [ ] All paths referenced in CLAUDE.md actually exist
- [ ] Build commands in CLAUDE.md work when copy-pasted
- [ ] AGENTS.md exists (if claimed)
- [ ] Doc-test directives (<!-- verify: -->) pass when executed

### API Surface (A2)
- [ ] Entry point --help works
- [ ] All listed subcommands have --help
- [ ] Flag names are consistent across commands
- [ ] Error messages are helpful (not raw tracebacks)

### Observability (A4)
- [ ] Health check command exists and produces structured output
- [ ] Discovery functions return meaningful data
- [ ] Error catalog covers common failure modes

### Cross-Dimension
- [ ] CLAUDE.md references match actual CLI commands
- [ ] Documented APIs actually exist and have correct signatures

## Scoring
Per dimension: L0-L3 based on what you VERIFIED (not claimed).
Include evidence for each score.

## Output
Write audit_report.md:
1. Per-dimension verified scores + evidence
2. Doc-test results (pass/fail per directive)
3. Critical issues (would confuse an agent)
4. Before/after maturity matrix
```

## Mandatory Rules

1. **ASSESS before TRANSFORM** — no generation without understanding current state
2. **User checkpoint after ASSESS** — user selects dimensions + targets
3. **User checkpoint after each TRANSFORM batch** — user reviews generated files
4. **Executor ≠ Verifier** — Auditor on different backend than Transformer
5. **No fabrication** — if no real failures exist, use `<!-- TODO: Add after real incidents -->`
6. **Verify all references** — every path/command in generated docs must actually exist
7. **CLAUDE.md length limit** — ≤40 lines simple project, ≤80 lines complex

## Anti-Patterns

```
❌ AG generates CLAUDE.md directly instead of dispatching subagent
   → AG is orchestrator. All file generation goes through task-delegate

❌ Fabricating anti-patterns or troubleshooting entries
   → Empty honesty > fabricated completeness. Use <!-- TODO --> markers

❌ Single monolithic "transform everything" prompt
   → Each dimension gets its own focused prompt

❌ Transformer and Auditor are the same subagent session
   → Violates Executor ≠ Verifier. Auditor must have fresh eyes

❌ Listing commands in CLAUDE.md without verifying they work
   → Every command must be tested with command -v or --help

❌ Generating 200-line CLAUDE.md for a 10-file project
   → Match doc size to project complexity. Overgeneration breeds staleness

❌ Skipping ASSESS and jumping to TRANSFORM
   → Without baseline, can't measure improvement or set targets
```

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Scout can't find CLI entry point | Specify in prompt: `--entry playground` or `--entry python -m pkg` |
| Generated CLAUDE.md references wrong paths | Re-run with `--verify` flag — Transformer must `ls` every path |
| Auditor scores lower than Transformer claimed | This is EXPECTED. Fix the gaps, don't argue with the auditor |
| Project has no CLI (library only) | Skip A2. Focus on A5 (documentation) and A4 (discovery API) |
| Doc-test verify directives fail | Either command changed or was wrong. Update CLAUDE.md |
| AGENTS.md conflicts with CLAUDE.md | AGENTS.md is cross-tool source of truth. CLAUDE.md adds Claude-specific info only |

## Composability

| Combination | Description |
|-------------|-------------|
| deep-analysis → agent-native-product | system_map.md feeds Phase 1 ASSESS |
| agent-native-product → agent-native-devflow | Product docs inform dev process setup |
| agent-native-product (audit only) | Re-run Phase 3 periodically to detect drift |
| sdk-audit → agent-native-product | Existing audit findings feed ASSESS |
