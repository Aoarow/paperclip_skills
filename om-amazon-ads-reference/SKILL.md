---
name: om-amazon-ads-reference
description: Stable Amazon Advertising API reference and data-layer specification for all Online Marketing agents — the Sponsored Products object model (campaign / ad group / product ad / keyword / target / negative), match types, bulk-operation and rate-limit rules, the report types and their grains, and the amazon_ads_raw Supabase schema (the Airbyte-ingested tables the agents actually read). The shared spec/contract layer used by Amazon campaign creation, optimization, and targeting. Use whenever an agent needs the exact, binding API or data-schema contract for building, changing, verifying, or reading an Amazon advertising structure. Strategic doctrine lives in om-amazon-advertising-manifest; evolving best practice lives in Drive KI-Wissen/Amazon.
---

# Amazon Advertising — Shared Reference

The binding spec layer for every Amazon ad agent. This skill holds **no procedures of its own** — it is a reference index. The procedures that use these files live in the consuming skills: `om-amazon-campaign-creation`, `om-amazon-optimization`, `om-amazon-positive-targeting`, `om-amazon-negative-targeting`.

Load only the file you need (progressive disclosure); do not read them all up front.

## Reference files

| File | Status |
|---|---|
| `references/supabase-schema.md` — the `amazon_ads_raw` tables (catalog + report streams), the camelCase/ID-cast pitfalls, the ASIN-join problem, the `public` join targets, the planned views, and the RLS state. **This is what the agents query for performance, not the Ads API.** | ✅ generated from the live DB (2026-06-15) |
| `references/report-types.md` — report streams & grains, attribution windows, the 3-day look-back/freshness rule, the Search-Term-report gap (monthly n8n, planned), and not-yet-ingested reports. | ✅ data-grounded |
| `references/sp-object-model.md` — SP hierarchy (profile → campaign → ad group → product ad / keyword / target / negatives), fields, states, the MANUAL/AUTO distinction, the write path. | ✅ data-grounded |
| `references/match-types.md` — keyword match types (broad/phrase/exact), product/category/auto targeting expressions, negative match types, and where each value lives in the data. | ✅ data-grounded |
| `references/bulk-and-rate-limits.md` — bulk-creation model, throttling/back-off, partial-failure handling. | ✅ grounded in the official Ads API rate-limiting docs (limits are dynamic — no fixed numbers; 429 + `Retry-After`) |
| `references/common-errors.md` — error lookup + the binding hard-stop/escalate rule. | ✅ standard HTTP semantics + rate-limit specifics; extend the error *bodies* from run logs |
| `references/mcp-write-tools.md` — the **write path**: how the `amazon-ads` MCP is reached (FIXED to the property), the skill-action → MCP-tool map, verify-after-write, and the delete/admin exclusions. | ✅ grounded in the live MCP tool surface (EU beta, 2026-06-25) |

## Data path (the binding rule)

- **Read performance from Supabase** (`amazon_ads_raw.*` / the `public` views), the same source the lexacore.de customer reporting uses — never read performance directly from the Ads API.
- **Write changes via the `amazon-ads` MCP** (`references/mcp-write-tools.md` — tool map + verify-after-write), never into Supabase.
- The two data homes join on **ASIN** (see architecture memo §4 / brief §4).

## Maintenance

This is the contract layer — it changes when the Amazon Ads API or the ingestion schema changes, and is edited by humans / devs only. Strategic doctrine belongs in `om-amazon-advertising-manifest`; evolving best practice and experience belong in Drive `KI-Wissen/Amazon` (Research-maintained), never here.
