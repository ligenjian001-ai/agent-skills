# Daily Report — 个人工作日报自动生成

> v1.0 | 2026-03-08 | lgj

## The Problem

跨多个 AG 对话、Panel Discussion、Task Delegate 的工作内容分散在不同目录，没有统一的日报机制。手动整理耗时且容易遗漏。

## The Solution

自动扫描三个数据源，按项目分组生成 markdown 日报，附 AI 改进建议和明日事项初稿。生成后 AG 与用户交互式复盘。

## Design Decisions

| 决策 | 选择 | 理由 |
|------|------|------|
| 输出格式 | Markdown | 可 git 管理，可进一步渲染 HTML/飞书 |
| 项目匹配 | 纯规则（projects.yaml） | 不依赖 LLM，快速确定，可审计 |
| 数据采集 | 纯文件系统扫描 | 三个数据源都是文件系统结构，无需 API |
| AI 初稿 | 脚本内规则生成 | 不调用 LLM API，零成本，可预测 |

## File Index

| File | Purpose |
|------|---------|
| `SKILL.md` | AG 操作指南 |
| `README.md` | 本文件 — 设计文档 |
| `projects.yaml` | 项目匹配配置 |
| `scripts/collect.py` | 数据采集：扫描 3 个数据源，输出 JSON |
| `scripts/generate_report.py` | 报告生成：JSON → Markdown |
| `scripts/daily_report.sh` | 入口脚本：协调全流程 |

## Evolution History

| Date | Version | Change |
|------|---------|--------|
| 2026-03-08 | v1.0 | 初始版本：3源采集 + 项目匹配 + 改进建议 + 明日事项 + backfill |
