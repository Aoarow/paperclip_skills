# Supabase Data Layer — `google_ads_raw` and the `agent_reads` views

The **measured truth** for Google Ads. Agents read performance from here; they write only
through the Google Ads MCP, and they verify a just-made change through GAQL. The Supabase
project ID and connection details are **not** in this skill — they live in the property's
`data-sources.md` and the secret store.

> Verified live on 2026-09-02 against the running system. When the schema changes,
> regenerate this file from the live DB — do not hand-edit drift in.

**BigQuery was retired on 2026-09-02.** Dataset, views and the MCC-level Data Transfer are
deleted. Any instruction naming `lexacore-agents.google_ads_raw` or a `v_<property>_*` view
is stale; report it rather than working around it.

## How the data gets here

`/home/paperclip/.google-ads-sync/google_ads_sync.py` — Python stdlib only plus `psql` for
loading, modelled on the Amazon `ads_sync.py`. Runs as the service user `paperclip`, nightly
at **05:15 UTC** via cron under `cron_guard.py` (`ALERT_THRESHOLD=1`, so a single missed run
raises an alert). Default lookback 14 days, because Google attributes conversions
retroactively.

It calls the Google Ads API **per account**. There is no MCC-level pipeline any more, so an
account does not need to sit under the MCC to be covered.

> **The header rule is load-bearing.** An account under the MCC (`4747084209`) needs
> `login-customer-id: 7807674607`. An independent account (`3010573696`) must **not** have
> it — with the header Google answers `403 USER_PERMISSION_DENIED`. This has produced the
> false diagnosis "account unreachable" more than once. The rule lives in the sync's
> `ACCOUNTS` list, one tuple per account.

## Two table groups

| Group | Tables | Why it exists |
| :--- | :--- | :--- |
| **Metrics** (time series) | `campaign_performance_daily`, `keyword_performance_daily`, `search_term_daily` | What happened. Re-fetchable from GAQL at any time. |
| **Snapshots** (daily state) | `campaign_config_daily`, `keyword_config_daily` | What the settings *were*. **Not retrievable retroactively** — every unmeasured day is lost for good. |

Both groups load with the same dedup strategy: delete the incoming keys in the target, then
insert. Re-running a day is therefore safe and produces no duplicates.

**The snapshots are the point of the whole data layer.** `om-google-review` measures a
decision 14 days later against its pre-change value. Without snapshots the only source for
that value is `decision-log.md` — written by the very agent under review. The snapshots are
the independent witness. **They start on 2026-09-02**; before that there is nothing, and that
gap is permanent.

## Conventions

Google's layer deliberately does **not** inherit the Airbyte-era quirks that the Amazon
schema still carries. Read `om-amazon-ads-reference/references/supabase-schema.md` for the
contrast — do not carry Amazon's workarounds over here.

| Amazon (Airbyte legacy) | Google | Consequence |
| :--- | :--- | :--- |
| camelCase, case-sensitive, must be double-quoted | **snake_case** | no quoting needed |
| IDs `varchar` in catalog, `bigint` in reports | **`bigint` everywhere** | no join casts |
| dates stored as `varchar` | **real `date`** | no casts for time windows |
| `_airbyte_*` metadata columns | `_row_id`, `_extracted_at`, `_sync_run` | `_extracted_at` is the freshness check |

**Amounts are stored as micros** (`cost_micros`, `budget_amount_micros`, `cpc_bid_micros`) —
lossless, exactly as the API delivers them. The `agent_reads` views convert to EUR. Agents
never see micros and never convert.

One exception worth knowing: `metrics.conversions_value` comes back from the API as a
**double in account currency, not micros** (unlike `cost_micros`). The sync multiplies it by
1,000,000 on the way in, so storage stays uniform.

### The two Postgres traps in every ratio

Both were paid for once, in a view that returned a plausible wrong number rather than an
error:

1. **Integer division.** `cost_micros` is `bigint`, and `bigint / bigint` truncates —
   `2000000 / 10000000 = 0`, silently. BigQuery's `SAFE_DIVIDE` computed in floating point
   and hid this. Cast explicitly: `::numeric`.
2. **Division by zero.** `SAFE_DIVIDE` returned NULL; Postgres raises. Guard with `NULLIF`.

**You need both.** `NULLIF` alone still truncates; the cast alone still raises. The bug that
shipped had `NULLIF` and no cast, and reported 0 % budget utilisation on a campaign at 20 %.

## The five views an agent reads

Per property, prefixed (`lxai` = lexacore.ai, `lxde` = lexacore.de). Resolve the prefix and
tenant name from the property's `data-sources.md`.

| View | Read it for |
| :--- | :--- |
| `<prefix>_campaign_trends` | **First read of every run.** 7d/30d per campaign, week-over-week change. |
| `<prefix>_budget_utilization` | Before any budget or bid decision. Carries `budget_stand_vom` — the date of the snapshot the budget came from. |
| `<prefix>_campaign_performance_daily` | Day by day, when the trends need explaining. |
| `<prefix>_search_term_daily` | What people actually typed. Negatives and keyword harvesting. |
| `<prefix>_keyword_performance_daily` | Keyword outcome joined to **that day's** bid and quality score — effect and lever side by side. |

All views are limited to 90 days and filtered on the property's numeric `customer_id`.

**Read `budget_stand_vom`.** A stale snapshot date means the sync has not run — not that the
budget is unchanged. Judge it before acting on a utilisation figure.

## Access

Agents do not use an MCP for this. They use the shell wrapper:

```
~/.supabase-ro/q.sh <tenant> -c "<SQL>"
```

Each tenant logs in as its own role `google_ro_<tenant>`, `NOBYPASSRLS`, granted `SELECT` on
`agent_reads.<prefix>_*` **and nothing else** — no `USAGE` on `google_ads_raw`, no access to
`public`. That grant *is* the tenant isolation; it is enforced by the database, not by agent
good behaviour.

`q.sh <tenant> --check` runs the isolation self-test: exactly one `customer_id` visible, all
five views readable, other tenants' views denied, `public.products` denied. **Run it as the
service user** — `sudo -u paperclip ~/.supabase-ro/q.sh <tenant> --check`. Checking as
yourself proves nothing about what the agent can see; `/home/alex` is not even readable by
`paperclip`, a trap that has cost time five times now.

## Adding a property

See `om-onboarding-new-projects/references/google.md` and its
`create_google_views.sql` — the five views plus the role provisioning, with the two
placeholders `{{PREFIX}}` and `{{CID}}`.
