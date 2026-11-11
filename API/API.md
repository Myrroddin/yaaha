# YAAHA Public API

YAAHA exposes a deliberately small public API to other World of Warcraft addons through the global `YAAHA_API` table. It is a normal global, not a LibStub library.

The release includes the required `YAAHA_AuctionDB` companion addon, which owns
YAAHA's market-value and trend database. This storage boundary does not change
the public contract: consumers query `YAAHA_API` and must not read either addon's
saved variables or AceDB database directly.

> [!IMPORTANT]
> YAAHA and its public API are under active development. Names, signatures, callbacks, returned structures, and behavior may change before the first stable release. The API version remains `1` during this pre-release design period.

## Contents

- [Quick start](#quick-start)
- [Common conventions](#common-conventions)
  - [Calling functions](#calling-functions)
  - [Item IDs and per-unit results](#item-ids-and-per-unit-results)
  - [Auction-house types](#auction-house-types)
  - [Unavailable data](#unavailable-data)
  - [Numbers and money](#numbers-and-money)
- [Versioning](#versioning)
- [Item market data](#item-market-data)
  - [`GetItemData`](#getitemdata)
  - [`IterateAuctionHouse`](#iterateauctionhouse)
  - [Item-data wrappers](#item-data-wrappers)
  - [`GetAuctionHouseStats`](#getauctionhousestats)
- [Price sources](#price-sources)
  - [`GetPriceSourceValue`](#getpricesourcevalue)
  - [`IsPriceSourceValid`](#ispricesourcevalid)
  - [`GetPriceSourceDescription`](#getpricesourcedescription)
- [Realm sale metrics](#realm-sale-metrics)
- [Material breakdowns](#material-breakdowns)
  - [`IsBreakable` and `GetBreakdownResults`](#isbreakable-and-getbreakdownresults)
  - [`GetBreakdownValue`](#getbreakdownvalue)
- [Crafting](#crafting)
  - [Crafting functions](#crafting-functions)
  - [Crafting results](#crafting-results)
  - [Material results](#material-results)
- [Callbacks](#callbacks)
- [Editor support](#editor-support)

## Quick start

Declare YAAHA as a required or optional dependency in the consuming addon's TOC when it must load first. Consumers depend on `YAAHA`, not its internal database companion. Test the global before using an optional dependency:

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

### Item IDs and per-unit results

An `itemID` identifies an item type, not an inventory quantity. Passing an
`itemID` never tells YAAHA how many copies the player owns and does not ask YAAHA
whether the player currently has enough items, profession skill, or other
requirements to perform an action.

Unless a field explicitly describes an auction count, auction quantity, observed
transaction quantity, or complete breakdown operation, every item price, value,
and cost returned for an `itemID` is for one unit. APIs do not multiply results by
the player's inventory, cursor stack, auction stack, or a profession's required
input quantity.

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

## Price sources

YAAHA price-source keys let consumers select a supported valuation without mapping
each key to a separate API function. All values are per item and expressed in copper.

| Key | Localized description | Meaning |
| --- | --- | --- |
| `minBid` | YAAHA Minimum bid | Lowest payable bid in the current snapshot. |
| `minBuyout` | YAAHA Minimum buyout | Lowest buyout in the current snapshot. |
| `currentMarketValue` | YAAHA Current market value | Market value calculated from the current scan. |
| `midweekMarketValue` | YAAHA 3-day market value | Weighted rolling three-day market value. |
| `weeklyMarketValue` | YAAHA 7-day market value | Weighted rolling seven-day market value. |
| `biweeklyMarketValue` | YAAHA 14-day market value | Weighted rolling fourteen-day market value. |
| `monthlyMarketValue` | YAAHA 30-day market value | Weighted rolling thirty-day market value. |
| `bimonthlyMarketValue` | YAAHA 60-day market value | Weighted rolling sixty-day market value. |
| `crafting` | YAAHA Crafting cost | Complete per-unit cost of a known recipe producing the item. |
| `reagentCost` | YAAHA Reagent cost | YAAHA's complete material cost for an item used by a known recipe. |
| `breakdown` | YAAHA Expected breakdown value | Complete expected per-unit disenchanting, prospecting, or milling value. |

`firstNonZeroMarketValue` is a convenience result, not a price-source key. Its
`firstNonZeroMarketSource` identifies the actual market source which supplied it.
Material acquisition labels such as `market`, `vendor`, `convert`, `derived`, and
`soulboundFallback` are provenance details and are not price-source keys.

### `GetPriceSourceValue`

```lua
local value, errorMessage = YAAHA_API.GetPriceSourceValue(
    "reagentCost",
    itemID,
    auctionHouseType
)
```

Returns the source's per-item value, or `nil` followed by a non-localized error
message. Every price source must resolve to a positive value.

`crafting` is available only for an output produced by a known recipe.
`reagentCost` is available only when the item is used by at least one known recipe
in the active faction-realm. Its calculation first honors an authoritative
item-specific derived method.
Without one, a known unlimited vendor price is authoritative; otherwise YAAHA
compares the current market value, conversions, and recursively known crafting
paths. The soulbound estimate is the final eligible fallback.

### `IsPriceSourceValid`

```lua
local valid, errorMessage = YAAHA_API.IsPriceSourceValid(
    priceSource,
    itemID,
    auctionHouseType
)
```

Returns whether the recognized source currently resolves to an allowed value for
that item and market. Consequently, a recognized source may be invalid for one
item and valid for another. Error messages are stable English diagnostics intended
for developers and are not localized.

### `GetPriceSourceDescription`

```lua
local description, errorMessage =
    YAAHA_API.GetPriceSourceDescription("currentMarketValue")
-- "YAAHA Current market value" in an English client
```

Returns the localized, YAAHA-prefixed display name. It validates only the source
key because descriptions do not depend on an item or auction house. An unknown key
returns `nil` followed by a non-localized error message.

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

## Material breakdowns

YAAHA presents disenchanting, prospecting, and milling through one breakdown
contract. Result ranges are global; pricing their outputs uses the requested
auction house. The aggregate price is always for one input item, even when the
game requires five ores or herbs to perform one prospecting or milling cast.

### `IsBreakable` and `GetBreakdownResults`

```lua
local known = YAAHA_API.IsBreakable(itemID)
local breakdown = YAAHA_API.GetBreakdownResults(itemID)
```

`IsBreakable` is a strict item-classification Boolean: it returns `true` when
YAAHA recognizes the item as breakable by any supported mechanic, and `false`
otherwise. It does not inspect the player's inventory, profession, skill, or
ability to perform that action. For example, it returns `true` for a recognized
prospectable ore or millable herb even when the player owns fewer than the five
items required for one operation.

`GetBreakdownResults` returns `nil` when YAAHA does not recognize the item, or a
`YAAHA_API.BreakdownResults` snapshot:

| Key | Type | Meaning |
| --- | --- | --- |
| `breakdownType` | `string` | `"disenchanting"`, `"prospecting"`, or `"milling"`. |
| `requiredQuantity` | `integer` | Input quantity consumed by one operation: normally `1` for disenchanting or `5` for prospecting and milling. |
| `requiredSkill` | `integer` | Required profession skill. |
| `sampleCount` | `integer` | Learned local and synchronized observations contributing to the result range. `0` means only the built-in dataset is used. |
| `results` | `BreakdownMaterial[]` | Possible material results for one operation. |

Each material contains:

| Key | Type | Meaning |
| --- | --- | --- |
| `itemID` | `integer` | Resulting material item ID. |
| `chance` | `number` | Decimal probability of receiving the material from one operation. |
| `minQuantity` | `integer` | Minimum possible quantity per operation. |
| `maxQuantity` | `integer` | Maximum possible quantity per operation. |
| `expectedQuantity` | `number` | Probability-adjusted expected quantity per operation. |

### `GetBreakdownValue`

```lua
local value = YAAHA_API.GetBreakdownValue(itemID, auctionHouseType)
local full = YAAHA_API.GetBreakdownValue(itemID, auctionHouseType, true)
```

YAAHA prices every possible result with its positive `currentMarketValue` from
the selected market. Historical market windows, minimum bids, and minimum buyouts
are not substituted. This keeps the value tied to materials present in the latest
market snapshot.

Without `fullResults`, the function returns the complete expected value of one
input item in copper. It returns `nil` when the item is unknown, the request is
invalid, or any possible result lacks a current price.

With `fullResults = true`, it returns a `YAAHA_API.PricedBreakdownResults`
snapshot only when every possible material has a valid current price. The public
API never exposes a partial aggregate:

| Key | Type | Meaning |
| --- | --- | --- |
| `expectedValue` | `integer` | Complete expected value per input item in copper. |
| `breakdownType` | `string` | Applicable breakdown mechanic. |
| `requiredQuantity` | `integer` | Input quantity consumed by one operation. |
| `requiredSkill` | `integer` | Required profession skill. |
| `sampleCount` | `integer` | Learned observation count. |
| `results` | `PricedBreakdownMaterial[]` | Priced possible materials for one operation. |

Each priced material contains the fields from `BreakdownMaterial` plus:

| Key | Type | Meaning |
| --- | --- | --- |
| `marketValue` | `integer` | Per-unit current market value in copper. |
| `priceSource` | `string` | `"currentMarketValue"`. |
| `expectedValue` | `integer` | Probability-adjusted material value per operation in copper. |
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

On Retail, YAAHA records the current character's recipe-specific Resourcefulness and Multicraft chances when the profession is scanned. Profession equipment and specialization changes made while that profession is open trigger another scan. Other characters retain their last recorded profession snapshot until their profession is opened again. A recipe unsupported by either stat retains a zero chance and receives no adjustment.

### Crafting results

A full result is a `YAAHA_API.CraftingResult` snapshot:

| Key | Type | Meaning |
| --- | --- | --- |
| `value` | `integer` | Expected per-unit crafting value in copper after Resourcefulness and Multicraft. |
| `totalReagentValue` | `integer` | Raw reagent value for one recipe cast in copper, before Resourcefulness. |
| `expectedReagentValue` | `integer` | Expected reagent value for one cast after Resourcefulness. |
| `resourcefulnessSavings` | `integer` | Expected Resourcefulness savings for one cast in copper. |
| `outputQuantity` | `number` | Base fixed output, or the average of the minimum and maximum output. |
| `effectiveOutputQuantity` | `number` | Expected average output for one cast after Multicraft. |
| `resourcefulnessChance` | `number` | Recipe-specific Resourcefulness proc chance from `0` to `1`. |
| `multicraftChance` | `number` | Recipe-specific Multicraft proc chance from `0` to `1`. |
| `expectedResourcefulnessRefund` | `number` | Expected fraction of eligible reagent value saved per cast, including recipe-specific specialization bonuses. |
| `expectedMulticraftYield` | `number` | Expected extra output as a fraction of base output, including recipe-specific specialization bonuses. |
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
| `resourcefulnessEligible` | `boolean` | Whether this required reagent contributes to expected Resourcefulness savings. |
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
