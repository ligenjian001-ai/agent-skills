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

> [!IMPORTANT]
> **A1 (API Quality) is a prerequisite.** If the underlying API has poor orthogonality,
> incomplete conceptual models, or missing convenience layers, then agent-native docs and
> tooling built on top will be fragile — agents will hit the same friction regardless of
> how good the docs are. Assess A1 first; if it scores L0-L1, prioritize API refactoring
> over documentation generation.

## Dimensions

| ID | Dimension | What It Means | Prerequisite? |
|----|-----------|---------------|---------------|
| A1 | **API Quality** | Orthogonality, conceptual model, layering | **Yes — assess first** |
| A2 | **API Surface** | CLI/API consistency, structured output, error design | Depends on A1 |
| A3 | **Environment Abstraction** | Portability, setup automation, env detection | No |
| A4 | **Observability** | Health checks, discovery APIs, structured logging | No |
| A5 | **Documentation** | CLAUDE.md, AGENTS.md, anti-patterns, executable doc-tests | Depends on A1 |
| A6 | **Agent Trial** _(optional)_ | End-to-end agent walkthrough, friction log collection | No |

### A1: API Quality — Detailed Criteria

APIs should fall into two clear layers:

- **Foundation layer**: Orthogonal, parameter-rich, high-cohesion/low-coupling, complete conceptual model
- **Convenience layer**: Covers Top-5 user workflows in minimal code (1-3 lines)

| Level | Foundation Layer | Convenience Layer |
|-------|-----------------|--------------------|
| **L0** | No clear module boundaries; functions do multiple unrelated things | No high-level helpers |
| **L1** | Basic modules exist but concepts overlap (e.g., fill vs order vs round-trip conflated) | Some helpers, but incomplete |
| **L2** | Orthogonal APIs; clear conceptual model; each function has single responsibility | Top-5 workflows covered |
| **L3** | L2 + composable (APIs chain naturally); result objects have typed sub-views | Top-5 workflows are 1-liners |

**Assessment checklist** (for Scout):

1. **Conceptual model**: Are domain concepts (e.g., order/fill/round-trip, raw data/bar/feature) distinct types or conflated?
2. **Orthogonality**: Can you change one concern (e.g., data source) without touching another (e.g., strategy logic)?
3. **Parameter richness**: Do functions expose enough knobs, or are behaviors hardcoded?
4. **Implicit dependencies**: Do modules secretly depend on fields injected elsewhere? (e.g., `time` field in aggTrade)
5. **Error design**: Do functions fail clearly when inputs are wrong, or silently produce garbage?
6. **Convenience coverage**: What % of the Top-5 user workflows require <3 lines? >10 lines? >50 lines?

> [!NOTE]
> **A6 is optional.** Include it when: (1) the project has a runnable workflow,
> (2) you want to catch runtime-only issues that static assessment misses.
> Smoke tests on quant_trading showed the most severe bugs (ZeroDivisionError,
> wrong column names, EOD state traps) were invisible to code reading.

## Prompt Files

All subagent prompts live in `prompts/`. AG reads the template, fills `{{PLACEHOLDERS}}`,
and passes the result to task-delegate.

| File | Used By | Placeholders |
|------|---------|-------------|
| `scout.txt` | Phase 1 Scout | `PROJECT_PATH`, `LANGUAGE`, `AGENT_TRIAL_SECTION`, `OUTPUT_PATH` |
| `scout_a6_agent_trial.txt` | Injected into Scout when A6 enabled | _(none — paste as-is into `AGENT_TRIAL_SECTION`)_ |
| `transform_a1_api_quality.txt` | Phase 2 A1 Transformer | `PROJECT_PATH`, `LANGUAGE`, `ENTRY_POINT`, `A1_ASSESSMENT`, `OUTPUT_PATH` |
| `transform_a5_docs.txt` | Phase 2 A5 Transformer | `PROJECT_PATH`, `LANGUAGE`, `BUILD_SYSTEM`, `A5_ASSESSMENT`, `LINE_LIMIT`, `OUTPUT_PATH` |
| `transform_a2_api.txt` | Phase 2 A2 Transformer | `PROJECT_PATH`, `ENTRY_POINT`, `A2_ASSESSMENT`, `OUTPUT_PATH` |
| `transform_a4_observability.txt` | Phase 2 A4 Transformer | `PROJECT_PATH`, `A4_ASSESSMENT`, `OUTPUT_PATH` |
| `auditor.txt` | Phase 3 Auditor | _(no placeholders — auditor uses project's own docs)_ |
| `friction_log_template.txt` | Referenced by Scout A6 + Auditor | _(template only — not a prompt)_ |

## 3-Phase Workflow

```
ASSESS (Scout) → [user ✓] → TRANSFORM (per-dim) → [user ✓] → AUDIT (独立验证)
```

### Phase 1: ASSESS

1. AG detects project metadata: language, build system, entry points
2. AG prepares Scout prompt from `prompts/scout.txt`:
   - Fill `{{PROJECT_PATH}}`, `{{LANGUAGE}}`, `{{OUTPUT_PATH}}`
   - If A6 enabled: read `prompts/scout_a6_agent_trial.txt` and inject into `{{AGENT_TRIAL_SECTION}}`
   - If A6 disabled: replace `{{AGENT_TRIAL_SECTION}}` with empty string
3. AG dispatches **Scout** via task-delegate (read-only assessment)
4. AG reads Scout output → writes `maturity_report.md` (L0-L3 per dimension)
5. **✅ USER CHECKPOINT**: present maturity scores, ask which dimensions to transform

```bash
TRANSFORM_ID="{YYYYMMDD_HHMM}_{project_name}"
TRANSFORM_DIR="${HOME}/.agent-native-transform/${TRANSFORM_ID}/product"
mkdir -p "${TRANSFORM_DIR}/assess"

# AG reads prompts/scout.txt, fills placeholders, writes to task dir
# Launch via task-delegate
bash ~/agent-skills/task-delegate/scripts/task_launch.sh \
  ${TRANSFORM_ID}_scout ${PROJECT_DIR} --backend cc
```

### Phase 2: TRANSFORM

AG processes selected dimensions. Recommended order: **A1 first** (API quality is foundation),
then A5 (docs), A2 (surface), A4 (observability), A3 (environment).

Per dimension, AG:
1. Reads the dimension-specific prompt from `prompts/transform_{dim}.txt`
2. Fills placeholders with project context + assessment findings
3. Dispatches Transformer via task-delegate
4. Reads output, verifies generated files
5. **✅ USER CHECKPOINT** per dimension

### Phase 3: AUDIT

**Executor ≠ Verifier**: Auditor runs on a DIFFERENT backend than Transformer.

AG reads `prompts/auditor.txt` and dispatches the Auditor. The auditor prompt has
expanded checks that align with A5 mandatory documentation items and A6 Agent Trial.

## Friction Log Standard

> [!TIP]
> The standard friction log format is defined in `prompts/friction_log_template.txt`.
> It is used by Scout (A6 sub-task) and Auditor (A6 audit). AG should also use this
> format when documenting friction from any manual testing.

Severity classification:
- 🔴 **Blocker**: Crashes, data loss, cannot proceed
- 🟡 **Misleading**: Docs say X but reality is Y
- 🟢 **Missing**: Feature absent, user writes boilerplate
- ⚪ **Friction**: Works but confusing or surprising

## Mandatory Rules

1. **ASSESS before TRANSFORM** — no generation without understanding current state
2. **User checkpoint after ASSESS** — user selects dimensions + targets
3. **User checkpoint after each TRANSFORM batch** — user reviews generated files
4. **Executor ≠ Verifier** — Auditor on different backend than Transformer
5. **No fabrication** — if no real failures exist, use `<!-- TODO: Add after real incidents -->`
6. **Verify all references** — every path/command in generated docs must actually exist
7. **CLAUDE.md length limit** — ≤40 lines simple project, ≤80 lines complex
8. **Prompts in files** — all subagent prompts live in `prompts/`, not inline in SKILL.md

## Anti-Patterns

```
❌ AG generates CLAUDE.md directly instead of dispatching subagent
   → AG is orchestrator. All file generation goes through task-delegate

❌ Fabricating anti-patterns or troubleshooting entries
   → Empty honesty > fabricated completeness. Use <!-- TODO --> markers

❌ Single monolithic "transform everything" prompt
   → Each dimension gets its own focused prompt file

❌ Transformer and Auditor are the same subagent session
   → Violates Executor ≠ Verifier. Auditor must have fresh eyes

❌ Listing commands in CLAUDE.md without verifying they work
   → Every command must be tested with command -v or --help

❌ Generating 200-line CLAUDE.md for a 10-file project
   → Match doc size to project complexity. Overgeneration breeds staleness

❌ Skipping ASSESS and jumping to TRANSFORM
   → Without baseline, can't measure improvement or set targets

❌ Inlining prompts in SKILL.md instead of using prompts/ files
   → Prompts are versioned separately, easier to iterate

❌ Skipping A6 Agent Trial when user opted in, reporting only static assessment
   → Static reading misses runtime-only bugs (ZeroDivisionError, state traps, wrong column names)
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
| A6 Agent Trial takes too long | Set a time/friction-count cap in Scout prompt. Stop at 10 friction points |

## Composability

| Combination | Description |
|-------------|-------------|
| deep-analysis → agent-native-product | system_map.md feeds Phase 1 ASSESS |
| agent-native-product → agent-native-devflow | Product docs inform dev process setup |
| agent-native-product (audit only) | Re-run Phase 3 periodically to detect drift |
| sdk-audit → agent-native-product | Existing audit findings feed ASSESS |
| smoke-test → agent-native-product | Friction log from external test feeds ASSESS + TRANSFORM |
