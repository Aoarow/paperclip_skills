---
name: google-ads-campaign-creation
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
- **Optimisation, bid changes, budget adjustments on live campaigns.** That is a separate optimisation skill, and live mutations require explicit per-action human approval.
- **Pausing, enabling, or deleting existing live structures.** Activation is always a human action.
- **Smart Campaigns and Local Services Ads.** These cannot be managed through the Google Ads API at all and must be configured in the UI.
- **Creating Google Ads accounts, MCC links, billing setup, or conversion tracking.** Assume these exist; if they do not, stop and surface the gap.

If a request asks for any of the above, stop and hand back to the human with a clear note explaining why this skill is not the right tool.

---

## Before you build anything: pre-flight checklist

Run through these checks before issuing a single mutate. Skipping them is the most common source of failed campaign launches.

1. **Customer ID resolved.** You know the exact `customer_id` (10-digit, no dashes) of the advertising account. If managing under an MCC, also set `login-customer-id`.
2. **Conversion tracking confirmed.** At least one primary conversion action exists and has received conversions in the last 30 days. Without this, smart bidding strategies will not function. Query `conversion_action` to verify.
3. **Budget decided.** Daily budget amount, currency, and whether it is shared. New campaigns should start with a dedicated (non-shared) budget unless explicitly told otherwise.
4. **Bidding strategy decided.** See "Bidding strategies" below — it must be appropriate for the campaign type and the campaign's data state (new campaigns rarely qualify for `TARGET_ROAS` from day one).
5. **Targeting decided.** Geographic locations, languages, network settings, audience signals, ad schedule.
6. **Assets ready.** For every campaign type that consumes creative, the required text and media assets are available and meet the spec (character limits, image dimensions, video durations). See "Asset quality & ad strength".
7. **Final URL(s) confirmed.** All landing pages return 200, are mobile-friendly, and match the offer described in the ad copy. The final URL domain must align with the advertiser's verified domain.
8. **Naming convention.** Follow the property's established naming convention (typically embedded in the property's `learnings.md`). If none exists, use `[Brand] | [Campaign Type] | [Audience/Geo] | [YYYY-MM]`.

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

## The PAUSED handover convention

This is the central safety rail of this skill. **Every campaign created by an agent must be in `PAUSED` status at the moment the create-call completes.** No exceptions.

Concretely:
- Set `campaign.status = PAUSED` in the create operation. Do not flip to `ENABLED` afterwards.
- Ad groups and ad group ads can be created in `ENABLED` status (inside a paused campaign they cannot serve anyway). This is the standard pattern — it means activation requires only one action by the human: flipping the campaign itself.
- Do not call any update operation that changes a campaign's status to `ENABLED`, even if the human's request appears to authorise it. Activation is a deliberate human action in the UI.

The handover message to the human should always include:
1. The campaign name and resource ID.
2. A direct link to the campaign in the Google Ads UI:
   `https://ads.google.com/aw/campaigns?campaignId={CAMPAIGN_ID}&__c={CUSTOMER_ID}`
3. A bullet list of what was created (budget, campaign, ad groups, ads / asset groups, keywords / audience signals).
4. The Ad Strength on every ad / asset group.
5. Any pre-flight concern that was overridden or any spec that fell short of the ideal.
6. The explicit next step: "Review and click **Enable** to activate."

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
- **Creating in `ENABLED` status.** Violates the handover convention. Always `PAUSED`.

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

For deeper detail on any of the following, load the corresponding reference file:

- `references/search-rsa-spec.md` — full Responsive Search Ad field reference, customizer tags, pinning conventions.
- `references/pmax-asset-types.md` — the full asset-type / field-type matrix for Performance Max, with character limits and image specs.
- `references/demand-gen-formats.md` — detailed spec for each Demand Gen ad format, including asset automation behaviour.
- `references/shopping-listing-groups.md` — product partition tree construction.
- `references/bidding-strategies.md` — extended decision tree for picking a bidding strategy, including the conversion-data thresholds for each target-based strategy.
- `references/gaql-verification-queries.md` — the canonical post-create verification queries for each campaign type.
- `references/common-errors.md` — error-code lookup with remediation steps.

These are loaded on demand. Do not read them up front — read only when the current task touches their subject.
