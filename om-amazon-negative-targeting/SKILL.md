---
name: om-amazon-negative-targeting
description: Weekly waste-negative management for a single Amazon property by the negative Targeter agent — find search terms and ASINs that spend without converting (or convert far above the ACOS target) and add them as negatives (negative-exact for clean isolation) so budget stops leaking. Handles waste negatives only; graduation negatives (a winner promoted to Exact and negated in its source) belong to the positive Targeter, because harvesting and negating-in-source are one action. Use whenever the negative Targeter runs its weekly cycle. Bidding belongs to om-amazon-optimization.
---

# Amazon Advertising — Negative Targeting (Waste Negatives)

This skill teaches the **negative Targeter** agent how to stop budget leaking on a property. It runs **weekly**. It handles exactly one of the manifest's two kinds of negatives:

- **Waste negatives (this skill):** irrelevant / non-converting / far-over-target terms and ASINs → add to negative lists so they stop being served.
- **Graduation negatives (NOT this skill):** a proven winner promoted to Exact-Profit and negated in its discovery source — that is one logical action and lives in `om-amazon-positive-targeting`.

> **Waste-negative ruleset DEFINED (2026-06-25).** Thresholds in *Waste detection* below. Calibrated to be **stricter than a bid-down** (negation is permanent): the zero-conversion click-floor is posture-specific (from each posture's measured CVR), backed by a money trigger. Starting values — expected to tighten with experience and once the Search Term report is ingested (AUT waste lives at the query level, which needs that report).

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

## Waste detection — the core mechanic
A search term/ASIN is a **waste candidate** when it spends without paying back. Negation is permanent, so the bar is **higher than a bid-down** (a marginal term is the Optimizer's job, not this skill's). Two triggers, either qualifies:

**1. Zero-conversion click-floor (posture-specific).** A term with **0 orders** and clicks ≥ the floor — set so that "0 orders" is genuinely improbable for a real winner (≈ `ln(0.10)/ln(1−CVR)`, i.e. <10 % chance a true converter would still show zero). From the measured posture CVRs:

| Posture | CVR | 0-order negation floor |
| :-- | :-- | :-- |
| MRK | 32 % | ≥ 6 clicks |
| GEN | 12.5 % | ≥ 17 clicks |
| WTB | 7.4 % | ≥ 30 clicks |
| AUT | 5.3 % | query-level only — needs the Search Term report (a single AUT keyword rarely reaches the floor on pilot budget) |

**2. Money trigger (fires below the click-floor too).** **0 orders AND spend ≥ 2 × the product's break-even CPA** (= price × target_ACOS; e.g. €30 product × 18 % = €5.40 → negate at ≈ €11 spent with nothing back).

Two guards:
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
This skill owns the *waste-negative procedure* and its thresholds (*Waste detection*). Invariants live in the manifest; per-property targets/prices feed the money trigger from `strategy.md` + the product catalog; API/schema in `om-amazon-ads-reference`. The reviewer reads this agent's `decision-log.md` too — keep the log format in step.
