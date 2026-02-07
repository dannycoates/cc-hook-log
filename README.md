# cc-hook-log

A Claude Code plugin that logs every hook event to NDJSON files for debugging and observability.

Each session writes to `/tmp/cc-hook-debug/<session_id>.jsonl` with one JSON object per line.

## Hooks logged

All 14 hook events: `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PermissionRequest`, `PostToolUse`, `PostToolUseFailure`, `Notification`, `SubagentStart`, `SubagentStop`, `Stop`, `TeammateIdle`, `TaskCompleted`, `PreCompact`, `SessionEnd`

All hooks run async (non-blocking). No matchers — everything is captured.

## Install

### Option A — plugin-dir flag

```sh
claude --plugin-dir /path/to/cc-hook-log
```

### Option B — marketplace

```
/plugin marketplace add https://github.com/dannycoates/cc-hook-log
/plugin install cc-hook-log@cc-hook-log
```

## Verify

After running a session with the plugin active:

```sh
# Check for log files
ls /tmp/cc-hook-debug/

# View recent events
cat /tmp/cc-hook-debug/*.jsonl | head -5 | jq .

# List event types captured
cat /tmp/cc-hook-debug/*.jsonl | jq -r '.hook_event_name' | sort -u
```

## How it works

A single script (`log-hook.mjs`) handles all hook events. It reads the hook input JSON from stdin, extracts the `session_id`, and appends the JSON as a single line to the session's `.jsonl` file.

- Node.js builtins only (no dependencies)
- Async file I/O (`node:fs/promises`)
- NDJSON format (one JSON object per line)

## License

MIT
