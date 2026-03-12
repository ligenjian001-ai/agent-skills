#!/bin/bash
# task_status.sh — Live progress check for running tasks
#
# Usage: task_status.sh <task_id>
#
# Designed for AG's monitoring loop. Outputs a clean progress summary
# by parsing live.log (stream-JSON) and extracting recent assistant actions.
# AG should run this every 60-90s and relay the output to the user.

set -euo pipefail

TASK_ID="${1:?Usage: task_status.sh <task_id>}"
TASK_DIR="$HOME/.task-delegate/$TASK_ID"
LIVE_LOG="$TASK_DIR/live.log"
RECORD="$TASK_DIR/execution_record.json"

# --- Check completion first ---
if [[ -f "$RECORD" ]]; then
  python3 -c "
import json
r = json.load(open('$RECORD'))
status = r.get('status', 'unknown')
dur = r.get('duration_seconds', 0)
icon = '✅' if status == 'success' else '❌'
print(f'{icon} COMPLETED | status={status} | duration={dur}s | exit_code={r.get(\"exit_code\", \"?\")}')
"
  exit 0
fi

# --- Check if live.log exists ---
if [[ ! -f "$LIVE_LOG" ]]; then
  echo "⏳ WAITING | live.log not yet created"
  exit 0
fi

# --- Check if tmux session alive ---
SESSION="task-${TASK_ID}"
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "💀 DEAD | tmux session gone, no execution_record.json"
  exit 1
fi

# --- Extract recent progress from live.log ---
export LIVE_LOG_PATH="$LIVE_LOG"
python3 << 'PYEOF'
import json, os, sys, time

live_log = os.environ["LIVE_LOG_PATH"]
now = time.time()

# Parse recent assistant messages and tool uses
recent_texts = []
recent_tools = []
total_lines = 0
errors = []

with open(live_log, 'r', encoding='utf-8') as f:
    for line in f:
        total_lines += 1
        line = line.strip()
        if not line or not line.startswith('{'):
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue

        msg_type = obj.get('type', '')

        if msg_type == 'assistant':
            content = obj.get('message', {}).get('content', [])
            for block in content:
                if isinstance(block, dict):
                    if block.get('type') == 'text':
                        text = block.get('text', '').strip()
                        if text and len(text) > 10:
                            # Keep last 200 chars as summary
                            recent_texts.append(text[:200])
                    elif block.get('type') == 'tool_use':
                        tool_name = block.get('name', '?')
                        tool_input = block.get('input', {})
                        # Extract key info from tool calls
                        if tool_name in ('write_to_file', 'edit_file', 'Replace', 'WriteToFile'):
                            path = tool_input.get('file_path', tool_input.get('path', '?'))
                            recent_tools.append(f"✏️  {tool_name}: {os.path.basename(str(path))}")
                        elif tool_name in ('bash', 'execute_command', 'Bash'):
                            cmd = str(tool_input.get('command', tool_input.get('cmd', '?')))[:80]
                            recent_tools.append(f"🔧 {tool_name}: {cmd}")
                        elif tool_name in ('read_file', 'ReadFile', 'Read'):
                            path = tool_input.get('file_path', tool_input.get('path', '?'))
                            recent_tools.append(f"👁️  read: {os.path.basename(str(path))}")
                        else:
                            recent_tools.append(f"🔧 {tool_name}")

        elif msg_type == 'result':
            if obj.get('is_error', False):
                errors.append(obj.get('error', 'unknown error')[:100])

# Calculate log age
log_mtime = os.path.getmtime(live_log)
age_s = int(now - log_mtime)

# Output summary
print(f"⏳ RUNNING | log_lines={total_lines} | last_update={age_s}s ago")

if age_s > 300:
    print(f"⚠️  WARNING: No output for {age_s}s — may be stalled")

if errors:
    print(f"❌ ERRORS ({len(errors)}):")
    for e in errors[-3:]:  # last 3 errors
        print(f"   {e}")

if recent_tools:
    print(f"🔧 Recent actions ({len(recent_tools)} total):")
    for t in recent_tools[-5:]:  # last 5 tool calls
        print(f"   {t}")

if recent_texts:
    print(f"💬 Latest assistant text:")
    # Show last text block, truncated
    last = recent_texts[-1]
    print(f"   {last}")
PYEOF

PYEOF_RESULT=$?
if [[ $PYEOF_RESULT -ne 0 ]]; then
  echo "⚠️  Could not parse live.log"
fi
