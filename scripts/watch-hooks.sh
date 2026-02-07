#!/usr/bin/env bash
# watch-hooks.sh - Watch all hook logs, including new sessions
# Usage: watch-hooks.sh                    # watch all sessions
#        watch-hooks.sh <session-prefix>   # watch matching sessions
#
# Requires: inotifywait (inotify-tools), jq
# Pipes through pretty-hooks.sh automatically.

set -uo pipefail

LOG_DIR="${CC_HOOK_LOG_DIR:-/tmp/cc-hook-debug}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PRETTY="$SCRIPT_DIR/pretty-hooks.sh"
FILTER="${1:-}"

if ! command -v inotifywait &>/dev/null; then
  echo "Error: inotifywait is required. Install it with: sudo apt install inotify-tools" >&2
  exit 1
fi

if [ ! -x "$PRETTY" ]; then
  echo "Error: pretty-hooks.sh not found at $PRETTY" >&2
  exit 1
fi

mkdir -p "$LOG_DIR"

# Track tail PIDs so we can clean up
declare -A TAILS
cleanup() {
  trap '' INT TERM   # Ignore signals during cleanup
  kill 0 2>/dev/null # Kill all processes in our group
  wait 2>/dev/null
  exit 0
}
trap cleanup INT TERM

# Start tailing a file
tail_file() {
  local file="$1"
  local base
  base=$(basename "$file")

  # Skip if already tailing
  [ -n "${TAILS[$file]:-}" ] && return

  # Apply session filter if set
  if [ -n "$FILTER" ] && [[ "$base" != *"$FILTER"* ]]; then
    return
  fi

  tail -n +1 -f "$file" | "$PRETTY" &
  TAILS["$file"]=$!
}

# Tail existing files
for f in "$LOG_DIR"/*.jsonl; do
  [ -f "$f" ] && tail_file "$f"
done

# Watch for new files
inotifywait -m -q -e create -e moved_to --format '%f' "$LOG_DIR" | while IFS= read -r name; do
  [[ "$name" == *.jsonl ]] && tail_file "$LOG_DIR/$name"
done
