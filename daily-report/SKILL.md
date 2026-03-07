---
name: daily-report
description: "生成个人日报/周报。自动搜集AG对话、Panel Discussion、Task Delegate数据，按项目分组总结，附AI改进建议和明日事项初稿。触发词：生成日报、daily report、今天做了什么、工作总结。"
---

# Daily Report Skill

> **ROLE**: AG 是日报的**生成者和复盘伙伴**。AG 运行脚本采集数据、生成初稿，然后与用户交互式讨论改进建议和明日事项。

## When to Trigger

- 用户说 "生成日报"、"daily report"、"今天做了什么"、"工作总结"
- 用户说 "补一下日报"、"backfill" → 使用 --backfill 模式
- 每日 cron 定时触发（Future）

## Workflow

### Step 1: 运行数据采集 + 报告生成

```bash
bash /home/lgj/agent-skills/daily-report/scripts/daily_report.sh [YYYYMMDD]
```

- 不传日期 = 今日
- `--backfill` = 检测并补齐缺失天数的日报

**输出**: `~/daily-reports/YYYY/MM/YYYYMMDD.md`

### Step 2: 展示日报给用户

AG 读取生成的 markdown 文件，以 artifact 形式展示给用户。

### Step 3: 交互式复盘

用户可以对以下内容提出修改：

- **📋 改进建议（AI 初稿）** — AG 根据数据模式自动生成
- **📅 明日事项建议（AI 初稿）** — AG 根据未完成任务推断

AG 根据用户反馈更新 markdown 文件中对应部分。

### Step 4: Git Commit

讨论完成后，AG 将最终版本 commit：

```bash
cd ~/daily-reports && git add -A && git commit -m "日报: YYYYMMDD"
```

## Data Sources

| 来源 | 路径 | 核心文件 |
|------|------|----------|
| AG 对话 | `~/.gemini/antigravity/brain/*/` | `conversation_journal.md`, `walkthrough.md`, `.metadata.json` |
| Panel Discussion | `~/.panel-discussions/panel_*/` | `topic.txt`, `round_*_summary.md` |
| Task Delegate | `~/.task-delegate/*/` | `execution_record.json`, `prompt.txt` |

## Project Matching

配置文件: `/home/lgj/agent-skills/daily-report/projects.yaml`

匹配优先级: `project` 字段 > 路径匹配 > 关键词匹配

添加新项目: 编辑 `projects.yaml`，添加 name, display, match.paths, match.keywords

## Mandatory Rules

1. **AI 只给初稿**: 改进建议和明日事项标注 "AI 初稿"，用户有最终决定权
2. **Backfill 不覆盖**: 已存在的日报不会被覆盖
3. **空日不生成**: 没有任何活动数据的日期跳过，不生成空日报
4. **Git commit 在讨论后**: 只有用户确认后才 commit，不自动 commit

## Anti-Patterns

```
❌ 跳过 Step 3 直接 commit
   → 必须展示给用户并确认

❌ 修改用户已确认的日报内容
   → 只修改 AI 初稿部分（改进建议、明日事项）

❌ 生成周报时逐日重新采集
   → 应该聚合已有的日报 markdown 文件
```

## Troubleshooting

| Problem | Fix |
|---------|-----|
| collect.py 没有找到对话 | 检查 `~/.gemini/antigravity/brain/` 是否存在，检查 `.metadata.json` 中的 `updatedAt` 时间 |
| 项目匹配全部归到 "其他" | 检查 `projects.yaml` 关键词配置是否覆盖足够 |
| PyYAML 未安装 | `pip install pyyaml` |
| 日期解析错误 | 确认日期格式为 YYYYMMDD（8位数字） |
