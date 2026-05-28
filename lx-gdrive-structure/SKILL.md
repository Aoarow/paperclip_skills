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

## Navigation principle (applies to all departments)

Two kinds of folders exist in this Drive:

- **Fixed infrastructure folders** – knowledge base, onboarding queue, client root. They exist exactly once and never move. Address them by their **Folder-ID**; it is robust and avoids path-navigation errors. Always call the Drive MCP with the Folder-ID, e.g.
  `mcp_gdrive_gdrive_list_folder({ url: "1o2VNGERtm2iN3YYiH7RCx0IdhHvL8494" })`
- **Schematic client folders** – they follow a repeating pattern instantiated per client, so every client has *different* Folder-IDs below the client level. Do **not** hard-code IDs for these. Navigate **by name**, starting from the fixed client-root Folder-ID.

## Maintenance

This map is the truth about the Drive structure. If the structure changes, update this skill in the same change – human or agent.
