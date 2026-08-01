-- Amazon: per-tenant agent read layer (Supabase / Postgres)
-- =========================================================
-- Creates the six scoped views one Amazon customer's agents read. Counterpart to
-- create_google_views.sql on the Google side.
--
-- SUBSTITUTE BEFORE RUNNING:
--   {{PREFIX}}      short lowercase tenant prefix used in the view names, e.g. "wi"
--                   (Windspiel) or "bi" (Bimmerle). Must be unique per customer and
--                   is a technical alias only -- it never renames the property.
--   {{PROFILE_ID}}  the customer's Amazon Advertising profileId for the marketplace,
--                   taken from amazon_ads_raw.profiles. CAREFUL: one seller account has
--                   one profileId PER MARKETPLACE -- pick the one the property advertises
--                   in (DE unless stated otherwise in client.md).
--   {{COMPANY_ID}}  the customer's company UUID (public.companies.id), the same value
--                   carried by products and amazon_sales_traffic_daily.
--
-- Isolation contract: every view is owned by postgres and is NOT security_invoker, so it
-- reads the raw tables with definer rights and bypasses RLS -- which is exactly why the
-- hard-coded profile/company filters below are the only thing keeping customers apart.
-- Never widen a filter, never add a view without one, and never expose the raw tables to
-- a tenant role.
--
-- After running, grant the tenant's read-only role (NOBYPASSRLS, no rights on public or
-- amazon_ads_raw) -- see the GRANT block at the end.

-- 1) Product master, one row per ASIN (FBM row wins; the FBA twin is resolved separately)
CREATE OR REPLACE VIEW agent_reads.{{PREFIX}}_products_by_asin AS
SELECT DISTINCT ON (p.asin)
    p.asin,
    p.company_id,
    c.name AS company_name,
    p.brand,
    p.product_name,
    p.priority,
    p.price,
    p.currency,
    p.status,
    p.sku,
    p.stock_status,
    ( SELECT p2.sku
        FROM products p2
       WHERE p2.company_id = p.company_id
         AND p2.asin = p.asin
         AND p2.sku LIKE '%-fba'
       ORDER BY p2.sku
       LIMIT 1) AS fba_sku
  FROM products p
  LEFT JOIN companies c ON c.id = p.company_id
 WHERE p.asin IS NOT NULL
   AND p.asin <> ''
   AND p.company_id = '{{COMPANY_ID}}'::uuid
 ORDER BY p.asin, p.sku;

-- 2) Campaign performance, daily
CREATE OR REPLACE VIEW agent_reads.{{PREFIX}}_sp_campaign_daily AS
SELECT COALESCE(NULLIF(r.date::text, ''), r."reportDate"::text)::date AS date,
    r."profileId"     AS profile_id,
    r."campaignId"    AS campaign_id,
    r."campaignName"  AS campaign_name,
    r."campaignStatus" AS campaign_status,
    substring(r."campaignName"::text, 'B0[A-Z0-9]{8}') AS asin,
    (regexp_match(r."campaignName"::text, 'SPRO-([A-Z]{2,3})-'))[1] AS strategy_code,
    (regexp_match(r."campaignName"::text, 'SPRO-[A-Z]{2,3}-([A-Za-z]+)-'))[1] AS match_type,
    pa.company_id,
    pa.company_name,
    pa.brand,
    pa.product_name,
    r.impressions,
    r.clicks,
    r.cost   AS spend,
    r.sales7d AS sales_7d,
    r.purchases7d AS orders_7d,
    r."unitsSoldClicks7d" AS units_7d,
    r.sales1d AS sales_1d,
    r.purchases1d AS orders_1d,
    round(r.cost / NULLIF(r.sales7d, 0), 4) AS acos_7d,
    round(r.sales7d / NULLIF(r.cost, 0), 4) AS roas_7d,
    round(r.clicks::numeric / NULLIF(r.impressions, 0)::numeric, 6) AS ctr,
    round(r.purchases7d::numeric / NULLIF(r.clicks, 0)::numeric, 6) AS cvr_7d,
    round(r.cost / NULLIF(r.clicks, 0)::numeric, 4) AS cpc
  FROM amazon_ads_raw.sponsored_products_campaigns_report_stream_daily r
  LEFT JOIN agent_reads.{{PREFIX}}_products_by_asin pa
         ON pa.asin = substring(r."campaignName"::text, 'B0[A-Z0-9]{8}')
 WHERE r."profileId" = '{{PROFILE_ID}}'::bigint;

-- 3) Keyword performance, daily
CREATE OR REPLACE VIEW agent_reads.{{PREFIX}}_sp_keyword_daily AS
SELECT COALESCE(NULLIF(r.date::text, ''), r."reportDate"::text)::date AS date,
    r."profileId"    AS profile_id,
    r."campaignId"   AS campaign_id,
    r."campaignName" AS campaign_name,
    r."adGroupId"    AS ad_group_id,
    r."adGroupName"  AS ad_group_name,
    r."keywordId"    AS keyword_id,
    r.keyword,
    r."matchType"    AS match_type,
    substring(r."campaignName"::text, 'B0[A-Z0-9]{8}') AS asin,
    (regexp_match(r."campaignName"::text, 'SPRO-([A-Z]{2,3})-'))[1] AS strategy_code,
    pa.company_id,
    pa.company_name,
    pa.brand,
    pa.product_name,
    r.impressions,
    r.clicks,
    r.cost   AS spend,
    r.sales7d AS sales_7d,
    r.purchases7d AS orders_7d,
    r."unitsSoldClicks7d" AS units_7d,
    round(r.cost / NULLIF(r.sales7d, 0), 4) AS acos_7d,
    round(r.sales7d / NULLIF(r.cost, 0), 4) AS roas_7d,
    round(r.clicks::numeric / NULLIF(r.impressions, 0)::numeric, 6) AS ctr,
    round(r.purchases7d::numeric / NULLIF(r.clicks, 0)::numeric, 6) AS cvr_7d,
    round(r.cost / NULLIF(r.clicks, 0)::numeric, 4) AS cpc
  FROM amazon_ads_raw.sponsored_products_keywords_report_stream_daily r
  LEFT JOIN agent_reads.{{PREFIX}}_products_by_asin pa
         ON pa.asin = substring(r."campaignName"::text, 'B0[A-Z0-9]{8}')
 WHERE r."profileId" = '{{PROFILE_ID}}'::bigint;

-- 4) Target performance, daily
CREATE OR REPLACE VIEW agent_reads.{{PREFIX}}_sp_target_daily AS
SELECT COALESCE(NULLIF(r.date::text, ''), r."reportDate"::text)::date AS date,
    r."profileId"    AS profile_id,
    r."campaignId"   AS campaign_id,
    r."campaignName" AS campaign_name,
    r."adGroupId"    AS ad_group_id,
    r."adGroupName"  AS ad_group_name,
    r."keywordId"    AS target_id,
    r.targeting,
    r."keywordType"  AS target_type,
    substring(r."campaignName"::text, 'B0[A-Z0-9]{8}') AS asin,
    (regexp_match(r."campaignName"::text, 'SPRO-([A-Z]{2,3})-'))[1] AS strategy_code,
    pa.company_id,
    pa.company_name,
    pa.brand,
    pa.product_name,
    r.impressions,
    r.clicks,
    r.cost   AS spend,
    r.sales7d AS sales_7d,
    r.purchases7d AS orders_7d,
    r."unitsSoldClicks7d" AS units_7d,
    round(r.cost / NULLIF(r.sales7d, 0), 4) AS acos_7d,
    round(r.sales7d / NULLIF(r.cost, 0), 4) AS roas_7d,
    round(r.clicks::numeric / NULLIF(r.impressions, 0)::numeric, 6) AS ctr,
    round(r.purchases7d::numeric / NULLIF(r.clicks, 0)::numeric, 6) AS cvr_7d,
    round(r.cost / NULLIF(r.clicks, 0)::numeric, 4) AS cpc
  FROM amazon_ads_raw.sponsored_products_targets_report_stream_daily r
  LEFT JOIN agent_reads.{{PREFIX}}_products_by_asin pa
         ON pa.asin = substring(r."campaignName"::text, 'B0[A-Z0-9]{8}')
 WHERE r."profileId" = '{{PROFILE_ID}}'::bigint;

-- 5) Sales (SP-API Sales & Traffic), daily -- the measured-truth revenue side of TACOS
CREATE OR REPLACE VIEW agent_reads.{{PREFIX}}_sales_daily AS
SELECT date,
    child_asin AS asin,
    parent_asin,
    marketplace_id,
    ordered_product_sales AS sales,
    ordered_product_sales_currency AS currency,
    units_ordered,
    total_order_items,
    sessions,
    page_views,
    buy_box_percentage,
    unit_session_percentage
  FROM amazon_sales_traffic_daily
 WHERE company_id = '{{COMPANY_ID}}'::uuid;

-- 6) TACOS, daily + rolling 7d/30d.
-- TACOS is a ratio (0.10 = 10%) and NULL when sales = 0, matching acos_7d.
-- Windows are date-based (RANGE), so gaps in the data do not shift them.
-- OBSERVATIONAL ONLY: agents may report TACOS but must not steer on it -- ACOS stays the
-- in-loop control variable (decision Alexander, 2026-07-16).
CREATE OR REPLACE VIEW agent_reads.{{PREFIX}}_tacos_daily AS
WITH sales AS (
    SELECT child_asin AS asin, date,
           ordered_product_sales AS sales_day,
           units_ordered, sessions
      FROM amazon_sales_traffic_daily
     WHERE company_id = '{{COMPANY_ID}}'::uuid
), ad AS (
    SELECT asin, date,
           sum(spend)    AS spend_day,
           sum(sales_7d) AS ad_sales_7d,
           sum(clicks)   AS clicks
      FROM agent_reads.{{PREFIX}}_sp_campaign_daily
     WHERE asin IS NOT NULL
     GROUP BY asin, date
), base AS (
    SELECT COALESCE(s.asin, a.asin) AS asin,
           COALESCE(s.date, a.date) AS date,
           COALESCE(s.sales_day, 0) AS sales_day,
           COALESCE(a.spend_day, 0) AS spend_day,
           s.units_ordered,
           s.sessions,
           COALESCE(a.ad_sales_7d, 0) AS ad_sales_7d,
           COALESCE(a.clicks, 0)      AS clicks
      FROM sales s
      FULL JOIN ad a ON a.asin = s.asin AND a.date = s.date
)
SELECT b.asin,
    b.date,
    p.product_name,
    p.priority,
    b.sales_day,
    b.spend_day,
    b.units_ordered,
    b.sessions,
    b.clicks,
    b.ad_sales_7d,
    sum(b.sales_day) OVER w7  AS sales_7d,
    sum(b.spend_day) OVER w7  AS spend_7d,
    sum(b.sales_day) OVER w30 AS sales_30d,
    sum(b.spend_day) OVER w30 AS spend_30d,
    round(sum(b.spend_day) OVER w7  / NULLIF(sum(b.sales_day) OVER w7, 0), 4)  AS tacos_7d,
    round(sum(b.spend_day) OVER w30 / NULLIF(sum(b.sales_day) OVER w30, 0), 4) AS tacos_30d
  FROM base b
  LEFT JOIN agent_reads.{{PREFIX}}_products_by_asin p ON p.asin = b.asin
WINDOW w7  AS (PARTITION BY b.asin ORDER BY b.date RANGE BETWEEN '6 days'::interval  PRECEDING AND CURRENT ROW),
       w30 AS (PARTITION BY b.asin ORDER BY b.date RANGE BETWEEN '29 days'::interval PRECEDING AND CURRENT ROW);

-- Tenant read-only role -------------------------------------------------------
-- Run once per customer. Set the password out of band (never in a transcript or ticket):
--   ALTER ROLE amazon_ro_{{PREFIX}} WITH PASSWORD '<generated on the server>';
-- NOBYPASSRLS is deliberate: the role must never be able to read the raw tables directly.
--
-- CREATE ROLE amazon_ro_{{PREFIX}} LOGIN NOBYPASSRLS;
-- GRANT USAGE ON SCHEMA agent_reads TO amazon_ro_{{PREFIX}};
-- GRANT SELECT ON
--     agent_reads.{{PREFIX}}_products_by_asin,
--     agent_reads.{{PREFIX}}_sp_campaign_daily,
--     agent_reads.{{PREFIX}}_sp_keyword_daily,
--     agent_reads.{{PREFIX}}_sp_target_daily,
--     agent_reads.{{PREFIX}}_sales_daily,
--     agent_reads.{{PREFIX}}_tacos_daily
--   TO amazon_ro_{{PREFIX}};
--
-- VERIFY afterwards, as the role, that every view returns only this customer:
--   SELECT count(DISTINCT company_id) FROM agent_reads.{{PREFIX}}_sp_campaign_daily;  -- 1
--   SELECT count(*) FROM public.products;                                             -- denied
