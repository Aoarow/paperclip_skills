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
property's total budget, enabling/pausing/deleting structures that are human decisions,
or acting without a documented reason.

## Levels

### Observe
The starting level for a new or unproven property. No live changes.
- Allowed: analyze performance, document findings, propose changes as tasks to the
  department head.
- Everything that would mutate the account escalates.

### Standard
The everyday level once a property runs reliably.
- Bid changes up to **±20 %** per campaign.
- Keyword adjustments (negative keywords, new long-tail keywords).
- Asset adjustments (new ad variations within the documented strategy).
- Budget reallocation between campaigns up to **15 %** of the daily budget.

### Extended
For proven properties with a solid track record.
- Bid changes up to **±35 %** per campaign.
- Keyword and asset adjustments as in Standard.
- Budget reallocation between campaigns up to **30 %** of the daily budget.
- Adjusting smart-bidding targets (tCPA / tROAS) within **±15 %** of the current target.

## Always escalate (every level)
Regardless of level, escalate these to the department head:
- Raising the property's total daily budget.
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
