#!/bin/sh
# Tests for hook.sh and session-monitor.sh against a temporary SESSION_MONITOR_HOME.
# Usage: plugin/tests/run.sh   (needs python3 only to validate JSON output)

set -u
ROOT=$(cd "${0%/*}/.." && pwd)
HOOK="$ROOT/scripts/hook.sh"
SM="$ROOT/scripts/session-monitor.sh"
export SESSION_MONITOR_HOME=$(mktemp -d)
H=$SESSION_MONITOR_HOME
trap 'rm -rf "$H"' EXIT
export CLAUDE_PID=4242
export TERM_PROGRAM=WarpTerminal

fails=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; fails=$((fails + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
valid_json() { python3 -c 'import json,sys; [json.load(open(f)) for f in sys.argv[1:]]' "$@" 2>/dev/null; }
count() { ls "$1" 2>/dev/null | grep -c '\.json$'; }

ev() { # ev <session_id> <event> [extra json fields]
  printf '{"session_id":"%s","transcript_path":"/tmp/t.jsonl","cwd":"/tmp","hook_event_name":"%s"%s}' "$1" "$2" "${3:-}" | "$HOOK"
}

A=aaaaaaaa-0000-4000-8000-000000000001
B=bbbbbbbb-0000-4000-8000-000000000002

echo '# unregistered'
ev $A SessionStart ',"source":"startup"'
check "seen written on SessionStart" '[ -f "$H/seen/$A.json" ]'
check "pid mapped to session" '[ "$(cat "$H/pids/4242")" = "$A" ]'
check "no spool for unregistered" '[ ! -d "$H/spool/$A" ]'
check "stable cli link for other skills" '[ -x "$H/bin/session-monitor" ] && "$H/bin/session-monitor" status $A | grep -q "not registered"'
check "seen is valid json with tty field" 'valid_json "$H/seen/$A.json" && grep -q "\"tty\":" "$H/seen/$A.json"'
ev $A PostToolUse ',"tool_name":"Bash"'
check "PostToolUse ignored unless needs-response" 'grep -q SessionStart "$H/seen/$A.json"'
ev $A PermissionRequest ',"tool_name":"Bash"'
ev $A PostToolUse ',"tool_name":"Bash"'
check "PostToolUse recorded after PermissionRequest" 'grep -q "\"hook_event_name\":\"PostToolUse\"" "$H/seen/$A.json"'

echo '# register'
out=$("$SM" register $A)
check "register prints status" 'echo "$out" | grep -q "registered (group: 미분류)"'
check "sessions dir and meta" '[ -d "$H/sessions/$A" ] && valid_json "$H/sessions/$A/meta.json"'
check "seen moved into spool" '[ ! -f "$H/seen/$A.json" ] && [ -f "$H/spool/$A/0-seen.json" ]'
"$SM" group $A '  이슈A  ' >/dev/null
check "group trimmed and saved" '[ "$(cat "$H/sessions/$A/group")" = "이슈A" ]'
check "group rejects slash" '! "$SM" group $A "a/b" 2>/dev/null'
printf 'line1\nline2\n' | "$SM" recap $A >/dev/null
check "recap saved" '[ "$(sed -n 2p "$H/sessions/$A/recap.md")" = "line2" ]'
check "recap needs registration" '! echo x | "$SM" recap $B 2>/dev/null'

echo '# registered events'
ev $A UserPromptSubmit ',"prompt":"say \"hi\"\nnext"'
ev $A Stop ',"last_assistant_message":"done"'
check "events spooled" '[ "$(count "$H/spool/$A")" -eq 3 ]'
check "spool files are valid json" 'valid_json "$H"/spool/$A/*.json'
check "no temp files left" '! ls "$H/spool/$A" | grep -q tmp'

echo '# /clear carries registration'
ev $A SessionEnd ',"reason":"clear"'
ev $B SessionStart ',"source":"clear"'
check "new session registered" '[ -d "$H/sessions/$B" ]'
check "group inherited" '[ "$(cat "$H/sessions/$B/group")" = "이슈A" ]'
check "previous recorded" 'grep -q "\"previous\":\"$A\"" "$H/sessions/$B/meta.json"'
check "pid now maps to new session" '[ "$(cat "$H/pids/4242")" = "$B" ]'
check "new session spooled" '[ "$(count "$H/spool/$B")" -eq 1 ]'

echo '# leave'
"$SM" leave $B >/dev/null
check "leave removes registration and spool" '[ ! -d "$H/sessions/$B" ] && [ ! -d "$H/spool/$B" ]'
ev $B Stop ',"last_assistant_message":"x"'
check "events after leave go to seen" '[ -f "$H/seen/$B.json" ] && [ ! -d "$H/spool/$B" ]'

echo '# robustness'
ev '../../etc' SessionStart ',"source":"startup"'
check "path-like session id ignored" '[ ! -e "$H/seen/../../etc.json" ] && ! ls "$H/seen" | grep -q etc'
printf '{"session_id": "%s", "hook_event_name": "Stop"}' $A | "$HOOK"
check "spaced json parsed" '[ "$(count "$H/spool/$A")" -eq 5 ]'
printf 'not json' | "$HOOK"; check "garbage input exits 0" '[ $? -eq 0 ]'
check "register rejects bad id" '! "$SM" register "a/b" 2>/dev/null'

echo '# concurrency'
big=$(python3 -c 'print("x" * 200000)')
i=0
while [ $i -lt 40 ]; do
  ev $A PostToolUse ",\"tool_name\":\"Bash\",\"tool_response\":\"$big\"" &
  i=$((i + 1))
done
wait
check "40 concurrent large events all spooled" '[ "$(count "$H/spool/$A")" -eq 45 ]'
check "concurrent spool files are valid json" 'valid_json "$H"/spool/$A/*.json'

echo
if [ $fails -eq 0 ]; then echo "all tests passed"; else echo "$fails test(s) failed"; exit 1; fi
