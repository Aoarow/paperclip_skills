# Shopping Campaigns — Listing Groups (Product Partitions)

Load this file when building a Standard Shopping campaign and you need the product-partition tree structure, dimension hierarchy, or the construction pattern for `ListingGroup` resources.

## When to use Standard Shopping vs Performance Max for retail

Google's recommendation is that **Performance Max for retail is the default choice** for almost every retail use case. Build Standard Shopping only when one of these reasons applies:

- The advertiser wants strict channel separation (Shopping only, no YouTube / Display)
- Brand-protected campaigns with explicit negatives that PMax does not support
- Fine-grained product-level bidding control beyond what PMax target ROAS allows
- The advertiser is in a category where PMax has known under-performance (very narrow vertical)

If none of these apply, build a Performance Max campaign with a Merchant Center feed instead.

## Required prerequisites

- A linked Google Merchant Center account.
- An approved product feed with at least some active products.
- `Campaign.shopping_setting.merchant_id` set to the linked MC account.
- `Campaign.shopping_setting.feed_label` or `sales_country` set.
- `Campaign.shopping_setting.campaign_priority`: `LOW`, `MEDIUM`, or `HIGH`. Default `LOW` unless multiple Shopping campaigns share products.

## Campaign structure

```
Campaign (SHOPPING)
└── AdGroup (SHOPPING_PRODUCT_ADS)
    ├── AdGroupAd → Ad → ShoppingProductAd  (the ad shell — usually one per ad group)
    └── AdGroupCriterion (with listing_group)
        └── tree of ListingGroup resources
```

`ShoppingProductAd` itself is essentially empty — there is no headline, no description, no image to provide. The ad is constructed at serve time from the Merchant Center product data. The structural work lives in the **listing group tree**.

## What a listing group is

A `ListingGroup` is a node in a partition tree that subdivides the product inventory by one product attribute at a time. Each node either:

- **Subdivides** further (type `SUBDIVISION`) — has children, no bid
- **Is a leaf** (type `UNIT`) — no children, has a bid (`cpc_bid_micros`)

Every product in the feed must end up in exactly one leaf. The tree always starts with a single root node that captures everything, and you subdivide downward.

## Dimensions you can partition on

Each subdivision level uses one `listing_dimension` type. Available types:

| Dimension type           | Subdivides by                                          |
|--------------------------|--------------------------------------------------------|
| `product_category`       | Google product taxonomy category                       |
| `product_brand`          | Brand string from the feed                             |
| `product_item_id`        | Specific SKU / item ID                                 |
| `product_condition`      | `NEW`, `REFURBISHED`, `USED`                           |
| `product_type`           | The feed's own product type taxonomy (5 levels)        |
| `product_channel`        | `ONLINE` or `LOCAL`                                    |
| `product_channel_exclusivity` | `SINGLE_CHANNEL` or `MULTI_CHANNEL`               |
| `product_custom_attribute` | One of 5 custom_label slots (0–4) from the feed     |

You cannot subdivide on the same dimension twice in a single path down the tree.

## Tree construction pattern

The API requires the tree to be built **top-down in a single bulk mutate**, with every parent reference using a temporary resource name. The structure of each `AdGroupCriterion.listing_group`:

```
AdGroupCriterion (negative_keyword: false)
├── listing_group
│   ├── type: SUBDIVISION | UNIT
│   ├── case_value: <ListingDimension>      (which slice of the parent this node represents)
│   └── parent_ad_group_criterion: <resource_name>  (the parent — null only for the root)
└── cpc_bid_micros  (only on UNIT leaves)
```

### Minimal valid tree

The smallest valid tree is a single root node with no subdivisions — one leaf catching every product:

```
root (UNIT, case_value: null)
   bid: cpc_bid_micros
```

### Typical brand-priority tree

```
root (SUBDIVISION on product_brand)
├── brand="Acme"             (UNIT, bid: high)
├── brand="Globex"           (UNIT, bid: medium)
└── brand=null (other)       (UNIT, bid: default)     ← required catch-all
```

**Catch-all requirement:** at every subdivision level, you must include a node with `case_value = null` (called the "other" or "everything else" node). Without it the API will reject the tree. The "other" node can itself be a `UNIT` leaf or another `SUBDIVISION` if you want to keep partitioning the unspecified products.

### Two-level subdivision

```
root (SUBDIVISION on product_type level 1)
├── "Apparel" (SUBDIVISION on product_brand)
│   ├── brand="Acme" (UNIT, bid)
│   ├── brand="Globex" (UNIT, bid)
│   └── brand=other (UNIT, bid)
├── "Electronics" (UNIT, bid)
└── product_type=other (UNIT, bid)
```

## Construction code shape

```
operations = [
  AdGroupCriterionOperation.create(
    resource_name = "customers/{cid}/adGroupCriteria/{agid}~-1",     # root, temp
    ad_group     = "customers/{cid}/adGroups/{agid}",
    status       = ENABLED,
    listing_group = {
      type = SUBDIVISION,
      case_value = { product_brand = null }   # root has null case
    }
  ),
  AdGroupCriterionOperation.create(
    resource_name = "customers/{cid}/adGroupCriteria/{agid}~-2",     # brand=Acme
    ad_group     = "customers/{cid}/adGroups/{agid}",
    status       = ENABLED,
    cpc_bid_micros = 2_500_000,
    listing_group = {
      type = UNIT,
      parent_ad_group_criterion = "customers/{cid}/adGroupCriteria/{agid}~-1",
      case_value = { product_brand = { value = "Acme" } }
    }
  ),
  …
]
```

The root node uses `case_value` with the appropriate dimension type but a null value (it represents "all products"); children carry the specific value for that slice.

## Bidding strategies for Shopping

- `MANUAL_CPC` — required if you want product-level bid control via the listing group tree's `cpc_bid_micros`.
- `MAXIMIZE_CLICKS` — traffic goal, no product-level bidding.
- `MAXIMIZE_CONVERSION_VALUE` (with optional `target_roas`) — recommended for revenue-focused Standard Shopping campaigns; per-leaf bids are ignored.
- `TARGET_ROAS` — requires conversion-value history.

If using a smart bidding strategy, the leaf-level `cpc_bid_micros` becomes informational only — Google's automated bidding ignores it. In that case, the listing group tree's value is just *segmentation* for reporting, not bidding.

## Negative product exclusions

`AdGroupCriterion` with `negative = true` and a `listing_group` of type `UNIT` removes a product slice from the campaign. Useful for excluding low-margin SKUs or out-of-stock categories.

## Verification queries

After construction, verify the tree with:

```sql
SELECT ad_group_criterion.criterion_id,
       ad_group_criterion.listing_group.type,
       ad_group_criterion.listing_group.case_value,
       ad_group_criterion.listing_group.parent_ad_group_criterion,
       ad_group_criterion.cpc_bid_micros
FROM ad_group_criterion
WHERE ad_group.id = {ad_group_id}
  AND ad_group_criterion.type = 'LISTING_GROUP'
```

Confirm every subdivision level has a `case_value = null` "other" node and that every leaf is reachable from the root.
