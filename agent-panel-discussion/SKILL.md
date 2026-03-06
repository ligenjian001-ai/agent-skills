---
name: agent-panel-discussion
description: "Multi-agent panel discussion — CC, Codex, Gemini debate a topic with preset stances across multiple rounds, producing an HTML report with academic-style references."
---

# Agent Panel Discussion Skill

> **ROLE**: AG is the **orchestrator**. AG does NOT participate in the debate — it prepares prompts, dispatches agents, collects outputs, handles research requests, and synthesizes the final report.

## When to Trigger

- User says "讨论一下"、"辩论"、"panel discussion"、"各 agent 怎么看"
- User presents a difficult problem and wants multiple perspectives
- User explicitly requests multi-agent discussion

## Panelist Roster

| Agent | Executor | Stance | Description |
|-------|----------|--------|-------------|
| 🔴 Skeptic | CC (Claude) | Devil's Advocate | Challenges assumptions, finds risks, stress-tests reasoning |
| 🔵 Pragmatist | CC (Claude) | Engineer | Focuses on feasibility, trade-offs, actionable steps |
| 🟢 Optimist | CC (Claude) | Visionary | Identifies opportunities, thinks big, champions innovation |

> [!NOTE]
> All 3 agents run on CC (Claude) for maximum reliability. The personas are differentiated
> by prompt, not by engine. The launch script still supports `gemini` and `codex` executors
> if you want to experiment, with codex→gemini auto-fallback.

## Workflow

### Phase 0: Topic Preparation (AG ↔ User)

1. Confirm the discussion topic with the user
2. Ask if they want custom stances (default: skeptic/pragmatist/optimist)
3. Confirm number of rounds (default: **3** — Opening + 2 Rebuttal)
4. **AG does pre-research**: search the web for relevant data, market info, competitor analysis, etc. This material goes into `topic.txt` so all agents have the same factual foundation.

```bash
TASK_ID="panel_$(date +%Y%m%d_%H%M)"
TASK_DIR="/tmp/panel/${TASK_ID}"
SKILL_DIR="/home/lgj/agent-skills/agent-panel-discussion"
TOTAL_ROUNDS=3

mkdir -p "${TASK_DIR}"
# Write topic.txt with the problem + research material
write_to_file("${TASK_DIR}/topic.txt", ...)
```

### Phase 1: Auto-Prepare Prompts

Use `panel_prepare.sh` to automatically combine persona templates + topic + previous round context:

```bash
# Round 0 — injects topic into each agent's template
# 4th arg = total_rounds (用于检测最终轮，启用信心评分 + 禁止搜索请求)
bash ${SKILL_DIR}/scripts/panel_prepare.sh ${TASK_DIR} 0 "" ${TOTAL_ROUNDS}

# Produces:
#   ${TASK_DIR}/round_0/skeptic/prompt.txt
#   ${TASK_DIR}/round_0/pragmatist/prompt.txt
#   ${TASK_DIR}/round_0/optimist/prompt.txt
```

> [!TIP]
> AG may also write custom prompts manually (using `write_to_file`) if the topic needs specialized context beyond what `panel_prepare.sh` generates. The auto-prepare script is a convenience, not a requirement.

### Phase 2: Launch Agents

```bash
bash ${SKILL_DIR}/scripts/panel_launch.sh cc  skeptic    ${TASK_DIR}/round_0/skeptic
bash ${SKILL_DIR}/scripts/panel_launch.sh cc  pragmatist ${TASK_DIR}/round_0/pragmatist
bash ${SKILL_DIR}/scripts/panel_launch.sh cc  optimist   ${TASK_DIR}/round_0/optimist
```

> [!CAUTION]
> **SESSION ISOLATION — NON-NEGOTIABLE**
> Each agent runs in its own tmux session. NEVER run agents in AG's main session.
> Launch commands themselves are quick (just tmux setup) — run them from AG's session.

### Phase 2.5: Monitor & Collect

Poll each agent's completion (60s interval):

```bash
# Check if all agents are done
ls ${TASK_DIR}/round_0/*/execution_record.json 2>/dev/null

# Or check tmux sessions for PANEL_DONE / PANEL_FAIL
tmux capture-pane -t panel-${TASK_ID}-r0-skeptic -p -S -5
```

Once all 3 are done, collect:

```bash
bash ${SKILL_DIR}/scripts/panel_collect.sh ${TASK_DIR} 0
```

### Phase 2.6: 处理搜索请求 + URL 溯源 ⭐ 核心

每轮收集后，AG 检查各 agent 输出中的 `### 📡 资料搜索请求` 部分。如果 agents 请求了额外数据：

1. **提取请求** — 从每个 agent 的 output.md 中找 `[REQUEST]` 行
2. **两步搜索**：
   - `search_web(query)` — 获取摘要 + URL 引用列表
   - `read_url_content(url)` — 对最相关的 1-2 个 URL 做深度抓取，提取关键段落
3. **编写 research supplement** — 写入 `${TASK_DIR}/research_supplement_rN.md`
4. **注入下一轮 prompt** — 追加到 `panel_prepare.sh` 生成的 prompt 文件中

> [!CAUTION]
> **URL 溯源是硬性要求。** AG 搜索后编写 research supplement 时，**必须**保留每条发现的原始 URL。
> 没有 URL 的引用在最终报告中无法生成可点击链接，等于无效引用。

#### Research Supplement 格式规范

每条搜索结果必须包含：标题、核心发现、**原始 URL 列表**。

```markdown
# AG 搜索补充资料 — 第 N 轮

## 发现 #1: AGPL v3 不覆盖求解器输出数据
StackExchange 和 GNU 官方 FAQ 明确：AGPL 的 copyleft 条款仅适用于
软件本身（"covered work"），不延伸到软件产生的输出数据...

**来源：**
- https://opensource.stackexchange.com/questions/5434/...
- https://www.gnu.org/licenses/gpl-faq.html#GPLOutput
- https://fossa.com/blog/open-source-software-licenses-101-agpl/

## 发现 #2: CFR 求解器实现复杂度
构建完整德扑求解器需处理 ~10^160 游戏状态...

**来源：**
- https://labml.ai/blog/cfr-poker
- https://int8.io/counterfactual-regret-minimization/
```

#### 搜索流程示例

```text
Agent 输出:  "### 📡 资料搜索请求
              - [REQUEST] 搜索 AGPL v3 是否覆盖软件输出数据"

AG 步骤 1:   search_web("AGPL v3 commercial use of output data")
             → 获取摘要 + 3 个 URL

AG 步骤 2:   read_url_content("https://opensource.stackexchange.com/...")
             → 深度抓取最相关页面，提取关键段落

AG 步骤 3:   将发现 + URL 写入 research_supplement_rN.md

AG 步骤 4:   追加到下一轮 prompt:
             cat research_supplement_rN.md >> round_N+1/{agent}/prompt.txt
```

> [!IMPORTANT]
> 这是 AG 作为协调者的核心价值 — agents 无法上网搜索，但可以告诉 AG 他们需要什么，
> AG 通过 `search_web` + `read_url_content` 两步获取数据并保留完整 URL 溯源链。

### Phase 3: Rebuttal Rounds (Round 1..N)

For each rebuttal round:

```bash
# Auto-prepare prompts with previous round context
# 4th arg tells the script this is round 1 of 3 total
bash ${SKILL_DIR}/scripts/panel_prepare.sh ${TASK_DIR} 1 "" ${TOTAL_ROUNDS}

# Launch, monitor, collect — same as Phase 2
bash ${SKILL_DIR}/scripts/panel_launch.sh cc  skeptic    ${TASK_DIR}/round_1/skeptic
bash ${SKILL_DIR}/scripts/panel_launch.sh cc  pragmatist ${TASK_DIR}/round_1/pragmatist
bash ${SKILL_DIR}/scripts/panel_launch.sh cc  optimist   ${TASK_DIR}/round_1/optimist

# Wait for completion, then:
bash ${SKILL_DIR}/scripts/panel_collect.sh ${TASK_DIR} 1

# Handle research requests, then repeat for round 2...
```

### Phase 4: Generate Reports

```bash
# Markdown report (mechanical assembly)
bash ${SKILL_DIR}/scripts/panel_report.sh ${TASK_DIR} ${TOTAL_ROUNDS}

# HTML report (polished, with collapsible rounds + references)
python3 ${SKILL_DIR}/scripts/panel_report_html.py ${TASK_DIR} ${TOTAL_ROUNDS}
```

The HTML report (`report.html`) features:

- 🌙 Dark mode UI with agent color coding
- 📊 Panelists grid + execution summary
- 🧠 AG Synthesis section at the top (most important content first)
- 📊 信心评分汇总 — 最终轮各 agent 对核心问题的 1-10 评分（红≤ 4，黄 5-6，绿≥ 7）
- 📝 Collapsible discussion rounds (click to expand)
- 📚 Consolidated References with clickable URLs

> [!NOTE]
> **反驳轮新功能：** `panel_prepare.sh` 现在会在反驳轮注入「立场变化声明」要求，强制每个 agent
> 在回复开头声明哪些观点修正/坚持/新增，让观点漂移可追踪。

To preview: `python3 -m http.server 8765 --bind 0.0.0.0` then open `http://{server_ip}:8765/report.html`

### Phase 5: Synthesis (AG)

AG reads `final_report.md` and fills in the **Synthesis** section:

1. **Areas of Agreement** — points where all 3 agents converged
2. **Key Points of Disagreement** — where they couldn't agree and why
3. **信心评分汇总** — 引用最终轮各 agent 的 1-10 评分并评论差异
4. **Final Recommendations** — AG's balanced conclusion weighing all perspectives

> [!IMPORTANT]
> **最终轮搜索补充**：最终轮禁止 agents 提搜索请求，但如果 AG 发现上一轮还有 2-3 个关键搜索请求
> 未被消化（因为是倒数第二轮提出的），AG 应在 synthesis 阶段快速搜索并将结果融入最终综合分析。

After writing synthesis, re-generate the HTML report so it includes the synthesis + confidence scores:

```bash
python3 ${SKILL_DIR}/scripts/panel_report_html.py ${TASK_DIR} ${TOTAL_ROUNDS}
```

### Phase 6: Present to User

```
📋 Panel discussion complete: ${TASK_ID}
📄 HTML report: http://{server_ip}:8765/report.html
📄 Markdown report: ${TASK_DIR}/final_report.md

{Paste key synthesis findings here}

Want me to go deeper into any specific point?
```

## Citation & Reference System

All agent templates include citation rules:

- Agents use `[n]` inline citations and list sources in `### References`
- Sources from AG's research should be cited by agents
- `[self]` marks claims based on agent's own knowledge (AG may verify later)
- `panel_report_html.py` consolidates all references into a unified bibliography

## Scripts Reference

| Script | Purpose |
|--------|---------|
| `panel_prepare.sh` | Auto-generate prompts from topic + templates + previous round |
| `panel_launch.sh` | Launch one agent in a dedicated tmux session (with fallback) |
| `panel_collect.sh` | Collect outputs and produce round summary |
| `panel_report.sh` | Generate markdown report |
| `panel_report_html.py` | Generate polished HTML report with references |

## tmux Rules

### Session naming

`panel-{task_id}-r{round}-{agent}`

### All tmux interactions: `waitForPreviousTools=true`

### Timeout policy

| Executor | Timeout | Action on timeout |
|----------|---------|-------------------|
| CC | 5 min | Ctrl+C → note failure, proceed with available outputs |
| Gemini | 5 min | Ctrl+C → note failure |
| Codex | 3 min | Auto-fallback to Gemini |

## Configuration

| Parameter | Default | Override |
|-----------|---------|----------|
| Rounds | 3 | User request |
| Skeptic executor | CC | Can swap to gemini/codex |
| Pragmatist executor | CC | Can swap to gemini/codex |
| Optimist executor | CC | Can swap to gemini/codex |
| Word limit | 500-800 per agent per round | Adjustable in prompt |

## Anti-Patterns

```
❌ AG participates in the debate itself
   → AG is the ORCHESTRATOR, not a panelist

❌ Sending prompt content via tmux send-keys
   → ALWAYS use write_to_file for prompt.txt

❌ Starting next round before current round completes
   → Wait for ALL agents in current round to finish

❌ Running all agents in AG's tmux session
   → Each agent gets its own dedicated session

❌ Skipping the synthesis section
   → The synthesis is the MOST VALUABLE part of the report

❌ Not including previous round's output in rebuttal prompts
   → Agents MUST see what others said to produce meaningful rebuttals

❌ Ignoring agents' research requests
   → AG MUST search and feed results into next round
```

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Agent hangs | Check `tmux capture-pane -t {session} -p -S -20` for errors |
| Agent produces no output.md | Check `live.log`, may need to re-extract from raw output |
| Codex 401 Unauthorized | Auto-fallback to Gemini should handle this |
| Codex "not a trusted directory" | Pass project_dir as 4th arg to `panel_launch.sh` |
| Gemini output has WARN noise | Already filtered by launch script |
| Round summary is empty | Check that `panel_collect.sh` ran after ALL agents completed |
| Report synthesis is shallow | AG should spend more effort on genuine analysis, not just summarize |
| HTML report won't open | Serve via `python3 -m http.server --bind 0.0.0.0` |
