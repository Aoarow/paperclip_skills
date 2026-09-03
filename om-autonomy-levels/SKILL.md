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
- **Negative adds** (waste negatives; graduation negatives) — the negation web. **One carve-out:** a negative arising from the **target-miss trigger** (`om-amazon-negative-targeting`, waste trigger 3 — a term that *converts* but runs far over target) is **proposed here, not applied.** That trigger is newer than the other two and negation is permanent; a wrong negation leaves silence, which nobody notices, while a wrong tolerance leaves spend, which shows up in every report.
- **Budget reallocation between campaigns** within the property's total: up to **15 %** of the total (the total itself is unchanged).
- **Pausing individual poor keywords/targets** is allowed.

### Extended (Amazon)
- **Bid changes**: ceiling **±35 %** per item per run (the engine's maturity step still applies within it).
- Keyword/target/negative adjustments as in Standard, **including the target-miss trigger**, which applies directly at this level instead of only proposing. Promoting a property to Extended therefore also switches that trigger live — worth knowing when you promote one.
- **Budget reallocation between campaigns** up to **30 %** of the total.
- **Adjusting the target-ACOS bands** (the Research vs. Profit bands) within **±15 %** of the value set in `strategy.md` — the analogue of the Google smart-bidding target change. The durable band in `strategy.md` stays human-owned: a lasting change is proposed up, not silently rewritten.

**Amazon — always escalate (in addition to the cross-channel list below):** pausing or enabling a whole campaign; raising the property's total monthly budget; changing the head-term ownership map; activating a newly created (PAUSED) campaign; a bid that would breach the **€0.07 floor or the €5.00 hard max-CPC** (knob 5) — to the human via the Account Manager; any change beyond the active level's bands. **Once a human has decided, the answer returns to the object's owner for execution — see *The return path* below.**

> **A permitted lever is not automatically an available lever.** The autonomy level says what an
> agent *may* do; whether a tool exists for it in that agent's runtime is set separately per agent
> (`enabled_tools`). On Amazon, several levers this skill permits have historically had **no
> callable tool** — notably budget reallocation and pausing individual targets, and until
> 2026-08-05 also bid changes. **Current availability is documented in
> `om-amazon-ads-reference/references/mcp-write-tools.md`.**
> If a lever is permitted but not callable: **escalate naming the exact tool id, and never
> substitute another tool for it.** Do not treat the missing tool as a reason to act outside the
> band, and do not treat the permission as proof the tool is there.

## The return path — who executes a decision that came back

Escalation is not a one-way street. Every escalation a human decides must come back down to
**the agent that owns the object**, and performing that routing is part of resolving the issue —
not an optional courtesy. Without it an approved change circles between tiers and nothing
happens.

- **Ownership follows the object, not the rank.** A bid belongs to the property Optimizer. A
  keyword, target or negative belongs to the Targeter that owns that lane. Campaign creation
  belongs to the Account Manager. **Nobody above the property tier writes to an ad account** —
  not the Account Manager for bids, not the department head, not the CEO agent. A tier that
  cannot hold the property's context (`strategy.md`, `learnings.md`, its own `decision-log.md`)
  must not write to it: an undocumented change reads as drift on the next daily run.
- **Route down before routing sideways or up.** Before handing an execution request to a peer or
  upward, look up the agent that holds the tool in
  `om-amazon-ads-reference/references/mcp-write-tools.md` and hand the issue to that agent. An
  execution request that travels past an agent who could have executed it is a routing defect,
  not diligence.
- **A human-authorized, bounded change is not an autonomous action.** When a human has approved a
  specific, enumerated change — named campaign, named items, named before/after values — the
  executing agent does **not** re-test it against its autonomy band. The band governs what an
  agent decides on its own; it does not gate what a human already decided. The executor's job
  narrows to three things: write exactly the enumerated scope, read it back, and log it with the
  authorization named. Anything beyond the enumerated scope is out of scope and escalates as
  usual. The hard bounds still hold without exception — the €0.07 floor, the €5.00 max-CPC, and
  everything under *Always escalate*.
- **When nobody can execute, stop on the first pass.** If no agent holds a callable tool for the
  lever, that is a **terminal state**, not something to discover by handing the issue around.
  Open a confirmation request to the human immediately, naming the exact tool id that is missing
  and the exact change still outstanding. Some levers are terminal by construction and are never
  routed to another agent: raising the property's total monthly budget, pausing or enabling a
  whole campaign, activating a PAUSED campaign, and any campaign-budget write
  (`update_campaign_budget` is callable by no agent, by design).
- **Never leave an issue `blocked` without a linked blocker.** `blocked` is human-reserved, and a
  bare `blocked` is a dead end that trips supervisor auto-recovery. Escalate or hand off instead.

## Always escalate (every level)
Regardless of level, escalate these to the department head:
- Raising the property's total monthly budget (`budget.csv`).
- Pausing a top-performer campaign.
- A campaign with no impressions for three days or more.
- Enabling AI Max, or changing any `asset_automation_settings` entry. It widens matching, ad text and landing pages in one step and is not a reversible bid tweak — no level covers it.
- Any change that would exceed the active level's ceilings.
- Any action whose justification is unclear — when in doubt, do nothing and escalate.

(Operational failures — a missing Drive document or failed ad-platform access — are
also escalations, handled in the agent's `HEARTBEAT.md`.)

## Maintenance
This skill is the single source of truth for Online Marketing autonomy levels.
`client.md` selects a level; it never redefines one. If the levels change, update them
here once. Other departments define their own autonomy levels in their own skill when
the need is real — do not generalize this one prematurely.
