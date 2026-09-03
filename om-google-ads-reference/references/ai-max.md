# AI Max for Search — API Reference

Load this file when an agent is asked to enable, configure, verify, or report on AI Max, or when
a Search campaign hits `CampaignError.CANNOT_SET_CAMPAIGN_KEYWORD_MATCH_TYPE`.

AI Max is **not a campaign type**. It is an optimisation layer switched on inside an existing
Search campaign. Everything below was verified against API **v23** on 2026-09-03.

## What the layer actually does

Three mechanisms, independently controllable:

1. **Search-term matching.** Keyword-less matching on top of the campaign's keywords. With AI Max
   on, all keywords behave as broad match regardless of their stored match type.
2. **Text customisation.** Google generates headlines and descriptions beyond the RSA assets.
3. **Final URL expansion.** Traffic is routed to whichever page on the domain the model judges
   more relevant than the ad's final URL.

## Enabling and the fields that govern it

| Field | Type | Meaning |
|---|---|---|
| `campaign.ai_max_setting.enable_ai_max` | bool | The master switch. |
| `campaign.ai_max_setting.bundling_required` | — | Read-only in practice; do not set. |
| `campaign.keyword_match_type` | enum (`BROAD` only) | **Superseded when AI Max is on.** Setting it alongside AI Max returns `CampaignError.CANNOT_SET_CAMPAIGN_KEYWORD_MATCH_TYPE`. Leave unset. |
| `ad_group.ai_max_ad_group_setting.disable_search_term_matching` | bool | Per-ad-group opt-out of mechanism 1 while the rest of AI Max stays on. |

### Creative and URL automation

Controlled through `campaign.asset_automation_settings`, a repeated message of
`{asset_automation_type, asset_automation_status}`. Status is `OPTED_IN` or `OPTED_OUT`.

| `asset_automation_type` | Governs |
|---|---|
| `TEXT_ASSET_AUTOMATION` | Mechanism 2 — generated headlines and descriptions. |
| `FINAL_URL_EXPANSION_TEXT_ASSET_AUTOMATION` | Text generated specifically for expanded landing pages. |

**Final URL expansion is opt-out, not opt-in.** Left alone it will send paid traffic to any
indexable page on the domain. For a lead-generation property with exactly one conversion page,
that is a defect, not a feature — constrain it before enabling AI Max, never after.

### Guardrails on generated text

`campaign.text_guidelines` holds two repeated fields:

| Field | Limit |
|---|---|
| `term_exclusions` | ≤ 30 characters each, max 25 entries |
| `messaging_restrictions` | ≤ 300 characters each, max 40 entries |

Use `term_exclusions` for words the generated copy must never contain. Any property with binding
price or claim wording (exact package prices, "no percentage fee", regulated claims) belongs here
— or keeps `TEXT_ASSET_AUTOMATION` on `OPTED_OUT` entirely, which is the safer default when the
landing page fixes the wording.

### Brand and landing-page control

Brand inclusions/exclusions and page restrictions are set as ad-group criteria — page targeting
via `AdGroupCriterion.webpage` (`WebpageInfo`). Apply these **in the same change** that enables
AI Max, not as a follow-up.

## Preconditions — check before proposing AI Max

AI Max widens matching and creative at the same time. It needs signal to steer by and budget to
absorb the learning phase. Verify all three; two out of three is not enough.

| Precondition | How to check | Threshold |
|---|---|---|
| Conversion signal | `conversion_action` with `primary_for_goal = TRUE` and real recorded conversions | Meaningful volume, not a configured-but-never-fired action |
| Budget headroom | `campaign_budget.amount_micros` against `metrics.average_cpc` for the head terms | Daily budget must clear several clicks, not a fraction of one |
| Room to widen | current match types | Exact/phrase-heavy campaigns benefit; already-broad campaigns have little to gain |

For lead generation specifically: without confirmed conversion tracking, AI Max optimises toward
a signal that does not exist and drifts up-funnel. **A campaign whose primary conversion action
has never fired is not a candidate.**

Enabling AI Max on a live campaign is a material change to matching, creative, and landing pages
at once. It is not a reversible bid tweak — it belongs to the human decision layer, not to an
optimizer's routine autonomy. See `om-autonomy-levels`.

## Verification

After enabling:

```sql
SELECT
  campaign.id,
  campaign.name,
  campaign.ai_max_setting.enable_ai_max,
  campaign.keyword_match_type,
  campaign.asset_automation_settings,
  campaign.text_guidelines.term_exclusions,
  campaign.text_guidelines.messaging_restrictions
FROM campaign
WHERE campaign.id = {campaign_id}
```

Expect `enable_ai_max = true`, `keyword_match_type = UNSPECIFIED`, and an explicit
`OPTED_IN`/`OPTED_OUT` entry for each automation type you intended to control. An automation type
absent from the list is **not** proof it is off — read the campaign back and confirm the entry
exists.

Per-ad-group opt-out:

```sql
SELECT ad_group.id, ad_group.name, ad_group.ai_max_ad_group_setting.disable_search_term_matching
FROM ad_group
WHERE ad_group.campaign = 'customers/{cid}/campaigns/{campaign_id}'
```

## Reporting

| Resource | Content |
|---|---|
| `ai_max_search_term_ad_combination_view` | Performance per combination of search term, headline, and landing page — the only place the three are joined. Requires a date filter. |
| `final_url_expansion_asset_view` | Which expanded URLs served. Requires at least one filter, otherwise the query is rejected. |

The Supabase views in `references/supabase-schema.md` do **not** carry these resources. AI Max
reporting is GAQL-only until the nightly sync is extended.

## Maintenance

Contract layer — field names and limits only. Performance expectations, vertical experience, and
whether AI Max is worth switching on for a given property belong in Drive `KI-Wissen/Google`.
