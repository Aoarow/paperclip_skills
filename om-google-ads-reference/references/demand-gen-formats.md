# Demand Gen — Ad Format Reference

Load this file when building a Demand Gen campaign and you need exact format specs, asset counts, image dimensions, video requirements, or asset-automation behaviour.

## Where Demand Gen ads serve

YouTube in-feed, YouTube Shorts, YouTube watch-next, Gmail (Promotions and Social tabs), and Discover. Notably **not** the open Display Network — that distinction is what separates Demand Gen from the legacy Display campaigns being migrated into it through 2026.

## Structural model

Same as Search: `AdGroup` → `AdGroupAd` → `Ad` (with one of the Demand Gen ad info types). Audience targeting is on the `AdGroup`, creative is on the `AdGroupAd`.

## The four ad formats

Pick one format per `AdGroupAd`. An ad group can contain multiple ad group ads of different formats.

| Format                        | `Ad` info field                | Use when                                                       |
|-------------------------------|--------------------------------|----------------------------------------------------------------|
| Multi-asset (single image)    | `demand_gen_multi_asset_ad`    | Default workhorse; one strong image + responsive text          |
| Carousel                      | `demand_gen_carousel_ad`       | 2–10 swipeable cards, story or product showcase                |
| Video responsive              | `demand_gen_video_responsive_ad` | Video-first creative; YouTube and Shorts inventory            |
| Product feed                  | `demand_gen_product_ad`        | Retail with Merchant Center feed                               |

## Format 1 — Multi-Asset Ad (single image)

`DemandGenMultiAssetAd`:

| Field           | Min | Max | Char limit | Image spec                                          |
|-----------------|-----|-----|-----------|------------------------------------------------------|
| Headlines       | 1   | 5   | 40 each   | text                                                 |
| Descriptions    | 1   | 5   | 90 each   | text                                                 |
| Long headline   | 1   | 1   | 90        | text                                                 |
| Business name   | 1   | 1   | 25        | text                                                 |
| Logo images     | 0   | 5   | —         | 1:1, ≥ 128×128 px, recommended 1200×1200             |
| Marketing imgs  | 1   | 15  | —         | 1.91:1 landscape, ≥ 600×314, recommended 1200×628    |
| Square imgs     | 1   | 15  | —         | 1:1, ≥ 300×300, recommended 1200×1200                |
| Portrait imgs   | 0   | 15  | —         | 4:5 (or 9:16 for Shorts), recommended 960×1200       |
| Call to action  | 0   | 1   | enum      | Predefined values; pick `AUTOMATED` unless specified |

Notes:

- Provide at least one square **and** one landscape image. Portrait is optional but unlocks YouTube Shorts inventory.
- The `classic_display_images` field on `DemandGenMultiAssetAd` (added in v24.1) is for custom uploaded images served without responsive recombination — use only for very specific brand-locked designs.

## Format 2 — Carousel Ad

`DemandGenCarouselAd`:

| Field           | Min | Max | Char limit | Spec                                                     |
|-----------------|-----|-----|-----------|-----------------------------------------------------------|
| Cards           | 2   | 10  | —         | Each is a `AdDemandGenCarouselCardAsset`                 |
| Business name   | 1   | 1   | 25        | text                                                     |
| Logo            | 1   | 1   | —         | 1:1, ≥ 128×128 px                                        |
| Headline        | 1   | 1   | 40        | text (ad-level, shared across cards)                     |
| Description     | 1   | 1   | 90        | text (ad-level)                                          |
| Call to action  | 0   | 1   | enum      | Recommended: `AUTOMATED`                                 |

Each carousel card:

| Field          | Limit                                                                    |
|----------------|---------------------------------------------------------------------------|
| Image          | One aspect ratio per ad; all cards must match: 1.91:1, 1:1, or 4:5       |
| Headline       | ≤ 40 chars                                                                |
| Final URL      | Each card has its own final URL — different products / pages allowed     |
| Call to action | Optional; falls back to ad-level CTA if absent                            |

**Critical constraint:** every card in a single carousel must share the same aspect ratio. Mixing 1:1 and 1.91:1 in one carousel will fail validation. To test both, create two separate carousel ads.

Carousel ads currently cannot use Merchant Center product feeds — use `DemandGenProductAd` for feed-driven product ads.

## Format 3 — Video Responsive Ad

`DemandGenVideoResponsiveAd`:

| Field          | Min | Max | Char limit | Spec                                       |
|----------------|-----|-----|-----------|---------------------------------------------|
| Headlines      | 1   | 5   | 40 each   | text                                        |
| Long headlines | 1   | 5   | 90 each   | text                                        |
| Descriptions   | 1   | 5   | 90 each   | text                                        |
| Business name  | 1   | 1   | 25        | text                                        |
| Videos         | 1   | 5   | —         | YouTube video IDs                           |
| Logo images    | 0   | 5   | —         | 1:1, ≥ 128×128 px                           |
| Call to action | 1   | 1   | 10 chars  | Custom CTA text required for video ads      |

Video best practice:

- Provide at least one 16:9 landscape video and one 9:16 vertical video to cover both standard YouTube and Shorts.
- 15–30 seconds is the sweet spot for view-through performance.
- Core hook in the first 5 seconds.
- Sound-optional design — many placements auto-mute.

## Format 4 — Product Ad (Demand Gen with Merchant Center)

`DemandGenProductAd` references a linked Merchant Center feed via the campaign's `shopping_setting`. Product images, titles, and prices are pulled from the feed.

Minimum required text assets at the ad group level:

| Field          | Min | Max | Char limit |
|----------------|-----|-----|-----------|
| Headlines      | 1   | 5   | 40 each   |
| Descriptions   | 1   | 5   | 90 each   |
| Logo           | 1   | 5   | —         |

The product set served can be narrowed using `AssetGroupListingGroupFilter` (yes — the same resource name as PMax retail uses) when the campaign has a product feed configured.

## Audience targeting

Demand Gen targeting lives at the ad group level via `AdGroupCriterion` resources. Available criteria:

- `user_list` — customer match, website visitors, app users (the seed for lookalikes)
- `user_interest` — affinity and in-market segments
- `custom_audience` — custom segments built from search terms, URLs, apps, places
- `lookalike_user_list` — note: from March 2026, lookalikes are AI-powered audience signals rather than strict targeting; this is invisible to the API contract but changes the behaviour
- `age_range`, `gender`, `parental_status`, `income_range` — demographic refinement
- `topic` and `keyword` — contextual signals

Best-practice structure: one ad group per audience tier so performance attribution is clean.

- Ad group 1: customer match + remarketing (warm)
- Ad group 2: lookalike (warm-ish)
- Ad group 3: custom audience + in-market (cold prospecting)

## Asset automation

`AssetAutomationSetting` on the campaign controls what Google may auto-generate. For Demand Gen specifically:

- `TEXT_ASSET_AUTOMATION` — auto-generated headlines, descriptions.
- `IMAGE_ASSET_AUTOMATION` — design variations of supplied images (added 2025).
- `VIDEO_ASSET_AUTOMATION` — short clips assembled from supplied videos and images (added 2025).

Each can be `OPT_IN` or `OPT_OUT`. **Default convention for this skill:** opt out of all asset automation unless explicitly requested. The handover message must list every automation setting that is opted in so the human knows what Google will produce on its own.

## Bidding strategies

Demand Gen supports:

- `MAXIMIZE_CONVERSIONS` (recommended starting point — needs no targets)
- `MAXIMIZE_CONVERSION_VALUE` (when value is tracked)
- `TARGET_CPA` (after ≥ 50 conversions in the last 30 days)
- `TARGET_ROAS` (after stable conversion-value history)
- `TARGET_CPC` (added 2025 — useful for traffic-quality goals without strong conversion data)

`MAXIMIZE_CLICKS` is not supported on Demand Gen.

## Conversion goal selection

By default a Demand Gen campaign opts into the account-default conversion goals. Use `Campaign.selective_optimization` plus `CampaignConversionGoal` resources to scope to specific goals (e.g. only "Lead form submit"). For new Demand Gen campaigns, scope to one primary goal — diluting across multiple goals slows learning.
