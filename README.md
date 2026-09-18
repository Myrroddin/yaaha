# YAAHA

YAAHA (Yet Another Auction House AddOn) helps players understand prices, find worthwhile deals, and make better buying and selling decisions in World of Warcraft Classic.

> [!IMPORTANT]
> YAAHA is under active development and is not yet ready for a public release. Features, settings, and saved data may change while the addon is being built.

## Supported versions

- World of Warcraft Classic Era
- The Burning Crusade Classic
- Wrath of the Lich King Classic (Titan Reforged)

WoW Forever, Mists of Pandaria Classic, and modern World of Warcraft are not currently supported.

## Current features

### Auction-house scanning

YAAHA can quickly scan the auction house and record minimum bids, minimum buyouts, available quantities, and market values covering the current scan and the past 3, 7, 14, 30, and 60 days.

Alliance, Horde, and Neutral auction-house information is kept separate. Holding Alt over an item shows Neutral information, while holding Ctrl shows information for the opposite faction when it is available.

### Item tooltips

Configurable item tooltips can show:

- Current and historical market values
- Price trends
- Minimum bid and buyout
- Quantity available at auction
- Personal and realm sale information
- Vendor buy and sell prices
- Average purchase value for items still owned
- Known-recipe crafting costs, material breakdowns, and estimated profit or loss
- Disenchanting results and estimated value

Hold Shift to multiply prices by the stack size under the cursor.

### Deals

The Deals page currently finds vendor and disenchanting opportunities. Vendor deals may be bid on or bought immediately, while disenchanting deals use buyouts. Every deal is checked again before YAAHA offers it.

YAAHA never purchases anything automatically. The player chooses whether to bid, buy out, or skip each result. YAAHA also keeps a resettable, realm-wide total of profit earned from qualifying vendor flips.

### Sale information

YAAHA follows auction outcomes to calculate the player's sale rate. Recent realm sale rates, quantities sold, and average sale values are also available from the player's observations and synchronized data.

### Known professions

Opening a profession teaches YAAHA which recipes that character knows. YAAHA can then compare current-character and same-faction crafting costs, including cheaper materials made by another recorded character.

### Why crafting costs may look different

YAAHA does not assume that every required material can be bought for the single lowest buyout currently recorded. That auction may already be gone, and the next seller is not obliged to offer the same price.

For example, if two Peacebloom are listed for 15 silver and 55 silver, buying both costs 70 silver, or an average of 35 silver each. A calculation based only on the minimum buyout would incorrectly value each Peacebloom at 15 silver, making the finished item look more profitable than it really is.

YAAHA instead uses its market values and considers less expensive ways to obtain each material, such as crafting, conversion, or an unlimited-supply vendor. In Burning Crusade and Wrath/Titan, YAAHA also recognizes Potion, Elixir, and Transmutation masteries when estimating the auction return and profit of applicable Alchemy recipes. Mastery does not reduce their crafting or material costs.

For readers interested in how auction listings can be turned into a more representative market value, TradeSkillMaster provides a helpful [plain-language explanation of market-value calculation](https://support.tradeskillmaster.com/custom-strings/how-is-auctiondb-market-value-calculated?).

### Synchronization

YAAHA can share auction and sale information with nearby players and guild members who also use the addon. Alliance, Horde, and Neutral information remains separate.

### Broker and minimap

The Broker display and optional minimap button use YAAHA's auction-house coin icon. The Broker text shows the current vendor-flip profit, and clicking either icon opens YAAHA's options.

## Opening the options

YAAHA's options can be opened in any of these ways:

- Enter `/yaaha` in chat.
- Open **Esc > Options > AddOns > YAAHA**.
- Click **Options** on YAAHA's auction-house tab.
- Click YAAHA's minimap or Broker icon.

## In development

YAAHA's auction-house workspace includes Post Auctions, Shopping, Cancelling, and Deals tabs. Scanning and the Deals tab are usable foundations; the other tabs are still being developed.

Planned work includes auction posting and shopping tools, quick cancellation of undercut auctions, prospecting and milling data, and additional deal and tooltip features.

## Addon developers

YAAHA exposes auction and item information through the global `YAAHA_API` table. See the [public API documentation](https://github.com/Myrroddin/yaaha/blob/main/API.md) for integration details and update callbacks.

## License

YAAHA's original source and content are proprietary and all rights are reserved. Embedded third-party libraries remain subject to their respective licenses. See [LICENSE](LICENSE) for details.
