#!/usr/bin/env python3
"""ag_deep_export.py — Format and index a deep-exported conversation transcript.

Called by AG after it writes the raw transcript markdown.
Handles: formatting, truncation marking, README update, and index regeneration.
"""
import argparse
import json
import os
import shutil
import sys
from datetime import datetime
from pathlib import Path


def get_conv_date(archive_dir: str, conv_id: str) -> str:
    """Find existing conversation directory date prefix, or use today."""
    conv_parent = Path(archive_dir) / "conversations"
    if conv_parent.exists():
        for d in conv_parent.iterdir():
            if d.is_dir() and conv_id[:8] in d.name:
                return d.name.split("_")[0]
    return datetime.now().strftime("%Y-%m-%d")


def add_truncation_warning(transcript_path: str) -> None:
    """Prepend truncation warning to transcript file."""
    warning = (
        "> ⚠️ **对话记录不完整** — 初始消息已被截断（AG 上下文窗口限制）\n"
        "> 以下内容仅包含 AG 可见的部分对话历史。\n\n"
        "---\n\n"
    )
    content = Path(transcript_path).read_text(encoding="utf-8")
    Path(transcript_path).write_text(warning + content, encoding="utf-8")


def update_readme(conv_dir: str) -> None:
    """Update the conversation README to reflect transcript availability."""
    readme = Path(conv_dir) / "README.md"
    if not readme.exists():
        return

    content = readme.read_text(encoding="utf-8")
    content = content.replace(
        "❌ 不可用（需在对话内部执行深度导出）",
        "✅ 已导出"
    )
    readme.write_text(content, encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description="AG Deep Export Helper")
    parser.add_argument("--conv-id", required=True, help="Conversation UUID")
    parser.add_argument("--transcript-file", required=True,
                        help="Path to the raw transcript markdown")
    parser.add_argument("--output-dir", required=True,
                        help="Archive output directory")
    parser.add_argument("--truncated", action="store_true",
                        help="Mark transcript as truncated (incomplete)")
    parser.add_argument("--title", default="",
                        help="Optional conversation title")
    args = parser.parse_args()

    if not os.path.exists(args.transcript_file):
        print(f"ERROR: Transcript file not found: {args.transcript_file}",
              file=sys.stderr)
        sys.exit(1)

    # Find or create conversation directory
    date_prefix = get_conv_date(args.output_dir, args.conv_id)
    short_id = args.conv_id[:8]
    conv_dir = os.path.join(args.output_dir, "conversations",
                            f"{date_prefix}_{short_id}")
    os.makedirs(conv_dir, exist_ok=True)

    # Copy transcript
    dest = os.path.join(conv_dir, "chat_transcript.md")
    shutil.copy2(args.transcript_file, dest)
    print(f"  Transcript saved: {dest}")

    # Add truncation warning if needed
    if args.truncated:
        add_truncation_warning(dest)
        print("  ⚠️  Truncation warning added")

    # Update README
    update_readme(conv_dir)

    # Update manifest
    manifest_path = os.path.join(args.output_dir, "export_manifest.json")
    manifest = {"export_time": "", "files": {}}
    if os.path.exists(manifest_path):
        try:
            with open(manifest_path) as f:
                manifest = json.load(f)
        except Exception:
            pass

    now = datetime.now().isoformat()
    manifest["files"][f"transcript_{short_id}"] = {
        "path": dest,
        "exported_at": now,
        "truncated": args.truncated,
        "title": args.title or "(deep export)"
    }
    manifest["export_time"] = now

    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)

    print(f"  Manifest updated: {manifest_path}")
    print(f"  Done: {conv_dir}")


if __name__ == "__main__":
    main()
