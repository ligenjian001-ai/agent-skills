#!/bin/bash
# task_extract.sh — Extract assistant text output from CC/Codex live.log
#
# Usage: task_extract.sh <task_id> [OPTIONS]
#
# Options:
#   --task-dir DIR        Override task directory (default: ~/.task-delegate/<task_id>)
#   --output-file PATH    Write output to file (default: stdout)
#   --result-only         Only extract the final result text (faster, less output)
#
# Parses live.log (stream-json format), extracts assistant text blocks,
# and produces clean markdown output suitable for further processing.
#
# Uses Python for reliable JSON parsing of very long lines.

set -euo pipefail

TASK_ID="${1:?Usage: task_extract.sh <task_id> [OPTIONS]}"
TASK_DIR=""
OUTPUT_FILE=""
RESULT_ONLY=false

shift 1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-dir) TASK_DIR="$2"; shift 2 ;;
    --output-file) OUTPUT_FILE="$2"; shift 2 ;;
    --result-only) RESULT_ONLY=true; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# Resolve task directory
if [[ -z "$TASK_DIR" ]]; then
  TASK_DIR="$HOME/.task-delegate/$TASK_ID"
fi

LIVE_LOG="$TASK_DIR/live.log"

if [[ ! -f "$LIVE_LOG" ]]; then
  echo "ERROR: live.log not found at $LIVE_LOG" >&2
  exit 1
fi

# Python extraction — handles arbitrarily long JSON lines
python3 -c "
import json, sys

result_only = '$RESULT_ONLY' == 'true'
output = []

with open('$LIVE_LOG', 'r', encoding='utf-8') as f:
    for line in f:
        line = line.strip()
        if not line or not line.startswith('{'):
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue

        msg_type = obj.get('type', '')

        if msg_type == 'result' and not obj.get('is_error', False):
            # Final result — this is the most reliable output
            result_text = obj.get('result', '')
            if result_text:
                output.append(result_text)

        elif msg_type == 'assistant' and not result_only:
            content = obj.get('message', {}).get('content', [])
            for block in content:
                if isinstance(block, dict) and block.get('type') == 'text':
                    text = block.get('text', '')
                    if text.strip():
                        output.append(text)

# Deduplicate: result line often duplicates last assistant text
# Keep only unique blocks
seen = set()
deduped = []
for block in output:
    key = block[:200]  # compare first 200 chars
    if key not in seen:
        seen.add(key)
        deduped.append(block)

print('\n'.join(deduped))
" > "${OUTPUT_FILE:-/dev/stdout}" 2>/dev/null

if [[ -n "$OUTPUT_FILE" ]]; then
  bytes=$(wc -c < "$OUTPUT_FILE")
  lines=$(wc -l < "$OUTPUT_FILE")
  echo "EXTRACT_DONE: $lines lines, $bytes bytes → $OUTPUT_FILE" >&2
fi
