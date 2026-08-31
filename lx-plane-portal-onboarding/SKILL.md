---
name: lx-plane-portal-onboarding
description: Create the Plane project + standard onboarding task list for a new client and wire it into the lexacore.de client portal. Use this when a new Google Ads client is being onboarded and needs their shared task board (client ⇄ Lexacore) to appear in the portal. Runs the create_plane_project.py helper, which builds the Plane project, the 14-task blueprint with dependencies, and the Supabase mapping.
---

# Plane / client-portal onboarding

> **Where this skill's reference files actually are.** Paperclip copies only this `SKILL.md` into
> the agent runtime — the `references/` folder is not delivered with it, and the runtime folder
> carries a hash suffix. A relative `references/<file>` path therefore does **not** resolve.
> Read them from the filesystem instead:
>
> **`/srv/lexacore-skills/lx-plane-portal-onboarding/references/<file>`**
>
> That path is readable for the agent user and is kept current from git. Progressive disclosure is
> unchanged — open the one file you need, not all of them.


Run this as part of onboarding a new client, **after** their Drive/Paperclip setup, to give them the shared task board that shows up in the lexacore.de client portal (tab "Projekt"). Client and Lexacore both see and work the same tasks there; Lexacore's completed prep work is shown, the client sees a short to-do list.

This is a small, self-contained building block. It does **not** provision the
Drive property scaffold or Paperclip agent set; that is
`om-onboarding-new-projects`.

## What it produces

- A Plane project `KUNDE: <Customer name>` with the 3-letter client code as its identifier.
- The 8-state workflow (Backlog → Geplant → In Arbeit → Wartet auf Kunde → Wartet auf Lexacore → In Prüfung → Erledigt → Abgebrochen) and the 6 labels (`partei:kunde`, `partei:lexacore`, Marketing, Vertrieb, Technik, Orga).
- The **14-task Google onboarding blueprint** with `start_after` dependencies. The six Lexacore prep tasks are created already **completed** (they are real bootstrap work you do during onboarding — sending the project-start mail, requesting account access, creating the data silos, etc.), so the client's first view shows visible Lexacore progress plus their own short list.
- The `company_plane_projects` mapping that connects the Plane project to the client's portal account.

Notifications (digest e-mails, dependency activation) then work **automatically** — the pipeline resolves projects dynamically, so no n8n change is needed per client.

## Procedure (order matters)

You need two inputs: the client's **canonical display name** and the **3-letter client code** (naming rule: exactly 3 characters, e.g. `RGB` — reuse the code already assigned across Plane / Paperclip / Drive, never invent a new one).

### Step 1 — Portal-profile gate (BLOCKING — do this first, every time)

The customer's portal login + company record can only be created by a human in the portal admin area (no service-role access by design; creating it also sends the client their login). So that this step can never be forgotten, **create a board task for the human and block on it**:

- Title: `Portal-Profil anlegen: <Customer> (lexacore.de)`
- Description: create the customer login in the portal admin area — email = the client's contact address, role = `customer`, and company name = **exactly** `<Customer display name>`. This exact string is the join key to the portal; any mismatch breaks the link.
- Treat it as a **blocking gate** (use the board's approval / gate mechanism — see `lx-paperclip-inbox-cycle`): **do not proceed to Step 2 until the board reports this task done.** Pause your run until then. This is deliberate — `create_plane_project.py` needs the company to exist and will stop with a clear error otherwise, so the gate is what keeps the ordering safe.

### Step 2 — Create the Plane project + blueprint + mapping

Only after Step 1 is confirmed done by the board. Requires `~/.lexacore/plane.env` on this host (Plane API key, workspace, Supabase URL + anon key, project-lead member id — ask the human to add it if missing).

```bash
source ~/.lexacore/plane.env
python3 references/create_plane_project.py "<Customer display name>" "<CODE>"
```

- `<Customer display name>` must match the company name from Step 1 **exactly** (join key). Example: `"Reiseglück Bergstraße"`.
- `<CODE>` is the 3-letter client code, e.g. `RGB`.

The script prints the new project id, each task id, the relations, and the mapping result. Run it **once** per client (project creation is not idempotent; the Supabase mapping is).

## Guardrails

- If the company is not found, the script stops with a clear error — the admin must create the client login/company first. Do not try to create the auth user yourself (no service-role access by design).
- The optional media tasks (#3 Lexacore, #11 client) stay in the blueprint. If the client needs no media, set **both** to "Abgebrochen" (they are coupled via a dependency) — do not delete them, so the decision stays traceable.
- Plane delivers webhooks at-least-once; the notification pipeline dedupes, so do not worry about duplicate events.
