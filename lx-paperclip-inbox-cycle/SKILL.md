---
name: lx-paperclip-inbox-cycle
description: The shared Paperclip wake-up routine for every Lexacore agent. Defines the canonical task lifecycle run on each heartbeat — read wake context, load assigned tasks, check out a task, load its context, do the work, then close the issue with a valid status. Covers the routing rules that keep the escalation chain moving without dead-ends - escalate upward by reassigning the issue to the supervisor and setting it to todo, delegate downward by creating a sub-issue for a subordinate, and never leave an issue blocked or without a concrete assignee. Use this whenever an agent's HEARTBEAT runs, so the task-handling commands live in exactly one place instead of being copied into every agent. The agent's own work step is supplied by the calling HEARTBEAT.
---

# Paperclip Inbox Cycle

Every Lexacore agent runs this same task lifecycle on each heartbeat. Only the
"do the work" step differs per agent; everything around it is identical and lives here.
HEARTBEAT files reference this skill instead of repeating the commands.

In Paperclip, an issue's **disposition is its status** — there is no separate field. The
disposition is set by a `PATCH /api/issues/{id}` that changes `status`. A **comment is
context, never a disposition**, and the PATCH body has **no `comment` field** — so a
status change and a comment are always **two separate calls** (post the comment to
`/comments`, then PATCH the status). The valid statuses are `backlog`, `todo`,
`in_progress`, `in_review`, `done`, `cancelled`, `blocked`.

**Why this matters (the failure this skill prevents).** When a run ends, Paperclip's
liveness check looks at every issue the run had checked out. If such an issue is left
`in_progress`, assigned to the same agent, with **no active delegated child** — or if the
run only commented without changing the status — Paperclip raises a *stale-disposition
warning*, fails auto-recovery, and reassigns the issue to a **recovery owner (the
supervisor)**. That is exactly why a supervisor keeps getting pulled into routine runs.
So **every path in Step 6 ends by setting a terminal or handoff status explicitly** — a
comment alone is never enough.

**The `in_progress` trap.** `in_progress` is a valid *end-of-run* state in **one** case
only: delegate-down (Step 6c), where you have just created a child issue that is now
actively assigned to a subordinate, so the parent legitimately waits. In every other
case, ending `in_progress` is read as a missing disposition. "I still need to keep
monitoring" is **not** a reason to stay `in_progress` — see below.

**A no-action run is still a completed run.** If today's pass needs no changes — or you
are waiting out a settling / observation period — that is `done`, with a one-line
"no action" comment. The continued monitoring is the **next** scheduled run's own dated
issue; it is never a reason to keep today's issue open. `blocked` is likewise never a
close-out (see rule 1 below).

All commands use the Paperclip environment variables present at wake-up:
`$PAPERCLIP_API_KEY`, `$PAPERCLIP_API_URL`, `$PAPERCLIP_AGENT_ID`, `$PAPERCLIP_RUN_ID`,
`$PAPERCLIP_COMPANY_ID`, `$PAPERCLIP_TASK_ID`, `$PAPERCLIP_WAKE_REASON`,
`$PAPERCLIP_WAKE_COMMENT_ID`. Substitute `{issueId}` with the task ID and
`{supervisorAgentId}` with the agent's supervisor as configured in Paperclip.

## Two rules that keep the chain moving

1. **Never leave an issue `blocked`, and never leave it without a concrete assignee.**
   `blocked` is a dead-end: other agents skip it (Step 2) and it must be revived by a
   human. If I cannot finish an issue myself, I route it to a real agent (up or down) —
   I do not block it. `blocked` is reserved for humans/manual use.
2. **Routing is structured, never prose.** Handing work on means setting the assignee
   *and* the status — not writing a comment that asks someone to take over. A comment
   carries context; it is never the handoff itself, and a pasted transcript never counts
   as a disposition.

## When to use
On every heartbeat, before any agent-specific work. Paperclip tasks always have
priority. When no task is waiting, control returns to the calling HEARTBEAT: a purely
reactive agent ends there; an agent with a scheduled standing mandate proceeds to that
mandate.

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

If no tasks are assigned, the inbox is clear. A purely reactive agent ends the heartbeat
here — it creates nothing on its own initiative. An agent whose HEARTBEAT defines a
**scheduled standing mandate** (e.g. a nightly optimizer) instead proceeds to that
mandate and opens its own run issue (Step 7). That is configured work, not self-invented
work; the *when* lives in the agent's HEARTBEAT, never here.

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
The context carries the issue's `projectId` and `parentId`. Note the `projectId` — you
need it if you create a sub-issue in Step 7.

### 5. Do the work
Perform the agent-specific work defined in the calling HEARTBEAT. This skill does not
define what the work is.

**Data integrity (read this before acting on any figure or fact).** A failed or empty
file read is **not** data. I never infer a document's contents from the issue thread,
prior comments, a decision log, or memory. If a read returns empty or errors, the file is
*missing* — I re-check the canonical path from `lx-gdrive-onlinemarketing` (e.g.
`budget.csv` lives under `02_Projektdurchführung/[Channel]/[property]/`, not in
some older location), and if it is still absent I treat it as a missing **required**
document and halt/escalate per Step 6, rather than substituting a remembered or
thread-mentioned value. This is exactly how a wrong budget slips in — a €900 figure
carried in the issue thread must never override (or stand in for) the €100 that an empty
read failed to return from `budget.csv`. Drive is the truth; the conversation is not.

### 6. Close the issue with a disposition (mandatory)
Every checked-out issue ends this run with exactly one of the outcomes below. Each is
**two calls**: first an optional context comment, then the status PATCH that *is* the
disposition. The status PATCH is the last act of the run, so the issue ends with a clean
disposition. Never end a run with the issue left unattended, with only a comment and no
status change, left `in_progress` without an active delegated child, or `blocked`.

**6.1 — record the context (recommended).** Post one short, structured comment. The body
field is `body`; this is a separate endpoint from the status PATCH.
```
run_shell_command({ command: "curl -s -X POST -H \"Authorization: Bearer $PAPERCLIP_API_KEY\" -H 'Content-Type: application/json' -H \"X-Paperclip-Run-Id: $PAPERCLIP_RUN_ID\" -d '{\"body\": \"<short result or handoff summary>\"}' \"$PAPERCLIP_API_URL/api/issues/{issueId}/comments\"" })
```

**6.2 — set the disposition (mandatory).** Exactly one of:

**a) Done — the work is finished, including a no-change or settling-period pass.**
```
run_shell_command({ command: "curl -s -X PATCH -H \"Authorization: Bearer $PAPERCLIP_API_KEY\" -H 'Content-Type: application/json' -H \"X-Paperclip-Run-Id: $PAPERCLIP_RUN_ID\" -d '{\"status\": \"done\"}' \"$PAPERCLIP_API_URL/api/issues/{issueId}\"" })
```

**b) Escalate up — beyond my autonomy, or a blocker I cannot resolve (including infra/access problems).**
Reassign the issue to my supervisor and set it back to `todo`, so it lands actionable in
their inbox. The 6.1 comment states the concrete decision or action I need — not a
narrative. This replaces blocking: I never set `blocked` to push a problem upward.
```
run_shell_command({ command: "curl -s -X PATCH -H \"Authorization: Bearer $PAPERCLIP_API_KEY\" -H 'Content-Type: application/json' -H \"X-Paperclip-Run-Id: $PAPERCLIP_RUN_ID\" -d '{\"status\": \"todo\", \"assigneeAgentId\": \"{supervisorAgentId}\"}' \"$PAPERCLIP_API_URL/api/issues/{issueId}\"" })
```
If I am at the top of the chain (no supervisor configured), I escalate to the human
owner per Paperclip configuration instead of to a `{supervisorAgentId}`.

**c) Delegate down — I have decided and a subordinate should execute.** (Supervisors only.)
Create a sub-issue for the chosen subordinate (Step 7), then set *this* issue to
`in_progress` so it stays mine while the sub-issue runs. This is the **only** valid
`in_progress` end-of-run state, because a child is now actively assigned downward. When
the sub-issue is resolved and I have reviewed the result, I close this issue `done`
(outcome a).
```
run_shell_command({ command: "curl -s -X PATCH -H \"Authorization: Bearer $PAPERCLIP_API_KEY\" -H 'Content-Type: application/json' -H \"X-Paperclip-Run-Id: $PAPERCLIP_RUN_ID\" -d '{\"status\": \"in_progress\"}' \"$PAPERCLIP_API_URL/api/issues/{issueId}\"" })
```

**d) Cancel — the work has become moot.**
```
run_shell_command({ command: "curl -s -X PATCH -H \"Authorization: Bearer $PAPERCLIP_API_KEY\" -H 'Content-Type: application/json' -H \"X-Paperclip-Run-Id: $PAPERCLIP_RUN_ID\" -d '{\"status\": \"cancelled\"}' \"$PAPERCLIP_API_URL/api/issues/{issueId}\"" })
```

The remaining statuses (`backlog`, `in_review`) are not part of the standard agent
close-out; use them only if a specific workflow introduces them. `blocked` is never an
agent close-out (rule 1).

### 7. Create an issue (delegate down, or a scheduled agent's own run)
Creating an issue is the one write that adds new board work. Two cases use the same
command — only `assigneeAgentId`, `parentId`, and `projectId` differ:

- **Delegate down (sub-issue):** `assigneeAgentId` = the chosen subordinate;
  `parentId` = this issue (quoted id); `projectId` = this issue's project (from the
  context in Step 4).
- **Scheduled standing mandate (self-run):** `assigneeAgentId` = `$PAPERCLIP_AGENT_ID`
  (itself); `parentId` = the JSON literal `null` (unquoted, no parent);
  `projectId` = the agent's own project.

```
run_shell_command({ command: "curl -s -X POST -H \"Authorization: Bearer $PAPERCLIP_API_KEY\" -H 'Content-Type: application/json' -H \"X-Paperclip-Run-Id: $PAPERCLIP_RUN_ID\" -d '{\"title\": \"...\", \"description\": \"...\", \"assigneeAgentId\": \"<assignee>\", \"parentId\": <parent>, \"projectId\": \"<projectId>\", \"goalId\": null}' \"$PAPERCLIP_API_URL/api/companies/$PAPERCLIP_COMPANY_ID/issues\"" })
```
`<assignee>` = subordinate's agentId (delegate) or `$PAPERCLIP_AGENT_ID` (self-run).
`<parent>` = `"{issueId}"` (delegate, quoted) or `null` (self-run, unquoted).
`<projectId>` = this issue's project (delegate) or the agent's own project (self-run).

A self-created run issue is normally `todo`/`backlog` at creation, so the same agent
checks it out (Step 3) and closes it (Step 6) through the normal lifecycle.

**Direction of the chain.** Escalation goes **up by reassignment** (Step 6b), never by
creating a child assigned to a supervisor. Sub-issues always go **down** to a subordinate
who executes; the parent stays with the delegating agent until the child is resolved and
reviewed. This keeps the whole chain — subordinate → supervisor → back down as
instructions → reviewed and closed — running without orphaned or blocked issues.

## Close
Before ending: every issue I checked out this run carries a status that names a clear
next step and a concrete assignee. Nothing is left `blocked`, unassigned, or silently
`in_progress` without a reason recorded. If there was nothing to do, end cleanly.

## Maintenance
This skill is the single source of truth for the Paperclip task lifecycle. If the
Paperclip API or the routine changes, update it here once — every agent inherits the
change. Long command blocks may be wrapped into small shell scripts later without
changing this skill's contract.
