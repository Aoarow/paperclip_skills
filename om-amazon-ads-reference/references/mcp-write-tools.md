# Amazon Ads MCP — write path & tool map

How agents **execute** changes on a live Amazon profile. Reads stay on Supabase (see `supabase-schema.md`); the MCP is the **write + verify** path only.

## How the MCP is reached (ops-wired, do not reconfigure from an agent)

- MCP server name in the runtime: **`amazon-ads`** (Codex `[mcp_servers.amazon-ads]`, streamable HTTP, EU endpoint `https://advertising-ai-eu.amazon.com/mcp`).
- **Fixed Account Context:** the property's `profileId` is pinned in the connection headers (`Amazon-Ads-AI-Account-Selection-Mode: FIXED` + `Amazon-Advertising-API-Scope: <profileId>`). The connection can therefore touch **only that one property** — an agent cannot reach another advertiser. Because the account is fixed in the header, tool calls generally do **not** need an account/profile argument.
- Auth (LWA bearer) is refreshed automatically out-of-band; agents never handle tokens.
- **Tool access is allow-listed** at the config level (`enabled_tools`). Tools not on the list are not callable — this is a hard floor *beneath* the autonomy bands, not a substitute for them. **Delete and account/user-admin tools are permanently excluded.**

## Tool map (skill action → MCP tool → verify)

Tools are self-describing: read each tool's MCP **input schema** (its declared properties) for exact arguments — do not assume field names. Names below are the binding tool ids.

| Lever (skill) | MCP tool to call | Verify after with |
| :--- | :--- | :--- |
| **Bid change** per keyword/target — `om-amazon-optimization` | `campaign_management-update_target_bid` | `campaign_management-query_target` |
| **Budget reallocation** between campaigns (within the property total) — `om-amazon-optimization` | `campaign_management-update_campaign_budget` | `campaign_management-query_campaign` |
| **Pause a poor keyword/target** — `om-amazon-optimization` | `campaign_management-update_target` (state) | `campaign_management-query_target` |
| **Graduate a winner** to Exact-Profit (+ negate-exact in source, one move §4) — `om-amazon-positive-targeting` | `campaign_management-create_target` (positive in Exact-Profit) **and** `campaign_management-create_target` (negative-exact in source) | `campaign_management-query_target` |
| **Head-term ownership** cross-ASIN negation §5 — `om-amazon-positive-targeting` | `campaign_management-create_target` (negative-exact on sibling ASINs) | `campaign_management-query_target` |
| **Waste negative** (term/ASIN) — `om-amazon-negative-targeting` | `campaign_management-create_target` (negative-exact keyword / negative product target) | `campaign_management-query_target` |
| **Create a campaign** (PAUSED) — `om-amazon-account-management` | `campaign_management-create_singleshot_sp_campaign` (one-shot) **or** `create_campaign` + `create_ad_group` + `create_ad` + `create_target` | `campaign_management-query_campaign` |
| **Read for verify only** (the data read of record is Supabase) | `query_campaign` / `query_ad_group` / `query_target` / `query_ad`; `account_management-query_advertiser_account`; `reporting-*` | — |

## Binding rules

- **Verify every write** by reading it back with the matching `query_*` tool — **via the MCP, not Supabase** (a just-made change is not yet ingested; this is the Optimizer run-sequence "verify via Ads API" step).
- **Never call a delete tool** (`campaign_management-delete_*`) or any account/manager/user-admin tool. These are excluded at the config level and are out of every agent's remit; a real need escalates to a human.
- **Pausing/enabling a whole campaign** (`update_campaign_state`) and **raising the property budget** are escalate-only regardless of tool availability (see `om-autonomy-levels`). New campaigns are handed over **PAUSED**.
- Stay within the autonomy band (`om-autonomy-levels`) and the bidding/targeting rulesets (`om-amazon-optimization`, the targeting skills) — the MCP makes an action *possible*, the rulesets decide whether it is *allowed*.

## Maintenance

Tool ids reflect the Amazon Ads MCP (open beta, EU) as of 2026-06-25. If the MCP tool surface changes, re-list it (`tools/list`) and update this table. Connection/credential wiring is ops, documented outside the skill (server `~/.amazon-ads-mcp/`), never in the repo.
