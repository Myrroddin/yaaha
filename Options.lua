local ALT_KEY = ALT_KEY
local AUCTION_HOUSE_BROWSE_HEADER_QUANTITY = AUCTION_HOUSE_BROWSE_HEADER_QUANTITY
local AUCTION_HOUSE_FRAME_TITLE_SELL = AUCTION_HOUSE_FRAME_TITLE_SELL
local AUCTIONS = AUCTIONS
local BIDS = BIDS
local BROWSE = BROWSE
local CTRL_KEY = CTRL_KEY
local format = string.format
local LibStub = LibStub
local NONE = NONE
local SEARCH = SEARCH
local SELL_PRICE = SELL_PRICE
local SHIFT_KEY = SHIFT_KEY

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local L = LibStub("AceLocale-3.0"):GetLocale("YAAHA")

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
			auctionHouseOpeningPage = {
				order = 5,
				type = "select",
				name = L["Open auction house to"],
				desc = L["Choose the page shown whenever the auction house is opened."],
				values = {
					browse = BROWSE,
					bids = BIDS,
					auctions = AUCTIONS,
					yaahaSearch = "YAAHA - " .. SEARCH,
					yaahaPost = "YAAHA - " .. AUCTION_HOUSE_FRAME_TITLE_SELL,
					yaahaCancelling = "YAAHA - " .. L["Cancelling"],
					yaahaDeals = "YAAHA - " .. L["Deals"],
				},
				get = function()
					return addon.db.profile.auctionHouseOpeningPage
				end,
				set = function(_, value)
					addon.db.profile.auctionHouseOpeningPage = value
				end,
			},
			trendDisplay = {
				order = 10,
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
				end,
			},
			coinDisplayStyle = {
				order = 15,
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
				end,
			},
			formatLargeNumbers = {
				order = 20,
				type = "toggle",
				name = L["Format large numbers"],
				desc = L["Show large coin values with localized digit separators."],
				get = function()
					return addon.db.profile.formatLargeNumbers
				end,
				set = function(_, value)
					addon.db.profile.formatLargeNumbers = value
					addon:GetModule("VendorFlipTracking"):RefreshDisplay()
				end,
			},
			includeBreakEvenVendorFlips = {
				order = 30,
				type = "toggle",
				name = L["Include break-even vendor flips"],
				desc = L["Include auctions whose purchase price equals the item's vendor value."],
				get = function()
					return self.db.profile.includeBreakEvenVendorFlips
				end,
				set = function(_, value)
					self.db.profile.includeBreakEvenVendorFlips = value
				end,
			},
			vendorFlipProfit = {
				order = 40,
				type = "group",
				name = L["Vendor flip profit"],
				args = {
					total = {
						order = 1,
						type = "description",
						name = function()
							local tracker = addon:GetModule("VendorFlipTracking")
							return format(L["Profit: %s"], tracker:GetFormattedProfit())
						end,
					},
					reset = {
						order = 2,
						type = "execute",
						name = L["Reset vendor flip profit"],
						confirm = L["Reset vendor flip profit and its outstanding item quantities?"],
						func = function()
							addon:GetModule("VendorFlipTracking"):Reset()
						end,
					},
				},
			},
			synchronization = {
				order = 45,
				type = "group",
				name = L["Synchronization"],
				args = {
					factionrealm = {
						order = 1,
						type = "toggle",
						name = L["Synchronize faction auction data"],
						desc = L["Send and receive auction data for the current character's faction."],
						get = function()
							return addon.db.profile.sendAndReceiveFactionRealm
						end,
						set = function(_, value)
							addon.db.profile.sendAndReceiveFactionRealm = value
						end,
					},
					neutral = {
						order = 2,
						type = "toggle",
						name = L["Synchronize neutral auction data"],
						desc = L["Send and receive neutral auction-house data without combining it with faction data."],
						get = function()
							return addon.db.profile.sendAndReceiveRealm
						end,
						set = function(_, value)
							addon.db.profile.sendAndReceiveRealm = value
						end,
					},
				},
			},
			tooltip = {
				order = 50,
				type = "group",
				name = L["Tooltip"],
				args = {
					priceModifier = {
						order = 1,
						type = "select",
						name = L["Stack price modifier"],
						desc = L["Hold this key while viewing an item tooltip to multiply prices by the stack size."],
						values = {
							CTRL = CTRL_KEY,
							NONE = NONE,
							SHIFT = SHIFT_KEY,
						},
						get = function()
							return addon.db.profile.tooltipPriceModifier
						end,
						set = function(_, value)
							addon.db.profile.tooltipPriceModifier = value
						end,
					},
					auctionHouseModifier = {
						order = 2,
						type = "description",
						name = format(L["Hold %s while viewing an item tooltip to show neutral auction-house data."], ALT_KEY),
					},
				},
			},
		},
	}

	local tooltipOptions = {
		{ "auctionQuantity", AUCTION_HOUSE_BROWSE_HEADER_QUANTITY },
		{ "breakdownResults", "Breakdown results" },
		{ "breakdownValue", "Expected breakdown value" },
		{ "minBid", "Minimum bid" },
		{ "minBuyout", "Minimum buyout" },
		{ "currentMarketValue", "Current market value" },
		{ "midweekMarketValue", "3-day market value" },
		{ "weeklyMarketValue", "7-day market value" },
		{ "biweeklyMarketValue", "14-day market value" },
		{ "monthlyMarketValue", "30-day market value" },
		{ "bimonthlyMarketValue", "60-day market value" },
		{ "vendorSell", SELL_PRICE },
		{ "vendorBuy", "Buy from vendor" },
		{ "inventoryAverageBuy", "Inventory average buy" },
		{ "personalSaleRate", "Personal sale rate" },
		{ "realmSaleRate", "Realm sale rate" },
		{ "realmSoldPerDay", "Realm sold per day" },
		{ "realmAverageSaleValue", "Realm average sale value" },
	}

	-- Explicit ordering for comparison with AceConfig's natural multiselect order.
	-- local tooltipValues = {}
	-- for order = 1, #tooltipOptions do
	-- 	local setting = tooltipOptions[order]
	-- 	local key = setting[1]
	-- 	tooltipValues[order] = (key == "auctionQuantity" or key == "vendorSell")
	-- 		and setting[2] or L[setting[2]]
	-- end
	-- options.args.tooltip.args.values = {
	-- 	order = 10,
	-- 	type = "multiselect",
	-- 	name = L["Tooltip values"],
	-- 	values = tooltipValues,
	-- 	get = function(_, index)
	-- 		return addon.db.profile.tooltip[tooltipOptions[index][1]]
	-- 	end,
	-- 	set = function(_, index, value)
	-- 		addon.db.profile.tooltip[tooltipOptions[index][1]] = value
	-- 	end,
	-- }

	local tooltipValues = {}
	for index = 1, #tooltipOptions do
		local setting = tooltipOptions[index]
		local key = setting[1]
		tooltipValues[key] = (key == "auctionQuantity" or key == "vendorSell")
			and setting[2] or L[setting[2]]
	end
	options.args.tooltip.args.values = {
		order = 10,
		type = "multiselect",
		name = L["Tooltip values"],
		values = tooltipValues,
		get = function(_, key)
			return addon.db.profile.tooltip[key]
		end,
		set = function(_, key, value)
			addon.db.profile.tooltip[key] = value
		end,
	}
	options.args.aboutPanel = self:AboutOptionsTable("YAAHA")
	options.args.aboutPanel.order = 1000

	return options
end