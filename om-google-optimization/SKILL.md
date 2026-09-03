---
name: om-google-optimization
description: Nightly performance optimization of a single Google Ads property by an optimizer agent — read campaign performance from Supabase, evaluate it against the property's documented goals, and make bounded live adjustments (manual bids, smart-bidding targets, keywords, negatives, targeting, budget reallocation and pacing) within the property's autonomy level, then document every decision for the weekly reviewer. Use this whenever an optimizer agent runs its optimization cycle or needs to decide and apply changes to a live Google Ads account. New-campaign creation lives in `om-google-campaign-creation`; permission ceilings live in `om-autonomy-levels`.
---

# Google Ads — Live Optimization

This skill teaches an optimizer agent how to optimize **one property's** live Google Ads
campaigns on its nightly run. The shape of every run is the same: read the performance,
judge it against the property's goals, make only the changes the property's autonomy
level permits, verify them, and write down every decision so the weekly reviewer can
learn from the outcome.

The agent **proposes; humans dispose.** Anything beyond the autonomy ceiling is escalated,
never executed. Money is real and changes are live — when in doubt, do nothing and
escalate.

## What this skill covers

- Reading and aggregating campaign performance from Supabase (`agent_reads` views).
- Judging performance against the goals in `strategy.md` using a weighted multi-window score.
- Bounded live adjustments within autonomy: manual bids (`MANUAL_CPC`), smart-bidding
  targets (tCPA/tROAS), keywords and negatives, asset/ad variations, targeting bid
  modifiers, and budget reallocation + pacing.
- Verifying every change via the Google Ads MCP.
- Documenting every decision — and every run, even no-change ones — in `decision-log.md` for the reviewer.

## What this skill does NOT do

- **Create new campaigns, ad groups, or asset groups.** That is `om-google-campaign-creation`.
- **Enable, pause, or delete whole campaigns autonomously.** Pausing a top-performer or any
  campaign-level enable/pause/delete is a human decision → escalate (see `om-autonomy-levels`).
- **Change `strategy.md` or `budget.csv`.** Both are read-only inputs here. Durable plan
  changes are escalated to Peggy to be written into `strategy.md`.
- **Raise the property's total monthly budget.** Never. Escalate.
- **Enable AI Max or change asset automation.** Always a human decision, at every autonomy level (see `om-autonomy-levels`). The fields and preconditions are in `om-google-ads-reference/references/ai-max.md`.
- **Reporting.** The monthly report is Peggy's; outcome review is the reviewer's.

If a request or a finding falls into the above, stop and escalate with a clear note.

**How to escalate — this is a Paperclip action, not a sentence in the log.** Escalating
means handing the **run issue** up the chain exactly as `lx-paperclip-inbox-cycle` Step 6b
defines it: reassign the issue to my supervisor (`{supervisorAgentId}` — Peggy) **and** set
its status to `todo`, with a short comment naming the concrete decision or fix I need. That
reassignment **is** the escalation. Writing `Status: escalated` in `decision-log.md` only
*records* it — it never stands in for the reassignment. I **never** set an issue to `blocked`
to push a problem upward, and I never treat a log entry or a comment as the handoff: an
escalation that did not reassign an issue to Peggy did not happen.

---

## Inputs — read these before doing anything

Read in this order; if any required document is missing or the account is unreachable,
do not optimize — escalate (operational failures are handled in `HEARTBEAT.md`).

| Source | Read for | Rights |
| :--- | :--- | :--- |
| `data-sources.md` | Technical wiring: Supabase tenant + view prefix, Google Ads `customer_id` / `login-customer-id`, MCP linkage | READ |
| `client.md` | `autonomy_level` (drives every permission below) | READ (human-owned) |
| `strategy.md` | The **goal**: target CPA/ROAS, KPIs, intended campaign split | READ (never write) |
| `budget.csv` | The **monthly ceiling** (sacred) | READ (human-owned) |
| `learnings.md` | The reviewer's accumulated lessons — let them inform decisions | READ |
| `decision-log.md` | The agent's **own prior decisions** — what was last changed and when (settling) | READ + WRITE |
| `KI-Wissen/Google` | Current best practice / new features (optional, judgment-informing) | READ |

Pre-flight: the account is reachable; Supabase has data for the property; **the conversion
action is healthy** — Google Ads shows it as recording or merely "no recent conversions",
the tag is detected, and the status is not *Inactive / Unverified / no tag detected*.
**Zero conversions is not, by itself, a tracking failure** — at low click volume (see the
sample floor under *Settling / grace*) zero conversions is the expected outcome on a small
pilot, not a broken tag. Treat tracking as *broken* only on an **explicit signal** (the
conversion action is Inactive/Unverified, or the tag is not detected/firing); only then is
smart bidding blind — do not optimize on it, and escalate. Resolve `customer_id` (and
`login-customer-id` under an MCC) from `data-sources.md`.

---

## Data path: Supabase to read, Google Ads (MCP) to write

> BigQuery is gone (deleted 2026-09-02). Any instruction anywhere that still names a
> BigQuery dataset or a `v_<property>_*` view is stale — report it rather than working
> around it.

- **Read performance from Supabase**, through the property's own scoped role:
  `~/.supabase-ro/q.sh <tenant> -c "<SQL>"`. Resolve `<tenant>` and the view prefix from
  `data-sources.md`. The role can see **only** its own `agent_reads.<prefix>_*` views — that
  is the tenant isolation, not a formality. Never try to reach the raw schema.
- **Write changes via the Google Ads MCP.** All mutations go through MCP, never SQL.
- **Verify a change you just made via MCP/GAQL, not Supabase.** GAQL is immediately
  consistent; Supabase is refreshed once a night (05:15 UTC) and its freshest complete day is
  **yesterday** — never react to "today". The division of labour: **history and trends from
  Supabase, point-in-time verification from GAQL.**

### The five views, and what each is for

| View | Read it for |
| :--- | :--- |
| `<prefix>_campaign_trends` | **The first read of every run.** 7d/30d per campaign with week-over-week change. |
| `<prefix>_budget_utilization` | Before **any** budget or bid decision. Carries `budget_stand_vom` — the date of the budget snapshot it used. |
| `<prefix>_campaign_performance_daily` | Day-by-day, when something in the trends needs explaining. |
| `<prefix>_search_term_daily` | What people actually typed. The basis for negatives and for harvesting new keywords. |
| `<prefix>_keyword_performance_daily` | Keyword outcome **joined to that day's bid and quality score** — effect and lever side by side. |

**Amounts in these views are already EUR** (`cost_eur`, `avg_cpc_eur`, `cpc_bid_eur`). The
underlying tables store micros; you never see them and never convert.

---

## Evaluating performance: the weighted multi-window score

Judge each campaign (or lower level) on a recency-weighted blend of **disjoint** windows,
so the most recent day is not counted multiple times.

- **Buckets (disjoint):** `day 0–1`, `day 2–7`, `day 8–30`.
- **Default weights:** `0–1d = 10 %`, `2–7d = 50 %`, `8–30d = 40 %`. (Defaults — tunable;
  see *Parameter defaults* below.)
- **Blend rate metrics** (CPA, ROAS, CTR, conversion rate) — never absolute volumes, or the
  30-day bucket dwarfs the rest.
- **Significance floor per bucket:** a bucket counts only if it clears a minimum volume
  (e.g. enough clicks/conversions to be meaningful). If it does not, **redistribute its
  weight** over the qualifying buckets — never feed a near-empty 24 h bucket in as noise.

```
score = Σ (wᵢ × rateᵢ)   over buckets i that pass the significance floor
        (weights wᵢ renormalized over the passing buckets)
```

- **The score is diagnosis only.** Compare it to the target in `strategy.md`: is performance
  off, and in which direction?
- **Tolerance band:** act only when the deviation from target exceeds a minimum threshold.
  Do not react to ±2 % noise.
- **The score never sets the size of the change.** *Whether* to act comes from the score;
  *how much* you may change comes solely from `om-autonomy-levels`.

---

## Settling / grace period (the anti-thrash rule)

- **New campaigns:** hands-off until the learning phase is genuinely complete — **time AND
  minimum volume**, not the calendar alone. Default ≈ **7 days** (matches the smart-bidding
  learning phase; see `bidding-strategies.md`).
- **After *any* material change** — including the agent's own (target/strategy switch, large
  budget move) — let the lever settle before touching it again; a material change restarts
  the learning phase. Read `decision-log.md` to know when each lever was last changed.
- **Grace = "don't tune", not "don't look".** Hard failures are still observed and
  **escalated** (reassign up, per the escalation rule above) during the grace period — they
  are not optimizations. A hard failure is: no impressions ≥ 3 days; conversion tracking
  broken **on an explicit signal** (not merely zero conversions); or meaningful spend with
  **zero conversions despite a sufficient click sample** (a floor — e.g. ≥ 30–50 clicks in
  the window). **Below that click floor, zero conversions is statistical noise on a small
  pilot, not a failure** — it is a normal `RUN — no action`, never an escalation.
- **No data yet is not a failure.** If the property's Supabase views return **no rows at all** (the nightly sync has not covered this account yet — normal in the first one to two nights after go-live — or the campaign has never delivered), that is a benign `RUN — no action`, never a failure or escalation. The `no impressions ≥ 3 days` hard-failure test applies only once the property has at least 3 days of data coverage.

---

## The levers — and how autonomy gates them

Which levers are allowed, and by how much, comes entirely from `om-autonomy-levels` (read
the property's `autonomy_level` from `client.md`). **This skill does not restate the
percentages** — that is the single source of truth. Map each finding to the right lever:

- **Bids vs. targets depends on the bidding mode.**
  - `MANUAL_CPC` campaigns → manual bid changes.
  - Smart bidding (tCPA/tROAS) → there are no manual bids; the equivalent lever is the
    **target**, which is a higher-autonomy action. A property whose level does not permit
    target changes optimizes via keywords, negatives, assets, and budget reallocation.
- **Keywords:** add negatives from the search-term report; add new long-tail keywords
  within the documented strategy.
- **Assets / ads:** add new ad variations. **RSAs are not edited in place** — create a new
  `AdGroupAd` and remove the old one (see `search-rsa-spec.md`); performance data does not
  carry over, so do not iterate casually.
- **Targeting:** geo / device / ad-schedule bid modifiers; audience refinements.
- **Budget:** tactical reallocation **between** campaigns within the monthly ceiling, plus
  pacing (see below). Pausing individual poor keywords/assets is allowed; pausing a whole
  campaign is an escalation.

Every change within the autonomy ceiling takes effect **live and immediately** — there is
no PAUSED handover here. That is exactly why the ceilings, the settling rule, and
verification matter: the autonomy level is the gate, not a per-action human click.

---

## Budget model & pacing

- `budget.csv` is the **total monthly** ceiling: client-approved, human-owned, read-only,
  and **never exceeded**.
- `strategy.md` holds the **intended split** across campaigns. The optimizer reads it and
  may deviate tactically, but cannot write it.
- **Tactical reallocation** between campaigns within the monthly ceiling is allowed up to the
  autonomy %, logged in `decision-log.md` as a deviation from the `strategy.md` plan.
- A reallocation that proves durable is **escalated to Peggy** to be written into
  `strategy.md` — that keeps Drive the truth for allocation.
- **Pacing:** the ceiling is monthly but Google Ads budgets are daily. Reason against
  **month-to-date spend vs. the monthly total**, and pace so the sum of daily budgets cannot
  overshoot the monthly ceiling before month end.

---

## Verify every change

After each mutation, before logging it, verify via the Google Ads MCP (GAQL), **not**
Supabase — the nightly sync will not show the change until tomorrow. Use the canonical
reads in `gaql-verification-queries.md`. Confirm the new value is in place, the resource
still has the intended status, and no
`policy_summary.approval_status` is `DISAPPROVED`. If a mutate returns an error, look it up
in `common-errors.md`; anything not covered, or any `PROHIBITED` policy topic, is a hard
stop → escalate (do not retry, do not invent a workaround).

---

## Document every decision (the reviewer's contract)

`decision-log.md` is **the contract between this skill (writer) and the reviewer (reader)**.
The reviewer reads it weekly and judges the 14-day impact, so every entry must carry the
**baseline** — without pre-change values there is no before/after.

**Add your entry with `gdrive_append_file` (`position: "start"`).** It reads the current
`decision-log.md` and writes your text **above** the existing content server-side, so the
reviewer's history is preserved automatically — pass only your new entry as `content`, never
the whole file. (Fallback only if `gdrive_append_file` is unavailable: a manual
read-modify-write — `gdrive_read_file` the full file, prepend your entry, then
`gdrive_write_file` the **entire** combined document. **Never** `gdrive_write_file` only your
new entry: it overwrites the whole file, which is exactly how a nightly run once wiped the
log.)

**Write-safety discipline (do this on every write — the reviewer's trust depends on it):**

1. **Dedup guard — check before you write.** Read the current top of the log first. If an
   entry with the *same timestamp and the same decision* is already there, the write already
   happened (a retry, a double-run) — **do not append it again.** A duplicated entry makes the
   reviewer double-count one action.
2. **`position: "start"` is mandatory, never the default end-append.** The log is strictly
   **newest-first**. Appending at the end (the tool's default) is a bug: it buries the entry
   below older ones and a top-down window read misses it. Always pass `position: "start"`.
3. **Verify after writing — and self-heal.** Re-read the log and confirm three things: your
   new entry is now **at the very top**, it appears **exactly once**, and the older entries are
   **all still present**. If it landed at the end, is duplicated, or the history is missing,
   the write went wrong — fix it now (remove the duplicate / restore correct newest-first order
   via a manual read-modify-write) before ending the run. Do not leave a malformed log for the
   reviewer.

Append one entry per decision, including proposals and escalations:

```
## [YYYY-MM-DD HH:MM] — <campaign / ad group / keyword> — <lever>
- Trigger: <what the score showed; which metric is off target, direction>
- Baseline (pre-change): <metric>=<value> | 0–1d / 2–7d / 8–30d: <…> | target (strategy.md): <…>
- Action: <exact change, e.g. tCPA 25.00 → 22.50 € (−10 %)>
- Autonomy: <level> — within ceiling: yes
- Status: executed | proposed | escalated
- Hypothesis: <what should improve, and by when>
- Settling until: <date — this lever is not touched again before then>
```

### Always leave a dated run marker

Every run writes at least one dated entry, even when nothing was changed. This serves two
purposes at once: it tells the reviewer the agent ran (and, on a quiet night, that it
*deliberately* changed nothing), and it is the dated marker the `HEARTBEAT.md` idempotency
check reads to know today's run already happened.

- On a run **with** decisions: the decision entries above already carry today's date — they
  *are* the marker. Do not add a redundant extra entry.
- On a run with **no** action (deviation inside the tolerance band, or every candidate lever
  still in settling/grace): append exactly one run marker.

```
## [YYYY-MM-DD HH:MM] — RUN — no action
- Reviewed: <campaigns / levels checked>
- Reason: <within tolerance band | all candidate levers in settling/grace | insufficient data>
- Next: <when the next meaningful check or lever becomes due, if known>
```

A hard failure spotted during grace (no impressions ≥ 3 days; conversion tracking broken on
an explicit signal; or meaningful spend with zero conversions despite a sufficient click
sample, e.g. ≥ 30–50 clicks) is **not** a "no action" run — it is an escalation: reassign
the run issue up per `lx-paperclip-inbox-cycle` Step 6b **and** log it with
`Status: escalated` in the decision format above. Zero conversions at low click volume is a
normal `RUN — no action`, not an escalation.

(If the decision-log format changes, the reviewer skill depends on it — keep them in step.
The `RUN — no action` marker is part of that contract: the reviewer must treat it as
"ran, no change", not as a decision to evaluate.)

---

## The run sequence

1. **Resolve wiring** from `data-sources.md` (Supabase tenant + view prefix, `customer_id`, MCC if any).
2. **Read context:** `client.md` (autonomy level), `strategy.md` (goals), `budget.csv`
   (ceiling), `learnings.md`, `decision-log.md` (own history), optionally `KI-Wissen/Google`.
3. **Pull performance** from Supabase at the needed levels (start with `<prefix>_campaign_trends`).
4. **Score** each campaign with the weighted multi-window blend; compare to targets; apply
   the tolerance band.
5. **Drop anything in settling/grace** from the action candidates (but escalate hard failures).
6. **For each candidate action:** check `om-autonomy-levels`. Within ceiling → apply via MCP.
   Beyond ceiling, durable plan change, or unclear justification → **escalate** (reassign the
   run issue to Peggy + `todo`, per `lx-paperclip-inbox-cycle` Step 6b — *not* a new child
   issue to her, and never `blocked`), do not act.
7. **Verify** each applied change via MCP/GAQL.
8. **Document** every decision — executed, proposed, and escalated — in `decision-log.md`
   via `gdrive_append_file` (`position: "start"`), which preserves the prior entries. If the
   run produced **no** decisions at all, still add the dated `RUN — no action` marker, so the
   run is recorded and today's idempotency marker exists.
9. **Close-out self-check:** monthly pacing still within ceiling; no campaign left in a hard-
   failure state unescalated; every change logged with a baseline; **today's run is recorded
   in `decision-log.md`** (decision entries or a `RUN — no action` marker dated today) **and
   the prior entries are still present** (you prepended, you did not overwrite the history).

---

## Parameter defaults

These are **skill defaults**, controlled because they steer agent behaviour — not casually
editable: window buckets (0–1 / 2–7 / 8–30 d), weights (10 / 50 / 40 %), grace ≈ 7 days,
the per-bucket significance floor, and the tolerance band. Revisit them with experience;
externalize the numbers only if retuning becomes frequent (avoid premature structure).

---

## References

Load on demand from the shared `om-google-ads-reference` skill — read only what the current
task touches:

- `om-google-ads-reference/references/bidding-strategies.md` — strategy fields, thresholds,
  migration path, learning-phase notes.
- `om-google-ads-reference/references/gaql-verification-queries.md` — post-change verification reads.
- `om-google-ads-reference/references/common-errors.md` — error lookup, remediation, escalation rule.
- `om-google-ads-reference/references/search-rsa-spec.md` — RSA rebuild rules (new ad, remove old), pinning.
- `om-google-ads-reference/references/pmax-asset-types.md` — PMax asset specs (for asset-group adjustments).

Permission ceilings: `om-autonomy-levels`. New-campaign creation: `om-google-campaign-creation`.

## Maintenance
This skill owns the optimization *procedure and discipline* (the score, the settling rule,
the budget/pacing model, the decision-log format). API spec lives in `om-google-ads-reference`;
permission ceilings in `om-autonomy-levels`; evolving best practice in Drive `KI-Wissen/Google`.
Keep those single sources of truth — do not restate them here.