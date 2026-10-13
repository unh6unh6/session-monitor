---
name: leave
description: Stop tracking the current session in the session-monitor app.
disable-model-invocation: true
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/session-monitor.sh *)
---

!`"${CLAUDE_PLUGIN_ROOT}/scripts/session-monitor.sh" leave "${CLAUDE_SESSION_ID}"`

Reply with the line above as a one-line confirmation. Do not do anything else.
