# Bidding Strategies — Extended Decision Reference

Load this file when picking or configuring a bidding strategy and you need the API field names, compatibility matrix, conversion-data thresholds, or the migration path between strategies.

## How bidding is configured on a campaign

Two patterns:

1. **Standard bidding strategy (campaign-owned).** Set the relevant strategy fields directly on the `Campaign` resource. Each campaign has its own strategy.
2. **Portfolio bidding strategy (`BiddingStrategy` resource).** Create a `BiddingStrategy` once, then link it to many campaigns via `Campaign.bidding_strategy`. Use this when several campaigns should share the same `target_cpa_micros` or `target_roas`.

The API uses `oneof` semantics: only one of the strategy-specific fields can be set on a campaign at a time. Switching strategies requires clearing the previous one and setting the new one in the same update.

## Strategy reference

### `MAXIMIZE_CONVERSIONS`

API field: `maximize_conversions` (optional sub-field: `target_cpa_micros`).

- Goal: get as many conversions as the budget allows.
- Optional `target_cpa_micros`: if set, treats it as the target CPA — effectively becomes `TARGET_CPA` with a different name.
- **Default starting strategy** for new Search, Demand Gen, and Performance Max campaigns when conversion count matters more than value.
- No conversion-data threshold to start, but performs poorly if the conversion tracking is broken or returns < 5 conversions / month.

### `MAXIMIZE_CONVERSION_VALUE`

API field: `maximize_conversion_value` (optional sub-field: `target_roas`).

- Goal: maximise the total conversion value within budget.
- Requires conversion tracking that includes a value (`conversion_value`).
- Optional `target_roas`: if set, becomes target-ROAS bidding.
- **Default starting strategy** for retail / e-commerce campaigns where revenue matters more than count.

### `TARGET_CPA`

API field: `target_cpa.target_cpa_micros`.

- Goal: hit a specific cost-per-acquisition.
- **Conversion-data threshold:** at least 30 conversions in the past 30 days at the account level for the relevant conversion action. Practical minimum 50 / month for stable behaviour.
- Setting too low a target starves the campaign of spend. A reasonable initial target is the campaign's recent actual CPA (or, for new campaigns, the advertiser's stated maximum tolerable CPA × 0.8 — Google's algorithm needs headroom).

### `TARGET_ROAS`

API field: `target_roas.target_roas` (as a decimal, e.g. `4.0` = 400 % ROAS).

- Goal: hit a specific return-on-ad-spend ratio.
- **Conversion-data threshold:** at least 30 conversions in the past 30 days, with conversion values tracked. Practical minimum 50 / month.
- The target is a fractional ratio — `1.0` means break-even, `4.0` means €4 in revenue per €1 in spend.
- Setting too high a target reduces eligible impressions. Start at or slightly below the campaign's recent actual ROAS.

### `MAXIMIZE_CLICKS`

API field: `target_spend.cpc_bid_ceiling_micros` (optional).

- Goal: get as much traffic as possible.
- Optional bid ceiling caps the CPC.
- Use case: traffic-building for a new site with no conversion data yet; awareness campaigns where conversion bidding is meaningless.
- **Not recommended** as a long-term strategy once conversion data exists.

### `TARGET_IMPRESSION_SHARE`

API field: `target_impression_share`:

```
target_impression_share
├── location: enum (ANYWHERE_ON_PAGE | TOP_OF_PAGE | ABSOLUTE_TOP_OF_PAGE)
├── location_fraction_micros: int  (target as fraction, e.g. 900_000 = 90 %)
└── cpc_bid_ceiling_micros: int    (cap on bid)
```

- Goal: brand defence / share-of-voice. Be on top of the page for X % of impressions.
- Search campaigns only.
- Use case: branded keyword campaigns where competitors are bidding on the brand name.

### `MANUAL_CPC`

API field: `manual_cpc.enhanced_cpc_enabled` (boolean).

- Goal: full manual control over bids at the keyword / ad group level.
- `enhanced_cpc_enabled = true` lets Google adjust bids slightly based on conversion likelihood (still mostly manual).
- **Rarely justified in 2026.** Use only when the human has a specific documented reason.

### `MANUAL_CPM`

API field: `manual_cpm`.

- Goal: pay per thousand impressions.
- Available on Video and (legacy) Display.
- Use case: reach campaigns where impressions matter more than clicks.

### `TARGET_CPM`

API field: `target_cpm.target_frequency_goal` (optional).

- Goal: hit a target cost per thousand impressions, with optional frequency goal.
- Video / Demand Gen reach campaigns.

### `TARGET_CPC` (Demand Gen)

Added in 2025 for Demand Gen specifically.

- Goal: hit a target cost-per-click.
- Useful when traffic quality matters but there is not enough conversion data for `TARGET_CPA`.

## Compatibility matrix

A `✓` means the strategy is supported on the campaign type. `✗` means it is not.

|                              | Search | PMax | Demand Gen | Shopping (Std.) | Video |
|------------------------------|:------:|:----:|:----------:|:---------------:|:-----:|
| `MAXIMIZE_CONVERSIONS`       | ✓      | ✓    | ✓          | ✓               | ✓     |
| `MAXIMIZE_CONVERSION_VALUE`  | ✓      | ✓    | ✓          | ✓               | ✗     |
| `TARGET_CPA`                 | ✓      | ✗*   | ✓          | ✗               | ✓     |
| `TARGET_ROAS`                | ✓      | ✗*   | ✓          | ✓               | ✗     |
| `MAXIMIZE_CLICKS`            | ✓      | ✗    | ✗          | ✓               | ✗     |
| `TARGET_IMPRESSION_SHARE`    | ✓      | ✗    | ✗          | ✗               | ✗     |
| `MANUAL_CPC`                 | ✓      | ✗    | ✗          | ✓               | ✗     |
| `MANUAL_CPM` / `TARGET_CPM`  | ✗      | ✗    | ✗          | ✗               | ✓     |
| `TARGET_CPC`                 | ✗      | ✗    | ✓          | ✗               | ✗     |

\* Performance Max uses `MAXIMIZE_CONVERSIONS` or `MAXIMIZE_CONVERSION_VALUE` with the optional `target_cpa_micros` / `target_roas` sub-fields. There is no standalone `TARGET_CPA` / `TARGET_ROAS` on PMax — the targets are sub-fields of the maximize-strategies.

## Decision tree

```
Is conversion tracking installed and firing?
├── No → fix tracking first; do not launch
└── Yes
    │
    Does the campaign track conversion VALUE (€ revenue)?
    ├── No (count-only conversions)
    │   ├── New campaign, < 30 conv/month
    │   │   └── MAXIMIZE_CONVERSIONS, no target
    │   └── Mature campaign, ≥ 30 conv/month
    │       ├── Strict CPA target → TARGET_CPA
    │       └── Loose target → MAXIMIZE_CONVERSIONS (no target)
    │
    └── Yes (value tracked)
        ├── New campaign, < 30 conv/month
        │   └── MAXIMIZE_CONVERSION_VALUE, no target
        ├── Mature campaign, ≥ 30 conv/month
        │   ├── Clear ROAS target → TARGET_ROAS
        │   └── Volume goal over efficiency → MAXIMIZE_CONVERSION_VALUE (no target)

Special cases:
├── Brand defence campaign → TARGET_IMPRESSION_SHARE
├── Traffic-building, no conversion data → MAXIMIZE_CLICKS
├── Brand awareness video → MANUAL_CPM or TARGET_CPM
└── Demand Gen, traffic quality matters, no conv data → TARGET_CPC
```

## Migration path

Switching strategies resets the learning phase (~7 days for smart bidding). Recommended migration sequence:

1. New campaign launches on `MAXIMIZE_CONVERSIONS` (or `MAXIMIZE_CONVERSION_VALUE` for retail).
2. Run for at least 2 weeks and ≥ 30 conversions.
3. Note the observed CPA / ROAS.
4. Switch to `TARGET_CPA` / `TARGET_ROAS` with the observed value as the target.
5. After another 2 weeks, tighten the target by 10–20 % if performance allows.

Never jump straight to `TARGET_ROAS` with an aggressive target on a brand-new campaign — it will under-deliver and possibly fail to spend.

## API field cheat sheet

When mutating `Campaign`, the strategy fields are mutually exclusive — set exactly one:

- `campaign.manual_cpc = ManualCpc{ enhanced_cpc_enabled }`
- `campaign.manual_cpm = ManualCpm{}`
- `campaign.maximize_conversions = MaximizeConversions{ target_cpa_micros }`
- `campaign.maximize_conversion_value = MaximizeConversionValue{ target_roas }`
- `campaign.target_cpa = TargetCpa{ target_cpa_micros, cpc_bid_floor_micros, cpc_bid_ceiling_micros }`
- `campaign.target_roas = TargetRoas{ target_roas, cpc_bid_floor_micros, cpc_bid_ceiling_micros }`
- `campaign.target_spend = TargetSpend{ cpc_bid_ceiling_micros }`  (Maximize Clicks)
- `campaign.target_impression_share = TargetImpressionShare{ location, location_fraction_micros, cpc_bid_ceiling_micros }`
- `campaign.target_cpm = TargetCpm{}`

Or, for portfolio strategies:

- `campaign.bidding_strategy = "customers/{cid}/biddingStrategies/{id}"`

`micros` fields: multiply the currency amount by 1,000,000. €5.00 CPA = `5_000_000`.
