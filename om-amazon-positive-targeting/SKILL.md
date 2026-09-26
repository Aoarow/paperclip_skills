---
name: om-amazon-positive-targeting
description: Monthly keyword and ASIN-target harvesting for a single Amazon property by the positive Targeter agent — mine new converting search terms and competitor ASINs from the Auto/Broad-Research campaigns and the Search Term report, classify each winner as brand / competitor / generic and graduate it into the Exact-Profit campaign of that class (MRK / WTB / GEN — never by source campaign), propose WTB-Broad seeds from competitor signals below the graduation bar, and simultaneously negate each graduated term in its source campaign so attribution stays clean. Owns the negation-maintenance invariant (on-add) and enforces the property's head-term ownership map via cross-ASIN negation. Use whenever the positive Targeter runs its monthly cycle. Waste negatives (irrelevant/non-converting terms) belong to om-amazon-negative-targeting; bidding belongs to om-amazon-optimization.
---

# Amazon Advertising — Positive Targeting (Harvest & Graduate)

This skill teaches the **positive Targeter** agent how to grow a property's proven keyword/target base. It runs **monthly** because it reads raw search terms (chunking applies — but rarely, so it stays cheap). The discovery→harvest funnel and the negation web are doctrine — they live in the manifest; this skill is the *procedure* that executes them.

**Why harvest + negate-in-source is one action:** graduating a term to Exact-Profit *and* negating it in its discovery source (AUT/Broad) is a single logical move (manifest §4 "graduation negatives"). That is why it sits here, not with the negative Targeter.

> **Ruleset DEFINED (2026-06-25).** The **graduation threshold** (*Graduation* below), the **keyword-roster cap** (*The keyword roster*), and AUT's spend cap / graduation-yield framing (`strategy.md` + `om-amazon-optimization`) are all set. The manifest carries the negation *invariants*; the operational *numbers* now live here.
>
> **Data dependency RESOLVED (2026-08-11).** The **Search Term report** is ingested nightly and readable at `agent_reads.<prefix>_sp_search_term_daily`. Real customer searches are now ordinary rows — including the ones behind AUT campaigns, which book no keywords at all and were previously invisible. Harvesting is no longer confined to promoting existing Broad keywords to Exact; genuine discovery is live.

## What this skill covers
- Reading the **Search Term report** and Auto/Broad-Research performance from Supabase.
- Identifying converting search terms and competitor ASIN targets worth graduating.
- **Classification:** sort every winner into BRAND / COMPETITOR / GENERIC before routing: the destination follows what the term *is*, not the campaign that found it.
- **Graduation:** add the winner as an exact keyword / ASIN target in the Exact-Profit campaign of its class, **and** add it as a negative-exact in its source campaign (the same move).
- **Negation maintenance (on-add invariant, manifest §4):** a new positive in MRK/WTB → negative in GEN **and** AUT; a new positive in GEN → negative in AUT.
- **Head-term ownership enforcement (manifest §5):** keep each head term positive only on its owning ASIN; set negative-exact on all sibling ASINs of the brand (GEN + AUT).
- **Roster management:** hold each Exact-Profit campaign to its ≤ 15-keyword cap by swapping (not appending) — see *The keyword roster*.
- **WTB proposals:** competitor terms and foreign ASINs with orders below the graduation bar become a monthly WTB-Broad proposal per ASIN.
- **AUT yield:** AUT is judged on graduation output, not ACOS (spend cap in `strategy.md`); harvesting *from* AUT is the yield this skill produces.

## What this skill does NOT do
- **Waste negatives** (irrelevant/non-converting terms) → `om-amazon-negative-targeting`.
- **Bid changes** → `om-amazon-optimization`.
- **Change the head-term ownership map itself.** Ownership is a human decision (set/changed on review in `strategy.md`); this skill *enforces* it, never silently flips it.
- **Cross-property head-term arbitration** → the Account Manager.

## Inputs
`data-sources.md` (profile, Supabase, Search Term workflow), `client.md` (autonomy), `strategy.md` (head-term ownership map, goals), `learnings.md`, `decision-log.md` (own history), `KI-Wissen/Amazon`.

## Graduation — the core mechanic

> **Aggregate per search term × ASIN, never per search term alone (2026-08-12).** A property can hold several brands, and Amazon's auto-targeting will match one brand's query to another brand's product. Averaging a term across every ASIN it touched turns a real loser into a passing number, because the winners subsidise it.
>
> **Measured:** `windspiel gin` screened globally at **5.67 % ACOS** — a clear winner. It ran on **eight ASINs**, and the one carrying the **largest spend** was `B0FGK2TJNH` (a *Powerwolf* product) at **25.61 % ACOS** on €24.51 — well past the bar, on a competitor-brand query, invisible in the average. Screen per term × ASIN, then decide; a term qualifying on one ASIN and failing on another is not one candidate but two facts, and the failing side is usually a **negation** job, not a graduation one.

A search term/ASIN target **graduates** when it has proven it converts. **Qualifying test (2026-06-25):** over a **90-day look-back**, the term has **≥ 2 orders AND eff_ACOS ≤ 18 %** (the Profit target; use the optimizer's canonical weighted eff_ACOS). The 90-day window is deliberate — at pilot volume a winner needs time to accumulate two orders. A term below the bar stays in discovery; it is not forced up. Once qualified, graduation is **one atomic move**:
1. **Add** the term as an **exact keyword** (or the ASIN as a product target) in the **Exact-Profit** campaign of the strategy the term *belongs to* — see *Route by what the term is* below. The source campaign does **not** decide this.
2. **Negate-exact** the same term in its **discovery source** (the AUT or Broad-Research campaign it came from) — so it is served by exactly one campaign from now on.
3. **Apply the on-add negation-maintenance invariant** (manifest §4): a new positive in MRK/WTB → negative-exact in GEN **and** AUT; a new positive in GEN → negative-exact in AUT.

Both halves of step 1–2 land together; a winner added without negating its source double-serves and dirties attribution.

## Route by what the term is, not where it was found (2026-09-26)

The manifest says AUT (and every Broad-Research campaign) surfaces terms "that can later be built into the MRK, WTB, or GEN campaigns" (§2). So the **destination follows the term's class, never its source.** A search term does not become generic because a GEN-Broad caught it. Classify every qualifying candidate **before** choosing a destination:

| Class | Test | Destination |
|---|---|---|
| **BRAND** | contains our own brand name, a spelling variant or misspelling of it, or our product-line name | **MRK** Exact-Profit |
| **COMPETITOR** | names another brand or product line, **or** is a foreign ASIN (a search term of the form `b0…` that is not one of our ASINs) | **WTB** Exact-Profit (keyword, or product target for an ASIN) |
| **GENERIC** | neither: category, attribute, occasion, origin | **GEN** Exact-Profit |

- **AUT is never a destination.** AUT books no keywords (manifest §2); there is no `…-AUT-Exact-P-…` campaign. An AUT find goes to MRK, WTB or GEN like any other.
- **Read the brand from the property**: the `brand` column of the product catalog and the brand cluster in `strategy.md` §3. Misspellings count as the brand: `woodstock rum` is a Wood Stork search, not a generic one.
- **Competitor = a brand that is not ours.** You recognise one from the term itself; it does not need to be on a list first. What `strategy.md` *controls* is whether WTB is **allowed** for this ASIN (see *Competitor signals below the bar*), not whether a term *is* a competitor term.
- **Uncertain or mixed** (a word that may or may not be a brand, "our brand vs. theirs", a term naming two brands) → do not guess. Put it in the escalation with class `UNCLEAR` and your reasoning; the human decides.
- **A misrouted winner is also a leak.** A brand or competitor term converting in GEN means the GEN isolation (manifest §4) missed it. The graduation plus its on-add negatives closes the leak for that term. Name the leak in the decision-log so the negative Targeter and the reviewer see the pattern.
- **Log the class and a one-line reason for every candidate.** A reviewer must be able to see *why* `pott rum 54 prozent` went to WTB.

*Measured origin (Wood Stork, LEXA-951, 2026-09-26):* the screen routed by source and proposed `woodstork gewürzter rum` + `woodstock rum` as "Spiced GEN" and `pott rum 54 prozent` + `probitas rum` (two competitor rums) as "Aged GEN". The human rebuilt them as Spiced **MRK** and Aged **WTB**. The WTB campaign the property had been waiting for had been in the proposal all along, labelled as generic.

## When the matching Exact-Profit campaign doesn't exist yet

A first winner for an ASIN often has **no Exact-Profit campaign to graduate into** (roster 0/15). **You do not build campaigns.** Since 2026-08-23 new campaigns are built by a human (via Claude Code), not by Paperclip agents. The move therefore splits across a **human build-and-enable gate**, and one owning issue carries it so nothing is left lying:

1. **Escalate a build request** through your supervisor chain. It must be precise enough to build without further questions: per destination the ASIN, class → strategy (`MRK`/`WTB`/`GEN`), the intended campaign name per manifest §6 (`…-<STRATEGY>-Exact-P-…`), the exact terms / ASIN targets with their 90-day evidence, their source campaign IDs, and the source bid of each target (so the destination does not start below what the term already bid). Do **not** name a budget: budget is human.
2. **Do nothing to the sources yet.** Negating first would pull the winner from its live discovery campaign while the destination does not serve, and the term goes dark (a real serving gap). Candidates stay live and un-negated in discovery.
3. **Wake-up condition is ENABLED, not "built".** A human confirming that a campaign *exists* is not enough. Before touching any source, read the destination back via `query_campaign` and check `state = ENABLED`. If it is still `PAUSED`, the graduation waits: say so on the issue and do not negate. Never a bare `blocked` (it dead-ends the issue and triggers supervisor auto-recovery). Use a `request_confirmation` with `continuationPolicy=wake_assignee` whose question is "enabled?", not "created?".
4. **Once the destination serves, finish the atomic move**: add the exact keyword/target, negate-exact in the source, apply the on-add invariant. Verify via `query_*`, log to `decision-log.md`, set `in_review`.

## Competitor signals below the bar → propose a WTB-Broad (2026-09-26, provisional)

Graduation needs ≥ 2 orders; a competitor term with **one** order stays in discovery and never reaches WTB. Left alone, competitor demand is harvested only by accident. So on every monthly run, collect competitor signals per **ASIN** as a **proposal**:

- **Seed rule (provisional, set 2026-09-26 by Alexander, review after the first three runs):** a COMPETITOR search term or foreign ASIN with **≥ 1 order** on this ASIN in the 90-day window. Clicks without an order are not a seed.
- **Where WTB exists but lacks the seed** → propose adding it to the existing WTB-Broad (keyword) or WTB product-target campaign. Adding positives to an existing campaign is within autonomy only if `client.md` / `om-autonomy-levels` allow it; otherwise escalate.
- **Where the ASIN has no WTB campaign** → propose a new **WTB-Broad-R** (keyword seeds) and/or **WTB product-target** campaign (foreign ASIN seeds) in the same build request format as above. A manual ad group carries keywords *or* product targets, never both, so keyword and ASIN seeds are two campaigns.
- **`strategy.md` decides whether WTB is allowed for this ASIN.** If it forbids or restricts WTB (e.g. "no WTB on the new bottles"), **still report the signals**, but mark the proposal as conflicting with the named `strategy.md` rule. The human decides whether the measured signals lift the restriction. Never drop them silently, and never build or add against the rule.
- **Do not re-propose** a seed the human declined. Check your own `decision-log.md` first; re-raise only with materially new evidence (for example a second order), and say what is new.
- This is a proposal only: no source negation, no bid change, no graduation. Log it as `PosTgt — WTB proposal`.

## The keyword roster (bounded per campaign)
Each **Exact-Profit** campaign holds a **fixed roster of ≤ 15 keywords**. Fewer, data-rich keywords beat a long noisy tail — and on pilot budgets the cap is what lets each keyword accumulate enough clicks to clear the optimizer's significance gate. Adding is therefore a **swap, not an append**.

- **Cap is per campaign type.** Exact-Profit: hard **≤ 15**. **Broad-Research:** a higher soft cap (≈ 30–40) — it is the discovery farm; capping it at 15 would choke the funnel. **AUT:** exempt (no keywords).
- **Cap is a ceiling, not a quota.** Do not churn to stay at 15. A new keyword enters **only if it beats the current weakest AND the weakest is genuinely droppable.** If all 15 pull their weight, add nothing — or, for a hero (Prio-1) that has outgrown one campaign, **split into a second Exact-Profit campaign** (manifest §3/§8); never raise the cap.
- **"Weakest" = worst spend-efficiency / biggest drag, NOT fewest sales.** A near-zero-cost long-tail that converts occasionally is cheap option value — protect it. The eviction target is the keyword that **spends meaningfully + runs over target ACOS + shows no recent conversions** (use the optimizer's canonical weighted eff_ACOS). Rank candidates by drag; evict the top.
- **Three exits for an evicted keyword:**
  1. **Delete** — pure waste, no value anywhere.
  2. **Move to another ASIN** — it was on the wrong product; valid only on a relevance check, and it is really **head-term-ownership enforcement** (§5) when a sibling held a term the owner should carry.
  3. **Demote Profit → Research** — a decayed ex-winner keeps gathering data at lower intent instead of dying. **Has a side effect:** the term was negated in its Research source on graduation (§4), so demotion must **remove that negative** in the Research campaign, or it will never serve there. The move is not free — it touches `om-amazon-negative-targeting`'s invariant; fix it in the same step.

## Head-term ownership enforcement (manifest §5)
Re-assert the property's head-term map each run: each head term stays positive only on its **owning** ASIN and negative-exact on the brand's **sibling** ASINs (GEN + AUT). Read the map from `strategy.md` — **never flip ownership** (human decision). Cross-*property* head-term arbitration is the Account-Manager's, not this skill's.

## Run sequence (draft)
1. Inbox cycle first (`lx-paperclip-inbox-cycle`); a comment/task wake is handled, not the monthly mandate.
2. On the monthly tick: idempotency check (a harvest dated this month already logged? → close); open the dated run issue; check out.
3. Resolve wiring; read context — `strategy.md` (head-term map, goals), `learnings.md`, own `decision-log.md`, autonomy from `client.md`.
4. Pull the **search terms** (`agent_reads.<prefix>_sp_search_term_daily`) + Auto/Broad-Research performance from Supabase. Aggregate over the 90-day window **per search term × ASIN** before testing the threshold (see *Graduation* — a raw row is not a candidate, and a term averaged across ASINs hides cross-brand leakage). Note the archive starts 2026-08-11 (65-day backfill, Amazon's hard limit): until ~November the 90-day look-back is short at the far end, so a borderline term may simply not have had time to prove itself.
5. Apply the graduation threshold → candidate winners (keywords + ASIN targets). Chunk if the term list is large (rare, monthly → cheap).
6. **Classify each winner** BRAND / COMPETITOR / GENERIC / UNCLEAR → destination strategy (*Route by what the term is*). Never route by source.
7. For each winner within autonomy whose destination exists **and is ENABLED**: execute the atomic graduation move (add Exact-Profit + negate source + on-add invariant). A missing or paused destination is a build request, not a build (*When the matching Exact-Profit campaign doesn't exist yet*). Escalate anything beyond the band.
8. Collect **competitor signals below the bar** per ASIN and propose WTB seeds (*Competitor signals below the bar*). Put them in the same escalation as any build request, so the human gets one decision per run.
9. Re-assert head-term ownership (cross-ASIN negatives) within autonomy.
10. **Verify** via the Ads API; **document** every decision in the per-property `decision-log.md` using the shared envelope (`om-amazon-optimization` → *Decision-log contract*), tagged `PosTgt`; on a no-harvest month write one dated `RUN — no action` marker.
11. Close-out self-check per the inbox cycle (nothing left `in_progress`/`blocked`; history preserved).

## References
- `om-amazon-advertising-manifest` — discovery→harvest funnel, negation invariants, head-term ownership (binding).
- `om-amazon-ads-reference` — `report-types.md` (Search Term), `match-types.md`, `sp-object-model.md`, `supabase-schema.md`.
- `om-autonomy-levels` — what the Targeter may change vs. escalate.
- `lx-paperclip-inbox-cycle` — close-out / escalation.

## Maintenance
This skill owns the *harvest/graduate procedure* **and its thresholds** — the graduation test (*Graduation*, defined 2026-06-25), the roster cap, and the per-term × ASIN aggregation rule (2026-08-12), the class-based routing and the enabled-destination gate (2026-09-26), and the provisional WTB seed rule (2026-09-26, review after three runs). They are **not** pending: an agent that reads this file has everything it needs to graduate, and must not wait for a threshold to arrive in its issue text. Invariants live in the manifest; API/schema in `om-amazon-ads-reference`. The reviewer reads this agent's `decision-log.md` too — keep the log format in step with the reviewer's contract.
