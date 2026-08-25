# Amazon Ads MCP — write path & tool map

How agents **execute** changes on a live Amazon profile. Reads stay on Supabase (see `supabase-schema.md`); the MCP is the **write + verify** path only.

## How the MCP is reached (ops-wired, do not reconfigure from an agent)

- MCP server name in the runtime: **`amazon-ads`** (Codex `[mcp_servers.amazon-ads]`, streamable HTTP, EU endpoint `https://advertising-ai-eu.amazon.com/mcp`).
- **Fixed Account Context:** the property's `profileId` is pinned in the connection headers (`Amazon-Ads-AI-Account-Selection-Mode: FIXED` + `Amazon-Advertising-API-Scope: <profileId>`). The connection can therefore touch **only that one property** — an agent cannot reach another advertiser. Because the account is fixed in the header, tool calls generally do **not** need an account/profile argument.
- Auth (LWA bearer) is refreshed automatically out-of-band; agents never handle tokens.
- **Tool access is allow-listed** at the config level (`enabled_tools`). Tools not on the list are not callable — this is a hard floor *beneath* the autonomy bands, not a substitute for them. **Account/manager/user-admin tools are permanently excluded.** Of the delete tools, **only `campaign_management-delete_target` is enabled** (human decision 2026-07-09, for the negative-targeting lane); `delete_campaign` / `delete_ad_group` / `delete_ad` / `delete_ad_association` remain excluded.

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
| **Remove a negative / a stray target** (incl. the on-remove invariant; match-type change = delete + re-create) — `om-amazon-negative-targeting` | `campaign_management-delete_target` (the **only** enabled delete tool) | `campaign_management-query_target` |
| **Create a campaign** (PAUSED) — `om-amazon-account-management` | `campaign_management-create_singleshot_sp_campaign` (one-shot) **or** `create_campaign` + `create_ad_group` + `create_ad` + `create_target` | `campaign_management-query_campaign` |
| **Read for verify only** (the data read of record is Supabase) | `query_campaign` / `query_ad_group` / `query_target` / `query_ad`; `account_management-query_advertiser_account`; `reporting-*` | — |

## Which levers are actually callable (this differs per agent)

The tool map above lists the **right** tool for each lever. Whether that tool is **callable in
your runtime** is a separate question: `enabled_tools` is set per agent, and a lever the autonomy
level permits may have no tool behind it.

**Current state — generated, never hand-maintained.** The block between the markers below is
produced from the authoritative registry `/home/paperclip/.amazon-ads-mcp/tenants.json` — the
same file `render-mcp-configs.py` stamps the agents' Codex configs from, so the map and the
runtime cannot disagree. Regenerate with `~/.amazon-ads-mcp/tool-map.py`; the daily
`~/paperclip-fixes/flotte.sh` check reports drift. **Do not edit between the markers by hand.**

> **⚠️ A stale map is worse than no map — and this one has now caused the same failure twice.**
> On 2026-08-25 this table still read "`update_target_bid` — WIN-amz Optimizer only", 20 days
> out of date: six property Optimizers held the tool, including the one that owned the campaign
> in question. Three agents drew the correct conclusion from the wrong premise — that nobody
> could execute a bid change for Bimmerle — and escalated **upward past the agent that could**.
> Six runs, no mutation (LEXA-590 / 595 / 596). The first occurrence is the LEXA-399…412 note
> below; there the tool really was missing. **When a lever looks unavailable, verify against the
> registry before concluding that it is** — and never route an execution request past its owner.

> **⚠️ Two `tenants.json` exist.** The authoritative one is under `/home/paperclip` (the renderer
> runs with `HOME=/home/paperclip`). The copy under `/home/alex` is left over from the migration,
> is out of date, and must not be read for this map.

<!-- TOOL-MAP:START — erzeugt von ~/.amazon-ads-mcp/tool-map.py, nicht von Hand pflegen -->

| Tool | In toolset | Agents |
| :--- | :--- | ---: |
| `campaign_management-update_target_bid` | `operate_bid` | 6 |
| `campaign_management-update_campaign_budget` | **none** | **nobody** |
| `campaign_management-update_target` | **none** | **nobody** |
| `campaign_management-update_campaign_state` | **none** | **nobody** |
| `campaign_management-update_campaign` | `operate`, `operate_bid` | 20 |
| `campaign_management-delete_target` | `operate`, `operate_bid` | 20 |

Which agent holds which toolset:

- **`operate`** (13 tools) — `BIM-amz Account Manager`, `BIM-donpasquale NegTar`, `BIM-donpasquale PosTar`, `BIM-evermann NegTar`, `BIM-evermann PosTar`, `BIM-loerch NegTar`, `BIM-loerch PosTar`, `BIM-needle NegTar`, `BIM-needle PosTar`, `BIM-woodstork NegTar`, `BIM-woodstork PosTar`, `WIN-amz Account Manager`, `WIN-amz NegTar`, `WIN-amz PosTar`
- **`operate_bid`** (14 tools) — `BIM-donpasquale Optimizer`, `BIM-evermann Optimizer`, `BIM-loerch Optimizer`, `BIM-needle Optimizer`, `BIM-woodstork Optimizer`, `WIN-amz Optimizer`
- **`read`** (5 tools) — `BIM-donpasquale Reviewer`, `BIM-evermann Reviewer`, `BIM-loerch Reviewer`, `BIM-needle Reviewer`, `BIM-woodstork Reviewer`, `WIN-amz Reviewer`

<!-- TOOL-MAP:END -->

**If the tool you need is not callable, escalate — never substitute.** Specifically:
- **delete + re-create is not a bid update.** It destroys the target's history and its
  performance record, and the engine's maturity rules then treat a proven target as new.
- **`update_campaign` is not a budget tool.** It has replace semantics and can flip campaign
  state as a side effect (see the binding rules below).
- Name the exact missing tool id in the escalation. That is what makes it fixable in one step
  instead of three rounds. *(This cost the Windspiel property two weeks and seven issues —
  LEXA-399 through LEXA-412 — where the Optimizer correctly identified a bid cut, the Account
  Manager correctly approved it, and nobody could execute it. A human finally set the bid by
  hand. The agents were right to refuse the workaround; the gap was above them.)*

### Bid writes — guardrails (`update_target_bid`)

Now that the tool is live for the property Optimizers, the rules around it are binding — for every agent that holds it, not just the first one:

1. **Ceiling from the autonomy level** (`om-autonomy-levels`): Standard **±20 %** per item per
   run, Extended ±35 %. The engine's maturity step (`om-amazon-optimization` knob 3) applies
   *within* that ceiling — the effective change is the **smaller** of the two.
2. **Hard bounds:** never below the **€0.07 floor**, never above the **€5.00 max-CPC**. A bid
   that would breach either escalates instead.
3. **Verify after every write** with `campaign_management-query_target` — via the MCP, not
   Supabase, which has not ingested the change yet. Log the read-back value, not the intended
   value.
4. **Settling:** after changing a target's bid, leave it alone for **7 days** unless a hard
   failure appears. Do not re-cut the next morning because the numbers have not moved yet —
   they cannot have.
5. **One reason per change.** Record in `decision-log.md` which measured fact triggered it
   (clicks, spend, orders, ACOS over which window), the old bid and the read-back new bid.

## Binding rules

- **Verify every write** by reading it back with the matching `query_*` tool — **via the MCP, not Supabase** (a just-made change is not yet ingested; this is the Optimizer run-sequence "verify via Ads API" step).
- **⚠️ `update_campaign` REPLACES, it does not patch.** Fields you omit are **reset to their defaults, not preserved**: an update sent with only `{campaignId, name}` **silently flips a `PAUSED` campaign to `ENABLED`**. **Always send `state` explicitly** — plus every other field you intend to keep — on *every* `update_campaign` call, and read the campaign back to confirm the state you expected. This is a live guardrail hazard, not a cosmetic one: a rename or a budget tweak can activate a campaign that doctrine requires to stay paused (manifest / the PAUSED handover). *(Learned the hard way 2026-07-17: a rename enabled three freshly built PAUSED campaigns.)* Treat any other `update_*` tool as replace-semantics until proven otherwise — read its input schema and send the full intended state.
- **Delete tools:** only `campaign_management-delete_target` is callable, and only for the negative-targeting lane (removing a negative / the on-remove invariant). **Never call any other delete tool** (`delete_campaign` / `delete_ad_group` / `delete_ad` / `delete_ad_association`) or any account/manager/user-admin tool — they are excluded at the config level and out of every agent's remit; a real need escalates to a human.
- **Pausing/enabling a whole campaign** (`update_campaign_state`) and **raising the property budget** are escalate-only regardless of tool availability (see `om-autonomy-levels`). New campaigns are handed over **PAUSED**.
- Stay within the autonomy band (`om-autonomy-levels`) and the bidding/targeting rulesets (`om-amazon-optimization`, the targeting skills) — the MCP makes an action *possible*, the rulesets decide whether it is *allowed*.

## Maintenance

Tool ids reflect the Amazon Ads MCP (open beta, EU) as of 2026-06-25. If the MCP tool surface changes, re-list it (`tools/list`) and update this table. Connection/credential wiring is ops, documented outside the skill (server `~/.amazon-ads-mcp/`), never in the repo.
