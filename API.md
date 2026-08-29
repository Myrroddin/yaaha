# YAAHA Public API

YAAHA exposes a small public API for other World of Warcraft addons through the global `YAAHA_API` table. It is not registered with LibStub and must not be retrieved through LibStub.

> [!IMPORTANT]
> YAAHA and its public API are under active development. Names, signatures, callbacks, returned structures, and behavior may change before the first stable release. The API version remains `1` during this pre-release design period.

## Table of contents

- [Access](#access)
- [Editor support](#editor-support)
- [Versioning](#versioning)
- [Functions](#functions)
  - [`GetVersion()`](#getversion)
  - [`GetItemData(itemID, auctionHouseType)`](#getitemdataitemid-auctionhousetype)
  - [Market-value wrappers](#market-value-wrappers)
  - [`GetAuctionHouseStats(auctionHouseType)`](#getauctionhousestatsauctionhousetype)
  - [Realm-data functions](#realm-data-functions)
  - [Disenchanting functions](#disenchanting-functions)
- [Callbacks](#callbacks)
  - [`AUCTION_HOUSE_DATA_UPDATED`](#auction_house_data_updated)
- [Conventions](#conventions)
  - [Function calls](#function-calls)
  - [Auction-house types](#auction-house-types)
  - [Unavailable data](#unavailable-data)
  - [Sale rates](#sale-rates)
  - [Copper values](#copper-values)

## Access

Addons should access the API directly through its global name:

```lua
local YAAHA_API = YAAHA_API
```

Do not use LibStub:

```lua
-- Incorrect: YAAHA_API is not a LibStub library.
local YAAHA_API = LibStub("YAAHA_API")
```

An addon which requires the API should declare YAAHA as a required or optional dependency in its TOC so that YAAHA loads first.

## Editor support

`API.lua` publishes [WoWLua-LS](https://tradeskillmaster.github.io/wowlua-ls/guide/why-wowlua-ls) annotations for the global API, accepted auction-house strings, callbacks, and returned tables. When YAAHA's source is visible to the language server, consumers receive completion, hover documentation, literal-value suggestions, argument checking, and nil-aware return types.

The global and its annotation namespace are both named `YAAHA_API`. Consumers normally need no additional annotation:

```lua
if YAAHA_API then
    local data = YAAHA_API.GetItemData(2589, "Alliance")
    if data then
        print(data.currentMarketValue)
    end
end
```

Supporting annotations use readable names beneath that namespace, such as `YAAHA_API.AuctionHouseType`, `YAAHA_API.ItemData`, and `YAAHA_API.DisenchantResults`. These are editor metadata, not runtime fields which consumers must access. WoWLua-LS applies them automatically to function arguments, return values, and callbacks.

## Versioning

The current public API version is `1`.

The API version is independent of YAAHA's addon release version. A new addon tag or release does not automatically increment the API version. It changes only when the public specification or behavior requires consumers to distinguish the new contract.

Consumers may read the `version` field or call `GetVersion()`:

```lua
if YAAHA_API and YAAHA_API.version >= 1 then
    -- API version 1 is available.
end
```

## Functions

### `GetVersion()`

Returns the current public API version.

```lua
local version = YAAHA_API.GetVersion()
```

Returns

| Value | Type | Description |
| --- | --- | --- |
| `version` | `number` | The public API version. Currently `1`. |

### `GetItemData(itemID, auctionHouseType)`

Returns YAAHA's public calculated data for one item in the requested auction house.

```lua
local data = YAAHA_API.GetItemData(2589)
if data then
    print(data.currentMarketValue)
end
```

The returned table is a new snapshot. Changing it does not alter YAAHA's saved data. Raw price observations, personal sale rates, and other internal processing data are intentionally not exposed.

Arguments

| Value | Type | Description |
| --- | --- | --- |
| `itemID` | `number` | A positive integer item ID. |
| `auctionHouseType` | `string` or `nil` | Optional. Exactly `"Alliance"`, `"Horde"`, or `"Neutral"`; omitted or `nil` uses the current character's faction auction house. |

Returns

Returns `nil` if the request is invalid or YAAHA has no public data for the item. Otherwise, it returns a `YAAHA_API.ItemData` table which can contain these keys:

| Key | Type | Description |
| --- | --- | --- |
| `auctionCount` | `number` | Number of auction listings for the item in the current scan. |
| `auctionQuantity` | `number` | Number of individual items represented by the current scan's listings. |
| `lastScan` | `number` | Server timestamp of the current item snapshot. Omitted when the item was absent from the latest scan. |
| `minBid` | `number` | Lowest payable per-unit bid in copper from the current scan. |
| `minBuyout` | `number` | Lowest per-unit buyout in copper from the current scan. |
| `currentMarketValue` | `number` | Market value calculated solely from the current scan. |
| `midweekMarketValue` | `number` | Weighted rolling three-day market value. |
| `weeklyMarketValue` | `number` | Weighted rolling seven-day market value. |
| `biweeklyMarketValue` | `number` | Weighted rolling fourteen-day market value. |
| `monthlyMarketValue` | `number` | Weighted rolling thirty-day market value. |
| `bimonthlyMarketValue` | `number` | Weighted rolling sixty-day market value. |

Every key is optional. Unknown, expired, and inapplicable values are omitted.

### Market-value wrappers

The following functions accept the same `(itemID, auctionHouseType)` arguments as `GetItemData()` and return only the named value, or `nil` when it is unavailable:

| Function | Returned key |
| --- | --- |
| `GetAuctionCount()` | `auctionCount` |
| `GetAuctionQuantity()` | `auctionQuantity` |
| `GetMinBid()` | `minBid` |
| `GetMinBuyout()` | `minBuyout` |
| `GetCurrentMarketValue()` | `currentMarketValue` |
| `GetMidweekMarketValue()` | `midweekMarketValue` |
| `GetWeeklyMarketValue()` | `weeklyMarketValue` |
| `GetBiweeklyMarketValue()` | `biweeklyMarketValue` |
| `GetMonthlyMarketValue()` | `monthlyMarketValue` |
| `GetBimonthlyMarketValue()` | `bimonthlyMarketValue` |
| `GetLastScanTime()` | `lastScan` |

### `GetAuctionHouseStats(auctionHouseType)`

Returns summary information for the latest complete scan or synchronized snapshot of the requested auction house.

```lua
local stats = YAAHA_API.GetAuctionHouseStats("Neutral")
if stats then
    print(stats.totalListings, stats.totalItems, stats.lastScan)
end
```

The returned `YAAHA_API.AuctionHouseStats` table is a defensive snapshot with these keys:

| Key | Type | Description |
| --- | --- | --- |
| `lastScan` | `number` | Server timestamp of the latest complete auction-house snapshot. |
| `totalListings` | `number` | Total number of auction listings represented by that snapshot. |
| `totalItems` | `number` | Number of distinct item IDs represented by that snapshot. |

The optional `auctionHouseType` follows the same rules as `GetItemData()`. The function returns `nil` when the request is invalid or no completed snapshot is available.

### Realm-data functions

Realm statistics are intentionally exposed one value at a time. They are not included in the table returned by `GetItemData()`, and YAAHA's private `personalSaleRate` is never returned by the public API.

Each function accepts `(itemID, auctionHouseType)` using the same validation, optional faction default, and auction-house separation as `GetItemData()`.

| Function | Return type | Description |
| --- | --- | --- |
| `GetRealmSaleRate()` | `number` or `nil` | Fraction of resolved auction quantities sold during the current rolling 24-hour realm-data window. |
| `GetRealmSoldPerDay()` | `number` or `nil` | Number of individual items sold during the current rolling 24-hour realm-data window. |
| `GetRealmAverageSaleValue()` | `number` or `nil` | Average gross per-unit auction sale value in copper during the current rolling 24-hour realm-data window. |

Realm data expires 24 hours after its newest qualifying observation. These functions return `nil` when the requested value is unavailable or expired. A known current sale rate or sold quantity may validly be zero.

### Disenchanting functions

Disenchanting results are universal and are not separated by auction-house type. Expected values use prices from the requested auction house without mixing faction and neutral data.

| Function | Return type | Description |
| --- | --- | --- |
| `IsDisenchantable(itemID)` | `boolean` | Whether YAAHA recognizes the item as disenchantable and has a result range for it. |
| `GetDisenchantResults(itemID)` | `table` or `nil` | A defensive copy of the item's possible materials, probabilities, quantity ranges, expected quantities, required skill, and Wrath sample count. |
| `GetDisenchantValue(itemID, auctionHouseType, fullResults)` | `number`, `table`, or `nil` | Expected value using prices from the selected auction house. Pass `true` for the complete priced breakdown. Missing prices make the total unavailable. |

`GetDisenchantResults()` returns `YAAHA_API.DisenchantResults`. Each `YAAHA_API.DisenchantMaterial` entry in its `results` array contains `itemID`, `chance`, `minQuantity`, `maxQuantity`, and `expectedQuantity`. `chance` is a decimal fraction. `expectedQuantity` already includes the probability of receiving that material.

For each material, expected value uses the first positive source in this order: `currentMarketValue`, `midweekMarketValue`, `weeklyMarketValue`, `biweeklyMarketValue`, `monthlyMarketValue`, then `bimonthlyMarketValue`. Minimum bid and minimum buyout are never used as substitutes.

#### Disenchant-value arguments

| Value | Type | Description |
| --- | --- | --- |
| `itemID` | `number` | A positive integer item ID. |
| `auctionHouseType` | `string` or `nil` | Optional auction-house type using the same rules as `GetItemData()`. |
| `fullResults` | `boolean` or `nil` | Optional. `true` returns the full breakdown; `false` or omitted returns only the summed value. |

When `fullResults` is `false` or omitted, `GetDisenchantValue()` returns the summed expected value in copper. It returns `nil` when any possible material lacks a positive market value, because a partial sum could be mistaken for a complete valuation.

When `fullResults` is `true`, the function returns a new `YAAHA_API.PricedDisenchantResults` table containing `expectedValue`, `requiredSkill`, `sampleCount`, and a `results` array. The top-level `expectedValue` is `nil` when any material price is missing, while the individual known material values remain available in `results`. Each `YAAHA_API.PricedDisenchantMaterial` contains:

| Key | Type | Description |
| --- | --- | --- |
| `itemID` | `number` | Resulting enchanting material. |
| `chance` | `number` | Decimal probability of receiving the material. |
| `minQuantity` | `number` | Minimum possible quantity. |
| `maxQuantity` | `number` | Maximum possible quantity. |
| `expectedQuantity` | `number` | Probability-adjusted expected quantity per disenchant. |
| `marketValue` | `number` or `nil` | Selected per-unit material value in copper. `nil` means it is unavailable. |
| `priceSource` | `string` or `nil` | Market-value source selected using YAAHA's defined priority order. |
| `expectedValue` | `number` or `nil` | This material's probability-adjusted value in copper. `nil` means its price is unavailable. |
| `missingPrice` | `boolean` | `true` when the material was not found with a positive value in the selected auction database. |

The returned table is a defensive snapshot. Changing it does not modify YAAHA's internal or saved data.

## Callbacks

YAAHA uses CallbackHandler-1.0 to notify consuming addons after public auction data changes. Register and unregister callbacks directly through `YAAHA_API`; do not retrieve CallbackHandler or YAAHA through LibStub.

The consumer object must be the first argument:

```lua
local consumer = {}

function consumer:OnAuctionHouseDataUpdated(event, auctionHouseType, source)
    local stats = YAAHA_API.GetAuctionHouseStats(auctionHouseType)
    -- YAAHA's updated data is ready to query here.
end

YAAHA_API.RegisterCallback(
    consumer,
    "AUCTION_HOUSE_DATA_UPDATED",
    "OnAuctionHouseDataUpdated"
)
```

Consumers should unregister callbacks when they no longer need notifications:

```lua
YAAHA_API.UnregisterCallback(consumer, "AUCTION_HOUSE_DATA_UPDATED")
```

### `AUCTION_HOUSE_DATA_UPDATED`

Fires once for each auction-house database which actually changed, after YAAHA has committed and recalculated its complete data.

| Callback value | Type | Description |
| --- | --- | --- |
| `event` | `string` | Always `"AUCTION_HOUSE_DATA_UPDATED"`. |
| `auctionHouseType` | `string` | Exactly `"Alliance"`, `"Horde"`, or `"Neutral"`. |
| `source` | `string` | `"scan"` for a completed local scan or `"sync"` for newly merged synchronized data. |

A synchronized packet which contains no newer or otherwise missing data does not fire the callback. Callback recipients may query any public API function immediately; they never observe a partially processed scan or merge.

## Conventions

These conventions apply to data functions as they are added to the public API.

### Function calls

Public functions use dot-call syntax:

```lua
local value = YAAHA_API.GetVersion()
```

They are not object methods and should not be called with a colon.

### Auction-house types

Omitting `auctionHouseType`, or passing `nil`, accesses the current character's faction auction-house database. Passing `"Neutral"` explicitly accesses the neutral auction-house database. An explicit faction value accesses faction data only when it matches the current character; requesting the opposite faction returns `nil`. YAAHA never substitutes or combines another auction-house type.

### Unavailable data

Data functions return `nil` when a requested value is unknown, unavailable, expired, or does not apply. The API does not silently substitute data from another faction or auction-house type.

### Sale rates

Sale rates are returned as decimal fractions rather than display percentages. They are rounded half-up to at most three decimal places.

```text
0.3104 → 0.310
0.3105 → 0.311
0.3114 → 0.311
0.3115 → 0.312
```

For display, consumers may multiply the returned value by 100. For example, `0.311` represents `31.1%`.

### Copper values

Monetary values are returned as whole copper. Values of at least one copper use half-up rounding to the nearest whole copper. Any positive value below one copper is rounded up to one copper so that a real positive value is never reported as zero.

```text
nil  → nil
0    → nil
0.01 → 1
0.49 → 1
0.99 → 1
1.20 → 1
1.49 → 1
1.50 → 2
```

Negative monetary values are invalid and are not returned by YAAHA.
