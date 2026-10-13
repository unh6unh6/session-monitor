# Shared helpers for hook.sh and session-monitor.sh. POSIX sh, no external
# dependencies beyond coreutils that ship with macOS.
# Storage layout: docs/DECISIONS.md D9.

SM_HOME=${SESSION_MONITOR_HOME:-$HOME/.session-monitor}
SM_SCHEMA=1

# json_field <json> <key>: prints the first string value of "key". Tries the
# compact form Claude Code emits first, then falls back to sed for spacing.
json_field() {
  _rest=${1#*\"$2\":\"}
  if [ "$_rest" = "$1" ]; then
    printf '%s' "$1" | sed -n "s/^[^{]*{.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n 1
    return
  fi
  printf '%s' "${_rest%%\"*}"
}

# valid_id <id>: session ids become path components, so allow only [A-Za-z0-9-].
valid_id() {
  case $1 in
    '' | *[!A-Za-z0-9-]*) return 1 ;;
  esac
  return 0
}

# json_str <value>: value safe to embed in a JSON string, or empty if it holds
# characters that would need escaping (env values here are simple tokens).
json_str() {
  case $1 in
    *[\"\\]* | *'
'*) printf '' ;;
    *) printf '%s' "$1" ;;
  esac
}

# ensure_dir <dir>
ensure_dir() {
  [ -d "$1" ] || mkdir -p "$1"
}

# atomic_write <path> <content>: readers only ever see complete files.
atomic_write() {
  _tmp="$1.tmp.$$"
  printf '%s\n' "$2" > "$_tmp" && mv -f "$_tmp" "$1"
}

now_iso() {
  date '+%Y-%m-%dT%H:%M:%S%z'
}
