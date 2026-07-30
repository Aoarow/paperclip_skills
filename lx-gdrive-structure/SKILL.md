---
name: lx-gdrive-structure
description: Map and navigation guide for the Lexacore Google Drive. Explains the folders and files the AI agents need in order to work in it. Department-specific reference files describe the folders and files for each department and its Head of Department. Use this skill whenever an agent needs to locate, read, or write a Drive document, or needs to understand the Drive folder structure.
---

# Lexacore Google Drive – The Workspace

This skill is the single source of truth for the Lexacore Google Drive structure. Humans and AI agents share the same map. Whoever moves, renames, or creates folders updates this skill – human and agent alike. A document is only "real" if its location is documented here.

## Shared-Drive-Root

```
https://drive.google.com/drive/u/0/folders/0APpEXGtLsCwkUk9PVA
Folder-ID: 0APpEXGtLsCwkUk9PVA
```

## How to use this skill

1. Identify which department the task belongs to.
2. Open the matching department reference file (table below) and read it **before** working in that department's Drive area.
3. Follow the read/write rules documented per file. Never write to a document you only have read access to.

## Department reference files

| Department                          | Head  | Reference file                  |
| :---------------------------------- | :---- | :------------------------------ |
| Online Marketing (Client Marketing) | Peggy | `lx-gdrive-onlinemarketing.md`  |

*(Further departments – Sales, AI Consulting – will be added here as they are built.)*

A department may have **channel-level** detail maps beneath it. For Online Marketing:

| Channel | Detail map |
| :------ | :--------- |
| Amazon  | `lx-gdrive-amazon.md` |

(Google Ads is currently covered within `lx-gdrive-onlinemarketing.md`; see its §3a channel table.)

## Navigation principle (applies to all departments)

Two kinds of folders exist in this Drive:

- **Fixed infrastructure folders** – knowledge base, onboarding queue, and the flat
  `01_Kunden & Projekte` root. They exist exactly once and are addressed by
  **Folder-ID**. *(In day-to-day work, the File-IDs of bound documents are normally
  already in the agent bundle's Location-binding table — read them directly with
  `~/.gdrive-ro/read.sh <FileID>`. Do **not** assume a `mcp_gdrive_*` tool exists.)*
- **Customer folders** – Twenty's `driveFolderId` is the only authoritative customer
  anchor. Open the folder by that ID; never identify it by name, status prefix, or path.
  Folder names are human-facing display and may change from `00_` to `01_` to `02_`.
  Discover children below the anchored customer folder and bind operational agents to
  their stable folder/file IDs. Never hard-code one customer's IDs into a reusable
  skill.

## Reading and writing a Drive file (the mechanism)

You address every Drive document by its **File-ID** (it is listed in your bundle's *Location binding* table and in the property's `data-sources.md`). To read or write the *content*, use the host-wide ops helpers — the service-account credentials live inside them; you only pass the File-ID. **Jump straight to these; do not hunt for credentials, a Drive MCP, `curl`, or a local mirror.**

- **Read** any file (Markdown, CSV, native Google Doc/Sheet; Shared-Drive files included):
  `~/.gdrive-ro/read.sh <FileID>` → prints the content to stdout.
- **Write** a native text file (e.g. `decision-log.md`, `learnings.md`). Drive has **no native append**, so read-modify-write: read the current content, build the new *full* content (prepend your dated entry), pipe it back, then read it back to confirm your entry **and** the prior history both survived:
  ```
  cur="$(~/.gdrive-ro/read.sh <FileID>)"
  printf '%s\n\n%s' "$new_entry" "$cur" | ~/.gdrive-ro/write.sh <FileID>
  ```

Facts these helpers encode (so you never re-derive them):
- They already pass the **Shared-Drive** flag and branch Google-Doc/Sheet export vs. native download. There is nothing left for you to reconstruct.
- The service account can **read and update** documents but **cannot delete, trash, or move** them — a deliberate safety floor. Never plan a delete; append/overwrite only.
- **Reads are live.** If a helper errors, that is a real access problem → escalate the blocker; **never fall back to a stale local mirror** or a file you found by searching the workspace (that is how stale-data decisions happen).
- Honour the WRITE/READ annotations in the department map: `client.md` and `budget.csv` are human-owned → read-only. Never write a file you only have read access to.

## Maintenance

This map is the truth about the Drive structure. If the structure changes, update this skill in the same change – human or agent.
