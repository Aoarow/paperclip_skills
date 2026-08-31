---
name: om-onboarding-new-projects
description: Provision a new Online Marketing channel or property for a customer after the customer-level Drive structure exists. Use when Peggy receives a Paperclip onboarding issue for Google Ads or Amazon, when a customer adds another property or channel, or when an existing setup must be checked for the canonical folders, control documents, data wiring, Paperclip project, and paused agent set. The human-owned client.md is the control file and the only authority for property names, channel assignment, account routing, and autonomy; never infer or invent those values.
---

# Online Marketing Project Onboarding

> **Where this skill's reference files actually are.** Paperclip copies only this `SKILL.md` into
> the agent runtime — the `references/` folder is not delivered with it, and the runtime folder
> carries a hash suffix. A relative `references/<file>` path therefore does **not** resolve.
> Read them from the filesystem instead:
>
> **`/srv/lexacore-skills/om-onboarding-new-projects/references/<file>`**
>
> That path is readable for the agent user and is kept current from git. Progressive disclosure is
> unchanged — open the one file you need, not all of them.


Set up the operational layer for an approved Online Marketing property. Treat this as
one cross-channel procedure with channel-specific branches.

The customer lifecycle automation has already created the customer root, `client.md`,
and the customer-level folders. Do not rebuild that layer. Create only the approved
channel/property subtrees, their base files, data wiring, Paperclip project, and paused
agent bundles.

## Required references

Read these before changing anything:

1. `lx-paperclip-inbox-cycle` for checkout, escalation, delegation, and close-out.
2. `lx-gdrive-structure` and `lx-gdrive-onlinemarketing` for the live Drive map and
   read/write rights.
3. [client-md-contract.md](references/client-md-contract.md) for the property gate and
   control-file grammar.
4. [property-scaffold.md](references/property-scaffold.md) for the shared folders,
   files, idempotency, and completion checks.
5. Exactly one channel reference:
   - [google.md](references/google.md) for Google Ads.
   - [amazon.md](references/amazon.md) for Amazon.

Do not provision Meta until a Meta reference exists. Escalate the unsupported channel
instead of adapting another channel's rules.

## Non-negotiable boundaries

- Resolve the customer folder from the stable `driveFolderId` supplied by Twenty or the
  onboarding issue. Never identify a customer by Drive folder name or status prefix.
- Read `client.md` before planning or creating anything.
- Treat `client.md` as human-owned and read-only. It is the control file, not an output
  of this procedure.
- Copy the property name exactly from `client.md`. Never derive it from the company,
  website, brand, marketplace, account, or issue title.
- Create technical shells for human-owned property files only where the scaffold
  contract explicitly permits it. Never invent strategy, budget, account data, or
  approval.
- Create only commissioned channels and declared properties.
- Make every create operation check-before-create and safe to rerun.
- Create Paperclip agents paused. A human deliberately enables them after every
  activation prerequisite is complete.

## Workflow

### 1. Check out and load the onboarding issue

Follow `lx-paperclip-inbox-cycle`. Establish:

- the Twenty company ID or equivalent canonical customer identifier;
- the stable Drive customer-folder ID (`driveFolderId`);
- the requested channel;
- the requested property, if the issue narrows the scope;
- the three-letter client code;
- the human owner or configured supervisor for missing-input escalation.

An issue value may narrow the requested scope, but it may not define a property that is
absent from `client.md`.

### 2. Verify the customer-level prerequisite

Open the folder by `driveFolderId`, then verify that `client.md` and the Customer V2
folders required by `lx-gdrive-onlinemarketing` exist. Do not infer readiness from
`01_` in the folder name.

If the ID is missing, resolves ambiguously, or the customer-level structure is
incomplete, stop. Post the exact missing prerequisite and route the issue upward as
`todo`; never leave it `blocked`.

### 3. Apply the property gate

Read `client.md` live and apply `client-md-contract.md`.

The hard identity gate passes only when the requested channel and property are explicit,
unique, and syntactically safe as Drive folder names. This is enough to create the
shared `scaffold-ready` folder/file shell. Status, autonomy, account routing, and channel
prerequisites are separate readiness gates and may prevent agent creation or
`activation-ready`.

If `client.md` explicitly marks the property `paused` or `archived`, stop before creating
anything unless the issue contains newer explicit human authorization. Do not silently
normalize spelling, case, dots, hyphens, or marketplace suffixes.

If the property is missing or ambiguous, make no property-level changes. In the
handoff comment state:

1. which customer and channel were requested;
2. which exact field or property block is missing or inconsistent;
3. the smallest concrete edit required in `client.md`;
4. that onboarding can be rerun unchanged after the human edit.

Then reassign upward with status `todo` according to `lx-paperclip-inbox-cycle`.

### 4. Build an idempotent change plan

Inventory the execution folder, reporting folder, base files, Paperclip project, and
agents before creating anything. Classify each expected object as:

- `reuse` — one compatible object already exists;
- `create` — no compatible object exists;
- `conflict` — duplicates or incompatible content exist.

Do not guess through a conflict. Escalate it with the object IDs/names and make no
destructive correction.

### 5. Create the shared property scaffold

Follow `property-scaffold.md`. Create the channel folder and exact property folder under
both:

- `02_Projektdurchführung/<Channel>/<property>/`
- `03_Reporting/<Channel>/<property>/`

Create the common base files in the execution property folder. Preserve every existing
file and its ID. Never replace a file merely to apply a newer template.

### 6. Run the channel branch

Load and execute the selected channel reference:

- Google Ads: website analysis, account/data prerequisites, Google Paperclip project,
  and the Optimizer/Reviewer pair.
- Amazon: account routing, product-master/data prerequisites, Amazon Paperclip project,
  Account Manager, and four property agents.

Where prerequisites are incomplete, finish only the explicitly safe scaffold stage,
record what remains, and route the issue to the person who must supply or approve the
missing input. Never represent a scaffold as activation-ready.

### 7. Verify before handoff

Read back every created or reused object. Confirm:

- the same customer folder ID was used throughout;
- folder names equal the `client.md` property name exactly;
- execution and reporting paths both exist once;
- all common and channel-specific files exist once;
- human-owned files contain no invented business values;
- the Paperclip project was reused or created once;
- the expected agents exist once and remain paused;
- no unrelated channel/property was changed.

### 8. Close with an auditable result

Post a compact result containing:

- customer, channel, and exact property name;
- Drive folder/file IDs created and reused;
- Paperclip project and agent IDs created and reused;
- readiness stage: `scaffold-ready` or `activation-ready`;
- unresolved human actions and the exact next owner;
- confirmation that all agents remain paused.

Set the issue disposition according to `lx-paperclip-inbox-cycle`. Use `done` only when
the requested onboarding stage is complete. Route incomplete human prerequisites upward
as `todo`; do not use `blocked`.

## Maintenance

This skill owns the shared onboarding sequence and its gates. The Drive map owns paths
and access rights; `client.md` owns customer/property truth; channel references own
channel-specific prerequisites and agent sets; specialist skills own campaign and
optimization procedures. Update those sources rather than duplicating their contents
here.
