local AUCTIONS = AUCTIONS
local AUCTION_HOUSE_BROWSE_HEADER_QUANTITY = AUCTION_HOUSE_BROWSE_HEADER_QUANTITY
local C_Container = C_Container
local C_Item = C_Item
local FACTION_NEUTRAL = FACTION_NEUTRAL
local floor = math.floor
local format = string.format
local FormatLargeNumber = FormatLargeNumber
local GameTooltip = GameTooltip
local GetMouseFoci = GetMouseFoci
local IsAltKeyDown = IsAltKeyDown
local IsControlKeyDown = IsControlKeyDown
local IsShiftKeyDown = IsShiftKeyDown
local ItemRefTooltip = ItemRefTooltip
local ItemRefShoppingTooltip1 = ItemRefShoppingTooltip1
local ItemRefShoppingTooltip2 = ItemRefShoppingTooltip2
local LibStub = LibStub
local match = string.match
local pairs = pairs
local SELL_PRICE = SELL_PRICE
local setmetatable = setmetatable
local ShoppingTooltip1 = ShoppingTooltip1
local ShoppingTooltip2 = ShoppingTooltip2
local tonumber = tonumber
local tostring = tostring
local UnitFactionGroup = UnitFactionGroup

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local module = addon:NewModule("Tooltip")
local disenchantingData = addon:GetModule("DisenchantingData")
local inventoryAverageBuy = addon:GetModule("InventoryAverageBuy")
local saleCollector = addon:GetModule("SaleCollector")
local L = LibStub("AceLocale-3.0"):GetLocale("YAAHA")
local playerFaction, localizedPlayerFaction = UnitFactionGroup("player")

local auctionPriceFields = {
	{ "minBid", "Minimum bid" },
	{ "minBuyout", "Minimum buyout" },
	{ "currentMarketValue", "Current market value" },
	{ "midweekMarketValue", "3-day market value" },
	{ "weeklyMarketValue", "7-day market value" },
	{ "biweeklyMarketValue", "14-day market value" },
	{ "monthlyMarketValue", "30-day market value" },
	{ "bimonthlyMarketValue", "60-day market value" },
}

local vendorPriceFields = {
	{ "vendorSell", SELL_PRICE },
	{ "vendorBuy", "Buy from vendor" },
}

local saleFields = {
	{ "personalSaleRate", "Personal sale rate", "rate" },
	{ "realmSaleRate", "Realm sale rate", "rate" },
	{ "realmSoldPerDay", "Realm sold per day", "quantity" },
	{ "realmAverageSaleValue", "Realm average sale value", "money" },
}

local tooltips = {
	GameTooltip,
	ItemRefTooltip,
	ShoppingTooltip1,
	ShoppingTooltip2,
	ItemRefShoppingTooltip1,
	ItemRefShoppingTooltip2,
}
local tooltipState = setmetatable({}, { __mode = "k" })
local GREEN_NUMBER = "|cff20ff20"
local RED_NUMBER = "|cffff2020"

local function TrimmedDecimal(value)
	local text = format("%.3f", value)
	text = text:gsub("0+$", "")
	return text:gsub("%.$", "")
end

local function FormatRate(rate)
	return TrimmedDecimal(rate * 100) .. "%"
end

local function FormatQuantity(quantity)
	quantity = floor(quantity + 0.5)
	if addon.db.profile.formatLargeNumbers then
		return FormatLargeNumber(quantity)
	end
	return tostring(quantity)
end

local function FormatExpectedQuantity(quantity)
	local text = format("%.3f", quantity)
	text = text:gsub("0+$", "")
	return text:gsub("%.$", "")
end

local function FormatTrend(trend, multiplier)
	if not trend or trend.direction == "none" then
		return
	end

	local change
	if addon.db.profile.trendDisplay == "value" then
		local value = trend.value * multiplier
		change = addon:FormatMoney(trend.direction == "down" and -value or value,
			false, trend.direction == "up" and GREEN_NUMBER or RED_NUMBER)
	else
		change = TrimmedDecimal(trend.percent) .. "%"
	end

	-- ASCII carets are font-agnostic across Classic clients. Color and orientation
	-- convey direction independently, while the number gives its magnitude.
	if trend.direction == "up" then
		return addon.db.profile.trendDisplay == "value"
			and GREEN_NUMBER .. "^|r " .. change or GREEN_NUMBER .. "^ " .. change .. "|r"
	end
	return addon.db.profile.trendDisplay == "value"
		and RED_NUMBER .. "v|r " .. change or RED_NUMBER .. "v " .. change .. "|r"
end

local function IsPriceModifierDown()
	local modifier = addon.db.profile.tooltipPriceModifier
	return modifier == "CTRL" and IsControlKeyDown()
		or modifier == "SHIFT" and IsShiftKeyDown()
end

local function GetCursorStackCount(itemID)
	if not IsPriceModifierDown() then
		return 1
	end

	local focus = GetMouseFoci()[1]
	local parent = focus and focus:GetParent()
	local bag = focus and focus.GetBagID and focus:GetBagID()
	if bag == nil and focus and focus.GetInventorySlot and parent then
		-- Blizzard and bag addons derived from ContainerFrameItemButtonTemplate put
		-- the slot on the button and may put the bag ID on an unnamed parent.
		bag = parent:GetID()
	elseif bag == nil and parent and parent.GetName and match(parent:GetName() or "", "^ContainerFrame") then
		bag = parent:GetID()
	end
	local slot = focus and focus.GetID and focus:GetID()
	if bag ~= nil and slot then
		local info = C_Container.GetContainerItemInfo(bag, slot)
		if info and info.itemID == itemID and info.stackCount and info.stackCount > 1 then
			return info.stackCount
		end
	end
	return 1
end

local function GetItemID(tooltip)
	local _, link = tooltip:GetItem()
	local itemID = link and match(link, "item:(%d+)")
	return itemID and tonumber(itemID), link
end

local function GetScope()
	-- Faction data is the useful everyday default. Alt provides an intentional,
	-- temporary look at the neutral market without doubling every item tooltip.
	return IsAltKeyDown() and "realm" or "factionrealm"
end

local function GetScopeName(scope)
	return scope == "realm" and FACTION_NEUTRAL or localizedPlayerFaction or playerFaction
end

function module:AddItemData(tooltip, itemID, scope)
	scope = scope or GetScope()
	local data = addon.db[scope].auctionDB[itemID]
	local disenchant = disenchantingData:GetValue(itemID, scope)
	local inventoryBuy = inventoryAverageBuy:GetValue(itemID)
	local personalSaleRate = saleCollector:GetPersonalSaleData(itemID, scope)
	local realmSaleRate, realmSoldPerDay, realmAverageSaleValue = saleCollector:GetRealmSaleData(itemID, scope)
	local _, _, _, _, _, _, _, _, _, _, vendorSell = C_Item.GetItemInfo(itemID)
	local vendorBuy = addon.db.global.vendorBuyPrices[itemID]
	if not data and not disenchant and not inventoryBuy and personalSaleRate == nil
		and realmSaleRate == nil and realmSoldPerDay == nil and not vendorSell and not vendorBuy then
		return
	end
	data = data or {}

	local settings = addon.db.profile.tooltip
	local multiplier = GetCursorStackCount(itemID)
	local activeSection, addedHeader
	local function EnsureHeader()
		if not addedHeader then
			tooltip:AddLine(" ")
			tooltip:AddLine("YAAHA", 1, 0.82, 0)
			tooltip:AddLine(format("----- %s -----", GetScopeName(scope)), 0.75, 0.75, 0.75)
			addedHeader = true
		end
	end
	local function AddLine(section, label, value)
		EnsureHeader()
		if activeSection ~= section then
			tooltip:AddLine(section, 1, 0.82, 0)
			activeSection = section
		end
		label = "  " .. label
		tooltip:AddDoubleLine(label, value, 1, 1, 1, 1, 1, 1)
	end

	for index = 1, #auctionPriceFields do
		local field = auctionPriceFields[index]
		local key = field[1]
		local value = data[key]
		if settings[key] and value and value > 0 then
			local display = addon:FormatMoney(value * multiplier)
			local trend = key ~= "currentMarketValue" and data.trends and FormatTrend(data.trends[key], multiplier)
			if trend then
				display = display .. "  " .. trend
			end
			AddLine(AUCTIONS, L[field[2]], display)
		end
	end

	if settings.auctionQuantity and data.auctionQuantity and data.auctionQuantity >= 1 then
		AddLine(AUCTIONS, AUCTION_HOUSE_BROWSE_HEADER_QUANTITY, FormatQuantity(data.auctionQuantity))
	end

	for index = 1, #vendorPriceFields do
		local field = vendorPriceFields[index]
		local key = field[1]
		local value = key == "vendorSell" and vendorSell or vendorBuy
		if settings[key] and value and value > 0 then
			local label = key == "vendorSell" and field[2] or L[field[2]]
			AddLine(L["Vendor prices"], label, addon:FormatMoney(value * multiplier))
		end
	end

	for index = 1, #saleFields do
		local field = saleFields[index]
		local key, kind = field[1], field[3]
		local value = key == "personalSaleRate" and personalSaleRate
			or key == "realmSaleRate" and realmSaleRate
			or key == "realmSoldPerDay" and realmSoldPerDay
			or key == "realmAverageSaleValue" and realmAverageSaleValue or data[key]
		if settings[key] and value ~= nil then
			if kind == "rate" and value >= 0 and value <= 1 then
				AddLine(L["Sales"], L[field[2]], FormatRate(value))
			elseif kind == "quantity" and value >= 0 then
				AddLine(L["Sales"], L[field[2]], FormatQuantity(value))
			elseif kind == "money" and value > 0 then
				AddLine(L["Sales"], L[field[2]], addon:FormatMoney(value))
			end
		end
	end
	if settings.inventoryAverageBuy and inventoryBuy and inventoryBuy > 0 then
		AddLine(L["Purchases"], L["Inventory average buy"],
			addon:FormatMoney(inventoryBuy * multiplier))
	end

	if disenchant and settings.breakdownResults then
		for index = 1, #disenchant.results do
			local result = disenchant.results[index]
			local materialName, materialLink = C_Item.GetItemInfo(result.itemID)
			local label = materialLink or materialName or tostring(result.itemID)
			local value = format("%s x%s", FormatRate(result.chance), FormatExpectedQuantity(result.expectedQuantity))
			if result.missingPrice then
				value = value .. "  |cff9d9d9d-- (" .. L["Not found in auction data"] .. ")|r"
			else
				value = value .. "  " .. addon:FormatMoney(result.expectedValue)
			end
			AddLine(L["Breakdown"], label, value)
		end
	end
	if disenchant and settings.breakdownValue then
		AddLine(L["Breakdown"], L["Expected breakdown value"],
			disenchant.expectedValue and addon:FormatMoney(disenchant.expectedValue, true) or "--")
	end

	if addedHeader then
		tooltip:Show()
	end
end

function module:ShowTooltip(owner, link, itemID, scope)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetHyperlink(link)
	-- SetHyperlink normally invokes our hook. This explicit call covers custom
	-- tooltip paths which populate the link without firing OnTooltipSetItem.
	local state = tooltipState[GameTooltip]
	if not state or state.itemID ~= itemID then
		tooltipState[GameTooltip] = { itemID = itemID, link = link }
		self:AddItemData(GameTooltip, itemID, scope)
	end
	GameTooltip:Show()
end

local function OnTooltipSetItem(tooltip)
	local itemID, link = GetItemID(tooltip)
	local state = tooltipState[tooltip]
	if not itemID or state and state.link == link then
		return
	end

	tooltipState[tooltip] = { itemID = itemID, link = link }
	module:AddItemData(tooltip, itemID)
end

local function OnTooltipCleared(tooltip)
	tooltipState[tooltip] = nil
end

function module:OnEnable()
	for _, tooltip in pairs(tooltips) do
		if tooltip then
			tooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
			tooltip:HookScript("OnTooltipCleared", OnTooltipCleared)
		end
	end
end