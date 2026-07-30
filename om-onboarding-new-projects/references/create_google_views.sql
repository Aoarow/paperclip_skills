-- create_google_views.sql
-- Per-property BigQuery views for a Google Ads client. Part of Gate-2 provisioning.
--
-- HOW GOOGLE DATA GETS HERE:
--   Ingestion is Google's native BigQuery Data Transfer at MCC level (login-customer
--   7807674607). It writes partitioned base tables p_ads_*_7807674607 that contain
--   EVERY account under the MCC (column: customer_id). So once the client's Google Ads
--   account (CID) is linked into the MCC, its data flows in automatically — no per-client
--   transfer needed. These views just scope and shape that data down to one client.
--
-- WHEN TO RUN: at Gate-2 prep, AFTER the client's CID is linked into the MCC and at least
--   one daily transfer has landed.
--
-- SUBSTITUTE two placeholders (do a plain find-replace) before running:
--   {{PROPERTY}}  BigQuery-safe technical alias derived from the exact human-defined
--                 property name: turn EVERY non-alphanumeric character into "_"
--                 (including dots and hyphens). This alias never renames the property.
--                 BigQuery object names cannot contain "-" or ".". Examples:
--                     lexacore.ai              -> lexacore_ai
--                     reiseglueck-bergstrasse.de -> reiseglueck_bergstrasse_de
--   {{CID}}       the client's raw numeric Google Ads customer id, digits only, no dashes
--                 (e.g. 107-535-0837 -> 1075350837)
--
-- RUN:
--   bq query --use_legacy_sql=false --project_id=lexacore-agents < create_google_views.sql
--
-- All three views are customer-scoped (WHERE customer_id = {{CID}}) so clients never mix.

-- 1) Daily campaign performance (90d) — the base view the other two build on.
CREATE OR REPLACE VIEW `lexacore-agents.google_ads_raw.v_{{PROPERTY}}_campaign_performance_daily` AS
SELECT
  s.segments_date AS date,
  s.campaign_id,
  c.campaign_name,
  c.campaign_status,
  c.campaign_advertising_channel_type AS channel_type,
  SUM(s.metrics_impressions) AS impressions,
  SUM(s.metrics_clicks) AS clicks,
  ROUND(SUM(s.metrics_cost_micros) / 1000000, 2) AS cost_eur,
  SUM(s.metrics_conversions) AS conversions,
  ROUND(SUM(s.metrics_conversions_value), 2) AS conversion_value_eur,
  SAFE_DIVIDE(SUM(s.metrics_clicks), SUM(s.metrics_impressions)) AS ctr,
  ROUND(SAFE_DIVIDE(SUM(s.metrics_cost_micros) / 1000000, SUM(s.metrics_clicks)), 2) AS avg_cpc_eur,
  ROUND(SAFE_DIVIDE(SUM(s.metrics_cost_micros) / 1000000, SUM(s.metrics_conversions)), 2) AS cost_per_conversion_eur,
  SAFE_DIVIDE(SUM(s.metrics_conversions), SUM(s.metrics_clicks)) AS conversion_rate
FROM `lexacore-agents.google_ads_raw.p_ads_CampaignStats_7807674607` AS s
LEFT JOIN (
  SELECT campaign_id,
    ANY_VALUE(campaign_name) AS campaign_name,
    ANY_VALUE(campaign_status) AS campaign_status,
    ANY_VALUE(campaign_advertising_channel_type) AS campaign_advertising_channel_type
  FROM `lexacore-agents.google_ads_raw.p_ads_Campaign_7807674607`
  WHERE _PARTITIONTIME = (SELECT MAX(_PARTITIONTIME) FROM `lexacore-agents.google_ads_raw.p_ads_Campaign_7807674607`)
    AND customer_id = {{CID}}
  GROUP BY campaign_id
) AS c ON s.campaign_id = c.campaign_id
WHERE s.segments_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
  AND s.customer_id = {{CID}}
GROUP BY s.segments_date, s.campaign_id, c.campaign_name, c.campaign_status, c.campaign_advertising_channel_type
ORDER BY s.segments_date DESC, cost_eur DESC;

-- 2) Campaign trends (7d / 30d + week-over-week). Built on the daily view above.
CREATE OR REPLACE VIEW `lexacore-agents.google_ads_raw.v_{{PROPERTY}}_campaign_trends` AS
WITH base AS (
  SELECT * FROM `lexacore-agents.google_ads_raw.v_{{PROPERTY}}_campaign_performance_daily`
),
agg AS (
  SELECT
    campaign_id,
    ANY_VALUE(campaign_name) AS campaign_name,
    ANY_VALUE(campaign_status) AS campaign_status,
    SUM(IF(date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY), impressions, 0)) AS impressions_7d,
    SUM(IF(date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY), clicks, 0)) AS clicks_7d,
    ROUND(SUM(IF(date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY), cost_eur, 0)), 2) AS cost_eur_7d,
    SUM(IF(date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY), conversions, 0)) AS conversions_7d,
    ROUND(SUM(IF(date BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY) AND DATE_SUB(CURRENT_DATE(), INTERVAL 8 DAY), cost_eur, 0)), 2) AS cost_eur_prev7d,
    SUM(IF(date BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY) AND DATE_SUB(CURRENT_DATE(), INTERVAL 8 DAY), conversions, 0)) AS conversions_prev7d,
    ROUND(SUM(IF(date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY), cost_eur, 0)), 2) AS cost_eur_30d,
    SUM(IF(date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY), conversions, 0)) AS conversions_30d,
    ROUND(SAFE_DIVIDE(
      SUM(IF(date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY), cost_eur, 0)),
      SUM(IF(date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY), clicks, 0))), 2) AS avg_cpc_7d,
    ROUND(SAFE_DIVIDE(
      SUM(IF(date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY), cost_eur, 0)),
      SUM(IF(date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY), clicks, 0))), 2) AS avg_cpc_30d
  FROM base
  GROUP BY campaign_id
)
SELECT
  campaign_id, campaign_name, campaign_status,
  impressions_7d, clicks_7d, cost_eur_7d, conversions_7d,
  cost_eur_30d, conversions_30d, avg_cpc_7d, avg_cpc_30d,
  ROUND(SAFE_DIVIDE(cost_eur_7d - cost_eur_prev7d, cost_eur_prev7d) * 100, 1) AS cost_change_pct_wow,
  ROUND(SAFE_DIVIDE(conversions_7d - conversions_prev7d, conversions_prev7d) * 100, 1) AS conversions_change_pct_wow
FROM agg
ORDER BY cost_eur_7d DESC;

-- 3) Budget utilization (latest budget vs. 7d spend).
CREATE OR REPLACE VIEW `lexacore-agents.google_ads_raw.v_{{PROPERTY}}_budget_utilization` AS
WITH latest_budget AS (
  SELECT campaign_id,
    ROUND(ANY_VALUE(campaign_budget_amount_micros) / 1000000, 2) AS daily_budget_eur,
    ANY_VALUE(campaign_name) AS campaign_name,
    ANY_VALUE(campaign_status) AS campaign_status
  FROM `lexacore-agents.google_ads_raw.p_ads_Campaign_7807674607`
  WHERE _PARTITIONTIME = (SELECT MAX(_PARTITIONTIME) FROM `lexacore-agents.google_ads_raw.p_ads_Campaign_7807674607`)
    AND customer_id = {{CID}}
  GROUP BY campaign_id
),
spend_7d AS (
  SELECT campaign_id,
    ROUND(AVG(daily_cost), 2) AS avg_daily_cost_eur_7d,
    ROUND(MAX(daily_cost), 2) AS max_daily_cost_eur_7d
  FROM (
    SELECT campaign_id, segments_date, SUM(metrics_cost_micros) / 1000000 AS daily_cost
    FROM `lexacore-agents.google_ads_raw.p_ads_CampaignStats_7807674607`
    WHERE segments_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
      AND customer_id = {{CID}}
    GROUP BY campaign_id, segments_date
  )
  GROUP BY campaign_id
)
SELECT b.campaign_id, b.campaign_name, b.campaign_status, b.daily_budget_eur,
  s.avg_daily_cost_eur_7d, s.max_daily_cost_eur_7d,
  ROUND(SAFE_DIVIDE(s.avg_daily_cost_eur_7d, b.daily_budget_eur) * 100, 1) AS avg_utilization_pct_7d,
  ROUND(SAFE_DIVIDE(s.max_daily_cost_eur_7d, b.daily_budget_eur) * 100, 1) AS max_utilization_pct_7d
FROM latest_budget AS b
LEFT JOIN spend_7d AS s USING (campaign_id)
WHERE b.campaign_status IN ('ENABLED', 'PAUSED')
ORDER BY avg_utilization_pct_7d DESC;
