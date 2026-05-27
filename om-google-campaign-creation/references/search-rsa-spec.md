# Responsive Search Ad — Full Field Reference

Load this file when building a Search campaign's RSAs and you need the exact field structure, character limits, customizer syntax, or pinning rules.

## Hard requirements

| Field        | Min | Max | Char limit | Notes                                            |
|--------------|-----|-----|------------|--------------------------------------------------|
| Headlines    | 3   | 15  | 30 each    | Each is an `AdTextAsset`                         |
| Descriptions | 2   | 4   | 90 each    | Each is an `AdTextAsset`                         |
| Final URLs   | 1   | n/a | n/a        | Must return 200; domain must match advertiser    |
| Paths        | 0   | 2   | 15 each    | `path1`, `path2` — appear in the display URL     |

Character counting: double-width languages (Japanese, Chinese, Korean) count each character as 2 toward the limit.

## Resource structure

A Responsive Search Ad lives inside an `AdGroupAd`, which lives inside an `AdGroup`. The shape of the `Ad` resource is:

```
Ad
├── final_urls: [string, …]            (required, ≥ 1)
├── final_mobile_urls: [string, …]     (optional)
├── tracking_url_template: string      (optional)
├── path1: string                      (optional, ≤ 15)
├── path2: string                      (optional, ≤ 15)
└── responsive_search_ad
    ├── headlines: [AdTextAsset, …]    (required, 3–15)
    ├── descriptions: [AdTextAsset, …] (required, 2–4)
    └── path1 / path2                  (alternative location for paths)
```

`AdTextAsset` shape:

```
AdTextAsset
├── text: string                                (the actual headline/description)
├── pinned_field: enum ServedAssetFieldType     (optional pinning)
└── asset_performance_label: enum               (read-only — set by Google after serving)
```

## Pinning

Pinning forces an asset to a specific position. Use sparingly — every pinned slot removes one degree of freedom from Google's optimisation.

| `pinned_field` value | Position                  |
|----------------------|---------------------------|
| `HEADLINE_1`         | First headline position   |
| `HEADLINE_2`         | Second headline position  |
| `HEADLINE_3`         | Third headline position   |
| `DESCRIPTION_1`      | First description slot    |
| `DESCRIPTION_2`      | Second description slot   |

Multiple assets can be pinned to the same position — Google will pick one of them for that slot.

**Default pinning convention:** pin one strong brand headline to `HEADLINE_1` if the advertiser has clear brand priority. Leave everything else unpinned unless there is a documented reason (legal required text, regulated industry).

## Ad customizers

Customizers let an RSA insert dynamic values at serve time without creating thousands of ads. Two flavours:

### Built-in customizers

Available immediately — no setup required. Use tag syntax inside the asset text:

| Tag                                          | What it inserts                                              | Fallback required? |
|----------------------------------------------|--------------------------------------------------------------|--------------------|
| `{Keyword:default text}`                     | The matched keyword                                          | Yes                |
| `{LOCATION(City):default}`                   | User's city                                                  | Yes                |
| `{LOCATION(Region):default}`                 | User's region/state                                          | Yes                |
| `{LOCATION(Country):default}`                | User's country                                               | Yes                |
| `{COUNTDOWN(YYYY-MM-DD HH:MM:SS, days_before)}` | Counts down to the date                                    | No                 |

Example asset texts:

```
Great Deals on {Keyword:Shoes}
Free Shipping in {LOCATION(City):Your City}
Offer Ends: {COUNTDOWN(2026-06-30 23:59:59,5)}
```

### Custom customizers

For values like price, discount percentage, or stock level that change over time but are not user-derived. Setup:

1. Create a `CustomizerAttribute` (with `name` and `type`: `TEXT`, `NUMBER`, `PRICE`, or `PERCENT`).
2. Link a value at the appropriate level:
   - `CustomerCustomizer` — account-wide default
   - `CampaignCustomizer` — campaign override
   - `AdGroupCustomizer` — ad group override
   - `AdGroupCriterionCustomizer` — keyword-level override (most specific)
3. Reference in asset text: `{CUSTOMIZER.attribute_name:fallback}`

Example:

```
Sale: {CUSTOMIZER.discount_percent:Up to 50%} Off
Ships from {CUSTOMIZER.city:Berlin}
```

The most specific value wins. Fallback text must always be supplied.

## Ad Strength

`ad_group_ad.ad_strength` is read-only and Google sets it after the ad is saved. Values:

- `PENDING` — not yet evaluated
- `NO_ADS` — empty
- `POOR`
- `AVERAGE`
- `GOOD`
- `EXCELLENT`

The handover gate is "Excellent". If the strength returns `GOOD` or below on the verification read, surface this back to the human with a list of what is missing (typically: more headlines, more diverse angles, missing keyword in any headline).

## Common construction patterns

### Headline angle checklist

When generating 15 headlines, cover at least these angles. Repeating the same angle in different words rarely raises Ad Strength.

- Brand
- Primary value proposition
- Key feature 1
- Key feature 2
- Social proof (e.g. "Trusted by 10,000+ Customers")
- Offer / discount
- Urgency / scarcity (only if true)
- Geographic relevance (if the campaign is geo-targeted)
- Question hook
- Direct CTA ("Get a Quote", "Start Free Trial")
- Long-tail keyword variant
- Short keyword variant
- Outcome / benefit
- Differentiator vs competitors
- Specificity (number, size, version)

### Description structure

Two descriptions minimum, but always provide all four:

1. **Lead with the offer or main value.** First description gets shown most often.
2. **Reinforce with proof or specificity.** Numbers, certifications, "since YYYY".
3. **Add the secondary CTA.** Different verb than any pinned headline.
4. **Risk reversal or supporting detail.** Free returns, money-back guarantee, no contract.

## Asset removal & versioning

`AdGroupAd` resources are not edited in place — to change an RSA, create a new `AdGroupAd` and remove the old one. The old ad's performance data does not carry over. Plan ahead: do not iterate RSAs casually; ship a complete, tested set.
