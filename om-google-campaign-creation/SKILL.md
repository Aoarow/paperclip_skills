---
name: om-google-campaign-creation
description: Create Google Ads campaigns, ad groups, ads, and asset groups end-to-end via the Google Ads API. Covers all five active campaign types (Search, Performance Max, Demand Gen, Shopping, Video) including budget setup, bidding strategies, targeting, RSA construction, Performance Max asset groups, and Demand Gen creatives. Use this skill whenever the agent is asked to build, launch, set up, draft, or assemble anything in Google Ads — even when the request is phrased loosely ("get a new campaign live for Bimmerle", "spin up search ads for the spring offer", "we need a PMax for the new product line"). All new structures are created in `PAUSED` status and handed back to a human for activation in the Google Ads UI; never enable a campaign autonomously.
---

# Google Ads — Campaign, Ad Group & Ad Creation

This skill teaches an agent how to assemble a complete, ready-to-launch Google Ads campaign through the Google Ads API. The end state is always the same: a fully configured campaign sitting in `PAUSED` status, with everything wired up correctly, waiting for a human to click "enable" in the Google Ads web UI.

## What this skill covers

- Search campaigns with Responsive Search Ads (RSAs)
- Performance Max campaigns with asset groups
- Demand Gen campaigns (the successor to Discovery Ads — Display campaigns are being migrated here in 2026)
- Shopping campaigns (Standard Shopping; for retail prefer Performance Max in most cases)
- Video campaigns (YouTube inventory; for performance goals prefer Demand Gen or Performance Max)

## What this skill does NOT do

- **Reporting and analysis.** Use the read-only Google Ads MCP server or a dedicated reporting skill for GAQL queries.
- **Optimisation, bid changes, budget adjustments on live campaigns.** That is a separate optimisation skill (`om-google-optimization`); live mutations are governed there by the property's autonomy level (`om-autonomy-levels`), not by this skill.
- **Pausing, enabling, or deleting existing live structures.** Activation is always a human action.
- **Smart Campaigns and Local Services Ads.** These cannot be managed through the Google Ads API at all and must be configured in the UI.
- **Creating Google Ads accounts, MCC links, billing setup, or conversion tracking.** Assume these exist; if they do not, stop and surface the gap.

If a request asks for any of the above, stop and hand back to the human with a clear note explaining why this skill is not the right tool.

---

## Before you build anything: pre-flight checklist

Run through these checks before issuing a single mutate. Skipping them is the most common source of failed campaign launches.

1. **Customer ID resolved.** You know the exact `customer_id` (10-digit, no dashes) of the advertising account. If managing under an MCC, also set `login-customer-id`.
2. **Conversion tracking confirmed — configured is not confirmed.** Exactly one action has `primary_for_goal = true`, every other enabled action has `include_in_conversions_metric = false`, and the primary action **has actually recorded conversions**. Query `conversion_action` with a date range to verify; an action that has never fired is not tracking, and no conversion-based bidding strategy will work against it. If it has never fired, say so and pick a cold-start strategy — do not treat the field values as proof.
3. **Budget decided.** Daily budget amount, currency, and whether it is shared. New campaigns should start with a dedicated (non-shared) budget unless explicitly told otherwise.
4. **Bidding strategy decided.** See "Bidding strategies" below — it must be appropriate for the campaign type and the campaign's data state (new campaigns rarely qualify for `TARGET_ROAS` from day one).
5. **Targeting decided.** Geography (radius vs. administrative region — see "Cold start"), positive geo target type, language, network settings, audience signals. New campaigns get **no** ad schedule.
6. **Assets ready.** For every campaign type that consumes creative, the required text and media assets are available and meet the spec (character limits, image dimensions, video durations). See "Asset quality & ad strength".
7. **Final URL(s) confirmed.** All landing pages return 200, are mobile-friendly, and match the offer described in the ad copy. The final URL domain must align with the advertiser's verified domain.
8. **Launch gates read and answered.** Open the property's `strategy.md` and `data-sources.md` and list every documented precondition with its state. A gate that is still active does not block *building* — everything is created `PAUSED` anyway — but it does block the recommendation to enable, and it must appear by name in the handover. A gate is never satisfied by not having noticed it.
9. **Naming convention.** Follow the property's established naming convention (typically embedded in the property's `learnings.md`). If none exists, use `[Brand] | [Campaign Type] | [Audience/Geo] | [YYYY-MM]`.

If any check fails, stop and surface the gap — do not invent a workaround.

---

## The universal build sequence

Every Google Ads campaign follows the same top-down construction order, regardless of type. Build in this order and submit each layer before starting the next, because each layer references the resource name of the one above it.

```
1. CampaignBudget                       (shared resource, defines spend)
2. Campaign                             (PAUSED, references the budget)
3. Targeting criteria                   (geo, language, network, ad schedule)
4. Ad Group  OR  Asset Group            (depends on campaign type — see below)
5. Keywords  /  Audience signals        (depends on campaign type)
6. Ad(s)  OR  Assets + AssetGroupAssets (the creative layer)
7. Conversion goal selection            (campaign-level, opt-in to relevant goals)
```

Many of these can be combined into a single bulk `mutate` call to the `GoogleAdsService` — and for Performance Max non-retail, **must** be combined, because an asset group cannot exist without its minimum required assets.

### Which data model applies?

Google Ads uses three structural models depending on campaign type. Knowing which one applies before you start prevents the most common architectural mistake (e.g. trying to attach keywords to a Performance Max campaign).

| Campaign type     | Container         | Creative layer                    | Targeting layer                          |
|-------------------|-------------------|-----------------------------------|------------------------------------------|
| Search            | `AdGroup`         | `AdGroupAd` → `ResponsiveSearchAd`| Keywords + audiences on ad group         |
| Performance Max   | `AssetGroup`      | `Asset` + `AssetGroupAsset`       | Audience signals on asset group          |
| Demand Gen        | `AdGroup`         | `AdGroupAd` → `DemandGen*Ad`      | Audiences on ad group                    |
| Shopping (Std.)   | `AdGroup`         | `AdGroupAd` → `ShoppingProductAd` | Listing groups (product partitions)      |
| Video             | `AdGroup`         | `AdGroupAd` → `VideoResponsiveAd` | Audiences + placements on ad group       |

---

## Campaign type playbooks

### Search campaigns

The workhorse for capturing existing demand. Modern Search campaigns use only Responsive Search Ads — every other Search ad format has been deprecated.

**Campaign settings**
- `advertising_channel_type`: `SEARCH`
- `network_settings.target_google_search`: `true`
- `network_settings.target_search_network`: typically `false` (search partners often dilute quality; enable only deliberately)
- `network_settings.target_content_network`: `false`
- Status: `PAUSED`

**Ad group**
- One ad group per tight thematic cluster (typically per product, per service line, or per intent stage).
- `type`: `SEARCH_STANDARD`
- Default `cpc_bid_micros` only matters under `MANUAL_CPC`; under smart bidding it is ignored but harmless.

**Keywords**
- Match types: prefer phrase and exact match. Broad match only with a documented reason (typically only when paired with smart bidding and a tight negative list).
- Add a campaign-level negative keyword list to filter known irrelevant queries.

**Responsive Search Ad — hard requirements**
- 3–15 headlines (each ≤ 30 chars)
- 2–4 descriptions (each ≤ 90 chars)
- ≥ 1 final URL
- Optional: 2 paths (≤ 15 chars each), ad customizers, pinning

Aim for the full 15 headlines and 4 descriptions. Pin sparingly — pinning reduces the asset-combination space that Google's optimisation operates over. A reasonable default is to pin one brand headline to `HEADLINE_1` and leave everything else unpinned.

Target **"Excellent" Ad Strength** before saving. If the strength is "Average" or below, surface this to the human rather than proceeding.

**Assets are part of the build, not a follow-up.** A Search campaign without sitelinks,
callouts and structured snippets is incomplete and must not be handed over. Minimums, the exact
character limits, the fixed structured-snippet header list, and the account/campaign/ad-group
level hierarchy are in `om-google-ads-reference/references/search-assets-spec.md`. Two rules that
decide where the work goes:

- **Build the evergreen set once at account level** (`customer_asset`) — callouts, snippets, call
  asset. Every future campaign inherits it. Override per campaign only where the message really
  differs, which is usually just sitelinks.
- **Every sitelink needs its own real final URL.** Not an RSA display path — those are cosmetic
  and point at nothing. A sitelink to a 404 is a hard defect.

**Negatives are built in three levels, not one list.** Universal junk goes in an
`ACCOUNT_LEVEL_NEGATIVE_KEYWORDS` shared set (applies account-wide with no link to forget);
reusable intent exclusions in a `NEGATIVE_KEYWORDS` shared set linked per campaign;
client-specific terms on the campaign. Negatives match **no** close variants — singular and plural
are two entries. See `om-google-ads-reference/references/negative-keywords-spec.md`.

**One conversion action per business outcome — never per campaign.** Google attributes every
conversion to the campaign that earned the click, so separate actions are never needed for
reporting. Override `campaign_conversion_goal` only when a campaign demonstrably pursues a
different action type. Before building: verify exactly one action has `primary_for_goal = true`
and that every other enabled action has `include_in_conversions_metric = false`.

**No ad schedule on a new campaign.** Time restriction is a data-driven lever, and set before
data it prevents exactly the data that would justify it — an excluded hour produces no evidence
that it should have been excluded, so the mistake is invisible. It also saves nothing: the daily
budget is the cap, not the clock; fewer hours mean fewer auctions to spend it in. Check it only
once there is meaningful click volume per bucket, which on small budgets never happens at the
hour level (168 buckets). **The ad schedule has no calendar** — `AdScheduleInfo` is `day_of_week`
plus hours only. Holidays and date ranges are a start/end date, a pause, or a
`BiddingSeasonalityAdjustment`; they are never an ad schedule. *Exception:* assets carrying a
service promise (call assets above all) get `ad_schedule_targets` from day one, derived from
actual staffing rather than performance.

**AI Max stays off on a new campaign.** `campaign.ai_max_setting.enable_ai_max` defaults to
`false` — leave it there. AI Max widens matching, creative, and landing pages at once, which a
campaign with no performance history cannot be judged against. It is a later, separate, human
decision once conversion data exists; the preconditions and fields are in
`om-google-ads-reference/references/ai-max.md`. Do not set `campaign.keyword_match_type`
alongside it.

### Performance Max campaigns

A fully automated, cross-channel campaign that runs across every Google surface (Search, Shopping, Display, YouTube, Gmail, Discover, Maps). There are no keywords and no ad groups — the structural unit is the **asset group**.

**Campaign settings**
- `advertising_channel_type`: `PERFORMANCE_MAX`
- `bidding_strategy_type`: `MAXIMIZE_CONVERSIONS` (with or without `target_cpa_micros`) or `MAXIMIZE_CONVERSION_VALUE` (with or without `target_roas`).
- For retail, link a Merchant Center feed via `shopping_setting`.
- `url_expansion_opt_out`: `true` by default unless the human explicitly wants Google to expand to new URLs on the domain.
- `brand_guidelines_enabled`: useful for established brands; opens up the brand guidelines fields on the campaign.
- Status: `PAUSED`

**Asset group**
- An asset group is a creative bundle centered on a theme or audience. Up to 100 per campaign.
- Required asset fields for a non-retail PMax:
  - `HEADLINE` (3–15, each ≤ 30 chars)
  - `LONG_HEADLINE` (1–5, each ≤ 90 chars)
  - `DESCRIPTION` (2–5, each ≤ 90 chars)
  - `BUSINESS_NAME` (1, ≤ 25 chars)
  - `MARKETING_IMAGE` (1–20, 1.91:1 landscape, ≥ 600×314 px)
  - `SQUARE_MARKETING_IMAGE` (1–20, 1:1, ≥ 300×300 px)
  - `LOGO` (1–5, 1:1, ≥ 128×128 px; optionally `LANDSCAPE_LOGO` 4:1)
  - `YOUTUBE_VIDEO` (≥ 1 recommended — if none supplied, Google auto-generates one, which is rarely on-brand)
- Optional but recommended: `PORTRAIT_MARKETING_IMAGE` (4:5), `CALL_TO_ACTION_SELECTION`, sitelinks.

**The bulk-mutate rule (critical).** In a non-retail PMax campaign, the `AssetGroup` and all `AssetGroupAsset` objects linking the minimum required assets **must be created in the same bulk mutate request**. You cannot create the asset group first and link assets afterwards — the asset group will be rejected as invalid. Use temporary resource names (negative integers) to reference resources within the same mutate request.

**Audience signals.** Not targeting — signals. They tell Google's model where to start looking; the algorithm will expand beyond them. Build signals from: customer match lists, custom segments (search terms, URLs, app activity), in-market segments, demographics.

### Demand Gen campaigns

Mid-funnel visual advertising across YouTube, YouTube Shorts, Gmail, and Discover. Has effectively replaced Discovery Ads, and Display campaigns are being migrated here through 2026.

**Campaign settings**
- `advertising_channel_type`: `DEMAND_GEN`
- Bidding: `MAXIMIZE_CONVERSIONS`, `MAXIMIZE_CONVERSION_VALUE`, `TARGET_CPA`, `TARGET_ROAS`, or `TARGET_CPC` (added in 2025).
- Status: `PAUSED`

**Ad group**
- Best practice: separate ad groups by audience tier — lookalike prospecting, custom intent, remarketing — so performance is attributable per layer.
- Audience options: lookalike segments (note: from March 2026 these became AI-powered audience signals rather than strict targeting), custom segments, customer match, in-market, affinity, demographics.

**Ad formats** (pick one per ad group ad)
- `DemandGenMultiAssetAd` — responsive multi-asset format (the workhorse).
- `DemandGenCarouselAd` — multi-card swipeable format.
- `DemandGenVideoResponsiveAd` — video-first.
- `DemandGenProductAd` — product feed-driven (requires Merchant Center).

**Asset automation.** Demand Gen now supports generating design variations and short videos from existing assets via `asset_automation_settings`. Useful for stretching limited creative inventory, but flag it explicitly in the handover so the human knows what Google will auto-generate.

### Shopping campaigns

Product-feed-driven ads for retail. For most retail use cases, **Performance Max for retail is the recommended choice** over Standard Shopping — it includes Shopping inventory plus all other Google surfaces. Build Standard Shopping only when the human explicitly wants channel separation, brand-protected campaigns, or fine-grained product-level bidding control.

**Campaign settings**
- `advertising_channel_type`: `SHOPPING`
- `shopping_setting.merchant_id`: linked Merchant Center account ID.
- `shopping_setting.sales_country` (or `feed_label`).
- `shopping_setting.campaign_priority`: `LOW`, `MEDIUM`, or `HIGH` (controls precedence when multiple Shopping campaigns share a product).
- Status: `PAUSED`

**Listing groups.** Shopping ad groups use product partitions (a tree of `ListingGroup` resources) to subdivide the product inventory by attributes (brand, category, item ID, custom labels). Start with a single "everything else" partition and subdivide only when there is a bidding or budgeting reason.

### Video campaigns

YouTube inventory. Google's guidance is to use Performance Max or Demand Gen for performance goals; Standard Video campaigns are now best reserved for upper-funnel awareness and reach.

**Campaign settings**
- `advertising_channel_type`: `VIDEO`
- `advertising_channel_sub_type` determines the campaign goal: e.g. `VIDEO_EFFICIENT_REACH`, `VIDEO_NON_SKIPPABLE`, `VIDEO_OUTSTREAM`, `VIDEO_SEQUENCE`.
- Status: `PAUSED`

**Ad formats** — pick based on objective:
- `VideoResponsiveAd` for the modern responsive format.
- `InStreamAd` for skippable pre-roll.
- `BumperAd` for 6-second non-skippable reach.

YouTube video assets must be uploaded to YouTube first; the campaign references them by YouTube video ID.

---

## Bidding strategies

Pick the strategy based on (a) campaign type, (b) conversion data available, and (c) the stated business goal. New campaigns rarely qualify for target-based smart bidding from day one — at least 30 conversions in the past 30 days at the relevant value tier is a practical minimum before `TARGET_CPA` or `TARGET_ROAS` will behave well.

| Strategy                       | Use when                                                | Compatible with                              |
|--------------------------------|---------------------------------------------------------|----------------------------------------------|
| `MAXIMIZE_CONVERSIONS`         | New campaign, conversions matter, no target yet         | Search, PMax, Demand Gen, Display, Video     |
| `MAXIMIZE_CONVERSION_VALUE`    | Revenue matters more than count, no target yet         | Search, PMax, Demand Gen, Shopping           |
| `TARGET_CPA`                   | Stable conversion volume, clear acceptable cost         | Search, Demand Gen, Display, Video           |
| `TARGET_ROAS`                  | Strong value-tracked conversions, clear ROAS target     | Search, PMax, Shopping, Demand Gen           |
| `MAXIMIZE_CLICKS`              | Traffic-building phase, no conversion data yet          | Search, Display, Shopping (Std.)             |
| `TARGET_IMPRESSION_SHARE`      | Brand defense / share-of-voice goals                    | Search                                       |
| `MANUAL_CPC`                   | Rarely justified; only with a documented reason         | Search, Display, Shopping (Std.)             |

`CallAd` and `CallAdInfo` were removed in API v23 — do not attempt to create call-only ads. Call extensions (now "call assets") remain supported.

---

## Asset quality & ad strength

Ad Strength is a leading indicator of how well Google's optimisation will be able to work with the creative inventory. Aim for **"Excellent"** on every RSA and PMax asset group before handover.

The fastest path to Excellent:
- Fill every available slot (15 headlines, 4 descriptions for RSAs; the full asset-type list for PMax).
- Vary headline angles: brand, value proposition, feature, social proof, offer, CTA. Avoid 15 paraphrases of the same idea.
- Include at least one keyword-relevant headline per ad group's intent cluster.
- Use the full character allowance — short headlines lose to longer competitive ads on visual weight.
- Mix image aspect ratios in PMax. Square, landscape, and portrait each unlock different placements.

When the strength falls short, do not lower the bar — surface it back to the human with a specific list of what is missing.

---

## Cold start: a campaign with no conversion history

A brand-new campaign in a brand-new account is not a small version of a mature one. Three
decisions differ, and getting them wrong is the most common way a launch produces nothing.

**Bidding.** Conversion-based strategies need a signal to learn from. An account with zero
recorded conversions gives them none — the campaign sits in `BIDDING_STRATEGY_LEARNING`
indefinitely. Start on `TARGET_SPEND` (maximise clicks) with a CPC ceiling, or `MANUAL_CPC`.
Graduate to conversion-based bidding once the property has meaningful monthly conversion volume;
the thresholds are in `references/bidding-strategies.md`. A configured-but-never-fired conversion
action is **not** a signal.

**Budget against the real click price.** Query the keyword planner for top-of-page bids on the
head terms before setting the budget, and compare. A daily budget below the price of a single
top-of-page click cannot compete, whatever the bidding strategy says. Google computes the monthly
charging limit as **daily budget × 30.4** — always state the derived monthly figure and check it
against the property's `budget.csv` ceiling. Halving or doubling that figure by dividing by 30 or
60 is a real and repeated error.

**Reach must be large enough to spend the budget.** The instinct on a small budget is to narrow
the geography. That is right only when demand exceeds budget. When it does not — thin B2B niches,
local service terms — narrowing starves the campaign of the impressions it needs to spend
anything. Size the target area by measured search volume against the affordable click count, not
by intuition. Administrative boundaries are a poor proxy for a catchment area: prefer a
`ProximityInfo` radius around the business over a state or region, which will include distant
cities and exclude near ones. Pair any local targeting with positive geo target type
**`PRESENCE`**, not `PRESENCE_OR_INTEREST`.

**Match types.** Exact and phrase on a thin niche capture a fraction of an already small pool, and
individually enumerated long-tail keywords in such niches usually carry zero volume. Broad match
on the two or three load-bearing terms, paired with a tight negative net and a weekly search-term
review, is the better shape. Broad match without that review is not.

---

## The PAUSED handover convention

This is the central safety rail of this skill. **Every campaign created by an agent must be in `PAUSED` status at the moment the create-call completes.** No exceptions.

Concretely:
- Set `campaign.status = PAUSED` in the create operation. Do not flip to `ENABLED` afterwards.
- Ad groups and ad group ads shall be created in `ENABLED` status (inside a paused campaign they cannot serve anyway). This is the standard pattern — it means activation requires only one action by the human: flipping the campaign itself.
- Do not call any update operation that changes a campaign's status to `ENABLED`, even if the human's request appears to authorise it. Activation is a deliberate human action in the UI.

### The handover has two parts, and the message is the second

First the **structural handoff**: set the issue's **assignee** *and* its **status**
(`lx-paperclip-inbox-cycle`). A message without a reassignment is not a handover — it is a note
in a dead-end issue. Never use a comment, and never `blocked`, to move work to a human.

### The message must be able to say something bad

A summary that can only describe success is not a check. The message is the last point at which a
human sees the campaign before being asked to enable it, so it reports the build **against its
requirements**, not merely its contents. Every block is written out even when empty — an omitted
block reads as "fine", and absence is exactly what goes unnoticed.

Four mandatory blocks:

**1. Gates — each one answered individually.** Every precondition from the property's
`strategy.md` and `data-sources.md`, listed by name with its state. A launch gate that is still
active is stated as still active. This must be a list to be answered, not a prompt to recall
concerns: the gate that gets missed is the one nobody experienced as an override.

**2. What was built, each figure beside the value it is measured against.** A bare number
carries no judgement; a number next to its reference does.

```
Budget 3.33 €/day        ⚠ = 101 €/month (× 30.4) · budget.csv ceiling: 200 €
Bidding MAXIMIZE_CONVERSIONS  ⚠ 0 conversions on record
4 RSAs, 15/4 each        ⚠ 1 × AVERAGE (target: EXCELLENT)
Sitelinks                ⚠ NONE
Callouts                 ⚠ NONE
```

Include the counts that can be zero — assets by type, negatives, shared-set links. A list of what
happened will never mention what did not.

**3. Deliberately not done, with the reason.** No ad schedule, AI Max off, no audiences. Without
this the human cannot tell a decision from an oversight.

**4. The read-back values, not the claim.** Report what the verification GAQL actually returned —
campaign status, serving status, approval counts, network settings. "Verified ✓" is worth
nothing; the values are the evidence.

Then the campaign name and ID, a direct link
(`https://ads.google.com/aw/campaigns?campaignId={CAMPAIGN_ID}&__c={CUSTOMER_ID}`), and **one**
explicit next step naming the person who owns it. If a gate is open, the next step is that gate —
not "review and enable".

---

## Common pitfalls

These are the failure modes that come up most often. Check each one before submitting.

- **Submitting a PMax asset group without its minimum required assets in the same bulk mutate.** The request will fail. Bundle everything.
- **Using `CallAd` or `CallAdInfo`.** Removed in API v23. Use call assets instead.
- **Attaching keywords to a non-Search campaign.** Performance Max, Demand Gen, and Shopping do not accept keywords — only Search and (in a limited way) Display do.
- **Defaulting to `TARGET_ROAS` on a brand-new campaign.** With no conversion history, the campaign will under-deliver or fail to spend. Start on `MAXIMIZE_CONVERSIONS` or `MAXIMIZE_CONVERSION_VALUE` and graduate later.
- **Forgetting `final_urls` on the ad.** RSAs require at least one. Without it, the ad is rejected.
- **Final URL domain mismatch.** The final URL domain must align with the advertiser's verified domain; mismatched domains trigger policy review.
- **Pinning every headline.** Defeats the optimisation. Pin sparingly, with intent.
- **Skipping `customer_id` validation under an MCC.** Always set `login-customer-id` explicitly when operating under a manager account.
- **Not setting `url_expansion_opt_out` on PMax.** The default is opt-in, which lets Google expand to new URLs on the domain — sometimes desirable, often not. Decide explicitly.
- **Silent API version drift.** Google moved to a monthly API release cadence in 2026. Pin the API version in the client config — never rely on the library default.
- **Creating campaigns in `ENABLED` status.** Violates the handover convention. Campaigns always `PAUSED`.
- **Building a Search campaign with no assets.** Sitelinks, callouts and structured snippets are part of the build. A campaign without them is not ready for handover.
- **Launching past an active gate in `strategy.md`.** A documented launch block (unconfirmed conversion tracking, missing approval) is not advisory. Build, leave `PAUSED`, and name the gate in the handover.
- **Deriving the daily budget by dividing the monthly ceiling by 30 or 60.** Google's monthly limit is daily × 30.4. Always state the derived monthly figure next to the ceiling.
- **Copying a sibling property's numbers.** Budgets, geo targets and `login-customer-id` are per property. A value that is correct next door is not evidence it is correct here.
- **Single-form negative keywords.** Negatives match no close variants; `kurs` does not block "kurse". Enter every relevant inflection.

---

## Verification before handover

After all mutate calls succeed and before composing the handover message, run a verification read using `GoogleAdsService.SearchStream` with GAQL queries:

```sql
SELECT campaign.id, campaign.name, campaign.status,
       campaign.advertising_channel_type, campaign.bidding_strategy_type,
       campaign_budget.amount_micros
FROM campaign
WHERE campaign.id = {NEW_CAMPAIGN_ID}
```

Plus the appropriate ad-group / asset-group / ad / keyword reads. Confirm:
- Status is `PAUSED`.
- Budget is attached and at the intended amount.
- Bidding strategy matches the intent.
- Every expected child resource exists.
- No `policy_summary.approval_status` is `DISAPPROVED`.

Only after this verification pass should the handover message be sent.

---

## References

For deeper detail on any of the following, load the corresponding reference file from the shared `om-google-ads-reference` skill (these references moved out of this skill so that both this skill and `om-google-optimization` share one source of truth):

- `om-google-ads-reference/references/search-rsa-spec.md` — full Responsive Search Ad field reference, customizer tags, pinning conventions.
- `om-google-ads-reference/references/pmax-asset-types.md` — the full asset-type / field-type matrix for Performance Max, with character limits and image specs.
- `om-google-ads-reference/references/demand-gen-formats.md` — detailed spec for each Demand Gen ad format, including asset automation behaviour.
- `om-google-ads-reference/references/shopping-listing-groups.md` — product partition tree construction.
- `om-google-ads-reference/references/bidding-strategies.md` — extended decision tree for picking a bidding strategy, including the conversion-data thresholds for each target-based strategy.
- `om-google-ads-reference/references/gaql-verification-queries.md` — the canonical post-create verification queries for each campaign type.
- `om-google-ads-reference/references/ai-max.md` — AI Max for Search: enable switch, automation opt-outs, generated-text guardrails, preconditions.
- `om-google-ads-reference/references/search-assets-spec.md` — Search assets: verified character limits, the fixed snippet header list, price/call assets, level hierarchy, measurement queries.
- `om-google-ads-reference/references/negative-keywords-spec.md` — negative keywords: no-close-variants rule, the three-level structure, limits, link verification.
- `om-google-ads-reference/references/common-errors.md` — error-code lookup with remediation steps.

These are loaded on demand. Do not read them up front — read only when the current task touches their subject.
