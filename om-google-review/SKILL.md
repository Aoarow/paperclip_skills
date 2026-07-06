---
name: om-google-review
description: Weekly outcome review of a single Google Ads property by the Reviewer agent — read the decision-log of every worker agent on the property (for lexacore.ai currently just the Optimizer), measure the ~14-day impact of each decision against the property's goals using fresh data from BigQuery, judge whether each decision was justified AND stayed inside its autonomy ceiling, and distil the durable lessons into learnings.md (the file every worker agent reads at the start of its next run). Use whenever the Reviewer agent runs its weekly cycle. The Reviewer never touches the ad account — it writes learnings and escalates; account changes belong to the worker agents within their autonomy. This is the reference review method for every channel; a channel-specific reviewer (om-amazon-review, …) mirrors its structure.
---

# Google Ads — Weekly Review

This skill teaches the **Reviewer** agent how to turn a week of a property's decisions into
durable lessons. It is the property's learning loop: the worker agents act and log; the
Reviewer judges the outcomes and writes `learnings.md`; every worker reads `learnings.md` at
the start of its next run — otherwise the decision-log is a write-only diary that never
changes behaviour.

**Who runs this:** the property's **Reviewer** agent, once a week. One Reviewer per property.

**This is the reference method for all channels.** The *structure* below — Inputs → Review
method → `learnings.md` contract → Run sequence — is what every channel reviewer follows.
What is channel-specific (the outcome data source, the doctrine the decisions are judged
against) is called out so a sibling skill can swap it without re-deriving the method.

**The Reviewer proposes lessons; it does not mutate the account.** It writes only
`learnings.md`. Anything that needs an account change is a *recommendation* in `learnings.md`;
anything systemic or urgent is **escalated** (reassign the run issue up + `todo`, per
`lx-paperclip-inbox-cycle` Step 6b), never executed here.

---

## Scope — what is reviewed

The Reviewer reads the property's **`decision-log.md`**, which every worker agent appends to.
For **lexacore.ai** that is currently a single writer — the **Optimizer** (nightly). The
method is built for **N worker agents** per property: when a property later gains more workers
(targeters, research), they append to the same single log, each entry tagged with its agent
and lever, and the Reviewer sees them as one timeline. Reading the whole timeline — not one
agent in isolation — is the point: it is where **cross-decision** patterns live (a bid raised,
cut, then raised again = thrashing; two agents fighting the same lever).

The decision-log **entry format is owned by `om-google-optimization`** (its *Document every
decision* section). This skill is the *reader* of that contract; keep the two in step.

---

## Inputs — read these before judging anything

| Source | Read for | Rights |
| :--- | :--- | :--- |
| `data-sources.md` | Technical wiring: BigQuery dataset, Google Ads `customer_id` — how to pull outcomes | READ |
| `decision-log.md` | Every worker decision in the review window (~last 14 days), each with its baseline | READ |
| `strategy.md` | The goals to judge against: target CPA/ROAS, KPIs, intended campaign split | READ (never write) |
| `client.md` | Account/property context + the `autonomy_level` each decision had to stay within | READ (human-owned) |
| `budget.csv` | The monthly ceiling — was pacing/reallocation kept inside it? | READ (human-owned) |
| `learnings.md` | Its own prior lessons: don't repeat them, and track whether they held | READ + WRITE |
| `om-autonomy-levels` | The ceiling each decision is checked against (channel-agnostic) | READ (skill) |

If a required document is missing or BigQuery is unreachable, do **not** invent a review —
stop and escalate (operational failures are handled in `HEARTBEAT.md`).

---

## Outcome data: read from BigQuery

- **Measure outcomes from BigQuery** — the same rate metric the decision targeted (CPA, ROAS,
  CTR, conversion rate), over a window comparable to the decision's baseline window.
- **BigQuery lags ~1 day.** The freshest bucket is yesterday; never measure "today".
- Outcome data is the channel-specific input. On Amazon the equivalent source is Supabase; the
  *method* below is identical, only the table you read changes.

---

## The review method

For **each** decision in the window that has cleared its **settling period** (a decision still
settling cannot yet be judged — record it as "still settling, re-check next week"):

1. **Recover the baseline** from the decision-log entry. Every entry carries its pre-change
   values — that is the writer↔reader contract. No baseline → you cannot judge it; flag the
   missing baseline as a decision-log hygiene issue.
2. **Measure the outcome** from BigQuery: the same metric, after the change, over a comparable
   window (respect the ~1-day lag).
3. **Judge the outcome** — helped / hurt / neutral — against the target in `strategy.md` *and*
   against the decision's own stated hypothesis. Use the same significance discipline as the
   optimizer's scoring: do not draw a conclusion from a near-empty sample. "No clear signal
   yet" is a valid, honest verdict.
4. **Judge the decision, not only the outcome.** Two independent checks:
   - **Was it justified?** Did the logged trigger actually warrant the action, or did the
     Optimizer act inside the tolerance band / on noise?
   - **Was it inside the ceiling?** Cross-check the change against `om-autonomy-levels` for the
     property's `autonomy_level`. A decision can produce a good number and still be a problem
     if it exceeded the autonomy the property was granted — name that plainly.
   A well-reasoned decision with a bad outcome is a *learning*, not a *fault*; a lucky outcome
   from an unjustified or over-ceiling decision is a *fault* to flag.
5. **Look across decisions** in the window for patterns a per-decision view misses — thrashing
   on one lever, a budget reallocation that quietly fought the monthly pacing, a change made
   before the previous one had settled. (On multi-worker properties this is also where
   cross-*agent* conflicts surface.)
6. **Extract a lesson only when the evidence supports one.** A one-off or an unsupported hunch
   does not earn a place in `learnings.md`.

---

## Output — the learnings.md contract

`learnings.md` is what actually changes the workers' behaviour, so it must stay **actionable
and short** — every worker reads it at the start of every run. A finding that would not change
a future decision does not belong there.

**Append with `gdrive_append_file` (`position: "start"`)** — it writes your entry *above* the
existing content server-side, preserving the whole history; pass only your new entry as
`content`, never the whole file. (Fallback only if `gdrive_append_file` is unavailable: manual
read-modify-write — `gdrive_read_file` the full file, prepend your entry, `gdrive_write_file`
the **entire** combined document. **Never** `gdrive_write_file` only your new entry — that
overwrites the file and erases the history.) Either way, **re-read after writing** and confirm
your new entry *and* the older entries all survive.

One dated entry per weekly run. **The header carries the ISO-week tag** so the idempotency
check is a deterministic string match, never date arithmetic. Get the tag from the shell —
`date +%G-W%V` (e.g. `2026-W28`); **never compute the week by hand.**

```
## [YYYY-MM-DD · <ISO-week from `date +%G-W%V`, e.g. 2026-W28>] — Weekly review (window: <from>–<to>)
- Reviewed: <#decisions, by agent/lever — e.g. Optimizer: 3 bid, 1 budget>
- What worked: <decision → measured outcome → the lesson>  (or "—")
- What didn't: <decision → measured outcome → the lesson>  (or "—")
- Discipline: <justified & inside ceiling? any over-ceiling / unjustified / thrashing move named — or "clean">
- Cross-decision: <thrashing / pacing conflict / acting before settled — or "none">
- Recommendations (workers / human): <concrete, e.g. "tCPA moves on Campaign X overshoot — tighten step to 5%" — or "—">
- Still settling (re-check next week): <decisions not yet judgeable — or "—">
- Held / broke: <did a prior learning hold up this week? — or "—">
- Escalated: <run-issue ref, if a systemic problem was handed up — or "—">
```

A quiet week is still a completed review: write the entry, note "no strong signal". Prune or
supersede stale lessons in the same pass rather than let the file grow into noise — but never
delete the *history* of a genuine past lesson; mark it superseded.

---

## Run sequence

1. **Inbox cycle first** (`lx-paperclip-inbox-cycle`). A comment/task wake is handled as that
   task, **not** as the weekly mandate.
2. On the scheduled **weekly** tick: **idempotency check (deterministic, by ISO week).** Get this
   run's week id from the shell — `date +%G-W%V` (e.g. `2026-W28`) — and scan `learnings.md` for a
   review header already carrying that exact tag. Present → close, done. **Never** judge the week by
   eyeballing dates or counting days in your head: read the current tag from the command and match
   the string. A Saturday entry tagged `2026-W27` does **not** match a Monday run's `2026-W28`.
3. **Open the dated review run issue**, assigned to self, and check it out.
4. **Read context:** `data-sources.md` (wiring), `decision-log.md` (the window), `strategy.md`
   (goals), `client.md` (autonomy level), `budget.csv` (ceiling), prior `learnings.md`.
5. **Pull outcome data** from BigQuery for each decision's metric and window.
6. **Apply the review method** per decision; synthesise the cross-decision patterns.
7. **Write one dated `learnings.md` entry** (append at start; re-read to confirm history
   survived). **Escalate** any systemic finding — broken tracking, a strategy mismatch, a
   repeated harmful pattern, or a decision that breached the autonomy ceiling — up the chain
   (reassign the run issue to the supervisor + `todo`); a recommendation in the log is not an
   escalation.
8. **Close the run issue `done`** with a one-line result comment. A no-lesson week still
   closes `done`. Never leave it `in_progress`, never set `blocked`. If the work genuinely
   cannot be completed (infra/access), escalate **up**.

---

## What this skill does NOT do

- **Change bids / keywords / negatives / targets / budget** — those are the workers' jobs
  within `om-autonomy-levels`. The Reviewer writes `learnings.md` and escalates; nothing else.
- **Change `strategy.md` / `budget.csv`** — human-owned. Recommend, never edit. A durable plan
  change is escalated to the department head to be written into `strategy.md`.
- **Write another agent's `decision-log.md`.** The Reviewer is the *only* writer of
  `learnings.md` and never touches a decision-log.

---

## References

- `om-google-optimization` — owns the **decision-log entry format** (the contract this skill
  reads, including the `RUN — no action` marker, which is "ran, changed nothing", not a
  decision to score). Keep the two in step.
- `om-autonomy-levels` — the permission ceilings each decision is checked against.
- `om-google-ads-reference` → `gaql-verification-queries.md` — canonical reads if an outcome
  must be confirmed against the live account rather than BigQuery.
- `lx-paperclip-inbox-cycle` — run / close / escalation mechanics.
- `lx-gdrive-structure` → `lx-gdrive-onlinemarketing` — Drive schema and read/write rules.

## Maintenance

This skill owns the *review procedure and the `learnings.md` contract*, and is the reference
method for every channel reviewer. The decision-log format is owned by `om-google-optimization`
— when it changes, update this skill in the same change, it depends on it. Goals live in
`strategy.md`; permission ceilings in `om-autonomy-levels`. Keep those single sources of truth
— do not restate them here.
