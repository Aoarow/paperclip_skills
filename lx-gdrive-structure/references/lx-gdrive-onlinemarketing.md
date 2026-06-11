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
| 01_Kunden & Projekte/01_Kunden (**client root**)  | 1LWUKYiwSSzrqiqzFVKeNRoPEBKOxLH7l                    |

## 2. Knowledge base (maintained by Research agents)

```
02_Agentur intern/09_Onlinemarketing/KI-Wissen/[Channel]/
```

Channels: `Google`, `Amazon`, `Meta`.
**WRITE:** Research agents · **READ:** all agents

## 3. Client folder schema (navigate by name from client root)

Every client follows this exact structure. Start from the client-root Folder-ID (section 1) and navigate **by name** – the Folder-IDs below the client level differ per client and must not be hard-coded.

```
01_Kunden & Projekte/
└── 01_Kunden/                                       [Folder-ID: see section 1 — client root]
    └── [client-name]/
        ├── client.md                                WRITE: Human only · READ: all
        │       Master data: autonomy level, channels, properties, project info.
        │       Critical document, filled at project start. CHANGED BY HUMAN ONLY.
        │
        ├── 02_Projektdurchführung & Assets/
        │   └── [Channel]/                            e.g. 01_Google Ads
        │       └── [property]/
        │           ├── strategy.md                   WRITE: Human, Roger, Peggy · READ: all
        │           ├── budget.csv                    WRITE: Human · READ: all
        │           ├── learnings.md                  WRITE: Reviewer agents · READ: all
        │           ├── data-sources.md               WRITE: Human, Roger, Peggy · READ: all
        │           ├── webseiten-analyse-google.md   WRITE: Peggy · READ: all   (Google only)
        │           └── decision-log.md               WRITE: Optimizer agents · READ: all
        │
        └── 04_Reporting & Analysen/
            ├── 01_Monatsreport/
            │   ├── [monthly report files]            WRITE: Peggy · READ: all
            │   └── dashboard-[YYYY-MM]-[channel].html WRITE: Peggy · READ: all
            └── [Channel]/
                └── [property]/
                    └── [YYYY-MM].md                  WRITE: Peggy · READ: all   (property detail reports)
```

## 4. Read/write rule

The WRITE/READ annotations above are binding. Never write to a document you only have read access to. `client.md` and `budget.csv` are human-owned – agents read them, but never change them.
