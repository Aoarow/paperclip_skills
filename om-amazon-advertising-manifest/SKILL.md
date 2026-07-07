---
name: om-amazon-advertising-manifest
description: The strategic doctrine and binding conventions for how Amazon advertising is structured at Lexacore. Defines the campaign model (1 campaign = 1 ad group = 1 ASIN), the four Sponsored Products strategies (Own Brand / Competitor / Generic / Auto), the Research vs. Profit goal model, the campaign naming convention, the negation invariants that keep search-term attribution clean, and head-term ownership across a brand's ASINs. Read this BEFORE creating, naming, optimizing, or adding keywords/negatives to any Amazon campaign — every Amazon ad agent (creation, optimization, positive and negative targeting) consumes these rules. This is the WHAT/WHY/rules layer; the exact API contract lives in om-amazon-ads-reference.
---

# Amazon Advertising — The Lexacore Manifest

This skill is the **single source of truth for Amazon advertising doctrine** at Lexacore. It is a hybrid skill: strategic philosophy *plus* the binding conventions (naming, strategy split, negation web, head-term ownership) that every Amazon ad agent must follow. Procedures (how to *do* a thing via the API) live in the consuming skills; the *rules they must obey* live here.

Phase 1 covers **Sponsored Products**; Sponsored Brands and Sponsored Display are placeholders (§7), to be expanded later (architecture memo §12).

## Who consumes this skill

- `om-amazon-campaign-creation` — strategy split (§2), naming convention (§6), negation web (§4) at build time.
- `om-amazon-optimization` — the R/P tag (§3) as a bidding input.
- `om-amazon-positive-targeting` — negation-maintenance invariant (§4), graduation rules (§3), head-term enforcement (§5).
- `om-amazon-negative-targeting` — the negation rules (§4) for waste negatives.

---

## 1. General rules

1. A campaign normally contains one ad group (the default "Anzeigengruppe 1").
2. A campaign normally advertises exactly one ASIN.
3. Each ASIN normally has at least one Sponsored Products campaign in each strategy — Own Brand (MRK), Competitor (WTB), Generic (GEN), and Auto (AUT). Higher-priority products may carry more campaigns (see §3, *Match type and goal*).

---

## 2. Sponsored Products — strategies

### Own Brand (MRK)
MRK campaigns use keywords related to our own brand (including variants) to reach shoppers who are already searching for the brand. Side effect: a defensive component that makes it harder for competitors to bid on our brands.

**Examples**

| Positive keyword | Negative keyword |
|:--|:--|
| Apple iPhone | cheap |
| Apple phone | feature phone |
| Apple iPhone 17 | case |

### Competitor (WTB)
WTB campaigns target specific competitors on our advertised ASIN — both by keyword and by ASIN.

**Examples**

| Positive keyword | Negative keyword |
|:--|:--|
| Samsung Galaxy | cheap |
| Google phone | feature phone |
| Nokia phone | case |

### Generic (GEN)
GEN campaigns target the generic product term for the advertised ASIN. Generic terms by their nature — the brand and competitor terms used in MRK and WTB are **structurally excluded** here (added as negatives), so each term runs in only one strategy. Where several ASINs of the same brand share a generic space, a high-volume head term is **not** bid on by every product — it is concentrated on a single owning ASIN (see §5, *Head-term ownership*), and the siblings target long-tail generics.

**Examples**

| Positive keyword | Negative keyword |
|:--|:--|
| smartphone | cheap |
| mobile phone | feature phone |
|  | case |
|  | Apple iPhone |
|  | Samsung Galaxy |
|  | Google phone |

### Auto (AUT)
The AUT campaign uses Amazon's automatic targeting to surface new search terms that can later be built into the MRK, WTB, or GEN campaigns. It is the widest discovery surface.

**All positive keywords of the MRK, WTB, and GEN campaigns are listed as negative keywords in the AUT campaign.** This keeps terms cleanly attributable, because a term is never served by more than one strategy at a time.

---

## 3. Match type and goal (Research vs. Profit)

Two fields in the nomenclature express *how* a campaign is run: match type (Broad / Exact / Auto) and goal (R = Research / P = Profit). They work as a pair.

**Goal (R/P) sets intent and bidding posture:**
- **Research (R)** — discover and validate search terms. Looser ACOS ceiling: we accept a higher cost to buy data. Winners are harvested into Profit campaigns.
- **Profit (P)** — scale proven winners efficiently, against a strict ACOS target.

**Match type couples to the goal by default:**
- **Broad = Research** — wide matching to surface converting variations.
- **Exact = Profit** — locked to proven terms for efficient scaling.
- **Auto (AUT) = Research** — automatic targeting, the widest discovery surface. AUT always carries the goal `R` and the match-type token `Auto` (it has no Broad/Exact keyword match type).
- The off-diagonal combinations (Exact-Research, Broad-Profit) are reserved for deliberate exceptions and are not used by default.

**Discovery → harvest funnel:**
AUT and Broad-Research campaigns discover converting search terms. A proven term graduates into the Exact-Profit campaign of the matching strategy as an exact keyword — and is simultaneously negated in its source campaign (see §4, *Negation rules*). This is how the Profit layer fills over time.

**Per strategy (default):**
- **MRK / WTB** — core terms are known and high-intent → primarily Exact-Profit. A Broad-Research campaign may be added to discover brand/competitor variations and new competitor ASINs.
- **GEN** — the largest discovery space → uses both: Broad-Research to mine generic queries, Exact-Profit for proven generic winners.
- **AUT** — always Auto-Research; feeds all of the above.

**Campaign count follows from this:**
- Baseline (every ASIN): one campaign per strategy, discovery-led — a new ASIN starts Research-heavy because there are no proven winners yet.
- Higher-priority products add the Exact-Profit harvest campaigns (and may split further); this is the source of the "more than four campaigns" case.

**Bidding link:** the R/P tag is an input to the Optimizer's bidding engine — Research campaigns are bid against a looser target-ACOS band, Profit campaigns against a strict one. The tag is not only for reporting; it drives bids.

---

## 4. Negation rules

Each search term should be active in exactly one strategy ("clean attribution"). The negation web enforces this.

**Static invariant (must always hold):**
- GEN negates all positive keywords **and ASINs** of MRK and WTB → GEN serves only purely generic terms.
- AUT negates all positive keywords **and ASINs** of MRK, WTB, and GEN → AUT discovers only genuinely new terms.
- MRK and WTB are treated as disjoint by nature (own brand vs. competitor) and are **not** mutually negated by default. Revisit if comparison terms (e.g. "Windspiel vs. …") cause overlap.

**Maintenance (a continuous invariant — owned by the positive Targeter agent):**
- **On add:** a new positive in MRK/WTB is immediately added as a negative in GEN **and** AUT; a new positive in GEN is added as a negative in AUT.
- **On remove:** when a positive is removed, its corresponding negatives elsewhere must also be removed — otherwise an orphaned negative blocks the term permanently and prevents it from flowing back into discovery/GEN.
- **Negative match type:** use **negative exact** for clean isolation of a specific term; negative phrase blocks too broadly.

---

## 5. Head-term ownership (killer keywords)

Some search terms are "killer keywords" — a single head term used by the large majority of searchers (e.g. "Gin" for the gin category). They are high-volume, expensive, and highly competitive.

**Rule:** within a brand, a head term is assigned to exactly **one owning ASIN** — normally the hero product (best-known, best-selling, highest conversion rate). All other ASINs of the brand use long-tail terms instead (e.g. "Pfeffer Gin", "Grapefruit Gin").

**Why:** bidding several of the brand's own products on the same head term causes self-competition (we drive up our own CPCs) and dilutes budget, so no product builds the sales velocity needed to rank. Concentrating the head term on the hero maximizes its conversion rate and ranking; broad searchers are served best by the hero, while long-tail searchers are served better by the matching niche product anyway.

**Enforcement (extends the Negation rules):** the head term is positive only in the owning ASIN's campaign and is set as a **negative exact** on all sibling ASINs (GEN and AUT) of the same brand. This is the existing negation invariant, widened from cross-strategy (within one ASIN) to cross-ASIN (within one property).

**Where the data lives:** a small head-term ownership map at the property level — in essence `term → owning ASIN` (plus rationale and date). Kept as a human-owned, reviewable record in the property (its own file, or a section of `strategy.md`) as the single source of truth. Ownership is a strategic decision and can change (new bestseller, stockout, season); it is set or changed by humans on review, never silently flipped by the daily Optimizer.

**Responsibilities:**
- *Within a property* (a brand's own ASINs): the positive Targeter enforces the ownership map via the cross-ASIN negation above.
- *Across properties of one client* (sibling brands contending for the same head term): the Account Manager arbitrates which property owns the term and audits, account-wide, that no head term is used twice. (This is its sibling-arbitration role — see `architecture-and-principles.md`.)

**Brand visibility:** to show several of the brand's products on a head term for brand presence, use Sponsored Brands (multiple products under the brand banner) rather than multiple Sponsored Products campaigns competing on the same term.

---

## 6. Campaign nomenclature

Campaigns follow a fixed name structure:

```
[CLIENT]-[ASIN]-[BRAND + PRODUCT NAME]-[CAMPAIGN TYPE]-[STRATEGY]-[MATCH TYPE]-[GOAL]-[NOTE]-LEXA
```

| Field | Format |
|:--|:--|
| CLIENT | 2 uppercase characters, **unique per client** (e.g. `WI` = Windspiel, `BI` = Bimmerle). Identifies the client's campaigns in a Lexacore-wide analysis. It does **not** need to encode the account, marketplace, or sales channel: those are recovered from the performance data via `profileId → amazon_ads_raw.profiles` (`countryCode` = marketplace, `accountInfo.type` = seller/vendor, `accountInfo.name`/`id` = account). The code is set per client in `client.md`. *(Field formerly defined per-account; changed 2026-06-15 once the data was confirmed to carry those dimensions.)* |
| ASIN | the advertised ASIN |
| BRAND + PRODUCT NAME | the **brand and product name joined** (Sheet `brand` + `product_name`, brand first, single space — e.g. `Windspiel Premium Dry Gin`), **normalized to exactly 35 characters** — truncate if longer, pad if shorter (see the length rule below). The name must always tie the brand to the product. |
| CAMPAIGN TYPE | `SPRO` = Sponsored Products / `SPBR` = Sponsored Brands / `SPDI` = Sponsored Display |
| STRATEGY | `MRK` = Own Brand / `WTB` = Competitor / `GEN` = Generic / `AUT` = Auto |
| MATCH TYPE | `Broad` / `Exact` — or `Auto` for AUT campaigns |
| GOAL | `R` = Research / `P` = Profit |
| NOTE | 4-character field for special notes (e.g. `XMAS`, `PRIM` for Prime Day); otherwise `NOTE` as placeholder |
| LEXA | fixed marker identifying the campaign as managed by Lexacore |

**Field-safety rules (so the name can be parsed unambiguously):**
- The BRAND + PRODUCT NAME field may contain **only letters (including umlauts and ß), numbers, and spaces** — plus the padding `_` defined below. All other characters — especially `-`, `/`, `|`, and punctuation such as `.` and `,` — are removed. Sanitize **first**, then normalize the length (next rule).
- **Exact 35-character length (interim rule, 2026-07-05).** Build the field as **`brand` + a single space + `product_name`** (Master-tab, brand first), sanitize, then make it **always exactly 35 characters**: truncate if longer; if shorter, **pad on the right with `_` (underscore)** until it reaches 35. Uniform length keeps campaign names reliably distinguishable in reporting (position- *and* delimiter-based). `_` is the sole exception to the letters/numbers/spaces rule, reserved for padding: it does **not** clash with the `-` field separator and — unlike trailing spaces — is **not** trimmed by Amazon. *(Width is **35 for now**; a later narrowing to ~30 is planned but is a larger operation — deferred. Half-clean interim overall: Amazon is rolling out a new product-title system; the source and this rule get redone properly then. Strip trailing `_` to recover the display name.)*
- The NOTE field follows the base rule (letters/numbers/spaces, no `-` or other separators), so it cannot break the parser.

**Example**

Cleaned campaign name:
`WI-B01EAR7GI2-Windspiel London Dry Gin 47 vol 1-SPRO-MRK-Broad-R-NOTE-LEXA`

(Read as: Client Windspiel — ASIN — brand + product name (`Windspiel` + `London Dry Gin 47 vol 1`) — Sponsored Products — Own Brand — Broad — Research — no special note — Lexacore campaign. Note that the original title's "vol. 1" becomes "vol 1" once the period is removed by the sanitization rule, and the field would then be padded/truncated to exactly 35.)

> **IMPORTANT:** Every campaign must keep this naming pattern. Otherwise campaigns cannot be evaluated by strategy, targeting, goal, etc. in reporting.

---

## 7. Sponsored Brands & Sponsored Display

*These segments will be expanded later (architecture memo §12). Phase 1 is Sponsored Products only.*

---

## 8. Product prioritization (the traffic light)

Every product carries a **priority** — `1` / `2` / `3` (mnemonic 🟢/🟡/🔴) — set per product by humans in the product Sheet and synced to Supabase, where the agents read it (`om-amazon-ads-reference/supabase-schema.md`). Priority is **data**; this section is the **binding ruleset** — what each level triggers, identical across every property and client.

| Prio | Meaning | Campaign build (creation) | Budget weight |
|---|---|---|---|
| **1** 🟢 | high / hero-tier | Expanded: the four strategies **plus** the Exact-Profit harvest campaigns (may split further) | Largest share of the property budget |
| **2** 🟡 | standard mitlaufend | Baseline: one campaign per strategy (MRK/WTB/GEN/AUT) | Normal share |
| **3** 🔴 | Randprodukt | Minimal: only the essentials (e.g. AUT for discovery + a single GEN/MRK), no Exact-Profit harvest | Smallest share |

- **Priority is a per-product budget/build tier — NOT head-term ownership.** A `category` may contain several Prio-1 products; a head term is owned by exactly **one** ASIN (§5), named separately in the head-term map in `strategy.md`. The owner is *typically* a Prio-1, but not every Prio-1 is an owner. Keep the two decisions separate.
- **Consumers:** `om-amazon-campaign-creation` reads the priority for build depth (§3); `om-amazon-optimization` and `om-amazon-account-management` weight budget allocation by it.
- **Strategic follow-on:** changing a class's head-term **owner** is a `strategy.md` edit (the Account-Manager **proposes**, human/Peggy approves — `strategy.md` is human-owned). A priority change alone does not move ownership; an agent never writes the priority or the map itself.

---

## Maintenance

This is the doctrine layer — it changes when Lexacore's Amazon advertising strategy changes, and is edited by humans. The *API contract* belongs in `om-amazon-ads-reference`; evolving best practice and experience belong in Drive `KI-Wissen/Amazon` (Research-maintained), never here. When the doctrine changes, update it here in the same change.
