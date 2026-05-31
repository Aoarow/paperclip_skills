---
name: om-google-optimization
description: Nightly performance optimization of a single Google Ads property by an optimizer agent — read campaign performance from BigQuery, evaluate it against the property's documented goals, and make bounded live adjustments (manual bids, smart-bidding targets, keywords, negatives, targeting, budget reallocation and pacing) within the property's autonomy level, then document every decision for the weekly reviewer. Use this whenever an optimizer agent runs its optimization cycle or needs to decide and apply changes to a live Google Ads account. New-campaign creation lives in `om-google-campaign-creation`; permission ceilings live in `om-autonomy-levels`.
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

- Reading and aggregating campaign performance from BigQuery.
- Judging performance against the goals in `strategy.md` using a weighted multi-window score.
- Bounded live adjustments within autonomy: manual bids (`MANUAL_CPC`), smart-bidding
  targets (tCPA/tROAS), keywords and negatives, asset/ad variations, targeting bid
  modifiers, and budget reallocation + pacing.
- Verifying every change via the Google Ads MCP.
- Documenting every decision in `decision-log.md` for the reviewer.

## What this skill does NOT do

- **Create new campaigns, ad groups, or asset groups.** That is `om-google-campaign-creation`.
- **Enable, pause, or delete whole campaigns autonomously.** Pausing a top-performer or any
  campaign-level enable/pause/delete is a human decision → escalate (see `om-autonomy-levels`).
- **Change `strategy.md` or `budget.csv`.** Both are read-only inputs here. Durable plan
  changes are escalated to Peggy to be written into `strategy.md`.
- **Raise the property's total monthly budget.** Never. Escalate.
- **Reporting.** The monthly report is Peggy's; outcome review is the reviewer's.

If a request or a finding falls into the above, stop and escalate with a clear note.

---

## Inputs — read these before doing anything

Read in this order; if any required document is missing or the account is unreachable,
do not optimize — escalate (operational failures are handled in `HEARTBEAT.md`).

| Source | Read for | Rights |
| :--- | :--- | :--- |
| `data-sources.md` | Technical wiring: BigQuery dataset, Google Ads `customer_id` / `login-customer-id`, MCP linkage | READ |
| `client.md` | `autonomy_level` (drives every permission below) | READ (human-owned) |
| `strategy.md` | The **goal**: target CPA/ROAS, KPIs, intended campaign split | READ (never write) |
| `budget.csv` | The **monthly ceiling** (sacred) | READ (human-owned) |
| `learnings.md` | The reviewer's accumulated lessons — let them inform decisions | READ |
| `decision-log.md` | The agent's **own prior decisions** — what was last changed and when (settling) | READ + WRITE |
| `KI-Wissen/Google` | Current best practice / new features (optional, judgment-informing) | READ |

Pre-flight: the account is reachable; BigQuery has data for the property; **conversion
tracking is firing** (if it is broken, smart bidding is blind — do not optimize on it,
escalate). Resolve `customer_id` (and `login-customer-id` under an MCC) from `data-sources.md`.

---

## Data path: BigQuery to read, Google Ads (MCP) to write

- **Read performance from BigQuery** (cost, impressions, clicks, CTR, conversions,
  conversion value, CPA, ROAS, impression share + lost IS budget/rank, avg CPC, conversion
  rate) at the levels you need: campaign, ad group, keyword, search term, ad/asset.
- **Write changes via the Google Ads MCP.** All mutations go through MCP, never BigQuery.
- **BigQuery lags ~1 day.** Never react to "today"; the freshest bucket is yesterday.
  And **verify changes via MCP/GAQL, not BigQuery** — a just-made change will not appear in
  BigQuery until the next export.

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
- **Grace = "don't tune", not "don't look".** Hard failures (e.g. no impressions ≥ 3 days,
  tracking broken, spend with zero conversions) are still observed and **escalated** during
  the grace period — they are not optimizations.

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
BigQuery. Use the canonical reads in `gaql-verification-queries.md`. Confirm the new value
is in place, the resource still has the intended status, and no
`policy_summary.approval_status` is `DISAPPROVED`. If a mutate returns an error, look it up
in `common-errors.md`; anything not covered, or any `PROHIBITED` policy topic, is a hard
stop → escalate (do not retry, do not invent a workaround).

---

## Document every decision (the reviewer's contract)

`decision-log.md` is **the contract between this skill (writer) and the reviewer (reader)**.
The reviewer reads it weekly and judges the 14-day impact, so every entry must carry the
**baseline** — without pre-change values there is no before/after. Append one entry per
decision, including proposals and escalations:

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

(If the decision-log format changes, the reviewer skill depends on it — keep them in step.)

---

## The run sequence

1. **Resolve wiring** from `data-sources.md` (BigQuery dataset, `customer_id`, MCC if any).
2. **Read context:** `client.md` (autonomy level), `strategy.md` (goals), `budget.csv`
   (ceiling), `learnings.md`, `decision-log.md` (own history), optionally `KI-Wissen/Google`.
3. **Pull performance** from BigQuery at the needed levels.
4. **Score** each campaign with the weighted multi-window blend; compare to targets; apply
   the tolerance band.
5. **Drop anything in settling/grace** from the action candidates (but escalate hard failures).
6. **For each candidate action:** check `om-autonomy-levels`. Within ceiling → apply via MCP.
   Beyond ceiling, durable plan change, or unclear justification → escalate (Paperclip task
   to Peggy), do not act.
7. **Verify** each applied change via MCP/GAQL.
8. **Document** every decision — executed, proposed, and escalated — in `decision-log.md`.
9. **Close-out self-check:** monthly pacing still within ceiling; no campaign left in a hard-
   failure state unescalated; every change logged with a baseline.

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
