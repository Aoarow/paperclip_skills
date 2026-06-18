---
name: om-amazon-review
description: Weekly outcome review of a single Amazon property by the Reviewer agent — read the decision-logs of ALL the property's worker agents (Optimizer, positive Targeter, negative Targeter), measure the ~14-day impact of their decisions against the property's goals using fresh data from Supabase, and distil what worked and what didn't into learnings.md (the file all four agents read at the start of every run). Use whenever the Reviewer agent runs its weekly cycle. The Reviewer does not change the ad account — it writes learnings; account changes belong to the worker agents within their autonomy. DRAFT: the procedure is complete; some scoring/impact thresholds are deliberately light until the bidding/negative rulesets exist.
---

# Amazon Advertising — Weekly Review

This skill teaches the **Reviewer** agent how to turn a week of the property's decisions into durable lessons. It is the property's learning loop: the four worker agents act and log; the Reviewer judges the outcomes and writes `learnings.md`; all four read `learnings.md` at the start of their next run — otherwise the log is a write-only diary that never changes behaviour (memo §6).

**Who runs this:** the property's **Reviewer** agent, weekly. One Reviewer per property.

**The Reviewer proposes lessons, it does not mutate the account.** It writes only `learnings.md`. Anything that needs an account change is a recommendation in `learnings.md`; anything systemic/urgent is **escalated** (reassign the run issue up + `todo`, per `lx-paperclip-inbox-cycle`), never executed here.

## Scope — what is reviewed
The Reviewer reads the **single per-property `decision-log.md`**, which all worker agents append to (Optimizer daily, positive Targeter monthly, negative Targeter weekly). Each entry is tagged with its agent and lever (format defined in `om-amazon-optimization` → *Decision-log contract*). The Reviewer therefore sees **all four agents' actions in one timeline** — and, crucially, their **interactions** (e.g. the Optimizer cut a bid the same week the positive Targeter graduated that term; a negative the negative Targeter added that orphaned a term the positive Targeter wanted).

## Inputs
| Source | Read for | Rights |
| :--- | :--- | :--- |
| `decision-log.md` | every worker decision in the review window (~last 14 days), with baselines | READ |
| `strategy.md` | the goals to judge against (ACOS target, head-term map, distribution) | READ |
| `client.md` | account/property context | READ (human-owned) |
| Supabase (`amazon_ads_raw` / views) | the **outcome** data to measure each decision's effect | READ |
| `learnings.md` | its own prior lessons (don't repeat; track whether past lessons held) | READ + WRITE |

## The review method
For each decision in the window that has cleared its **settling period** (a decision still settling cannot yet be judged — note it as "pending, re-check next week"):
1. **Recover the baseline** from the decision-log entry (every entry carries pre-change values — that is the writer↔reader contract).
2. **Measure the outcome** from Supabase: the same metric, after the change, over a comparable window (respect the ~1-day data lag / freshness rule, `report-types.md`).
3. **Judge** helped / hurt / neutral against the `strategy.md` target and the decision's stated hypothesis. Use the same recency-weighted, significance-floored thinking as the optimizer's scoring (don't draw conclusions from a near-empty sample). *(DRAFT: exact impact thresholds stay light until the bidding/negative rulesets are set; favour "insufficient data → re-check" over a false verdict.)*
4. **Look for cross-agent interactions** in the same window — conflicts, double-moves, or orphaned negatives — and call them out; these are the lessons a per-agent view would miss.
5. **Extract a lesson** only when the evidence supports one. "No clear signal yet" is a valid, honest result.

## Output — the learnings.md contract
`learnings.md` is what changes the workers' behaviour. Keep it **actionable and short** — the four agents read it every run. Append with `gdrive_append_file` (`position: "start"`); never overwrite the history (same discipline as the decision-log, see `om-amazon-optimization`). Re-read after writing to confirm new + old entries survive.

```
## [YYYY-MM-DD] — Weekly review (window: <from>–<to>)
- Reviewed: <#decisions by agent — Optimizer/PosTgt/NegTgt>
- What worked: <decision → measured outcome → lesson>
- What didn't: <decision → measured outcome → lesson>
- Cross-agent: <any conflict/interaction observed, or "none">
- Recommendations (for the workers / human): <concrete, e.g. "GEN bids on ASIN X overshoot — tighten band"; or "—">
- Still settling (re-check next week): <decisions not yet judgeable>
- Escalated: <issue ref, if any systemic problem was handed up>
```

## Run sequence
1. Inbox cycle first (`lx-paperclip-inbox-cycle`); a comment/task wake is handled, not the weekly mandate.
2. On the scheduled weekly tick: idempotency check (a review dated this week already in `learnings.md`? → close).
3. Open the dated review run issue; check out.
4. Read `decision-log.md` (window), `strategy.md`, prior `learnings.md`; pull outcome data from Supabase.
5. Apply the review method per decision; synthesise cross-agent interactions.
6. Write one dated `learnings.md` entry (append at start). Escalate any systemic finding (broken tracking, strategy mismatch, repeated harmful pattern) up the chain.
7. Close the run issue `done` (a quiet week is still a completed review — write the entry, note "no strong signal").

## What this skill does NOT do
- **Change bids/keywords/negatives/budget** — those are the workers' jobs within `om-autonomy-levels`. The Reviewer only writes `learnings.md` and escalates.
- **Change `strategy.md` / `budget.csv` / the head-term map** — human-owned; recommend, don't edit.

## References
- `om-amazon-optimization` — the **decision-log entry format** (the contract this skill reads). Keep them in step.
- `om-amazon-advertising-manifest` — the doctrine the decisions are judged against (R/P intent, negation, head-term).
- `om-amazon-ads-reference` — `supabase-schema.md`, `report-types.md` (the outcome data + freshness rule).
- `lx-paperclip-inbox-cycle` — run/close/escalation mechanics.

## Maintenance
This skill owns the *review procedure and the learnings.md contract*. The decision-log format is owned by `om-amazon-optimization`; goals live in `strategy.md`; doctrine in the manifest. When the decision-log format changes, update this skill in the same change — it depends on it.
