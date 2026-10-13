---
name: register
description: Register the current Claude Code session with the session-monitor app so its status (working, done, needs response) shows there, optionally in a group. Use when the user asks to track, monitor, or register this session, or when another skill requires session tracking.
argument-hint: "[group]"
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/session-monitor.sh *)
---

!`"${CLAUDE_PLUGIN_ROOT}/scripts/session-monitor.sh" register "${CLAUDE_SESSION_ID}"`

The line above is the result of registering this session with session-monitor.

Requested group: `$ARGUMENTS`

1. If a group was requested above (not empty), set it with this command, passing the group name as one single-quoted argument:

```sh
"${CLAUDE_PLUGIN_ROOT}/scripts/session-monitor.sh" group "${CLAUDE_SESSION_ID}" '<group>'
```

2. Save a recap of this session so far, so it can be identified in the app. Write 2-5 short lines in the user's language: the goal of this session, what has been done, and what is in progress or next. If the session has just started and there is no context yet, write one line saying so.
   Save it with exactly this command (keep the quoted heredoc):

```sh
"${CLAUDE_PLUGIN_ROOT}/scripts/session-monitor.sh" recap "${CLAUDE_SESSION_ID}" <<'RECAP'
<recap lines>
RECAP
```

3. Reply with one line confirming the registration and the group. Do not do anything else.
