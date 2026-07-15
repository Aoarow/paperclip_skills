---
name: om-google-new-projects-workflow
description: Procedure for setting up a new Google Ads project — for a brand-new client (onboarding form → n8n) or a new property/project for an existing client (manual issue). Covers folder scaffold, draft docs, website analysis, the Paperclip project, the two required sub-agents, and the two human gates.
---

# New Google Ads project — setup procedure

Run this when a new Google Ads project starts. It is **entry-agnostic**: the same steps apply whether the trigger is a brand-new client (Google onboarding form → n8n) or an existing client starting a new property/channel (a manually created Paperclip issue).

## Trigger & handoff

You are woken by a Paperclip issue assigned to you, titled `Onboarding Google Ads: <Org> (<property>)`. The issue description is the handoff and already carries the full intake:

- Organisation (client display name), primary website, additional websites
- Property slug (domain with dots → underscores, e.g. `reiseglueck-bergstrasse_de`)
- Google Ads customer ID (CID), main goal, target CPA/ROAS, monthly budget
- Geography, competitors
- Creative context: why-us, problem solved, target group, tone (language + head/heart), forbidden words
- Contact person + email

n8n does **not** create Drive folders. You build the scaffold yourself via the Google Drive MCP. The human's involvement is the two gates below.

## Division of labour (read first — it is a guardrail)

`client.md`, `strategy.md` and `budget.csv` are **human-owned** (see repo `CLAUDE.md` §7/§10). You may create the **initial version** of each at onboarding, but you never edit them again during operation — every later change is human-only.

- `client.md`, `strategy.md`: create as **ENTWURF**; the human approves them → FREIGEGEBEN at Gate 1.
- `budget.csv`: write the **customer's stated monthly budget from the form once** at creation (the same figure a human would copy over), then **never touch the file again**. The human confirms it at Gate 1 and owns all later changes.

| Task | Peggy (agent) | Human |
| :--- | :--- | :--- |
| Folder scaffold | creates | — |
| `client.md`, `strategy.md` | creates as **ENTWURF** | approves → FREIGEGEBEN (Gate 1) |
| `budget.csv` | writes the customer's stated figure **once**, then never again | confirms at Gate 1; owns all later changes |
| Website analysis | produces | reviews (Gate 1) |
| Paperclip project + 2 agents | creates (agents PAUSED) | enables (Gate 2) |
| MCC link + BigQuery data layer | — | provisions (Gate-2 prerequisite) |

**Gate 1 is a Paperclip board approval** (see Step 5), not a comment: the process halts until the board approves.

## Step 1 — Determine client & property

1. **Client code** — each client has a code that is **exactly three uppercase characters** (e.g. `RGB` for Reiseglück Bergstraße, `WIN` for Windspiel, `BIM` for Bimmerle, `LEX` for Lexacore as a client), assigned once and reused for all their projects. This length is a hard convention — always exactly 3 characters, never 2. Reuse it if the client's `client.md` already has one; otherwise assign a fitting three-character code and record it in `client.md`. *(Firm-wide 2→3 character migration, 2026-07-15.)*
2. **Property slug** — take it from the issue (domain, dots → underscores, mirroring `lexacore_ai` / `lexacore_de`).
3. **New vs. existing client** — check by name whether the client folder + `client.md` already exist under the client root:
   - **New client** → create the full folder skeleton + draft `client.md` (Steps 2–3).
   - **Existing client** → reuse the folder and `client.md`; only add the new property subtree (Step 2, property parts) and append the new property under "Channels & Properties" in `client.md`. Reuse client-level context (tone, forbidden words, client code).

## Step 2 — Create the Drive structure (Drive MCP)

Navigate from the fixed client-root Folder-ID (authoritative schema and IDs live in **`lx-gdrive-onlinemarketing`** — do not hard-code IDs here). Create the **full client skeleton**; idempotent (check-then-create, never overwrite an existing file). It mirrors existing clients:

```
01_Kunden & Projekte/01_Kunden/<Org>/
  00_Vertragsunterlagen & Stammdaten/   (00_Angebot, 01_Vertrag, 02_NDAs)
  01_Management & Kommunikation/         (00_Protokolle, 01_Korrespondenz, 02_Projektplanung)
  02_Projektdurchführung & Assets/01_Google Ads/<property>/
  03_Input Kunde/
  04_Reporting & Analysen/01_Google Ads/<property>/
  05_Archiv/
  client.md
```

Files inside the property folder `02_Projektdurchführung & Assets/01_Google Ads/<property>/`:

- `strategy.md` — draft, status ENTWURF (Step 4)
- `budget.csv` — write the customer's stated monthly budget from the form (one row), then never edit it again (human-only thereafter)
- `data-sources.md` — technical wiring draft (Step 4)
- `learnings.md` — empty
- `decision-log.md` — empty

The reporting property folder stays empty at setup; monthly reports land there later.

## Step 3 — Draft `client.md` (ENTWURF)

Create `client.md` in the client root as a **draft** using the manifest structure: Stammdaten, Autonomy Level (default **Standard**), Channels & Properties, Creative context, **stable Drive Folder-IDs**, Reporting, History. Populate from the issue data and mark it clearly as ENTWURF for Gate 1.

Record the **client code** and the **stable Drive Folder-IDs** — they are the binding anchor. The folder *name* may be renamed by a human later; agents and reporting bind to the IDs, never the name.

## Step 4 — Draft `strategy.md` & `data-sources.md`

- `strategy.md` (status: ENTWURF) — pre-fill goal, target group, geography and competitors from the issue. The human refines and approves at Gate 1.
- `data-sources.md` — technical wiring: BigQuery project/dataset, the client's Google Ads customer ID, and the per-property view `v_<property>_campaign_trends`. **State in the file** that this view + ingestion still have to be provisioned (Gate-2 prerequisite).

## Step 5 — Website analysis (this triggers Gate 1)

Scan the client website (and competitors), assess it for Google Ads, and write `.../01_Google Ads/<property>/webseiten-analyse-google.md`:

```
---
created: <date>
analyzed_by: Peggy
websites: <URL>
channel: Google Ads
---
## Overall assessment      [traffic-light table: clarity, CTA, landing pages, social proof, tracking]
## Strengths
## Keyword potential        [clusters A/B/C with concrete keywords]
## Recommended campaign structure   [campaigns 1–3 with goals and budget shares]
## Action items before launch        [Critical 🔴 / Recommended 🟡 / Good 🟢]
## Launch recommendation     [where to start, why]
```

Then open **GATE 1 as a Paperclip board approval linked to this issue** (`POST /api/issues/{issueId}/approvals`) — not a plain comment or task. The approval request summarises what you drafted (`client.md`, `strategy.md`, `budget.csv`) plus the website analysis, and asks the human to review, confirm the budget, set the docs to FREIGEGEBEN, and clear any action items before launch.

**Halt here.** Do not proceed to Steps 6–7 until the board approves. If the board **requests revision**, revise the drafts and resubmit the approval; on **rejection**, stop and await instructions.

> Canonical approval syntax (create / await / resubmit) belongs in `lx-paperclip-inbox-cycle`. If it is not documented there yet, treat that as a gap to close — do not copy raw endpoints into every skill.

**No Google project launches without a completed website analysis and a granted Gate-1 board approval.**

## Step 6 — Paperclip project

Create a Paperclip project **`om-<CODE>-<channel>`** (Google → `om-<CODE>-goog`, e.g. `om-RGB-goog`) and nest this project's operational issues in it. Mirrors the Amazon convention (`om-WIN-amz`). `<CODE>` is the client's 3-uppercase-character code (see the CLIENT field in `om-amazon-advertising-manifest` §6).

## Step 7 — Sub-agents (after Gate 1) → Gate 2

Every Google project needs two sub-agents, **cloned from an existing project** (blueprint: the `lexacore.ai` Optimizer + Reviewer) with paths adjusted to the new property:

- **`<domain> Optimizer – Google`** — nightly: reads performance, adjusts bids/keywords within autonomy, logs decisions to `decision-log.md` (see `om-google-optimization`).
- **`<domain> Reviewer – Google`** — weekly: reads the last 14 days of `decision-log.md`, judges each decision against `strategy.md`, writes durable lessons to `learnings.md` (see `om-google-review`).

**Naming — do not deviate.** The agent display name is `<dotted-domain> <Role> – Google`, e.g. `reiseglueck-bergstrasse.de Optimizer – Google` and `reiseglueck-bergstrasse.de Reviewer – Google` — matching the existing `lexacore.ai …` agents. Use the **property domain**, never the client/org name: a client can run several properties (e.g. `lexacore.ai` *and* `lexacore.de`), so org-based agent names would collide. The property **folder** uses the underscore slug (`reiseglueck-bergstrasse_de`); the agent **name** uses the dotted domain.

Create the agents **PAUSED**. Enabling them is **GATE 2** — a deliberate human action — with two hard prerequisites:

1. **MCC link.** The client's Google Ads account (CID) is linked into the Lexacore MCC (`7807674607`). This is also what feeds the data: ingestion is a native BigQuery Data Transfer at MCC level, so once linked, the client's data flows into `google_ads_raw` automatically — there is no per-client transfer to set up.
2. **Per-property views.** Run `references/create_google_views.sql` (find-replace `{{PROPERTY}}` = the BigQuery-safe slug — the domain with **every** non-alphanumeric char turned into `_`, e.g. `reiseglueck_bergstrasse_de`; `{{CID}}` = the raw numeric customer id). It creates the three **customer-scoped** views (`v_<property>_campaign_performance_daily` / `_campaign_trends` / `_budget_utilization`) that the optimizer and reviewer read. The views filter by `customer_id`, so clients never mix. Note: the BigQuery slug may differ from the Drive folder slug (BigQuery names cannot contain `-` or `.`).

Campaigns are created later, **PAUSED**, and handed to the human per `om-google-campaign-creation` and the `CLAUDE.md` §10 guardrails.
