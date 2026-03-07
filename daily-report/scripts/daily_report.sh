#!/bin/bash
set -euo pipefail

# daily_report.sh — Daily Report Entry Script
#
# Usage:
#   daily_report.sh [YYYYMMDD] [--output-dir DIR] [--backfill]
#
# Examples:
#   daily_report.sh                    # Generate today's report
#   daily_report.sh 20260307           # Generate report for specific date
#   daily_report.sh --backfill         # Detect and fill missing reports
#   daily_report.sh --output-dir /tmp  # Custom output directory

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECT_SCRIPT="${SCRIPT_DIR}/collect.py"
GENERATE_SCRIPT="${SCRIPT_DIR}/generate_report.py"

# Defaults
DATE=""
OUTPUT_DIR="${HOME}/daily-reports"
BACKFILL=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --backfill)
            BACKFILL=true
            shift
            ;;
        --help|-h)
            echo "Usage: daily_report.sh [YYYYMMDD] [--output-dir DIR] [--backfill]"
            echo ""
            echo "Options:"
            echo "  YYYYMMDD        Date for the report (default: today)"
            echo "  --output-dir    Output directory (default: ~/daily-reports)"
            echo "  --backfill      Detect and generate missing reports"
            exit 0
            ;;
        *)
            if [[ "$1" =~ ^[0-9]{8}$ ]]; then
                DATE="$1"
            else
                echo "Error: Unknown argument: $1" >&2
                exit 1
            fi
            shift
            ;;
    esac
done

# Default date = today
if [[ -z "$DATE" && "$BACKFILL" == "false" ]]; then
    DATE=$(date +%Y%m%d)
fi

generate_single_report() {
    local report_date="$1"
    local year="${report_date:0:4}"
    local month="${report_date:4:2}"
    local output_path="${OUTPUT_DIR}/${year}/${month}/${report_date}.md"

    # Skip if already exists
    if [[ -f "$output_path" ]]; then
        echo "[SKIP] ${report_date} — report already exists: ${output_path}"
        return 0
    fi

    echo "[COLLECT] ${report_date} — scanning data sources..."

    # Collect data
    local collected
    collected=$(python3 "$COLLECT_SCRIPT" --date "$report_date" --json 2>/dev/null)

    # Check if there's any data
    local total
    total=$(echo "$collected" | python3 -c "
import json, sys
d = json.load(sys.stdin)
s = d.get('stats', {})
print(s.get('ag_conversations', 0) + s.get('panel_discussions', 0) + s.get('task_delegates', 0))
" 2>/dev/null || echo "0")

    if [[ "$total" == "0" ]]; then
        echo "[SKIP] ${report_date} — no activity data found"
        return 0
    fi

    # Generate report
    mkdir -p "$(dirname "$output_path")"
    echo "$collected" | python3 "$GENERATE_SCRIPT" --output "$output_path"

    echo "[DONE] ${report_date} — ${output_path} (${total} items)"
    return 0
}

do_backfill() {
    echo "=== Backfill Mode ==="

    # Find the latest existing report
    local latest_report
    latest_report=$(find "$OUTPUT_DIR" -name "*.md" -type f 2>/dev/null | sort | tail -1)

    local start_date
    if [[ -z "$latest_report" ]]; then
        # No reports exist, start from 7 days ago
        start_date=$(date -d "7 days ago" +%Y%m%d 2>/dev/null || date -v-7d +%Y%m%d)
        echo "No existing reports found. Scanning from ${start_date}."
    else
        # Extract date from filename
        local basename
        basename=$(basename "$latest_report" .md)
        start_date=$(date -d "${basename} + 1 day" +%Y%m%d 2>/dev/null || \
                     date -j -f "%Y%m%d" "$basename" -v+1d +%Y%m%d 2>/dev/null || \
                     echo "")
        if [[ -z "$start_date" ]]; then
            echo "Error: Could not parse date from ${latest_report}" >&2
            exit 1
        fi
        echo "Last report: ${basename}. Scanning from ${start_date}."
    fi

    local today
    today=$(date +%Y%m%d)
    local current="$start_date"
    local filled=0

    while [[ "$current" -le "$today" ]]; do
        generate_single_report "$current"
        if [[ $? -eq 0 ]] && [[ -f "${OUTPUT_DIR}/${current:0:4}/${current:2:2}/${current}.md" ]]; then
            filled=$((filled + 1))
        fi
        # Increment date
        current=$(date -d "${current} + 1 day" +%Y%m%d 2>/dev/null || \
                  date -j -f "%Y%m%d" "$current" -v+1d +%Y%m%d)
    done

    echo ""
    echo "=== Backfill complete: generated ${filled} report(s) ==="
}

# --- Main ---
if [[ "$BACKFILL" == "true" ]]; then
    do_backfill
else
    generate_single_report "$DATE"
fi
