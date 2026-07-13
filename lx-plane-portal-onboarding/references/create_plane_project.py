#!/usr/bin/env python3
"""
Create the Plane customer project + the standard Google-onboarding task blueprint,
then link it to the Supabase customer record so the client portal shows it.

Usage:
    source ~/.lexacore/plane.env
    python3 create_plane_project.py "<Customer display name>" "<CODE>"

Example:
    python3 create_plane_project.py "Reiseglück Bergstraße" "RGB"

Prerequisites (see SKILL.md):
  - The customer LOGIN + company record already exist (admin created them in the
    portal admin area). The company display name MUST equal the argument exactly.
  - ~/.lexacore/plane.env exports:
      PLANE_API_KEY, PLANE_WORKSPACE_SLUG, PLANE_BASE_URL,
      SUPABASE_URL, SUPABASE_ANON_KEY, PROJECT_LEAD_MEMBER_ID

The script talks to Plane via curl (robust TLS) and to Supabase via its REST RPC.
It is NOT idempotent for the Plane project itself — run once per customer.
"""
import json, os, subprocess, sys

if len(sys.argv) != 3:
    sys.exit("Usage: create_plane_project.py \"<Customer display name>\" \"<CODE>\"")
CUSTOMER_NAME, CODE = sys.argv[1], sys.argv[2].upper()
if len(CODE) != 3:
    sys.exit("CODE must be exactly 3 characters (naming rule).")

def env(k):
    v = os.environ.get(k)
    if not v:
        sys.exit(f"Missing env var {k} (source ~/.lexacore/plane.env first).")
    return v

PKEY = env("PLANE_API_KEY"); SLUG = env("PLANE_WORKSPACE_SLUG"); PBASE = env("PLANE_BASE_URL")
SUPA_URL = env("SUPABASE_URL"); SUPA_KEY = env("SUPABASE_ANON_KEY")
LEAD = env("PROJECT_LEAD_MEMBER_ID")
B = f"{PBASE}/api/v1/workspaces/{SLUG}"

def plane(method, path, body=None):
    args = ["curl", "-s", "--max-time", "30", "-X", method,
            "-H", f"X-API-Key: {PKEY}", "-H", "Content-Type: application/json", f"{B}{path}"]
    if body is not None:
        args += ["--data-binary", json.dumps(body)]
    out = subprocess.run(args, capture_output=True, text=True).stdout
    try:
        return json.loads(out)
    except Exception:
        return {"_raw": out}

PROJECT_NAME = f"KUNDE: {CUSTOMER_NAME}"

# 1) Project ---------------------------------------------------------------
proj = plane("POST", "/projects/", {"name": PROJECT_NAME, "identifier": CODE})
PID = proj.get("id")
if not PID:
    sys.exit(f"Project creation failed: {json.dumps(proj)[:300]}")
print(f"Project: {PROJECT_NAME}  id={PID}  identifier={CODE}")

# 2) States -> 8-schema ----------------------------------------------------
states = plane("GET", f"/projects/{PID}/states/?per_page=50")
states = states.get("results", states)
by_name = {s["name"]: s for s in states}
# rename the 5 Plane defaults + sequence them
renames = [("Backlog", "Backlog", 10000), ("Todo", "Geplant", 20000),
           ("In Progress", "In Arbeit", 30000), ("Done", "Erledigt", 70000),
           ("Cancelled", "Abgebrochen", 80000)]
for old, new, seq in renames:
    s = by_name.get(old) or by_name.get(new)
    if s:
        plane("PATCH", f"/projects/{PID}/states/{s['id']}/", {"name": new, "sequence": seq})
# add the 3 missing "started" states (color is required on POST)
for name, color, seq in [("Wartet auf Kunde", "#0B4EB3", 40000),
                         ("Wartet auf Lexacore", "#E26913", 50000),
                         ("In Prüfung", "#8B5CF6", 60000)]:
    r = plane("POST", f"/projects/{PID}/states/", {"name": name, "group": "started", "color": color})
    if r.get("id"):
        plane("PATCH", f"/projects/{PID}/states/{r['id']}/", {"sequence": seq})  # POST ignores sequence
S = {s["name"]: s["id"] for s in plane("GET", f"/projects/{PID}/states/?per_page=50").get("results", [])}

# 3) Labels ----------------------------------------------------------------
for name, color in [("Orga", "#94A3B8"), ("Technik", "#6366F1"), ("Vertrieb", "#F59E0B"),
                    ("Marketing", "#22C55E"), ("partei:lexacore", "#E26913"), ("partei:kunde", "#0B4EB3")]:
    plane("POST", f"/projects/{PID}/labels/", {"name": name, "color": color})
L = {l["name"]: l["id"] for l in plane("GET", f"/projects/{PID}/labels/?per_page=50").get("results", [])}

# 4) project_lead (for Lexacore notification recipient resolution) ----------
plane("PATCH", f"/projects/{PID}/", {"project_lead": LEAD})

# 5) Tasks (the blueprint) -------------------------------------------------
lex, kun = L["partei:lexacore"], L["partei:kunde"]
# key, name, state, [labels], assign_lead, description
TASKS = [
 ("1","E-Mail „Projektstart Google“ senden","Erledigt",[lex,L["Orga"]],True,"Aus Vorlage: Link Google-Ads-Kontoerstellung, Link Google-Form, allg. Infos."),
 ("2","Google-Ads-Konto des Kunden: Verbindung anfordern","Erledigt",[lex,L["Technik"]],True,""),
 ("3","Ggf. Medien anfordern (Logo, Bilder, Video)","Erledigt",[lex,L["Marketing"]],True,"OPTIONAL – bei Nichtbedarf auf „Abgebrochen“ (zusammen mit #11)."),
 ("4","Kundenkonto im Portal (lexacore.de) anlegen","Erledigt",[lex,L["Technik"]],True,"Voraussetzung für den Portalzugang des Kunden."),
 ("5","Vertragsunterlagen an Kunde senden","Erledigt",[lex,L["Vertrieb"]],True,""),
 ("6","Datensilos anlegen (Ordner & Dateien)","Erledigt",[lex,L["Technik"]],True,""),
 ("7","Projekt recherchieren & konzipieren","Backlog",[lex,L["Marketing"]],True,"Kernarbeit – startet nach Kunden-Input (Form, Zugänge, ggf. Medien)."),
 ("8","Finale Abstimmung: Strategie, Budget usw.","Backlog",[lex,L["Marketing"]],True,""),
 ("9","Google-Form ausfüllen","Wartet auf Kunde",[kun,L["Orga"]],False,""),
 ("10","Google-Ads: Verbindung zum Lexacore-Verwaltungskonto genehmigen","Wartet auf Kunde",[kun,L["Technik"]],False,""),
 ("11","Ggf. Medien bereitstellen","Wartet auf Kunde",[kun,L["Marketing"]],False,"OPTIONAL – entfällt mit #3."),
 ("12","Vertrag unterzeichnen & an Lexacore senden","Wartet auf Kunde",[kun,L["Vertrieb"]],False,""),
 ("13","Finale Abstimmung: Strategie, Budget usw.","Backlog",[kun,L["Orga"]],False,"Spiegel von #8 – gemeinsamer Termin."),
 ("14","🚀 Projektstart – alle Aufgaben erledigt","Backlog",[lex,L["Orga"]],True,"Meilenstein: erreicht, wenn alle nicht-abgebrochenen Aufgaben erledigt sind."),
]
ID = {}
for key, name, state, labels, assign, desc in TASKS:
    p = {"name": name, "state": S[state], "labels": labels}
    if desc: p["description_html"] = f"<p>{desc}</p>"
    if assign: p["assignees"] = [LEAD]
    r = plane("POST", f"/projects/{PID}/work-items/", p)
    if not r.get("id"):
        sys.exit(f"Task #{key} failed: {json.dumps(r)[:200]}")
    ID[key] = r["id"]
    print(f"  task #{key} -> {r['id']}")

# 6) start_after relations (A starts after B) ------------------------------
def rel(a, bs):
    plane("POST", f"/projects/{PID}/work-items/{ID[a]}/relations/",
          {"relation_type": "start_after", "issues": [ID[b] for b in bs]})
rel("9", ["1"]); rel("10", ["2"]); rel("11", ["3"]); rel("12", ["5"])
rel("7", ["9", "10", "11"]); rel("8", ["7"]); rel("13", ["7"]); rel("14", ["8", "13"])
print("  relations set")

# 7) Link to the Supabase customer (company_plane_projects) -----------------
rpc = subprocess.run(
    ["curl", "-s", "--max-time", "30", "-X", "POST",
     f"{SUPA_URL}/rest/v1/rpc/link_company_plane_project",
     "-H", f"apikey: {SUPA_KEY}", "-H", f"Authorization: Bearer {SUPA_KEY}",
     "-H", "Content-Type: application/json",
     "-d", json.dumps({"p_company_name": CUSTOMER_NAME,
                       "p_plane_project_id": PID,
                       "p_plane_project_name": PROJECT_NAME})],
    capture_output=True, text=True).stdout
print(f"Mapping (company_plane_projects): {rpc.strip()}")
print("\nDONE. Notifications work automatically (dynamic project lookup) — no n8n change needed.")
print("Remaining human step: the customer login/company must exist in the portal admin area.")
