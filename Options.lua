-- Builds YAAHA's AceConfig options with client-appropriate controls and sizing.

local ALT_KEY = ALT_KEY
local AUCTION_HOUSE_BROWSE_HEADER_QUANTITY = AUCTION_HOUSE_BROWSE_HEADER_QUANTITY
local AUCTION_HOUSE_FRAME_TITLE_SELL = AUCTION_HOUSE_FRAME_TITLE_SELL
local AUCTIONS = AUCTIONS
local BIDS = BIDS
local BROWSE = BROWSE
local CTRL_KEY = CTRL_KEY
local floor = math.floor
local format = string.format
local GENERAL_LABEL = GENERAL_LABEL
local HIDE = HIDE
local LibStub = LibStub
local LOCK = LOCK
local MINIMAP_LABEL = MINIMAP_LABEL
local SELL_PRICE = SELL_PRICE
local SHIFT_KEY = SHIFT_KEY

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local isClassicEra = addon.isClassicEra
local isForever = addon.isForever
local isTBC = addon.isTBC
local usesSharedAuctionHouse = addon.usesSharedAuctionHouse
local L = LibStub("AceLocale-3.0"):GetLocale("YAAHA")
local LibDBIcon = LibStub("LibDBIcon-1.0")

local function GetRoundedMinimapPosition(value)
	if addon.db.global.minimap.lockOnDegree then
		value = floor(value + 0.5)
	end
	return value < 1 and 1 or value > 360 and 360 or value
end

local function RefreshMinimapButton()
	LibDBIcon:Refresh("YAAHA", addon.db.global.minimap)
end

local function CreateTooltipToggle(order, name, desc)
	return {
		order = order,
		type = "toggle",
		width = "relative",
		relWidth = 1 / 3,
		name = name,
		desc = desc,
	}
end

local options
function addon:GetOptions()
	if options then
		return options
	end

	options = {
		order = 10,
		type = "group",
		childGroups = "tab",
		name = "YAAHA",
		handler = addon,
		args = {
			generalSettings = {
				order = 10,
				type = "group",
				name = GENERAL_LABEL,
				args = {
					auctionHouseOpeningPage = {
						order = 10,
						type = "select",
						width = "relative",
						relWidth = 0.33,
						name = L["Open auction house to"],
						desc = L["Choose the page shown whenever the auction house is opened."],
						values = {
							browse = BROWSE,
							bids = BIDS,
							auctions = AUCTIONS,
							yaahaPost = "YAAHA - " .. AUCTION_HOUSE_FRAME_TITLE_SELL,
							yaahaSearch = "YAAHA - " .. L["Shopping"],
							yaahaCancelling = "YAAHA - " .. L["Cancelling"],
							yaahaDeals = "YAAHA - " .. L["Deals"],
						},
						get = function()
							return addon.db.profile.auctionHouseOpeningPage
						end,
						set = function(_, value)
							addon.db.profile.auctionHouseOpeningPage = value
						end
					},
					coinDisplayStyle = {
						order = 20,
						type = "select",
						width = "relative",
						relWidth = 0.33,
						name = L["Coin display"],
						desc = L["Choose between Blizzard's coin textures and localized denomination letters."],
						values = {
							text = L["Denomination letters"],
							texture = L["Coin textures"],
						},
						get = function()
							return addon.db.profile.coinDisplayStyle
						end,
						set = function(_, value)
							addon.db.profile.coinDisplayStyle = value
							addon:GetModule("VendorFlipTracking"):RefreshDisplay()
						end
					},
					numDecimals = {
						order = 30,
						type = "range",
						width = "relative",
						relWidth = 0.33,
						name = L["Decimal places"],
						desc = L["Choose how many decimal places YAAHA displays."],
						get = function()
							return addon.db.profile.numDecimals
						end,
						set = function(_, value)
							addon.db.profile.numDecimals = floor(value + 0.5)
						end,
						min = 1,
						max = 3,
						step = 1,
					},
					syncData = {
						order = 40,
						type = "toggle",
						width = "relative",
						relWidth = 0.5,
						name = L["Sync Data"],
						desc = L["Send and receive all supported auction, realm-sale, and learned material-breakdown data with guild members on the same or a connected realm."],
						get = function()
							return addon.db.profile.syncData
						end,
						set = function(_, value)
							addon.db.profile.syncData = value
						end
					},
					formatLargeNumbers = {
						order = 50,
						type = "toggle",
						width = "relative",
						relWidth = 0.5,
						name = L["Format large numbers"],
						desc = L["Show large coin values with localized digit separators."],
						get = function()
							return addon.db.profile.formatLargeNumbers
						end,
						set = function(_, value)
							addon.db.profile.formatLargeNumbers = value
							addon:GetModule("VendorFlipTracking"):RefreshDisplay()
						end
					},
					includeBreakEvenVendorDeals = {
						order = 60,
						type = "toggle",
						width = "relative",
						relWidth = 0.5,
						name = L["Include break-even vendor flips"],
						desc = L["Include vendor-flip deals whose purchase price equals their guaranteed vendor return."],
						get = function()
							return self.db.profile.includeBreakEvenVendorDeals
						end,
						set = function(_, value)
							self.db.profile.includeBreakEvenVendorDeals = value
						end
					},
					total = {
						order = 70,
						type = "description",
						width = "relative",
						relWidth = 0.5,
						name = function()
							local tracker = addon:GetModule("VendorFlipTracking")
							return format(L["Vendor flip profit: %s"], tracker:GetFormattedProfit())
						end
					},
					reset = {
						order = 80,
						type = "execute",
						width = "relative",
						relWidth = 0.5,
						name = L["Reset vendor flip profit"],
						confirm = L["Reset vendor flip profit and its outstanding item quantities?"],
						func = function()
							addon:GetModule("VendorFlipTracking"):Reset()
						end
					},
					disenchantingDealThreshold = {
						order = 90,
						type = "range",
						width = "relative",
						relWidth = 0.5,
						name = L["Disenchanting deal threshold"],
						desc = L["Only return disenchanting deals whose purchase price is no more than this percentage of their expected disenchanting value."],
						min = 0.01,
						max = 1,
						step = 0.01,
						bigStep = 0.05,
						isPercent = true,
						get = function()
							return addon.db.profile.disenchantingDealThreshold
						end,
						set = function(_, value)
							addon.db.profile.disenchantingDealThreshold = value
						end,
					},
					prospectingDealThreshold = {
						order = 100,
						type = "range",
						width = "relative",
						relWidth = 0.5,
						name = L["Prospecting deal threshold"],
						desc = L["Only return prospecting deals whose purchase price is no more than this percentage of their expected prospecting value."],
						min = 0.01,
						max = 1,
						step = 0.01,
						bigStep = 0.05,
						isPercent = true,
						get = function()
							return addon.db.profile.prospectingDealThreshold
						end,
						set = function(_, value)
							addon.db.profile.prospectingDealThreshold = value
						end,
						hidden = isClassicEra or isForever,
					},
					millingDealThreshold = {
						order = 110,
						type = "range",
						width = "relative",
						relWidth = 0.5,
						name = L["Milling deal threshold"],
						desc = L["Only return milling deals whose purchase price is no more than this percentage of their expected milling value."],
						min = 0.01,
						max = 1,
						step = 0.01,
						bigStep = 0.05,
						isPercent = true,
						get = function()
							return addon.db.profile.millingDealThreshold
						end,
						set = function(_, value)
							addon.db.profile.millingDealThreshold = value
						end,
						hidden = isClassicEra or isForever or isTBC,
					}
				}
			},
			tooltip = {
				order = 20,
				type = "group",
				name = L["Tooltip"],
				args = {
					neutralModifier = {
						order = 10,
						type = "description",
						name = "* " .. format(L["Hold %s while viewing an item tooltip to show neutral auction-house data."], ALT_KEY),
						hidden = usesSharedAuctionHouse,
						width = "full"
					},
					oppositeFactionModifier = {
						order = 20,
						type = "description",
						name = "* " .. format(L["Hold %s while viewing an item tooltip to show opposite-faction auction-house data."], CTRL_KEY),
						hidden = usesSharedAuctionHouse,
						width = "full"
					},
					stackModifier = {
						order = 30,
						type = "description",
						name = "* " .. format(L["Hold %s while viewing an item tooltip to multiply prices by the stack size."], SHIFT_KEY),
						width = "full"
					},
					modifierPriority = {
						order = 40,
						type = "description",
						name = "* " .. format(L["Holding %s + %s always shows neutral auction-house data."], CTRL_KEY, ALT_KEY),
						hidden = usesSharedAuctionHouse,
						width = "full"
					},
					trendDisplay = {
						order = 50,
						type = "select",
						width = "relative",
						relWidth = 0.34,
						name = L["Trend display"],
						values = {
							percent = L["Percent"],
							value = L["Gold value"],
						},
						get = function()
							return addon.db.profile.trendDisplay
						end,
						set = function(_, value)
							addon.db.profile.trendDisplay = value
						end
					},
					values = {
						order = 60,
						type = "group",
						inline = true,
						width = "full",
						name = L["Tooltip values"],
						get = function(info)
							return addon.db.profile.tooltip[info[#info]]
						end,
						set = function(info, value)
							addon.db.profile.tooltip[info[#info]] = value
						end,
						args = {
							["01-minBid"] = CreateTooltipToggle(10, L["Minimum bid"]),
							["02-minBuyout"] = CreateTooltipToggle(20, L["Minimum buyout"]),
							["03-currentMarketValue"] = CreateTooltipToggle(30, L["Current market value"]),
							["04-midweekMarketValue"] = CreateTooltipToggle(40, L["3-day market value"]),
							["05-weeklyMarketValue"] = CreateTooltipToggle(50, L["7-day market value"]),
							["06-biweeklyMarketValue"] = CreateTooltipToggle(60, L["14-day market value"]),
							["07-monthlyMarketValue"] = CreateTooltipToggle(70, L["30-day market value"]),
							["08-bimonthlyMarketValue"] = CreateTooltipToggle(80, L["60-day market value"]),
							["09-auctionQuantity"] = CreateTooltipToggle(90, AUCTION_HOUSE_BROWSE_HEADER_QUANTITY),
							["10-breakdownValue"] = CreateTooltipToggle(100, L["Expected breakdown value"]),
							["11-breakdownResults"] = CreateTooltipToggle(110, L["Breakdown results"]),
							["12-vendorSell"] = CreateTooltipToggle(120, SELL_PRICE),
							["13-vendorBuy"] = CreateTooltipToggle(130, L["Buy from vendor"]),
							["14-inventoryAverageBuy"] = CreateTooltipToggle(140, L["Inventory average buy"]),
							["15-personalRollingSaleRate"] = CreateTooltipToggle(150,
								L["Personal 60-day sale rate"],
								L["Fraction of your resolved sale quantity sold across all characters and auction houses on this realm during the rolling 60-day window."]),
							["16-realmRollingSaleRate"] = CreateTooltipToggle(160,
								L["Realm 60-day sale rate"],
								L["Fraction of observed listing and purchase quantity confirmed sold in this market during the rolling 60-day window."]),
							["17-realmRollingSalesPerDay"] = CreateTooltipToggle(170,
								L["Realm rolling sales per day"],
								L["Average number of individual items confirmed sold through completed listings or purchases during YAAHA's observed market window, up to 60 days."]),
							["18-realmRollingAverageSaleValue"] = CreateTooltipToggle(180,
								L["Realm 60-day average sale value"],
								L["Average gross per-unit auction sale value in this market during the rolling 60-day window."]),
							["19-craftingValue"] = CreateTooltipToggle(190, L["Crafting cost"]),
							["20-craftingResults"] = CreateTooltipToggle(200, L["Crafting breakdown"]),
							["21-conversionValue"] = CreateTooltipToggle(210, L["Conversion cost"]),
							["22-conversionResults"] = CreateTooltipToggle(220, L["Full conversion breakdown"]),
						}
					}
				}
			},
			minimap = {
				order = 30,
				type = "group",
				name = MINIMAP_LABEL,
				args = {
					hide = {
						order = 10,
						type = "toggle",
						width = "relative",
						relWidth = 0.33,
						name = HIDE,
						desc = L["Hide the minimap button."],
						get = function()
							return addon.db.global.minimap.hide
						end,
						set = function(_, value)
							addon.db.global.minimap.hide = value
							if value then
								LibDBIcon:Hide("YAAHA")
							else
								LibDBIcon:Show("YAAHA")
							end
							RefreshMinimapButton()
						end
					},
					lock = {
						order = 20,
						type = "toggle",
						width = "relative",
						relWidth = 0.33,
						name = LOCK,
						desc = L["Lock the minimap button and prevent dragging."],
						get = function()
							return addon.db.global.minimap.lock
						end,
						set = function(_, value)
							local minimap = addon.db.global.minimap
							if value then
								LibDBIcon:Lock("YAAHA")
							else
								LibDBIcon:Unlock("YAAHA")
							end
							-- LibDBIcon clears this key while unlocking. Restore the explicit
							-- false value so AceDB's true default cannot make it appear locked.
							minimap.lock = value
							minimap.minimapPos = GetRoundedMinimapPosition(minimap.minimapPos)
							LibDBIcon:SetButtonToPosition("YAAHA", minimap.minimapPos)
							RefreshMinimapButton()
						end
					},
					lockOnDegree = {
						order = 30,
						type = "toggle",
						width = "relative",
						relWidth = 0.33,
						name = L["Precise Lock"],
						desc = L["When locked, snap the minimap button to an exact degree."],
						get = function()
							return addon.db.global.minimap.lockOnDegree
						end,
						set = function(_, value)
							local minimap = addon.db.global.minimap
							minimap.lockOnDegree = value
							minimap.minimapPos = GetRoundedMinimapPosition(minimap.minimapPos)
							LibDBIcon:SetButtonToPosition("YAAHA", minimap.minimapPos)
							RefreshMinimapButton()
						end
					},
					addonCompartment = {
						order = 40,
						type = "toggle",
						width = "relative",
						relWidth = 0.33,
						name = L["AddOn Compartment"],
						desc = L["Show the minimap button in the addon compartment."],
						hidden = function()
							-- The bundled LibDBIcon provides this newer method, but WoWLua-LS's library definition does not yet include it.
							---@diagnostic disable-next-line: undefined-field
							return not LibDBIcon:IsButtonCompartmentAvailable()
						end,
						get = function()
							return addon.db.global.minimap.showInCompartment
						end,
						set = function(_, value)
							local minimap = addon.db.global.minimap
							if value then
								LibDBIcon:AddButtonToCompartment("YAAHA")
							else
								LibDBIcon:RemoveButtonFromCompartment("YAAHA")
							end
							-- Removing a compartment entry clears the library's DB key. AceDB
							-- needs an explicit false to override YAAHA's enabled-by-default value.
							minimap.showInCompartment = value
						end
					},
					minimapPos = {
						order = 50,
						type = "range",
						width = "relative",
						relWidth = 0.67,
						name = L["Rotate Button"],
						desc = L["Rotate the minimap button."],
						disabled = function()
							return addon.db.global.minimap.lock
						end,
						get = function()
							return addon.db.global.minimap.minimapPos
						end,
						set = function(_, value)
							local minimap = addon.db.global.minimap
							minimap.minimapPos = GetRoundedMinimapPosition(value)
							LibDBIcon:SetButtonToPosition("YAAHA", minimap.minimapPos)
							RefreshMinimapButton()
						end,
						min = 1,
						max = 360,
						step = 1,
						bigStep = 15
					}
				}
			}
		}
	}
	options.args.aboutPanel = self:AboutOptionsTable("YAAHA")
	options.args.aboutPanel.order = 1000

	return options
end