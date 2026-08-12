---
name: om-amazon-negative-targeting
description: Weekly waste-negative management for a single Amazon property by the negative Targeter agent — find search terms and ASINs that spend without converting (or convert far above the ACOS target) and add them as negatives (negative-exact for clean isolation) so budget stops leaking. Handles waste negatives only; graduation negatives (a winner promoted to Exact and negated in its source) belong to the positive Targeter, because harvesting and negating-in-source are one action. Use whenever the negative Targeter runs its weekly cycle. Bidding belongs to om-amazon-optimization.
---

# Amazon Advertising — Negative Targeting (Waste Negatives)

This skill teaches the **negative Targeter** agent how to stop budget leaking on a property. It runs **weekly**. It handles exactly one of the manifest's two kinds of negatives:

- **Waste negatives (this skill):** irrelevant / non-converting / far-over-target terms and ASINs → add to negative lists so they stop being served.
- **Graduation negatives (NOT this skill):** a proven winner promoted to Exact-Profit and negated in its discovery source — that is one logical action and lives in `om-amazon-positive-targeting`.

> **Waste-negative ruleset DEFINED (2026-06-25).** Thresholds in *Waste detection* below. Calibrated to be **stricter than a bid-down** (negation is permanent): the zero-conversion click-floor is posture-specific (from each posture's measured CVR), backed by a money trigger. Starting values — expected to tighten with experience.
>
> **Query-level negation UNLOCKED (2026-08-11).** The Search Term report is ingested nightly (`agent_reads.<prefix>_sp_search_term_daily`), so waste can now be judged on the **actual customer query** rather than only on the booked keyword. This is what makes AUT waste addressable at all.

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

> **Judge only fully attributed days: `date <= current_date - 7`.** Both triggers below rest on **0 orders**, and orders are counted on a **7-day attribution window** — so a click from the last seven days *cannot yet* carry the order that would clear it. Counting those clicks charges a term for a verdict it had no chance to earn, and the sentence is permanent. This is stricter than the general freshness rule ("don't react to today"), and it applies to the **click and spend sums too**, not just to the order count: drop the unsettled days from the aggregate entirely rather than dividing a mature numerator by a fresh denominator.
>
> **Measured, not theoretical (2026-08-12).** In the first live candidate list, `freixenet solare aperitivo` showed 17 clicks / €15.05 / 0 orders against a GEN floor of 17 — one click over the line. Split by maturity: **8 settled clicks + 9 from the last seven days.** On settled data it sits at 8, less than half the floor. It was the *only* discovered negation candidate in the whole account; with the correct window there were none. An unfiltered query does not merely add noise here — it manufactures the entire candidate list.

**1. Zero-conversion click-floor (posture-specific).** A term with **0 orders** and clicks ≥ the floor — set so that "0 orders" is genuinely improbable for a real winner (≈ `ln(0.10)/ln(1−CVR)`, i.e. <10 % chance a true converter would still show zero). From the measured posture CVRs:

| Posture | CVR | 0-order negation floor |
| :-- | :-- | :-- |
| MRK | 32 % | ≥ 6 clicks |
| GEN | 12.5 % | ≥ 17 clicks |
| WTB | 7.4 % | ≥ 30 clicks |
| AUT | 5.3 % | ≥ 43 clicks, **query-level only** — apply the floor to the search term, never to the AUT match type itself (negating `close-match` would switch the campaign off) |

**2. Money trigger (fires below the click-floor too).** **0 orders AND spend ≥ 2 × the product's break-even CPA** (= price × target_ACOS; e.g. €30 product × 18 % = €5.40 → negate at ≈ €11 spent with nothing back).

**3. Target miss with conversion (2026-08-12).** Triggers 1 and 2 both require **0 orders**, so a term that converts *and* burns money was invisible to this skill. A **discovered** term with **≥ 1 order**, **eff_ACOS ≥ 3 × the strategy's target ACOS**, on **≥ 20 clicks** now qualifies. Discovered only — an AUT row, or a search term that differs from the booked keyword. A *booked* target that overspends stays a bid problem and goes to the Optimizer as a handoff (see *Object scope*).

> **This trigger proposes; below Extended it does not negate on its own.** See `om-autonomy-levels` — the permission lives there, the threshold here.
>
> **Why it is set loose on purpose.** The two failure modes are not equally visible. A term negated too early leaves **silence** — no clicks, no rows, nothing anyone trips over — while a term tolerated too long leaves **spend**, and spend shows up in every report. You can only correct the mistake you can see, so the first version errs toward tolerating. Tighten it once the escalations have a track record, never the other way round.
>
> **Calibration (measured 2026-08-12, both tenants, settled window).** At 2 × target the trigger catches 3 cases / €44.85; at 3 × it catches 2 / €27.60; at 4 × one / €12.69. The click floor is not the binding constraint — 10, 15 and 20 clicks all yield the same set. **3 × is the natural cut** because it drops the one category head term in the 2 × set (`likör` at 2.85 ×) by economics alone, leaving two unambiguous AUT-discovered ASIN targets — so this trigger and the head-term guard in *Object scope* pull the same way instead of overlapping.
>
> **What this trigger does NOT solve.** Cross-brand leakage sits *below* any sane multiple: `windspiel gin` matched onto a Powerwolf ASIN runs at 1.4 × target. It is not economically wrong, it is **brand-wrong**, and no ACOS threshold will find it. That case belongs to head-term ownership enforcement, not here.

**Object scope — negate what you did *not* choose.** Negation removes *discovered* traffic: customer **search terms** (from the Search Term report) and **irrelevant ASIN targets** matched by broad/auto. A **deliberately-placed positive keyword** — every keyword in a MRK/GEN/WTB manual campaign is one the property chose — is **never a waste-negation candidate.** Negating a GEN campaign's own category head term (e.g. `aperitivo` in the Aperitivo GEN campaign) blinds the campaign to its reason to exist. A positive keyword that wastes is a **bid problem, not a negation problem**: the fix is a lower bid or a pause, both the Optimizer's levers. A keyword-level money-trigger candidate that is a positive keyword is therefore **routed to the Optimizer as a bid-down handoff** — log it under the shared decision-log envelope tagged `NegTgt` with `handoff → Optimizer: bid-down` plus the baseline metrics, and add **no** negative. The Optimizer reads these handoffs on its next run.

Since 2026-08-11 the distinction is directly readable: in `<prefix>_sp_search_term_daily`, `search_term` is what the customer typed and `keyword` is what we booked. Where the two differ, the waste is **discovered** traffic and negating the `search_term` is in scope; where a query merely restates a booked keyword, it is the bid handoff above. AUT rows (`target_type = 'TARGETING_EXPRESSION_PREDEFINED'`) are always discovered — the "keyword" there is only Amazon's match type (`close-match`, `substitutes`, …), never something the property chose, and must never itself be negated.

Three guards:
- **Object scope (above):** never negate a chosen positive keyword or a head/category-defining term (`strategy.md` §3 head-term ownership) — route it to the Optimizer as a bid-down handoff instead.
- **Don't kill terms still in the settling window** (they haven't had a fair chance) — this covers two different things: the **attribution** window (the mandatory `date <= current_date - 7` filter above, a property of the data) and the **Optimizer's** settling state after a recent bid change (coordinate via `decision-log.md`). Both must hold.
- **Respect the on-remove invariant** (manifest §4): never orphan a negative that should later flow back into discovery; and don't negate a term the positive Targeter is about to graduate (check recent `PosTgt` log entries to avoid the two agents fighting).

Add waste negatives as **negative-exact** keywords and **negative product (ASIN)** targets, in the correct campaign/ad group (negative-phrase blocks too broadly — manifest §4).

## Reading at scale — push the filter down
The property may carry **20–50+ campaigns**, but waste is rare: at pilot budget a full week yields only a **handful of candidates** (single digits is normal). The context cost of a run scales with the **candidate count, not the campaign count** — as long as the read is done right.

- **Never pull per-campaign target/keyword inventories into context to eyeball them.** That scales with campaign count and will not fit at 30–50 campaigns. The Ads API `query_*` calls are for the **write target lookup and verify read-back only**, not for scanning performance.
- **Run one aggregate query (per posture) that returns only threshold-breaching rows.** Aggregate the week window per `target_id` / `keyword_id` / `search_term` (`sum(clicks)`, `sum(orders_7d)`, `sum(spend)`) from the property's Supabase reader, then filter **in SQL** to the waste thresholds (`orders = 0 AND clicks ≥ posture floor`, or `orders = 0 AND spend ≥ 2 × break-even-CPA`). **The window is the week that ended seven days ago** — `date between current_date - 14 and current_date - 7` — not the week just past; see the attribution rule in *Waste detection*. Only candidates come back — typically single digits — no matter how many campaigns exist. Break-even-CPA (price × target_ACOS) comes from the product catalog / `strategy.md`; join it in SQL or apply it to the returned rows. Column/view names live in `om-amazon-ads-reference` → `supabase-schema.md`.
- **Chunk by ASIN only if a week ever returns a large candidate set** (e.g. onboarding a new ASIN with fresh AUT waste): process one ASIN's candidates → log → next; never hold the whole account's raw performance at once. At steady state a single query covers the property.

## Run sequence (draft)
1. Inbox cycle first (`lx-paperclip-inbox-cycle`); a comment/task wake is handled, not the weekly mandate.
2. On the weekly tick: idempotency check (a run dated this week already logged? → close); open the dated run issue; check out.
3. Resolve wiring; read context — `strategy.md` (targets), `learnings.md`, own `decision-log.md`, and recent `PosTgt` entries (avoid conflicts), autonomy from `client.md`.
4. Pull the week-window waste **candidates** from Supabase with a single pushed-down aggregate query per posture (see *Reading at scale* — filter to threshold-breaching rows in SQL; never scan full inventories; chunk by ASIN only if the candidate set is large). **Judge only fully attributed days** (`date <= current_date - 7`) — the ~1-day freshness lag is not enough for a 0-order verdict, see *Waste detection*.
5. Apply the waste thresholds → candidate negatives (**discovered search terms + irrelevant ASINs**), excluding anything still settling or pending graduation. A wasteful **positive keyword** never becomes a negative — log it as a **bid-down handoff to the Optimizer** (see *Object scope*), do not negate it. **Trigger-3 candidates are proposed, not applied**, unless the property is Extended (`om-autonomy-levels`) — and every trigger-3 candidate is logged with its metrics **whether or not the human accepts it**, because the record of what was proposed and refused is the only evidence a later tightening can rest on. Without it you are back to reasoning from silence.
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
