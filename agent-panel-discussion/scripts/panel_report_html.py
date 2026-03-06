#!/usr/bin/env python3
"""
panel_report_html.py — Generate a polished HTML panel discussion report.

Usage: python3 panel_report_html.py <task_dir> <total_rounds>

Features:
  - Executive summary with synthesis at top
  - Collapsible discussion rounds (click to expand)
  - Academic-style References section (consolidated from all agents)
  - Agent color coding (🔴 Skeptic, 🔵 Pragmatist, 🟢 Optimist)
  - Dark mode ready
"""

import json
import os
import re
import sys
from datetime import datetime
from pathlib import Path

def load_text(path):
    try:
        return Path(path).read_text(encoding="utf-8")
    except FileNotFoundError:
        return ""

def get_executor_label(record_path):
    try:
        d = json.loads(Path(record_path).read_text())
        exe = d.get("executor", "unknown")
        labels = {"cc": "Claude", "gemini": "Gemini", "codex": "Codex", "ag-fallback": "AG"}
        label = labels.get(exe, exe)
        fb = d.get("fallback", "")
        if fb:
            label += f" (fallback: {fb})"
        return label
    except:
        return "unknown"

def get_duration(record_path):
    try:
        d = json.loads(Path(record_path).read_text())
        return d.get("duration_human", "?")
    except:
        return "?"

def extract_references(text):
    """Extract numbered references from ### References / 参考文献 section."""
    refs = []
    in_refs = False
    for line in text.split("\n"):
        if re.match(r"^###?\s*(?:References|参考文献)", line, re.IGNORECASE):
            in_refs = True
            continue
        if in_refs:
            if line.startswith("###") or line.startswith("## "):
                break
            m = re.match(r"\s*\[(\d+|self)\]\s*(.*)", line)
            if m:
                refs.append({"id": m.group(1), "text": m.group(2).strip()})
    return refs

def extract_research_requests(text):
    """Extract research requests from ### 📡 Research Requests / 资料搜索请求 section."""
    reqs = []
    in_reqs = False
    for line in text.split("\n"):
        if "Research Requests" in line or "资料搜索请求" in line:
            in_reqs = True
            continue
        if in_reqs:
            if line.startswith("###") or line.startswith("## "):
                break
            m = re.match(r"\s*-\s*\[REQUEST\]\s*(.*)", line)
            if m:
                reqs.append(m.group(1).strip())
    return reqs

def extract_confidence_scores(text):
    """Extract confidence scores from ### 📊 信心评分 table in final-round output."""
    scores = []
    in_scores = False
    for line in text.split("\n"):
        if "信心评分" in line:
            in_scores = True
            continue
        if in_scores:
            if line.startswith("###") or line.startswith("## "):
                break
            # Match table rows: | question | score | reason |
            m = re.match(r"\s*\|\s*(.+?)\s*\|\s*(\d+)\s*\|\s*(.+?)\s*\|", line)
            if m:
                question = m.group(1).strip()
                score = int(m.group(2).strip())
                reason = m.group(3).strip()
                if question and not re.match(r"^[-:]+$", question):  # skip header separator
                    scores.append({"question": question, "score": score, "reason": reason})
    return scores

def md_to_html(text):
    """Minimal Markdown → HTML. Headers, bold, italic, lists, inline code, citations."""
    lines = text.split("\n")
    html_lines = []
    in_list = False
    in_table = False

    for line in lines:
        stripped = line.strip()

        # Skip reference/research sections (handled separately)
        if re.match(r"^###?\s*(?:References|参考文献|📡 Research Requests|📡 资料搜索请求)", stripped, re.IGNORECASE):
            break

        # Headers
        if stripped.startswith("#### "):
            if in_list: html_lines.append("</ul>"); in_list = False
            html_lines.append(f"<h4>{inline_fmt(stripped[5:])}</h4>")
        elif stripped.startswith("### "):
            if in_list: html_lines.append("</ul>"); in_list = False
            html_lines.append(f"<h3>{inline_fmt(stripped[4:])}</h3>")
        elif stripped.startswith("## "):
            if in_list: html_lines.append("</ul>"); in_list = False
            html_lines.append(f"<h2>{inline_fmt(stripped[3:])}</h2>")
        elif stripped.startswith("# "):
            if in_list: html_lines.append("</ul>"); in_list = False
            html_lines.append(f"<h1>{inline_fmt(stripped[2:])}</h1>")
        # Table
        elif "|" in stripped and not stripped.startswith("```"):
            cells = [c.strip() for c in stripped.split("|")[1:-1]]
            if all(re.match(r"^[-:]+$", c) for c in cells):
                continue  # separator row
            if not in_table:
                html_lines.append("<table>")
                tag = "th"
                in_table = True
            else:
                tag = "td"
            row = "".join(f"<{tag}>{inline_fmt(c)}</{tag}>" for c in cells)
            html_lines.append(f"<tr>{row}</tr>")
        # Blockquote
        elif stripped.startswith("> "):
            if in_list: html_lines.append("</ul>"); in_list = False
            html_lines.append(f'<blockquote>{inline_fmt(stripped[2:])}</blockquote>')
        # Unordered list
        elif re.match(r"^\s*[-*]\s+", stripped):
            if not in_list:
                html_lines.append("<ul>")
                in_list = True
            content = re.sub(r"^\s*[-*]\s+", "", stripped)
            html_lines.append(f"<li>{inline_fmt(content)}</li>")
        # Ordered list
        elif re.match(r"^\s*\d+\.\s+", stripped):
            content = re.sub(r"^\s*\d+\.\s+", "", stripped)
            html_lines.append(f"<li>{inline_fmt(content)}</li>")
        # Empty
        elif not stripped:
            if in_list: html_lines.append("</ul>"); in_list = False
            if in_table: html_lines.append("</table>"); in_table = False
        # Paragraph
        else:
            if in_list: html_lines.append("</ul>"); in_list = False
            if in_table: html_lines.append("</table>"); in_table = False
            html_lines.append(f"<p>{inline_fmt(stripped)}</p>")

    if in_list: html_lines.append("</ul>")
    if in_table: html_lines.append("</table>")
    return "\n".join(html_lines)

def inline_fmt(text):
    """Apply inline formatting: bold, italic, code, citation links."""
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"\*(.+?)\*", r"<em>\1</em>", text)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    # Citation links → superscript
    text = re.sub(r"\[(\d+)\]", r'<sup class="cite"><a href="#ref-\1">[\1]</a></sup>', text)
    text = re.sub(r"\[self\]", r'<sup class="cite cite-self">[self]</sup>', text)
    return text

AGENT_META = {
    "skeptic":    {"emoji": "🔴", "color": "#ef4444", "title": "怀疑论者", "subtitle": "魔鬼代言人"},
    "pragmatist": {"emoji": "🔵", "color": "#3b82f6", "title": "务实工程师", "subtitle": "工程师"},
    "optimist":   {"emoji": "🟢", "color": "#22c55e", "title": "乐观派", "subtitle": "愿景者"},
}

def linkify_urls(text):
    """Convert bare URLs in text to clickable <a> tags."""
    return re.sub(
        r'(https?://[^\s<>"\)]+)',
        r'<a href="\1" target="_blank" rel="noopener">\1</a>',
        text
    )

def generate_html(task_dir, total_rounds):
    topic = load_text(f"{task_dir}/topic.txt").strip()
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M")

    # Collect all references globally (dedup by text)
    all_refs = {}
    ref_counter = [0]
    def normalize_ref(ref_text, agent, round_num):
        if ref_text in all_refs:
            return all_refs[ref_text]["global_id"]
        ref_counter[0] += 1
        gid = ref_counter[0]
        all_refs[ref_text] = {"global_id": gid, "agent": agent, "round": round_num}
        return gid

    # Collect all research requests
    all_research_reqs = []

    # Pre-scan all outputs for references and research requests
    round_data = []
    for r in range(total_rounds):
        agents = {}
        for agent in ["skeptic", "pragmatist", "optimist"]:
            output_path = f"{task_dir}/round_{r}/{agent}/output.md"
            record_path = f"{task_dir}/round_{r}/{agent}/execution_record.json"
            output = load_text(output_path)
            refs = extract_references(output)
            reqs = extract_research_requests(output)
            if reqs:
                all_research_reqs.extend([(r, agent, req) for req in reqs])
            # Normalize ref IDs
            for ref in refs:
                if ref["id"] != "self":
                    ref["global_id"] = normalize_ref(ref["text"], agent, r)
            agents[agent] = {
                "output": output,
                "refs": refs,
                "reqs": reqs,
                "executor": get_executor_label(record_path),
                "duration": get_duration(record_path),
            }
            # Extract confidence scores from final round
            if r == total_rounds - 1:
                agents[agent]["confidence"] = extract_confidence_scores(output)
        round_data.append(agents)

    # Load synthesis (last section of final_report.md if exists)
    synthesis_html = ""
    final_report = load_text(f"{task_dir}/final_report.md")
    if "## Synthesis" in final_report or "​## 🧠" in final_report or "## 综合分析" in final_report:
        # Extract everything after synthesis header
        parts = re.split(r"## (?:Synthesis|🧠.*|综合分析)", final_report, maxsplit=1)
        if len(parts) > 1:
            synthesis_html = md_to_html(parts[1])

    # ===== BUILD HTML =====
    html = []
    html.append(f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Panel Discussion: {topic[:60]}...</title>
<style>
:root {{
  --bg: #0f172a; --surface: #1e293b; --surface2: #334155;
  --text: #e2e8f0; --text-dim: #94a3b8; --border: #475569;
  --red: #ef4444; --blue: #3b82f6; --green: #22c55e;
  --accent: #8b5cf6;
}}
* {{ margin: 0; padding: 0; box-sizing: border-box; }}
body {{
  font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
  background: var(--bg); color: var(--text);
  line-height: 1.7; max-width: 960px; margin: 0 auto; padding: 2rem 1.5rem;
}}
h1 {{ font-size: 1.8rem; margin-bottom: 0.5rem; }}
h2 {{ font-size: 1.4rem; margin: 1.5rem 0 0.8rem; color: var(--text); }}
h3 {{ font-size: 1.1rem; margin: 1rem 0 0.5rem; }}
h4 {{ font-size: 1rem; margin: 0.8rem 0 0.4rem; }}
p {{ margin: 0.5rem 0; }}
a {{ color: var(--accent); text-decoration: none; }}
a:hover {{ text-decoration: underline; }}
code {{ background: var(--surface2); padding: 2px 6px; border-radius: 4px; font-size: 0.9em; }}
blockquote {{
  border-left: 3px solid var(--accent); padding: 0.5rem 1rem;
  margin: 0.8rem 0; background: rgba(139,92,246,0.08); border-radius: 0 8px 8px 0;
}}
table {{ width: 100%; border-collapse: collapse; margin: 1rem 0; font-size: 0.9rem; }}
th, td {{ padding: 0.5rem 0.8rem; border: 1px solid var(--border); text-align: left; }}
th {{ background: var(--surface2); font-weight: 600; }}
ul, ol {{ padding-left: 1.5rem; margin: 0.5rem 0; }}
li {{ margin: 0.3rem 0; }}
strong {{ color: #f1f5f9; }}

.header {{ text-align: center; margin-bottom: 2rem; padding-bottom: 1.5rem; border-bottom: 1px solid var(--border); }}
.header .meta {{ color: var(--text-dim); font-size: 0.9rem; margin-top: 0.5rem; }}
.topic-box {{
  background: var(--surface); border: 1px solid var(--border); border-radius: 12px;
  padding: 1.5rem; margin: 1.5rem 0; white-space: pre-line;
}}

/* Synthesis */
.synthesis {{
  background: linear-gradient(135deg, rgba(139,92,246,0.1), rgba(59,130,246,0.08));
  border: 1px solid var(--accent); border-radius: 12px;
  padding: 1.5rem 2rem; margin: 2rem 0;
}}
.synthesis h2 {{ color: var(--accent); }}

/* Agent cards */
.agent-card {{
  border-radius: 12px; padding: 1.5rem 2rem; margin: 1rem 0;
  border-left: 4px solid; background: var(--surface);
}}
.agent-card.skeptic {{ border-color: var(--red); }}
.agent-card.pragmatist {{ border-color: var(--blue); }}
.agent-card.optimist {{ border-color: var(--green); }}
.agent-header {{
  display: flex; align-items: center; gap: 0.8rem; margin-bottom: 1rem;
  font-size: 1.1rem; font-weight: 600;
}}
.agent-badge {{
  display: inline-flex; align-items: center; gap: 0.4rem;
  padding: 0.2rem 0.8rem; border-radius: 20px; font-size: 0.8rem;
  background: var(--surface2); color: var(--text-dim);
}}

/* Collapsible rounds */
details {{ margin: 1rem 0; }}
summary {{
  cursor: pointer; padding: 0.8rem 1.2rem; background: var(--surface);
  border: 1px solid var(--border); border-radius: 8px;
  font-weight: 600; font-size: 1.1rem; user-select: none;
  display: flex; align-items: center; gap: 0.5rem;
}}
summary:hover {{ background: var(--surface2); }}
summary::marker {{ content: ''; }}
summary::before {{ content: '▶'; font-size: 0.8rem; transition: transform 0.2s; }}
details[open] > summary::before {{ transform: rotate(90deg); }}
details > .round-content {{ padding: 1rem 0; }}

/* References */
.references {{
  background: var(--surface); border-radius: 12px; padding: 1.5rem 2rem; margin: 2rem 0;
}}
.references h2 {{ margin-top: 0; }}
.ref-item {{ margin: 0.5rem 0; font-size: 0.9rem; color: var(--text-dim); }}
.ref-item .ref-id {{ color: var(--accent); font-weight: 600; min-width: 2rem; display: inline-block; }}
sup.cite a {{ color: var(--accent); font-size: 0.75rem; }}
sup.cite-self {{ color: var(--text-dim); font-style: italic; }}

/* Panelists table */
.panelists {{
  display: grid; grid-template-columns: repeat(3, 1fr); gap: 1rem; margin: 1.5rem 0;
}}
.panelist {{
  background: var(--surface); border-radius: 10px; padding: 1rem 1.2rem;
  border-top: 3px solid; text-align: center;
}}
.panelist.skeptic {{ border-color: var(--red); }}
.panelist.pragmatist {{ border-color: var(--blue); }}
.panelist.optimist {{ border-color: var(--green); }}
.panelist .emoji {{ font-size: 1.5rem; }}
.panelist .name {{ font-weight: 600; margin: 0.3rem 0; }}
.panelist .role {{ font-size: 0.85rem; color: var(--text-dim); }}
.panelist .engine {{ font-size: 0.8rem; color: var(--text-dim); margin-top: 0.3rem; }}

/* Confidence scores */
.confidence-grid {{
  background: var(--surface); border-radius: 12px; padding: 1.5rem 2rem; margin: 2rem 0;
  border: 1px solid var(--border);
}}
.confidence-grid h2 {{ margin-top: 0; }}
.score-row {{
  display: grid; grid-template-columns: 1fr repeat(3, 80px); gap: 0.5rem;
  padding: 0.5rem 0; border-bottom: 1px solid var(--surface2); align-items: center;
}}
.score-row.header {{ font-weight: 600; color: var(--text-dim); font-size: 0.85rem; }}
.score-cell {{ text-align: center; }}
.score-badge {{
  display: inline-block; width: 36px; height: 36px; line-height: 36px;
  border-radius: 50%; font-weight: 700; font-size: 0.9rem; text-align: center;
}}
.score-low {{ background: rgba(239,68,68,0.2); color: #ef4444; }}
.score-mid {{ background: rgba(234,179,8,0.2); color: #eab308; }}
.score-high {{ background: rgba(34,197,94,0.2); color: #22c55e; }}

@media (max-width: 600px) {{
  .panelists {{ grid-template-columns: 1fr; }}
  body {{ padding: 1rem; }}
}}
</style>
</head>
<body>
""")

    # Header
    html.append(f"""
<div class="header">
  <h1>🎙️ Panel 讨论报告</h1>
  <div class="meta">{timestamp} · {total_rounds} 轮讨论 · {len(all_refs)} 篇参考文献</div>
</div>
""")

    # Topic
    topic_html = inline_fmt(topic.replace("\n", "<br>"))
    html.append(f'<div class="topic-box">{topic_html}</div>')

    # Panelists
    html.append('<div class="panelists">')
    for agent in ["skeptic", "pragmatist", "optimist"]:
        m = AGENT_META[agent]
        exe = round_data[0][agent]["executor"] if round_data else "?"
        html.append(f"""
  <div class="panelist {agent}">
    <div class="emoji">{m['emoji']}</div>
    <div class="name">{m['title']}</div>
    <div class="role">{m['subtitle']}</div>
    <div class="engine">{exe}</div>
  </div>""")
    html.append('</div>')

    # Synthesis at top (if available)
    if synthesis_html:
        html.append(f'<div class="synthesis"><h2>🧠 AG 综合分析 — 最终结论</h2>{synthesis_html}</div>')

    # Confidence scores summary (from final round)
    if round_data:
        final_agents = round_data[-1]
        has_scores = any(final_agents[a].get("confidence") for a in ["skeptic", "pragmatist", "optimist"])
        if has_scores:
            html.append('<div class="confidence-grid"><h2>📊 信心评分汇总</h2>')
            # Collect all unique questions
            all_questions = []
            for a in ["skeptic", "pragmatist", "optimist"]:
                for s in final_agents[a].get("confidence", []):
                    if s["question"] not in all_questions:
                        all_questions.append(s["question"])
            # Header
            html.append('<div class="score-row header"><div>问题</div>')
            for a in ["skeptic", "pragmatist", "optimist"]:
                html.append(f'<div class="score-cell">{AGENT_META[a]["emoji"]} {AGENT_META[a]["title"]}</div>')
            html.append('</div>')
            # Data rows
            for q in all_questions:
                html.append(f'<div class="score-row"><div>{inline_fmt(q)}</div>')
                for a in ["skeptic", "pragmatist", "optimist"]:
                    score_data = next((s for s in final_agents[a].get("confidence", []) if s["question"] == q), None)
                    if score_data:
                        sc = score_data["score"]
                        css = "score-low" if sc <= 4 else ("score-mid" if sc <= 6 else "score-high")
                        html.append(f'<div class="score-cell"><span class="score-badge {css}" title="{score_data["reason"]}">{sc}</span></div>')
                    else:
                        html.append('<div class="score-cell">-</div>')
                html.append('</div>')
            html.append('</div>')

    # Discussion rounds (collapsible)
    html.append('<h2>📝 讨论过程</h2>')
    for r in range(total_rounds):
        round_label = "开场陈述" if r == 0 else f"反驳轮 #{r}"
        open_attr = ' open' if r == total_rounds - 1 else ''  # last round open by default
        html.append(f'<details{open_attr}><summary>第 {r} 轮: {round_label}</summary><div class="round-content">')

        for agent in ["skeptic", "pragmatist", "optimist"]:
            m = AGENT_META[agent]
            data = round_data[r][agent]
            output_html = md_to_html(data["output"])
            html.append(f"""
<div class="agent-card {agent}">
  <div class="agent-header">
    {m['emoji']} {m['title']}
    <span class="agent-badge">{data['executor']} · {data['duration']}</span>
  </div>
  {output_html}
</div>""")

        html.append('</div></details>')

    # References section
    if all_refs:
        html.append('<div class="references"><h2>📚 参考文献</h2>')
        for ref_text, info in sorted(all_refs.items(), key=lambda x: x[1]["global_id"]):
            gid = info["global_id"]
            linked_text = linkify_urls(inline_fmt(ref_text))
            html.append(f'<div class="ref-item" id="ref-{gid}"><span class="ref-id">[{gid}]</span> {linked_text}</div>')
        html.append('</div>')

    # Footer
    html.append(f"""
<div style="text-align:center; padding: 2rem 0; color: var(--text-dim); font-size: 0.85rem; border-top: 1px solid var(--border); margin-top: 2rem;">
  由 <strong>Agent Panel Discussion</strong> 生成 · {timestamp}
</div>
</body></html>""")

    return "\n".join(html)


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python3 panel_report_html.py <task_dir> <total_rounds>", file=sys.stderr)
        sys.exit(1)

    task_dir = sys.argv[1]
    total_rounds = int(sys.argv[2])
    output_path = os.path.join(task_dir, "report.html")

    html = generate_html(task_dir, total_rounds)
    Path(output_path).write_text(html, encoding="utf-8")
    size = os.path.getsize(output_path)
    print(f"\n✅ HTML report written to: {output_path}")
    print(f"   {size:,} bytes")
