# YAAHA

YAAHA (Yet Another Auction House AddOn) helps World of Warcraft players understand market prices, evaluate crafting costs, and find worthwhile auction-house deals.

> [!IMPORTANT]
> YAAHA is under active development and is not yet ready for a public release. Features, settings, and saved data may change while the addon is being built.

YAAHA requires both folders included in its release. `YAAHA` provides the
features and interface, while `YAAHA_AuctionDB` stores market values and price
history separately from personal settings and activity. Disabling or removing
either folder leaves the installation incomplete.

## Approach

YAAHA favors current, observable information and keeps distinct auction-house
markets separate. Unknown prices remain unknown rather than being silently
invented or borrowed from another market. Values are presented per item by
default, and every bid or purchase remains under the player's control.

## Features

- Auction-house scans with minimum bids, minimum buyouts, quantities, current market values, and rolling 3, 7, 14, 30, and 60-day trends.
- Configurable item tooltips covering auction prices, vendor values, inventory purchase values, crafting and reagent costs, conversions, and material breakdowns.
- Crafting costs which compare available market, vendor, recipe, conversion, and supported derived-material paths. Applicable Alchemy bonuses and Retail Resourcefulness and Multicraft expectations are included.
- Disenchanting, prospecting, and milling estimates where those professions are available.
- Vendor-flip, disenchanting, prospecting, and milling deal searches with configurable thresholds.
- Rolling 60-day personal sales information and market-specific realm sales metrics.
- Optional guild synchronization of supported market, realm-sale, and learned breakdown data with eligible guild members. Personal activity and vendor-flip profit remain private.
- An optional minimap or Broker display showing accumulated vendor-flip profit.

## Supported game versions

YAAHA's current auction-house workflow supports:

- World of Warcraft Classic Era
- WoW Classic: Forever
- The Burning Crusade Classic
- Wrath of the Lich King Classic and Titan Reforged

Support for Mists of Pandaria Classic and Retail, including their shared
auction-house and commodity systems, remains under active development and
testing.

## Getting started

1. Visit an auction house and use YAAHA's tab to scan the current market and search for deals.
2. Open profession windows so YAAHA can record the recipes known by that character.
3. Open relevant merchants to refresh prices for vendor-supplied crafting materials.
4. Hover over items to view the enabled YAAHA tooltip information.

YAAHA displays prices, costs, and breakdown values per individual item.
Prospecting and milling therefore show one-fifth of a complete five-item
operation. Hold **Shift** while viewing an item tooltip to multiply applicable
values by the stack size. On faction-based clients, **Alt** shows Neutral
auction-house data and **Ctrl** shows opposite-faction data when available.

## Options

Enter `/yaaha`, use **Esc > Options > AddOns > YAAHA**, or click YAAHA's minimap or Broker icon.

## Addon developers

YAAHA exposes auction and item information through the global `YAAHA_API` table. See the [public API documentation](https://github.com/Myrroddin/yaaha/blob/main/API/API.md) for integration details and update callbacks.

## License

YAAHA's original source and content are proprietary and all rights are reserved, subject to limited permissions for personal use and modification, direct non-commercial sharing of unmodified release packages, and distribution through addon-hosting services authorized by the copyright holder. Modified copies may not be distributed, and no warranty is provided. Embedded third-party libraries remain subject to their respective licenses. See [LICENSE](https://github.com/Myrroddin/yaaha/blob/main/LICENSE) for details.
