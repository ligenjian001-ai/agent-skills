#!/bin/bash
# panel_extract_output.sh — Post-run hook for panel discussion: extract output.md from live.log
#
# Called by task_launch.sh --post-run after backend completes.
# Arguments: $1 = task_dir  $2 = backend  $3 = status
#
# Produces: $task_dir/output.md

set -euo pipefail

TASK_DIR="$1"
BACKEND="$2"
STATUS="$3"

LIVE_LOG="${TASK_DIR}/live.log"
OUTPUT_FILE="${TASK_DIR}/output.md"

if [[ ! -f "$LIVE_LOG" ]]; then
  echo "[panel-extract] No live.log found, skipping output extraction"
  exit 0
fi

case "$BACKEND" in
  cc)
    # Extract text content from CC stream-json output
    if command -v python3 &>/dev/null; then
      python3 -c "
import json, sys

text_parts = []
for line in open('${LIVE_LOG}'):
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
        if obj.get('type') == 'result':
            text_parts.append(obj.get('result', ''))
        elif obj.get('type') == 'assistant' and 'content' in obj:
            for block in obj['content']:
                if block.get('type') == 'text':
                    text_parts.append(block['text'])
    except (json.JSONDecodeError, KeyError, TypeError):
        pass

# Use result if available, otherwise concatenate assistant text
if text_parts:
    has_result = any('\"type\":\"result\"' in l for l in open('${LIVE_LOG}'))
    print(text_parts[-1] if has_result else '\n'.join(text_parts))
else:
    print('[No structured output extracted. Check live.log]')
" > "$OUTPUT_FILE" 2>/dev/null || cp "$LIVE_LOG" "$OUTPUT_FILE"
    else
      cp "$LIVE_LOG" "$OUTPUT_FILE"
    fi
    ;;
  gemini|codex|deepseek|*)
    # Strip log/noise lines, keep content
    grep -v '^\[task-launch\]' "$LIVE_LOG" \
      | grep -v '^---$' \
      | grep -v '^\[WARN\]' \
      | grep -v '^Approval mode' \
      > "$OUTPUT_FILE" || cp "$LIVE_LOG" "$OUTPUT_FILE"
    ;;
esac

echo "[panel-extract] Output extracted to ${OUTPUT_FILE} ($(wc -l < "$OUTPUT_FILE") lines)"
