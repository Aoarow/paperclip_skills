---
name: om-amazon-campaign-creation
description: Create Amazon Sponsored Products campaigns, ad groups, product ads, keywords, and targets end-to-end via the Amazon Ads API. Builds the Lexacore campaign structure (1 campaign = 1 ad group = 1 ASIN; at least the four strategies Own Brand / Competitor / Generic / Auto per ASIN), applies the binding naming convention, wires up the negation web at creation time, and respects Ads API bulk/rate limits. Use whenever an agent is asked to build, launch, set up, or assemble Amazon advertising structures — even loosely phrased ("get Sponsored Products live for this ASIN", "spin up campaigns for the new product"). This is an Account-Manager-tier action (campaign creation is account-level, not a property-agent task). All new campaigns are created PAUSED and handed to a human for activation; never enable a campaign autonomously.
---

# Amazon Advertising — Campaign Creation

This skill assembles complete, ready-to-launch **Sponsored Products** campaigns through the Amazon Ads API, following the Lexacore manifest. The end state is always the same: a set of campaigns for an ASIN sitting in `PAUSED`, the negation web in place, waiting for a human to enable them.

**Who runs this:** the **KI-Account-Manager** (campaign creation is a structural, account-level act — architecture memo §1/§6), not the property-level Optimizer/Targeter agents.

**Doctrine is not restated here.** The *why* and the *rules* (strategy split, R/P pairing, naming, negation, head-term ownership) live in `om-amazon-advertising-manifest`; the *API contract* (objects, fields, limits, errors) lives in `om-amazon-ads-reference`. This skill is the *procedure* that obeys them. Read both before building.

## What this skill covers
- Sponsored Products only (Phase 1): campaign, ad group, product ads (both SKUs — FBM + FBA twin, by SKU; manifest §1), keywords, product/category targets, and the negation web.
- The four-strategy build per ASIN — MRK / WTB / GEN / AUT — with the correct match-type/goal pairing (manifest §3).
- Applying the campaign naming convention with sanitization (manifest §6).
- Establishing the negation web at creation (manifest §4–§5).
- Bulk creation that respects the Ads API rate limiter (`om-amazon-ads-reference/bulk-and-rate-limits.md`).

## What this skill does NOT do
- **Live optimization / bid & budget changes** → `om-amazon-optimization`.
- **Keyword/target harvesting and graduation** → `om-amazon-positive-targeting`.
- **Adding waste negatives on live campaigns** → `om-amazon-negative-targeting`.
- **Enabling, pausing, or deleting live structures.** Activation is always a human action.
- **Sponsored Brands / Sponsored Display** — deferred (manifest §7).
- **Reporting / analysis.** Read from Supabase per `om-amazon-ads-reference`.

If a request asks for any of the above, stop and hand back with a clear note that this is not the right tool.

---

## Inputs — read before building
| Source | Read for | Rights |
| :--- | :--- | :--- |
| product catalog (Supabase, synced from the Google Sheet; agents read the property's scoped view — see `data-sources.md`) | the ASIN(s): `asin`, **`sku`** (FBM) + **`fba_sku`** (the twin — both needed for the dual-SKU product ads, manifest §1), `product_name`, `brand`, `marketplace`, `category`, and **`priority`** (the traffic light → build depth, manifest §8). **Not** `stock_status` — always empty by design (stock is live, per-SKU; it comes from the Ads API, see pre-flight 2). | READ |
| `client.md` | the 3-char `CLIENT` code, autonomy context, the Amazon account block(s) (Ads profile ID, account ID, marketplace, sales channel) and which property maps to which account | READ (human-owned) |
| `strategy.md` | which products to push, the **head-term ownership map**, starting-bid intent, dynamic-bidding posture | READ (never write) |
| `budget.csv` | the per-product/campaign daily budget (sacred, human-owned) | READ (human-owned) |
| `data-sources.md` | the property's data wiring (Supabase tables/connection, ingestion workflow); points to the account in `client.md` rather than repeating its IDs | READ |

> **Bids & dynamic-bidding mode are policy inputs, not invented here.** Starting bids, the bidding strategy (down-only / up-and-down / fixed), and placement adjustments come from `strategy.md` and the (pending) bidding-policy ruleset (`om-amazon-optimization`, memo §12.5). If `strategy.md` gives no starting bid, use the marketplace's suggested-bid as a conservative anchor and **record the value used** in the handover — do not guess a number into a permanent default.

---

## Pre-flight checklist
Run before issuing a single create. Skipping these is the most common source of failed/duplicated builds.

1. **Profile & account resolved** — the `profileId`, account, and marketplace from the Amazon account block in `client.md` (the property maps to one account); the `CLIENT` code (manifest §6) is known.
2. **ASIN + SKUs confirmed advertisable — ask the Ads API, not the catalog.** The ASIN exists in the product catalog (Supabase) with `status = active`; then verify **each SKU you will advertise** (manifest §1: the FBM SKU + its FBA twin) **live against the Ads API** — the per-SKU eligibility / delivery status is the authoritative signal. **Do not gate on `stock_status` from the catalog:** stock is a live, per-SKU property, the Sheet deliberately does not carry it (decision 2026-07-17), so the column is always empty — gating on it would be a check against nothing. A SKU returning **`NOT_BUYABLE`** (e.g. zero stock on that fulfilment) is **not a reason to skip the build**: build per doctrine, but **name the affected SKU explicitly in the handover** so the human knows that half will not serve until the offer is fixed. *(Precedent: B0F9Y3ZSQ7 — a zero-stock FBM offer silently killed an entire ASIN-level build for 12 days; per-SKU ads surfaced it immediately.)* *(New ASIN not yet synced from the Sheet? trigger the sync first, or read the Sheet for that one product.)*
3. **Budget decided** — per-product/campaign daily budget present in `budget.csv` (human-owned). At €0, stop and escalate (budget is sacred).
4. **Strategy known** — `strategy.md` says whether this ASIN is a focus/hero or side product (drives baseline vs. expanded build) and carries the **head-term ownership map**.
5. **Head-term ownership checked** — for this ASIN's brand: which head terms does this ASIN own, and which does it *not* own (→ those become negatives here). See manifest §5.
6. **No duplicates** — pre-read the catalog (`om-amazon-ads-reference`): does a campaign with the intended name already exist? The Ads API has no natural dedup — re-creating makes duplicates.

If any check fails, stop and surface the gap — do not invent a workaround.

---

## The per-ASIN build

For one ASIN you build a **set** of campaigns (baseline = one per strategy). Each campaign follows the same object sequence (`om-amazon-ads-reference/sp-object-model.md`):

```
1. Campaign        (state = PAUSED; MANUAL vs AUTO via autoCreationSettings — see below;
                    daily budget >= 1.00 EUR; dynamic bidding)
2. Ad Group        (one; defaultBid; NO name — see naming convention)
3. Product Ads     (TWO — the FBM `sku` AND its FBA twin `<sku>-fba`, created by SKU / productIdType=SKU, never the ASIN — manifest §1)
4. Keywords  and/or Targets   (per strategy — see playbooks)
5. Negative keywords / negative targets   (the negation web — see below)
```

Build top-down (a child needs its parent's ID). Where the API supports it, batch within a request; otherwise create the parent, use the returned ID, then the children. Respect the rate limiter (`bulk-and-rate-limits.md`): chunk, serialize, honour `429` + `Retry-After`, and **parse per-item results** (partial success is normal).

### Build depth follows the product's priority (manifest §8)
Read the product's `priority` (1/2/3) from the catalog (Supabase) and build accordingly:
- **Prio 1 (high): expanded** — the four strategies **plus** the Exact-Profit harvest campaigns (may split further).
- **Prio 2 (standard): baseline** — one campaign per strategy (MRK/WTB/GEN/AUT), discovery-led; a new ASIN starts research-heavy (no proven winners yet, manifest §3).
- **Prio 3 (fringe): minimal** — only the essentials (e.g. AUT for discovery + a single GEN/MRK), no Exact-Profit harvest.

Head-term ownership is **separate** from priority — whether this ASIN bids its class's head term comes from the head-term map in `strategy.md` (§5/manifest §5), not from its Prio. (Priority is the source of build depth; the ruleset lives in manifest §8, the per-product value in the Sheet→Supabase catalog.)

---

## Per-strategy playbooks (manifest §2–§3)

### MRK — Own Brand
- **Campaign:** manual targeting — i.e. **leave `autoCreationSettings.autoCreateTargets` unset/false**. **Keyword-targeted.** Default goal **Exact-Profit** (brand terms are known, high-intent); a Broad-Research sibling may be added to discover brand variants.
- **Keywords:** own-brand terms + variants (from `strategy.md` / brand knowledge).
- **Negatives:** standard waste negatives (e.g. "cheap", "case") as seeded in `strategy.md`.

### WTB — Competitor
- **Campaign:** manual targeting (`autoCreateTargets` unset/false). **Keyword *and* product (ASIN) targeted** — competitor brand terms *and* competitor ASINs (product targeting expression `asin="…"`, see `match-types.md`). Default Exact-Profit; optional Broad-Research for new competitor variations/ASINs.
- **Targets:** competitor keywords + competitor ASIN targets.

### GEN — Generic
- **Campaign:** manual targeting (`autoCreateTargets` unset/false). **Keyword-targeted** (generic product terms), optionally category targeting. **Uses both** Broad-Research (mine generic queries) and Exact-Profit (proven generics) — the largest discovery space.
- **Keywords:** generic category terms. **Head-term rule (§5):** bid the brand's head term here **only if this ASIN owns it**; otherwise use long-tail generics and add the head term as a negative (see negation web).

### AUT — Auto
- **Campaign: set `autoCreationSettings.autoCreateTargets = true` at creation.** Always **Auto-Research** (goal `R`, match token `Auto`). Amazon's four auto clauses (`close-match`, `loose-match`, `substitutes`, `complements`) — each separately biddable.
- **No manual keywords.** Its whole job is discovery; it feeds MRK/WTB/GEN via the positive Targeter.

> **⚠️ There is no `targetingType` field in `campaign_management-create_campaign`.**
> The only thing that makes a Sponsored Products campaign an Auto campaign is
> **`autoCreationSettings.autoCreateTargets: true`**, set **at creation time**. Omit it and you
> get a MANUAL campaign wearing an AUT name — Amazon then rejects every AUTO/THEME target on
> it, correctly, and the ad group reads back as `AD_GROUP_INCOMPLETE` with zero targets.
>
> **This cannot be repaired afterwards.** `update_campaign` does not carry
> `autoCreationSettings` in its schema, and Amazon does not allow a campaign's targeting type
> to change after creation. The only fix is to build a new campaign — and since
> `delete_campaign` is excluded from every toolset, the malformed one stays behind as a
> PAUSED empty shell for a human to remove in the Amazon UI.
>
> **Preferred path for AUT: `campaign_management-create_singleshot_sp_campaign`**, which knows
> `themeTarget` and wires the four clauses in one call.
>
> *(Learned the hard way 2026-08-04, Wood Stork `226256803039857`: this skill previously said
> `targetingType = AUTO`, a field the tool does not have. The agent could not comply, built a
> MANUAL campaign, and the resulting target failures were misdiagnosed twice — first as a
> broken MCP translator, then as an unexplained `targetingType=MANUAL` — costing five agent
> runs and two issues. Verification shortcut: every healthy AUT campaign reads back
> `autoCreationSettings: {autoCreateTargets: true}`; check that first.)*

---

## Ad group naming — leave it to Amazon

**Do not name the ad group.** Omit `name` in `create_ad_group` and let Amazon assign its own
default (`Anzeigengruppe 1` on a German marketplace, `Ad group 1` on an English one).

The naming convention below governs **campaign** names only. Because the structure is
1 campaign = 1 ad group = 1 ASIN, an ad group name carries no information the campaign name does
not already carry — so the house practice is to leave the default in place. This is not a
preference invented here: of the 92 Sponsored Products ad groups across the Windspiel and
Bimmerle accounts, 87 carry Amazon's default name, and every single one built before 2026-08-04
does.

**Never copy the campaign name onto the ad group.** It reads as a second, competing convention
in the Amazon UI and makes lists harder to scan.

*(Learned 2026-08-04, Wood Stork: four of five newly built campaigns got ad groups named like
`BIM-B0GXWD674S-GEN-Broad-R` because this skill said nothing about ad group names — the agent
filled the gap by analogy to the campaign convention. The fifth omitted the name and got
`Anzeigengruppe 1`, matching every other ad group in both accounts. Note that
`update_ad_group` is deliberately excluded from the agent toolsets, so a wrong ad group name
cannot be repaired by an agent afterwards — it takes a human in the Amazon UI. Getting it right
at creation is the only cheap moment.)*

---

## Minimum daily budget

**Amazon rejects any campaign daily budget below 1,00 EUR** with
`FIELD_VALUE_IS_BELOW_MINIMUM_LIMIT` — including campaigns created `PAUSED`. A strategy that
allocates less than that per campaign is not buildable as written.

Do **not** silently substitute a higher budget: that is a budget increase and outside the
authorization. Escalate for a revised allocation, or for a reduced campaign count that fits
the property budget at 1,00 EUR per campaign.

*(Learned 2026-08-04, Wood Stork: an approved 0,50 EUR/day campaign could not be created at
all; the whole build stopped until the human authorization was amended.)*

---

## The negation web at creation (manifest §4–§5)

After seeding the positives above, install the negatives **in the same build**, so attribution is clean from day one. For this ASIN:

**Static invariant (cross-strategy, within the ASIN):**
- **GEN** gets, as **negative exact**, every positive keyword of MRK and WTB; and as **negative product targets**, the ASINs targeted by WTB. → GEN serves only purely generic terms.
- **AUT** gets, as negatives, every positive keyword of MRK, WTB, **and** GEN (and the WTB ASIN targets). → AUT discovers only genuinely new terms.
- MRK and WTB are **not** mutually negated by default (disjoint by nature).

**Head-term ownership (cross-ASIN, within the brand — §5):**
- For each head term this ASIN does **not** own: add it as **negative exact** on this ASIN's **GEN and AUT** campaigns.
- If this ASIN **owns** a head term: the head term is positive in its owning campaign; the negative goes on the *sibling* ASINs (handled when those are built, or reconciled by the positive Targeter). Consult the ownership map in `strategy.md` — never flip ownership here.

**Match type:** always **negative exact** for clean isolation (negative phrase blocks too broadly).

> Building a full brand at once: seed all ASINs' positives first, then resolve the cross-ASIN head-term negatives, so the map is applied consistently. For a single ASIN added to an existing brand, read the existing siblings' positives/ownership from the catalog before negating.

---

## Naming convention (manifest §6)

Every campaign name follows:
```
[CLIENT]-[ASIN]-[BRAND + PRODUCT NAME]-[CAMPAIGN TYPE]-[STRATEGY]-[MATCH TYPE]-[GOAL]-[NOTE]-LEXA
```
- `CLIENT` = the client's exactly 3-character uppercase code from `client.md` (per client, not per account — marketplace/channel are recovered from the data; manifest §6). `CAMPAIGN TYPE` = `SPRO` (Sponsored Products). `STRATEGY` = `MRK`/`WTB`/`GEN`/`AUT`. `MATCH TYPE` = `Broad`/`Exact` (or `Auto` for AUT). `GOAL` = `R`/`P`. `NOTE` = 4-char special note or `NOTE`.
- **`BRAND + PRODUCT NAME` = the Sheet `brand` + `product_name` joined, brand first** (single space, e.g. `Windspiel Single Malt Whisky`) — **never drop the brand**. Then sanitize (keep only letters incl. umlauts/ß, numbers, spaces; strip everything else — especially `-`, `/`, `|`, `.`, `,`; collapse multiple spaces, trim) per manifest §6 — **variable length, no padding, no fixed width**. Removing every `-` is what keeps the field unambiguously parseable. Same sanitize rule for `NOTE`.
- This name is **load-bearing for reporting** — the ASIN is parsed back out of the 2nd field for the ASIN-join (no `asin` column in the ad data, see `supabase-schema.md`). A malformed name silently drops the campaign out of ASIN-level reporting. Validate the name parses before creating.

Example: `WIN-B01EAR7GI2-Windspiel London Dry Gin 47 vol 1-SPRO-MRK-Broad-R-NOTE-LEXA`

---

## The PAUSED handover (the central safety rail)

**Every campaign is `PAUSED` at the moment its create-call completes. No exceptions.**
- Set `campaign.state = PAUSED` in the create operation; never flip to `ENABLED` afterwards.
- Ad groups, product ads, keywords, and targets are created `ENABLED` (inside a paused campaign they cannot serve anyway) — so the human enables with a single action per campaign.
- Do not call any update that sets a campaign `ENABLED`, even if the request seems to authorise it. Activation is a deliberate human action in the Amazon Ads console.

**Handover message must include:**
1. The ASIN, brand, and marketplace.
2. Per campaign: the full name, the strategy/match/goal, the daily budget, and the starting bids + dynamic-bidding mode used (and where they came from — `strategy.md` or suggested-bid anchor).
3. A summary of the negation web installed (which head terms negated, the static invariant applied).
4. A pointer to the campaigns in the Amazon Ads console (deep-link if available, otherwise the SP campaign manager for that profile).
5. Any pre-flight concern that was overridden or any spec that fell short.
6. The explicit next step: "Review and **enable** each campaign to activate."

---

## Verification before handover
After all creates succeed, read back via the Ads API (not Supabase — a just-made change isn't ingested yet). Confirm:
- Every campaign is `PAUSED`, with the intended budget and bidding mode.
- The full structure exists per campaign: ad group, **both SKU product ads** (FBM `sku` + FBA `<sku>-fba`, `productIdType=SKU` — manifest §1; not a single ASIN ad), keywords/targets.
- The negation web is present (the static invariant + the head-term negatives).
- No item is in a rejected/`PROHIBITED` state.
- Every campaign name parses correctly (ASIN recoverable from field 2) **and its `BRAND + PRODUCT NAME` field is brand-first, sanitized, and `-`-free** (manifest §6) — a `-` left inside this field breaks the parser; a missing brand is a naming defect to avoid (the reported brand itself comes from the `products` join on the ASIN, not from the name).

Only after this verification pass send the handover. On any unrecognized error or policy rejection: hard stop, surface, do not retry/work around (`common-errors.md`).

---

## Common pitfalls
- **Creating campaigns `ENABLED`.** Violates the handover rail. Always `PAUSED`.
- **Skipping the negation web at creation.** Then terms serve in multiple strategies and attribution is dirty from day one — back-filling later is painful.
- **Bidding the head term on a non-owning ASIN.** Self-competition; the owning ASIN loses velocity (manifest §5). Negate it instead.
- **Trusting the catalog for stock.** `stock_status` is always empty (stock is live and per-SKU; the Sheet does not carry it). Check **per-SKU advertisability against the Ads API** instead (pre-flight 2) and flag any `NOT_BUYABLE` SKU in the handover.
- **Building one ASIN-level product ad instead of the two SKU ads.** It hides the offer-level truth: a dead SKU makes the ad silently never serve while the API still reports the campaign as delivering (B0F9Y3ZSQ7 — 12 days, zero impressions, no error anywhere). Per-SKU ads surface it as `NOT_BUYABLE` (manifest §1).
- **Malformed campaign name.** Drops the campaign from ASIN-level reporting. Sanitize per manifest §6; validate the parse.
- **Duplicates from a re-run.** No natural idempotency — pre-read by name first.
- **Firing all creates at once.** Trips the rate limiter; chunk and serialize, honour `429` + `Retry-After`.
- **Inventing bid numbers.** Bids/posture are policy inputs — read them, record them, don't bake guesses into the skill.

---

## References
- `om-amazon-advertising-manifest` — strategy split (§2), R/P pairing (§3), negation (§4), head-term (§5), naming (§6). **Binding.**
- `om-amazon-ads-reference` — `sp-object-model.md`, `match-types.md`, `bulk-and-rate-limits.md`, `common-errors.md`, `supabase-schema.md` (the ASIN-join reason for strict naming).
- `om-amazon-optimization` — where bids are tuned after launch; source of the (pending) bidding posture.
- `lx-paperclip-inbox-cycle` — the run/escalation mechanics for the Account-Manager run that invokes this skill.

## Maintenance
This skill owns the *creation procedure*. Doctrine (naming, negation, strategy) lives in the manifest; API contract in `om-amazon-ads-reference`. Keep those single sources of truth — do not restate them here. When the build sequence or the handover convention changes, update it here in the same change.
