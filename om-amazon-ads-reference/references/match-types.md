# Match Types & Targeting Expressions

The targeting surfaces an SP campaign can use, and how they map to Lexacore doctrine. Keyword match-type values verified against live data (`BROAD`, `EXACT` present 2026-06-15; `PHRASE` valid but unused in the current pilot data).

## Keyword match types (MANUAL campaigns)

| Match type | Matches | Lexacore default use |
|---|---|---|
| `BROAD` | the term + variants, synonyms, related, re-orderings | **Research** — discovery in GEN/MRK/WTB Broad-Research campaigns (manifest §3) |
| `PHRASE` | the term as a phrase, in order, with words around it | optional middle ground; not a default in the manifest |
| `EXACT` | the term and close variants only | **Profit** — proven winners in Exact-Profit campaigns |

**Doctrine link (manifest §3):** Broad = Research, Exact = Profit. A term graduates Broad→Exact when it proves out, and is negated in its Broad/AUT source on graduation (manifest §4, owned by the positive Targeter).

## Negative keyword match types

| Type | Use |
|---|---|
| `NEGATIVE_EXACT` | **default** — clean isolation of one specific term (manifest §4) |
| `NEGATIVE_PHRASE` | blocks a phrase + surrounding words — **too broad**; avoid unless deliberately culling a family of queries |

## Product / category targeting expressions (the `expression` clause)

Used by manual targets (WTB competitor ASINs, GEN category targeting) and by AUT.

- **Manual product targeting:** `asin = "B0…"` — target a specific competitor/own ASIN's detail page. The WTB ASIN surface.
- **Manual category targeting:** `category = "<id>"`, optionally refined: `brand`, `price` range, `rating`, `prime shipping`. Generic-space targeting.
- **Auto targeting (AUT only, `expressionType = AUTO`):** the four Amazon clauses —
  - `close-match` — shopper searches closely matching the product
  - `loose-match` — loosely related searches
  - `substitutes` — shoppers viewing similar/competing products
  - `complements` — shoppers viewing complementary products
  Each is separately biddable; AUT's job is discovery (manifest §2/§3), feeding harvested terms to MRK/WTB/GEN.

## Negative product targeting

- Exclude a specific `asin` or `brand` from serving. Carries the cross-ASIN head-term negation (manifest §5, head term set negative-exact on sibling ASINs) and waste-ASIN exclusions (negative-targeting skill).

## Where the values live in the data

- Keyword match type: `…keywords_report_stream_daily."matchType"` (`BROAD`/`EXACT`).
- Target type: `sponsored_product_targetings."expressionType"` (`MANUAL`/`AUTO`); report side `…targets_report_stream_daily."keywordType"` (`TARGETING_EXPRESSION` = manual clause, `TARGETING_EXPRESSION_PREDEFINED` = AUTO clause).
- The catalog keyword table does **not** store match type — read it from the report stream or the create payload.
