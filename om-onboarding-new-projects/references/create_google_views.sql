-- create_google_views.sql
-- Per-property agent_reads views for a Google Ads client, in Supabase (Postgres).
--
-- HOW GOOGLE DATA GETS HERE:
--   The nightly sync /home/paperclip/.google-ads-sync/google_ads_sync.py (cron 05:15 UTC,
--   wrapped in cron_guard) calls the Google Ads API per account and writes into the
--   schema google_ads_raw. There is no MCC-level transfer any more and no data warehouse
--   to wait for: an account is covered the moment it is listed in the sync's ACCOUNTS.
--   (BigQuery was retired on 2026-09-02.)
--
-- WHEN TO RUN: at Gate-2 prep, AFTER the account has been added to the sync's ACCOUNTS
--   and at least one sync run has landed.
--
-- SUBSTITUTE two placeholders (plain find-replace) before running:
--   {{PREFIX}}  the property's view prefix, lowercase [a-z0-9_], e.g. lxai / lxde.
--               The scoped read role google_ro_<tenant> is granted SELECT on
--               agent_reads.{{PREFIX}}_* and nothing else - that grant IS the
--               tenant isolation.
--   {{CID}}     the raw numeric Google Ads customer id, digits only, no dashes
--               (e.g. 474-708-4209 -> 4747084209)
--
-- RUN: as a role-capable user (the Supabase MCP connects as postgres).
--
-- TWO POSTGRES TRAPS, both already paid for once:
--   1. Integer division. cost_micros is bigint, and bigint/bigint truncates -
--      2000000 / 10000000 = 0, silently. BigQuery's SAFE_DIVIDE computed in floating
--      point and hid this. Every ratio below therefore casts to numeric explicitly.
--   2. Division by zero. SAFE_DIVIDE returned NULL; Postgres raises. Hence NULLIF.
--   You need BOTH. One without the other is a bug that returns a plausible number.
--
-- Amounts are stored as micros (lossless, as the API delivers them) and converted to
-- EUR here. Agents never see micros.

-- 1) Daily campaign performance, 90 days. The base read for cause-finding.
--    customer_id is the last column on purpose: it is the anchor for the isolation
--    self-test (q.sh <tenant> --check), not a business column.
CREATE OR REPLACE VIEW agent_reads.{{PREFIX}}_campaign_performance_daily AS
SELECT
  date, campaign_id, campaign_name, campaign_status, channel_type,
  impressions, clicks,
  ROUND(cost_micros / 1000000.0, 2)                            AS cost_eur,
  conversions,
  ROUND(conversions_value_micros / 1000000.0, 2)               AS conversion_value_eur,
  ROUND(clicks::numeric / NULLIF(impressions, 0), 6)           AS ctr,
  ROUND((cost_micros / 1000000.0) / NULLIF(clicks, 0), 2)      AS avg_cpc_eur,
  ROUND((cost_micros / 1000000.0) / NULLIF(conversions, 0), 2) AS cost_per_conversion_eur,
  ROUND(conversions / NULLIF(clicks, 0), 6)                    AS conversion_rate,
  search_impression_share,
  search_budget_lost_impression_share,
  search_rank_lost_impression_share,
  customer_id
FROM google_ads_raw.campaign_performance_daily
WHERE customer_id = {{CID}}
  AND date >= CURRENT_DATE - INTERVAL '90 days'
ORDER BY date DESC, cost_micros DESC;

-- 2) Campaign trends 7d/30d with week-over-week change. The first read of every run.
CREATE OR REPLACE VIEW agent_reads.{{PREFIX}}_campaign_trends AS
WITH agg AS (
  SELECT
    campaign_id,
    MAX(campaign_name)   AS campaign_name,
    MAX(campaign_status) AS campaign_status,
    SUM(impressions) FILTER (WHERE date >= CURRENT_DATE - 7)  AS impressions_7d,
    SUM(clicks)      FILTER (WHERE date >= CURRENT_DATE - 7)  AS clicks_7d,
    SUM(cost_micros) FILTER (WHERE date >= CURRENT_DATE - 7)  AS cost_micros_7d,
    SUM(conversions) FILTER (WHERE date >= CURRENT_DATE - 7)  AS conversions_7d,
    SUM(cost_micros) FILTER (WHERE date BETWEEN CURRENT_DATE - 14 AND CURRENT_DATE - 8) AS cost_micros_prev7d,
    SUM(conversions) FILTER (WHERE date BETWEEN CURRENT_DATE - 14 AND CURRENT_DATE - 8) AS conversions_prev7d,
    SUM(cost_micros) FILTER (WHERE date >= CURRENT_DATE - 30) AS cost_micros_30d,
    SUM(conversions) FILTER (WHERE date >= CURRENT_DATE - 30) AS conversions_30d,
    SUM(clicks)      FILTER (WHERE date >= CURRENT_DATE - 30) AS clicks_30d
  FROM google_ads_raw.campaign_performance_daily
  WHERE customer_id = {{CID}}
    AND date >= CURRENT_DATE - INTERVAL '90 days'
  GROUP BY campaign_id
)
SELECT
  campaign_id, campaign_name, campaign_status,
  COALESCE(impressions_7d, 0)  AS impressions_7d,
  COALESCE(clicks_7d, 0)       AS clicks_7d,
  ROUND(COALESCE(cost_micros_7d, 0) / 1000000.0, 2)  AS cost_eur_7d,
  COALESCE(conversions_7d, 0)  AS conversions_7d,
  ROUND(COALESCE(cost_micros_30d, 0) / 1000000.0, 2) AS cost_eur_30d,
  COALESCE(conversions_30d, 0) AS conversions_30d,
  ROUND((cost_micros_7d  / 1000000.0) / NULLIF(clicks_7d, 0), 2)  AS avg_cpc_7d,
  ROUND((cost_micros_30d / 1000000.0) / NULLIF(clicks_30d, 0), 2) AS avg_cpc_30d,
  ROUND((cost_micros_7d - cost_micros_prev7d)::numeric
        / NULLIF(cost_micros_prev7d, 0) * 100, 1) AS cost_change_pct_wow,
  ROUND((conversions_7d - conversions_prev7d)
        / NULLIF(conversions_prev7d, 0) * 100, 1) AS conversions_change_pct_wow
FROM agg
ORDER BY cost_micros_7d DESC NULLS LAST;

-- 3) Budget utilisation. The daily budget comes from the configuration snapshot, so the
--    view also reports WHICH DAY that budget was observed (budget_stand_vom). Read it:
--    a stale snapshot date means the sync has not run, not that the budget is unchanged.
CREATE OR REPLACE VIEW agent_reads.{{PREFIX}}_budget_utilization AS
WITH latest_budget AS (
  SELECT DISTINCT ON (campaign_id)
    campaign_id, campaign_name, status AS campaign_status,
    budget_amount_micros, snapshot_date
  FROM google_ads_raw.campaign_config_daily
  WHERE customer_id = {{CID}}
  ORDER BY campaign_id, snapshot_date DESC
),
spend_7d AS (
  SELECT campaign_id,
         AVG(cost_micros)::numeric AS avg_cost_micros,
         MAX(cost_micros)::numeric AS max_cost_micros
  FROM google_ads_raw.campaign_performance_daily
  WHERE customer_id = {{CID}}
    AND date >= CURRENT_DATE - 7
  GROUP BY campaign_id
)
SELECT
  b.campaign_id, b.campaign_name, b.campaign_status,
  ROUND(b.budget_amount_micros / 1000000.0, 2) AS daily_budget_eur,
  ROUND(s.avg_cost_micros / 1000000.0, 2)      AS avg_daily_cost_eur_7d,
  ROUND(s.max_cost_micros / 1000000.0, 2)      AS max_daily_cost_eur_7d,
  ROUND(s.avg_cost_micros / NULLIF(b.budget_amount_micros, 0)::numeric * 100, 1) AS avg_utilization_pct_7d,
  ROUND(s.max_cost_micros / NULLIF(b.budget_amount_micros, 0)::numeric * 100, 1) AS max_utilization_pct_7d,
  b.snapshot_date AS budget_stand_vom
FROM latest_budget b
LEFT JOIN spend_7d s USING (campaign_id)
WHERE b.campaign_status IN ('ENABLED', 'PAUSED')
ORDER BY avg_utilization_pct_7d DESC NULLS LAST;

-- 4) Search terms, 90 days. What people actually typed - the basis for negatives and for
--    harvesting new keywords. Grain is the query, so this fans out well beyond the
--    booked keywords.
CREATE OR REPLACE VIEW agent_reads.{{PREFIX}}_search_term_daily AS
SELECT
  date, campaign_id, ad_group_id, search_term, match_type, search_term_status,
  impressions, clicks,
  ROUND(cost_micros / 1000000.0, 2)                            AS cost_eur,
  conversions,
  ROUND(conversions_value_micros / 1000000.0, 2)               AS conversion_value_eur,
  ROUND(clicks::numeric / NULLIF(impressions, 0), 6)           AS ctr,
  ROUND((cost_micros / 1000000.0) / NULLIF(conversions, 0), 2) AS cost_per_conversion_eur
FROM google_ads_raw.search_term_daily
WHERE customer_id = {{CID}}
  AND date >= CURRENT_DATE - INTERVAL '90 days'
ORDER BY date DESC, cost_micros DESC;

-- 5) Keyword performance joined to the SAME DAY's bid and quality score. Effect and lever
--    side by side - this is what lets the reviewer recover a pre-change bid without
--    relying on the decision-log written by the agent being reviewed.
CREATE OR REPLACE VIEW agent_reads.{{PREFIX}}_keyword_performance_daily AS
SELECT
  p.date, p.campaign_id, p.ad_group_id, p.criterion_id,
  p.keyword_text, p.match_type,
  p.impressions, p.clicks,
  ROUND(p.cost_micros / 1000000.0, 2)                              AS cost_eur,
  p.conversions,
  ROUND(p.conversions_value_micros / 1000000.0, 2)                 AS conversion_value_eur,
  ROUND(p.clicks::numeric / NULLIF(p.impressions, 0), 6)           AS ctr,
  ROUND((p.cost_micros / 1000000.0) / NULLIF(p.clicks, 0), 2)      AS avg_cpc_eur,
  ROUND((p.cost_micros / 1000000.0) / NULLIF(p.conversions, 0), 2) AS cost_per_conversion_eur,
  k.status                                         AS keyword_status,
  ROUND(k.cpc_bid_micros / 1000000.0, 2)           AS cpc_bid_eur,
  ROUND(k.effective_cpc_bid_micros / 1000000.0, 2) AS effective_cpc_bid_eur,
  k.quality_score
FROM google_ads_raw.keyword_performance_daily p
LEFT JOIN google_ads_raw.keyword_config_daily k
  ON  k.customer_id   = p.customer_id
  AND k.snapshot_date = p.date
  AND k.ad_group_id   = p.ad_group_id
  AND k.criterion_id  = p.criterion_id
WHERE p.customer_id = {{CID}}
  AND p.date >= CURRENT_DATE - INTERVAL '90 days'
ORDER BY p.date DESC, p.cost_micros DESC;

-- Grants. The role must NOT get USAGE on google_ads_raw - only on agent_reads.
-- Substitute <tenant> to match the role created by
--   provision-tenant-db-user.sh --channel google <tenant> {{PREFIX}} property
--
-- GRANT USAGE ON SCHEMA agent_reads TO google_ro_<tenant>;
-- GRANT SELECT ON agent_reads.{{PREFIX}}_campaign_trends,
--                 agent_reads.{{PREFIX}}_budget_utilization,
--                 agent_reads.{{PREFIX}}_campaign_performance_daily,
--                 agent_reads.{{PREFIX}}_search_term_daily,
--                 agent_reads.{{PREFIX}}_keyword_performance_daily
--   TO google_ro_<tenant>;
--
-- Then verify as the service user:  sudo -u paperclip ~/.supabase-ro/q.sh <tenant> --check
