# Bulk Operations & Rate Limits

How to create/update SP structures at scale without tripping the Amazon Ads API. The Lexacore structure scales **linearly** (N ASINs × ≥4 strategies × campaign+adgroup+ad+keywords+negatives), so bulk creation (the Account Manager's campaign-creation skill) is the main pressure point.

> **Key fact (authoritative, Amazon Ads API docs):** rate limits are **dynamic — based on real-time system load — and Amazon does not publish fixed per-second/per-day numbers.** There is therefore no "correct limit" to hard-code. Design for the throttle *signal*, not a fixed budget. (This is unlike the SP-API and the Product Advertising API, which do publish/expose numbers — do not carry their figures over.)

## The throttle signal (stable, documented)

- Throttling returns **HTTP `429` (Too Many Requests)**.
- The response carries a **`Retry-After`** header (seconds to wait) — honour it.
- **Exception:** the `Retry-After` header is **not** present on `POST /reporting/reports` (the async report-request endpoint) — fall back to your own exponential backoff there.
- The Amazon Ads API does **not** expose `x-amzn-RateLimit-Limit` / `-Remaining` headers (the SP-API does; the Ads API does not) — you cannot read remaining quota ahead of time, so you must react to 429s.
- Rate-limit **scope** (per Client ID vs. per refresh token / per profile) is not crisply documented and has open community questions — assume it can bind at the client-application level and pace the whole integration, not just one property.

## Documented best practices (Amazon's own recommendations)

- **Exponential backoff with jitter on `429` and `5xx`.** Retry the throttled/failed items, not the whole world.
- **Avoid `list*Extended` operations** — they carry roughly **5× the throttling weight** of the plain `list`. Use them only when you genuinely need the extended fields.
- **Prefer `/exports` over paginated `list`** for bulk entity retrieval (pulling all campaigns/keywords/targets): the async export is far lighter on the rate limiter than walking pages.
- **Pin the API version** in the client config; the Ads API evolves — never rely on a library default.

## Object creation model (stable)

- SP management uses **JSON batch endpoints**: campaigns, ad groups, product ads, keywords, targets, and negatives each accept a **list** in one request and return a **per-item success/error** result — **partial success is normal** (a batch can half-succeed).
- **Build top-down, respecting parent references:** Campaign → Ad Group → (Product Ad, Keywords, Targets, Negatives). A child needs its parent's ID.
- **Idempotency:** there is no natural dedup — re-running a create makes duplicates. Guard with a pre-read of the catalog (does this campaign name already exist?) before creating.

## Handling throttling & partial failure (practice)

- Respect `429` + `Retry-After`; back off exponentially with jitter where the header is absent.
- **Chunk large creates** into modest batches and **serialize** them rather than firing all at once; a full property build is many objects (manifest §3 "campaign count") — pace it.
- **Always parse the per-item response.** Log which items succeeded/failed with their error; retry only the failed items after fixing the cause, never the whole batch blindly.
- **Verify after create** by reading the catalog back (the create-skill's verification step) — do not trust the create response alone.

## Object-count ceilings
Per-account/-campaign object ceilings (campaigns per account, keywords per ad group, etc.) do exist but are not consolidated in one public table and can change. Treat a `400`/limit error as the authority and surface it; do not pre-encode a number that may be stale.

## Sources
- Amazon Ads API — Rate limiting (concept): https://advertising.amazon.com/API/docs/en-us/reference/concepts/rate-limiting
- Amazon Ads API — Developer notes: https://advertising.amazon.com/API/docs/en-us/get-started/developer-notes
- (Pages are JS-rendered; not mirrored as markdown in `amzn/ads-advanced-tools-docs`. Re-check the live pages when revising.)

## Cross-references
- Object shapes & IDs: `sp-object-model.md`. Error handling / hard-stop rule: `common-errors.md`. What gets built: `om-amazon-campaign-creation` + manifest §1–§6.
