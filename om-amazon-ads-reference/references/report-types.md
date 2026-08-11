# Report Types & Grains

What performance data exists, at what grain, and how it reaches Supabase. The agents read these via `amazon_ads_raw` (see `supabase-schema.md`); they never call the Reporting API directly.

## Ingested nightly (daily)

Ingestion runs from the custom sync `~/.amazon-ads-sync/ads_sync.py` on the operations server (cron 05:00 UTC), which replaced Airbyte. It calls the Reporting API v3 async flow (request → poll → download) and loads via `psql COPY` with dedup on each stream's key.

| Report stream (in `amazon_ads_raw`) | Grain | Used by |
|---|---|---|
| `sponsored_products_campaigns_report_stream_daily` | profile × date × campaign | Optimizer (campaign-level aggregates — the LLM policy layer) |
| `sponsored_products_keywords_report_stream_daily` | profile × date × ad group × keyword | Optimizer (deterministic bid engine), positive/negative Targeter |
| `sponsored_products_targets_report_stream_daily` | profile × date × ad group × target | Optimizer, Targeters (ASIN/auto targets) |
| `sponsored_products_search_term_report_stream_daily` | profile × date × ad group × target × **search term** | positive Targeter (harvest), negative Targeter (query-level waste) — see below |

Plus the **catalog** streams (campaigns, ad groups, keywords, negative keywords, targetings, profiles) — current-state config, needed to see the *full* set of keywords/targets including zero-activity ones (a report row only exists for items with activity). See `supabase-schema.md`.

### Attribution windows
Every report metric comes at four attribution windows: `1d`, `7d`, `14d`, `30d` (`sales7d`, `purchases7d`, …), with `…SameSku…` variants separating same-ASIN from halo sales. **Pick one window consistently** for ACOS/ROAS — `7d` is the usual default; document the choice in the optimization skill once the bidding ruleset is set. These are **ad-attributed** sales (ACOS), not total sales (TACOS — see below).

### Look-back / freshness
- Amazon re-states recent days; the sync re-fetches a **rolling 14-day window** each night, and the report streams dedup on their key so re-fetched days update in place (no duplicates).
- Practical rule for agents: **the freshest fully-settled day is yesterday or earlier.** Do not react to "today" — the current day is partial and still being attributed.
- Sync cadence: daily, cron 05:00 UTC (≈07:00 DE summer / 06:00 winter). The Optimizer must run **after** a successful sync (brief §7).

## The Search Term report (INGESTED 2026-08-11)

Which *customer search terms* actually triggered ads — as opposed to the keywords and targets we booked. This is the only stream that shows demand nobody chose, and it is the data dependency behind keyword harvesting (positive Targeter) and query-level waste negation (negative Targeter).

- **Grain:** profile × date × campaign × ad group × target × **search term**. One booked keyword matches many search terms on the same day, so `searchTerm` is part of the key — joining this stream to the keyword report on keyword alone fans out.
- **Columns:** the target-report block plus `searchTerm`. Both `keywordType` and `matchType` are present and carry the *same* value: `TARGETING_EXPRESSION_PREDEFINED` marks an AUT match (`close-match`, `loose-match`, `substitutes`, `complements`), `BROAD`/`PHRASE`/`EXACT` a booked keyword.
- **Why the AUT rows are the point:** an AUT campaign has no booked keywords at all, only match types — without this stream, everything AUT spends money on is invisible. On the first live pulls, AUT rows were roughly half the report.
- **Backfill limit:** Amazon allows at most a **65-day** look-back (`backfill_search_term.py` on the ops server). Older history cannot be recovered; the archive only deepens going forward.
- The earlier plan — a separate monthly n8n workflow writing `…_search_term_report_monthly` (brief §13) — was **dropped**: once the custom sync replaced Airbyte it already carried the Reporting-API-v3 machinery, so this is simply a third report stream on the nightly run.

## Reports available but not yet ingested

Sponsored Brands, Sponsored Display, attribution reports, advertised-product (ad-level — would give native ASIN↔campaign mapping, see `supabase-schema.md` "ASIN join"), purchased-product, etc. Adding one means a new report type + column list + target table in `ads_sync.py`, following the pattern the search-term stream established. Phase 1 deliberately ingests only SP performance + catalogs.

## TACOS note
None of these ad reports yield **total** revenue. TACOS = ad spend ÷ *total* sales needs `public.sales_data` (manual monthly now; SP-API in Phase 2). The Account Manager computes TACOS monthly; the daily loop steers on ACOS from the streams above (brief §4, memo §8).
