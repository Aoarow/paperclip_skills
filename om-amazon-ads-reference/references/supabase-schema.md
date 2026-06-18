# Supabase Data Layer — `amazon_ads_raw` (and the `public` join targets)

The **measured truth** for Amazon. Agents read performance from here, never from the Ads API directly (the Ads API is write-only for our agents). Project `Lexacore_de` (ref `dkasvozgzliglssmxdwn`, region `eu-central-1`). Ingestion: Airbyte daily (Amazon Ads API → `amazon_ads_raw`), cron `0 0 5 * * ? UTC`. See `project_amazon_paperclip/Airbyte.md` / `Supabase.md`.

> Verified live on 2026-06-15 via the Supabase MCP. When the streams or schema change, regenerate this file from the live DB — do not hand-edit drift in.

## Two table groups (their sync mode matters)

| Group | Sync mode | Tables | RLS behaviour |
|---|---|---|---|
| **Catalog** (configuration / current state) | `full_refresh_overwrite` — dropped & recreated each sync | `profiles`, `sponsored_product_campaigns`, `sponsored_product_ad_groups`, `sponsored_product_keywords`, `sponsored_product_negative_keywords`, `sponsored_product_targetings` | **RLS resets to disabled on every sync** (table is recreated) — see Security below |
| **Reports** (daily time-series) | `incremental_deduped_history` (Append + Deduped) | `sponsored_products_campaigns_report_stream_daily`, `sponsored_products_keywords_report_stream_daily`, `sponsored_products_targets_report_stream_daily` | RLS persists (table not recreated) |

Report streams use dedup (not plain append) because the Amazon source re-fetches a 3-day `look_back_window` each sync; dedup on the primary key updates those rows in place instead of duplicating.

## Conventions that bite (read before writing SQL)

- **Columns are camelCase and case-sensitive.** Postgres folds unquoted identifiers to lowercase, so every camelCase column **must be double-quoted**: `"campaignId"`, `"reportDate"`, `"matchType"`. Unquoted `campaignid` will error.
- **ID type mismatch between the two groups.** In the **catalog** tables, `campaignId` / `adGroupId` / `keywordId` / `targetId` are `character varying` (text). In the **report** streams, `campaignId` / `adGroupId` / `keywordId` are `bigint`. **Joining catalog↔report requires a cast** (e.g. `c."campaignId" = r."campaignId"::text`). This is a known Airbyte connector quirk — handle it in the `public` views, not ad hoc in every query.
- **Airbyte metadata columns** prefix every table: `_airbyte_raw_id`, `_airbyte_extracted_at`, `_airbyte_meta` (jsonb), `_airbyte_generation_id`. Ignore them in business logic; `_airbyte_extracted_at` is useful as a freshness check.
- **Dates are stored as `varchar`** (`date`, `reportDate` — ISO `YYYY-MM-DD` strings), not `date` type. Cast for range math: `"reportDate"::date >= current_date - 30`.

## Catalog tables (current state)

- **`profiles`** (1 row) — `profileId`, `countryCode`, `currencyCode`, `timezone`, `dailyBudget`, `accountInfo` (jsonb). The advertising profile = the property's account×marketplace handle. **`accountInfo` carries `name`, `id`, `type` (`seller`/`vendor`), and `marketplaceStringId`.** Every report stream carries `profileId`, so joining `report.profileId → profiles.profileId` recovers the **marketplace** (`countryCode`), the **sales channel** (`accountInfo.type`), and the **account identity** (`accountInfo.name`/`id`) for any campaign row. This is why the campaign-name `CLIENT` code is per-*client*, not per-account (manifest §6) — those dimensions need not be encoded in the name. Note: `profileId` is `bigint` here and in the report streams (no cast needed for this join, unlike the campaignId join).
- **`sponsored_product_campaigns`** (≈63) — `campaignId` (text), `name`, `state` (`ENABLED`/`ARCHIVED`/`PAUSED`), `targetingType` (`MANUAL`/`AUTO` — this is the AUT-vs-rest distinction), `budget` (jsonb), `dynamicBidding` (jsonb), `startDate`, `endDate`, `portfolioId`, `tags` (jsonb). **`name` is the parser source for ASIN/strategy/goal** (see "ASIN join" below).
- **`sponsored_product_ad_groups`** (≈63) — `adGroupId` (text), `campaignId` (text), `name`, `state`, `defaultBid`.
- **`sponsored_product_keywords`** (≈272) — `keywordId` (text), `adGroupId`, `campaignId`, `keywordText`, `state` (`ENABLED`/`ARCHIVED`). *Note: the catalog keyword table does **not** carry `matchType`; match type is on the report stream and on the create payload.*
- **`sponsored_product_negative_keywords`** (≈413) — same shape as keywords; the negation web lives here. Large row count is expected (every GEN/AUT campaign carries the MRK/WTB negatives — manifest §4).
- **`sponsored_product_targetings`** (≈125) — `targetId` (text), `adGroupId`, `campaignId`, `bid`, `state`, `expressionType` (`MANUAL`/`AUTO`), `expression` / `resolvedExpression` (jsonb — the product/category/auto-targeting clause).

## Report streams (daily time-series — the performance source)

All three carry the same metric block (per `reportDate`): `impressions`, `clicks`, `cost`, and **ad-attributed** outcomes at four attribution windows — `sales{1,7,14,30}d`, `purchases{1,7,14,30}d`, `unitsSoldClicks{…}`, plus `…SameSku…` variants (same-ASIN vs. halo sales).

| Stream | Grain | Key columns beyond metrics |
|---|---|---|
| `…campaigns_report_stream_daily` (≈159) | profile × date × campaign | `campaignId` (bigint), `campaignName`, `campaignStatus`, `campaignBudgetAmount` |
| `…keywords_report_stream_daily` (≈242) | profile × date × ad group × keyword | `keywordId`, `keyword`, `matchType` (`BROAD`/`EXACT`), `adGroupName`, `campaignName` |
| `…targets_report_stream_daily` (≈201) | profile × date × ad group × target | `keywordId`, `keyword`, `targeting`, `keywordType` (`TARGETING_EXPRESSION` / `TARGETING_EXPRESSION_PREDEFINED`) |

**These are AD-attributed sales** — the basis for **ACOS** (`cost / sales`), the in-loop control metric. They are **not** total sales: **TACOS** needs total revenue from `public.sales_data` (monthly, manual for now → automated via SP-API in Phase 2). Do not compute TACOS from these columns.

**Metric formulas** (pick one attribution window consistently — `7d` is the usual default): ACOS = `cost / sales7d`; ROAS = `sales7d / cost`; CTR = `clicks / impressions`; CVR = `purchases7d / clicks`; CPC = `cost / clicks`. Guard divide-by-zero.

## The ASIN join (the central modelling problem — not yet solved)

The report streams carry `campaignId` / `campaignName` but **no `asin` column**, and no ad-level (product-ad) stream is ingested yet. So Amazon performance cannot join to `public.products` on ASIN directly. Two paths:

1. **Via the naming convention (available now):** ASIN is the 2nd field of `campaignName` (manifest §6: `[ACCOUNT]-[ASIN]-…`). Parse it out (`split_part(..., '-', 2)`) — this is why the rigid nomenclature is load-bearing for reporting, not just tidiness.
2. **Via an ad-level stream (cleaner, later):** add the Sponsored Products **product-ad** stream to Airbyte to get `campaignId → adId → asin` natively, removing the parser dependency.

Until path 2 exists, the `public` views rely on path 1 — so a campaign that violates the naming convention silently drops out of ASIN-level reporting.

## `public` join targets

- **`products`** — `id` (uuid), `company_id` (uuid), `sku`, `product_name`, `brand`, `asin`. **`asin` is the join key.** (Note: this is leaner than the target `products.csv` in Drive, brief §5 — the Drive catalog is the decided truth; this table is the DB mirror used for the customer frontend.)
- **`companies`** — `id`, `name`.
- **`sales_data`** — total sales (for TACOS, Phase 2 / monthly). Not yet wired to the ads data.

## Planned `public` views (TO BUILD — open item)

No `public` view joins `amazon_ads_raw.*` to `products`/`companies` yet. The intended layer (replacing the dropped hand-populated `amazon_daily_ad_performance`): derived views that (a) cast the ID-type mismatch away, (b) resolve ASIN via the naming convention, (c) join to `products`/`companies`, (d) expose tidy per-day ACOS/ROAS/CTR/CVR at campaign / keyword / target grain. Build these before the Optimizer reads live (brief §7, Supabase.md open items).

## Security — RLS state (surface, do not auto-fix)

As of 2026-06-15 the 6 **catalog** tables have **RLS disabled** (the report streams have it enabled). This is the documented "RLS resets on `full_refresh_overwrite`" issue (`Airbyte.md`): each sync recreates the catalog tables and drops the `ENABLE ROW LEVEL SECURITY` flag. These tables hold no policies and are intended for service-role / direct-Postgres access only — but with RLS off they are reachable by the `anon`/`authenticated` keys. The standing TODO (Airbyte.md) is to **automate re-applying RLS after each sync** (Postgres event trigger or a post-sync step). Re-apply SQL lives in `Airbyte.md`. Do not enable RLS without policies blindly — coordinate with whoever owns the Supabase frontend access model.
