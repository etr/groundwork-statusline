---
name: uninstall
description: Remove the groundwork-statusline from Claude Code settings
allowed_tools:
  - Read
  - Edit
  - AskUserQuestion
---

Remove the groundwork-statusline configuration from `~/.claude/settings.json`.

Steps:

1. Read `~/.claude/settings.json`
2. Check if a `statusLine` key exists:
   - If no `statusLine` key exists, tell the user "No statusLine is configured — nothing to remove." and stop.
   - If it exists but its `command` field does NOT contain `groundwork-statusline`, use AskUserQuestion to ask: "The current statusLine doesn't appear to be groundwork-statusline. Remove it anyway?" — if they say no, stop.
3. Edit `~/.claude/settings.json` to remove the entire `statusLine` key and its value.
4. Tell the user: "Statusline removed. Restart Claude Code (`/exit` then relaunch) to apply."
