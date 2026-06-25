---
name: om-autonomy-levels
description: Defines the autonomy levels for Online Marketing optimizer agents — what an agent may change on its own at each level, and which actions always escalate to the department head. The level for a given property is set in its client.md; this skill defines what each level means. Use this whenever an optimizer agent needs to decide whether an action is within its autonomy or must be escalated.
---

# Online Marketing — Autonomy Levels

Optimizer agents are kept on a short leash at first and earn more freedom as the system
proves reliable and experience accumulates. The level for each property is set in its
`client.md` (`autonomy_level: ...`); this skill defines what each level permits. An
agent reads its level from `client.md` and applies the matching section below.

Principle: agents propose, humans dispose. **No level** ever permits raising the
property's total monthly budget (`budget.csv`), enabling/pausing/deleting structures that are human decisions,
or acting without a documented reason.

## Levels

The three levels are **department-wide**. The lever percentages in this first block are the **Google lever map** (manual CPC, smart-bidding targets). The **Amazon lever map** — same three levels, Amazon-specific levers — is in its own section below.

### Observe
The starting level for a new or unproven property. No live changes.
- Allowed: analyze performance, document findings, propose changes as tasks to the
  department head.
- Everything that would mutate the account escalates.

### Standard
The everyday level once a property runs reliably.
- Manual bid changes (`MANUAL_CPC` campaigns) up to **±20 %** per campaign.
- Keyword adjustments (negative keywords, new long-tail keywords).
- Asset adjustments (new ad variations within the documented strategy).
- Budget reallocation between campaigns up to **15 %** of the property's total budget (the total itself is unchanged).

(Note: under smart bidding there are no manual bids — the equivalent lever is the
smart-bidding *target*, which is an *Extended*-level action. A Standard property on smart
bidding therefore optimizes via keywords, negatives, assets, and budget reallocation.)

### Extended
For proven properties with a solid track record.
- Manual bid changes (`MANUAL_CPC` campaigns) up to **±35 %** per campaign.
- Keyword and asset adjustments as in Standard.
- Budget reallocation between campaigns up to **30 %** of the property's total budget (the total itself is unchanged).
- Adjusting smart-bidding targets (tCPA / tROAS) within **±15 %** of the current target.

## Amazon — lever map per level

> **Confirmed against the rulesets (2026-06-25).** The level here is the **ceiling** — the most a trust level permits. The engine's *chosen* per-item bid step is the **maturity rule** (new ≤ 20 % / established ≤ 10 % per change) in `om-amazon-optimization` (*The bidding-policy ruleset*, knob 3); the effective change is the **smaller** of engine step and level ceiling. Harvest/graduation and waste thresholds live in `om-amazon-positive-targeting` / `om-amazon-negative-targeting`. Numbers are not restated here — only the permission ceilings are.

On Amazon the daily Optimizer runs a **deterministic bidding engine** over all keywords/targets, and the LLM sets the **policy** (memo §7). Autonomy therefore gates two different things: the **size of a single engine-applied change**, and **who may change the policy itself**.

### Observe (Amazon)
No live changes. Analyze performance, document findings, propose changes as tasks. Everything that would mutate the account escalates.

### Standard (Amazon)
- **Bid changes** (per keyword/target, applied by the engine within policy): ceiling **±20 %** per item per run — within it the engine uses its maturity step (`om-amazon-optimization` knob 3).
- **Keyword/target adds** from harvesting (positive Targeter) within the documented strategy.
- **Negative adds** (waste negatives; graduation negatives) — the negation web.
- **Budget reallocation between campaigns** within the property's total: up to **15 %** of the total (the total itself is unchanged).
- **Pausing individual poor keywords/targets** is allowed.

### Extended (Amazon)
- **Bid changes**: ceiling **±35 %** per item per run (the engine's maturity step still applies within it).
- Keyword/target/negative adjustments as in Standard.
- **Budget reallocation between campaigns** up to **30 %** of the total.
- **Adjusting the target-ACOS bands** (the Research vs. Profit bands) within **±15 %** of the value set in `strategy.md` — the analogue of the Google smart-bidding target change. The durable band in `strategy.md` stays human-owned: a lasting change is proposed up, not silently rewritten.

**Amazon — always escalate (in addition to the cross-channel list below):** pausing or enabling a whole campaign; raising the property's total monthly budget; changing the head-term ownership map; activating a newly created (PAUSED) campaign; a bid that would breach the **€0.07 floor or the €5.00 hard max-CPC** (knob 5) — to the human via the Account Manager; any change beyond the active level's bands.

## Always escalate (every level)
Regardless of level, escalate these to the department head:
- Raising the property's total monthly budget (`budget.csv`).
- Pausing a top-performer campaign.
- A campaign with no impressions for three days or more.
- Any change that would exceed the active level's ceilings.
- Any action whose justification is unclear — when in doubt, do nothing and escalate.

(Operational failures — a missing Drive document or failed ad-platform access — are
also escalations, handled in the agent's `HEARTBEAT.md`.)

## Maintenance
This skill is the single source of truth for Online Marketing autonomy levels.
`client.md` selects a level; it never redefines one. If the levels change, update them
here once. Other departments define their own autonomy levels in their own skill when
the need is real — do not generalize this one prematurely.
