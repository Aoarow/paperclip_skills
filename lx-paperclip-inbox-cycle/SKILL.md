---
name: lx-paperclip-inbox-cycle
description: The shared Paperclip wake-up routine for every Lexacore agent. Defines the canonical task lifecycle run on each heartbeat — read wake context, load assigned tasks, check out a task, load its context, do the work, then close the issue with a valid status. Covers the routing rules that keep the escalation chain moving without dead-ends - escalate upward by reassigning the issue to the supervisor and setting it to todo, delegate downward by creating a blocking child issue for a subordinate and setting the parent blocked on it, and never leave an issue blocked without a linked blocker or without a concrete assignee. Use this whenever an agent's HEARTBEAT runs, so the task-handling commands live in exactly one place instead of being copied into every agent. The agent's own work step is supplied by the calling HEARTBEAT.
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
disposition guard looks at the issue the run worked on. If it is left `in_progress` and
none of these hold — another run or wake for the same issue is already queued, a question
or approval is pending, or the issue is **linked as blocked by an open issue** — Paperclip
posts "needs a disposition", wakes the agent once to fix it, and if that fails blocks the
issue on a **recovery owner (the supervisor)**. That is exactly why a supervisor keeps
getting pulled into routine runs. So **every path in Step 6 ends by setting a terminal or
handoff status explicitly** — a comment alone is never enough.

⚠️ **A child issue alone does not count.** The guard never looks at `parentId`. A parent
left `in_progress` with a perfectly assigned child still trips it — verified in the
Paperclip server code on 2026-09-19, after LEXA-871 did everything this skill used to
prescribe and still pulled in Roger twice. What counts is the **blocker link**, which
Step 6c creates.

**The `in_progress` trap.** `in_progress` is never a valid *end-of-run* state for an
agent. "I still need to keep monitoring" and "my child issue is still running" are both
**not** reasons to stay `in_progress` — see below and Step 6c.

**A no-action run is still a completed run.** If today's pass needs no changes — or you
are waiting out a settling / observation period — that is `done`, with a one-line
"no action" comment. The continued monitoring is the **next** scheduled run's own dated
issue; it is never a reason to keep today's issue open. Nor is `blocked` — that is only
for a parent waiting on linked children (rule 1 below).

All commands use the Paperclip environment variables present at wake-up:
`$PAPERCLIP_API_KEY`, `$PAPERCLIP_API_URL`, `$PAPERCLIP_AGENT_ID`, `$PAPERCLIP_RUN_ID`,
`$PAPERCLIP_COMPANY_ID`, `$PAPERCLIP_TASK_ID`, `$PAPERCLIP_WAKE_REASON`,
`$PAPERCLIP_WAKE_COMMENT_ID`. Substitute `{issueId}` with the task ID and
`{supervisorAgentId}` with the agent's supervisor as configured in Paperclip.

## Two rules that keep the chain moving

1. **Never leave an issue `blocked` without a linked blocker, and never without a concrete
   assignee.** `blocked` with nothing linked is a dead-end: nothing will ever wake it, and
   it must be revived by a human. If I cannot finish an issue myself, I route it to a real
   agent — up by reassignment (6b), down by a blocking child (6c). The **one** `blocked` an
   agent may set is the parent in 6c, where Paperclip itself holds the link to the child
   and wakes me when it is done. Every other `blocked` is reserved for humans.
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
unblock them — **except** when `$PAPERCLIP_WAKE_REASON` is `issue_blockers_resolved`: then
every child that blocked `$PAPERCLIP_TASK_ID` is `done`, and that parent is yours to review
and close now (Step 6c, last paragraph).
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
The context carries the issue's `projectId` and `parentId`. A child created in Step 7
inherits the `projectId` by itself; a self-run issue needs the agent's own project.

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
status change, left `in_progress`, or `blocked` without a linked child (6c).

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
Create each child through the **children endpoint with `blockParentUntilDone: true`**
(Step 7). Paperclip then links *this* issue as blocked by the child. After the last child
is created, set *this* issue to `blocked` (command below). It stays assigned to me.

Why this shape: the blocker link is what the disposition guard accepts (see "Why this
matters"), and it is also what brings me back — when **every** linked child is `done`,
Paperclip wakes me with `issue_blockers_resolved`. No comment, no polling, no supervisor.
On that wake I read the children's results, verify them against the parent's success
criteria, and close this issue `done` (outcome a) — or delegate again if something is
missing.

🔴 **A blocking child is closed `done`, never `cancelled`.** Paperclip only counts `done`
as resolved. A cancelled child leaves the parent `blocked` with no wake — silently stuck.
If a child's work turns out to be unnecessary, close it `done` with a comment saying why
it was not executed. If I cancel one of my own children myself, I finish the parent in the
same run.

🔴 **Two more ways this goes wrong — both observed on 2026-09-03, both cost a recovery
escalation each.** The child must be **assigned** and it must go **downward**. Check both
before the create call.

| Mistake | What it actually is | Do this instead |
| :--- | :--- | :--- |
| Child created and assigned to my **supervisor** | An escalation wearing a delegation's clothes | Escalate properly (6b): reassign **this** issue upward. Do not create a child. |
| Child created with **no assignee** | No active child exists, so the parent has no disposition | Set `assigneeAgentId` in the create call. A child without an assignee is not a delegation. |

**You cannot repair a delegation after you create it.** A `PATCH` or even a `comment` on a
child that is assigned to another agent returns
`403 Issue is outside this actor's authorization boundary`. The only remedy is to escalate
to a supervisor and ask them to cancel and re-create it — which costs several runs for what
is usually a typo. So: **verify the payload before the create call, not after.** Any list of
resource names, IDs or counts you hand down gets a read-back **first**; a wrong list does not
become right by being passed through escalation levels.

**One card, one reversible action.** A card that bundles several unrelated changes cannot
fail in isolation: one unfinished item holds the whole card open, and an open card with no
valid disposition feeds the recovery loop. On 2026-09-03 six of seven items succeeded in a
single run, and the seventh kept the parent alive through eight agent runs. Split by action,
not by topic.

After the children exist, set the parent (this command is the disposition):
```
run_shell_command({ command: "curl -s -X PATCH -H \"Authorization: Bearer $PAPERCLIP_API_KEY\" -H 'Content-Type: application/json' -H \"X-Paperclip-Run-Id: $PAPERCLIP_RUN_ID\" -d '{\"status\": \"blocked\"}' \"$PAPERCLIP_API_URL/api/issues/{issueId}\"" })
```
Then read the parent back (`GET /api/issues/{issueId}`): its `blockedBy` array must list
every child. If it is empty, the children were not created through the children endpoint —
the parent is then a dead-end `blocked`. Fix it in the same run by PATCHing
`{"blockedByIssueIds": ["<childId>", ...]}` (that is the write field; `blockedBy` is the
read field).

**d) Cancel — the work has become moot.**
```
run_shell_command({ command: "curl -s -X PATCH -H \"Authorization: Bearer $PAPERCLIP_API_KEY\" -H 'Content-Type: application/json' -H \"X-Paperclip-Run-Id: $PAPERCLIP_RUN_ID\" -d '{\"status\": \"cancelled\"}' \"$PAPERCLIP_API_URL/api/issues/{issueId}\"" })
```

The remaining statuses (`backlog`, `in_review`) are not part of the standard agent
close-out; use them only if a specific workflow introduces them. `blocked` is an agent
close-out **only** as the linked parent in 6c (rule 1).

### 7. Create an issue (delegate down, or a scheduled agent's own run)
Creating an issue is the one write that adds new board work. The two cases use
**different endpoints**.

**Delegate down (child issue)** — the children endpoint of this issue. It inherits the
parent's `projectId` by itself; `blockParentUntilDone: true` creates the blocker link that
6c depends on. Never create a delegated child through the company endpoint with a
`parentId` — that child exists, but blocks nothing, and the parent trips the guard.
```
run_shell_command({ command: "curl -s -X POST -H \"Authorization: Bearer $PAPERCLIP_API_KEY\" -H 'Content-Type: application/json' -H \"X-Paperclip-Run-Id: $PAPERCLIP_RUN_ID\" -d '{\"title\": \"...\", \"description\": \"...\", \"assigneeAgentId\": \"<subordinateAgentId>\", \"status\": \"todo\", \"blockParentUntilDone\": true}' \"$PAPERCLIP_API_URL/api/issues/{issueId}/children\"" })
```

**Scheduled standing mandate (self-run)** — the company endpoint, assigned to myself, no
parent, the agent's own project:
```
run_shell_command({ command: "curl -s -X POST -H \"Authorization: Bearer $PAPERCLIP_API_KEY\" -H 'Content-Type: application/json' -H \"X-Paperclip-Run-Id: $PAPERCLIP_RUN_ID\" -d '{\"title\": \"...\", \"description\": \"...\", \"assigneeAgentId\": \"'$PAPERCLIP_AGENT_ID'\", \"parentId\": null, \"projectId\": \"<projectId>\", \"goalId\": null}' \"$PAPERCLIP_API_URL/api/companies/$PAPERCLIP_COMPANY_ID/issues\"" })
```

A self-created run issue is normally `todo`/`backlog` at creation, so the same agent
checks it out (Step 3) and closes it (Step 6) through the normal lifecycle.

**Direction of the chain.** Escalation goes **up by reassignment** (Step 6b), never by
creating a child assigned to a supervisor. Sub-issues always go **down** to a subordinate
who executes; the parent stays with the delegating agent, `blocked` on its children, until
Paperclip wakes it and it is reviewed. This keeps the whole chain — subordinate →
supervisor → back down as instructions → reviewed and closed — running without orphaned
or dead-end issues.

## Close
Before ending: every issue I checked out this run carries a status that names a clear
next step and a concrete assignee. Nothing is left unassigned, `in_progress`, or `blocked`
without a linked child. If there was nothing to do, end cleanly.

## Maintenance
This skill is the single source of truth for the Paperclip task lifecycle. If the
Paperclip API or the routine changes, update it here once — every agent inherits the
change. Long command blocks may be wrapped into small shell scripts later without
changing this skill's contract.
