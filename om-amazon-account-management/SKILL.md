---
name: om-amazon-account-management
description: The account-level (cross-property) duties of the KI-Account-Manager for one client's Amazon business — propose budget allocation across the client's properties within the human-approved total, arbitrate between sibling properties (cannibalization and head-term ownership across brands), and produce the client-facing monthly TACOS roll-up that spans the whole Amazon channel (one report per client, not per property). Campaign creation is also an Account-Manager act but has its own skill (om-amazon-campaign-creation). Use when the Account-Manager agent runs its monthly cycle or is asked an account-level question a single property cannot answer. DRAFT: campaign creation and the monthly roll-up are exercisable now; cross-property allocation and sibling arbitration are pass-through until a client has more than one property (avoid premature structure).
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

## Inputs
| Source | Read for | Rights |
| :--- | :--- | :--- |
| `client.md` | the client's accounts, properties, autonomy, `CLIENT` code | READ (human-owned) |
| `budget.csv` | the human-approved total + per-property ceilings | READ (human-owned) |
| `strategy.md` (per property) | goals, head-term ownership maps | READ (never write) |
| Supabase (`amazon_ads_raw` / views) | per-property performance (ACOS, spend, ad-attributed sales) | READ |
| `public.sales_data` / monthly CSV | total sales for TACOS | READ |
| each property's `decision-log.md` / `learnings.md` | context for allocation/arbitration | READ |

## Run sequence (monthly + on-demand)
1. Inbox cycle first (`lx-paperclip-inbox-cycle`) — handle account-level questions/escalations from the human or from a property agent.
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
- `om-amazon-ads-reference` — `supabase-schema.md` (per-property data + the `sales_data`/TACOS note).
- `lx-paperclip-inbox-cycle` — run/escalation mechanics.

## Maintenance
This skill owns the *account-level coordination procedure*. Creation lives in its own skill; doctrine in the manifest; budgets/strategy stay human-owned in Drive. Flesh out duties 1–2 and the scorecard layout when a multi-property client and the Reporting decision make them real.
