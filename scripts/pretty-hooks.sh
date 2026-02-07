#!/usr/bin/env bash
# pretty-hooks.sh - Pretty print cc-hook-log NDJSON logs
# Usage: tail -f /tmp/cc-hook-debug/<session>.jsonl | pretty-hooks.sh
#        cat /tmp/cc-hook-debug/<session>.jsonl | pretty-hooks.sh
#
# Requires: jq

set -uo pipefail
trap '' PIPE

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required. Install it with: sudo apt install jq" >&2
  exit 1
fi

# Colors
RST='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
MAGENTA='\033[35m'
CYAN='\033[36m'
WHITE='\033[37m'
BLACK='\033[30m'
BG_RED='\033[41m'
BG_GREEN='\033[42m'
BG_YELLOW='\033[43m'
BG_BLUE='\033[44m'
BG_MAGENTA='\033[45m'
BG_CYAN='\033[46m'

MAX_WIDTH=${COLUMNS:-$(tput cols 2>/dev/null || echo 120)}
TRUNCATE=${PRETTY_HOOKS_TRUNCATE:-300}

# Map event names to colored badges
badge() {
  local event="$1"
  local tool="${2:-}"
  local bg fg
  case "$event" in
    PreToolUse)         printf "${BG_CYAN}${BLACK}${BOLD} %s >>> ${RST}" "${tool:-TOOL}"; return ;;
    PostToolUse)        printf "${BG_MAGENTA}${WHITE}${BOLD} %s <<< ${RST}" "${tool:-TOOL}"; return ;;
    PostToolUseFailure) printf "${BG_RED}${WHITE}${BOLD} %s ERR ${RST}" "${tool:-TOOL}"; return ;;
    SessionStart|TaskCompleted)                                        bg=$BG_GREEN;   fg=$BLACK ;;
    SessionEnd)                                                        bg=$BG_RED;     fg=$WHITE ;;
    SubagentStart)                                                     bg=$BG_CYAN;    fg=$BLACK ;;
    SubagentStop)                                                      bg=$BG_MAGENTA; fg=$WHITE ;;
    Stop|Notification|PermissionRequest|PreCompact|TeammateIdle)       bg=$BG_YELLOW;  fg=$BLACK ;;
    *)                                                                 bg=$BG_BLUE;    fg=$WHITE ;;
  esac
  printf "${bg}${fg}${BOLD} %s ${RST}" "$event"
}

# Truncate a string to N chars, adding ... if truncated
truncate() {
  local str="$1"
  local max="$2"
  if [ "${#str}" -gt "$max" ]; then
    echo "${str:0:$max}..."
  else
    echo "$str"
  fi
}

# Print a labeled field
field() {
  local label="$1" value="$2"
  [ -z "$value" ] || [ "$value" = "null" ] && return
  printf "  ${DIM}%s:${RST} %s\n" "$label" "$value"
}

# Print a labeled field with color
cfield() {
  local label="$1" value="$2" color="$3"
  [ -z "$value" ] || [ "$value" = "null" ] && return
  printf "  ${DIM}%s:${RST} ${color}%s${RST}\n" "$label" "$value"
}

# Print a code block (for tool input/output)
codeblock() {
  local label="$1" content="$2" color="${3:-$DIM}"
  [ -z "$content" ] || [ "$content" = "null" ] && return
  local truncated
  truncated=$(truncate "$content" "$TRUNCATE")
  printf "  ${DIM}%s:${RST}\n" "$label"
  while IFS= read -r subline; do
    printf "    ${color}%s${RST}\n" "$subline"
  done <<< "$truncated"
}

# Separator line
sep() {
  printf "${DIM}"
  printf '%.0s─' $(seq 1 "$MAX_WIDTH")
  printf "${RST}\n"
}

# Process each JSON line
while IFS= read -r line; do
  # Skip empty lines
  [ -z "$line" ] && continue

  # Validate JSON
  if ! echo "$line" | jq -e . &>/dev/null; then
    printf "${RED}[invalid json]${RST} %s\n" "$line"
    continue
  fi

  event=$(echo "$line" | jq -r '.hook_event_name // "unknown"')
  session=$(echo "$line" | jq -r '.session_id // ""' | cut -c1-8)
  tool_name=$(echo "$line" | jq -r '.tool_name // ""')

  # Buffer all output for this event, then write at once to prevent
  # interleaving when multiple sessions are tailed concurrently
  _out=$(
  sep
  printf "$(badge "$event" "$tool_name") ${DIM}session:${RST}${YELLOW}%s${RST}\n" "$session"

  case "$event" in
    SessionStart)
      model=$(echo "$line" | jq -r '.model // ""')
      source=$(echo "$line" | jq -r '.source // ""')
      cwd=$(echo "$line" | jq -r '.cwd // ""')
      agent_type=$(echo "$line" | jq -r '.agent_type // ""')
      cfield "model" "$model" "$GREEN"
      field "source" "$source"
      field "cwd" "$cwd"
      [ -n "$agent_type" ] && [ "$agent_type" != "null" ] && cfield "agent" "$agent_type" "$CYAN"
      ;;

    UserPromptSubmit)
      prompt=$(echo "$line" | jq -r '.prompt // ""')
      mode=$(echo "$line" | jq -r '.permission_mode // ""')
      codeblock "prompt" "$prompt" "$WHITE"
      field "mode" "$mode"
      ;;

    PreToolUse)
      tool=$(echo "$line" | jq -r '.tool_name // ""')
      input=$(echo "$line" | jq -r '.tool_input // "" | if type == "object" then tojson else . end')
      # For common tools, show a compact summary
      case "$tool" in
        Bash)
          cmd=$(echo "$line" | jq -r '.tool_input.command // ""')
          codeblock "command" "$cmd" "$WHITE"
          ;;
        Read)
          path=$(echo "$line" | jq -r '.tool_input.file_path // ""')
          cfield "file" "$path" "$WHITE"
          ;;
        Edit)
          path=$(echo "$line" | jq -r '.tool_input.file_path // ""')
          old=$(echo "$line" | jq -r '.tool_input.old_string // ""')
          new=$(echo "$line" | jq -r '.tool_input.new_string // ""')
          cfield "file" "$path" "$WHITE"
          codeblock "old" "$old" "$RED"
          codeblock "new" "$new" "$GREEN"
          ;;
        Write)
          path=$(echo "$line" | jq -r '.tool_input.file_path // ""')
          cfield "file" "$path" "$WHITE"
          ;;
        Glob)
          pattern=$(echo "$line" | jq -r '.tool_input.pattern // ""')
          path=$(echo "$line" | jq -r '.tool_input.path // ""')
          cfield "pattern" "$pattern" "$WHITE"
          [ -n "$path" ] && [ "$path" != "null" ] && field "path" "$path"
          ;;
        Grep)
          pattern=$(echo "$line" | jq -r '.tool_input.pattern // ""')
          cfield "pattern" "$pattern" "$WHITE"
          ;;
        Task)
          desc=$(echo "$line" | jq -r '.tool_input.description // ""')
          agent=$(echo "$line" | jq -r '.tool_input.subagent_type // ""')
          cfield "agent" "$agent" "$MAGENTA"
          field "description" "$desc"
          ;;
        WebFetch)
          url=$(echo "$line" | jq -r '.tool_input.url // ""')
          cfield "url" "$url" "$WHITE"
          ;;
        *)
          codeblock "input" "$input" "$WHITE"
          ;;
      esac
      ;;

    PostToolUse)
      stdout=$(echo "$line" | jq -r '.tool_response.stdout // ""')
      stderr=$(echo "$line" | jq -r '.tool_response.stderr // ""')
      [ -n "$stdout" ] && [ "$stdout" != "null" ] && codeblock "stdout" "$stdout" "$GREEN"
      [ -n "$stderr" ] && [ "$stderr" != "null" ] && codeblock "stderr" "$stderr" "$RED"
      ;;

    PostToolUseFailure)
      error=$(echo "$line" | jq -r '.error // ""')
      is_interrupt=$(echo "$line" | jq -r '.is_interrupt // false')
      codeblock "error" "$error" "$RED"
      [ "$is_interrupt" = "true" ] && cfield "interrupted" "yes" "$YELLOW"
      ;;

    Stop)
      stop_active=$(echo "$line" | jq -r '.stop_hook_active // false')
      field "stop_hook_active" "$stop_active"
      ;;

    SubagentStart)
      agent_id=$(echo "$line" | jq -r '.agent_id // ""')
      agent_type=$(echo "$line" | jq -r '.agent_type // ""')
      cfield "type" "$agent_type" "$CYAN"
      field "id" "$agent_id"
      ;;

    SubagentStop)
      agent_id=$(echo "$line" | jq -r '.agent_id // ""')
      agent_type=$(echo "$line" | jq -r '.agent_type // ""')
      stop_active=$(echo "$line" | jq -r '.stop_hook_active // false')
      transcript=$(echo "$line" | jq -r '.agent_transcript_path // ""')
      cfield "type" "$agent_type" "$MAGENTA"
      field "id" "$agent_id"
      field "stop_hook_active" "$stop_active"
      [ -n "$transcript" ] && [ "$transcript" != "null" ] && field "transcript" "$transcript"
      ;;

    Notification)
      message=$(echo "$line" | jq -r '.message // ""')
      title=$(echo "$line" | jq -r '.title // ""')
      ntype=$(echo "$line" | jq -r '.notification_type // ""')
      field "type" "$ntype"
      [ -n "$title" ] && [ "$title" != "null" ] && cfield "title" "$title" "$WHITE"
      codeblock "message" "$message" "$YELLOW"
      ;;

    SessionEnd)
      reason=$(echo "$line" | jq -r '.reason // ""')
      cfield "reason" "$reason" "$RED"
      ;;

    PermissionRequest)
      tool=$(echo "$line" | jq -r '.tool_name // ""')
      input=$(echo "$line" | jq -r '.tool_input // "" | if type == "object" then tojson else . end')
      cfield "tool" "$tool" "${BOLD}${YELLOW}"
      codeblock "input" "$input" "$WHITE"
      ;;

    PreCompact)
      trigger=$(echo "$line" | jq -r '.trigger // ""')
      instructions=$(echo "$line" | jq -r '.custom_instructions // ""')
      field "trigger" "$trigger"
      [ -n "$instructions" ] && [ "$instructions" != "null" ] && codeblock "instructions" "$instructions" "$WHITE"
      ;;

    TeammateIdle)
      teammate=$(echo "$line" | jq -r '.teammate_name // ""')
      team=$(echo "$line" | jq -r '.team_name // ""')
      cfield "teammate" "$teammate" "$CYAN"
      field "team" "$team"
      ;;

    TaskCompleted)
      task_id=$(echo "$line" | jq -r '.task_id // ""')
      subject=$(echo "$line" | jq -r '.task_subject // ""')
      description=$(echo "$line" | jq -r '.task_description // ""')
      teammate=$(echo "$line" | jq -r '.teammate_name // ""')
      team=$(echo "$line" | jq -r '.team_name // ""')
      field "task_id" "$task_id"
      cfield "subject" "$subject" "$GREEN"
      [ -n "$description" ] && [ "$description" != "null" ] && codeblock "description" "$description" "$WHITE"
      [ -n "$teammate" ] && [ "$teammate" != "null" ] && field "teammate" "$teammate"
      [ -n "$team" ] && [ "$team" != "null" ] && field "team" "$team"
      ;;

    *)
      echo "$line" | jq -C . 2>/dev/null || echo "$line"
      ;;
  esac
  )
  printf '%s\n' "$_out"
done
