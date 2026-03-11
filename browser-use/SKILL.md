---
name: browser-use
description: "Browser automation via 3 layers: AG browser_subagent (built-in), HybridAgent (browser-use + CDP keyboard), and noVNC fallback. Use this skill for web tasks requiring navigation, text input into SPAs, cookie sharing, or human-in-the-loop."
---

# Browser Use Skill

> **PURPOSE**: Workstation has 3 browser automation layers. This skill documents when and how to use each.

## Layer Architecture

| Layer | Engine | Best For | Limitations |
|-------|--------|----------|-------------|
| **L1: AG browser_subagent** | Playwright + CDP + LLM vision | Quick navigation, screenshots, DOM reading, clicking | Separate browser instance, no login state sharing |
| **L2: HybridAgent** | browser-use 0.12.1 + Gemini LLM + CDP keyboard | SPA text input (Discord etc.), multi-phase workflows | Needs `GOOGLE_API_KEY` env var |
| **L3: noVNC fallback** | Xvfb :99 + x11vnc + websockify | Human-in-the-loop, CAPTCHA, complex UI | Manual, requires user at noVNC |

## Layer Selection Guide

| Task | Use |
|------|-----|
| Read a webpage, take screenshot, click buttons | L1 `browser_subagent` |
| Type into Discord/Slack/SPA input fields | L2 `HybridAgent.type_and_send()` |
| Navigate + type + read response (end-to-end) | L2 `HybridAgent` full flow |
| Login needed, CAPTCHA, complex visual task | L3 noVNC + `wait_for_human()` |
| Share login cookies between L1 and L2 | `export_cookies()` → `import_cookies()` |
| Push notification when human action required | Auto via `DISCORD_WEBHOOK_URL` env |

## L2: HybridAgent Usage

**Project**: `~/workstation-ops/browser-tools/`
**Run**: Always `cd ~/workstation-ops/browser-tools && uv run python <script>`

### Quick Usage (Delegation to CC/Codex)

When writing a task for a subagent that needs browser automation, include this context:

```python
import sys, os
sys.path.insert(0, os.path.expanduser("~/workstation-ops/browser-tools"))
os.environ["DISPLAY"] = ":99"

from lib import HybridAgent

agent = HybridAgent(novnc_url="http://192.168.1.10:6080/vnc.html")
await agent.start()

# Phase 1: Navigate (LLM-driven)
await agent.navigate("Go to https://example.com and click Login")

# Phase 2: Type into SPA input (CDP, no duplication)
await agent.type_and_send("hello world", textbox_selector='div[role="textbox"]')

# Phase 3: Read response (LLM-driven)
reply = await agent.read_response("What is the latest message?")

# Human-in-the-loop (auto-notifies Discord if DISCORD_WEBHOOK_URL set)
done = await agent.wait_for_human(
    prompt="Please solve the CAPTCHA",
    check_prompt="Is the CAPTCHA solved and the next page visible?",
    timeout=120,
)

await agent.close()
```

### Available Modules

```
lib/
├── cdp_keyboard.py   — cdp_type_text(page, text)     # Input.insertText, no char duplication
│                       cdp_press_key(page, key, code)  # keyDown/keyUp pair for Enter/Tab/etc
├── hybrid_agent.py   — HybridAgent class              # 3-phase: navigate → type → read
├── session.py        — export_cookies(profile_dir)     # Chromium SQLite → JSON
│                       import_cookies(page, path)      # JSON → CDP Network.setCookies
│                       SHARED_PROFILE_DIR              # ~/.browser-use-profile
├── notify.py         — send_discord_notification(msg)  # Discord webhook, stdlib only
└── __init__.py       — exports all public symbols
```

### Key Technical Details

- **CDP keyboard**: Uses `Input.insertText` (single atomic event per character). This is critical for SPAs like Discord that double-handle `keyDown.text` + `char.text` events.
- **Special keys**: `cdp_press_key("Enter", "Enter")` — dispatches `keyDown`/`keyUp` pair only, no `char` event.
- **Profile**: HybridAgent uses `~/.browser-use-profile/` by default. Cookies can be exported to JSON and imported into other browser sessions via CDP.
- **Notification**: `wait_for_human()` auto-sends Discord webhook notification when `DISCORD_WEBHOOK_URL` is set. No extra config needed.
- **Display**: All browser automation runs on `Xvfb :99` (1280x720x24). Set `DISPLAY=:99` before launching.

## L1: AG browser_subagent

AG's built-in `browser_subagent` tool. No additional setup needed.

```
# In AG tool calls:
browser_subagent(Task="Navigate to https://github.com and take a screenshot")
```

To import cookies from HybridAgent's profile into a Playwright page:

```python
from lib.session import export_cookies
export_cookies()  # writes /tmp/browser_cookies.json
# Then in Playwright: import via CDP Network.setCookies
```

## L3: noVNC Fallback

- **URL**: `http://192.168.1.10:6080/vnc.html`
- **Service**: `browser-vnc.service` (systemd user service)
- **When**: CAPTCHA, OAuth popups, visual tasks that LLM can't handle

## Infrastructure Status

```
Xvfb :99 (1280x720x24)     ✅ systemd
x11vnc → localhost:5999     ✅ systemd
websockify → :6080          ✅ systemd
browser-use 0.12.1          ✅ uv venv
Playwright (dev dep)        ✅ chromium-headless-shell v1208
```

## Mandatory Rules

1. **ALWAYS `cd ~/workstation-ops/browser-tools`** before running any HybridAgent script
2. **ALWAYS use `uv run python`** — the venv has all dependencies
3. **Set `DISPLAY=:99`** in your script or environment
4. **Use `cdp_type_text` for text, `cdp_press_key` for special keys** — NEVER use the old triple-dispatch pattern
5. **For Gemini model**: Use `gemini-3.1-flash-lite-preview` (HybridAgent default), NOT `gemini-2.5-flash-preview`

## Anti-Patterns

```
❌ Using page.keyboard.type() or page.press() for SPA input
   → SPAs double-handle keyboard events. Use cdp_type_text/cdp_press_key

❌ Running from ~/browser-use-demo/ (old location)
   → Moved to ~/workstation-ops/browser-tools/

❌ Dispatching keyDown + char + keyUp for text input
   → This is the old bug. Use Input.insertText instead

❌ Forgetting DISPLAY=:99
   → Browser launch will fail with "no display" error
```

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Browser can't launch | Check `DISPLAY=:99` is set, verify Xvfb: `pgrep -a Xvfb` |
| Character duplication in SPA | Ensure using `cdp_type_text` (Input.insertText), not old triple-dispatch |
| Gemini 404 | Check model name in HybridAgent constructor, ensure `GOOGLE_API_KEY` is set |
| noVNC not accessible | Check `systemctl --user status browser-vnc` |
| Cookie import fails | Run `export_cookies()` first, check `/tmp/browser_cookies.json` exists |
| Discord notification not sent | Check `DISCORD_WEBHOOK_URL` env var is set |
