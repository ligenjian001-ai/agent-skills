---
name: tmux-protocol
description: MANDATORY terminal command protocol via tmux with PS1-based automatic markers. MUST be read before ANY terminal operation.
---

# Tmux Terminal Protocol

> **CRITICAL**: Every terminal command MUST go through tmux.
> Direct `run_command` for work commands (ssh, docker, python3, make, etc.) is FORBIDDEN.
>
> See `AG_TERMINAL_BEHAVIOR.md` in this directory for platform constraints and history.

## Session Setup (once per conversation)

Derive session ID from artifact directory path, e.g. `brain/ffe43b43-...` → `ffe43b43`.

```bash
bash /home/lgj/agent-skills/tmux-protocol/scripts/init_session.sh {id}
```

- `SafeToAutoRun=true`
- `WaitMsBeforeAsync=3000`
- `waitForPreviousTools=true`

> [!CAUTION]
> **ALWAYS use `init_session.sh`** — NEVER run bare `tmux new-session` directly.
> Bare tmux commands produce no stdout → `run_command` backgrounds them → conversation hangs.
> The script outputs `TMUX_SESSION_READY: {id}` so `run_command` completes normally.

## Shell Environment

`~/.bashrc` auto-detects agent tmux sessions and activates **dumb terminal mode**:

- `TERM=dumb`, no conda init, no color, no PROMPT_COMMAND
- `PS1='AG_READY:${?}:$ '` — **automatic marker with exit code**

## PS1 Marker Protocol

Every command's completion is **automatically detected** via the shell prompt.
You do NOT need to wrap commands with special markers.

### 1. SEND a command

Just send it. No wrapping needed:

```bash
tmux send-keys -t {id} 'ls -la' Enter
```

### 2. READ output (interpret PS1 markers)

```bash
tmux capture-pane -t {id} -p -S -30
```

Look at the **last non-empty line** of the pane:

| What you see | State | Meaning |
|---|---|---|
| `AG_READY:0:$` (cursor here) | **DONE — success** | Command finished, exit code 0 |
| `AG_READY:N:$` (N ≠ 0) | **DONE — failed** | Command finished, exit code N |
| No `AG_READY` after command | **RUNNING** | Command still executing |
| Command text not visible | **PENDING** | send-keys not delivered yet |

### 3. Examples

**Successful command:**

```
AG_READY:0:$ ls -la
total 4
drwxr-xr-x 2 lgj lgj 4096 ...
AG_READY:0:$              ← DONE, exit 0
```

**Failed command:**

```
AG_READY:0:$ ls /nonexistent
ls: cannot access '/nonexistent': No such file or directory
AG_READY:2:$              ← DONE, exit 2
```

**Running command (captured during execution):**

```
AG_READY:0:$ make -j8
[ 12%] Building CXX...
[ 25%] Building CXX...
                          ← no AG_READY = still running
```

### 4. Complex and Long Commands

For commands with special characters or that take >10 seconds, use script mode:

```
write_to_file("/tmp/ag_task.sh", "pip install pandas && python3 process.py 2>&1")
tmux send-keys -t {id} 'bash /tmp/ag_task.sh' Enter
```

Then capture-pane periodically. RUNNING state with partial output is expected.

## Mandatory Rules

1. **ALWAYS set `waitForPreviousTools=true`** on EVERY tmux `run_command`. Still best practice even though PS1 markers provide self-synchronization.
2. **Keep commands SHORT.** For long sequences, write a script file first.
3. **For file creation**: Use `write_to_file` / `create_file` tools. NEVER use `send-keys` to write file content.
4. **Interpret PS1 markers before acting.** Check the last line of capture-pane output for `AG_READY`.

## Anti-Patterns

```
❌ HANG: Heredoc / multi-line file content via send-keys
    tmux send-keys -t {id} 'cat << EOF > file' Enter
    → pane permanently stuck

❌ WRONG: Retrying a command that already succeeded (background with exit 0)
    → check exit code first

❌ WRONG: Bypassing tmux during error recovery / fallbacks
    → ALL commands go through tmux, no exceptions
```

## Background Recovery

If `run_command` returns a "Background command ID":

**First check: did it already succeed?**

- **Exit code 0** → command succeeded. Do NOT retry. Proceed.
- **Still running** → wait, then use `command_status` to check.
- **Non-zero exit** → diagnose before retrying.

```
✅ Background with Exit code 0 → just proceed, don't retry
❌ WRONG: Background with Exit code 0 → "Got background, let me retry"
```

## run_command Hang Recovery

`run_command` calls may intermittently hang (stuck RUNNING). This is an AG framework scheduling bug. It can happen on the **first command** in a conversation — no prior cancel required.

**Symptoms**: `run_command` shows RUNNING indefinitely. The command itself is instant in bash.

**What to do**:

1. ✅ **Tell the user**: suggest cancel + continue (resets AG scheduling state)
2. ✅ Continue with non-terminal tools (`view_file`, `write_to_file`, `grep_search`)
3. If repeated cancel+continue fails, suggest starting a new conversation

See `AG_TERMINAL_BEHAVIOR.md` Section 11 for full analysis.

## Large Output

For commands with large output, use one of:

- `tmux capture-pane -t {id} -p -S -10000` (capture more lines)
- `tee /tmp/build.log` inside the command + `view_file /tmp/build.log`
