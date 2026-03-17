---
name: api-design-audit
description: "Audit API design proposals against user's design preferences. Evaluates 7 checkpoints (raw data preservation, metric justification, core concept, data constraints, minimal state, additive design, market transparency). Trigger: 'audit this API design', '审计API设计', 'review this proposal'."
---

# API Design Audit

> **ROLE**: AG reads the proposed API design and evaluates it against 7 verifiable checkpoints derived from the user's design preferences. AG produces a structured audit report with PASS/NEEDS WORK/FAIL verdict and actionable suggestions.

## When to Trigger

- AG or a subagent (CC/Codex) proposes a new API design
- User asks "审计一下这个设计" / "review this proposal"
- Before presenting any API design to the user for approval

---

## Operational Workflow

### Phase 1: Collect the Design Under Review

Identify the API design to audit. It can be:
- A file path (e.g., `output.md` from a CC/Codex task)
- A section of conversation (user or AG proposed something)
- An issue body or implementation plan

Read the full design. Extract:
1. **What new types/enums/structs are introduced** (if any)
2. **What new methods are added** (to which classes)
3. **What existing data is modified or wrapped**
4. **What the design claims to solve**

### Phase 2: Run the 7-Checkpoint Audit

Evaluate each checkpoint independently. For each, cite specific evidence from the design.

#### C1: Raw Data Preservation ⭐ (CRITICAL)

> Does the design modify, replace, or wrap the original event types/fields?

| Verdict | Criteria |
|---------|----------|
| ✅ PASS | Original `ORDER`, `TRADE`, `OrderData`, `TransData` types are untouched. New API is additive |
| ❌ FAIL | Design introduces new enums/structs that re-classify events (e.g., `UserAction::CANCEL` replacing `TRADE(CANCEL)`) |

**Example FAIL**: CC's `UserAction` enum mapped `TRADE(CANCEL)` → `UserAction::CANCEL`, replacing the raw event classification.

#### C2: Metric Justification

> Can every new abstraction name a specific metric it helps compute?

| Verdict | Criteria |
|---------|----------|
| ✅ PASS | Each new method/struct has a named use case (e.g., "`IsSessionConfirmed()` enables computing passive rel_vol at the right moment") |
| ❌ FAIL | Abstractions exist "for completeness" or "future use" without a named metric |

**Test**: For each new API element, ask: "What metric does this help compute?" If the answer is vague ("provides a unified view"), it fails.

#### C3: Single Core Concept ⭐ (CRITICAL)

> Does the design have one clear C-position idea, or is it a flat list of utilities?

| Verdict | Criteria |
|---------|----------|
| ✅ PASS | There is one organizing concept that explains when/how all other elements become valid |
| ❌ FAIL | Design is a list of 5+ independent methods/helpers with no unifying principle |

**Example PASS**: `IsSessionConfirmed()` is the single concept; everything else (`GetSessionOrder()`, `GetSessionTransList()`) only makes sense at confirm time.
**Example FAIL**: `GetTicksFromBest()`, `IsAggressive()`, `IsEventCancel()`, `GetPreBestBid()` as a flat list.

#### C4: Data Constraint Grounding

> Is the design built from actual data-layer constraints upward?

| Verdict | Criteria |
|---------|----------|
| ✅ PASS | Design explicitly addresses known data constraints (e.g., SSE Incremental Volume, SZ TRADE(CANCEL) vs SH ORDER(DELETE)) |
| ❌ FAIL | Design assumes ideal/uniform data semantics across markets |

**Test**: Can the design handle SH stock data where ORDER(ADD) volume is already post-fill? If not addressed, it fails.

#### C5: Minimal Stored State

> Does the design avoid redundant state when values can be derived?

| Verdict | Criteria |
|---------|----------|
| ✅ PASS | No new stored fields that duplicate information derivable from existing data |
| ❌ FAIL | Design stores pre/post book state, cached prices, or redundant copies of raw event data |

**Example FAIL**: Codex's `OrderFlowEvent` stored `pre_best_bid`, `pre_best_ask`, `post_best_bid`, `post_best_ask` — all derivable at query time.

#### C6: Additive Not Replacement

> Does the design add methods to existing classes, or introduce a new type system?

| Verdict | Criteria |
|---------|----------|
| ✅ PASS | New API consists of methods on `OrderBook` / free functions on `MarketEvent` |
| ❌ FAIL | Design introduces new wrapper types (e.g., `OrderFlowEvent`, `SessionInfo`) that agents must use instead of raw types |

**Key distinction**: `bool OrderBook::IsSessionConfirmed()` ✅ vs `struct OrderFlowEvent { FlowAction action; ... }` ❌

#### C7: Market Difference Transparency

> Are market-specific differences expressed as different rules under a unified concept?

| Verdict | Criteria |
|---------|----------|
| ✅ PASS | One concept (e.g., "session confirm"), different rules per market listed explicitly |
| ❌ FAIL | Market differences hidden behind a single uniform API that pretends SH == SZ |

**Example PASS**: `IsSessionConfirmed()` with explicit per-market confirm rules table.
**Example FAIL**: A single `GetSessionAction()` that returns the same enum for both markets, masking timing differences.

### Phase 3: Produce the Audit Report

Write the report in this format:

```markdown
## API Design Audit Report

**Design**: {design name or source}
**Date**: {YYYY-MM-DD}
**Overall**: ✅ PASS / ⚠️ NEEDS WORK / ❌ FAIL

| # | Check | Verdict | Evidence |
|---|-------|---------|----------|
| C1 | Raw Data Preservation | ✅/❌ | {one-line evidence} |
| C2 | Metric Justification | ✅/❌ | {one-line evidence} |
| C3 | Single Core Concept | ✅/❌ | {one-line evidence} |
| C4 | Data Constraint Grounding | ✅/❌ | {one-line evidence} |
| C5 | Minimal Stored State | ✅/❌ | {one-line evidence} |
| C6 | Additive Not Replacement | ✅/❌ | {one-line evidence} |
| C7 | Market Difference Transparency | ✅/❌ | {one-line evidence} |

### Suggestions
1. {actionable suggestion with specific fix}
2. ...
```

### Phase 4: Apply Verdict

| Condition | Verdict |
|-----------|---------|
| All 7 ✅ | ✅ **PASS** — present to user |
| 1-2 ❌, but C1 and C3 both ✅ | ⚠️ **NEEDS WORK** — suggest fixes, iterate |
| 3+ ❌, or C1 ❌, or C3 ❌ | ❌ **FAIL** — redesign needed |

---

## Mandatory Rules

1. **ALWAYS run the audit BEFORE presenting an API design to the user.** If AG or a subagent produces a design, audit it first.
2. **C1 (Raw Data) and C3 (Core Concept) are hard gates.** Either one failing = overall FAIL, no exceptions.
3. **Cite specific evidence.** "Looks fine" is not evidence. Quote the specific new type/method/field.
4. **Do NOT skip checkpoints.** All 7 must be evaluated even if the first 3 pass.
5. **The audit report goes to the user.** Don't silently audit and present only the design — show the audit results too.

---

## Anti-Patterns

❌ Skipping audit because "the design is obviously good"
   → Every design gets audited. The user's own Session Confirm design would pass; CC/Codex proposals would not. The audit catches what feels natural but violates principles.

❌ Giving a PASS verdict with vague evidence ("design seems additive")
   → Evidence must name specific types/methods. "No new enums introduced, only `IsSessionConfirmed()` method added to `OrderBook`" is proper evidence.

❌ Auditing only the parts AG proposed, ignoring subagent additions
   → Audit the FULL design including any methods, types, or state added by CC/Codex.

❌ Treating all 7 checks as equal weight
   → C1 and C3 are hard gates. A design that fails either should be redesigned, not patched.

❌ Using the audit to block iteration
   → ⚠️ NEEDS WORK is a valid outcome. Give specific suggestions and iterate. Don't let perfect be the enemy of good.

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Design is too vague to audit (no concrete API surface) | Ask the designer to specify: what new types? what new methods? on which classes? |
| Checkpoint seems inapplicable (e.g., C7 for single-market design) | Mark as ✅ N/A with explanation. Single-market designs pass C7 trivially. |
| Subagent ignored audit feedback and re-proposed same design | Re-run audit, highlight unchanged violations, escalate to user |
| Multiple valid core concepts (C3 ambiguous) | Ask: which ONE concept, if removed, would make the rest meaningless? That's the core. |
| User explicitly wants to violate a checkpoint | Record user override in audit report: "C{N}: ❌ (user override: {reason})" |

---

## Reference

The 7 checkpoints are derived from:
- [user_api_design_preferences.md](file:///home/lgj/hft_build/docs/user_api_design_preferences.md) — CC-authored style guide based on Session Confirm design process
- Issue #83 — the concrete case that revealed these preferences
