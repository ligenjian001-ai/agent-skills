---
name: browser-use
description: "Execute web automation tasks using browser-use (Playwright + Gemini 2.5 Flash). Use this to scrape data, interact with web pages, or automate browser workflows rapidly."
---

# Browser Use Skill

> **ROLE**: This skill wraps the `browser-use` open-source library to perform fast, LLM-driven web automation and scraping. It runs strictly on `gemini-2.5-flash` in the `~/browser-use-demo/` environment.

## Operational Workflow

1. Check the target task and formulate a clear instruction for the agent.
2. Formulate the terminal command using `uv run`.
   To run a generic task via the provided script:

   ```bash
   cd ~/browser-use-demo/ && uv run python /home/lgj/agent-skills/browser-use/scripts/run_task.py --task "Your instructions here"
   ```

3. To run a specific example script (e.g., GitHub star extractor):

   ```bash
   cd ~/browser-use-demo/ && uv run python /home/lgj/agent-skills/browser-use/examples/github_star.py
   ```

4. Read the standard output of the command to capture the extraction result.

## Mandatory Rules

1. **ALWAYS use `gemini-2.5-flash`**: Never use the `preview` version (will 404). If you are writing a custom script, specify the model explicitly.
2. **Execute within `~/browser-use-demo/`**: The environment and uv dependencies are configured there. Always `cd ~/browser-use-demo/` before running.
3. **Prefix all execution commands with `uv run`**: Ensures the correct `.venv` is used.

## Anti-Patterns

❌ Running python directly without `uv` or from the wrong directory
   → `python script.py` (Fails due to missing dependencies)
   → `cd ~/browser-use-demo/ && uv run python script.py` (Correct)

❌ Specifying the `gemini-2.5-flash-preview` model
   → Fails with a 404 error because the model doesn't exist or isn't supported. Always use the GA version `gemini-2.5-flash`.

❌ Writing complex scraping code from scratch
   → `browser-use` is already set up to be driven by natural language. Rely on the LLM to navigate the DOM instead of hardcoding CSS selectors.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Playwright browser not found | Run `uv run playwright install chromium` in `~/browser-use-demo/` |
| uv command not found | Ensure `uv` is installed and in your PATH, or check shell environment |
| Gemini 404 Error | Ensure the code uses `gemini-2.5-flash` exactly, not a preview version |
