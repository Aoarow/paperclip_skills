---
name: lx-gdrive-onlinemarketing
description: Maps and explains the folders and files inside the Lexacore Google Drive for the Client Marketing (Online Marketing) department (Head of Department: Peggy). All agents working with Google Ads, Amazon, or Meta use this as the reference for where folders and files live and how to work with them.
---

# Department: Online Marketing (Client Marketing) – Peggy and Team

## 1. Fixed infrastructure folders (address by Folder-ID)

These folders exist exactly once and never move. Always address them by Folder-ID, never by path navigation.

| Path                                              | Folder-ID                          |
| :------------------------------------------------ | :--------------------------------- |
| 02_Agentur intern                                 | 1o2VNGERtm2iN3YYiH7RCx0IdhHvL8494  |
| 02_Agentur intern/09_Onlinemarketing              | 1-zJyBCzG5hi6YhoqYG5NvdzYUG_rbSJx  |
| 02_Agentur intern/09_Onlinemarketing/KI-Wissen    | 162NZ-kuhXiSyQ-bfEq5OsO_-vAyazCOz  |
| KI-Wissen/Google                                  | 1HucQTBQKW4tZGkenVqJyDTseLJFpM-dQ  |
| KI-Wissen/Amazon                                  | 1cKaVTuoNgVGujXPY8FK2I8z5IiKdieEX  |
| KI-Wissen/Meta                                    | 14RKRyP337oyceZljS_OkuHOlfaYLP0Ak  |
| Onboarding-Queue                                  | 10zw2H4WJTU5on9fH4qarjxh6GGjK6OIR  |
| 01_Kunden & Projekte/01_Kunden (**client root**)  | 1LWUKYiwSSzrqiqzFVKeNRoPEBKOxLH7l  |

## 2. Knowledge base (maintained by Research agents)

```
02_Agentur intern/09_Onlinemarketing/KI-Wissen/[Channel]/
```

Channels: `Google`, `Amazon`, `Meta`.
**WRITE:** Research agents · **READ:** all agents

## 3. Client folder schema (navigate by name from client root)

Every client follows this exact structure. The **top-level folders (00–05) are identical for every client** (verified across all live clients). Start from the client-root Folder-ID (section 1) and navigate **by name** – the Folder-IDs below the client level differ per client and must not be hard-coded.

```
01_Kunden & Projekte/
└── 01_Kunden/                                       [Folder-ID: see section 1 — client root]
    └── [client-name]/
        ├── client.md                                WRITE: Human only · READ: all
        │       Master data: autonomy level, channels, properties, project info.
        │       Critical document, created at project start. CHANGED BY HUMAN ONLY.
        │       (An agent may draft the initial ENTWURF at onboarding; the human owns the FREIGEGEBEN version — see §4.)
        │
        ├── 00_Vertragsunterlagen & Stammdaten/      WRITE: Human · READ: all
        │       (00_Angebot, 01_Vertrag, 02_NDAs)
        ├── 01_Management & Kommunikation/           WRITE: Human · READ: all
        │       (00_Protokolle, 01_Korrespondenz, 02_Projektplanung)
        ├── 02_Projektdurchführung & Assets/
        │   └── [Channel]/                            e.g. 01_Google Ads
        │       └── [property]/
        │           ├── strategy.md                   WRITE: Human, Roger, Peggy · READ: all
        │           ├── budget.csv                    WRITE: Human · READ: all   (onboarding exception — see §4)
        │           ├── learnings.md                  WRITE: Reviewer agents · READ: all
        │           ├── data-sources.md               WRITE: Human, Roger, Peggy · READ: all
        │           ├── webseiten-analyse-google.md   WRITE: Peggy · READ: all   (Google only)
        │           └── decision-log.md               WRITE: Optimizer agents · READ: all
        │
        ├── 03_Input Kunde/                           WRITE: Human · READ: all   (customer-provided material)
        ├── 04_Reporting & Analysen/
        │   └── [Channel]/
        │       └── [property]/
        │           └── [YYYY-MM].md                  WRITE: Peggy · READ: all   (property detail reports)
        └── 05_Archiv/                                WRITE: Human, Peggy · READ: all
```

> **Reporting aggregate subfolders are not yet standardised** (flagged, do not invent a canonical answer). Google clients (e.g. Lexacore UG) use `11_Absätze / 12_Dashboards / 99_Monatsreport`; Amazon clients (Windspiel, Bimmerle) use `00_Dashboards / 01_Absätze / 02_Werbung`. Only the **property detail report** path above (`04_Reporting & Analysen/[Channel]/[property]/[YYYY-MM].md`) is canonical. **New-project setup creates only the top-level `04_Reporting & Analysen/` plus the `[Channel]/[property]/` folder** — the aggregate/report subfolders are created at reporting time and should be harmonised in a separate pass.

## 3a. Channel-specific maps

The tree above is the shared shape. Channel-specific detail (the exact channel folder name, the channel's files, and their read/write rules) lives in a channel map:

| Channel    | Channel folder   | Detail map               |
| :--------- | :--------------- | :----------------------- |
| Amazon     | `00_Amazon`      | `lx-gdrive-amazon.md`    |
| Google Ads | `01_Google Ads`  | (covered in this file for now) |
| Meta       | (tbd)            | (not yet)                |

Before working in a client's `00_Amazon` folder, read `lx-gdrive-amazon.md`.

## 4. Read/write rule

The WRITE/READ annotations above are binding. Never write to a document you only have read access to. `client.md`, `strategy.md` and `budget.csv` are **human-owned** – agents read them and do not change them during operation.

**Two onboarding exceptions** (single source of truth for the procedure: `om-google-new-projects-workflow`): at project start an agent may (a) draft the initial **ENTWURF** of `client.md` and `strategy.md` for human approval → **FREIGEGEBEN**, and (b) write the customer's stated budget figure into `budget.csv` **once**. After that, all three are human-only.

**Adding to a file: use `gdrive_append_file`.** To add an entry to any accumulating document (e.g. `decision-log.md`, `learnings.md`), use `gdrive_append_file` (`position: "start"` to prepend / `"end"` to append) — it preserves the existing content server-side, so you pass only your new fragment. **Do not** use `gdrive_write_file` to add an entry: it **overwrites the entire file**, so passing only your fragment destroys everything already there. Editing existing text in place is a strict read-modify-write: `gdrive_read_file` the full file → make the change in memory → `gdrive_write_file` the **complete** document back → re-read and confirm the prior content survived. This protects the history that accumulating logs depend on.
