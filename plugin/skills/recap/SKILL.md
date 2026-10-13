---
name: recap
description: Update the recap of the current session shown in the session-monitor app. Use when the user asks to refresh or update the session recap/summary in session-monitor.
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/session-monitor.sh *)
---

!`"${CLAUDE_PLUGIN_ROOT}/scripts/session-monitor.sh" status "${CLAUDE_SESSION_ID}"`

If the line above says the session is not registered, tell the user to run `/session-monitor:register [group]` first and stop.

Otherwise:

1. Write 2-5 short lines in the user's language: the goal of this session, what has been done, and what is in progress or next.
2. Save it with exactly this command (keep the quoted heredoc):

```sh
"${CLAUDE_PLUGIN_ROOT}/scripts/session-monitor.sh" recap "${CLAUDE_SESSION_ID}" <<'RECAP'
<recap lines>
RECAP
```

3. Reply with one line confirming the recap was updated.
