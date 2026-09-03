# Search Assets — Spec Reference

Load this file when building, verifying, or reviewing assets ("ad extensions") on a Search
campaign. Character limits and minimums below were verified against the live API with
`validate_only` mutates on 2026-09-03, not copied from documentation.

Assets are free, they enlarge the ad, and they feed Ad Rank. A Search campaign shipped without
them is incomplete, not merely unpolished.

## The three mandatory types

Every Search campaign carries these before handover. No exceptions, no "later".

| Type | Field | Limit | Minimum to serve | Practical target |
|---|---|---|---|---|
| Sitelink | `sitelink_asset.link_text` | **25** | 2 | 4–6 |
| | `sitelink_asset.description1` / `.description2` | **35** each | — | both, or the ad shows the compact form |
| Callout | `callout_asset.callout_text` | **25** | 2 | 6–8 |
| Structured snippet | `structured_snippet_asset.values[]` | **25** each | **3 values** | 4–6 |

Two hard failures, both confirmed by the API:

- A structured snippet with fewer than 3 values is rejected: `TOO_FEW`.
- The snippet `header` is **not free text**. Anything off the list returns `INVALID_FORMAT`.
  Verified valid German headers: `Ausstattung`, `Marken`, `Kurse`, `Studiengänge`, `Modelle`,
  `Dienstleistungen`, `Shows`, `Stile`, `Typen`, `Services`. Rejected (tested): `Leistungen`,
  `Angebote`, `Produkte`, `Stadtteile`, `Versicherungsschutz`.

**Every sitelink needs its own `final_urls` entry, and it must be a real page.** A sitelink to a
404 is a hard defect. Do not confuse this with an RSA's `path1`/`path2`, which are cosmetic
display text and point at nothing. If the site has only one relevant page, use anchors
(`/leistung#preise`) or say so in the handover instead of inventing paths.

## Type reference — the rest

| Field type | Message | Notes |
|---|---|---|
| `CALL` | `call_asset` | `phone_number`, `country_code`, plus **`ad_schedule_targets`** and `call_conversion_action`. See below. |
| `PRICE` | `price_asset` | The strongest asset for a fixed-price service offer. See below. |
| `PROMOTION` | `promotion_asset` | Time-boxed discounts only. Contradicts a fixed-price positioning. |
| `LEAD_FORM` | `lead_form_asset` | Collects the lead inside the SERP — bypasses the landing page **and** its conversion tag. Never add one while the site's own conversion tracking is unproven. |
| `IMAGE` / `AD_IMAGE` | `image_asset` | Needs real creative; no placeholders. |
| `BUSINESS_MESSAGE` | `business_message_asset` | WhatsApp / Messenger. B2C pattern. |
| Location | `location_asset` | Requires a linked Google Business Profile (`business_profile_locations` or `place_id`). Strong for a radius-targeted local campaign. **There is no `LOCATION` value in `AssetFieldTypeEnum`** — location assets are linked differently; do not search for that field type. |

### Call assets — two things that are always forgotten

1. **`ad_schedule_targets`.** A phone number shown at 23:00 on a Sunday is a promise nobody
   keeps. The schedule comes from actual staffing, not from performance data — this is the one
   scheduling decision that is correct on day one.
2. **`call_conversion_action`** with `call_conversion_reporting_state =
   USE_RESOURCE_LEVEL_CALL_CONVERSION_ACTION`. Without it, calls are invisible in reporting and
   the campaign optimises as if the phone did not exist.

### Price assets — for fixed-price service offers

`price_asset` renders a table of offerings directly beneath the ad. For an advertiser whose
differentiator *is* the published price, this is the only asset type that shows it before the
click — and pre-qualifying the click matters more than winning it when the budget is small.

- `type_`: `SERVICES`, `SERVICE_TIERS`, `PRODUCT_TIERS`, `SERVICE_CATEGORIES`, `BRANDS`,
  `EVENTS`, `LOCATIONS`, `NEIGHBORHOODS`, `PRODUCT_CATEGORIES`
- `price_qualifier`: `FROM`, `UP_TO`, `AVERAGE`
- `price_offerings[]`: `header`, `description`, `price`, `unit`, `final_url`
- `unit`: `PER_HOUR`, `PER_DAY`, `PER_WEEK`, `PER_MONTH`, `PER_YEAR`, `PER_NIGHT`

Price wording is a commitment. It must match the landing page **exactly** — never rounded, never
reformulated.

## The level hierarchy

Assets attach at three levels, and the more specific one overrides the more general:

```
customer_asset   → applies to every campaign in the account
  campaign_asset → overrides for one campaign
    ad_group_asset → overrides for one ad group
```

**Build the evergreen set once at account level.** Callouts, structured snippets, and the call
asset rarely differ per campaign; putting them on `customer_asset` means every future campaign
inherits them and no one can forget to attach them. Override only where the message genuinely
differs — typically sitelinks, which are offer-specific.

An account with the same USPs repeated across four RSAs and zero account-level callouts has the
copy in the wrong place.

## Automated assets

Google generates dynamic sitelinks and callouts on its own. Control this through
`campaign.asset_automation_settings` (`OPTED_IN` / `OPTED_OUT`) per `asset_automation_type` —
`TEXT_ASSET_AUTOMATION` and `FINAL_URL_EXPANSION_TEXT_ASSET_AUTOMATION`.

**Opt out whenever the advertiser has binding wording** — published prices, regulated claims, a
fixed service scope. Generated text will eventually phrase a price differently from the landing
page, and that difference is the advertiser's problem, not Google's.

## Verification and measurement

After building, read back — do not assert:

```sql
SELECT campaign.id, campaign_asset.field_type, campaign_asset.status,
       asset.sitelink_asset.link_text, asset.callout_asset.callout_text,
       asset.structured_snippet_asset.header, asset.structured_snippet_asset.values
FROM campaign_asset
WHERE campaign.id = {campaign_id} AND campaign_asset.status != 'REMOVED'
```

Account level uses `customer_asset` (no `campaign.id` filter). Note that `campaign_asset`
**requires `campaign.id` in the `SELECT`** when filtered on it — see the GAQL reference.

For the optimizer, later: which assets actually earn their place.

```sql
SELECT asset_field_type_view.field_type, metrics.impressions, metrics.clicks
FROM asset_field_type_view WHERE segments.date DURING LAST_30_DAYS
```

Per individual asset, add `metrics` to the `campaign_asset` query above. Both paths verified
working. Without this step, weak callouts are replaced by guesswork instead of evidence.
