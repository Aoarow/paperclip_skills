---
name: lx-paperclip-inbox-cycle
description: The shared Paperclip wake-up routine for every Lexacore agent. Defines the canonical task lifecycle run on each heartbeat — read wake context, load assigned tasks, check out a task, load its context, update status, and escalate. Use this whenever an agent's HEARTBEAT runs, so the task-handling commands live in exactly one place instead of being copied into every agent. The agent's own work step is supplied by the calling HEARTBEAT.
---

# Paperclip Inbox Cycle

Every Lexacore agent runs this same task lifecycle on each heartbeat. Only the
"do the work" step differs per agent; everything around it is identical and lives here.
HEARTBEAT files reference this skill instead of repeating the commands.

All commands use the Paperclip environment variables present at wake-up:
`$PAPERCLIP_API_KEY`, `$PAPERCLIP_API_URL`, `$PAPERCLIP_AGENT_ID`, `$PAPERCLIP_RUN_ID`,
`$PAPERCLIP_COMPANY_ID`, `$PAPERCLIP_TASK_ID`, `$PAPERCLIP_WAKE_REASON`,
`$PAPERCLIP_WAKE_COMMENT_ID`. Substitute `{issueId}` with the task ID and
`{supervisorAgentId}` with the agent's supervisor as configured in Paperclip.

## When to use
On every heartbeat, before any agent-specific work. Paperclip tasks always have
priority.

## The cycle

### 1. Read the wake context
```
run_shell_command({ command: "echo TASK=$PAPERCLIP_TASK_ID REASON=$PAPERCLIP_WAKE_REASON COMMENT=$PAPERCLIP_WAKE_COMMENT_ID" })
```

### 2. Load assigned tasks
```
run_shell_command({ command: "curl -s -H \"Authorization: Bearer $PAPERCLIP_API_KEY\" \"$PAPERCLIP_API_URL/api/agents/me/inbox-lite\"" })
```
Priority: `in_progress` first, then `todo`. Ignore `blocked` tasks unless you can
unblock them.
**Blocked-task dedup:** if your last comment already describes a blocked status and no
newer comments from other agents or humans exist since, skip the task.
If no tasks are assigned: end the heartbeat — agents create nothing on their own
initiative.

### 3. Check out the task (mandatory before any work)
```
run_shell_command({ command: "curl -s -X POST -H \"Authorization: Bearer $PAPERCLIP_API_KEY\" -H 'Content-Type: application/json' -H \"X-Paperclip-Run-Id: $PAPERCLIP_RUN_ID\" -d '{\"agentId\": \"$PAPERCLIP_AGENT_ID\", \"expectedStatuses\": [\"todo\", \"backlog\", \"blocked\"]}' \"$PAPERCLIP_API_URL/api/issues/{issueId}/checkout\"" })
```
On `409`: the task belongs to someone else → take the next task. Never retry a `409`.

### 4. Load the task context
```
run_shell_command({ command: "curl -s -H \"Authorization: Bearer $PAPERCLIP_API_KEY\" \"$PAPERCLIP_API_URL/api/issues/{issueId}/heartbeat-context\"" })
```
If `$PAPERCLIP_WAKE_COMMENT_ID` is set, read that comment first:
```
run_shell_command({ command: "curl -s -H \"Authorization: Bearer $PAPERCLIP_API_KEY\" \"$PAPERCLIP_API_URL/api/issues/{issueId}/comments/$PAPERCLIP_WAKE_COMMENT_ID\"" })
```
Otherwise, on a cold start only, load all comments:
```
run_shell_command({ command: "curl -s -H \"Authorization: Bearer $PAPERCLIP_API_KEY\" \"$PAPERCLIP_API_URL/api/issues/{issueId}/comments\"" })
```

### 5. Do the work
Perform the agent-specific work defined in the calling HEARTBEAT. This skill does not
define what the work is.

### 6. Update status and comment (mandatory)
On completion:
```
run_shell_command({ command: "curl -s -X PATCH -H \"Authorization: Bearer $PAPERCLIP_API_KEY\" -H 'Content-Type: application/json' -H \"X-Paperclip-Run-Id: $PAPERCLIP_RUN_ID\" -d '{\"status\": \"done\", \"comment\": \"<short result summary>\"}' \"$PAPERCLIP_API_URL/api/issues/{issueId}\"" })
```
On a blocker:
```
run_shell_command({ command: "curl -s -X PATCH -H \"Authorization: Bearer $PAPERCLIP_API_KEY\" -H 'Content-Type: application/json' -H \"X-Paperclip-Run-Id: $PAPERCLIP_RUN_ID\" -d '{\"status\": \"blocked\", \"comment\": \"<what blocks me and what the Head of Department or human must do>\"}' \"$PAPERCLIP_API_URL/api/issues/{issueId}\"" })
```

### 7. Escalate (on anomalies)
Open a task for the agent's department head. `{supervisorAgentId}` is the agent's
supervisor — resolve it from the agent's Paperclip configuration, not from these files.
```
run_shell_command({ command: "curl -s -X POST -H \"Authorization: Bearer $PAPERCLIP_API_KEY\" -H 'Content-Type: application/json' -H \"X-Paperclip-Run-Id: $PAPERCLIP_RUN_ID\" -d '{\"title\": \"...\", \"description\": \"...\", \"assigneeAgentId\": \"{supervisorAgentId}\", \"parentId\": \"{issueId}\", \"goalId\": null}' \"$PAPERCLIP_API_URL/api/companies/$PAPERCLIP_COMPANY_ID/issues\"" })
```

## Close
Comment any open `in_progress` task before ending. If there is nothing to do, end
cleanly.

## Maintenance
This skill is the single source of truth for the Paperclip task lifecycle. If the
Paperclip API or the routine changes, update it here once — every agent inherits the
change. Long command blocks may be wrapped into small shell scripts later without
changing this skill's contract.
