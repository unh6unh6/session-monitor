#!/bin/sh
# Registration commands used by the session-monitor skills (and by other skills
# that want their session tracked).
#
#   session-monitor.sh register <session_id> [group]
#   session-monitor.sh group    <session_id> [group]   (empty group = 미분류)
#   session-monitor.sh recap    <session_id>           (recap text on stdin)
#   session-monitor.sh leave    <session_id>
#   session-monitor.sh status   <session_id>

# Other skills call this through the ~/.session-monitor/bin symlink.
self=$0
[ -L "$self" ] && self=$(readlink "$self")
. "${self%/*}/common.sh"

die() {
  printf 'session-monitor: %s\n' "$1" >&2
  exit 1
}

cmd=$1
sid=$2
[ $# -ge 2 ] || die "usage: ${0##*/} register|group|recap|leave|status <session_id> [args]"
shift 2
valid_id "$sid" || die "invalid session id: $sid"
dir="$SM_HOME/sessions/$sid"

# Group names become a single-line file; trim spaces, reject path/control chars.
normalize_group() {
  _g=$(printf '%s' "$*" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  case $_g in
    */* | *'
'*) die "group name must be a single line without '/': $_g" ;;
  esac
  printf '%s' "$_g"
}

write_group() {
  if [ -n "$1" ]; then
    atomic_write "$dir/group" "$1"
  else
    rm -f "$dir/group"
  fi
}

describe() {
  _group=미분류
  [ -f "$dir/group" ] && read -r _group < "$dir/group"
  printf 'session %s registered (group: %s)\n' "$sid" "$_group"
}

case $cmd in
  register)
    group=$(normalize_group "$@") || exit 1
    if [ -d "$dir" ]; then
      [ -n "$group" ] && write_group "$group"
      describe
      exit 0
    fi
    mkdir -p "$dir"
    atomic_write "$dir/meta.json" \
      "{\"schema\":$SM_SCHEMA,\"session_id\":\"$sid\",\"registered_at\":\"$(now_iso)\",\"previous\":\"\",\"via\":\"register\"}"
    write_group "$group"
    # Seed the timeline with the latest event seen before registration.
    if [ -f "$SM_HOME/seen/$sid.json" ]; then
      ensure_dir "$SM_HOME/spool/$sid"
      mv -f "$SM_HOME/seen/$sid.json" "$SM_HOME/spool/$sid/0-seen.json"
    fi
    describe
    ;;
  group)
    [ -d "$dir" ] || die "session $sid is not registered"
    group=$(normalize_group "$@") || exit 1
    write_group "$group"
    describe
    ;;
  recap)
    [ -d "$dir" ] || die "session $sid is not registered"
    text=$(cat)
    [ -n "$text" ] || die "recap text is empty (pass it on stdin)"
    atomic_write "$dir/recap.md" "$text"
    printf 'recap saved for session %s\n' "$sid"
    ;;
  leave)
    # sessions/ first so concurrent hooks stop spooling before cleanup (D9).
    rm -rf "$dir"
    rm -rf "$SM_HOME/spool/$sid"
    printf 'session %s unregistered\n' "$sid"
    ;;
  status)
    if [ -d "$dir" ]; then describe; else printf 'session %s is not registered\n' "$sid"; fi
    ;;
  *)
    die "unknown command: $cmd"
    ;;
esac
