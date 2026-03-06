# Agent Skills — Project Rules

## CONVERSATION JOURNAL — AUTO-START

**NON-NEGOTIABLE**: At the START of every conversation, after skill bootstrap, AG MUST:

1. Read `/home/lgj/agent-skills/ag-archive/SKILL.md` → Conversation Journal Protocol
2. Create `<appDataDir>/brain/<conversation-id>/conversation_journal.md` with the user's first message recorded **verbatim**
3. This takes priority over all other actions — **record first, then work**

The journal is NOT for celebrating progress (that's `walkthrough.md`'s job). The journal exists to:

- **Preserve the user's original intent** — the first message defines the objective
- **Track recurring errors and pain points** — patterns of repeated mistakes are the most valuable data
- **Enable daily/weekly work report compilation** — conversations are the raw material for structured retrospectives
- **Support continuous strategic improvement** — decision context that is otherwise lost when conversations truncate
