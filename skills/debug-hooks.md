---
name: debug-hooks
version: "1.0.0"
description: >
  This skill should be used when diagnosing or analyzing Claude Code hook
  behavior using cc-hook-log debug logs. It applies when the user asks to
  debug hooks, analyze hook logs, investigate hook events, understand what
  happened in a session, check tool usage patterns, trace subagent activity,
  find errors or failures, or diagnose why a hook isn't firing. Also applies
  when the user mentions /tmp/cc-hook-debug, .jsonl hook logs, "what did
  claude do", session replay, or hook troubleshooting.
user_invocable: true
---

# Debugging Hook Logs with cc-hook-log

You have access to Claude Code hook debug logs produced by the cc-hook-log
plugin. Logs are NDJSON files at `/tmp/cc-hook-debug/{session_id}.jsonl` with
one JSON object per line, one line per hook event.

## Log Location and Format

- **Directory:** `/tmp/cc-hook-debug/`
- **Files:** `{session_id}.jsonl` (one file per Claude Code session)
- **Format:** NDJSON - each line is a self-contained JSON object
- **Written by:** `log-hook.mjs` which is registered as an async hook on all 14 event types

## Common Fields (present on every event)

Every log entry contains:
- `session_id` - UUID identifying the Claude Code session
- `hook_event_name` - the event type (see below)
- `transcript_path` - path to the Claude Code session transcript
- `cwd` - working directory of the session

## Hook Event Types and Their Fields

### Session Lifecycle
- **SessionStart** - `source`, `model`, optionally `agent_type`
- **SessionEnd** - `reason`
- **Stop** - `stop_hook_active`

### User Input
- **UserPromptSubmit** - `prompt`, `permission_mode`

### Tool Lifecycle
- **PreToolUse** - `tool_name`, `tool_input`, `tool_use_id`, `permission_mode`
- **PostToolUse** - `tool_name`, `tool_input`, `tool_response` (with `stdout`, `stderr`), `tool_use_id`
- **PostToolUseFailure** - `tool_name`, `tool_input`, `error`, `is_interrupt`, `tool_use_id`
- **PermissionRequest** - `tool_name`, `tool_input`

### Subagent Lifecycle
- **SubagentStart** - `agent_id`, `agent_type`
- **SubagentStop** - `agent_id`, `agent_type`, `stop_hook_active`, `agent_transcript_path`

### Other Events
- **Notification** - `message`, `notification_type`, optionally `title`
- **PreCompact** - `trigger`, optionally `custom_instructions`
- **TeammateIdle** - `teammate_name`, `team_name`
- **TaskCompleted** - `task_id`, `task_subject`, `task_description`, optionally `teammate_name`, `team_name`

## How to Query Logs

All query examples require `jq`.

Use `jq` via Bash to query the NDJSON log files. All queries operate on
`/tmp/cc-hook-debug/*.jsonl` or a specific session file.

> In the examples below, `SESSION` is a placeholder for the actual session UUID.
> To find the most recent session file, run `ls -t /tmp/cc-hook-debug/*.jsonl | head -1`.

### Listing sessions

```bash
# List all sessions with their start info
jq -r 'select(.hook_event_name == "SessionStart") | "\(.session_id) \(.model // "?") \(.cwd)"' /tmp/cc-hook-debug/*.jsonl
```

### Finding the right session file

```bash
# Most recently modified session
ls -t /tmp/cc-hook-debug/*.jsonl | head -1

# Find session that worked in a specific directory
jq -r 'select(.hook_event_name == "SessionStart" and (.cwd | contains("project-name"))) | .session_id' /tmp/cc-hook-debug/*.jsonl
```

### Filtering by event type

```bash
# All events of a type from a session
jq 'select(.hook_event_name == "PreToolUse")' /tmp/cc-hook-debug/SESSION.jsonl

# Multiple event types
jq 'select(.hook_event_name == "PreToolUse" or .hook_event_name == "PostToolUse")' /tmp/cc-hook-debug/SESSION.jsonl
```

### Filtering by tool name

```bash
# All Bash tool uses
jq 'select(.tool_name == "Bash")' /tmp/cc-hook-debug/SESSION.jsonl

# All Bash commands that were run (PreToolUse only)
jq -r 'select(.hook_event_name == "PreToolUse" and .tool_name == "Bash") | .tool_input.command' /tmp/cc-hook-debug/SESSION.jsonl

# All files that were read
jq -r 'select(.hook_event_name == "PreToolUse" and .tool_name == "Read") | .tool_input.file_path' /tmp/cc-hook-debug/SESSION.jsonl

# All files that were edited or written
jq -r 'select(.hook_event_name == "PreToolUse" and (.tool_name == "Edit" or .tool_name == "Write")) | .tool_input.file_path' /tmp/cc-hook-debug/SESSION.jsonl
```

### Finding errors and failures

```bash
# All tool failures
jq 'select(.hook_event_name == "PostToolUseFailure")' /tmp/cc-hook-debug/SESSION.jsonl

# Bash commands that produced stderr output
jq 'select(.hook_event_name == "PostToolUse" and .tool_name == "Bash" and .tool_response.stderr != "")' /tmp/cc-hook-debug/SESSION.jsonl

# Interrupted operations
jq 'select(.hook_event_name == "PostToolUseFailure" and .is_interrupt == true)' /tmp/cc-hook-debug/SESSION.jsonl
```

### Tracing subagent activity

```bash
# All subagent start/stop events
jq 'select(.hook_event_name == "SubagentStart" or .hook_event_name == "SubagentStop")' /tmp/cc-hook-debug/SESSION.jsonl

# Which subagent types were spawned
jq -r 'select(.hook_event_name == "SubagentStart") | .agent_type' /tmp/cc-hook-debug/SESSION.jsonl

# Match a subagent's start and stop by agent_id
jq 'select(.agent_id == "AGENT_ID")' /tmp/cc-hook-debug/SESSION.jsonl
```

### Counting and summarizing

```bash
# Count events by type
jq -r '.hook_event_name' /tmp/cc-hook-debug/SESSION.jsonl | sort | uniq -c | sort -rn

# Count tool uses by tool name
jq -r 'select(.hook_event_name == "PreToolUse") | .tool_name' /tmp/cc-hook-debug/SESSION.jsonl | sort | uniq -c | sort -rn

# List user prompts in order
jq -r 'select(.hook_event_name == "UserPromptSubmit") | .prompt' /tmp/cc-hook-debug/SESSION.jsonl
```

### Correlating PreToolUse with PostToolUse

Use `tool_use_id` to match a tool invocation with its result:

```bash
# Find the result of a specific tool invocation
jq 'select(.tool_use_id == "TOOL_USE_ID")' /tmp/cc-hook-debug/SESSION.jsonl

# Show tool name, input summary, and whether it succeeded or failed
jq -r 'select(.tool_use_id != null) | "\(.hook_event_name) \(.tool_name) \(.tool_use_id)"' /tmp/cc-hook-debug/SESSION.jsonl
```

## Diagnostic Procedures

### "Why isn't my hook firing?"

1. Check if the cc-hook-log plugin is installed: look for its entry in `claude plugin list` output
2. Check that `/tmp/cc-hook-debug/` exists and has `.jsonl` files
3. Find the current session file (most recent by mtime)
4. Check if SessionStart was logged - if not, the plugin isn't loading at all
5. Check if the specific event type you expect is present in the log
6. If PreToolUse events exist but not for your tool, the tool matcher may be filtering it out

### "What was the session timeline?"

```bash
jq -r '"\(.hook_event_name)\t\(.tool_name // "")\t\(.agent_id // "")"' /tmp/cc-hook-debug/SESSION.jsonl
```

### "Was the context compacted?"

```bash
jq 'select(.hook_event_name == "PreCompact")' /tmp/cc-hook-debug/SESSION.jsonl
```

## Tips

- Session IDs are UUIDs. Use `ls -t` to find the most recent session file.
- `tool_use_id` links PreToolUse, PostToolUse, and PostToolUseFailure for the same invocation.
- SubagentStart and SubagentStop share `agent_id` to pair them.
- SubagentStop includes `agent_transcript_path` for deeper investigation of subagent behavior.
- The `transcript_path` field on every event points to the full Claude Code transcript if you need richer context.
- All hooks are async so log ordering may occasionally differ from execution order, but in practice they are sequential.
- Logs persist in `/tmp/` and survive until the next reboot or manual cleanup.
