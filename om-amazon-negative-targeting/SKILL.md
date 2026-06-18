---
name: om-amazon-negative-targeting
description: Weekly waste-negative management for a single Amazon property by the negative Targeter agent — find search terms and ASINs that spend without converting (or convert far above the ACOS target) and add them as negatives (negative-exact for clean isolation) so budget stops leaking. Handles waste negatives only; graduation negatives (a winner promoted to Exact and negated in its source) belong to the positive Targeter, because harvesting and negating-in-source are one action. Use whenever the negative Targeter runs its weekly cycle. Bidding belongs to om-amazon-optimization.
---

# Amazon Advertising — Negative Targeting (Waste Negatives)

This skill teaches the **negative Targeter** agent how to stop budget leaking on a property. It runs **weekly**. It handles exactly one of the manifest's two kinds of negatives:

- **Waste negatives (this skill):** irrelevant / non-converting / far-over-target terms and ASINs → add to negative lists so they stop being served.
- **Graduation negatives (NOT this skill):** a proven winner promoted to Exact-Profit and negated in its discovery source — that is one logical action and lives in `om-amazon-positive-targeting`.

> **Scaffold status — PENDING HUMAN INPUT.** The **waste-negative ruleset** — the thresholds that make a term/ASIN a waste candidate (e.g. clicks/spend with zero conversions; ACOS far over target with a sufficient sample), and the protections against over-negating (don't kill terms still in the settling window) — is part of the pending negative ruleset (architecture memo §12.6). Do not invent thresholds.

## What this skill covers
- Reading search-term and target performance from Supabase (week window).
- Identifying waste: spend without conversion above a click floor; ACOS far over the strategy's target with a sufficient sample.
- Adding **negative-exact** keywords and **negative product (ASIN)** targets in the right campaign/ad group (manifest: negative-exact for clean isolation; negative-phrase blocks too broadly).
- Respecting the on-remove invariant: never orphan a negative that should later flow back into discovery (coordination with the positive Targeter's maintenance).

## What this skill does NOT do
- **Graduation negatives / harvesting** → `om-amazon-positive-targeting`.
- **Bid changes / pausing campaigns** → `om-amazon-optimization` / escalation.
- **Change `strategy.md` / `budget.csv`** — read-only.

## Inputs
`data-sources.md`, `client.md` (autonomy), `strategy.md` (targets), `learnings.md`, `decision-log.md` (own history), `KI-Wissen/Amazon`.

## Waste detection — the core mechanic (draft)
A search term/ASIN is a **waste candidate** when it spends without paying back: clicks/spend with zero conversions above a click floor, or ACOS far over the strategy's target with a sufficient sample. The exact thresholds are the **pending waste ruleset** — do not invent them. Two guards:
- **Don't kill terms still in the settling window** (they haven't had a fair chance) — coordinate with the Optimizer's settling state via `decision-log.md`.
- **Respect the on-remove invariant** (manifest §4): never orphan a negative that should later flow back into discovery; and don't negate a term the positive Targeter is about to graduate (check recent `PosTgt` log entries to avoid the two agents fighting).

Add waste negatives as **negative-exact** keywords and **negative product (ASIN)** targets, in the correct campaign/ad group (negative-phrase blocks too broadly — manifest §4).

## Run sequence (draft)
1. Inbox cycle first (`lx-paperclip-inbox-cycle`); a comment/task wake is handled, not the weekly mandate.
2. On the weekly tick: idempotency check (a run dated this week already logged? → close); open the dated run issue; check out.
3. Resolve wiring; read context — `strategy.md` (targets), `learnings.md`, own `decision-log.md`, and recent `PosTgt` entries (avoid conflicts), autonomy from `client.md`.
4. Pull the week-window search-term / target performance from Supabase (respect the ~1-day lag).
5. Apply the waste thresholds → candidate negatives (keywords + ASINs), excluding anything still settling or pending graduation.
6. Add negative-exact entries in the correct campaigns within autonomy; **escalate** anything beyond the band (per the inbox cycle — never `blocked`).
7. **Verify** via the Ads API; **document** every decision in the per-property `decision-log.md` using the shared envelope (`om-amazon-optimization` → *Decision-log contract*), tagged `NegTgt`; on a no-change week write one dated `RUN — no action` marker.
8. Close-out self-check per the inbox cycle (nothing left `in_progress`/`blocked`; history preserved).

## References
- `om-amazon-advertising-manifest` — negation rules, match-type guidance (binding).
- `om-amazon-ads-reference` — `match-types.md`, `sp-object-model.md`, `supabase-schema.md`, `report-types.md`.
- `om-autonomy-levels` — what the Targeter may change vs. escalate.
- `lx-paperclip-inbox-cycle` — close-out / escalation.

## Maintenance
This skill owns the *waste-negative procedure*. Invariants live in the manifest; thresholds are the pending ruleset; API/schema in `om-amazon-ads-reference`. The reviewer reads this agent's `decision-log.md` too — keep the log format in step.
