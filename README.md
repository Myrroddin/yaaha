# YAAHA

YAAHA (Yet Another Auction House AddOn) is a modular auction-house data addon for World of Warcraft Classic. It scans the auction house, records per-item prices, and calculates several weighted market values over time.

> [!IMPORTANT]
> YAAHA is in early development. Its database format, calculations, and user interface may change before the first stable release.

## Supported game versions

- World of Warcraft Classic Era
- The Burning Crusade Classic
- Wrath of the Lich King Classic (Titan Reforged)

Mists of Pandaria Classic and modern World of Warcraft are not currently supported.

## Current functionality

When the auction house is open, YAAHA provides a button for starting a full scan. Scan availability follows Blizzard's auction-house throttling rules.

After a successful full scan, the Scan button is disabled for the session's fifteen-minute cooldown and displays the decreasing time remaining. The expiry is retained through `/reload`, which does not reset Blizzard's throttle. When the auction house is opened after logging back in, Blizzard's readiness result clears the saved countdown because a true logout resets the full-scan timer.

YAAHA adds one tab after Blizzard's auction-house tabs. Its compact workspace contains separate Search, Post, Cancelling, and Deals pages while keeping shared scan controls and auction-house status visible.

YAAHA currently:

- Records prices by `itemID`, because individual auction IDs are not stable.
- Stores `minBid` and `minBuyout` as per-unit copper values.
- Calculates current and historical market values after each completed scan.
- Tracks whether each historical market value moved up or down since its preceding calculation.
- Separates faction and neutral auction-house data.
- Builds a preliminary cache of auctions which may be profitable to buy and sell to an NPC vendor.
- Processes scan results incrementally to avoid freezing the game client.

The tooltip display, vendor-flip interface, disenchanting results, milling results, and prospecting results are still planned or under development.

## Auction-house separation

Alliance and Horde auction-house data is stored in the character's AceDB `factionrealm` scope. Neutral auction houses, including those in Winterspring, Tanaris, and Stranglethorn Vale, are stored in the `realm` scope.

YAAHA identifies the auctioneer and chooses the appropriate database silently. Faction and neutral prices are never intentionally combined.

Each scan starts with a fresh snapshot of the active auction house. Only that auction house is processed; scanning one auction house does not recalculate the other scopes.

## Price values

All prices are stored in copper and calculated per item, even when an auction contains a stack.

| Value | Period | Behavior |
| --- | ---: | --- |
| `minBid` | Current scan | Lowest per-unit payable bid found for the item. Cleared when the item is absent from the current scan. |
| `minBuyout` | Current scan | Lowest per-unit buyout found for the item. Cleared when the item is absent from the current scan. |
| `currentMarketValue` | Current scan | Calculated exclusively from the current scan. It retains no earlier observations and is cleared when the item is absent. |
| `midweekMarketValue` | Rolling 3 days | Uses the first three weights from the market-value curve. |
| `weeklyMarketValue` | Rolling 7 days | Uses the first seven weights from the market-value curve. |
| `biweeklyMarketValue` | Rolling 14 days | Uses all fourteen weights from the market-value curve. |
| `monthlyMarketValue` | Rolling 30 days | Uses the fourteen-day weighted curve, then holds at its minimum weight through day 30. |
| `bimonthlyMarketValue` | Rolling 60 days | Uses the fourteen-day weighted curve, then holds at its minimum weight through day 60. |

### Current market value

The current market value is intended to describe a competitive price from one scan without allowing unusually expensive or inexpensive listings to distort it. The calculation follows the process documented for [TradeSkillMaster's AuctionDB market value](https://support.tradeskillmaster.com/tsm-addon-documentation/auctiondb-market-value):

1. Treat every item in a stack as one observation at that stack's per-unit buyout.
2. Sort the available unit prices from lowest to highest.
3. Consider at most the cheapest 30% of the observations.
4. After passing the cheapest 15%, stop at a price increase of 20% or more.
5. Calculate the average and standard deviation of the accepted observations.
6. Remove observations farther than 1.5 standard deviations from that average.
7. Average the remaining observations and round the result to whole copper.

`currentMarketValue` is completely replaced after every scan. It is not blended with the preceding scan and does not have a trend, because it is deliberately a moment-in-time value. Every completed current-market calculation is also retained as an observation for the rolling values.

### Historical weighting

Every current-market calculation is retained as a timestamped observation for that specific `itemID`. Different items can therefore have different histories and expiry times. Individual scans can still be unusually high or low, especially when an item has very few listings, but repeated observations and the weighted rolling calculations normalize those fluctuations over time.

YAAHA uses the relative weighting curve published for TradeSkillMaster AuctionDB. Newer observations influence a result more strongly than older observations. The weights are normalized before use, so they change the relative influence of observations without multiplying the resulting price.

| Rolling age band | Relative weight |
| ---: | ---: |
| 0–24 hours | 132 |
| 24–48 hours | 125 |
| 48–72 hours | 100 |
| 3–4 days | 75 |
| 4–5 days | 45 |
| 5–6 days | 34 |
| 6–7 days | 33 |
| 7–8 days | 38 |
| 8–9 days | 28 |
| 9–10 days | 21 |
| 10–11 days | 15 |
| 11–12 days | 10 |
| 12–13 days | 7 |
| 13–14 days | 5 |

The history is divided into rolling 24-hour bands measured backward from the newest scan time. These are not calendar days. When an item was seen in multiple scans within one band, those scan values are averaged first. This prevents frequently scanning during one 24-hour period from giving that period more influence merely because it contains more scans.

The 3-, 7-, and 14-day values use the corresponding beginning portion of the curve. The 30- and 60-day values use the complete fourteen-day curve, then keep every older observation at the final raw weight of `5`. The weight never increases as data ages: it decreases to this minimum floor and remains there until the observation expires.

### Expiry

Price history is neither pruned nor recalculated by an idle timer. It changes only after a completed scan of the relevant auction house.

Consequently, saved prices may appear stale when the user has not scanned recently. On the next completed scan, observations outside a particular value's period are ignored by that calculation, while observations older than 60 rolling days are removed from storage. An item absent from the latest scan loses its current values but keeps unexpired historical values. Its complete `[itemID]` record is removed after its final historical observation passes the 60-day cutoff.

## Trends

YAAHA compares each newly calculated historical value only with the preceding value for the same period. For example, `weeklyMarketValue` is compared with the previous `weeklyMarketValue`, never with the current or monthly market value.

Each trend records:

- Direction: up, down, or unchanged.
- Percentage change, which is the default display format.
- Absolute price change in copper, which can be displayed as localized gold, silver, and copper.

Zero-valued coin denominations are omitted: `4g23c` is displayed instead of `4g0s23c`. Large gold values can optionally use Blizzard's `FormatLargeNumber()` formatting.

## Vendor-flip data

YAAHA records listings whose per-unit bid or buyout is less than or equal to the item's NPC vendor value. Listings with the same stack size and unit prices are combined in the cache. A completed full scan replaces the vendor cache for only the active auction-house type.

The Deals page provides a user-initiated vendor-flip search with controls to stop or restart it. During a full auction scan and subsequent processing, these controls are disabled while the Deals page reports vendor-cache progress. They are enabled only after the replacement cache has been installed atomically. Cached entries are only a shortlist: YAAHA performs targeted live searches and verifies the item, stack, seller, bid, buyout, and vendor return before presenting an auction. Each qualifying listing requires the player to choose a profitable Bid or Buyout action, or Skip. An unavailable or unprofitable action is not shown, and the listing is checked again immediately before any money is committed. The popup shows both the purchase price and resulting profit; hovering over its item link shows YAAHA's available price values. An option controls whether break-even auctions are included and is disabled by default.

## Configuration

The preliminary profile settings include:

- Choose which Blizzard or YAAHA page opens with the auction house.
- Display trends as a percentage or an absolute coin value.
- Apply Blizzard's large-number formatting to large gold values.
- Include or exclude break-even vendor-flip opportunities when results are presented.

Settings use AceDB profiles. Auction data uses the `factionrealm` or `realm` scope described above, while shared processing data intended to be independent of a character, faction, or realm uses the `global` scope.

## Synchronization

YAAHA can exchange incremental auction and realm-sale observations with other online YAAHA users. Faction and neutral data remain separate, and profile settings independently control whether either scope is sent or received.

Small discovery messages are staggered across guild and nearby auction-house users. YAAHA does not discover or synchronize through raid or party channels, and it suspends synchronization while the character is inside an instance. After discovery through guild or nearby yell, manifests and requested deltas are transferred privately by addon whisper rather than broadcasting large databases. AceSerializer preserves the Lua data, EncodingUtil compresses and Base64-encodes it for transport, and AceComm handles message splitting and throttling.

The receiver immediately ignores messages whose sender matches either the current character's short name or full `name-realm`. Manifests compare stable observation identities, so already-known records are not requested again and synchronized observations can safely reach another peer without creating feedback loops.

Synchronization exchanges timestamped source observations rather than trusting another client's rounded derived values. It includes current minimums and market data, per-item listing and quantity counts, scan-wide listing and distinct-item totals, and authoritative realm-sale observations. Both peers merge the same inputs and recalculate rolling market values, realm sale rate, daily quantity sold, and average sale value locally with the same rules.

Buyer-confirmed sales are synchronized as provisional observations so peers can agree before the seller collects the proceeds. Seller-confirmed sales are authoritative: a matching seller record replaces exactly one provisional buyer observation, while nonmatching transactions remain separate so legitimate sales are not lost. Transaction keys behave as a counted multiset, and no synchronization source is identified in the user interface.

## Development

YAAHA is written in Lua and developed with [WoWLua-LS](https://tradeskillmaster.github.io/wowlua-ls/). The repository's `.wowluarc.json` configures the supported Classic flavors and embedded-library definitions.

Embedded libraries currently include selected Ace3 components, LibAboutPanel-2.0, LibStub, and CallbackHandler-1.0. Release packaging is configured through `.pkgmeta`.

WoW API compatibility is checked against the current [Warcraft Wiki API documentation](https://warcraft.wiki.gg/wiki/World_of_Warcraft_API), its widget documentation, event documentation, and Blizzard FrameXML sources.

## Public API

YAAHA exposes its public integration surface through the global `YAAHA_API` table. See the [YAAHA Public API documentation](API.md) for access instructions, versioning, functions, and return-value conventions.

## License

YAAHA's original source and content are proprietary and all rights are reserved. Embedded third-party libraries remain subject to their respective licenses. See [LICENSE](LICENSE) for details.
