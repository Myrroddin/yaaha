# YAAHA Public API

YAAHA exposes a deliberately small public API to other World of Warcraft addons through the global `YAAHA_API` table. It is a normal global, not a LibStub library.

> [!IMPORTANT]
> YAAHA and its public API are under active development. Names, signatures, callbacks, returned structures, and behavior may change before the first stable release. The API version remains `1` during this pre-release design period.

## Contents

- [Quick start](#quick-start)
- [Common conventions](#common-conventions)
  - [Calling functions](#calling-functions)
  - [Auction-house types](#auction-house-types)
  - [Unavailable data](#unavailable-data)
  - [Numbers and money](#numbers-and-money)
- [Versioning](#versioning)
- [Item market data](#item-market-data)
  - [`GetItemData`](#getitemdata)
  - [`IterateAuctionHouse`](#iterateauctionhouse)
  - [Item-data wrappers](#item-data-wrappers)
  - [`GetAuctionHouseStats`](#getauctionhousestats)
- [Realm sale metrics](#realm-sale-metrics)
- [Disenchanting](#disenchanting)
  - [`IsDisenchantable` and `GetDisenchantResults`](#isdisenchantable-and-getdisenchantresults)
  - [`GetDisenchantValue`](#getdisenchantvalue)
- [Crafting](#crafting)
  - [Crafting functions](#crafting-functions)
  - [Crafting results](#crafting-results)
  - [Material results](#material-results)
- [Callbacks](#callbacks)
- [Editor support](#editor-support)

## Quick start

Declare YAAHA as a required or optional dependency in the consuming addon's TOC when it must load first. Test the global before using an optional dependency:

```lua
if YAAHA_API then
    local value, source = YAAHA_API.GetFirstNonZeroMarketValue(2589)
    if value then
        print(value, source)
    end
end
```

Do not retrieve the API through LibStub:

```lua
-- Incorrect: YAAHA_API is not a LibStub library.
local API = LibStub("YAAHA_API")
```

## Common conventions

### Calling functions

Public functions use dot-call syntax because they are functions on a global namespace, not object methods:

```lua
local version = YAAHA_API.GetVersion()
```

### Auction-house types

Functions which accept `auctionHouseType` recognize these strings:

| Value | Meaning |
| --- | --- |
| `"Alliance"` | Alliance market on a faction-separated client. |
| `"Horde"` | Horde market on a faction-separated client. |
| `"Neutral"` | Neutral market on a faction-separated client. |
| `"Shared"` | The single shared market on Mists and Retail. |

On Classic Era, Burning Crusade, Wrath/Titan, and Forever, omitting the argument or passing `nil` uses the current character's faction market. Explicit values never combine faction and neutral data.

Mists and Retail use one shared market. On those clients, `nil`, `"Alliance"`, `"Horde"`, `"Neutral"`, and `"Shared"` all resolve to the same shared database. This normalization lets a consumer use one call path across clients. Any other string is invalid.

Some modern commodities are traded region-wide, but YAAHA has no external aggregation service. The API reports data observed through the local auction house and does not claim to provide region-wide statistics.

### Unavailable data

Functions return `nil` when data is unknown, expired, inapplicable, or the request is invalid. Optional table fields are omitted for the same reasons. YAAHA does not invent a price or silently substitute another auction-house type.

Returned tables are defensive snapshots. Changing them does not modify YAAHA's saved or working data.

### Numbers and money

- Item IDs, spell IDs, quantities, counts, skills, and timestamps are numbers; IDs must be positive integers.
- Market values, prices, and crafting values are whole copper. Positive fractional copper is rounded half-up and remains at least `1` copper.
- Sale rates and result chances are decimal fractions. For example, `0.311` means `31.1%`.
- Public sale rates are rounded half-up to at most three decimal places.

## Versioning

The current public API version is `1`. It is independent of YAAHA's addon release version and changes only when consumers must distinguish a new public contract.

```lua
if YAAHA_API and YAAHA_API.version >= 1 then
    -- API version 1 is available.
end

local version = YAAHA_API.GetVersion()
```

Both `YAAHA_API.version` and `GetVersion()` return the same integer.

## Item market data

### `GetItemData`

```lua
local data = YAAHA_API.GetItemData(itemID, auctionHouseType)
```

Returns `nil` when YAAHA has no public data for the item. Otherwise it returns a `YAAHA_API.ItemData` snapshot. Raw observations, personal activity, vendor-flip activity, and other private processing data are intentionally excluded.

| Key | Type | Meaning |
| --- | --- | --- |
| `auctionCount` | `integer?` | Number of listings in the current snapshot. |
| `auctionQuantity` | `integer?` | Number of individual items represented by those listings. |
| `lastScan` | `integer?` | Server timestamp of the current item snapshot. Omitted when the item was absent from the latest scan. |
| `minBid` | `integer?` | Lowest payable per-unit bid in copper. |
| `minBuyout` | `integer?` | Lowest per-unit buyout in copper. |
| `firstNonZeroMarketValue` | `integer?` | First positive market value in copper from the shortest available time frame. |
| `firstNonZeroMarketSource` | `string?` | Field which supplied `firstNonZeroMarketValue`. |
| `currentMarketValue` | `integer?` | Market value calculated from the current scan. |
| `midweekMarketValue` | `integer?` | Weighted rolling three-day market value. |
| `weeklyMarketValue` | `integer?` | Weighted rolling seven-day market value. |
| `biweeklyMarketValue` | `integer?` | Weighted rolling fourteen-day market value. |
| `monthlyMarketValue` | `integer?` | Weighted rolling thirty-day market value. |
| `bimonthlyMarketValue` | `integer?` | Weighted rolling sixty-day market value. |

`firstNonZeroMarketValue` checks the six market-value fields from current through sixty-day. Its source is the matching field name. Minimum bid and buyout are literal prices and are never market-value fallbacks.

### `IterateAuctionHouse`

```lua
local iterator = YAAHA_API.IterateAuctionHouse(auctionHouseType)
if iterator then
    for itemID, data in iterator do
        print(itemID, data.currentMarketValue)
    end
end
```

Returns an iterator over every item for which YAAHA has public data in the selected auction house. Each iteration returns the item ID and the same defensive `ItemData` snapshot returned by `GetItemData`. Results are ordered by ascending item ID and remain stable for the lifetime of that iterator, even if YAAHA processes a later scan or synchronization update.

An invalid auction-house type returns `nil`. A valid auction house with no item data returns an iterator which yields no results. The iterator never exposes raw observations, private activity, or mutable internal tables.

### Item-data wrappers

These functions accept `(itemID, auctionHouseType)` and return only the named value. An unavailable value is `nil`.

| Function | Return |
| --- | --- |
| `GetAuctionCount` | `auctionCount` |
| `GetAuctionQuantity` | `auctionQuantity` |
| `GetMinBid` | `minBid` |
| `GetMinBuyout` | `minBuyout` |
| `GetFirstNonZeroMarketValue` | `firstNonZeroMarketValue, firstNonZeroMarketSource` |
| `GetCurrentMarketValue` | `currentMarketValue` |
| `GetMidweekMarketValue` | `midweekMarketValue` |
| `GetWeeklyMarketValue` | `weeklyMarketValue` |
| `GetBiweeklyMarketValue` | `biweeklyMarketValue` |
| `GetMonthlyMarketValue` | `monthlyMarketValue` |
| `GetBimonthlyMarketValue` | `bimonthlyMarketValue` |
| `GetLastScanTime` | `lastScan` |

### `GetAuctionHouseStats`

```lua
local stats = YAAHA_API.GetAuctionHouseStats(auctionHouseType)
```

Returns `nil` when no complete scan or synchronized snapshot is available. Otherwise it returns a `YAAHA_API.AuctionHouseStats` snapshot:

| Key | Type | Meaning |
| --- | --- | --- |
| `lastScan` | `integer` | Server timestamp of the latest complete snapshot. |
| `totalListings` | `integer` | Number of listings represented by the snapshot. |
| `totalItems` | `integer` | Number of distinct item IDs represented by the snapshot. |

## Realm sale metrics

These functions accept `(itemID, auctionHouseType)`. Each observation expires exactly 60 days after its confirmed auction outcome.

| Function | Return | Meaning |
| --- | --- | --- |
| `GetRealmRollingSaleRate` | `number?` | Confirmed sold quantity divided by observed resolved listing and purchase quantity in the rolling window. |
| `GetRealmRollingSalesPerDay` | `number?` | Confirmed sold quantity divided by YAAHA's observed market window, from one day up to 60 days. |
| `GetRealmRollingAverageSaleValue` | `integer?` | Average gross per-unit sale value in copper. |

YAAHA treats a confirmed purchase as evidence that the market sold that quantity, whether the buyer later uses, transforms, destroys, vendors, or relists the item. Buyer observations affect only realm metrics; they never affect the private personal sale rate. When guild synchronization supplies both sides of one transaction, YAAHA deduplicates them by Blizzard's auction ID where available or by matching the Classic invoice's seller with the item, quantity, value, and nearby timestamps from both sides. Observations without enough matching evidence remain independent rather than being guessed into one transaction.

The quantity is transaction volume, not a count of unique physical items. Buying 127 cloth confirms 127 sold. If three of those are later resold through the auction house, that second transaction adds three more, for 130 observed sales in total. Selling them to an NPC does not create another auction-house sale.

Faction-separated clients keep Alliance, Horde, and Neutral observations separate. Mists and Retail use their shared market. These values describe confirmed transactions YAAHA observed or received through guild synchronization; they are not a claim to cover every transaction in the market. A known sale rate or sales-per-day value may validly be `0`; `nil` means there is no usable observation.

The observed window begins when YAAHA first tracks that market. Guild synchronization may move its start earlier when another installation supplies older observations. The denominator has a one-day minimum for a new installation and reaches a maximum of 60 days. Consequently, one item sold during a mature 60-day window returns approximately `0.016667`, while one item sold during the first observed day returns `1`. The API preserves the fractional value; YAAHA applies the user's decimal-place preference only when displaying it.

Personal sale history is private user activity and is not exposed by the public API.

## Disenchanting

Disenchant result ranges are not separated by auction-house type. Pricing those results does use the requested market.

### `IsDisenchantable` and `GetDisenchantResults`

```lua
local known = YAAHA_API.IsDisenchantable(itemID)
local breakdown = YAAHA_API.GetDisenchantResults(itemID)
```

`IsDisenchantable` returns whether YAAHA recognizes the item and has a result range. `GetDisenchantResults` returns `nil` when it does not, or a `YAAHA_API.DisenchantResults` snapshot:

| Key | Type | Meaning |
| --- | --- | --- |
| `requiredSkill` | `integer` | Required Enchanting skill. |
| `sampleCount` | `integer` | Learned local and synchronized observations contributing to the result range. `0` means the built-in dataset is being used without learned observations. |
| `results` | `DisenchantMaterial[]` | Possible materials. |

Each material contains:

| Key | Type | Meaning |
| --- | --- | --- |
| `itemID` | `integer` | Resulting enchanting-material item ID. |
| `chance` | `number` | Decimal probability of receiving the material. |
| `minQuantity` | `integer` | Minimum possible quantity. |
| `maxQuantity` | `integer` | Maximum possible quantity. |
| `expectedQuantity` | `number` | Probability-adjusted expected quantity per disenchant. |

### `GetDisenchantValue`

```lua
local value = YAAHA_API.GetDisenchantValue(itemID, auctionHouseType)
local full = YAAHA_API.GetDisenchantValue(itemID, auctionHouseType, true)
```

YAAHA prices each possible material with its positive `currentMarketValue` from the selected market. Historical market windows, minimum bids, and minimum buyouts are not substituted. This keeps the result tied to materials present in the latest market snapshot.

Without `fullResults`, the function returns the summed expected value in copper. It returns `nil` when the item is unknown, the request is invalid, or any possible material lacks a current price.

With `fullResults = true`, it returns a `YAAHA_API.PricedDisenchantResults` snapshot only when every possible material has a valid current price. If any price is missing, the entire API call returns `nil`; the public API never exposes a partial priced result:

| Key | Type | Meaning |
| --- | --- | --- |
| `expectedValue` | `integer` | Complete expected value in copper. |
| `requiredSkill` | `integer` | Required Enchanting skill. |
| `sampleCount` | `integer` | Learned observation count. |
| `results` | `PricedDisenchantMaterial[]` | Priced possible materials. |

Each priced material contains the fields from `DisenchantMaterial` plus:

| Key | Type | Meaning |
| --- | --- | --- |
| `marketValue` | `integer` | Per-unit current market value in copper. |
| `priceSource` | `string` | `"currentMarketValue"`. |
| `expectedValue` | `integer` | Probability-adjusted value in copper. |
| `missingPrice` | `boolean` | Always `false`; incomplete priced results return `nil`. |

## Crafting

YAAHA can value recipes it has recorded from profession windows. Calculations use prices from the requested market and do not mix auction-house types.

### Crafting functions

```lua
local value = YAAHA_API.GetCraftingValue(
    itemID,
    auctionHouseType,
    fullResults,
    currentCharacterOnly
)

local value = YAAHA_API.GetRecipeCraftingValue(
    spellID,
    auctionHouseType,
    fullResults,
    currentCharacterOnly
)
```

| Function | Meaning |
| --- | --- |
| `GetCraftingValue` | Finds the least expensive recorded recipe for an output item. |
| `GetRecipeCraftingValue` | Values one recorded recipe spell, including direct enchants without an output item. |

`fullResults = true` returns a `CraftingResult`; otherwise the return is only its per-unit `value`. `currentCharacterOnly = true` restricts candidates to the logged-in character. When it is false or omitted, all recipes in the applicable faction-realm profession store may be considered.

Both functions return `nil` when the recipe is unknown or any required material lacks a valid acquisition value. A tradeable reagent absent from the current market remains unavailable unless YAAHA knows another real vendor, conversion, crafting, or authoritative derived-value path. Only soulbound or quest-bound materials may receive a final estimated fallback.

### Crafting results

A full result is a `YAAHA_API.CraftingResult` snapshot:

| Key | Type | Meaning |
| --- | --- | --- |
| `value` | `integer` | Per-unit crafting value in copper. |
| `totalReagentValue` | `integer` | Reagent value for one recipe cast in copper. |
| `outputQuantity` | `number` | Fixed output, or the average of the minimum and maximum output. |
| `expectedOutputMultiplier` | `number` | Expected finished-item auction-return multiplier from an applicable Alchemy specialization. Current values are `1`, `1.2`, or `1.4`. It never reduces material or crafting costs. |
| `character` | `string` | Character whose known recipe supplied the result: `name-realm` normally or `firstName surname` on Forever. |
| `profession` | `string` | Localized profession name. |
| `stale` | `boolean` | Whether the saved profession snapshot predates the current game-client build. A stale result remains usable until that character refreshes the profession. |
| `spellID` | `integer` | Recipe spell ID. |
| `outputItemID` | `integer?` | Crafted item ID; omitted for a direct enchant. |
| `name` | `string` | Localized recipe name. |
| `materials` | `CraftingMaterial[]` | Priced reagents for one recipe cast. |

### Material results

Each crafting material contains:

| Key | Type | Meaning |
| --- | --- | --- |
| `itemID` | `integer` | Reagent item ID. |
| `quantity` | `number` | Quantity required for one recipe cast. |
| `unitValue` | `integer` | Selected per-unit value in copper. |
| `totalValue` | `integer` | Value of the required quantity in copper. |
| `source` | `string` | Acquisition source which supplied `unitValue`. |
| `conversion` | `CraftingConversion?` | Single-source conversion details when `source` is `"convert"`; absent for averaged conversion families. |
| `crafting` | `CraftingResult?` | Nested recipe details when `source` is `"crafting"`. |

`source` has one of these meanings:

| Value | Meaning |
| --- | --- |
| `"market"` | The reagent's current market value. |
| `"vendor"` | A known unlimited-supply NPC price. |
| `"convert"` | A known conversion or complete averaged conversion family was less expensive. |
| `"crafting"` | A recorded recipe for the reagent was less expensive. |
| `"derived"` | An authoritative item-specific method replaced YAAHA's default material-cost method and supplied the material's opportunity cost. |
| `"soulboundFallback"` | A last-resort estimate for a soulbound or quest-bound reagent after real values failed. |

A `CraftingConversion` contains the source material's `itemID`, the source `quantity` required for one requested unit, and `priceSource`. Conversion pricing currently uses the source material's `currentMarketValue`, so a present `priceSource` is `"currentMarketValue"`. When several interchangeable conversion paths exist, YAAHA averages their complete per-unit costs before comparing that family with other acquisition methods. Because no individual source represents the average, `conversion` is omitted for that material.

## Callbacks

YAAHA uses CallbackHandler-1.0 internally, but consumers register directly through `YAAHA_API`:

```lua
local consumer = {}

function consumer:OnAuctionHouseDataUpdated(event, auctionHouseType, source)
    local stats = YAAHA_API.GetAuctionHouseStats(auctionHouseType)
    -- The complete updated snapshot is ready to query here.
end

YAAHA_API.RegisterCallback(
    consumer,
    "AUCTION_HOUSE_DATA_UPDATED",
    "OnAuctionHouseDataUpdated"
)
```

Available registration helpers are:

| Function | Purpose |
| --- | --- |
| `RegisterCallback(receiver, event, method, arg)` | Registers a method name or callback function. When supplied, `arg` is inserted before the callback's normal event arguments. |
| `UnregisterCallback(receiver, event)` | Removes the receiver's registration for one event. |
| `UnregisterAllCallbacks(receiver)` | Removes all registrations for the receiver. |

### `AUCTION_HOUSE_DATA_UPDATED`

Fires after YAAHA commits and recalculates a complete auction-house database which actually changed.

| Argument | Type | Meaning |
| --- | --- | --- |
| `event` | `string` | Always `"AUCTION_HOUSE_DATA_UPDATED"`. |
| `auctionHouseType` | `string` | `"Alliance"`, `"Horde"`, or `"Neutral"` on faction-separated clients; `"Shared"` on shared-market clients. |
| `source` | `string` | `"scan"` for a completed local scan or `"sync"` for newly merged guild data. |

A synchronized packet which adds no newer or missing data does not fire the callback. Consumers may query the API immediately from the callback and will not observe a partially processed scan or merge.

## Editor support

`API.lua` publishes [WoWLua-LS](https://tradeskillmaster.github.io/wowlua-ls/guide/why-wowlua-ls) annotations for the global API, accepted auction-house strings, callbacks, and return tables. When YAAHA's source is visible to the language server, consumers receive completion, hover documentation, literal suggestions, argument checking, and nil-aware return types.

Supporting names such as `YAAHA_API.ItemData` and `YAAHA_API.CraftingResult` are editor metadata, not runtime fields consumers must access.
