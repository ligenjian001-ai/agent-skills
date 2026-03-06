#!/usr/bin/env bash
# archive_large_conversations.sh
# Move oversized AG IDE conversation .pb files (>4MB) to an archive directory.
# Files are NOT deleted — they can be restored by moving them back.
#
# Usage:
#   bash archive_large_conversations.sh [threshold_mb]
#   Default threshold: 4 (MB)
#
# Run ON the workstation (or via ssh workstation 'bash ...')

set -euo pipefail

THRESHOLD_MB="${1:-4}"
CONV_DIR="$HOME/.gemini/antigravity/conversations"
ARCHIVE_DIR="$HOME/.gemini/antigravity/conversations_archive"
BRAIN_DIR="$HOME/.gemini/antigravity/brain"

if [ ! -d "$CONV_DIR" ]; then
  echo "ERROR: conversations directory not found: $CONV_DIR"
  exit 1
fi

mkdir -p "$ARCHIVE_DIR"

THRESHOLD_BYTES=$((THRESHOLD_MB * 1048576))
echo "=== AG IDE Conversation Archive ==="
echo "Threshold: ${THRESHOLD_MB}MB"
echo ""

# List candidates
CANDIDATES=$(find "$CONV_DIR" -name "*.pb" -size "+${THRESHOLD_MB}M" -printf "%s %f\n" 2>/dev/null | sort -rn)

if [ -z "$CANDIDATES" ]; then
  echo "No .pb files exceed ${THRESHOLD_MB}MB. Nothing to archive."
  exit 0
fi

echo "Files to archive:"
echo ""
echo "$CANDIDATES" | while read size fname; do
  cid="${fname%.pb}"
  size_mb=$(echo "scale=1; $size/1048576" | bc)
  modtime=$(stat -c '%y' "$CONV_DIR/$fname" 2>/dev/null | cut -d. -f1)
  # Try to get conversation title from brain
  title=$(head -1 "$BRAIN_DIR/$cid/task.md" 2>/dev/null | sed 's/^# //' || echo "(no title)")
  printf "  %7sMB  %s  %s  %s\n" "$size_mb" "$modtime" "$cid" "$title"
done

echo ""
read -p "Archive these files? [y/N] " confirm
if [[ "$confirm" != [yY] ]]; then
  echo "Cancelled."
  exit 0
fi

echo ""
COUNT=0
echo "$CANDIDATES" | while read size fname; do
  mv "$CONV_DIR/$fname" "$ARCHIVE_DIR/"
  echo "  ✅ archived $fname"
  COUNT=$((COUNT + 1))
done

echo ""
echo "=== Done ==="
echo "Remaining: $(ls "$CONV_DIR"/*.pb 2>/dev/null | wc -l) conversations"
echo "Archived:  $(ls "$ARCHIVE_DIR"/*.pb 2>/dev/null | wc -l) conversations"
echo ""
echo "To restore a conversation:"
echo "  mv $ARCHIVE_DIR/<id>.pb $CONV_DIR/"
echo ""
echo "⚠️  Restart AG IDE for changes to take effect."
