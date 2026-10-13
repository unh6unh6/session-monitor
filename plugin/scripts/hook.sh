#!/bin/sh
# Claude Code hook for session-monitor. Runs on every subscribed event of every
# session, so the unregistered path must stay cheap. Always exits 0 so it never
# affects Claude. Design: docs/DECISIONS.md D1, D3, D5, D9, D10.

. "${0%/*}/common.sh"

in=$(cat) || exit 0
sid=$(json_field "$in" session_id)
valid_id "$sid" || exit 0
event=$(json_field "$in" hook_event_name)
pid=${CLAUDE_PID:-$PPID}

registered() {
  [ -d "$SM_HOME/sessions/$1" ]
}

term_json() {
  printf '{"program":"%s","session":"%s","iterm":"%s","tmux":"%s","tmux_pane":"%s"}' \
    "$(json_str "${TERM_PROGRAM:-}")" "$(json_str "${TERM_SESSION_ID:-}")" \
    "$(json_str "${ITERM_SESSION_ID:-}")" "$(json_str "${TMUX:-}")" "$(json_str "${TMUX_PANE:-}")"
}

# Wraps the raw hook input with process info. tty costs a `ps`, so only
# SessionStart pays for it; the app carries it forward per pid.
record() {
  _tty=
  [ "$event" = SessionStart ] && _tty=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')
  printf '{"schema":%s,"ts":"%s","pid":%s,"tty":"%s","term":%s,"input":%s}' \
    "$SM_SCHEMA" "$(now_iso)" "$pid" "$(json_str "$_tty")" "$(term_json)" "$in"
}

if [ "$event" = SessionStart ]; then
  ensure_dir "$SM_HOME/pids"
  # /clear keeps the process but starts a new session: carry the registration over.
  case $in in
    *'"source":"clear"'* | *'"source": "clear"'*)
      prev=
      [ -f "$SM_HOME/pids/$pid" ] && read -r prev < "$SM_HOME/pids/$pid"
      if valid_id "$prev" && registered "$prev" && ! registered "$sid"; then
        dir="$SM_HOME/sessions/$sid"
        mkdir -p "$dir"
        [ -f "$SM_HOME/sessions/$prev/group" ] && cp "$SM_HOME/sessions/$prev/group" "$dir/group"
        atomic_write "$dir/meta.json" \
          "{\"schema\":$SM_SCHEMA,\"session_id\":\"$sid\",\"registered_at\":\"$(now_iso)\",\"previous\":\"$prev\",\"via\":\"clear\"}"
      fi
      ;;
  esac
  atomic_write "$SM_HOME/pids/$pid" "$sid"
  # Stable path for other skills; the plugin dir changes with each version.
  ensure_dir "$SM_HOME/bin"
  ln -sf "${0%/*}/session-monitor.sh" "$SM_HOME/bin/session-monitor"
fi

if registered "$sid"; then
  dir="$SM_HOME/spool/$sid"
  ensure_dir "$dir"
  # Ordering: the app sorts by file mtime (ns on APFS), then by name.
  atomic_write "$dir/$(date +%s)-$pid-$$.json" "$(record)"
  exit 0
fi

# Unregistered: keep only the latest state-changing event for the dimmed list.
seen="$SM_HOME/seen/$sid.json"
case $event in
  PostToolUse | PostToolUseFailure)
    # Only matters when it ends a "needs response" state.
    last=
    [ -f "$seen" ] && read -r last < "$seen"
    case $last in
      *'"hook_event_name":"PermissionRequest"'*) ;;
      *) exit 0 ;;
    esac
    ;;
esac
ensure_dir "$SM_HOME/seen"
atomic_write "$seen" "$(record)"
exit 0
