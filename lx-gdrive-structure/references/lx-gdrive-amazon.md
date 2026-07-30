---
name: lx-gdrive-amazon
description: Maps the Amazon-specific Drive files and data homes for an Online Marketing property. Read with lx-gdrive-structure and lx-gdrive-onlinemarketing whenever an agent locates or uses Amazon strategy, budget, product-master, data-source, decision, learning, or reporting artifacts.
---

# Online Marketing — Amazon Drive map

This reference extends `lx-gdrive-onlinemarketing`. Resolve the customer root by
Twenty's `driveFolderId`, then discover and bind its children by stable IDs.

## Two data homes

- **Drive = decided truth:** `client.md`, strategy, budget, technical bindings,
  decision history, learnings, reports, and the human product Sheet.
- **Supabase = measured/operational truth:** product rows, advertising performance, and
  sales data, scoped to the property. Agents read operational product facts and
  performance from Supabase, not from the Drive Sheet. ASIN is the join key.

## Canonical Amazon property paths

```text
<customer root by driveFolderId>/
├── client.md
├── 02_Projektdurchführung/
│   └── 02_Amazon/
│       └── <property>/
│           ├── <property> Produkte   Google Sheet · WRITE: Human · READ: Human/n8n
│           ├── strategy.md           WRITE: Human · READ: all
│           ├── budget.csv            WRITE: Human · READ: all
│           ├── data-sources.md        WRITE: Peggy, Roger, Human · READ: all
│           ├── decision-log.md        WRITE: property agents · READ: all
│           └── learnings.md           WRITE: Reviewer · READ: all
├── 03_Reporting/
│   └── 02_Amazon/
│       └── <property>/
│           └── <YYYY-MM>.md           WRITE: Peggy / Account Manager · READ: all
└── 04_Kundeneingang/                  customer-provided raw exports
```

Do not create per-property briefing, input, or archive trees.

## `client.md` routing

`client.md` is the human-owned, read-only account register. It holds:

- the three-letter client code;
- Amazon account references;
- Ads profile/account identifiers;
- marketplace and Seller/Vendor channel;
- the mapping from each exact property name to one account reference;
- the autonomy level per property.

No separate `_konten` file exists. Credentials stay in the secret store. Never infer
account routing from a property name.

## Product Sheet

There is one human-owned Google Sheet per property: `<property> Produkte`.

The canonical columns are defined once in
`om-onboarding-new-projects/references/amazon.md`. They cover product/account master
facts, price, status, priority, and source metadata. They deliberately do not include
`stock_status`: live per-SKU buyability is checked through Amazon, not maintained in the
Sheet. n8n syncs the Sheet to Supabase. Agents read the synced table and never edit the
Sheet. Onboarding may create the empty canonical Sheet shell; only a human populates
facts.

## Per-file notes

- `strategy.md` — human-approved goals and guardrails, ACOS/TACOS targets, Buy Box and
  inventory constraints, seasonality, distribution logic, and head-term ownership.
- `budget.csv` — human-approved monthly ceiling; read-only and sacred.
- `data-sources.md` — stable file/folder IDs, Supabase scope, ingestion workflow,
  freshness checks, and raw-export bindings. It points to account routing in
  `client.md` rather than repeating it.
- `decision-log.md` — shared append history for Amazon property agents.
- `learnings.md` — durable lessons written by the Reviewer.
- `03_Reporting/02_Amazon/<property>/` — property reporting output.
- `04_Kundeneingang/` — customer-provided advertising and sales exports before
  ingestion; no second reporting taxonomy.

## Read/write rule

The annotations are binding. Onboarding creates only the technical shells permitted by
`om-onboarding-new-projects`; it does not author human business values. Append to
accumulating files without destroying prior history, following `lx-gdrive-structure`.

## Maintenance

This file owns Amazon Drive locations and rights. The onboarding sequence lives in
`om-onboarding-new-projects/references/amazon.md`; data/API contracts live in
`om-amazon-ads-reference`; doctrine lives in `om-amazon-advertising-manifest`.
