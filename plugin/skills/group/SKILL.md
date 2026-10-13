---
name: group
description: Move the current session to another group in the session-monitor app, or clear its group when no name is given.
argument-hint: "[group]"
disable-model-invocation: true
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/session-monitor.sh *)
---

!`"${CLAUDE_PLUGIN_ROOT}/scripts/session-monitor.sh" group "${CLAUDE_SESSION_ID}" '$ARGUMENTS'`

Reply with the line above as a one-line confirmation. If it says the session is not registered, suggest `/session-monitor:register [group]`. Do not do anything else.
