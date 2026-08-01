# Amazon onboarding branch

Apply this reference only after the shared property gate and scaffold pass.

## Scope and boundaries

- One Amazon property is the exact human-declared strategic unit in `client.md`.
- Property naming is a human decision. Names such as `crazyspirits-seller-de`,
  `evermann-seller-de`, or `needle-seller-de` are examples, not a generation rule.
- Use `02_Amazon` as the Drive channel folder in both execution and reporting.
- Reuse one Paperclip project per customer × Amazon:
  `om-<CLIENT>-amz`, where `<CLIENT>` is the established three-letter client code.
- The Amazon account is a routing layer, not the property. Several properties may share
  one Seller or Vendor account.

## Account-routing gate

The property block must point to one explicit Amazon account block in `client.md`. That
account block owns the non-secret routing facts:

- Ads profile ID;
- account ID;
- marketplace;
- sales channel (`seller` or `vendor`).

Never derive account routing from the property name. Keep credentials in the secret
store, never in `client.md` or `data-sources.md`.

The advertising **profile ID** is the technical counterpart of this routing and is per
marketplace, not per account: one seller account has a different profileId in DE, FR, UK
and so on. Read the correct one from `amazon_ads_raw.profiles` and record it in
`data-sources.md`; never reuse another customer's or another marketplace's profile.

Agents reach the Amazon Ads MCP through a per-tenant registry on the operations server,
`~/.amazon-ads-mcp/tenants.json`, which maps each customer to its profile ID and each
Paperclip agent to its customer and tool allowlist. `render-mcp-configs.py` stamps the
freshly refreshed token, the customer's profile scope, and the allowlist into every
registered agent's Codex config on each token refresh. Onboarding a customer therefore
adds one `tenants` entry plus one `agents` entry per agent — never a hand edit of an
agent's `config.toml`, which the next refresh would overwrite. An agent absent from the
registry simply has no Amazon MCP access.

The shared folder/file scaffold may be created if the property and account reference are
unambiguous even while live identifiers are pending. Live ingestion and agent activation
require all routing identifiers.

## Product master

Create one Google Sheet shell per property, named:

`<property> Produkte`

The Sheet is human-owned. Peggy may create the empty, canonical column structure but may
not add, infer, or change product facts, priorities, prices, or inventory. Preserve an
existing Sheet and its columns.

Use these canonical columns for a new Sheet, in this order:

```text
asin, sku, fba_sku, product_name, brand, marketplace, category, priority,
status, price, currency, source, last_human_update
```

`priority` uses the human-set `1` / `2` / `3` convention from
`om-amazon-advertising-manifest`. `status` identifies whether a catalog item is active;
it is not live offer availability. Do not add or gate on `stock_status`: stock and
buyability are live, per-SKU facts checked through the Amazon Ads/API path, not maintained
in this Sheet.

n8n syncs the human-maintained Sheet to Supabase. Agents read product facts from
Supabase, not directly from the Sheet; ASIN is the join key. Before calling the sync
operational, verify that its mapping accepts every canonical column. Escalate a mapping
mismatch instead of silently dropping a field.

Each customer gets its own copy of the sync workflow (`<CLIENT>-amz Produkt-Sheet →
Supabase`), because a Google Sheets trigger binds to one document. The transform node is
identical in every copy: it carries a `TENANT` constant plus a `TENANTS` registry holding
each customer's `company_id`, and refuses to run when `TENANT` does not match the
workflow name. Clone the workflow, change that one line, keep the guard. Without it a
forgotten edit writes one customer's catalogue under another customer's `company_id`,
which no downstream check would catch.

## Data prerequisites

Record confirmed technical wiring in `data-sources.md` without duplicating the account
facts from `client.md`. Before declaring `activation-ready`, require:

- all Amazon account-routing identifiers in `client.md`;
- the product Sheet populated and its sync verified;
- Supabase product rows scoped to the property;
- Ads performance ingestion scoped to the confirmed profile/account;
- historical advertising CSVs ingested and tested where available;
- sales data available for TACOS reporting;
- the data freshness check passing;
- a non-empty, human-approved `budget.csv`;
- a human-completed `strategy.md`, including channel guardrails needed by the Amazon
  specialist skills.

Customer-provided raw exports land in the customer-level `04_Kundeneingang`; do not
create a parallel per-property intake tree. `data-sources.md` records their stable IDs or
ingestion destinations.

## Agent read layer

Ads ingestion is account-agnostic: it walks every profile the token can see, so a new
customer's raw rows usually exist before onboarding starts. What must be created is the
customer's own scoped read layer.

Run [create_amazon_views.sql](create_amazon_views.sql) with `{{PREFIX}}` (short tenant
alias, e.g. `bi`), `{{PROFILE_ID}}` and `{{COMPANY_ID}}` substituted. It creates the six
`agent_reads.<prefix>_*` views the agents read, plus the GRANT block for the customer's
read-only role. Record the view names in `data-sources.md`.

Then provision the role's credentials on the operations server:

```bash
~/.supabase-ro/provision-tenant-db-user.sh <tenant> <prefix>
```

Nobody chooses or types this password. The script generates it, writes
`~/.supabase-ro/<tenant>.env` (mode 600), and prints only the SCRAM verifier to apply
with `ALTER ROLE`. The plaintext never leaves that host, so the credential cannot be
leaked through a chat, a ticket, or an agent transcript — and onboarding a customer stays
two commands rather than a manual trip through the database console. The same command
rotates an existing tenant.

Agents then query through `~/.supabase-ro/q.sh <tenant> "<SQL>"`, each logging in as its
own role. Record the exact invocation in the property's `data-sources.md`; the specialist
skills deliberately resolve the read path from there rather than hard-coding it.

Gate before creating agents: `~/.supabase-ro/q.sh <tenant> --check` must exit zero.

Isolation rules, all load-bearing:

- The views are owned by `postgres` and are not `security_invoker`, so they read the raw
  tables with definer rights and bypass RLS. The hard-coded profile/company filter inside
  each view is therefore the only thing separating customers. Never widen one, and never
  add a view without one.
- Grant each tenant role only its own views, explicitly. Do not use
  `ALTER DEFAULT PRIVILEGES` on `agent_reads`: a blanket default grants every future
  customer's views to whichever role it names. That exact trap was live until 2026-08-01,
  when Bimmerle's `bi_*` views were silently granted to `amazon_ro_windspiel`.
- After provisioning, verify as the tenant role that each view returns exactly one
  `company_id` and that `public.products` is denied.

## Paperclip project and agents

Inventory before creating. Reuse the customer's `om-<CLIENT>-amz` project if it exists.
Create it only when absent.

Create or reuse one project-level Account Manager:

- `<customer> – Amazon Account Manager` — uses `om-amazon-account-management`.

Create or reuse four agents per property:

- `<property> – Amazon Optimizer` — `om-amazon-optimization`;
- `<property> – Amazon Positive Targeter` — `om-amazon-positive-targeting`;
- `<property> – Amazon Negative Targeter` — `om-amazon-negative-targeting`;
- `<property> – Amazon Reviewer` — `om-amazon-review`.

Bind property agents to the exact property and stable Drive/data identifiers. Configure
the hierarchy through Paperclip: property agents → Amazon Account Manager → Peggy.
Do not hard-code supervisor IDs into reusable bundles.

Create every new agent paused and verify the paused state. The Account Manager remains a
single customer/channel role when additional properties are added; never create one per
property.

## Gate and handoff

Build and validate against historical data before connecting live automation whenever
historical exports exist. Human approval, complete strategy/budget, verified product
sync, and verified Ads/sales ingestion are required for `activation-ready`.

Campaign creation belongs to `om-amazon-campaign-creation`; any created campaign remains
paused for human activation. Optimization and targeting permissions come from
`om-autonomy-levels` and the Amazon specialist skills.

If product, account, data, strategy, or budget prerequisites are missing, report the
exact missing item and owner. The Drive scaffold may be `scaffold-ready`; it is not
`activation-ready`.
