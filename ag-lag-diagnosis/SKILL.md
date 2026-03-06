---
name: ag-lag-diagnosis
description: Diagnose and fix Antigravity IDE Agent Manager lag/stalling. Covers streamAgentStateUpdates polling storms, oversized conversation .pb files, VERY LONG TASK renderer blocking, and memory leaks.
---

# AG IDE Lag Diagnosis & Fix

> **When to trigger**: User reports AG IDE edits stuck on "Working...", Agent Manager freezing, or general IDE sluggishness that resolves when switching to Editor view.

## Quick Diagnosis (Run All)

### Step 1: Find the latest log session

```bash
ls -lt ~/Library/Application\ Support/Antigravity/logs/ | head -3
# Use the most recent directory, e.g. 20260306T175017
# Set AG_LOG variable for subsequent commands
```

### Step 2: Check streamAgentStateUpdates polling storm

```bash
# Total error count
grep -c "streamAgentStateUpdates error" "$AG_LOG/agent-window-console.log"

# Which conversations are polling (sorted by count)
grep "streamAgentStateUpdates error" "$AG_LOG/agent-window-console.log" \
  | awk -F'error for ' '{print $2}' | awk -F: '{print $1}' \
  | sort | uniq -c | sort -rn
```

**Diagnosis**: If any single conversation has 100+ errors, it is in a polling death loop (~2s interval, no backoff). This is the #1 cause of lag.

### Step 3: Check VERY LONG TASK renderer blocking

```bash
grep "VERY LONG TASK" "$AG_LOG/rendererPerf.log" | tail -20
```

**Diagnosis**: Tasks >200ms block the UI. Tasks >500ms cause visible freezes. Tasks >1000ms cause multi-second hangs.

### Step 4: Check oversized conversation .pb files (remote workstation)

```bash
ssh workstation 'find ~/.gemini/antigravity/conversations -name "*.pb" -size +4M \
  -printf "%s %f\n" | sort -rn | head -20'
```

**Diagnosis**: Files >4MB exceed gRPC message limit and trigger `update is too large` errors, causing infinite spin.

### Step 5: Check process resource usage

```bash
ps axo pid,rss,pcpu,comm | grep -i antigravity | sort -k2 -rn | head -10
```

**Diagnosis**: Renderer processes >500MB RSS indicate memory leaks. CPU >20% on a Renderer indicates active polling storm.

---

## Fixes (In Order of Effectiveness)

### Fix 1: Archive oversized conversation .pb files

This is the most impactful fix. Move .pb files >4MB to an archive directory (preserves history, can restore later).

```bash
# Use the provided script
bash ag-lag-diagnosis/scripts/archive_large_conversations.sh
```

Or manually on the remote workstation:

```bash
mkdir -p ~/.gemini/antigravity/conversations_archive
find ~/.gemini/antigravity/conversations -name "*.pb" -size +4M \
  -exec mv {} ~/.gemini/antigravity/conversations_archive/ \;
```

> **IMPORTANT**: Before archiving, summarize conversation contents for user confirmation:
>
> ```bash
> for f in $(find ~/.gemini/antigravity/conversations -name "*.pb" -size +4M -printf "%f\n"); do
>   cid=${f%.pb}
>   echo "=== $cid ==="
>   head -5 ~/.gemini/antigravity/brain/$cid/task.md 2>/dev/null || echo "(no task.md)"
> done
> ```

**After archiving, restart AG IDE.**

### Fix 2: Restart AG IDE

Clears all orphan stream subscriptions and resets memory. This alone fixes polling storms temporarily, but they will recur if oversized .pb files remain.

### Fix 3: Enable GPU rasterization (macOS only)

Edit `~/.antigravity/argv.json` and add:

```json
{
    "enable-gpu-rasterization": true
}
```

Offloads rendering from CPU main thread to GPU, reducing VERY LONG TASK frequency.

### Fix 4: Reduce open workspaces

Each workspace window creates an independent cascadeId and starts polling. Close workspaces not actively used for agent operations.

### Fix 5: Restore archived conversations (if needed)

```bash
mv ~/.gemini/antigravity/conversations_archive/<conversation_id>.pb \
  ~/.gemini/antigravity/conversations/
```

---

## Root Cause Summary

| Layer | Problem | Mechanism |
|-------|---------|-----------|
| gRPC transport | Conversation .pb >4MB exceeds message limit | Backend drops payload → frontend retries forever |
| Agent Manager | `streamAgentStateUpdates` has no exponential backoff | Orphan/failed conversations polled every ~2s indefinitely |
| Renderer | Polling + artifact resolution errors saturate event loop | VERY LONG TASK blocks Webview message consumption |
| Memory | Renderer processes leak over time (1GB+ after 18h) | GC pauses compound with above issues |

## Anti-Patterns

```
❌ Only restarting AG IDE without archiving .pb files
   → Polling storms WILL recur within hours. Archive >4MB files FIRST, then restart

❌ Deleting .pb files instead of archiving them
   → Move to conversations_archive/, don't delete. User may want to restore later

❌ Diagnosing lag without checking ALL 5 steps
   → Multiple causes are often active simultaneously. Run ALL diagnosis steps before fixing

❌ Archiving .pb files without user confirmation
   → ALWAYS show conversation summaries (task.md) and get user approval before moving files

❌ Assuming lag is a network issue
   → AG lag is almost always caused by local polling storms or oversized .pb files, not network

❌ Running diagnosis on the remote workstation when logs are on macOS
   → AG logs are in ~/Library/... on macOS, but .pb files are on the remote workstation. Check both
```

## Mandatory Rules

1. **Confirm before archiving**: Always show conversation summaries before moving .pb files
2. **Archive, don't delete**: Move .pb files to `conversations_archive/`, never `rm`
3. **Restart after archive**: AG IDE must be restarted after archiving for changes to take effect

## Prevention

- Archive conversations >4MB weekly
- Restart AG IDE daily
- Keep open workspace count to ≤3
- Monitor with: `grep -c "streamAgentStateUpdates error" $AG_LOG/agent-window-console.log`
