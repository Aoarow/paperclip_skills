# Common Errors — Lookup & Remediation

Load this file when a Google Ads API mutate or read returns an error and you need to identify the cause and the fix. The error is found in `GoogleAdsFailure.errors[].error_code.<error_enum>`.

## How Google Ads API errors are structured

A failed request returns a `GoogleAdsFailure` with one or more `GoogleAdsError` entries. Each error has:

- `error_code` — a `oneof` field naming the error enum (e.g. `field_error`, `policy_violation_error`, `asset_group_error`).
- `message` — human-readable description.
- `trigger` — the value that triggered the error (when applicable).
- `location` — points to the operation index in the request that failed.
- `details` — for policy errors, contains `PolicyViolationDetails` or `PolicyFindingDetails`.

In partial-failure requests (`partial_failure = true`), failed operations are reported in `mutate_response.partial_failure_error` while successful operations still apply.

## Authentication & authorisation

| Error                                                    | Cause                                                                     | Fix                                                                                            |
|----------------------------------------------------------|---------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------|
| `AuthenticationError.CLIENT_CUSTOMER_ID_INVALID`         | Customer ID format wrong                                                  | Use 10-digit ID with no dashes                                                                |
| `AuthenticationError.NOT_ADS_USER`                       | The Google account is not linked to any Ads account                       | Check the OAuth account; switch to one with Ads access                                        |
| `AuthorizationError.USER_PERMISSION_DENIED`              | The authenticated user lacks access to the target customer                | Grant access in Google Ads admin or switch users                                              |
| `AuthorizationError.DEVELOPER_TOKEN_NOT_APPROVED`        | Dev token still in basic / pending state                                  | Apply for standard access; basic tokens cannot mutate production accounts                      |
| `HeaderError.LOGIN_CUSTOMER_ID_INVALID`                  | Missing or wrong `login-customer-id` when operating under an MCC          | Set `login-customer-id` to the MCC customer ID                                                |

## Quota & rate limits

| Error                                                      | Cause                                            | Fix                                                                                      |
|------------------------------------------------------------|--------------------------------------------------|------------------------------------------------------------------------------------------|
| `QuotaError.RESOURCE_EXHAUSTED`                            | Hit a per-account or per-developer-token quota   | Back off exponentially and retry; check the quota dashboard                              |
| `QuotaError.RESOURCE_TEMPORARILY_EXHAUSTED`                | Transient throttle                               | Retry after a short delay (typically 1–5 s)                                              |
| `InternalError.TRANSIENT_ERROR`                            | Backend hiccup                                   | Retry with exponential backoff up to 3 attempts                                          |

## Account-state errors

| Error                                                                          | Cause                                                                         | Fix                                                                                            |
|--------------------------------------------------------------------------------|-------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------|
| `CustomerError.CUSTOMER_NOT_ENABLED`                                           | Account is suspended or not yet enabled                                       | Resolve in the Google Ads UI; the API will not unblock this                                   |
| `BillingSetupError.BILLING_SETUP_NOT_COMPLETE`                                 | No payment method on the account                                              | Human must add billing in the UI                                                              |
| `MutateError.EU_POLITICAL_ADVERTISING_DECLARATION_REQUIRED` (from Apr 1, 2026) | One or more campaigns have no `contains_eu_political_advertising` declaration | Declare existing campaigns before any other mutate; reporting calls remain unaffected         |

The EU political advertising declaration is a 2026-specific gate. Until every campaign in the account has an explicit `contains_eu_political_advertising` value (`TRUE` or `FALSE`), all campaign-management mutates will fail. Resolution sequence:

```sql
SELECT campaign.id, campaign.name, campaign.contains_eu_political_advertising
FROM campaign
WHERE campaign.contains_eu_political_advertising = UNSPECIFIED
```

Then update each one with the correct declaration (almost always `FALSE` for commercial advertisers).

## Budget & bidding

| Error                                                            | Cause                                                                  | Fix                                                                          |
|------------------------------------------------------------------|------------------------------------------------------------------------|------------------------------------------------------------------------------|
| `CampaignBudgetError.NON_MUTABLE_BUDGET`                         | Trying to modify a system-managed budget                               | Create a new explicit budget instead                                         |
| `CampaignBudgetError.MONEY_AMOUNT_TOO_LARGE`                     | Budget exceeds account limit                                           | Reduce the amount; check account currency conversion                         |
| `BiddingStrategyError.CANNOT_REMOVE_ASSOCIATED_STRATEGY`         | Trying to delete a strategy still in use                               | Unlink campaigns first                                                       |
| `BiddingError.BIDDING_STRATEGY_NOT_AVAILABLE_FOR_ACCOUNT_TYPE`   | Strategy not allowed on this account type                              | Pick a compatible strategy (see `bidding-strategies.md`)                     |

## Campaign-creation errors

| Error                                                      | Cause                                                                                          | Fix                                                                                          |
|------------------------------------------------------------|------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------|
| `CampaignError.CANNOT_SET_BOTH_TRACKING_TEMPLATE_AND_TRACKING_SETTING_URL` | Conflicting URL fields on the campaign                                                         | Pick one; usually `tracking_url_template`                                                   |
| `CampaignError.INVALID_TRACKING_URL`                       | Tracking URL doesn't expand correctly                                                          | Validate ValueTrack parameters; test with the URL validator                                  |
| `CampaignError.REQUIRED_BUSINESS_NAME_ASSET_NOT_LINKED`    | Brand-guidelines-enabled PMax campaign missing `BUSINESS_NAME` `CampaignAsset`                 | Add the BUSINESS_NAME as a `CampaignAsset` in the same mutate                                |
| `CampaignError.REQUIRED_LOGO_ASSET_NOT_LINKED`             | Brand-guidelines-enabled PMax campaign missing `LOGO` `CampaignAsset`                          | Add a square logo as a `CampaignAsset` in the same mutate                                    |

## Performance Max asset group errors

These are the most common failures when building PMax. They almost all stem from the bulk-mutate rule (asset group + minimum required assets must arrive together).

| Error                                                         | Cause                                                              | Fix                                                                                       |
|---------------------------------------------------------------|--------------------------------------------------------------------|------------------------------------------------------------------------------------------|
| `AssetGroupError.NOT_ENOUGH_HEADLINE_ASSET`                   | < 3 HEADLINE field-type assets linked                              | Add headlines in the same mutate; minimum 3                                              |
| `AssetGroupError.NOT_ENOUGH_LONG_HEADLINE_ASSET`              | < 1 LONG_HEADLINE                                                  | Add at least 1 long headline (≤ 90 chars)                                                |
| `AssetGroupError.NOT_ENOUGH_DESCRIPTION_ASSET`                | < 2 DESCRIPTION                                                    | Add at least 2 descriptions                                                              |
| `AssetGroupError.NOT_ENOUGH_BUSINESS_NAME_ASSET`              | Missing BUSINESS_NAME                                              | Add 1 BUSINESS_NAME (≤ 25 chars); or set as `CampaignAsset` if brand_guidelines_enabled  |
| `AssetGroupError.NOT_ENOUGH_MARKETING_IMAGE_ASSET`            | Missing 1.91:1 landscape image                                     | Add ≥ 1 MARKETING_IMAGE meeting the 1.91:1 spec                                          |
| `AssetGroupError.NOT_ENOUGH_SQUARE_MARKETING_IMAGE_ASSET`     | Missing 1:1 square image                                           | Add ≥ 1 SQUARE_MARKETING_IMAGE (≥ 300×300 px)                                            |
| `AssetGroupError.NOT_ENOUGH_LOGO_ASSET`                       | Missing logo                                                       | Add ≥ 1 LOGO (1:1, ≥ 128×128 px)                                                         |
| `AssetGroupError.ASSET_GROUP_NAME_DUPLICATED`                 | Two asset groups with the same name within the campaign            | Rename                                                                                   |
| `AssetGroupAssetError.INVALID_FIELD_TYPE`                     | Asset doesn't match the declared field type (e.g. text used for image field) | Re-upload as the correct asset type                                              |

## Ad-level errors

| Error                                                       | Cause                                                          | Fix                                                                                |
|-------------------------------------------------------------|----------------------------------------------------------------|-----------------------------------------------------------------------------------|
| `AdError.LINE_TOO_WIDE`                                     | Headline / description exceeds character limit                 | Trim text; check double-width language counting                                   |
| `AdError.AD_CUSTOMIZERS_NOT_SUPPORTED_FOR_AD_TYPE`          | Customizer used in an ad type that doesn't support them        | Remove the customizer tags or change ad type                                      |
| `AdError.TOO_MANY_OCCURRENCES_OF_AD_CUSTOMIZER_TAG`         | Same customizer used too many times                            | Use distinct customizers                                                          |
| `AdError.FINAL_URL_MUST_NOT_BE_SET`                         | Final URL set on a sub-asset where it's not allowed            | Move the URL to the correct level                                                 |
| `AdError.FINAL_URLS_NOT_SET`                                | No final URL on an ad that requires one                        | Add `final_urls` with at least one entry                                          |
| `ResponsiveSearchAdError.HEADLINES_AT_LEAST_THREE`          | < 3 headlines                                                  | Provide at least 3 unique headlines                                               |
| `ResponsiveSearchAdError.DESCRIPTIONS_AT_LEAST_TWO`         | < 2 descriptions                                               | Provide at least 2 unique descriptions                                            |
| `ResponsiveSearchAdError.PINNED_FIELD_NOT_SET`              | Pinning set incorrectly                                        | Verify `pinned_field` is a valid `ServedAssetFieldType` for the asset type        |

## Policy violations

Policy errors are not raw API errors — they come back as `PolicyViolationError` with structured `PolicyViolationDetails`. The flow:

1. First mutate attempt fails with `PolicyFindingError.POLICY_FINDING`.
2. The error's `details` contain `PolicyFindingDetails.policy_topic_entries`, each with a `topic` and `type` (e.g. `PROHIBITED`, `LIMITED`).
3. For `LIMITED` topics that are exemptible, the agent **may** resubmit the same mutate with `policy_validation_parameter.ignorable_policy_topics` populated — this requests human review under exemption.
4. `PROHIBITED` topics are never exemptible. Surface to the human; do not retry.

```
PolicyTopicEntry.type values:
  PROHIBITED       → ad/keyword cannot run; not exemptible
  LIMITED          → can run with restrictions or after review; sometimes exemptible
  FULLY_LIMITED    → severely restricted; usually not exemptible
  DESCRIPTIVE      → informational only
  SUGGESTION       → informational, performance hint
```

**Convention for this skill:** when a policy error returns, never silently submit an exemption request. Always surface the policy topics to the human and let them decide whether to request an exemption.

## Keyword errors

| Error                                                  | Cause                                                | Fix                                                          |
|--------------------------------------------------------|------------------------------------------------------|--------------------------------------------------------------|
| `KeywordPlanIdeaError.KEYWORD_HAS_INVALID_CHARS`       | Disallowed characters in keyword                     | Remove `!`, `@`, `*`, etc.                                  |
| `CriterionError.KEYWORD_TOO_LONG`                      | Keyword > 80 chars or > 10 words                     | Shorten                                                      |
| `CriterionError.INVALID_KEYWORD_TEXT`                  | Malformed match-type syntax                          | Use match_type enum, not bracket / quote syntax              |
| `CriterionError.CANNOT_ADD_DUPLICATE_CRITERION`        | Duplicate keyword in the ad group                    | Deduplicate before sending                                   |

## Shopping & Merchant Center errors

| Error                                                      | Cause                                                       | Fix                                                                       |
|------------------------------------------------------------|-------------------------------------------------------------|---------------------------------------------------------------------------|
| `ShoppingError.MERCHANT_ID_CANNOT_BE_CHANGED`              | Trying to change the linked MC account on a live campaign   | Create a new campaign                                                     |
| `ShoppingError.SUBDIVISION_REQUIRES_OTHERS_CASE_VALUE`     | Listing group subdivision missing the "other" catch-all     | Add a child node with `case_value = null` at that level                  |
| `ShoppingError.LISTING_GROUP_UNIT_CANNOT_HAVE_CHILDREN`    | A `UNIT` leaf has child nodes                               | Change to `SUBDIVISION` or remove the children                            |
| `ShoppingError.SAME_CAMPAIGN_PRIORITY_FOR_DUPLICATE_CAMPAIGNS` | Two shopping campaigns sharing the feed with same priority | Differentiate priorities (LOW / MEDIUM / HIGH)                            |

## Resource-state errors

| Error                                                   | Cause                                                                   | Fix                                                                            |
|---------------------------------------------------------|-------------------------------------------------------------------------|-------------------------------------------------------------------------------|
| `ResourceCountLimitExceededError`                       | Account limit hit (e.g. 10,000 campaigns, 20,000 ad groups per campaign) | Archive unused resources; the account-level limit cannot be raised             |
| `MutateError.RESOURCE_NOT_FOUND`                        | Referenced resource (campaign, ad group, asset) doesn't exist           | Verify temp resource names are consistent within the mutate                    |
| `MutateError.ID_EXISTS_IN_MULTIPLE_MUTATES`             | Same resource name used twice in one mutate                             | Deduplicate operations                                                         |
| `MutateError.INCONSISTENT_FIELD_VALUES`                 | Fields set on the same resource conflict between operations             | Consolidate into one operation                                                 |

## Version-drift errors (2026)

The API moved to monthly releases in January 2026. Drift problems show up as:

| Error                                                  | Cause                                                              | Fix                                                                                      |
|--------------------------------------------------------|--------------------------------------------------------------------|-----------------------------------------------------------------------------------------|
| `RequestError.UNKNOWN`                                 | Field used that doesn't exist in the requested version             | Pin the API version explicitly; do not rely on the client library default               |
| `FieldMaskError.FIELD_NOT_FOUND`                       | Update mask references a deprecated or moved field                  | Check the release notes for the version; refactor the mask                              |
| `CallAd` / `CallAdInfo` references in v23+            | Removed in v23                                                     | Use call assets via `CallAsset` resource instead                                        |
| `QueryError.UNRECOGNIZED_FIELD` on `campaign.start_date` / `campaign.end_date` | Both removed in v23 | Use `campaign.start_date_time` / `campaign.end_date_time` (datetime, not date) |
| `QueryError.UNRECOGNIZED_FIELD` on `campaign.conversion_goal_campaign_config.*` | The whole sub-message is gone from `Campaign` in v23 | Query the `campaign_conversion_goal` resource instead — see GAQL reference §9 |
| `QueryError.INVALID_VALUE_WITH_DURING_OPERATOR` | A date literal that does not exist, almost always `LAST_90_DAYS` | Use one of the twelve valid literals, or `segments.date BETWEEN 'YYYY-MM-DD' AND 'YYYY-MM-DD'` |
| `CampaignError.CANNOT_SET_CAMPAIGN_KEYWORD_MATCH_TYPE` | `campaign.keyword_match_type` set while AI Max is enabled | Leave it unset — AI Max supersedes it. See `references/ai-max.md` |
| `QueryError.UNRECOGNIZED_FIELD` on `asset_group_asset.performance_label` | Removed in v23 | Use `asset_group_asset.primary_status` and `primary_status_reasons` |
| `QueryError.UNRECOGNIZED_FIELD` on `asset.business_name_asset.*` | No such asset type — `BUSINESS_NAME` is a plain text asset | Select `asset.text_asset.text` and filter on `field_type = 'BUSINESS_NAME'` |
| `QueryError` *"may not be used in SELECT clause"* | A message field selected instead of its leaf (`asset_group_signal.audience`, `listing_group.case_value`) | Select the leaf: `…audience.audience`, `…case_value.product_type.value` |
| `QueryError` *"must be present in SELECT clause: campaign.id"* | `campaign_asset` filtered on `campaign.id` without selecting it | Add `campaign.id` to the `SELECT` — this resource is stricter than the others |

## Reading partial-failure responses

When a mutate is sent with `partial_failure = true`:

- Successful operations apply and return resource names.
- Failed operations populate `mutate_response.partial_failure_error.errors[]`.
- Each error's `location.field_path_elements` points to the failed operation's index in the request.

Use partial failure for batch imports where one bad row should not block the rest. Do **not** use it for the initial PMax bulk mutate — there, atomicity matters (the asset group either exists with its minimum assets or doesn't exist at all).

## Escalation rule

Any error not in this reference, or any policy `PROHIBITED` topic, is a hard stop. Surface the error to the human with:

- The error enum name
- The trigger value (if any)
- The location in the request
- A plain-language summary of what was being attempted

Do not retry. Do not invent a workaround.
