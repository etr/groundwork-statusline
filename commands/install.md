---
name: install
description: Install the groundwork-statusline into Claude Code settings
allowed_tools:
  - Read
  - Edit
  - AskUserQuestion
---

Install the groundwork-statusline by configuring `~/.claude/settings.json`.

Steps:

1. Read `~/.claude/settings.json`
2. Check if a `statusLine` key already exists in the JSON:
   - If it exists and its `command` field contains `groundwork-statusline`, tell the user it's already installed and stop.
   - If it exists but points to something else, use AskUserQuestion to ask the user: "A statusLine is already configured pointing to a different command. Replace it with groundwork-statusline?" — if they say no, stop.
3. Edit `~/.claude/settings.json` to add (or replace) the `statusLine` key with exactly this value:

```json
"statusLine": {
  "type": "command",
  "command": "bash ${CLAUDE_PLUGIN_ROOT}/statusline-command.sh",
  "height": 3
}
```

4. Tell the user: "Statusline installed. Restart Claude Code (`/exit` then relaunch) to see it."
