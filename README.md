# YAAHA

YAAHA (Yet Another Auction House AddOn) helps World of Warcraft players understand prices, evaluate crafting costs, and find worthwhile auction-house deals without becoming a full TradeSkillMaster replacement.

> [!IMPORTANT]
> YAAHA is under active development and is not yet ready for a public release. Features, settings, and saved data may change while the addon is being built.

## Features

- Fast auction-house scans with minimum bids, minimum buyouts, quantities, and market values covering the current scan and rolling 3, 7, 14, 30, and 60-day periods.
- Configurable item tooltips with auction prices, trends, vendor values, inventory purchase values, crafting costs, conversions, and material breakdowns.
- Crafting costs which compare current market prices, vendor supplies, known recipes, conversions, and supported special material valuations. Applicable Alchemy specializations and recipe bonuses are included.
- Disenchanting, prospecting, and milling estimates where those professions are available.
- Guided vendor-flip, disenchanting, prospecting, and milling deal searches, with configurable value thresholds. YAAHA never purchases an item without the player's action.
- Rolling 60-day personal sales information across the player's realm, plus market-specific realm statistics.
- Optional guild synchronization of supported market and learned breakdown data. Personal activity and vendor-flip profit remain private.
- An optional minimap button and LibDataBroker display showing accumulated vendor-flip profit.

## Supported game versions

YAAHA's current auction-house workflow supports:

- World of Warcraft Classic Era
- WoW Classic: Forever
- The Burning Crusade Classic
- Wrath of the Lich King Classic and Titan Reforged

Support for Mists of Pandaria Classic and Retail (mainline), including their shared auction-house and commodity systems, is under development and is not yet complete.

## Getting started

1. Visit an auction house and use YAAHA's tab to scan the current market and search for deals.
2. Open profession windows so YAAHA can record the recipes known by that character.
3. Open relevant merchants to refresh prices for vendor-supplied crafting materials.
4. Hover over items to view the enabled YAAHA tooltip information.

Hold **Shift** while viewing an item tooltip to multiply applicable values by the stack size. On faction-based clients, **Alt** shows Neutral auction-house data and **Ctrl** shows opposite-faction data when available.

## Options

Enter `/yaaha`, use **Esc > Options > AddOns > YAAHA**, or click YAAHA's minimap or Broker icon.

## Addon developers

YAAHA exposes auction and item information through the global `YAAHA_API` table. See the [public API documentation](https://github.com/Myrroddin/yaaha/blob/main/API/API.md) for integration details and update callbacks.

## License

YAAHA's original source and content are proprietary and all rights are reserved, subject to limited permissions for personal use and modification, direct non-commercial sharing of unmodified release packages, and distribution through addon-hosting services authorized by the copyright holder. Modified copies may not be distributed, and no warranty is provided. Embedded third-party libraries remain subject to their respective licenses. See [LICENSE](https://github.com/Myrroddin/yaaha/blob/main/LICENSE) for details.
