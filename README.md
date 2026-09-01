# YAAHA

YAAHA (Yet Another Auction House AddOn) helps players understand auction-house prices, spot useful deals, and make better buying and selling decisions in World of Warcraft Classic.

> [!IMPORTANT]
> YAAHA is under active development and is not yet ready for a public release. Features, settings, and saved data may change while the addon is being built.

## Supported versions

- World of Warcraft Classic Era
- The Burning Crusade Classic
- Wrath of the Lich King Classic (Titan Reforged)

Mists of Pandaria Classic and modern World of Warcraft are not currently supported.

## Features

### Auction-house scanning

Start a fast, complete scan from YAAHA's auction-house window. YAAHA records the active auction house without combining Alliance, Horde, or Neutral data.

Scans provide minimum bids, minimum buyouts, available quantities, and market values covering the current scan and the past 3, 7, 14, 30, and 60 days.

### Informative tooltips

YAAHA can add useful auction information to item tooltips, including:

- Current and historical market values
- Price trends
- Minimum bid and buyout
- Quantity available at auction
- Personal and realm sale information
- Vendor buy and sell prices
- Average purchase value for items still owned
- Disenchanting results and estimated value

Tooltip entries are configurable. Hold Alt for neutral auction-house data, Ctrl for
opposite-faction data, or Shift to multiply prices by the stack under the cursor.

### Vendor deals

The Deals page finds auctions which may be purchased and sold to an NPC vendor for a profit. Every result is checked again before being offered.

YAAHA never makes a purchase automatically. The player chooses whether to bid, buy out, or skip each deal. A realm-wide running total tracks profit from qualifying vendor flips and can be reset at any time.

### Market history and trends

Repeated scans build a longer view of an item's market instead of relying on one moment at the auction house. YAAHA shows whether historical values are rising or falling and can display the change as either a percentage or a coin value.

### Sale information

YAAHA follows the player's auction outcomes to calculate personal sale rates. Recent realm sale rates, quantities sold, and average sale values are also available from the player's observations and synchronized data.

### Synchronization

YAAHA users can share recent auction and sale information with one another. Faction and Neutral auction houses remain separate, and either type of synchronization can be disabled in the settings.

### Disenchanting

For supported items, YAAHA shows possible disenchanting materials, quantities, probabilities, and estimated values. Results can improve as players disenchant items.

## In development

YAAHA's auction-house workspace includes Search, Post, Cancelling, and Deals pages. Deals and scanning are usable foundations; the remaining pages and several related features are still being developed.

Planned work includes broader auction searching and posting tools, quick cancellation of undercut auctions, prospecting, milling, and further tooltip and deal improvements.

## Addon developers

YAAHA exposes auction and item information through the global `YAAHA_API` table. See the [public API documentation](API.md) for integration details and update callbacks.

## License

YAAHA's original source and content are proprietary and all rights are reserved. Embedded third-party libraries remain subject to their respective licenses. See [LICENSE](LICENSE) for details.
