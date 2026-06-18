# Common Errors & Remediation

Error lookup for Amazon Ads API mutations, plus the binding hard-stop rule. The *rule* is stable doctrine; the *exhaustive error table* depends on the live API.

> The Amazon Ads API uses **standard HTTP status codes** (the semantics below are stable); the exact error *body* messages vary by endpoint and are best extended from real run logs. Rate-limit specifics (429 + `Retry-After`, no remaining-quota header, dynamic limits) are confirmed against the official docs — see `bulk-and-rate-limits.md`. Do not invent error semantics; extend this table from logs.

## The hard-stop rule (binding — same as Google)

On any **unrecognized API error**, any **policy rejection** (`PROHIBITED` / disapproved), or anything not covered below: **hard stop — surface to the human, do not retry, do not invent a workaround.** Retrying blindly against money-bearing mutations is how spend leaks. When in doubt, escalate (reassign the run issue up + `todo` per `lx-paperclip-inbox-cycle`).

## Starter table (stable cases — extend from logs)

| Symptom | Likely cause | Remediation |
|---|---|---|
| `401 Unauthorized` / `403` | expired/invalid OAuth token; wrong profile scope | refresh token; confirm the `profileId` header matches the property's account; escalate if creds are missing (creds live in the secret store, never in Drive) |
| `429 Too Many Requests` | rate limit / throttle (dynamic, load-based) | honour the `Retry-After` header; where it's absent (`POST /reporting/reports`) use exponential back-off + jitter; chunk/serialize batches (`bulk-and-rate-limits.md`) — **not** a hard stop, it is expected. No remaining-quota header exists, so you must react to the 429 |
| `400` invalid field / validation | malformed payload, bad enum, missing parent ID | fix the payload; check `sp-object-model.md` for required fields & valid enums; do not retry unchanged |
| Partial-success batch (some items error) | per-item validation failures | parse the per-item response; retry only the fixed failures, never the whole batch |
| Duplicate object created | no idempotency; create re-run | pre-read the catalog by name before creating (`bulk-and-rate-limits.md`) |
| Policy rejection / `PROHIBITED` topic | ad/keyword content flagged | **hard stop** → surface to human; never work around policy |
| Campaign won't serve after enable | created `PAUSED` (intended) or budget/bid/eligibility issue | confirm the human enabled it; check budget > 0, ASIN in stock & buy-box (Phase 2), bids above floor |
| Naming-convention parse failure downstream | campaign name violates manifest §6 | the campaign drops out of ASIN-level reporting (`supabase-schema.md` "ASIN join") — fix the name; sanitize-then-truncate |

## Escalate (don't improvise) when
- Credentials/profile access missing or invalid (after one token refresh).
- A `PROHIBITED` policy topic or any disapproval.
- Any error not in the (verified) table.
- Repeated failure of the same mutation after a corrected retry.

## Cross-references
- Object/field contract: `sp-object-model.md`. Throttling/batching: `bulk-and-rate-limits.md`. Escalation mechanics: `lx-paperclip-inbox-cycle`.
