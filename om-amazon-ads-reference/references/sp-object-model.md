# Sponsored Products — Object Model

The structural contract for Sponsored Products (SP), the only campaign type in Phase 1. Grounded in the live `amazon_ads_raw` catalog tables (verified 2026-06-15) plus the Amazon Ads API v3 object model. Sponsored Brands / Display are out of scope until the manifest §7 is expanded.

## Hierarchy

```
Profile  (= the property's account × marketplace; profileId, countryCode, currencyCode)
└── Campaign            (campaignId, name, state, targetingType, budget, dynamicBidding)
    └── Ad Group        (adGroupId, name, state, defaultBid)
        ├── Product Ad  (the advertised ASIN/SKU)        ← not yet ingested to Supabase
        ├── Keyword     (keywordId, keywordText, matchType, state)         [MANUAL campaigns]
        ├── Target      (targetId, expression, expressionType, bid, state) [product/category/AUTO]
        ├── Negative Keyword (keywordText, matchType, state)
        └── Negative Target  (negative product/brand target)
```

Lexacore structure on top of this (manifest §1): **1 campaign = 1 ad group = 1 ASIN**.

## Campaign

- **`targetingType`** (live values: `MANUAL`, `AUTO`) — the load-bearing distinction. `AUTO` = the AUT strategy (Amazon's automatic targeting, no manual keywords). `MANUAL` = MRK/WTB/GEN (keyword- and product-targeted).
- **`state`** (live: `ENABLED`, `ARCHIVED`; also `PAUSED`) — **new campaigns are created `PAUSED`** and handed to a human (manifest / creation skill). `ARCHIVED` is terminal — archived objects cannot be un-archived; do not archive as a "pause".
- **`budget`** (jsonb) — daily budget + budget type. `dynamicBidding` (jsonb) — bid strategy (`LEGACY_FOR_SALES` = down only, `AUTO_FOR_SALES` = up & down, `MANUAL`) + placement bid adjustments. The Optimizer's bidding policy interacts with this; the exact policy is the pending ruleset.
- `portfolioId` — optional grouping (Amazon's own portfolio concept; distinct from our property/brand model).

## Ad Group

- Single ad group per campaign by convention (`defaultBid` = the fallback bid for targets without an explicit bid). One ASIN advertised per ad group.

## Keyword (MANUAL campaigns)

- `keywordText` + `matchType` (`BROAD` / `PHRASE` / `EXACT`) + `state`. Bid is per-keyword (in the create payload / report; the catalog keyword table does not store the live bid — read bids from the targetings table or the report stream).
- Match-type/goal pairing (Broad=Research, Exact=Profit) is doctrine — see `match-types.md` and manifest §3.

## Target (`sponsored_product_targetings`)

- **`expressionType`** (live: `MANUAL`, `AUTO`).
  - `AUTO` → the four Amazon auto-targeting clauses (`close-match`, `loose-match`, `substitutes`, `complements`) in the AUT campaign.
  - `MANUAL` → product targeting (`asin="…"`) and category targeting (`category="…"`, optionally refined by brand/price/rating) — the ASIN-target surface used by WTB (competitor ASINs).
- `expression` (raw clause) vs. `resolvedExpression` (Amazon's resolved form) — both jsonb. `bid` is per-target.

## Negatives

- **Negative keywords** (`sponsored_product_negative_keywords`): `keywordText` + match type. Use **negative exact** for clean isolation (manifest §4); negative phrase blocks too broadly.
- **Negative product targets**: exclude specific ASINs/brands. Used for the cross-ASIN head-term negation (manifest §5) and waste ASINs (negative-targeting skill).
- The negation web (which positives are mirrored as negatives where) is doctrine in manifest §4–§5; this file only describes the objects that carry it.

## Identifiers & write path

- IDs are strings in the catalog, integers in the reports — see the cast rule in `supabase-schema.md`.
- **All mutations go through the Amazon Ads API / MCP**, never via Supabase (Supabase is read-only measured truth, refreshed by Airbyte). Bulk creation patterns and limits: `bulk-and-rate-limits.md`.

## Open / not-yet-modelled

- **Product-ad stream not ingested** → ASIN↔campaign mapping currently depends on the naming convention (`supabase-schema.md`, "ASIN join").
- **Sponsored Brands / Display** objects (ad creatives, landing pages, stores) — deferred with manifest §7.
