---
name: lx-gdrive-onlinemarketing
description: Maps and explains the Lexacore Google Drive structure for Client Marketing (Online Marketing), including the customer lifecycle folders, property paths, stable-ID navigation, and read/write ownership. Read this before working with a Google Ads, Amazon, or Meta customer's Drive area.
---

# Department: Online Marketing — Peggy and team

## Fixed infrastructure folders

Address these by Folder-ID:

| Path | Folder-ID |
| :--- | :--- |
| `01_Kunden & Projekte` | `1hvrDAJ8JqrtNWupio5I9el4eGE714wFg` |
| `02_Agentur intern` | `1o2VNGERtm2iN3YYiH7RCx0IdhHvL8494` |
| `02_Agentur intern/09_Onlinemarketing` | `1-zJyBCzG5hi6YhoqYG5NvdzYUG_rbSJx` |
| `02_Agentur intern/09_Onlinemarketing/KI-Wissen` | `162NZ-kuhXiSyQ-bfEq5OsO_-vAyazCOz` |
| `KI-Wissen/Google` | `1HucQTBQKW4tZGkenVqJyDTseLJFpM-dQ` |
| `KI-Wissen/Amazon` | `1cKaVTuoNgVGujXPY8FK2I8z5IiKdieEX` |
| `KI-Wissen/Meta` | `14RKRyP337oyceZljS_OkuHOlfaYLP0Ak` |
| `Onboarding-Queue` | `10zw2H4WJTU5on9fH4qarjxh6GGjK6OIR` |

Customer folders live flat under `01_Kunden & Projekte`. Do not navigate to a customer
by name from this root. Resolve it from Twenty's `driveFolderId`.

## Knowledge base

```text
02_Agentur intern/09_Onlinemarketing/KI-Wissen/<Channel>/
```

Channels: `Google`, `Amazon`, `Meta`.

**WRITE:** Research agents. **READ:** all agents.

## Customer lifecycle

The root display name follows `<status>_<CLIENT>_<company>`, but automation never reads
identity or status from that name:

- `00_` — Prospect;
- `01_` — Customer;
- `02_` — Former Customer / archive preparation.

Twenty's stable `driveFolderId` survives renames and moves and is the binding anchor.

### Prospect scaffold

n8n creates:

```text
00_<CLIENT>_<company>/
├── client.md
├── 00_Geschäftsverkehr/
│   ├── 00_Angebote/
│   ├── 01_Verträge/
│   ├── 02_NDAs/
│   └── 03_Beauftragungen & Nachträge/
└── 05_Recherche & Wissen/
```

### Customer V2 scaffold

When Twenty changes the company to Customer, n8n renames the same anchored folder and
adds:

```text
01_<CLIENT>_<company>/
├── client.md
├── 00_Geschäftsverkehr/
│   ├── 00_Angebote/
│   ├── 01_Verträge/
│   ├── 02_NDAs/
│   └── 03_Beauftragungen & Nachträge/
├── 01_Kommunikation/
│   ├── 00_Briefing & Ziele/
│   ├── 01_Protokolle/
│   └── 02_Planung & Freigaben/
├── 02_Projektdurchführung/
├── 03_Reporting/
│   └── 00_Kundenreport/
├── 04_Kundeneingang/
├── 05_Recherche & Wissen/
└── 99_Archiv/
```

Channels and properties remain absent until a human declares them in `client.md`.
Communication, briefings, approvals, research, customer input, and archive stay at
customer level.

## Property schema

Peggy provisions only commissioned properties through
`om-onboarding-new-projects`:

```text
02_Projektdurchführung/
└── <Channel>/
    └── <property>/
        ├── strategy.md       WRITE: Human · READ: all
        ├── budget.csv        WRITE: Human · READ: all
        ├── data-sources.md   WRITE: Peggy, Roger, Human · READ: all
        ├── decision-log.md   WRITE: property agents · READ: all
        └── learnings.md      WRITE: Reviewer · READ: all

03_Reporting/
└── <Channel>/
    └── <property>/
        └── <YYYY-MM>.md      WRITE: Peggy / channel Account Manager · READ: all
```

| Channel | Canonical folder | Detail map |
| :--- | :--- | :--- |
| Google Ads | `01_Google Ads` | `om-onboarding-new-projects/references/google.md` |
| Amazon | `02_Amazon` | `lx-gdrive-amazon.md` and `om-onboarding-new-projects/references/amazon.md` |
| Meta | `03_Meta` | Reserved; do not provision until its onboarding reference exists |

The property name is copied exactly from human-owned `client.md`; it is never generated
from a company, website, brand, account, or marketplace.

## Ownership

- `client.md` is the human-owned control file for client code, channels, properties,
  autonomy, and account routing. Agents read it first and never write it.
- `strategy.md` and every budget value are human-owned. Onboarding may create their
  canonical empty shells but may not invent or copy business values.
- `data-sources.md` holds confirmed non-secret technical bindings and stable IDs; it
  does not duplicate strategy, budget, or account routing.
- `decision-log.md` and `learnings.md` accumulate operational history under their
  documented writers.

For append-only history, use the shared read-modify-write helper procedure from the
root Drive skill and verify that prior content survives.

## Maintenance

This file owns the Online Marketing Drive topology and rights. The customer lifecycle
automations own the customer-level scaffold. `om-onboarding-new-projects` owns the
property setup procedure. Update all affected sources in the same change when the
structure changes.
