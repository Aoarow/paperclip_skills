# Supabase Data Layer — `amazon_ads_raw` (and the `public` join targets)

The **measured truth** for Amazon. Agents read performance from here, never from the Ads API directly (the Ads API is write-only for our agents). The Supabase project ID, region, and connection details are **not** in this skill — they live in the property's `data-sources.md` and the secret store. Ingestion: Airbyte daily (Amazon Ads API → `amazon_ads_raw`), cron `0 0 5 * * ? UTC`. See `project_amazon_paperclip/Airbyte.md` / `Supabase.md`.

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

**These are AD-attributed sales** — the basis for **ACOS** (`cost / sales`), the in-loop control metric. They are **not** total sales: **TACOS** needs total revenue, which since 2026-07-16 comes from the **SP-API sales layer** (see below). Do not compute TACOS from these columns — read `agent_reads.<prefix>_tacos_daily`, which already joins spend to total revenue.

**Metric formulas** (pick one attribution window consistently — `7d` is the usual default): ACOS = `cost / sales7d`; ROAS = `sales7d / cost`; CTR = `clicks / impressions`; CVR = `purchases7d / clicks`; CPC = `cost / clicks`. Guard divide-by-zero.

## The ASIN join (the central modelling problem — not yet solved)

The report streams carry `campaignId` / `campaignName` but **no `asin` column**, and no ad-level (product-ad) stream is ingested yet. So Amazon performance cannot join to `public.products` on ASIN directly. Two paths:

1. **Via the naming convention (available now):** ASIN is the 2nd field of `campaignName` (manifest §6: `[ACCOUNT]-[ASIN]-…`). Parse it out (`split_part(..., '-', 2)`) — this is why the rigid nomenclature is load-bearing for reporting, not just tidiness.
2. **Via an ad-level stream (cleaner, later):** add the Sponsored Products **product-ad** stream to Airbyte to get `campaignId → adId → asin` natively, removing the parser dependency.

Until path 2 exists, the `public` views rely on path 1 — so a campaign that violates the naming convention silently drops out of ASIN-level reporting.

## `public` join targets

- **`products`** — `id` (uuid), `company_id` (uuid), `sku`, `product_name`, `brand`, `asin`. **`asin` is the join key.** (Note: this is leaner than the target `products.csv` in Drive, brief §5 — the Drive catalog is the decided truth; this table is the DB mirror used for the customer frontend.)
- **`companies`** — `id`, `name`.
- **`sales_data`** — **legacy** monthly total sales (manual CSV import, `product_id` × `report_month` × `sales_channel`). **Superseded for TACOS** by the SP-API sales layer below (daily, per ASIN, automated). Still the monthly reporting table; a roll-up from the daily layer is planned. Do not use it for in-loop decisions.

## `public` bridge views + `agent_reads.*` agent views (BUILT 2026-06-22 · scoped 2026-07-07)

Derived views resolve the ID-type mismatch, parse ASIN from the campaign name, join to `products`/`companies`, and expose tidy per-day ACOS/ROAS/CTR/CVR at campaign / keyword / target grain.

- **Infrastructure views (`public.*`, `service_role`-only — NOT for agents):** `public.amazon_sp_campaign_daily` / `amazon_sp_keyword_daily` / `amazon_sp_target_daily` + helper `amazon_products_by_asin`. `security_invoker`, readable only by `service_role`; used for build/verification, not by agents.
- **Agent views (`agent_reads.<prefix>_*` — READ THESE):** each property has its own tenant-isolated, SELECT-only views. Windspiel = `agent_reads.wi_sp_campaign_daily` / `wi_sp_keyword_daily` / `wi_sp_target_daily` / `wi_products_by_asin` (same columns as the `public` views). They are `security_definer`, **hard-filtered to the property's Ads `profileId`**, so other tenants in the same DB are invisible. A dedicated **SELECT-only** role (`amazon_ro_<property>`, e.g. `amazon_ro_windspiel`) reads only these — no writes, no other tenant, no raw-table access.
- **Never** query `public.amazon_sp_*` or `amazon_ads_raw.*` from an agent — they are **denied** to the agent role. The connection (Supabase session pooler) + wrapper `~/.supabase-ro/q.sh "<SQL>"` are documented in the property's `data-sources.md`.

## SP-API sales & traffic — the total-revenue source (LIVE 2026-07-16)

Total (organic **+** ad) revenue per ASIN per day, from the **Selling Partner API**. This is the missing half of TACOS: the ad report streams answer *"what did advertising sell"*; this answers *"what did the ASIN sell in total"*.

- **Source:** SP-API Reports, `GET_SALES_AND_TRAFFIC_REPORT` (`reportOptions: dateGranularity=DAY, asinGranularity=CHILD`), **Brand Analytics** role, marketplace DE.
- **Report quirk that bites:** the report returns `salesAndTrafficByDate` (all ASINs summed) and `salesAndTrafficByAsin` (whole range summed) as **two separate sections** — there is **no date × ASIN cross-tab**. Daily per-ASIN rows therefore require **one report request per day**, reading the `byAsin` section. This is why the pull loops over days rather than requesting a range.
- **Freshness — do not trust the newest days.** Amazon delivers a day with ~1–2 days' lag and **restates it for ~72 h** (cancellations, late attribution). The pull re-fetches a **rolling 7-day window** and upserts, so a day converges to Amazon's final figure over several runs. **Treat the most recent ~2 days as provisional.**
- **Landing table `public.amazon_sales_traffic_daily`** (`service_role` only — **NOT for agents**). Grain: `company_id` × `marketplace_id` × `date` × `child_asin` (unique key). Columns: `parent_asin`, `child_asin`, `sku`, `ordered_product_sales` + `ordered_product_sales_currency`, `units_ordered`, `total_order_items`, `sessions`, `page_views`, `buy_box_percentage`, `unit_session_percentage`, `fetched_at`.
  > **Sales are ASIN-level, not SKU-level:** an ASIN's FBM and FBA offers are **collapsed into one row**. Do not expect a fulfilment split here (unlike `products`, which carries both the FBM row and its `-fba` twin — join on the FBM row, `sku NOT LIKE '%-fba'`).

- **Agent views (READ THESE):**
  - **`agent_reads.<prefix>_sales_daily`** — raw daily sales/traffic rows, tenant-filtered (`sales`, `units_ordered`, `sessions`, `page_views`, `buy_box_percentage`, …).
  - **`agent_reads.<prefix>_tacos_daily`** — **the metric to use.** Per ASIN × day: `sales_day`, `spend_day`, `clicks`, `ad_sales_7d`, rolling `sales_7d` / `spend_7d` / `sales_30d` / `spend_30d`, plus **`tacos_7d`** / **`tacos_30d`**, joined to `product_name` + `priority`.
  - Windspiel = `agent_reads.wi_sales_daily` / `wi_tacos_daily`. Same `security_definer` + `amazon_ro_<property>` SELECT-only model as the ad views.

- **TACOS convention:** `tacos_* = spend ÷ total sales`, a **ratio** (`0.10` = 10 %), **NULL when sales = 0** — identical convention to `acos_7d`. Rolling windows are **date-based** (calendar days, not row counts), so gaps in the data do not silently shift the window.
- **ACOS vs TACOS — why both:** ACOS divides by **ad-attributed** sales, TACOS by **total** revenue. An ASIN can show a NULL/harmless ACOS and a terrible TACOS — spend with zero attributed sales, measured against real organic revenue. That blind spot is what TACOS is *for*.

> ### ⚠️ TACOS is OBSERVATIONAL ONLY (decided 2026-07-16 — do not improvise past this)
> TACOS is available for **reporting, analysis, and surfacing observations to humans**. It does **not**
> drive decisions. The in-loop control metric remains **ACOS** (G1 bidding, `om-amazon-optimization`).
>
> **Do not** change a bid, negate a term, graduate a target, pause/enable anything, or move a budget
> because of `tacos_7d` / `tacos_30d` — no matter how bad the number looks. A high TACOS is a finding to
> **report**, not a trigger to act on. The `strategy.md` 10 % TACOS figure is a **reporting** target and
> carries no in-loop authority.
>
> *Whether and how TACOS may move a decision is an open rule question, deliberately deferred by Alexander.
> Until that rule exists in the rule set, treat TACOS as read-only context. If TACOS seems to demand an
> action, that is an escalation to the human — not an action.*

## Security — RLS state (surface, do not auto-fix)

As of 2026-06-15 the 6 **catalog** tables have **RLS disabled** (the report streams have it enabled). This is the documented "RLS resets on `full_refresh_overwrite`" issue (`Airbyte.md`): each sync recreates the catalog tables and drops the `ENABLE ROW LEVEL SECURITY` flag. These tables hold no policies and are intended for service-role / direct-Postgres access only — but with RLS off they are reachable by the `anon`/`authenticated` keys. The standing TODO (Airbyte.md) is to **automate re-applying RLS after each sync** (Postgres event trigger or a post-sync step). Re-apply SQL lives in `Airbyte.md`. Do not enable RLS without policies blindly — coordinate with whoever owns the Supabase frontend access model.
