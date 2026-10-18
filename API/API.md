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
  - [Item-data wrappers](#item-data-wrappers)
  - [`GetAuctionHouseStats(auctionHouseType)`](#getauctionhousestatsauctionhousetype)
  - [Realm-data functions](#realm-data-functions)
  - [Disenchanting functions](#disenchanting-functions)
  - [Crafting functions](#crafting-functions)
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
        print(data.firstNonZeroMarketValue, data.firstNonZeroMarketSource)
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
    print(data.firstNonZeroMarketValue, data.firstNonZeroMarketSource)
end
```

The returned table is a new snapshot. Changing it does not alter YAAHA's saved data. Raw price observations, personal sale rates, vendor-flip activity, and other private or internal processing data are intentionally not exposed.

Arguments

| Value | Type | Description |
| --- | --- | --- |
| `itemID` | `number` | A positive integer item ID. |
| `auctionHouseType` | `string` or `nil` | Optional. Uses the client-specific rules described under [Auction-house types](#auction-house-types). |

Returns

Returns `nil` if the request is invalid or YAAHA has no public data for the item. Otherwise, it returns a `YAAHA_API.ItemData` table which can contain these keys:

| Key | Type | Description |
| --- | --- | --- |
| `auctionCount` | `number` | Number of auction listings for the item in the current scan. |
| `auctionQuantity` | `number` | Number of individual items represented by the current scan's listings. |
| `lastScan` | `number` | Server timestamp of the current item snapshot. Omitted when the item was absent from the latest scan. |
| `minBid` | `number` | Lowest payable per-unit bid in copper from the current scan. |
| `minBuyout` | `number` | Lowest per-unit buyout in copper from the current scan. |
| `firstNonZeroMarketValue` | `number` | First positive market value in copper, checking the available time frames from shortest to longest. |
| `firstNonZeroMarketSource` | `string` | Key which supplied `firstNonZeroMarketValue`, such as `"currentMarketValue"` or `"midweekMarketValue"`. |
| `currentMarketValue` | `number` | Market value calculated solely from the current scan. |
| `midweekMarketValue` | `number` | Weighted rolling three-day market value. |
| `weeklyMarketValue` | `number` | Weighted rolling seven-day market value. |
| `biweeklyMarketValue` | `number` | Weighted rolling fourteen-day market value. |
| `monthlyMarketValue` | `number` | Weighted rolling thirty-day market value. |
| `bimonthlyMarketValue` | `number` | Weighted rolling sixty-day market value. |

Every key is optional. Unknown, expired, and inapplicable values are omitted.

`firstNonZeroMarketValue` checks `currentMarketValue`, `midweekMarketValue`, `weeklyMarketValue`, `biweeklyMarketValue`, `monthlyMarketValue`, and `bimonthlyMarketValue` in that order. `minBid` and `minBuyout` are literal prices and are never considered market-value sources.

### Item-data wrappers

The following functions accept the same `(itemID, auctionHouseType)` arguments as `GetItemData()` and return only the named value or values. Unavailable values are `nil`:

| Function | Returned key |
| --- | --- |
| `GetAuctionCount()` | `auctionCount` |
| `GetAuctionQuantity()` | `auctionQuantity` |
| `GetMinBid()` | `minBid` |
| `GetMinBuyout()` | `minBuyout` |
| `GetFirstNonZeroMarketValue()` | `firstNonZeroMarketValue`, `firstNonZeroMarketSource` |
| `GetCurrentMarketValue()` | `currentMarketValue` |
| `GetMidweekMarketValue()` | `midweekMarketValue` |
| `GetWeeklyMarketValue()` | `weeklyMarketValue` |
| `GetBiweeklyMarketValue()` | `biweeklyMarketValue` |
| `GetMonthlyMarketValue()` | `monthlyMarketValue` |
| `GetBimonthlyMarketValue()` | `bimonthlyMarketValue` |
| `GetLastScanTime()` | `lastScan` |

`GetFirstNonZeroMarketValue()` is the only wrapper in this group with two returns:

```lua
local firstNonZeroMarketValue, firstNonZeroMarketSource = YAAHA_API.GetFirstNonZeroMarketValue(2589)
```

It returns the selected copper value and its source key, or `nil, nil` when no positive market value is available.

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

Realm statistics are intentionally exposed one value at a time. They are not included in the table returned by `GetItemData()`, and YAAHA's private, realm-wide personal sale rate is never returned by the public API.

Each function accepts `(itemID, auctionHouseType)` using the same validation, optional faction default, and auction-house separation as `GetItemData()`.

| Function | Return type | Description |
| --- | --- | --- |
| `GetRealmSaleRate()` | `number` or `nil` | Fraction of resolved auction quantities sold during the rolling 60-day realm-data window. |
| `GetRealmSoldPerDay()` | `number` or `nil` | Average number of individual items sold per day across the rolling 60-day realm-data window. |
| `GetRealmAverageSaleValue()` | `number` or `nil` | Average gross per-unit auction sale value in copper during the rolling 60-day realm-data window. |

Each observation expires exactly 60 days after its recorded outcome. The private personal sale rate uses the same rolling window. Faction-separated clients keep Alliance, Horde, and Neutral observations isolated. Mists and Retail use their single shared market. These functions return `nil` when the requested value is unavailable or every observation has expired. A known sale rate or daily sold quantity may validly be zero.

### Disenchanting functions

Disenchanting results are universal and are not separated by auction-house type. Expected values use prices from the requested auction house without mixing faction and neutral data.

| Function | Return type | Description |
| --- | --- | --- |
| `IsDisenchantable(itemID)` | `boolean` | Whether YAAHA recognizes the item as disenchantable and has a result range for it. |
| `GetDisenchantResults(itemID)` | `table` or `nil` | A defensive copy of the item's possible materials, probabilities, quantity ranges, expected quantities, required skill, and learned sample count. |
| `GetDisenchantValue(itemID, auctionHouseType, fullResults)` | `number`, `table`, or `nil` | Expected value using current prices from the selected auction house's latest scan. Pass `true` for the complete priced breakdown. Missing prices make the total unavailable. |

`GetDisenchantResults()` returns `YAAHA_API.DisenchantResults`. Each `YAAHA_API.DisenchantMaterial` entry in its `results` array contains `itemID`, `chance`, `minQuantity`, `maxQuantity`, and `expectedQuantity`. `chance` is a decimal fraction. `expectedQuantity` already includes the probability of receiving that material.

`sampleCount` is the number of local and synchronized disenchantments YAAHA has learned for that item category and level range. These observations supplement YAAHA's built-in probabilities on every supported game client. A value of `0` means the result still relies entirely on the built-in dataset; a larger value means observed results have increasingly contributed to the estimate.

For each material, expected value uses the first positive source in this order: `currentMarketValue`, `midweekMarketValue`, `weeklyMarketValue`, `biweeklyMarketValue`, `monthlyMarketValue`, then `bimonthlyMarketValue`. Minimum bid and minimum buyout are never used as substitutes.

#### Disenchant-value arguments

| Value | Type | Description |
| --- | --- | --- |
| `itemID` | `number` | A positive integer item ID. |
| `auctionHouseType` | `string` or `nil` | Optional auction-house type using the same rules as `GetItemData()`. |
| `fullResults` | `boolean` or `nil` | Optional. `true` returns the full breakdown; `false` or omitted returns only the summed value. |

#### Disenchanting examples

Get only the expected disenchant value:

```lua
local value = YAAHA_API.GetDisenchantValue(2589)
```

Request the complete priced breakdown when individual results are needed:

```lua
local results = YAAHA_API.GetDisenchantValue(2589, "Alliance", true)
if results then
    print(results.expectedValue)
end
```

When `fullResults` is `false` or omitted, `GetDisenchantValue()` returns the summed expected value in copper. It returns `nil` when any possible material lacks a positive current market value in the latest scan, because a historical price or partial sum could be mistaken for materials the player can presently obtain or sell.

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

### Crafting functions

YAAHA records recipes when the current character opens a profession window. Crafting calculations use those known recipes and prices from the requested auction house without combining auction-house types.

| Function | Description |
| --- | --- |
| `GetCraftingValue(itemID, auctionHouseType, fullResults, currentCharacterOnly)` | Returns the cheapest known crafting value for an output item. |
| `GetRecipeCraftingValue(spellID, auctionHouseType, fullResults, currentCharacterOnly)` | Returns the crafting value of a specific known recipe, including direct enchants which have no output item. |

#### Crafting-value arguments

| Value | Type | Description |
| --- | --- | --- |
| `itemID` or `spellID` | `number` | Positive integer identifying the crafted item or recipe spell. |
| `auctionHouseType` | `string` or `nil` | Optional auction-house type using the same rules as `GetItemData()`. |
| `fullResults` | `boolean` or `nil` | `true` returns the priced recipe and reagent breakdown; otherwise only the per-unit crafting value is returned. |
| `currentCharacterOnly` | `boolean` or `nil` | `true` restricts recipes to the logged-in character; otherwise all recorded same-faction characters on the realm are considered. |

#### Crafting examples

Get the least expensive known per-unit crafting value for an item:

```lua
local value = YAAHA_API.GetCraftingValue(6452)
```

Request the full recipe and material breakdown, restricted to recipes known by the current character:

```lua
local results = YAAHA_API.GetCraftingValue(6452, nil, true, true)
if results then
    print(results.value, results.outputQuantity)
end
```

When a reagent used by a known recipe has a recorded unlimited-supply NPC price, YAAHA uses that vendor price. Opening a merchant refreshes the account-wide value with the current character's price, including reputation discounts. Auction listings do not override a dependable unlimited vendor source. Otherwise, YAAHA independently considers the reagent's current market value, conversion value, and recursively calculated crafting value, then uses the least expensive available source. Conversion values use the converted source material's current market value; they do not recursively reuse its vendor or crafting value.

Only when every real price and opportunity-cost source fails, YAAHA may estimate a Blizzard-identified Bind on Pickup or quest-bound reagent as `max(vendorSell, (expansionID + 1) * 1g)`. Blizzard numbers Vanilla as expansion `0`, so its fallback floor is `1g`; each subsequent expansion adds another `1g`. Tradeable reagents never use this fallback: a tradeable item absent from the current auction snapshot remains unavailable unless another valid acquisition path exists.

On supported clients other than Classic Era and Forever, a recorded Potion, Elixir, or Transmutation mastery gives matching Vanilla-through-Mists Alchemy recipes an expected finished-item auction-return multiplier of `1.2`. A qualifying same-faction alchemist may supply that adjustment.

A learned Rank 3 Legion or Battle for Azeroth Alchemy recipe uses an expected output multiplier of `1.4`. This recipe-specific adjustment is independent of the character's older mastery: the systems apply to different recipes and never stack. Warlords of Draenor recipes and Rank 1 or Rank 2 Legion and Battle for Azeroth recipes use the baseline multiplier of `1`.

Expected output multipliers never change required reagents, crafting cost, material cost, or the cost of a crafted item when it is used as a reagent. They apply only when estimating the matching finished recipe's auction return.

Neutral and opposite-faction requests on faction-separated clients use the baseline multiplier of `1` because the recorded alchemist cannot sell directly in those markets.

In Wrath/Titan, an equipment-enchant result represents its auctionable scroll. Its crafting value includes the cheapest compatible armor or weapon vellum available through the same material-cost calculation. Classic Era and Burning Crusade equipment enchants retain their reagent cost but have no auctionable output item.

Profession snapshots from an earlier game-client build are marked as stale. YAAHA prefers a current-build copy of a recipe whenever one is available, but retains a stale recipe as a fallback until that character opens the profession and refreshes it. Full crafting results expose this state to consumers.

Variable-yield recipes divide the total reagent value by their average output. A recipe is unavailable when any required reagent has no usable price. Each positive market, vendor, conversion, crafting, or applicable soulbound-fallback value is rounded to whole copper before use. Per-output crafting values and reagent subtotals exposed by the API use the same half-up rounding. A known nonzero value which would otherwise round to zero becomes `1` copper, while an exact zero remains zero and unavailable data remains `nil`.

When `fullResults` is true, the returned `YAAHA_API.CraftingResult` is a defensive snapshot containing:

| Key | Type | Description |
| --- | --- | --- |
| `value` | `number` | Per-unit crafting value in copper. |
| `totalReagentValue` | `number` | Total reagent value for one recipe cast. |
| `outputQuantity` | `number` | Fixed output or average of the minimum and maximum output. |
| `expectedOutputMultiplier` | `number` | Expected finished-item auction-return multiplier: `1` normally, `1.2` for an applicable legacy Alchemy mastery, or `1.4` for a learned Rank 3 Legion or Battle for Azeroth Alchemy recipe. It does not reduce crafting or material costs. |
| `character` | `string` | Canonical character identity whose known recipe supplied the result (`name-realm` or Forever's `firstName-surname`). |
| `profession` | `string` | Localized profession name. |
| `stale` | `boolean` | Whether the profession snapshot predates the current game-client build. |
| `spellID` | `number` | Recipe spell ID. |
| `outputItemID` | `number` or `nil` | Crafted item ID; absent for a direct enchant. |
| `name` | `string` | Localized recipe name. |
| `materials` | `table` | Reagent entries containing `itemID`, `quantity`, `unitValue`, `totalValue`, and the selected `source`. Conversion and nested crafting details are included when applicable. |

The material `source` is exactly `"market"`, `"vendor"`, `"convert"`, `"crafting"`, or `"soulboundFallback"`. The last value is possible only for a Bind on Pickup or quest-bound reagent after every higher-priority source failed. The two functions return `nil` when the recipe is unknown or a complete value cannot be calculated.

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
| `auctionHouseType` | `string` | `"Alliance"`, `"Horde"`, or `"Neutral"` on faction-separated clients; `"Shared"` on clients with one shared auction house. |
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

On Classic Era, Burning Crusade, Wrath/Titan, and Forever, omitting `auctionHouseType` or passing `nil` accesses the current character's faction auction-house database. Explicit `"Alliance"`, `"Horde"`, and `"Neutral"` values access only their corresponding databases. Opposite-faction data is available when YAAHA has received or recorded it. YAAHA never substitutes or combines another market on these clients.

Mists and Retail have one shared auction house rather than separate faction and neutral markets. On those clients, omitting the argument or passing `"Alliance"`, `"Horde"`, `"Neutral"`, or `"Shared"` accesses that same shared database. Callbacks identify it as `"Shared"`. Other strings are invalid on every client.

Some modern commodities are traded across a region, but YAAHA has no external service which aggregates region-wide sales. Its public values remain the data visible through the local auction house and YAAHA's realm-derived sale observations; the API does not claim to provide region-wide statistics.

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

Negative monetary values are invalid and are not returned.
