# Performance Max — Asset Type & Field Type Matrix

Load this file when building Performance Max asset groups and you need the exact field-type values, asset counts, image dimensions, character limits, and the bulk-mutate construction pattern.

## Why Performance Max is structurally different

PMax has no ad groups, no keywords, no individual ad records. The structural unit is the **asset group**, which is a themed bundle of assets that Google AI combines and serves across every Google surface.

```
Campaign (PERFORMANCE_MAX)
└── AssetGroup                 (max 100 per campaign, ≥ 1 required)
    ├── AssetGroupAsset        (one link record per asset per field type)
    │   ├── asset_group: <resource_name>
    │   ├── asset: <resource_name>
    │   └── field_type: enum AssetFieldType
    ├── AssetGroupSignal       (audience signals, optional but recommended)
    └── AssetGroupListingGroupFilter  (retail only — controls which products serve)
```

## The bulk-mutate rule

For **non-retail** Performance Max, the `AssetGroup` and all `AssetGroupAsset` records linking the minimum required assets **must be sent in a single bulk mutate**. The API validates the asset group against minimum requirements at the time of creation; if any required field type is missing, the entire mutate fails with `AssetGroupError.NOT_ENOUGH_*` errors.

Use temporary resource names (negative integers) to reference within the same request:

```
operations:
  - asset_group_operation.create:
      resource_name: "customers/{cid}/assetGroups/-1"   # temporary
      campaign: "customers/{cid}/campaigns/{campaign_id}"
      name: "Asset Group A"
      final_urls: ["https://example.com/landing"]
      status: ENABLED
  - asset_group_asset_operation.create:
      asset_group: "customers/{cid}/assetGroups/-1"      # references the temp name
      asset: "customers/{cid}/assets/{headline_asset_id}"
      field_type: HEADLINE
  - … (further AssetGroupAsset operations for every required field type)
```

For **retail** PMax campaigns with a Merchant Center feed, the asset group can be created without meeting minimum asset requirements — the product feed satisfies the creative side. Asset requirements kick in only the moment the first `AssetGroupAsset` is attached.

## Required asset field types (non-retail PMax)

If the campaign has `brand_guidelines_enabled = true`, `BUSINESS_NAME` and `LOGO` must be linked as `CampaignAsset` resources (campaign level), not `AssetGroupAsset` resources.

| Field type                | Min | Max | Text limit | Image spec                                                |
|---------------------------|-----|-----|-----------|------------------------------------------------------------|
| `HEADLINE`                | 3   | 15  | 30 chars  | text                                                       |
| `LONG_HEADLINE`           | 1   | 5   | 90 chars  | text                                                       |
| `DESCRIPTION`             | 2   | 5   | 90 chars; one of them ≤ 60 chars | text                                |
| `BUSINESS_NAME`           | 1   | 1   | 25 chars  | text                                                       |
| `MARKETING_IMAGE`         | 1   | 20  | —         | 1.91:1 landscape, ≥ 600×314 px, recommended 1200×628 px    |
| `SQUARE_MARKETING_IMAGE`  | 1   | 20  | —         | 1:1, ≥ 300×300 px, recommended 1200×1200 px                |
| `PORTRAIT_MARKETING_IMAGE`| 0   | 20  | —         | 4:5, ≥ 480×600 px, recommended 960×1200 px                 |
| `LOGO`                    | 1   | 5   | —         | 1:1, ≥ 128×128 px, recommended 1200×1200 px                |
| `LANDSCAPE_LOGO`          | 0   | 5   | —         | 4:1, ≥ 512×128 px, recommended 1200×300 px                 |
| `YOUTUBE_VIDEO`           | 0   | 5   | —         | YouTube video ID, ≥ 10 seconds recommended                 |

Image file rules: JPG, PNG, or static GIF; ≤ 5,120 KB; text covering > 20 % of the image is disallowed (including logos).

**Practical note on videos:** if no `YOUTUBE_VIDEO` is supplied, Google will auto-generate one from the supplied images and text. This rarely meets brand standards. Always supply at least one human-approved YouTube video unless the agent has been explicitly told the auto-generated video is acceptable.

## Optional asset types

These improve Ad Strength and unlock additional placements:

| Field type                 | Notes                                                      |
|----------------------------|------------------------------------------------------------|
| `CALL_TO_ACTION_SELECTION` | Predefined CTAs (e.g. "Shop now", "Sign up", "Learn more") |
| `SITELINK`                 | Linked via `Asset` of type `SitelinkAsset`                 |
| `PROMOTION`                | Linked via `PromotionAsset`                                |
| `PRICE`                    | Linked via `PriceAsset`                                    |
| `CALLOUT`                  | Linked via `CalloutAsset`                                  |
| `STRUCTURED_SNIPPET`       | Linked via `StructuredSnippetAsset`                        |
| `MOBILE_APP`               | Linked via `MobileAppAsset`                                |
| `LEAD_FORM`                | Linked via `LeadFormAsset`                                 |

## Asset group signals

`AssetGroupSignal` resources are hints to Google's optimisation about which users matter most. They are **not strict targeting** — the campaign can and will serve to users outside the signals. Two ways to set a signal:

1. **`audience`** — a reference to an `Audience` resource (the modern, recommended path). `Audience` resources combine user lists, custom segments, demographics, in-market segments, and affinity.
2. **Direct user list / segment references** — older pattern, still supported.

Best practice: build one `Audience` per asset group that represents the ideal customer for that asset group's creative theme.

## Text guidelines (campaign-level)

`Campaign.text_guidelines` lets you constrain Google's AI text generation:

- `term_exclusions`: up to 25 exact words/phrases to exclude (each ≤ 30 chars).
- `messaging_restrictions`: up to 5 freeform instructions to guide tone (each ≤ 300 chars).

Use cautiously. Overly restrictive guidelines reduce the asset variation Google can produce, which hurts performance. Useful for: brand-protected terms, legal restrictions, banned competitor names.

## Asset automation (campaign-level)

`Campaign.asset_automation_settings` controls which kinds of assets Google will auto-generate. Common types:

- `TEXT_ASSET_AUTOMATION` — auto-generated headlines, descriptions, long headlines.
- `IMAGE_ENHANCEMENT_AUTOMATION` — enhanced versions of supplied images.
- `IMAGE_EXTRACTION_AUTOMATION` — images pulled from the landing page.
- `VIDEO_GENERATION_AUTOMATION` — short videos assembled from supplied assets.

Each can be set `OPT_IN` or `OPT_OUT`. Default convention for this skill: opt out of all asset automation unless the human has explicitly requested it, so handover predictability is preserved.

## Brand guidelines

`Campaign.brand_guidelines_enabled = true` unlocks the brand fields on the campaign and forces the advertiser to supply consistent `BUSINESS_NAME` and `LOGO` at the campaign level. When this is on:

- `BUSINESS_NAME` must be a `CampaignAsset` (not in any `AssetGroupAsset`).
- `LOGO` must be a `CampaignAsset`.
- Failure: `CampaignError.REQUIRED_BUSINESS_NAME_ASSET_NOT_LINKED` or `REQUIRED_LOGO_ASSET_NOT_LINKED`.

Brand colours, fonts, and other guideline fields populate `Campaign.brand_guidelines`. Worth enabling for any established brand — it produces visibly more on-brand ad combinations.

## Asset reusability

A single `Asset` resource can be linked to many asset groups, ad groups, or campaigns through their respective link records (`AssetGroupAsset`, `AdGroupAsset`, `CampaignAsset`). Build a small library of approved assets per property and link them — do not re-upload the same headline text or image for every new campaign.

Verify reusable assets with a GAQL query before creating new ones:

```sql
SELECT asset.resource_name, asset.name, asset.type,
       asset.image_asset.full_size.width_pixels,
       asset.image_asset.full_size.height_pixels
FROM asset
WHERE asset.type = 'IMAGE'
  AND asset.image_asset.full_size.width_pixels >= 1200
```
