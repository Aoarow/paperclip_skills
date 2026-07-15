---
name: lx-gdrive-amazon
description: Maps and explains the Google Drive folders and files for the Amazon channel of the Client Marketing (Online Marketing) department. Read together with lx-gdrive-structure and lx-gdrive-onlinemarketing. Use this whenever an agent needs to locate, read, or write an Amazon property's documents (strategy, budget, data-sources, learnings, decision-log) or the product Sheet, or to understand the Amazon folder structure.
---

# Online Marketing — Amazon Channel Map

The channel-level map for **Amazon**, beneath the Online Marketing department (Head: Peggy). It extends `lx-gdrive-onlinemarketing` with the Amazon-specific folder/file schema and read/write rules. **Do not duplicate** the shared fixed Folder-IDs (client root, KI-Wissen, onboarding) — they live once in `lx-gdrive-onlinemarketing` (§1). Navigate the per-client folders **by name** from the client-root Folder-ID; the IDs below the client level differ per client and are never hard-coded.

## The two data homes (recap — see `om-amazon-ads-reference`)
- **Drive = the *decided* truth:** the files below (strategy, budget, data-sources, learnings, decision-log) + the product **Sheet**.
- **Supabase = the *measured* truth:** ad performance + (later) sales, keyed by ASIN. **Agents read product facts and performance from Supabase, not from Drive** — the product Sheet is human-maintained and synced to Supabase by n8n. The two join on **ASIN**.

## Client folder schema (navigate by name from the client root)

```
01_Kunden & Projekte/
└── 01_Kunden/                                    [client-root Folder-ID: see lx-gdrive-onlinemarketing §1]
    └── [client]/                                  e.g. Windspiel
        ├── client.md                              WRITE: Human · READ: all
        │     Master data + autonomy_level. Holds the Amazon account block(s):
        │     CLIENT code (3 chars, per client), Ads profile ID, account ID, marketplace,
        │     sales channel (seller/vendor), and which property maps to which account.
        │     (No separate _konten/ file — account routing lives here. No secrets.)
        │
        ├── 02_Projektdurchführung & Assets/
        │   └── 00_Amazon/                          ← channel folder (fixed name, every client)
        │       └── [property]/                     property ID = [brand]-[seller|vendor]-[marketplace]
        │           │                                 e.g. windspiel-seller-de
        │           ├── [property] Produkte         Google Sheet · WRITE: Human · READ: humans
        │           │     The product master (one Sheet per property). Hard facts +
        │           │     priority (1/2/3) + category + source. Agents do NOT read it —
        │           │     n8n syncs it to Supabase public.products; agents read Supabase.
        │           ├── strategy.md                  WRITE: Human, Peggy · READ: all
        │           ├── budget.csv                   WRITE: Human · READ: all
        │           ├── data-sources.md              WRITE: Human, Peggy · READ: all
        │           ├── learnings.md                 WRITE: Reviewer agent · READ: all
        │           └── decision-log.md              WRITE: property agents (Optimizer, +Targeter, −Targeter) · READ: all
        │
        └── 04_Reporting & Analysen/                    ← human raw exports + agent report output
            ├── 01_Absätze/                              sales CSV exports (Seller/Vendor, monthly) = TACOS source · WRITE: Human · READ: all
            ├── 02_Werbung/01_Amazon/                    ad CSV exports (bootstrap, pre-Airbyte) · WRITE: Human · READ: all
            │   └── [property]/[YYYY-MM].md              monthly roll-up report output · WRITE: Peggy / Account-Manager · READ: all
            └── 00_Dashboards/                           HTML performance dashboards · WRITE: Peggy · READ: all
                  Reporting taxonomy decided 2026-06-22: the existing Drive structure is the
                  truth (no separate `02_Amazon` / `99_Monatsreport`). Sales + ad raw exports
                  are human-maintained inputs; the agent monthly report is the `.md` output
                  under `02_Werbung/01_Amazon/[property]/`.
```

## Knowledge base
```
02_Agentur intern/09_Onlinemarketing/KI-Wissen/Amazon/   [Folder-ID: see lx-gdrive-onlinemarketing §1]
```
**WRITE:** Research agents · **READ:** all agents. Evolving Amazon best practice (not the binding API contract — that is `om-amazon-ads-reference`).

## Per-file notes
- **client.md** — human-owned; the single home for Amazon account routing (memo §4, consolidated 2026-06-15). Read first by all agents.
- **product Sheet** — one per property; the human product master, extensible for SP-API logistics fields later. The n8n sync also auto-creates an FBA twin row per product in Supabase (see `examples/windspiel/products-catalog.md`). Agents never read or write the Sheet.
- **strategy.md** — goals/guardrails, head-term ownership map, seasonality, distribution, constraints. The per-product priority is **not** here (it is the Sheet's `priority` column; ruleset in `om-amazon-advertising-manifest` §8).
- **budget.csv** — monthly rows per property (`monat, budget_eur, notiz`); human-owned, sacred.
- **data-sources.md** — the property's data wiring (Supabase tables/connection, ingestion workflow, CSV exports); points to the account in client.md rather than repeating its IDs.
- **decision-log.md** — one per property, appended to by all three worker agents (shared envelope in `om-amazon-optimization`); read by the Reviewer.
- **learnings.md** — written by the Reviewer (`om-amazon-review`), read by all four property agents at the start of each run.

## Read/write rule
The WRITE/READ annotations above are binding. Never write to a document you only have read access to. `client.md` and `budget.csv` are human-owned — agents read them, never change them. **Adding to an accumulating file** (`decision-log.md`, `learnings.md`): use `gdrive_append_file` (`position: "start"` to prepend), never `gdrive_write_file` with only your fragment (it overwrites the whole file). See `lx-gdrive-onlinemarketing` §4 for the full rule.

## Maintenance
This map is the truth about the Amazon Drive structure. If it changes, update this skill in the same change — human or agent. Shared fixed Folder-IDs stay in `lx-gdrive-onlinemarketing`; the API/data contract stays in `om-amazon-ads-reference`; doctrine in `om-amazon-advertising-manifest`.
