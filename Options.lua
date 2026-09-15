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
					factionrealm = {
						order = 30,
						type = "toggle",
						name = L["Synchronize faction auction data"],
						desc = L["Send and receive auction data for the current character's faction."],
						get = function()
							return addon.db.profile.sendAndReceiveFactionRealm
						end,
						set = function(_, value)
							addon.db.profile.sendAndReceiveFactionRealm = value
						end
					},
					oppositeFaction = {
						order = 40,
						type = "toggle",
						name = L["Synchronize opposite-faction auction data"],
						desc = L["Send and receive opposite-faction auction-house data without combining it with current-faction or neutral data."],
						get = function()
							return addon.db.profile.sendAndReceiveOppositeFaction
						end,
						set = function(_, value)
							addon.db.profile.sendAndReceiveOppositeFaction = value
						end
					},
					neutral = {
						order = 50,
						type = "toggle",
						name = L["Synchronize neutral auction data"],
						desc = L["Send and receive neutral auction-house data without combining it with faction data."],
						get = function()
							return addon.db.profile.sendAndReceiveRealm
						end,
						set = function(_, value)
							addon.db.profile.sendAndReceiveRealm = value
						end
					},
					formatLargeNumbers = {
						order = 60,
						type = "toggle",
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
					includeBreakEvenDeals = {
						order = 70,
						type = "toggle",
						name = L["Include break-even deals"],
						desc = L["Include vendor, disenchanting, prospecting, and milling deals whose purchase price equals their expected return."],
						get = function()
							return self.db.profile.includeBreakEvenDeals
						end,
						set = function(_, value)
							self.db.profile.includeBreakEvenDeals = value
						end
					},
					total = {
						order = 80,
						type = "description",
						name = function()
							local tracker = addon:GetModule("VendorFlipTracking")
							return format(L["Vendor flip profit: %s"], tracker:GetFormattedProfit())
						end
					},
					reset = {
						order = 90,
						type = "execute",
						name = L["Reset vendor flip profit"],
						confirm = L["Reset vendor flip profit and its outstanding item quantities?"],
						func = function()
							addon:GetModule("VendorFlipTracking"):Reset()
						end
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
						width = "full"
					},
					oppositeFactionModifier = {
						order = 20,
						type = "description",
						name = "* " .. format(L["Hold %s while viewing an item tooltip to show opposite-faction auction-house data."], CTRL_KEY),
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
						width = "full"
					},
					trendDisplay = {
						order = 50,
						type = "select",
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
						type = "multiselect",
						name = L["Tooltip values"],
						values = {
							["01-minBid"] = L["Minimum bid"],
							["02-minBuyout"] = L["Minimum buyout"],
							["03-currentMarketValue"] = L["Current market value"],
							["04-midweekMarketValue"] = L["3-day market value"],
							["05-weeklyMarketValue"] = L["7-day market value"],
							["06-biweeklyMarketValue"] = L["14-day market value"],
							["07-monthlyMarketValue"] = L["30-day market value"],
							["08-bimonthlyMarketValue"] = L["60-day market value"],
							["09-auctionQuantity"] = AUCTION_HOUSE_BROWSE_HEADER_QUANTITY,
							["10-breakdownValue"] = L["Expected breakdown value"],
							["11-breakdownResults"] = L["Breakdown results"],
							["12-vendorSell"] = SELL_PRICE,
							["13-vendorBuy"] = L["Buy from vendor"],
							["14-inventoryAverageBuy"] = L["Inventory average buy"],
							["15-personalSaleRate"] = L["Personal sale rate"],
							["16-realmSaleRate"] = L["Realm sale rate"],
							["17-realmSoldPerDay"] = L["Realm sold per day"],
							["18-realmAverageSaleValue"] = L["Realm average sale value"],
							["19-craftingValue"] = L["Crafting cost"],
							["20-craftingResults"] = L["Crafting breakdown"],
						},
						get = function(_, key)
							return addon.db.profile.tooltip[key]
						end,
						set = function(_, key, value)
							addon.db.profile.tooltip[key] = value
						end
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