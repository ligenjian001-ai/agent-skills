#!/usr/bin/env bash
# ag_archive.sh — Export AG conversation artifacts and knowledge items
# Supports incremental archiving via export_manifest.json
set -euo pipefail

# ─── Defaults ───
AG_DIR="${HOME}/.gemini/antigravity"
OUTPUT_DIR=""
MODE=""
CONV_ID=""
FORCE=false

# ─── Usage ───
usage() {
  cat <<'EOF'
Usage: ag_archive.sh [OPTIONS]

Modes:
  --full              Export conversations + knowledge items
  --conversations     Export conversation artifacts only
  --knowledge         Export knowledge items only
  --conv-id <UUID>    Export a specific conversation

Options:
  --output-dir <DIR>  Archive output directory (required)
  --force             Force full re-export (ignore manifest)
  -h, --help          Show this help

Examples:
  # First-time full export
  ag_archive.sh --full --output-dir ~/ag-archive

  # Incremental update (auto-detects manifest)
  ag_archive.sh --full --output-dir ~/ag-archive

  # Export single conversation
  ag_archive.sh --conv-id 5f9b971a-438c-4178-8068-b32757dac70d --output-dir ~/ag-archive
EOF
  exit 0
}

# ─── Parse args ───
while [[ $# -gt 0 ]]; do
  case "$1" in
    --full)          MODE="full"; shift ;;
    --conversations) MODE="conversations"; shift ;;
    --knowledge)     MODE="knowledge"; shift ;;
    --conv-id)       MODE="single"; CONV_ID="$2"; shift 2 ;;
    --output-dir)    OUTPUT_DIR="$2"; shift 2 ;;
    --force)         FORCE=true; shift ;;
    -h|--help)       usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

[[ -z "$MODE" ]] && { echo "ERROR: Must specify a mode (--full, --conversations, --knowledge, --conv-id)"; exit 1; }
[[ -z "$OUTPUT_DIR" ]] && { echo "ERROR: --output-dir is required"; exit 1; }

MANIFEST="${OUTPUT_DIR}/export_manifest.json"
CONV_DIR="${AG_DIR}/conversations"
BRAIN_DIR="${AG_DIR}/brain"
KI_DIR="${AG_DIR}/knowledge"

mkdir -p "${OUTPUT_DIR}/conversations" "${OUTPUT_DIR}"

# ─── Utilities ───

# Get file mtime as epoch seconds
get_mtime() { stat -c '%Y' "$1" 2>/dev/null || echo "0"; }

# Get file size in bytes
get_size() { stat -c '%s' "$1" 2>/dev/null || echo "0"; }

# Get human-readable date from epoch
epoch_to_date() { date -d "@$1" '+%Y-%m-%d' 2>/dev/null || echo "unknown"; }

# Get human-readable datetime from epoch
epoch_to_datetime() { date -d "@$1" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown"; }

# Get short ID (first 8 chars) from full UUID
short_id() { echo "${1:0:8}"; }

# Check if file changed since last export (returns 0=changed, 1=unchanged)
file_changed() {
  local filepath="$1"
  [[ "$FORCE" == "true" ]] && return 0
  [[ ! -f "$MANIFEST" ]] && return 0

  local current_mtime; current_mtime=$(get_mtime "$filepath")
  local current_size; current_size=$(get_size "$filepath")
  local key; key=$(echo "$filepath" | sed 's/[\/\.]/___/g')

  # Check manifest for this file
  local recorded; recorded=$(python3 -c "
import json, sys
try:
    m = json.load(open('${MANIFEST}'))
    entry = m.get('files', {}).get('${key}', {})
    if str(entry.get('mtime','')) == '${current_mtime}' and str(entry.get('size','')) == '${current_size}':
        print('unchanged')
    else:
        print('changed')
except:
    print('changed')
" 2>/dev/null)

  [[ "$recorded" == "unchanged" ]] && return 1
  return 0
}

# Record a file in the manifest
record_file() {
  local filepath="$1"
  local mtime; mtime=$(get_mtime "$filepath")
  local size; size=$(get_size "$filepath")
  local key; key=$(echo "$filepath" | sed 's/[\/\.]/___/g')

  # Will be batch-written at the end
  echo "${key}|${mtime}|${size}|${filepath}" >> "${OUTPUT_DIR}/.manifest_updates"
}

# ─── Export one conversation ───
export_conversation() {
  local conv_id="$1"
  local pb_file="${CONV_DIR}/${conv_id}.pb"
  local brain_path="${BRAIN_DIR}/${conv_id}"

  # Check if .pb exists
  if [[ ! -f "$pb_file" ]]; then
    echo "  WARN: No .pb file for ${conv_id}, skipping"
    return
  fi

  # Check if brain directory exists (some conversations have no artifacts)
  if [[ ! -d "$brain_path" ]]; then
    echo "  SKIP: No brain artifacts for $(short_id "$conv_id")"
    return
  fi

  # Count exportable files (exclude .tempmediaStorage and .system_generated)
  local file_count
  file_count=$(find "$brain_path" -maxdepth 1 -type f \
    \( -name '*.md' -o -name '*.png' -o -name '*.webp' -o -name '*.json' \) \
    ! -name '*.resolved' ! -name '*.resolved.*' 2>/dev/null | wc -l)

  if [[ "$file_count" -eq 0 ]]; then
    echo "  SKIP: No exportable artifacts for $(short_id "$conv_id")"
    return
  fi

  # Check if conversation changed (using .pb mtime)
  if ! file_changed "$pb_file"; then
    echo "  SKIP: $(short_id "$conv_id") unchanged"
    return
  fi

  # Get date from .pb mtime
  local pb_mtime; pb_mtime=$(get_mtime "$pb_file")
  local date_prefix; date_prefix=$(epoch_to_date "$pb_mtime")
  local sid; sid=$(short_id "$conv_id")
  local conv_out="${OUTPUT_DIR}/conversations/${date_prefix}_${sid}"

  mkdir -p "${conv_out}/artifacts"

  # Copy artifact files (exclude resolved versions, tempmedia, system_generated)
  local copied=0
  while IFS= read -r -d '' f; do
    local basename; basename=$(basename "$f")
    cp -p "$f" "${conv_out}/artifacts/${basename}"
    record_file "$f"
    copied=$((copied + 1))
  done < <(find "$brain_path" -maxdepth 1 -type f \
    \( -name '*.md' -o -name '*.png' -o -name '*.webp' -o -name '*.json' \) \
    ! -name '*.resolved' ! -name '*.resolved.*' -print0 2>/dev/null) || true

  # Also copy browser recordings if they exist
  local browser_dir="${brain_path}/browser"
  if [[ -d "$browser_dir" ]]; then
    local webp_count
    webp_count=$(find "$browser_dir" -name '*.webp' -type f 2>/dev/null | wc -l)
    if [[ "$webp_count" -gt 0 ]]; then
      mkdir -p "${conv_out}/browser_recordings"
      # Only copy recordings < 10MB to avoid huge files
      while IFS= read -r -d '' rec; do
        local rec_size; rec_size=$(get_size "$rec")
        if [[ "$rec_size" -lt 10485760 ]]; then
          cp -p "$rec" "${conv_out}/browser_recordings/"
          copied=$((copied + 1))
        fi
      done < <(find "$browser_dir" -name '*.webp' -type f -print0 2>/dev/null) || true
    fi
  fi

  # Generate README.md for this conversation
  local datetime; datetime=$(epoch_to_datetime "$pb_mtime")
  local pb_size; pb_size=$(get_size "$pb_file")
  local pb_size_mb; pb_size_mb=$(echo "scale=1; ${pb_size}/1048576" | bc 2>/dev/null || echo "?")

  # Try to extract title from task.md or implementation_plan.md
  local title="(untitled)"
  if [[ -f "${conv_out}/artifacts/task.md" ]]; then
    title=$(head -1 "${conv_out}/artifacts/task.md" | sed 's/^#\s*//')
  elif [[ -f "${conv_out}/artifacts/implementation_plan.md" ]]; then
    title=$(head -1 "${conv_out}/artifacts/implementation_plan.md" | sed 's/^#\s*//')
  elif [[ -f "${conv_out}/artifacts/walkthrough.md" ]]; then
    title=$(head -1 "${conv_out}/artifacts/walkthrough.md" | sed 's/^#\s*//')
  fi

  # Check for chat_transcript.md (from deep export)
  local has_transcript="❌ 不可用（需在对话内部执行深度导出）"
  if [[ -f "${conv_out}/chat_transcript.md" ]]; then
    has_transcript="✅ 已导出"
  fi

  cat > "${conv_out}/README.md" <<READMEEOF
# ${title}

| 属性 | 值 |
|------|-----|
| 对话 ID | \`${conv_id}\` |
| 最后活跃 | ${datetime} |
| 对话大小 | ${pb_size_mb} MB |
| 导出 Artifacts | ${copied} 个文件 |
| 聊天记录 | ${has_transcript} |

## Artifacts

$(ls -1 "${conv_out}/artifacts/" 2>/dev/null | sed 's/^/- /')
READMEEOF

  record_file "$pb_file"
  echo "  DONE: ${date_prefix}_${sid} — ${copied} files (${title})"
}

# ─── Export knowledge items ───
export_knowledge() {
  echo ""
  echo "=== Exporting Knowledge Items ==="
  local ki_out="${OUTPUT_DIR}/knowledge"

  if [[ ! -d "$KI_DIR" ]]; then
    echo "  No knowledge directory found"
    return
  fi

  local ki_count=0
  for ki_path in "${KI_DIR}"/*/; do
    [[ ! -d "$ki_path" ]] && continue
    local ki_name; ki_name=$(basename "$ki_path")
    [[ "$ki_name" == "knowledge.lock" ]] && continue

    local ki_meta="${ki_path}/metadata.json"
    local ki_ts="${ki_path}/timestamps.json"

    # Check if KI changed
    if [[ -f "$ki_meta" ]] && ! file_changed "$ki_meta"; then
      echo "  SKIP: ${ki_name} unchanged"
      continue
    fi

    local dest="${ki_out}/${ki_name}"
    mkdir -p "$dest"

    # Copy metadata
    [[ -f "$ki_meta" ]] && cp -p "$ki_meta" "$dest/" && record_file "$ki_meta"
    [[ -f "$ki_ts" ]] && cp -p "$ki_ts" "$dest/" && record_file "$ki_ts"

    # Copy artifacts
    if [[ -d "${ki_path}/artifacts" ]]; then
      cp -rp "${ki_path}/artifacts" "$dest/"
    fi

    ki_count=$((ki_count + 1))
    echo "  DONE: ${ki_name}"
  done
  echo "  Total: ${ki_count} knowledge items exported"
}

# ─── Generate index.md ───
generate_index() {
  echo ""
  echo "=== Generating index.md ==="

  local index_file="${OUTPUT_DIR}/index.md"
  local export_time; export_time=$(date '+%Y-%m-%d %H:%M:%S %Z')

  cat > "$index_file" <<INDEXEOF
# AG Archive Index

> 导出时间: ${export_time}
> 来源: \`${AG_DIR}\`

## 对话列表（按时间倒序）

| 日期 | 对话 ID | 标题 | Artifacts | 聊天记录 |
|------|---------|------|-----------|----------|
INDEXEOF

  # Collect conversation dirs and sort by date (reverse)
  if [[ -d "${OUTPUT_DIR}/conversations" ]]; then
    for conv_dir in $(ls -1rd "${OUTPUT_DIR}/conversations/"*/ 2>/dev/null); do
      local dir_name; dir_name=$(basename "$conv_dir")
      local date_part; date_part=$(echo "$dir_name" | cut -d'_' -f1)
      local readme="${conv_dir}/README.md"

      local title="—"
      local artifact_count="0"
      local transcript="❌"

      if [[ -f "$readme" ]]; then
        title=$(head -1 "$readme" | sed 's/^#\s*//')
        artifact_count=$(grep -c '^\- ' "$readme" 2>/dev/null || echo "0")
      fi
      [[ -f "${conv_dir}/chat_transcript.md" ]] && transcript="✅"

      echo "| ${date_part} | \`${dir_name}\` | ${title} | ${artifact_count} | ${transcript} |" >> "$index_file"
    done
  fi

  # Knowledge items section
  if [[ -d "${OUTPUT_DIR}/knowledge" ]]; then
    cat >> "$index_file" <<'KIEOF'

## Knowledge Items

| 名称 | 文件数 |
|------|--------|
KIEOF
    for ki_dir in "${OUTPUT_DIR}/knowledge"/*/; do
      [[ ! -d "$ki_dir" ]] && continue
      local ki_name; ki_name=$(basename "$ki_dir")
      local ki_files; ki_files=$(find "$ki_dir" -type f 2>/dev/null | wc -l)
      echo "| ${ki_name} | ${ki_files} |" >> "$index_file"
    done
  fi

  echo "  Generated: ${index_file}"
}

# ─── Finalize manifest ───
finalize_manifest() {
  echo ""
  echo "=== Updating manifest ==="

  local updates_file="${OUTPUT_DIR}/.manifest_updates"
  local export_time; export_time=$(date -Iseconds)

  python3 - "$MANIFEST" "$updates_file" "$export_time" <<'PYEOF'
import json, sys, os

manifest_path = sys.argv[1]
updates_path = sys.argv[2]
export_time = sys.argv[3]

# Load existing manifest
manifest = {"export_time": "", "files": {}}
if os.path.exists(manifest_path):
    try:
        with open(manifest_path) as f:
            manifest = json.load(f)
    except:
        pass

manifest["export_time"] = export_time

# Apply updates
if os.path.exists(updates_path):
    with open(updates_path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split('|', 3)
            if len(parts) == 4:
                key, mtime, size, path = parts
                manifest["files"][key] = {
                    "mtime": mtime,
                    "size": size,
                    "path": path,
                    "exported_at": export_time
                }

# Write manifest
with open(manifest_path, 'w') as f:
    json.dump(manifest, f, indent=2, ensure_ascii=False)

# Cleanup
if os.path.exists(updates_path):
    os.remove(updates_path)

file_count = len(manifest["files"])
print(f"  Manifest updated: {file_count} files tracked")
PYEOF
}

# ─── Main ───
echo "╔══════════════════════════════════════╗"
echo "║       AG Archive Export Tool         ║"
echo "╚══════════════════════════════════════╝"
echo ""
echo "Mode: ${MODE}"
echo "Output: ${OUTPUT_DIR}"
echo "Force: ${FORCE}"
echo "Manifest: ${MANIFEST}"
[[ -f "$MANIFEST" ]] && echo "  (existing manifest found — incremental mode)" || echo "  (no manifest — full export)"
echo ""

# Init manifest updates file
> "${OUTPUT_DIR}/.manifest_updates"

case "$MODE" in
  full)
    echo "=== Exporting Conversations ==="
    for pb_file in "${CONV_DIR}"/*.pb; do
      [[ ! -f "$pb_file" ]] && continue
      conv_id=$(basename "$pb_file" .pb)
      export_conversation "$conv_id"
    done
    export_knowledge
    ;;
  conversations)
    echo "=== Exporting Conversations ==="
    for pb_file in "${CONV_DIR}"/*.pb; do
      [[ ! -f "$pb_file" ]] && continue
      conv_id=$(basename "$pb_file" .pb)
      export_conversation "$conv_id"
    done
    ;;
  knowledge)
    export_knowledge
    ;;
  single)
    echo "=== Exporting Single Conversation ==="
    export_conversation "$CONV_ID"
    ;;
esac

generate_index
finalize_manifest

echo ""
echo "════════════════════════════════════════"
echo "  Archive complete: ${OUTPUT_DIR}"
echo "  View index: cat ${OUTPUT_DIR}/index.md"
echo "════════════════════════════════════════"
