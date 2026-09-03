# Negative Keywords — Spec Reference

Load this file when building a negative-keyword structure, or when a search-term review produces
terms to exclude. Verified against the live API on 2026-09-03.

## The rule that quietly breaks most negative lists

**Negative keywords do not match close variants.** No plurals, no inflections, no misspellings,
no synonyms — for all three match types. This is the opposite of positive keywords, and it is the
single most common reason a negative list does nothing.

| Negative (broad) | blocks | does **not** block |
|---|---|---|
| `kurs` | "google ads kurs" | kurse, kursen |
| `kostenlos` | "ads tool kostenlos" | kostenlose, kostenloser |
| `schulung` | "ads schulung" | schulungen |

**Every negative is entered in all its relevant forms.** Singular and plural are two entries. A
negative without its inflections is half a negative.

Second counter-intuitive point: for negatives, **broad is the narrowest type** with respect to
variants, not the widest. Negative broad means "the query contains all these words, in any
order" — not "and anything similar".

| Match type | Blocks |
|---|---|
| `BROAD` | queries containing all the words, any order, no variants |
| `PHRASE` | queries containing the exact word sequence, no variants |
| `EXACT` | only that exact query |

## Three levels, not one list

Mixing universal junk with judgement calls produces a list nobody can reason about once it passes
a few hundred entries. Separate by who owns the decision and how often it is revisited.

| Level | Mechanism | Contents | Revisited |
|---|---|---|---|
| Account | `SharedSet` type **`ACCOUNT_LEVEL_NEGATIVE_KEYWORDS`** | universal junk: adult, image/photo intent, obvious nonsense | never |
| Reusable | `SharedSet` type `NEGATIVE_KEYWORDS` + `CampaignSharedSet` | intent exclusions for a class of client (job, ausbildung, praktikum, kurs, tutorial, vorlage, "selber machen") | per client onboarding |
| Campaign | `campaign_criterion.keyword` with `negative = true` | client-specific: competitor terms, services not offered | weekly, from search terms |

`ACCOUNT_LEVEL_NEGATIVE_KEYWORDS` needs **no** campaign link — it applies account-wide the moment
it exists. That is what makes it the right home for "always exclude": there is nothing to forget
to attach.

A plain `NEGATIVE_KEYWORDS` shared set does nothing until linked through `CampaignSharedSet`.
Creating the set and forgetting the link is a silent failure — verify the link, not the set.

## Resources

```
SharedSet          name, type_, status, member_count, reference_count
SharedCriterion    shared_set, keyword{text, match_type}, type_
CampaignSharedSet  campaign, shared_set, status
```

Shared sets are **campaign-level only** — there is no ad-group equivalent. Ad-group negatives go
on `ad_group_criterion` directly.

## Limits

- 5,000 negatives per shared set
- 1,000 account-level negatives
- 20 shared sets per account

Google has intermittently accepted lists over 5,000 since 2025 without confirming a policy
change. Do not design against the higher number.

## Negatives come from observation, not imagination

Invented lists are insurance; the return is in the weekly `search_term_view` review. Insurance is
cheap and worth having — especially alongside broad match — but it is never where the effort
goes.

**Before excluding a term, check that it really sits outside the offer.** Price-adjacent words
are the classic trap: for an advertiser competing on transparent, predictable pricing, "günstig"
or "billig" describes the target customer, not a time-waster. `kostenlos` excludes someone who
intends to pay nothing; `günstig` excludes someone who intends to pay carefully. Those are not
the same person.

## Verification

```sql
SELECT shared_set.id, shared_set.name, shared_set.type, shared_set.status,
       shared_set.member_count, shared_set.reference_count
FROM shared_set WHERE shared_set.status != 'REMOVED'
```

```sql
SELECT campaign.name, shared_set.name, campaign_shared_set.status
FROM campaign_shared_set WHERE campaign.id = {campaign_id}
```

`reference_count = 0` on a `NEGATIVE_KEYWORDS` set means it is linked to nothing and is having no
effect — the most common silent failure in this area.
