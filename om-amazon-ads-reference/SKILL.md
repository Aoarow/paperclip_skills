---
name: om-amazon-ads-reference
description: Stable Amazon Advertising API reference and data-layer specification for all Online Marketing agents — the Sponsored Products object model (campaign / ad group / product ad / keyword / target / negative), match types, bulk-operation and rate-limit rules, the report types and their grains, and the amazon_ads_raw Supabase schema (the nightly-ingested tables the agents actually read). The shared spec/contract layer used by Amazon campaign creation, optimization, and targeting. Use whenever an agent needs the exact, binding API or data-schema contract for building, changing, verifying, or reading an Amazon advertising structure. Strategic doctrine lives in om-amazon-advertising-manifest; evolving best practice lives in Drive KI-Wissen/Amazon.
---

# Amazon Advertising — Shared Reference

> **Where this skill's reference files actually are.** Paperclip copies only this `SKILL.md` into
> the agent runtime — the `references/` folder is not delivered with it, and the runtime folder
> carries a hash suffix. A relative `references/<file>` path therefore does **not** resolve.
> Read them from the filesystem instead:
>
> **`/srv/lexacore-skills/om-amazon-ads-reference/references/<file>`**
>
> That path is readable for the agent user and is kept current from git. Progressive disclosure is
> unchanged — open the one file you need, not all of them.


The binding spec layer for every Amazon ad agent. This skill holds **no procedures of its own** — it is a reference index. The procedures that use these files live in the consuming skills: `om-amazon-campaign-creation`, `om-amazon-optimization`, `om-amazon-positive-targeting`, `om-amazon-negative-targeting`.

Load only the file you need (progressive disclosure); do not read them all up front.

> **Tool availability is never a question of memory.** Before you record that a tool is not
> callable — and above all before you escalate or hand work to another agent because of it —
> read `references/mcp-write-tools.md` and find **your own agent name** in the toolset lists.
> That block is generated from the same registry the runtime is stamped from, so it cannot
> disagree with what you actually hold. That another agent lacks a tool says nothing about
> whether you have it.

## Reference files

| File | Status |
|---|---|
| `references/supabase-schema.md` — the `amazon_ads_raw` tables (catalog + report streams), the camelCase/ID-cast pitfalls, the ASIN-join problem, the `public` join targets, the planned views, and the RLS state. **This is what the agents query for performance, not the Ads API.** | ✅ generated from the live DB (2026-06-15) |
| `references/report-types.md` — report streams & grains, attribution windows, the look-back/freshness rule, the **search-term stream** (its fan-out, the AUT caveat, the 65-day backfill limit), and not-yet-ingested reports. | ✅ data-grounded |
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
