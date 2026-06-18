---
name: om-amazon-new-projects-workflow
description: What to set up when onboarding a new Amazon advertising client (= one Paperclip project per client × Amazon, the account/isolation boundary). Covers the Drive folder + base documents per property, the non-secret account register entry, the data-sources wiring (Ads profile, Supabase, ingestion), and instantiating the agents — the KI-Account-Manager (project head) plus the four property agents (Optimizer, positive Targeter, negative Targeter, Reviewer). Use whenever a new Amazon client or a new property is being set up, or when checking that an existing Amazon project has its required folders, files, and agents in place.
---

# Amazon — New Project / Property Setup

This skill describes what must exist before an Amazon property goes live, mirroring the Google new-projects workflow but adapted for Amazon's structure (an account tier, four property agents, Supabase instead of BigQuery). **One Paperclip project per client × Amazon** is the account boundary (architecture memo §1).

Check whether the files/folders below exist. If not, create them as empty files first, then open a Paperclip issue so they get filled. Build and **test against the client's historical CSVs first**; wire to live profiles and nightly ingestion once Amazon access is granted.

> **Scaffold status:** outline below; exact folder paths/IDs come from the Amazon Drive map (`lx-gdrive-amazon.md`, to be authored in the Drive-Map phase) — this skill references that map, it does not hard-code paths.

## 1. Folders & base documents
Per the Amazon Drive map (`lx-gdrive-structure` → `lx-gdrive-amazon.md`):

- **Account info lives in `client.md`** (at the client root, read first by all agents) — **not** a separate `_konten/` file. Model the Amazon channel as **Channel → Account(s) → Properties**: each account block carries the 2-char `CLIENT` code (per client), Ads profile ID, account ID, marketplace, and sales channel (seller/vendor), and lists the properties on that account. Non-secret routing only; real credentials stay in the secret store. (This consolidation supersedes the architecture memo §4 `_konten/[account].md` register.)
- **Per property** (`02_Amazon/[property]/`, e.g. `windspiel-seller-de`):
  - `data-sources.md` — the property's **data wiring**: Supabase tables/connection, the ingestion workflow, customer CSV exports. Points to the account in `client.md` for the Ads profile ID / marketplace rather than repeating them (single source of truth).
  - `strategy.md` — goals, ACOS/TACOS target slots, Buy-Box threshold + inventory guardrail slots, head-term ownership map, distribution logic (human + Peggy).
  - `budget.csv` — *human-owned* monthly € budget per product/brand. Agents read only.
  - `products.csv` — hard facts only (schema in brief §5); seed manually now, SP-API sync later.
  - `learnings.md` — empty file (written by the Reviewer).
  - `decision-log.md` — empty file (written by the property agents).
- **Reporting:** the per-property reporting folder; monthly `[YYYY-MM].md` detail reports are created later by Peggy / the Account Manager (TACOS roll-up).

## 2. Determine the properties
Apply the property split test (architecture memo §2) before creating agents: a property is the smallest unit with a coherent strategy and its own budget — normally the brand. Split only if **all** split conditions hold. Encode the property ID as `[unit]-[seller|vendor]-[marketplace]` from day one (memo §3).

## 3. Agents to instantiate
Adapt existing agent bundles (per the Google pattern) and re-path for Amazon — do not invent bundles from scratch.

- **[client] – KI-Account-Manager** (project head): cross-property budget allocation within the human total, sibling/head-term arbitration, **campaign creation**, monthly TACOS roll-up. Thin/pass-through for a single-property client.
- **Per property — four agents:**
  - **[property] – Optimizer** (daily; runs after ingestion) — `om-amazon-optimization`.
  - **[property] – Positive Targeter** (monthly) — `om-amazon-positive-targeting`.
  - **[property] – Negative Targeter** (weekly) — `om-amazon-negative-targeting`.
  - **[property] – Reviewer** (weekly; reads all property agents' logs, writes `learnings.md`).

Supervisors resolve via Paperclip config (property agents → Account Manager → Peggy); do not hard-code supervisors into reusable bundles.

## 4. Pilot note
The first proband is **Windspiel (Seller, DE)** — a multi-week live trial before the rest of the rollout (memo §11). Final Windspiel property count (1 vs. 2) is a pending human decision (memo §12).

## References
- `lx-gdrive-structure` → `lx-gdrive-amazon.md` — folder schema, Folder-IDs, read/write rights.
- `om-amazon-advertising-manifest`, `om-amazon-campaign-creation`, `om-amazon-optimization`, `om-amazon-positive-targeting`, `om-amazon-negative-targeting`.
- `om-autonomy-levels` — the level set per property in `client.md`.

## Maintenance
This skill owns the *setup checklist*. Folder paths/IDs live in the Drive map; agent procedures live in their own skills. Keep those single sources of truth.
