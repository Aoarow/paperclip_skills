---
name: om-amazon-fba
description: Daily FBA replenishment for one Amazon account — read stock, sales velocity, shipment state and packing data from Supabase (agent_reads only, never the SP-API directly), decide whether a delivery is due, and prepare the shipment for a human to confirm. Covers the trigger logic (fixed cadence vs. demand), reach and protection-interval maths, rounding to shipping units, product-status rules, the out-of-stock cases, packing sources, and the guards that keep a plausible-looking number from becoming a pallet in the wrong place. The agent is an assistant, not an autonomous optimizer — confirmPlacementOption and confirmTransportationOptions cost money, are irreversible, and stay permanently with the human at every autonomy level. Dates and limits (cadence, target reach, lead time, thresholds, country exclusions, responsibilities) are read from the customer's client.md; quantities (units per shipping unit, delivery quantum) are read from the product data. Neither is ever hard-coded here. Use whenever an FBA agent runs its daily cycle, judges whether a shipment is due, prepares a position list, or chases a missing tracking number. Advertising doctrine lives in om-amazon-advertising-manifest; permission ceilings in om-autonomy-levels.
---

# Amazon FBA — Replenishment and Shipment Preparation

This skill teaches an FBA agent how to run its daily cycle for **one Amazon account** (account-wide,
not per brand — the delivery threshold is reached jointly across brands, so a per-brand view would
never trigger).

**The agent is an assistant, not an autonomous optimizer.** Unlike the advertising agents it does not
act and report; it observes, judges, prepares, and hands over. The two steps that cost money and
cannot be undone — `confirmPlacementOption` (placement fee) and `confirmTransportationOptions`
(booking) — stay with the human **permanently, at every autonomy level.** This is not a ceiling that
rises with maturity; it is the design.

> **The valuable half of this work needs no write access at all.** Reach, stock-out risk, shipments
> hanging without a tracking number, divergence between shipped and received — all of it is
> observation. Run the agent in observation mode long enough to see whether its judgement is sound,
> in a place where a wrong judgement costs nothing.

---

## What this skill covers

- Deciding whether a delivery is due, and how much of what to send
- Building the position list (and, once the tooling exists, the shipment draft up to the money steps)
- Product-status and out-of-stock handling
- Chasing tracking numbers and keeping shipment state honest
- The guards that stop a wrong-but-plausible number

## Where this skill stops

These are boundaries the agent could otherwise cross, not a map of neighbouring territory.

- **Confirming placement or transportation.** Never, at any autonomy level. Prepare and escalate.
- **Deciding the customer's numbers.** Cadence, target reach, thresholds, pallet composition,
  country exclusions and packing exceptions are read, not decided — see below.
- **Physical work.** Sticking labels, measuring cartons, building pallets. The **pallet count** is
  set by the customer's logistics, not by us: the agent counts in cartons and trays and supplies
  dimensions as an indication only.
- **The end of the current scope: the shipment is created.** Everything downstream — drafting the
  message to the customer's warehouse, depositing or sending carton and pallet labels, entering the
  tracking number at Amazon — is out of scope for now and done by the human. Watching for shipments
  that hang without a tracking number stays in scope; it is observation, not action.

Advertising (bids, budgets, keywords) belongs to `om-amazon-optimization` and its siblings — worth
naming only because the Account Manager reads both this skill and the advertising doctrine.

---

## The split: mechanism here, numbers in `client.md`

This skill is **customer-agnostic on purpose**, so every present and future FBA agent can point at
it and a change to the general method is made in exactly one place.

Everything that differs per customer lives in that customer's **`client.md`** in their Google Drive
folder — because such rules hold across all of the customer's properties, not per property:

| Read from `client.md` | Examples of what varies |
|---|---|
| Trigger mode and cadence | fixed cadence (e.g. every 14 days, Tuesdays) vs. demand-driven |
| Target reach, in selling days | the stock horizon to fill up to |
| Lead time | measured, not estimated — see *Protection interval* |
| Delivery threshold | minimum shipping units below which nothing ships |
| **Freight form** | how this customer ships to Amazon — pallet/LTL, small parcel, or another form |
| Hard exclusions | destination countries that must never be accepted |
| Who does what | sender, packing site, carrier, and how the tracking number reaches us |

The freight form is a **policy, not an observation.** The shipment mirror records the form actually
used on past shipments; that is history, and history may include practices the customer has since
abandoned. Read the form from `client.md`. If a computed shipment does not fit that form — too small
to be worth a pallet, say — **report it and ask; never switch form on your own.**

⚠️ **The dividing line: dates and limits in `client.md`, quantities at the product.** Nothing about
how a product is packed is read from the customer file — not the shipping unit, not the pallet
composition, not which products go as a full load. All of that is per-SKU data:

| Read from the product data | Meaning |
|---|---|
| `units_per_carton` | how many items one shipping unit holds — 6 for a carton of bottles, 1 where the item *is* the unit (a tray, an oversize bottle) |
| `fba_default` | delivery quantum in units; shipments are rounded up to a multiple of it. **Empty means 1**, i.e. no quantum |

A customer file that starts listing SKUs, cartons or pallets has taken on work that belongs
elsewhere. Where such a file explains *why* a quantum has the value it does, that is documentation
for the human maintaining it — never the number the agent computes with.

**If a number this skill needs is missing from `client.md`, the agent says so and stops** — it does
not substitute a default. A silently assumed number is the failure mode this whole method is built
against.

---

## Inputs — read before doing anything

Read **only** through `agent_reads` in Supabase. **Never call the SP-API directly** — the nightly
mirror is the source, and the agent has no SP-API credentials by design.

| Source | What for |
|---|---|
| `<t>_fba_inventory_daily` | fulfillable stock and inbound quantities, per FNSKU, per day |
| `<t>_sales_daily` | sales velocity, per ASIN |
| `<t>_fba_shipments` | shipment state, destination, delivery window |
| `<t>_fba_chase` | shipments ready/shipped without a tracking number |
| `<t>_fba_packing` | measured units per carton, from the carton history |
| `<t>_products_by_asin` | `status`, `units_per_carton`, `fba_default`, `fba_sku`, `price` |
| `client.md` (Drive) | every customer-level number, plus the hard exclusions |

`<t>` is the tenant prefix of the account.

### Which source gates which answer

A stale source blocks **its own** part of the run, not the whole run. Say what is unavailable and
deliver the rest.

| Answer | Needs | Does **not** need |
|---|---|---|
| Is a delivery due, and how much | stock, sales, packing, `client.md` | the shipment view — inbound quantities come from the stock view |
| Which shipments hang without a tracking number | the shipment view | — |
| Has a shipment arrived as sent | the shipment view | — |

Refusing to compute a reach check because the *shipment* mirror is stale withholds a correct answer
for an unrelated reason. Compute what the fresh sources support, mark the rest as unavailable, and
escalate the stale source separately.

⚠️ **A timestamp is only a freshness signal if it is written on every pass.** A column filled by a
database default is set once, at first insert, and then keeps claiming that moment forever while the
row around it updates normally. Before trusting any `fetched_at`-style column, confirm the writer
sends it — otherwise it reports when a row was first seen, not when it was last confirmed.

---

## The replenishment mechanic

### Two trigger modes

**Fixed cadence** — the trigger is the **calendar**, not the stock level. The question is not "is a
delivery worth it" but "how far do we fill so it lasts until the delivery after next". This is a
periodic (R,S) policy. A customer with a standing arrangement with their warehouse is in this mode.

**Demand-driven** — the trigger is the **threshold**: nothing ships until the shipment is large
enough to be worth moving. Slow accounts are in this mode.

Which mode applies is stated in `client.md`.

### Reach

    reach [days] = available stock / sales velocity [units per day]

Available stock is **fulfillable** plus inbound. `total_quantity` is **not** a stock measure — it
includes goods already on their way and double-counts them.

### Protection interval

    protection interval = cadence + lead time

Everything whose reach at delivery time falls below the protection interval **must** be on this
shipment — there is no next chance before it runs dry. Lead time is **measured** from the shipment
timeline in the mirror, not estimated. Until enough shipments have been measured, the agent
**computes without a lead time and says so**.

### Fill quantity and rounding

    need [units] = velocity × target reach − available stock

Rounding happens in **two layers, in this order**:

1. **Round up to whole shipping units**, using `units_per_carton` for the SKU — 6 for a carton of
   bottles, 1 where the item is itself the unit. Where the measured carton history disagrees with
   the catalogue value, the history wins (see the packing sources below).
2. **Round up to a multiple of `fba_default`**, the per-SKU delivery quantum from the product data.
   Where it is empty the value is **1**, so this layer does nothing and the shipping unit from
   step 1 stands. Where it holds a number — for example a full pallet of cans expressed in units —
   the shipment is rounded up to whole multiples of it.

This is what keeps a slow-turning product in a pallet-shaped class from receiving a pallet it will
not consume: it simply has no quantum set, so it ships in plain shipping units.

For a product that *does* carry a quantum, the trigger is the **protection interval, not the fill
target** — otherwise the agent sends a full quantum every cadence for a product that consumes a
fraction of one.

### The threshold

Below the customer's threshold, **nothing ships — but the agent reports.** For a customer on a fixed
cadence the warehouse *expects* a delivery on every date; silence is indistinguishable from a
failure. The report is a deliverable, not an omission.

The reporting path is the same one used for every run: **the agent creates a task per run and writes
into it what it decided and did** — exactly as the advertising agents already do. A no-delivery run
is a full entry with its reason, not a blank.

---

## Sales velocity — read this before computing anything

**Never average velocity over days when stock was zero.** A sold-out product records no sales,
measures as a non-seller, and is therefore never replenished — it removes itself from the process
permanently. This is the single most dangerous computation in this skill.

    velocity = units sold ON THE MEASURED DAYS / count of those same days

⚠️ **Numerator and denominator must cover exactly the same days.** This is the part that goes wrong
in practice: a window is chosen for the sales figure, a different, shorter one for the day count,
and the velocity comes out inflated by the ratio between them. Measured on the live account, that
mistake produced a **2.5× overshoot** — a shipment two and a half times larger than the truth, and
every intermediate number looked reasonable.

The days that count are those where stock was **measured and greater than zero**. A day with no
stock snapshot is **not** a day without stock — it is a day we know nothing about, and it belongs in
neither half of the fraction. Sum the sales of the qualifying days only; divide by how many there
are.

Stock snapshots begin later than sales history, so the usable window is short at first and widens
by one day per day. The agent states which window it used and how many days it holds.

Two further properties of the data, both of which produce plausible wrong numbers:

- **Stock hangs on the FNSKU, not the seller SKU.** Summing over SKU double-counts.
- **Sales are per ASIN across all channels**, not FBA alone. Where a customer also sells merchant
  fulfilled, velocity overstates FBA demand. State the limitation; do not silently correct it.

---

## Product status and lifecycle

> **The whole rule in one sentence:** a product with its own FBA SKU and `status = active` should be
> stocked to the target reach — no exceptions, no tiers. If that cannot be computed for lack of
> reliable numbers, ask the human. If `status = discontinued`, do not replenish. **There is nothing
> in between.**
>
> A slow-moving product is not a special case: its computed need is simply small, so it triggers
> rarely. That is the intended behaviour, not a gap.

**1. Status decides first.** `status = discontinued` → the product is out of the FBA process
entirely. It appears in no proposal and in no report. No further question arises.

**2. A new product is a question, not a computation.** Active, listed for FBA, but with no or too
little sales history → the agent does **not** extrapolate. Initial stocking is a human decision. The
agent names the product, states that history is missing, and asks.

**3. Zero stock with history is a sell-out, not a listing problem.** When a product has been empty
for a while, its offer may disappear from the listing — that is the *consequence* of the empty
stock, not a separate fault. There is no listing branch: restore the stock and the offer returns.
Compute the velocity for such a product from the period **before** it ran dry (see above).

**4. Capacity is the real ceiling — and is currently not measurable.** The limiting factor for FBA
is the storage capacity Amazon grants the account, not our willingness to ship. No source in the
mirror carries that limit today. Until one does, the agent **states the assumption out loud**
("capacity limit not verified; per `client.md` we are far from it") rather than quietly assuming it.

> ⏸️ **Deferred:** urgency graded by product priority (the traffic light) — refill focus products
> earlier than slow movers even when logistics cost argues otherwise. Decided to postpone; the
> ruleset for the traffic light itself is in `om-amazon-advertising-manifest` §8 and is **not**
> repeated here.

---

## Packing — two sources, in this order

1. **Carton history** (`<t>_fba_packing`) — measured, from shipments actually made. Preferred.
2. **`units_per_carton`** from the product catalogue — for anything without history.

There is no third source. If neither carries a value for a SKU that needs shipping, that is a
finding to report, not a gap to fill with a guess.

`varianten_physisch > 1` is a finding worth reporting. `varianten_vorlagenname > 1` is **not** — the
template name is human-assigned and often just describes the pallet build of that one shipment. The
name is a strong hint, never a rule.

---

## Guards — every one of these has produced a wrong number already

- **Check country exclusions on the warehouse code, never on the delivery address.** A warehouse
  code belonging to an excluded country can deliver to an address inside the permitted one. An
  address-based guard passes every such case.
- **Never sum over the seller SKU where the FNSKU is the grain.**
- **Resolve the FBA SKU through the `fba_sku` field, never by appending a suffix to the merchant
  SKU.** The product data maintains the merchant SKU and names its FBA counterpart explicitly. The
  two names are usually related but not always mechanically: a counterpart may drop the hyphen, or
  differ outright. Measured on the live catalogue, the SKUs where the names diverge are precisely the
  ones carrying a delivery quantum — so a suffix-based guess fails exactly where it costs a pallet.
- **Never read `total_quantity` as a stock measure.**
- **Any Amazon list without an explicit status filter is suspect.** Several endpoints silently
  return only active records and omit the rest without any error.
- **Plan age is not shipment age.** Old plans carry fresh shipments.
- **A partial day is not a measurement.** Mark the current day as partial; never read an absence of
  measurement as a measurement of zero.
- **Check completion against the target state, not against the agent's own report.**
- **Measured history is not policy.** The mirror shows what was done, never what should be done. A
  practice visible in past shipments may have been abandoned precisely because it went badly. Where
  history and `client.md` disagree, `client.md` wins and the divergence is a finding worth naming.

---

## Run sequence

1. Read `client.md` — abort with a clear statement if a required number is absent.
2. Determine the data cutoff: latest settled day per source; mark partial days as partial.
3. Pull stock, velocity (excluding zero-stock days), shipment state, packing data.
4. Apply the status and lifecycle rules; set aside what needs a human decision.
5. Determine the trigger: cadence date reached, or threshold met.
6. Compute reach, protection interval, need; round to shipping units.
7. Decide: deliver, or do not deliver.
8. If delivering: prepare the position list, and create the shipment where the tooling allows —
   **stop before the two money steps.** This is where the current scope ends.
9. Escalate: create a Paperclip issue with **Peggy as assignee**, who reaches the human handler.
10. Write the run entry — **every run, including runs where nothing was due.**
11. Chase: list shipments ready or shipped without a tracking number beyond the customer's grace
    period, and report them. Reporting only — entering the number at Amazon is the human's step.

---

## Escalation and the ask-back loop

The FBA agent holds a **conversation**, which the advertising agents do not: it asks before a
shipment is built, and continues once answered. Route: agent creates a Paperclip issue with Peggy as
assignee → Peggy reaches the human → the human answers → the agent resumes.

⚠️ Mind the disposition: leaving a checked-out issue `in_progress` at the end of a run without a
live child issue pulls in auto-recovery and the supervisor. Close or hand back cleanly.

---

## Decision-log contract

Same duty as the advertising agents, same file, same discipline — **a dated entry every run,
including runs where nothing happened.** An entry carries:

- **Data cutoff** — which day is settled, which is partial
- **Finding, with numbers** — not an adjective
- **Decision** and its reason
- **Executed** — what actually changed, or explicitly nothing
- **Read-back check** — verify against the target state, not the report

---

## References

- Customer specifics: `client.md` in the customer's Drive folder
- Advertising doctrine incl. the traffic light: `om-amazon-advertising-manifest`
- Autonomy ceilings: `om-autonomy-levels`
- Data shapes and view definitions: `om-amazon-ads-reference/references/supabase-schema.md`

---

## Maintenance

**Why one skill and not a manifest plus a procedure.** Advertising splits the standard
(`om-amazon-advertising-manifest`) from the procedures (`om-amazon-optimization` and siblings)
because five agent roles share one standard. FBA has one role, so one skill is the right size — the
split would be structure without a need. **Split the standard out when a second logistics role
appears** (for example a separate shipment builder, or the Account Manager needing to judge logistics
findings on its own).

Customer numbers never move into this file. If a rule here can only be written by naming a specific
customer's value, it belongs in `client.md` instead — and if it can only be written by naming a
specific SKU, it belongs with the product data.

**Known placeholders, to be replaced when decided:**

- **Reporting path.** A task per run is the deliberate simple start. A more precise route for the
  no-delivery case in particular is worth designing later.
- **Scope extension.** Drafting the message to the customer's warehouse and handling carton and
  pallet labels are the obvious next steps once the observation phase has proven the judgement.
  When that step comes, the **recipient is not maintained here and not in `client.md`** — the CRM is
  the customer master, the same way it already holds the authoritative `driveFolderId`. Note that no
  agent has yet made a CRM call in practice, so treat that path as unproven until it is exercised.
- **Urgency by product priority.** Deferred; see the lifecycle section.
