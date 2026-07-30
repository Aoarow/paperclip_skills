# Shared property scaffold

This reference defines what every approved Online Marketing property receives,
independent of channel. Load the channel reference afterwards for additions.

## Preconditions

Require all of the following:

- a stable customer `driveFolderId`;
- an existing Customer V2 root and `client.md`;
- a unique valid property declaration in `client.md`;
- one supported channel (`Google Ads` or `Amazon`).

The customer lifecycle automation, not Peggy, owns the customer root and top-level
folders.

## Canonical paths

Use the exact channel names from the Drive map:

| Channel | Folder name |
| :--- | :--- |
| Google Ads | `01_Google Ads` |
| Amazon | `02_Amazon` |
| Meta | `03_Meta` (reserved; onboarding unsupported until its reference exists) |

For each property create or reuse:

```text
<customer root by driveFolderId>/
├── 02_Projektdurchführung/
│   └── <Channel>/
│       └── <property>/
│           ├── strategy.md
│           ├── budget.csv
│           ├── data-sources.md
│           ├── decision-log.md
│           └── learnings.md
└── 03_Reporting/
    └── <Channel>/
        └── <property>/
```

Do not create per-property briefing, communication, approval, research, customer-input,
or archive folders. Those concerns stay at customer level. The property is the smallest
internal strategic unit, not a second customer tree.

## Base-file ownership and initial content

Creating a file shell is not permission to author its business content.

### `strategy.md` — human-owned

Create only when absent, using:

```markdown
# Strategy — <property>

Status: AWAITING HUMAN INPUT

This strategy is human-owned. Define goals, guardrails, audience, geography,
seasonality, exclusions, and channel-specific constraints before activation.
```

Do not infer any of those values from an issue, website, or prior property. Peggy may
produce separate analysis and recommendations, but the human approves and records the
strategy.

### `budget.csv` — human-owned

Create only when absent, with the header:

```csv
month,budget_eur,note
```

Do not insert, copy, or alter a budget value. A human enters the approved monthly
ceiling. An empty data row means the property is not activation-ready.

### `data-sources.md` — Peggy may maintain technical bindings

Create only when absent:

```markdown
# Data sources — <property>

## Property binding
- Channel: <channel>
- Property: <exact property name from client.md>

## Sources
- Status: NOT WIRED

## Location bindings
- Execution folder ID:
- Reporting folder ID:
```

Peggy may add confirmed non-secret technical identifiers and stable file/folder IDs.
Do not repeat customer strategy, budget, credentials, or account-routing facts owned by
`client.md`.

### `decision-log.md` — property agents write

Create only when absent:

```markdown
# Decision log — <property>

No decisions recorded.
```

### `learnings.md` — Reviewer writes

Create only when absent:

```markdown
# Learnings — <property>

No durable learnings recorded.
```

Channel references may add files. They may not weaken these ownership rules.

## Idempotency and conflicts

For every folder, file, Paperclip project, and agent:

1. Search within the exact expected parent/scope.
2. Zero matches: create it.
3. One compatible match: reuse it and preserve its stable ID.
4. More than one match, wrong type, or incompatible binding: stop and escalate.

Never delete, move, rename, overwrite, or merge an existing object as an automatic
repair. Never replace a human-edited file with the initial template.

If a run stops after partial creation, the next run repeats the inventory and safely
continues. Report partial objects and IDs in the Paperclip handoff.

## Readiness stages

Use exactly these terms:

- **`scaffold-ready`** — folders and shells exist; business/data/approval prerequisites
  may still be open; agents are absent or paused.
- **`activation-ready`** — human-owned strategy and budget are complete, channel data
  prerequisites pass, required agents exist paused, and only deliberate human enabling
  remains.

Neither term means a campaign is live. Campaign creation and activation belong to their
specialist skills and human gates.
