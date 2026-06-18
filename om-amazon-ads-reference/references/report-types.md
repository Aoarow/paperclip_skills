# Report Types & Grains

What performance data exists, at what grain, and how it reaches Supabase. The agents read these via `amazon_ads_raw` (see `supabase-schema.md`); they do not call the Reporting API directly except for the one gap below.

## Ingested via Airbyte (daily)

| Report stream (in `amazon_ads_raw`) | Grain | Used by |
|---|---|---|
| `sponsored_products_campaigns_report_stream_daily` | profile × date × campaign | Optimizer (campaign-level aggregates — the LLM policy layer) |
| `sponsored_products_keywords_report_stream_daily` | profile × date × ad group × keyword | Optimizer (deterministic bid engine), positive/negative Targeter |
| `sponsored_products_targets_report_stream_daily` | profile × date × ad group × target | Optimizer, Targeters (ASIN/auto targets) |

Plus the **catalog** streams (campaigns, ad groups, keywords, negative keywords, targetings, profiles) — current-state config, needed to see the *full* set of keywords/targets including zero-activity ones (a report row only exists for items with activity). See `supabase-schema.md`.

### Attribution windows
Every report metric comes at four attribution windows: `1d`, `7d`, `14d`, `30d` (`sales7d`, `purchases7d`, …), with `…SameSku…` variants separating same-ASIN from halo sales. **Pick one window consistently** for ACOS/ROAS — `7d` is the usual default; document the choice in the optimization skill once the bidding ruleset is set. These are **ad-attributed** sales (ACOS), not total sales (TACOS — see below).

### Look-back / freshness
- Amazon re-states recent days; the Airbyte source re-fetches a **3-day `look_back_window`** each sync, and the report streams dedup on their primary key so re-fetched days update in place (no duplicates).
- Practical rule for agents: **the freshest fully-settled day is yesterday or earlier.** Do not react to "today" — the current day is partial and still being attributed.
- Sync cadence: daily, cron `0 0 5 * * ? UTC` (≈07:00 DE summer / 06:00 winter). The Optimizer must run **after** a successful sync (brief §7).

## NOT covered by Airbyte — the Search Term report (gap)

The Airbyte Amazon Ads connector does **not** support the **Search Term report** (confirmed against connector docs, not a version issue). This report — which *customer search terms* actually triggered ads (vs. our keywords/targets) — is essential for ad-group-level keyword harvesting (the positive Targeter).

**Plan (brief §13 / Supabase.md):** a separate **monthly n8n workflow** calls the Amazon Ads Reporting API v3 directly for the Search Term report (async request → poll → download; look-back up to **65 days**) and writes it to a new table `amazon_ads_raw.sponsored_products_search_term_report_monthly`. Status: **planned, not built.** Until it exists, the positive Targeter has no search-term source and can only harvest from what the target/keyword reports already expose.

## Reports available but not yet ingested (add to Airbyte as needed)

Sponsored Brands, Sponsored Display, attribution reports, advertised-product (ad-level — would give native ASIN↔campaign mapping, see `supabase-schema.md` "ASIN join"), purchased-product, etc. Discover the full stream list via the Airbyte source schema (`Airbyte.md`). Add streams to the connection's `configurations.streams` array when a skill needs them — Phase 1 deliberately ingests only SP performance + catalogs.

## TACOS note
None of these ad reports yield **total** revenue. TACOS = ad spend ÷ *total* sales needs `public.sales_data` (manual monthly now; SP-API in Phase 2). The Account Manager computes TACOS monthly; the daily loop steers on ACOS from the streams above (brief §4, memo §8).
