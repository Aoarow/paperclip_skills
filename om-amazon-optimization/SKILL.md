---
name: om-amazon-optimization
description: Daily performance optimization of a single Amazon property by an optimizer agent — read fresh ad performance from Supabase, run a deterministic bidding engine over all keywords/targets, and have the LLM set/adjust the bidding policy by reasoning over campaign-level aggregates and anomalies (not row-by-row), within the property's autonomy level, then document every decision for the weekly reviewer. ACOS is the in-loop control metric (TACOS is monthly, rolled up by the Account Manager). Use whenever an Amazon optimizer agent runs its daily cycle or needs to decide and apply bid/budget changes to a live Amazon advertising profile. Campaign creation lives in om-amazon-campaign-creation; keyword/target harvesting in om-amazon-positive-targeting; permission ceilings in om-autonomy-levels.
---

# Amazon Advertising — Daily Optimization

This skill teaches an optimizer agent how to optimize **one property's** live Sponsored Products campaigns on its daily run. The core design (architecture memo §7): **per-keyword bids are set by a deterministic engine (code/rules), not by the LLM per keyword.** The LLM sets/adjusts the *policy*, reviews **campaign-level aggregates**, handles exceptions/anomalies, and documents its reasoning. This is what keeps one optimizer per property cheap and unbounded by keyword count.

The agent **proposes; humans dispose.** Anything beyond the autonomy ceiling is escalated, never executed. Money is real and changes are live — when in doubt, do nothing and escalate.

**Ordering:** runs **after** successful nightly ingestion (Airbyte → Supabase). Stale data → wrong bid/budget moves → wasted spend.

> **Scaffold status — PENDING HUMAN INPUT.** The **bidding-policy ruleset** (the deterministic bid rules: ACOS-over-target + sufficient clicks → lower bid, the Research vs. Profit target-ACOS bands, etc. — architecture memo §12.5) is not yet written by Alexander. This skill can be scaffolded but **the optimization logic must not be invented.** Author the ruleset, then encode it here (and/or as a small script the skill invokes).

## What this skill covers
- Reading performance from **Supabase** (`amazon_ads_raw.*` / `public` views) at campaign / ad group / keyword / target / search-term level.
- The **deterministic bidding engine**: applying the bid ruleset across all keywords/targets (Research band vs. Profit band per the R/P tag from the manifest).
- The **LLM policy layer**: reasoning over campaign aggregates and anomalies; setting/justifying policy; staging proposals; escalating exceptions.
- Bounded live adjustments within autonomy: bids, budget reallocation between campaigns within the monthly ceiling, pausing individual poor keywords/targets.
- Verifying every change via the Ads API and documenting every run (incl. no-change) in `decision-log.md`.

## What this skill does NOT do
- **Create campaigns** → `om-amazon-campaign-creation`.
- **Harvest/graduate keywords or ASIN targets** → `om-amazon-positive-targeting` (monthly).
- **Add waste negatives** → `om-amazon-negative-targeting` (weekly).
- **Change `strategy.md` / `budget.csv`** — read-only inputs; durable plan changes escalate to the Account Manager / Peggy.
- **Raise the property's total monthly budget.** Never. Escalate.
- **Enable/pause/delete whole campaigns autonomously.** Escalate (see `om-autonomy-levels`).

## Inputs — read before doing anything
| Source | Read for | Rights |
| :--- | :--- | :--- |
| `data-sources.md` | Ads profile ID, marketplace, Supabase tables/connection, ingestion workflow | READ |
| `client.md` | `autonomy_level` | READ (human-owned) |
| `strategy.md` | goals: ACOS/TACOS target, head-term ownership map, distribution logic | READ (never write) |
| `budget.csv` | the monthly ceiling (sacred) | READ (human-owned) |
| product catalog (Supabase) | per-ASIN `priority` (traffic light) → **budget weighting** across products (manifest §8); category/stock context | READ |
| `learnings.md` | the reviewer's accumulated lessons | READ |
| `decision-log.md` | own prior decisions / settling | READ + WRITE |
| `KI-Wissen/Amazon` | current best practice (optional) | READ |

When reallocating budget across campaigns within the property total, **weight by the product's priority** (Prio 1 largest share, 2 normal, 3 smallest — manifest §8), within the autonomy band.

## The engine / policy split (the core mechanic)
- **Deterministic engine (code/ruleset):** applies the per-keyword/target bid arithmetic across *all* items every run — "ACOS over target + enough clicks → lower bid", Research band vs. Profit band per the R/P tag (manifest §3). Scales to thousands of items for ~nothing. **The exact rules are the pending bidding ruleset** — until written, the engine is scaffolded, not run.
- **LLM policy layer:** reads **campaign-level aggregates** (dozens of summaries, not thousands of rows), sets/justifies the policy, handles anomalies/exceptions, and decides what to escalate. It does **not** price individual keywords.
- **Autonomy gates two things:** the size of a single engine-applied bid change, and whether the LLM may change the policy/target-ACOS bands (`om-autonomy-levels`, Amazon map — Extended only for band changes).

## Settling / anti-thrash (draft)
- **New campaigns / new structures:** hands-off until both time **and** minimum volume are met — a change needs data before it can be judged. *(DRAFT: exact window TBD with the ruleset; don't tune on a near-empty sample.)*
- **After any material change** (incl. the engine's own), let the lever settle before touching it again; read `decision-log.md` to know when each lever last moved.
- **Grace = "don't tune", not "don't look":** hard failures (no impressions ≥ N days; tracking broken on an explicit signal; meaningful spend with zero conversions above a click floor) are still **escalated** during grace — they are not optimizations.

## Run sequence (draft)
1. Inbox cycle first (`lx-paperclip-inbox-cycle`); a comment/task wake is handled, not the daily mandate.
2. On the daily tick (after a successful ingestion): idempotency check — a run dated today already in `decision-log.md`? → close.
3. Open today's dated run issue; check out.
4. Resolve wiring (`data-sources.md`); read context (autonomy from `client.md`, `strategy.md`, `budget.csv`, `learnings.md`, own `decision-log.md`).
5. Pull performance from Supabase at campaign/keyword/target level (respect the ~1-day lag; freshest day is yesterday).
6. **Engine:** stage per-keyword/target bid changes against the R/P bands (pending ruleset).
7. **Policy:** review campaign aggregates + anomalies; drop anything in settling from the action set (but escalate hard failures); apply the autonomy band to each staged change.
8. Apply within-autonomy changes via the Ads API; **escalate** the rest (reassign the run issue up + `todo`, per the inbox cycle — never `blocked`).
9. **Verify** each applied change via the Ads API (not Supabase — a just-made change isn't ingested yet).
10. **Document** every decision in `decision-log.md` (append at `start`); on a quiet day still write the dated `RUN — no action` marker.
11. Close-out self-check: monthly pacing within the ceiling; nothing left in a hard-failure state unescalated; today's run recorded; prior history preserved (you prepended, not overwrote).

## Decision-log contract (shared by all property agents)
`decision-log.md` is **one file per property**, appended to by the Optimizer, positive Targeter, and negative Targeter, and read by the **Reviewer** (`om-amazon-review`). Every entry is tagged with the **agent** and **lever** so the timeline is parseable and the Reviewer can judge impact and spot cross-agent interactions. **Every entry carries the baseline** — without pre-change values there is no before/after for the Reviewer.

Append with `gdrive_append_file` (`position: "start"`); never `gdrive_write_file` only your entry (it wipes the file). Re-read after writing to confirm new + old entries survive.

```
## [YYYY-MM-DD HH:MM] — <AGENT: Optimizer|PosTgt|NegTgt> — <campaign / keyword / target / ASIN> — <lever>
- Trigger: <what the data showed; which metric is off target, direction>
- Baseline (pre-change): <metric>=<value> | windows used | target (strategy.md): <…>
- Action: <exact change, e.g. bid 0.45 → 0.38 € (−16 %); or "graduated 'pfeffer gin' → Exact-Profit, negated in AUT">
- Autonomy: <level> — within band: yes
- Status: executed | proposed | escalated
- Hypothesis: <what should improve, by when>
- Settling until: <date — not touched again before then>
```
On a no-action run, append exactly one dated `## [..] — Optimizer — RUN — no action` marker (reason: within tolerance | all candidate levers settling | insufficient data). The Reviewer treats it as "ran, no change", not a decision to evaluate. (The targeter skills reuse this envelope with their own lever vocabulary.)

## References
- `om-amazon-advertising-manifest` — the R/P tag and its bidding meaning; strategy structure.
- `om-amazon-ads-reference` — `supabase-schema.md`, `report-types.md`, `sp-object-model.md`, `common-errors.md`.
- `om-autonomy-levels` — permission ceilings (the single source of truth; do not restate %).
- `lx-paperclip-inbox-cycle` — escalation = reassign the run issue up + `todo`, never `blocked`.

## Maintenance
This skill owns the optimization *procedure and discipline* (the engine/policy split, settling rule, decision-log contract). The bid *numbers/rules* are the pending ruleset; permission ceilings live in `om-autonomy-levels`; API/schema in `om-amazon-ads-reference`; evolving best practice in Drive `KI-Wissen/Amazon`.
