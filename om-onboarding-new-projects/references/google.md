# Google Ads onboarding branch

Apply this reference only after the shared property gate and scaffold pass.

## Scope and boundaries

- One Google Ads property is the exact human-declared unit in `client.md`, commonly a
  website/domain but not necessarily derived from one.
- Use `01_Google Ads` as the Drive channel folder in both execution and reporting.
- Reuse one Paperclip project per customer × Google Ads:
  `om-<CLIENT>-goog`, where `<CLIENT>` is the established three-letter client code.
- Never rename the property to satisfy Google Ads or Postgres syntax. Derive technical
  identifiers separately and record them in `data-sources.md`.

## Additional property file

Create `webseiten-analyse-google.md` in the execution property folder only when absent.
Peggy owns this analysis and may update it.

Use this structure:

```markdown
---
created: <date>
analyzed_by: Peggy
property: <exact property name>
websites: <confirmed URL(s)>
channel: Google Ads
---

# Website analysis — Google Ads

## Overall assessment
## Strengths
## Conversion and tracking readiness
## Keyword potential
## Recommended campaign structure
## Actions before launch
## Launch recommendation
```

Base the analysis on a live scan of the website and confirmed competitors. Clearly
separate observed facts from recommendations. Do not write recommendations into the
human-owned `strategy.md`.

## Data and account prerequisites

The shared scaffold can be created once the property itself is valid. Before declaring
`activation-ready`, require:

- a confirmed Google Ads CID in `client.md`;
- conversion tracking reviewed and either verified or recorded as a human action;
- the CID added to the sync's account list and to `GADS_ALLOWED_CUSTOMERS`;
- the property's five `agent_reads` views created and its scoped read role provisioned;
- the technical bindings, tenant name and view prefix recorded in `data-sources.md`;
- a non-empty, human-approved `budget.csv`;
- a human-completed `strategy.md`.

> **MCC linkage is no longer a data prerequisite.** It used to be, because the BigQuery
> transfer ran at MCC level and only picked up accounts linked beneath it. The Supabase
> sync calls each account directly, so an independent account works exactly as well —
> `lexacore.de` (`3010573696`) has always been one. Whether to link a client into the MCC
> is now purely an access/administration question, not a reporting one.

### Wiring a new property

1. **Add the account to the sync.** In `google_ads_sync.py`, extend `ACCOUNTS` with
   `(customer_id, login_customer_id_or_None)`. **The header rule is not cosmetic:** an
   account under the MCC needs `login-customer-id`; an independent account must **not**
   have it, or Google answers `403 USER_PERMISSION_DENIED`.
2. **Choose a tenant name and a view prefix** (lowercase, `a-z0-9_`). Convention so far:
   `lexacore_ai` / `lxai`, `lexacore_de` / `lxde`.
3. **Create the five views** from
   [create_google_views.sql](create_google_views.sql) after substituting `{{PREFIX}}` and
   `{{CID}}`. Review the rendered SQL before running it.
4. **Provision the read role:**
   `~/.supabase-ro/provision-tenant-db-user.sh --channel google <tenant> <prefix> property`
   then apply the printed `ALTER ROLE` as a role-capable user.
5. **Verify:** `~/.supabase-ro/q.sh <tenant> --check` must exit 0 — and run it **as the
   service user** (`sudo -u paperclip`), not as yourself.

Every view is filtered on the confirmed numeric customer ID so customer data cannot mix;
the read role can see only its own prefix. Both are checked by `--check`.

## Paperclip project and agents

Inventory before creating. Reuse the customer's `om-<CLIENT>-goog` project if it exists.
Create it only when absent.

Create or reuse exactly two property agents from the established Google blueprints:

- `<property> Optimizer – Google` — uses `om-google-optimization`;
- `<property> Reviewer – Google` — uses `om-google-review`.

Bind both agents to the exact property and stable Drive file/folder IDs. Do not make
agent identity depend on a re-derived slug. Create new agents paused and confirm the
paused state after creation.

## Gate and handoff

When the website analysis, strategy, budget, tracking, CID, and Supabase wiring are
complete, request the established human approval/gate for launch readiness. An approval
does not enable agents or campaigns.

For a new customer, the shared client task board in the lexacore.de portal is set up
after the Drive/Paperclip setup through `lx-plane-portal-onboarding`. Check whether the
customer's Plane portal project already exists; if not, run that skill (it has its own
blocking portal-profile gate) or route the step to its owner in the handoff.

Campaigns are created later through `om-google-campaign-creation`, always paused. A human
enables campaigns and agents deliberately.

If an account, tracking, data, strategy, or budget prerequisite is missing, report the
exact missing item and owner. The Drive scaffold may be `scaffold-ready`; it is not
`activation-ready`.
