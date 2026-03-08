# Browser Use Agent Skill

> Version: 1.0.0
> Date: 2026-03-08
> Author: Antigravity

## The Problem

AG's built-in `browser_subagent` can be slow, especially for complex navigation or rapid scraping tasks. The open-source `browser-use` library (79k+ stars) driven by Playwright and an LLM offers a significantly faster alternative for web automation, but it requires a specific Python environment setup and correct model configuration to work reliably.

## The Solution

This skill encapsulates the execution environment for `browser-use`, standardizing its use around the `~/browser-use-demo/.venv/` environment. It enforces the use of the GA `gemini-2.5-flash` model, ensuring speed and stability. Benchmarks show this approach is 2-9x faster than the built-in AG browser subagent.

## Design Decisions

- **Model Choice**: `gemini-2.5-flash` is strictly enforced. The `preview` versions were found to consistently return 404 errors during automation with the LangChain provider.
- **Environment Management**: We rely on `uv run` from within `~/browser-use-demo/` to execute scripts rather than trying to bootstrap a new environment dynamically. This ensures instantaneous execution leveraging the already-working `browser-use>=0.12.1` and `langchain-openai>=1.1.9` dependencies.
- **Generic Executor**: `scripts/run_task.py` was created to allow arbitrary single-prompt tasks without needing to write a new Python file every time.

## Failed Approaches

- **Using preview models**: Trying to use `gemini-2.5-flash-preview` resulted in pipeline failures due to 404 API errors from Google.

## FAQ

- **Why is `uv run` required?** It automatically resolves the `.venv` inside `~/browser-use-demo/`, avoiding Python path resolution issues.
- **Does it run headless?** By default Playwright can run headless, though depending on the script configuration, it may launch a visible browser.

## Evolution History

| Date | Version | Change |
|------|---------|--------|
| 2026-03-08 | 1.0.0 | Initial release wrapping `browser-use` with Gemini 2.5 Flash |

## File Index

| File | Purpose |
|------|---------|
| `SKILL.md` | Agent operational guide and rules |
| `README.md` | Human-readable documentation, design rationale, and benchmarks |
| `scripts/run_task.py` | Generic Python executor accepting a `--task` string |
| `examples/github_star.py` | Example: Extract star count from a GitHub repository |
| `examples/hn_headline.py` | Example: Extract top headlines from Hacker News |
| `examples/general_scraper.py` | Example: Generic webpage data scraper |
