# Google Ads onboarding branch

Apply this reference only after the shared property gate and scaffold pass.

## Scope and boundaries

- One Google Ads property is the exact human-declared unit in `client.md`, commonly a
  website/domain but not necessarily derived from one.
- Use `01_Google Ads` as the Drive channel folder in both execution and reporting.
- Reuse one Paperclip project per customer × Google Ads:
  `om-<CLIENT>-goog`, where `<CLIENT>` is the established three-letter client code.
- Never rename the property to satisfy Google Ads or BigQuery syntax. Derive technical
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
- the client account linked to the Lexacore MCC (`7807674607`) — a human action; once
  linked, the MCC-level BigQuery transfer picks up the client's data automatically;
- conversion tracking reviewed and either verified or recorded as a human action;
- the MCC-level BigQuery transfer feeding the raw dataset;
- customer-scoped BigQuery views for the property;
- the technical bindings and view names recorded in `data-sources.md`;
- a non-empty, human-approved `budget.csv`;
- a human-completed `strategy.md`.

Derive the BigQuery identifier by replacing every non-alphanumeric character in the
property name with `_`. This is a technical alias only. Create or verify the established
customer-scoped views:

- `v_<technical_property>_campaign_performance_daily`
- `v_<technical_property>_campaign_trends`
- `v_<technical_property>_budget_utilization`

Filter every view by the confirmed numeric customer ID so customer data cannot mix.
Run [create_google_views.sql](create_google_views.sql) after substituting its
`{{PROPERTY}}` and `{{CID}}` placeholders. Review the rendered SQL before execution and
verify all three views are customer-scoped after creation.

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

When the website analysis, strategy, budget, tracking, CID/MCC, and BigQuery wiring are
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
