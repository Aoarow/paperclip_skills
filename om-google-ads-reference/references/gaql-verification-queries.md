# GAQL Verification Queries

Load this file after every campaign-creation pass, before sending the handover message. Each query confirms that the structure the agent built matches what it intended to build. Run the queries with `GoogleAdsService.SearchStream` and check the field values against the create operations.

## How to read this reference

Each section lists:

1. The query template (substitute `{cid}` for customer ID, `{campaign_id}` for campaign ID, etc.).
2. The fields to verify and what each one should equal.
3. Failure modes — what the value will look like if something is wrong.

### Date literals in `DURING`

`DURING` accepts only these twelve literals. Anything else — most commonly `LAST_90_DAYS`,
which does not exist — fails with `INVALID_VALUE_WITH_DURING_OPERATOR`, not with an empty
result. For any other window use an explicit range:
`WHERE segments.date BETWEEN '2026-06-05' AND '2026-09-03'`.

```
TODAY                 YESTERDAY             LAST_7_DAYS           LAST_14_DAYS
LAST_30_DAYS          LAST_BUSINESS_WEEK    THIS_MONTH            LAST_MONTH
THIS_WEEK_SUN_TODAY   THIS_WEEK_MON_TODAY   LAST_WEEK_SUN_SAT     LAST_WEEK_MON_SUN
```

### Two selectability traps

Not every field that exists on a resource may appear in `SELECT`:

- **Message fields are not selectable, their leaves are.** `asset_group_signal.audience` and
  `ad_group_criterion.listing_group.case_value` both fail with *"may not be used in SELECT
  clause"*. Select the leaf instead — `…audience.audience`, `…case_value.product_type.value`.
- **`campaign_asset` requires `campaign.id` in the `SELECT`** when you filter on it, otherwise
  the query is rejected with *"must be present in SELECT clause"*. Other resources do not.

## 1. Campaign-level verification (all types)

```sql
SELECT
  campaign.id,
  campaign.name,
  campaign.status,
  campaign.serving_status,
  campaign.advertising_channel_type,
  campaign.advertising_channel_sub_type,
  campaign.bidding_strategy_type,
  campaign.maximize_conversions.target_cpa_micros,
  campaign.maximize_conversion_value.target_roas,
  campaign.target_cpa.target_cpa_micros,
  campaign.target_roas.target_roas,
  campaign.start_date_time,
  campaign.end_date_time,
  campaign.network_settings.target_google_search,
  campaign.network_settings.target_search_network,
  campaign.network_settings.target_content_network,
  campaign.network_settings.target_partner_search_network,
  campaign_budget.amount_micros,
  campaign_budget.delivery_method,
  campaign_budget.explicitly_shared
FROM campaign
WHERE campaign.id = {campaign_id}
```

Verify:

- `campaign.status = PAUSED` — non-negotiable per the handover convention.
- `campaign.serving_status` — should be `PENDING` or `SERVING` (will be `SERVING` only after enable; for a paused campaign expect `PENDING` or `NOT_ELIGIBLE`).
- `campaign.advertising_channel_type` matches the intended type.
- `campaign.bidding_strategy_type` matches what was set.
- For target-based bidding, the `target_*_micros` or `target_roas` field is populated.
- `campaign_budget.amount_micros` matches the requested daily budget (× 1,000,000).
- `campaign_budget.explicitly_shared` is `false` for a dedicated budget.

## 2. Targeting verification

### Geo targets

```sql
SELECT
  campaign_criterion.criterion_id,
  campaign_criterion.location.geo_target_constant,
  campaign_criterion.negative,
  campaign_criterion.bid_modifier
FROM campaign_criterion
WHERE campaign.id = {campaign_id}
  AND campaign_criterion.type = 'LOCATION'
```

Verify: every intended location appears; no unintended locations; negatives are correctly flagged.

### Languages

```sql
SELECT
  campaign_criterion.criterion_id,
  campaign_criterion.language.language_constant
FROM campaign_criterion
WHERE campaign.id = {campaign_id}
  AND campaign_criterion.type = 'LANGUAGE'
```

### Ad schedule

```sql
SELECT
  campaign_criterion.ad_schedule.day_of_week,
  campaign_criterion.ad_schedule.start_hour,
  campaign_criterion.ad_schedule.start_minute,
  campaign_criterion.ad_schedule.end_hour,
  campaign_criterion.ad_schedule.end_minute,
  campaign_criterion.bid_modifier
FROM campaign_criterion
WHERE campaign.id = {campaign_id}
  AND campaign_criterion.type = 'AD_SCHEDULE'
```

## 3. Search campaign verification

### Ad groups

```sql
SELECT
  ad_group.id,
  ad_group.name,
  ad_group.status,
  ad_group.type,
  ad_group.cpc_bid_micros
FROM ad_group
WHERE campaign.id = {campaign_id}
```

Verify: every intended ad group exists; `status = ENABLED`; `type = SEARCH_STANDARD`.

### Keywords

```sql
SELECT
  ad_group.name,
  ad_group_criterion.criterion_id,
  ad_group_criterion.keyword.text,
  ad_group_criterion.keyword.match_type,
  ad_group_criterion.negative,
  ad_group_criterion.status
FROM ad_group_criterion
WHERE campaign.id = {campaign_id}
  AND ad_group_criterion.type = 'KEYWORD'
```

Verify: keyword count matches; match types are correct; no unintended negatives.

### Responsive Search Ads

```sql
SELECT
  ad_group.name,
  ad_group_ad.ad.id,
  ad_group_ad.status,
  ad_group_ad.ad_strength,
  ad_group_ad.policy_summary.approval_status,
  ad_group_ad.policy_summary.review_status,
  ad_group_ad.ad.final_urls,
  ad_group_ad.ad.responsive_search_ad.headlines,
  ad_group_ad.ad.responsive_search_ad.descriptions,
  ad_group_ad.ad.responsive_search_ad.path1,
  ad_group_ad.ad.responsive_search_ad.path2
FROM ad_group_ad
WHERE campaign.id = {campaign_id}
  AND ad_group_ad.ad.type = 'RESPONSIVE_SEARCH_AD'
```

Verify:

- Every intended ad exists.
- `ad_strength = EXCELLENT` (or surface the actual value to the human).
- `policy_summary.approval_status` is `APPROVED` or `APPROVED_LIMITED`, never `DISAPPROVED`.
- Headlines and descriptions match the intended copy.

## 4. Performance Max verification

### Asset groups

```sql
SELECT
  asset_group.id,
  asset_group.name,
  asset_group.status,
  asset_group.primary_status,
  asset_group.primary_status_reasons,
  asset_group.ad_strength,
  asset_group.final_urls,
  asset_group.path1,
  asset_group.path2
FROM asset_group
WHERE campaign.id = {campaign_id}
```

Verify: every intended asset group exists; `ad_strength = EXCELLENT`; `primary_status_reasons` is empty (anything in here flags a problem: missing assets, policy issues, etc.).

### Assets linked to each asset group

```sql
SELECT
  asset_group.name,
  asset_group_asset.field_type,
  asset_group_asset.primary_status,
  asset_group_asset.primary_status_reasons,
  asset_group_asset.policy_summary.approval_status,
  asset.id,
  asset.type,
  asset.text_asset.text,
  asset.image_asset.full_size.width_pixels,
  asset.image_asset.full_size.height_pixels,
  asset.youtube_video_asset.youtube_video_id
FROM asset_group_asset
WHERE campaign.id = {campaign_id}
```

Verify: every minimum required `field_type` is present (see `pmax-asset-types.md`); image dimensions match expected; no `DISAPPROVED` policy summary.

Count check — group the results by `field_type` and confirm counts meet the minima:

- HEADLINE: ≥ 3
- LONG_HEADLINE: ≥ 1
- DESCRIPTION: ≥ 2
- BUSINESS_NAME: 1
- MARKETING_IMAGE: ≥ 1
- SQUARE_MARKETING_IMAGE: ≥ 1
- LOGO: ≥ 1

### Audience signals

```sql
SELECT
  asset_group.name,
  asset_group_signal.audience.audience,
  asset_group_signal.search_theme.text,
  asset_group_signal.approval_status
FROM asset_group_signal
WHERE campaign.id = {campaign_id}
```

Verify: signals are attached and resolve to real audience resources.

### Campaign-level brand assets (when brand_guidelines_enabled)

```sql
SELECT
  campaign.id,
  campaign_asset.field_type,
  asset.text_asset.text,
  asset.image_asset.full_size.width_pixels,
  asset.image_asset.full_size.height_pixels
FROM campaign_asset
WHERE campaign.id = {campaign_id}
  AND campaign_asset.field_type IN ('BUSINESS_NAME', 'LOGO', 'LANDSCAPE_LOGO')
```

Verify: `BUSINESS_NAME` and `LOGO` are linked at the campaign level (not the asset group).

## 5. Demand Gen verification

### Ad groups + ads

```sql
SELECT
  ad_group.id,
  ad_group.name,
  ad_group.status,
  ad_group_ad.ad.id,
  ad_group_ad.ad.type,
  ad_group_ad.ad_strength,
  ad_group_ad.policy_summary.approval_status,
  ad_group_ad.ad.demand_gen_multi_asset_ad.headlines,
  ad_group_ad.ad.demand_gen_multi_asset_ad.descriptions,
  ad_group_ad.ad.demand_gen_multi_asset_ad.business_name,
  ad_group_ad.ad.demand_gen_carousel_ad.carousel_cards,
  ad_group_ad.ad.demand_gen_video_responsive_ad.videos
FROM ad_group_ad
WHERE campaign.id = {campaign_id}
```

### Audiences attached to ad groups

```sql
SELECT
  ad_group.name,
  ad_group_criterion.type,
  ad_group_criterion.user_list.user_list,
  ad_group_criterion.user_interest.user_interest_category,
  ad_group_criterion.custom_audience.custom_audience,
  ad_group_criterion.age_range.type,
  ad_group_criterion.gender.type
FROM ad_group_criterion
WHERE campaign.id = {campaign_id}
  AND ad_group_criterion.type IN ('USER_LIST', 'USER_INTEREST', 'CUSTOM_AUDIENCE', 'AGE_RANGE', 'GENDER')
```

## 6. Shopping campaign verification

### Listing group tree

```sql
SELECT
  ad_group.name,
  ad_group_criterion.criterion_id,
  ad_group_criterion.listing_group.type,
  ad_group_criterion.listing_group.case_value.product_type.value,
  ad_group_criterion.listing_group.case_value.product_brand.value,
  ad_group_criterion.listing_group.case_value.product_item_id.value,
  ad_group_criterion.listing_group.parent_ad_group_criterion,
  ad_group_criterion.cpc_bid_micros,
  ad_group_criterion.negative
FROM ad_group_criterion
WHERE campaign.id = {campaign_id}
  AND ad_group_criterion.type = 'LISTING_GROUP'
```

Verify: every subdivision level has a `case_value = null` ("other") node; every leaf (`type = UNIT`) has a bid (unless smart bidding); parent references resolve.

### Merchant Center linkage

```sql
SELECT
  campaign.shopping_setting.merchant_id,
  campaign.shopping_setting.feed_label,
  campaign.shopping_setting.campaign_priority
FROM campaign
WHERE campaign.id = {campaign_id}
```

## 7. Video campaign verification

```sql
SELECT
  ad_group.id,
  ad_group.name,
  ad_group.type,
  ad_group_ad.ad.id,
  ad_group_ad.ad.type,
  ad_group_ad.ad.video_responsive_ad.headlines,
  ad_group_ad.ad.video_responsive_ad.long_headlines,
  ad_group_ad.ad.video_responsive_ad.descriptions,
  ad_group_ad.ad.video_responsive_ad.videos,
  ad_group_ad.policy_summary.approval_status
FROM ad_group_ad
WHERE campaign.id = {campaign_id}
```

## 8. Policy summary roll-up

A single query for any campaign type to catch all policy issues at once:

```sql
SELECT
  ad_group_ad.ad.id,
  ad_group_ad.policy_summary.approval_status,
  ad_group_ad.policy_summary.review_status,
  ad_group_ad.policy_summary.policy_topic_entries
FROM ad_group_ad
WHERE campaign.id = {campaign_id}
  AND ad_group_ad.policy_summary.approval_status != 'APPROVED'
```

Any rows returned require attention. `APPROVED_LIMITED` may be acceptable depending on the limitation; surface the `policy_topic_entries` to the human.

## 9. Conversion goal verification

```sql
SELECT
  campaign.id,
  campaign.selective_optimization.conversion_actions,
  campaign_conversion_goal.category,
  campaign_conversion_goal.origin,
  campaign_conversion_goal.biddable
FROM campaign_conversion_goal
WHERE campaign.id = {campaign_id}
```

Verify: the campaign is optimising toward the intended conversion goals; no unintended goals are flagged biddable.

## Verification checklist for the handover message

After running the queries above, the handover message should include a one-line confirmation for each:

```
✓ Campaign status: PAUSED
✓ Budget: €X / day
✓ Bidding strategy: <type> (with target if applicable)
✓ Geo targeting: <N> locations
✓ Ad groups: <N> created
✓ Ads / asset groups: <N> created, all APPROVED
✓ Ad strength: EXCELLENT on all
✓ Conversion goals: <list>
```

If any line cannot be checked off cleanly, do not send the handover yet — fix or escalate first.
