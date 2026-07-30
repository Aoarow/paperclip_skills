# `client.md` control-file contract

`client.md` is the human-owned steering file for one customer. Every Online Marketing
onboarding begins by reading it live. Agents never create, edit, repair, or append to
it.

## Authority order

For property onboarding, use this order:

1. `driveFolderId` identifies the customer folder.
2. The `client.md` inside that folder identifies commissioned channels and properties.
3. A property block identifies its exact folder name, lifecycle state, autonomy level,
   and channel-specific routing.
4. The Paperclip issue selects work from that approved set.

The issue may not override or supplement a missing `client.md` declaration. Drive folder
names, existing agent names, ad-account names, and prior comments are not substitutes.

## Canonical property blocks

Use a visible channel heading and one repeated property heading per strategic unit.
The property name after `Property:` is the exact, stable identifier copied into Drive
folders and agent bindings.

```markdown
## Channels & Properties

### Google Ads

#### Property: example.de
- Status: onboarding
- Autonomy Level: Observe
- Website: https://example.de
- Google Ads CID: 1234567890
- MCC linked: no

### Amazon

#### Account: example-seller-de
- Ads Profile ID: [human input required]
- Account ID: [human input required]
- Marketplace: DE
- Sales Channel: seller

#### Property: examplebrand-seller-de
- Status: onboarding
- Autonomy Level: Observe
- Account Reference: example-seller-de
```

The headings and labels are the canonical format for new entries. Existing manifests
using the older bold form (`**Property: ...**`) remain readable if the same facts are
unambiguous; do not rewrite them during onboarding.

## Hard identity gate

The shared Drive scaffold requires only:

- **Channel** — by placement below `Google Ads` or `Amazon`.
- **Property** — a non-empty exact name.

This narrow gate expresses the human decision that matters for folder creation: which
strategic unit exists, under which channel, and what its exact stable name is.

## Readiness fields

The canonical block should also state:

- **Status** — `onboarding`, `active`, `paused`, or `archived`;
- **Autonomy Level** — `Observe`, `Standard`, or `Extended`, as defined by
  `om-autonomy-levels`.

Missing Status or Autonomy Level does not prevent the technical Drive shell. It does
prevent agent activation and `activation-ready`. Do not assume `Standard`. New and
unproven properties should normally be set to `Observe`, but the human records that
decision. An explicit `paused` or `archived` status stops all new provisioning unless a
human explicitly authorizes reactivation/migration.

## Channel-required fields

Google Ads requires before its analysis/data/agent stages can complete:

- `Website`;
- `Google Ads CID` before data wiring and agent activation;
- explicit MCC-link state.

Amazon requires before its data/agent stages can complete:

- an `Account Reference` on the property;
- one matching account block with marketplace and sales channel;
- Ads profile/account identifiers before live ingestion and activation.

Missing readiness/account/data fields do not authorize inference. The channel reference
states which scaffold work can safely precede them.

## Property-name validation

Treat the human-defined property name as opaque. Preserve its spelling and case exactly.
Validate only what is required for safe and deterministic use:

- not empty and not `.` or `..`;
- no `/`, `\`, control characters, or leading/trailing whitespace;
- unique within the channel, including case-insensitive comparison;
- no collision with a different existing folder or agent binding.

Do not change dots to underscores, add a marketplace suffix, transliterate characters,
or derive a “cleaner” slug. Channel systems may derive a separate technical identifier
where their API requires it; record that derived identifier in `data-sources.md` and
never rename the property because of it.

A property rename is a human-approved migration affecting Drive, Paperclip bindings,
data views, and potentially external systems. It is never an onboarding cleanup.

## Missing-property escalation

When no unique valid property exists for the requested channel:

- create no channel/property folders, documents, project, or agents;
- leave `client.md` untouched;
- comment with the exact missing or conflicting declaration;
- route the issue to the configured supervisor/human as `todo`.

Example:

> Customer `Bimmerle`, channel `Amazon`: `client.md` contains no approved Property
> block. Please add an exact `Property` beneath `### Amazon`. Status, Autonomy Level,
> and Account Reference will then be required before agent setup and activation
> readiness. I will rerun the same onboarding issue after the Property edit.

Never set the issue to `blocked`; the canonical routing rule lives in
`lx-paperclip-inbox-cycle`.
