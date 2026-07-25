---
name: om-amazon-optimization
description: Daily performance optimization of a single Amazon property by an optimizer agent — read fresh ad performance from Supabase, run a deterministic bidding engine over all keywords/targets, and have the LLM set/adjust the bidding policy by reasoning over campaign-level aggregates and anomalies (not row-by-row), within the property's autonomy level, then document every decision for the weekly reviewer. ACOS is the in-loop control metric (TACOS is monthly, rolled up by the Account Manager). Use whenever an Amazon optimizer agent runs its daily cycle or needs to decide and apply bid/budget changes to a live Amazon advertising profile. Campaign creation lives in om-amazon-campaign-creation; keyword/target harvesting in om-amazon-positive-targeting; permission ceilings in om-autonomy-levels.
---

# Amazon Advertising — Daily Optimization

This skill teaches an optimizer agent how to optimize **one property's** live Sponsored Products campaigns on its daily run. The core design (architecture memo §7): **per-keyword bids are set by a deterministic engine (code/rules), not by the LLM per keyword.** The LLM sets/adjusts the *policy*, reviews **campaign-level aggregates**, handles exceptions/anomalies, and documents its reasoning. This is what keeps one optimizer per property cheap and unbounded by keyword count.

The agent **proposes; humans dispose.** Anything beyond the autonomy ceiling is escalated, never executed. Money is real and changes are live — when in doubt, do nothing and escalate.

**Ordering:** runs **after** successful nightly ingestion (Airbyte → Supabase). Stale data → wrong bid/budget moves → wasted spend.

> **Bidding-policy ruleset — DEFINED (2026-06-25).** The deterministic bid rules live in *The bidding-policy ruleset* below. Property-specific numbers (target-ACOS bands, AUT spend cap) are read from `strategy.md`; the engine **mechanism** (gate, weighted ACOS, dynamic max-CPC, step bands, settling) is doctrine here. Defaults were calibrated from Windspiel's 8-month history; a second property reviews them against its own data before reuse.

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
- **Deterministic engine (code/ruleset):** applies the per-keyword/target bid arithmetic across *all* items every run — "ACOS over target + enough clicks → lower bid", Research band vs. Profit band per the R/P tag (manifest §3). Scales to thousands of items for ~nothing. **The exact rules are in *The bidding-policy ruleset* below.**
- **LLM policy layer:** reads **campaign-level aggregates** (dozens of summaries, not thousands of rows), sets/justifies the policy, handles anomalies/exceptions, and decides what to escalate. It does **not** price individual keywords.
- **Autonomy gates two things:** the size of a single engine-applied bid change, and whether the LLM may change the policy/target-ACOS bands (`om-autonomy-levels`, Amazon map — Extended only for band changes).

## The bidding-policy ruleset
The engine is a **nudge** model (step the bid toward the target, not solve for a target-CPC) — deliberately, because pilot per-keyword volumes are thin and a computed target-CPC would itself be noisy. Six knobs; numbers in `strategy.md` are authoritative where they overlap.

### Canonical effective ACOS (used by every decision below)
Weight the **components** (spend and sales), then form the ratio — never average the per-window ACOS values (a low-volume window would distort the mean). Renormalize when a window is empty (a new keyword has no 31–90-day bucket → the present windows scale to 100 %).
```
eff_spend = Σ wᵢ·spendᵢ , eff_sales = Σ wᵢ·salesᵢ , eff_ACOS = eff_spend / eff_sales
windows:  0–2 d → 0.10 | 3–7 d → 0.30 | 8–30 d → 0.50 | 31–90 d → 0.10
```
The 0–2-day window is down-weighted on purpose: spend is reported immediately but sales lag 7–10 days, so the freshest days look artificially expensive.

### The six knobs
| # | Knob | Rule |
| :-- | :-- | :-- |
| 1 | **Significance gate** | Touch a keyword only if **active ≥ 21 days AND** its posture click-floor is met in the weighted window. Floor ≈ **3 / CVR** clicks (enough that "0 orders" is genuinely unlikely if it were a winner). Windspiel posture CVRs → floors: **MRK ≥ 5 · GEN ≥ 12 · WTB ≥ 20** clicks. Evidence is direction-aware: lowering needs enough clicks to believe "doesn't convert"; raising needs *proven* profitable conversions, not a low ACOS on a few clicks. **Maturity is also direction-aware: the 21-day requirement gates *raises and fine-tuning* — a protective *downward* move (knob 4 overspend) may act before day 21** once the posture click-floor is met, because stopping a bleed needs less evidence than confirming a winner, and a lower bid is reversible. **AUT has no per-keyword gate** — managed at campaign level (see *AUT*). |
| 2 | **Window** | the canonical eff_ACOS above. |
| 3 | **Step size** | per autonomy: **new** (project / campaign / keyword) **≤ 20 %**, **established ≤ 10 %** per change. With the 7-day settling (knob 6) a keyword moves at most ~weekly, so this is "per change", not compounding daily. Magnitude ceiling is enforced by `om-autonomy-levels`. **The band is a magnitude *limit*, not a target — for a confirmed overspend (knob 4) take the *maximum downward step the band allows* in one move; do not under-nudge a 300 %-ACOS bleeder at 10 %.** Protective **downward** steps are **exempt from the 7-day settling freeze** (knob 6), so a persistent bleeder can be cut again on the next run; raises always settle. When even the max band step cannot bring the bid to a safe level (bid ≫ dynamic max-CPC or ≫ Amazon's suggested range), **escalate the larger one-shot cut or a pause** — never silently leave it bleeding. |
| 4 | **Direction** | eff_ACOS > target + gate met → **lower**. eff_ACOS < target + impression headroom + proven conversions → **raise**. **Overspend** = gate-many clicks with **0 orders, OR ≤ 1 order at eff_ACOS ≥ 3 × target** (a token order at catastrophic ACOS is not a pass) → take the **max downward step now** (knob 3 severity path), **skip the 21-day maturity gate and the 7-day freeze**, and **escalate a larger cut or a pause** if repeated max-steps cannot stop the bleed. **Never negate — removing a chosen keyword is not this skill's lever and is the wrong fix; price it down or pause it.** Also fold in any `NegTgt` **bid-down handoffs** from the decision-log (waste candidates that are positive keywords, routed here rather than negated) as priority overspend candidates. |
| 5 | **Floor / ceiling** | bid floor **€0.07**. The binding economic ceiling is a **dynamic max-CPC = target_ACOS × CVR × price** (per product; e.g. €30 product, 12.5 % CVR, 18 % target → €0.68) — never bid above what the product can repay, especially in the looser Research band. Hard override **€5.00**: beyond it (either bound) requires human approval via the Account Manager. **Suggested-bid anchor (when available):** where `data-sources.md` exposes Amazon's suggested bid, a live bid **materially above the top of the suggested range** is an independent, **ACOS-free** overspend signal — a downward nudge toward the range is allowed even before ACOS matures, and a seed/live bid far above Amazon's suggestion is the earliest sign a keyword will bleed. |
| 6 | **Settling** | freeze a lever **7 days** after any change (read `decision-log.md` for the last move). **Override only downward** + escalate when pacing projects a budget overshoot (allowed/day = remaining budget ÷ remaining days) — the emergency exit may cut or pause, never raise. |

### AUT (Auto campaigns) — not bid per keyword
AUT is a discovery feeder, not a profit campaign. It carries **no ACOS target**. It is governed by **(a) a spend cap = the % of monthly budget set in `strategy.md`** (Windspiel: 10 %) and **(b) graduation yield** — how many terms it feeds into the real campaigns (owned by `om-amazon-positive-targeting`). Cap hit without graduations over several runs → throttle + escalate. The engine never prices individual AUT targets.

### Pacing
Spread the monthly ceiling evenly (allowed/day = remaining budget ÷ remaining days); reallocate across campaigns weighted by product `priority` (manifest §8). The `budget.csv` total is sacred — at risk of overshoot, throttle (knob 6 override), never top up.

## Settling / anti-thrash
- **New campaigns / new structures:** hands-off until **both** the 21-day window **and** the posture click-floor are met (knob 1) — a change needs data before it can be judged.
- **After any material change** (incl. the engine's own), the lever is frozen 7 days (knob 6); read `decision-log.md` to know when each lever last moved.
- **Grace = "don't raise", not "don't protect":** during the 21-day grace the engine still may not *raise* or fine-tune, but it **may take a protective downward step** on a clear overspend (knob 4) — stopping a bleed and cutting for pacing (knob 6) are always allowed. Hard failures (no impressions ≥ N days; tracking broken on an explicit signal; overspend above the posture click-floor) are still **escalated** during grace. **If the runtime lacks the bid-write tool (propose-only), a protective downward move is escalated as an *urgent proposal* — never dropped.**

## Run sequence (draft)
1. Inbox cycle first (`lx-paperclip-inbox-cycle`); a comment/task wake is handled, not the daily mandate.
2. On the daily tick (after a successful ingestion): idempotency check — a run dated today already in `decision-log.md`? → close.
3. Open today's dated run issue; check out.
4. Resolve wiring (`data-sources.md`); read context (autonomy from `client.md`, `strategy.md`, `budget.csv`, `learnings.md`, own `decision-log.md` — including recent `NegTgt` **bid-down handoffs** to fold into this run's overspend candidates).
5. Pull performance from Supabase at campaign/keyword/target level (respect the ~1-day lag; freshest day is yesterday).
6. **Engine:** stage per-keyword/target bid changes against the R/P bands (*The bidding-policy ruleset*) — apply the gate, the weighted eff_ACOS, direction, step, floor/dynamic-ceiling.
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
This skill owns the optimization *procedure and discipline* (the engine/policy split, the bidding-policy ruleset mechanism, settling rule, decision-log contract). Property-specific *numbers* (target-ACOS bands, AUT cap) live in `strategy.md`; permission ceilings in `om-autonomy-levels`; API/schema in `om-amazon-ads-reference`; evolving best practice in Drive `KI-Wissen/Amazon`.
