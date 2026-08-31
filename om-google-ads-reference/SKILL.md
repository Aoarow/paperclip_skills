---
name: om-google-ads-reference
description: Stable Google Ads API reference and specification for all Online Marketing agents — field types, character limits, asset specs, listing-group construction, bidding-strategy compatibility, GAQL verification queries, and error remediation. The shared spec/contract layer used by both campaign creation (Peggy) and the optimizer agents. Use whenever an agent needs the exact, binding API contract for building, changing, or verifying a Google Ads structure. Evolving best practice and experience live in Drive KI-Wissen/Google, not here.
---

# Google Ads — Shared Reference

> **Where this skill's reference files actually are.** Paperclip copies only this `SKILL.md` into
> the agent runtime — the `references/` folder is not delivered with it, and the runtime folder
> carries a hash suffix. A relative `references/<file>` path therefore does **not** resolve.
> Read them from the filesystem instead:
>
> **`/srv/lexacore-skills/om-google-ads-reference/references/<file>`**
>
> That path is readable for the agent user and is kept current from git. Progressive disclosure is
> unchanged — open the one file you need, not all of them.


The binding spec layer for every Google Ads agent. This skill holds **no procedures of
its own** — it is a reference index. The procedures that use these files live in the
consuming skills: `om-google-campaign-creation` (building campaigns) and
`om-google-optimization` (optimizing live campaigns).

Load only the file you need (progressive disclosure); do not read them all up front.

## Reference files

- `references/search-rsa-spec.md` — Responsive Search Ad field reference, customizer tags, pinning conventions.
- `references/pmax-asset-types.md` — Performance Max asset-type / field-type matrix, image specs, the bulk-mutate rule.
- `references/demand-gen-formats.md` — Demand Gen ad-format specs and asset-automation behaviour.
- `references/shopping-listing-groups.md` — Shopping product-partition (listing group) tree construction.
- `references/bidding-strategies.md` — bidding-strategy fields, compatibility matrix, conversion-data thresholds, migration path.
- `references/gaql-verification-queries.md` — canonical post-mutation verification queries per campaign type.
- `references/common-errors.md` — error-code lookup with remediation steps.

## Maintenance
This is the contract layer — it changes when the Google Ads API changes, and is edited by
humans / devs only. Evolving best practice and experience belong in Drive
`KI-Wissen/Google` (Research-maintained), never here.
