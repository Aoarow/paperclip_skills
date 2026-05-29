# Google Ads Skills — Foundations & Allocation

*Decision record + working notes for the Online Marketing Google Ads skill set.*
*Captures (1) where each piece of Google Ads knowledge lives, and (2) the optimizer's
evaluation logic, to seed the `om-google-optimization` skill. Per "Drive is the truth",
this record should land in Drive once confirmed.*

---

## 1. The three homes for knowledge

The dividing line, as one test:

> **Does it change when *Google* changes → reference skill. Does it change when *we
> learn* → Drive. Is it a rule the agent must obey → skill. Is it knowledge that
> informs the agent's judgment → Drive.**

| Home | Holds | Maintained by | Changes |
| :--- | :--- | :--- | :--- |
| **`om-google-ads-reference`** (shared skill) | Stable API spec & contract: field types, char limits, asset specs, listing-group trees, bidding-strategy compatibility, GAQL verification queries, error remediation. Binding rules. | Humans / devs (skill bundle) | Rarely (when the API changes) |
| **Drive `KI-Wissen/Google`** (existing folder) | Evolving best practice & experience: new features/betas, platform changes, what's working per vertical, seasonal patterns, accumulated cross-property learnings. Judgment-informing knowledge. | Research agents + humans · `WRITE: Research · READ: all` | Continuously |
| **Consuming skills** — `om-google-campaign-creation` (Peggy) and `om-google-optimization` (optimizers) | Their own *procedures* and operating discipline. Each references the two above. | Humans / devs | Per procedure |

Decisive reason the evolving knowledge must live in Drive, not a skill: **Research agents
can write to Drive but not to skills.** Anything meant to be kept current by Research
agents has to live where they can reach it.

---

## 2. Reference reorganization (action)

**Create a new shared skill `om-google-ads-reference`** and move these files into it,
out of `om-google-campaign-creation/references/`:

- `bidding-strategies.md`
- `search-rsa-spec.md`
- `pmax-asset-types.md`
- `demand-gen-formats.md`
- `shopping-listing-groups.md`
- `gaql-verification-queries.md`
- `common-errors.md`

All seven are Google Ads spec/contract — equally relevant to creation and to optimization
(the optimizer needs the verification queries, error remediation, bidding-strategy fields,
and the RSA/asset specs just as much as Peggy does). Their old location wrongly implied
they were creation-specific.

**Required in the same change** (Peggy runs productively):
- Update `om-google-campaign-creation/SKILL.md` → its *References* section now points to
  `om-google-ads-reference/<file>` instead of `references/<file>`.
- **No file content changes** — only the home and the pointers.

Proposed entry file for the new skill:

```md
---
name: om-google-ads-reference
description: Stable Google Ads API reference and specification for all Online Marketing
  agents — field types, character limits, asset specs, listing-group construction,
  bidding-strategy compatibility, GAQL verification queries, and error remediation. The
  shared spec/contract layer used by both campaign creation (Peggy) and the optimizer
  agents. Use whenever an agent needs the exact, binding API contract for building or
  verifying a Google Ads structure. Evolving best practice and experience live in Drive
  KI-Wissen/Google, not here.
---

# Google Ads — Shared Reference

The binding spec layer for every Google Ads agent. Load only the file you need
(progressive disclosure); do not read all up front.

- `bidding-strategies.md` — strategy fields, compatibility matrix, conversion thresholds, migration path.
- `search-rsa-spec.md` — RSA field reference, customizers, pinning.
- `pmax-asset-types.md` — Performance Max asset/field matrix, bulk-mutate rule.
- `demand-gen-formats.md` — Demand Gen ad-format specs, asset automation.
- `shopping-listing-groups.md` — product partition tree construction.
- `gaql-verification-queries.md` — canonical post-mutation verification queries.
- `common-errors.md` — error-code lookup and remediation.

## Maintenance
This is the contract layer — it changes when the Google Ads API changes. Evolving
best practice belongs in Drive `KI-Wissen/Google`, never here.
```

---

## 3. Drive `KI-Wissen/Google` — what goes here

The living, Research-maintained side. Examples: new Google features and betas, platform
announcements, "what's currently working" per vertical, seasonal patterns, accumulated
cross-property experience. The folder already exists in the Drive map
(`…/09_Onlinemarketing/KI-Wissen/Google`, `WRITE: Research · READ: all`) — **no new
structure needed.** Both Peggy and the optimizers read it for current best practice.

---

## 4. Optimizer evaluation logic — draft notes for `om-google-optimization`

These are *procedure/discipline* → they live in the optimizer skill itself (not in the
shared reference, not in Drive). The numbers below are **defaults**, controlled because
they steer agent behaviour.

### 4.1 Weighted multi-window performance score

- **Disjoint buckets**, not nested windows — so the most recent day isn't counted three
  times: `day 0–1`, `day 2–7`, `day 8–30`.
- **Default weights** (examples, tunable): `0–1d = 10 %`, `2–7d = 50 %`, `8–30d = 40 %`.
  With disjoint buckets this yields a clean falling per-day recency weighting.
- **Blend rate metrics** (CPA, ROAS, CTR, conversion rate) — never absolute volumes, or
  the 30-day bucket dwarfs the rest.
- **Significance floor per bucket:** a bucket counts only if it meets a minimum volume;
  otherwise its weight is **redistributed (renormalized)** over the qualifying buckets —
  never fed in as noise (critical for the near-empty 24 h bucket).

```
score = Σ (wᵢ × rateᵢ)   over buckets i that pass the significance floor
        (weights wᵢ renormalized over the passing buckets)
```

- **The score is diagnosis only** — compared against the targets in `strategy.md`. It says
  *whether* something is off.
- **Response magnitude is governed solely by `om-autonomy-levels`** (±20 % / ±35 % etc.).
  Diagnosis and action size stay separate.
- **Tolerance band:** act only beyond a minimum deviation from target — no reacting to
  ±2 % noise.

### 4.2 Settling / grace period

- **New campaigns:** hands-off until the learning phase is genuinely complete — i.e.
  **time AND minimum volume**, not the calendar alone. Default ≈ **7 days**, matching the
  smart-bidding learning phase (`bidding-strategies.md`).
- **Generalizes to: after *any* material change** (incl. the agent's own — strategy
  switch, large budget/target change), let it settle before touching the same lever
  again. The agent reads its own `decision-log.md` to know when it last acted. **This is
  the anti-thrash rule.**
- **Grace = "don't tune", not "don't look":** hard failures (e.g. no impressions ≥ 3 days,
  already an escalation in `om-autonomy-levels`) are still observed and escalated during
  the grace period.

### 4.3 Parameter note

Weights, bucket boundaries, grace length, significance floors, tolerance band → **skill
defaults**, controlled and deliberate, not casually editable. Revisit with experience;
externalize the numbers only if retuning becomes frequent (avoid premature structure).

### 4.4 Budget model & pacing

- `budget.csv` is the **total monthly** ceiling (client-approved, human-owned,
  read-only). **Never exceeded** — the "budget is sacred" rule in concrete form.
- `strategy.md` holds the **intended split** across campaigns (human / Roger / Peggy
  owned). The optimizer **reads** it; it cannot write it.
- The optimizer may make **bounded tactical reallocations** between campaigns within the
  monthly ceiling (per `om-autonomy-levels` %), logged in `decision-log.md` as deviations
  from the `strategy.md` plan. A reallocation that proves durable is **escalated to Peggy**
  to be written into `strategy.md` — that keeps Drive the truth for allocation.
- **Pacing:** the ceiling is monthly but Google Ads budgets are daily, so the optimizer
  reasons against **month-to-date spend vs. the monthly total**, not the daily number
  alone. It paces so the sum of daily budgets cannot overshoot the monthly ceiling.

---

## 5. Decisions & open points (carried forward)

**Resolved**

- **Budget model.** `budget.csv` = the client-approved **total monthly** budget (the
  sacred ceiling, human-owned, read-only). The split across campaigns is Lexacore's
  decision, documented in `strategy.md` (human / Roger / Peggy owned). See §4.4 for what
  the optimizer may do within this.
- **Verification source.** Post-change verification runs against **Google Ads via MCP**,
  not BigQuery — BigQuery exports lag ~1 day and won't reflect a just-made change. The
  same lag means the optimizer never reacts to "today".

**Open**

- **Standard-level + smart bidding gap.** Under `om-autonomy-levels`, target (tCPA/tROAS)
  adjustment is only allowed at *Extended*, while *Standard* speaks of "bid changes
  ±20 %" — but smart-bidding campaigns have no manual bids. So a Standard property on
  smart bidding can't touch its most important lever. Intended (conservative) or an
  oversight to fix?
- **`om-autonomy-levels` budget wording.** The skill measures budget moves against "the
  daily budget" and lists "raising the property's total *daily* budget" as an escalation —
  but the ceiling is now defined as monthly (`budget.csv`). Reconcile the unit:
  reallocation % against the property's total budget, and the escalation trigger →
  total **monthly** budget.
