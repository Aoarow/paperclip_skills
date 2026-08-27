---
name: om-amazon-account-management
description: The account-level (cross-property) duties of the KI-Account-Manager for one client's Amazon business — propose budget allocation across the client's properties within the human-approved total, arbitrate between sibling properties (cannibalization and head-term ownership across brands), and produce the client-facing monthly TACOS roll-up that spans the whole Amazon channel (one report per client, not per property). Campaign creation is also an Account-Manager act but has its own skill (om-amazon-campaign-creation). It also owns the first check on a **delivery-gap escalation** from a property Optimizer — whether the Buy Box, not the advertising, is why a campaign stopped serving. Use when the Account-Manager agent runs its monthly cycle, when a property agent escalates that campaigns have delivered nothing for days, or when asked an account-level question a single property cannot answer. DRAFT: campaign creation and the monthly roll-up are exercisable now; cross-property allocation and sibling arbitration are pass-through until a client has more than one property (avoid premature structure).
---

# Amazon Advertising — Account Management (cross-property)

This skill teaches the **KI-Account-Manager** the decisions a single property cannot make. One Account-Manager owns one client's Amazon business (= the head of that client's Paperclip project). It does **not** supervise the worker agents (they run autonomously on their property config); it owns the **account-level** concerns that emerge because, on Amazon, several brand-properties share one account, one budget, and one catalog (architecture memo §1; `architecture-and-principles.md`).

It runs **rarely** (monthly + on-demand) and is therefore cheap. For a **single-property client** (e.g. the Windspiel pilot) this tier is thin/pass-through — most of it activates only when the client has siblings.

**The agent proposes; humans dispose.** Budget stays human-owned (`budget.csv`); the Account-Manager *proposes* allocations within the human-approved total and never raises the total.

## Duties

### 1. Cross-property budget allocation — ⏸️ pass-through until multi-property
Within the client's human-approved **total**, propose how budget is distributed/shifted across the client's properties (e.g. move spend toward the property with headroom and better tACOS). The total and the per-property ceilings remain in `budget.csv` (human-owned, read-only). A proposed reallocation is escalated to the human to be written into `budget.csv` / `strategy.md` — the Account-Manager never edits them.
> **Single-property pilot:** there is nothing to allocate across — the whole budget is the one property's. Activates with the second property.

### 2. Sibling arbitration (cannibalization & head-term ownership) — ⏸️ pass-through until multi-property
When two of the client's properties (sibling brands) would compete on overlapping terms — especially a **head term** (manifest §5) — the Account-Manager decides which property owns the term and audits, account-wide, that no head term is used twice. This is the cross-property half of head-term ownership (the within-property half is the positive Targeter's job). Ownership decisions are recorded in the human-owned head-term map (`strategy.md`), proposed by the Account-Manager, confirmed by the human.
> **Single-property pilot:** no siblings → nothing to arbitrate. Activates with the second property.

### 3. Campaign creation — ✅ active (own skill)
Creating campaigns is a structural, account-level act and sits here, not with the property agents. The procedure lives in **`om-amazon-campaign-creation`** — this skill does not duplicate it; the Account-Manager invokes it. (PAUSED handover; human enables.)

### 4. Monthly client-facing TACOS roll-up — ✅ active (even for one property)
Produce **one** client-facing monthly scorecard across the whole Amazon channel (not one per property): the TACOS view the customer conversation is built on (brief §4, memo §8). TACOS = ad spend ÷ **total** sales; total sales come from the monthly sales export now (`public.sales_data` / customer CSV), automated via SP-API in Phase 2. Aggregate the per-property results (ACOS, spend, ad-attributed sales from Supabase) and the total-sales figure into the scorecard.
> **DRAFT:** the exact scorecard layout follows the Reporting decision (TODO §D / the Peggy-level reporting work). Reuse the Google monthly-report shape where it fits; keep ACOS (live) and TACOS (monthly) distinct.

### 5. Head-term map upkeep on priority changes — ✅ active (even for one property)
The per-product **traffic light** lives in the product Sheet (→ Supabase); its ruleset is manifest §8. A change that flips a class's **🟢 Grün** product has a strategic follow-on: that product is the class's **head-term owner** (§5), so the head-term ownership map in `strategy.md` must follow. When such a change is detected — the sync/n8n raises an issue for the Account-Manager, or it is caught on the monthly run by comparing the Sheet's Grün-per-class against the map — the Account-Manager **proposes** the head-term update to the human/Peggy. It **never** writes `strategy.md` or the light itself (both human-owned; agent proposes, human disposes). The positive Targeter then enforces the approved map via cross-ASIN negation.

### 6. Delivery-gap triage — the Buy-Box check on an Optimizer escalation — ✅ active (even for one property)
**Without the Buy Box, Sponsored Products campaigns do not serve.** A property Optimizer that sees a campaign deliver nothing for days escalates — correctly, because it cannot see the offer side. The Account-Manager is its direct supervisor and owns the first check: **is the Buy Box the explanation?** Answering it here ends the chain one step below Peggy.

Run this **before** passing a delivery-gap escalation upward. Two sources, and they answer different questions — use both:

| Source | Answers | Available from |
| :--- | :--- | :--- |
| `agent_reads.<tenant-prefix>_sales_daily.buy_box_percentage` | **When** did we hold the Buy Box? Daily share of page views with our featured offer; `0` = we had it on none. | 2026-07-01 |
| `agent_reads.<tenant-prefix>_buybox_daily` / `_buybox_current` | **Why** don't we hold it? (the five `buybox_status` values) | 2026-08-13 |

> **`<tenant-prefix>` is the *tenant* prefix (`bi_`, `wi_`) — never a property prefix.** As the
> account-level role you read the **account-wide** views, which already span every property of the
> client; filter them by ASIN or campaign to look at one brand. The property-scoped views
> (`bi_woodstork_…`) belong to the property agents, and your role is denied them **at the database
> level** — that denial is the design, not a misconfiguration. If you hit `permission denied` on a
> property-scoped view, you asked for the wrong view: switch to the account-wide one. Never request
> a grant to work around it, and never treat the denial as a blocker to escalate.

**Procedure**
1. Take the ASIN and the **exact date range** from the escalation.
2. Read `buy_box_percentage` for that ASIN across the range. A stretch at or near `0` that coincides with the delivery gap is the cause — the ads are not the problem.
3. Read `buybox_status` for the same range to get the **reason**, then route by it:

| Finding | Verdict | Action |
| :--- | :--- | :--- |
| `suppressed` | Amazon withdrew the Buy Box (typically: the item is cheaper off-Amazon). Ends by itself. | **Close the task.** No ad change — do not pause, do not lower bids, do not restructure. Write the `decision-log.md` entry. |
| `competitor_wins` | Offer side, but a **price** issue. | Close the ad escalation, raise the price topic **to Lexacore** — not to the customer. Record in `decision-log.md`. |
| `no_own_offer` | We are not on the listing at all (dead listing / no buyable offer). A real problem. | Escalate — but as a **listing** issue, naming it as such. |
| Buy Box held throughout (`we_win`, `buy_box_percentage` high) | Not the Buy Box. | Escalate to Peggy as originally raised. |
| **No data for the range** | Not provable. | Say so **explicitly** and escalate to Peggy. Never read a measurement gap as "all fine". |

**The last row is the one that bites.** The Buy-Box state is **not retrievable retroactively** — `amazon_buybox_daily` only knows days it actually measured, and nothing before 2026-08-13; `buy_box_percentage` reaches back to 2026-07-01 but says nothing about the *reason*. For a range before those dates the honest answer is "cannot be established", not a verdict.

Whatever the outcome, write a dated `decision-log.md` entry on the property — including the close-the-task case. A closed escalation without a logged reason recreates the same escalation next week.

> **Pending (needs the monthly report, which does not exist yet):** a Buy Box `suppressed` for **more than 10 consecutive days** belongs in the client's monthly report — no escalation, but the customer learns of it and it is on record. `days_in_status` in `agent_reads.<tenant-prefix>_buybox_current` is the field. Until the report exists, note it in `decision-log.md` so it can be picked up later.

## Inputs
| Source | Read for | Rights |
| :--- | :--- | :--- |
| `client.md` | the client's accounts, properties, autonomy, `CLIENT` code | READ (human-owned) |
| `budget.csv` | the human-approved total + per-property ceilings | READ (human-owned) |
| `strategy.md` (per property) | goals, head-term ownership maps | READ (never write) |
| Supabase (`amazon_ads_raw` / views) | per-property performance (ACOS, spend, ad-attributed sales) | READ |
| `public.sales_data` / monthly CSV | total sales for TACOS | READ |
| `agent_reads.<tenant-prefix>_buybox_daily` / `_buybox_current` | **why** an ASIN has no Buy Box — the five `buybox_status` values, `days_in_status` (duty 6) | READ |
| `agent_reads.<tenant-prefix>_sales_daily.buy_box_percentage` | **when** we held the Buy Box — the historical half of duty 6 | READ |
| each property's `decision-log.md` / `learnings.md` | context for allocation/arbitration | READ |

## Run sequence (monthly + on-demand)
1. Inbox cycle first (`lx-paperclip-inbox-cycle`) — handle account-level questions/escalations from the human or from a property agent. **A delivery-gap escalation from an Optimizer runs duty 6 before anything else** — it is the cheapest question in the queue and usually ends the chain here.
2. On the monthly tick: build the TACOS roll-up (duty 4). For a multi-property client, also run duties 1–2 (propose allocation, audit head-term ownership across siblings) and escalate proposals to the human.
3. On a campaign-creation request: invoke `om-amazon-campaign-creation`.
4. Close out per the inbox cycle; escalate anything beyond authority (budget total, strategy changes) to Peggy/human.

## What this skill does NOT do
- **Mutate property campaigns / bids / keywords** — that is the worker agents within `om-autonomy-levels`.
- **Edit `budget.csv` / `strategy.md`** — human-owned; propose, don't write.
- **Supervise the worker agents** — they run autonomously; the Account-Manager owns decisions, not oversight.

## References
- `architecture-and-principles.md` / architecture memo §1 — the Account-Manager tier and when it is instantiated.
- `om-amazon-campaign-creation` — the creation procedure (duty 3).
- `om-amazon-advertising-manifest` §5 — head-term ownership (cross-property arbitration).
- `om-amazon-ads-reference` — `supabase-schema.md` (per-property data, the `sales_data`/TACOS note, and the Buy-Box views used by duty 6).
- `lx-paperclip-inbox-cycle` — run/escalation mechanics.

## Maintenance
This skill owns the *account-level coordination procedure*. Creation lives in its own skill; doctrine in the manifest; budgets/strategy stay human-owned in Drive. Flesh out duties 1–2 and the scorecard layout when a multi-property client and the Reporting decision make them real.
