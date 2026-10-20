-- Adds YAAHA auction, sales, inventory, material-breakdown, conversion, and crafting data to item tooltips.

local AUCTIONS = AUCTIONS
local _G = _G
local AUCTION_HOUSE_BROWSE_HEADER_QUANTITY = AUCTION_HOUSE_BROWSE_HEADER_QUANTITY
local C_Container = C_Container
local C_Item = C_Item
local C_Timer = C_Timer
local EmbeddedItemTooltip = EmbeddedItemTooltip
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
local next = next
local SELL_PRICE = SELL_PRICE
local setmetatable = setmetatable
local ShoppingTooltip1 = ShoppingTooltip1
local ShoppingTooltip2 = ShoppingTooltip2
local ShoppingTooltip3 = ShoppingTooltip3
local tostring = tostring
local UnitFactionGroup = UnitFactionGroup

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local usesSharedAuctionHouse = addon.UsesSharedAuctionHouse
local module = addon:NewModule("Tooltip")
local convertData = addon:GetModule("ConvertData")
local disenchantingData = addon:GetModule("DisenchantingData")
local inventoryAverageBuy = addon:GetModule("InventoryAverageBuy")
local millingData = addon:GetModule("MillingData", true)
local professionScanner = addon:GetModule("ProfessionScanner")
local prospectingData = addon:GetModule("ProspectingData", true)
local saleCollector = addon:GetModule("SaleCollector")
local L = LibStub("AceLocale-3.0"):GetLocale("YAAHA")
local playerFaction, localizedPlayerFaction = UnitFactionGroup("player")
local storage
local breakdownDataModules = { disenchantingData }
if prospectingData then
	breakdownDataModules[#breakdownDataModules + 1] = prospectingData
end
if millingData then
	breakdownDataModules[#breakdownDataModules + 1] = millingData
end

-- Ordering prefixes belong only to profile settings. Keep the stored price and
-- trend field names unchanged; each row maps its data field to its option key.
local auctionPriceFields = {
	{ "minBid", "Minimum bid", "01-minBid" },
	{ "minBuyout", "Minimum buyout", "02-minBuyout" },
	{ "currentMarketValue", "Current market value", "03-currentMarketValue" },
	{ "midweekMarketValue", "3-day market value", "04-midweekMarketValue" },
	{ "weeklyMarketValue", "7-day market value", "05-weeklyMarketValue" },
	{ "biweeklyMarketValue", "14-day market value", "06-biweeklyMarketValue" },
	{ "monthlyMarketValue", "30-day market value", "07-monthlyMarketValue" },
	{ "bimonthlyMarketValue", "60-day market value", "08-bimonthlyMarketValue" },
}

local vendorPriceFields = {
	{ "vendorSell", SELL_PRICE, "12-vendorSell" },
	{ "vendorBuy", "Buy from vendor", "13-vendorBuy" },
}

local saleFields = {
	{ "personalRollingSaleRate", "Personal 60-day sale rate", "rate", "15-personalRollingSaleRate" },
	{ "realmRollingSaleRate", "Realm 60-day sale rate", "rate", "16-realmRollingSaleRate" },
	{ "realmRollingSalesPerDay", "Realm rolling sales per day", "decimal", "17-realmRollingSalesPerDay" },
	{ "realmRollingAverageSaleValue", "Realm 60-day average sale value", "money", "18-realmRollingAverageSaleValue" },
}

local tooltips = {}
local function AddTooltip(tooltip)
	if tooltip then
		tooltips[#tooltips + 1] = tooltip
	end
end
AddTooltip(GameTooltip)
AddTooltip(ItemRefTooltip)
AddTooltip(EmbeddedItemTooltip)
AddTooltip(ShoppingTooltip1)
AddTooltip(ShoppingTooltip2)
AddTooltip(ShoppingTooltip3)
AddTooltip(ItemRefShoppingTooltip1)
AddTooltip(ItemRefShoppingTooltip2)
local tooltipState = setmetatable({}, { __mode = "k" })
local tooltipDisplayState = setmetatable({}, { __mode = "k" })
local GREEN_NUMBER = "|cff20ff20"
local RED_NUMBER = "|cffff2020"
local CRAFT_SALE_VALUE_FIELDS = {
	"minBuyout",
	"midweekMarketValue",
	"weeklyMarketValue",
	"biweeklyMarketValue",
	"monthlyMarketValue",
	"bimonthlyMarketValue",
}

local function FormatRate(rate)
	return format(L["%s%%"], addon:FormatDecimal(rate * 100) or "")
end

local function FormatQuantity(quantity)
	quantity = floor(quantity + 0.5)
	if addon.db.profile.formatLargeNumbers then
		return FormatLargeNumber(quantity)
	end
	return tostring(quantity)
end

local function FormatExpectedQuantity(quantity)
	return addon:FormatDecimal(quantity) or ""
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
		change = format(L["%s%%"], addon:FormatDecimal(trend.percent) or "")
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

local function GetCursorStackCount(itemID)
	if not IsShiftKeyDown() then
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

local function HasRenderedYAAHAData(tooltip)
	local name = tooltip:GetName()
	if not name then
		return false
	end
	for index = 1, tooltip:NumLines() do
		local line = _G[name .. "TextLeft" .. index]
		if line and line:GetText() == "YAAHA" then
			return true
		end
	end
	return false
end

local function IsSameDisplay(tooltip, kind, id)
	local state = tooltipDisplayState[tooltip]
	return state and state.kind == kind and state.id == id
		and state.alt == IsAltKeyDown() and state.control == IsControlKeyDown()
		and state.shift == IsShiftKeyDown()
end

local function RememberDisplay(tooltip, kind, id)
	tooltipDisplayState[tooltip] = {
		kind = kind,
		id = id,
		alt = IsAltKeyDown(),
		control = IsControlKeyDown(),
		shift = IsShiftKeyDown(),
	}
end

local function HasAuctionData(scopeDB)
	return scopeDB and scopeDB.auctionDB and next(scopeDB.auctionDB) ~= nil
end

local function GetContext(scope)
	if usesSharedAuctionHouse then
		return "realm", addon.db.realm, L["Shared"]
	end
	if scope == "realm" then
		return scope, addon.db.realm, FACTION_NEUTRAL
	elseif scope == "factionrealm" then
		return scope, addon.db.factionrealm, localizedPlayerFaction or playerFaction
	end

	-- ALT is intentionally checked first so neutral wins when both auction-house
	-- modifiers are held. An unavailable alternate view falls back to faction data.
	if IsAltKeyDown() then
		if HasAuctionData(addon.db.realm) then
			return "realm", addon.db.realm, FACTION_NEUTRAL
		end
	elseif IsControlKeyDown() then
		storage = storage or addon:GetModule("Storage")
		local oppositeDB, oppositeName = storage:GetOppositeFactionData()
		if HasAuctionData(oppositeDB) then
			return "opposite", oppositeDB, oppositeName
		end
	end
	return "factionrealm", addon.db.factionrealm, localizedPlayerFaction or playerFaction
end

local function AddCraftingLines(AddLine, result, showBreakdown, multiplier)
	if not result or not showBreakdown then
		return
	end
	local quantityScale = multiplier / result.outputQuantity
	for index = 1, #result.materials do
		local material = result.materials[index]
		local name, link = C_Item.GetItemInfo(material.itemID)
		local label = format(L["%s x%s"], link or name or tostring(material.itemID),
			FormatExpectedQuantity(material.quantity * quantityScale))
		local value = material.totalValue
			and addon:FormatMoney(material.totalValue * quantityScale) or "--"
		AddLine(L["Crafting"], label, value)
		-- Keep the recipe's actual reagent above; this is only the cheaper way
		-- to obtain it and never changes the saved recipe requirements.
		if material.source == "convert" and material.detail then
			local convertedName, convertedLink = C_Item.GetItemInfo(material.detail.itemID)
			local sourceQuantity = material.detail.quantity < 1 and 1 or material.detail.quantity
			local resultQuantity = material.detail.quantity < 1 and 1 / material.detail.quantity or 1
			AddLine(L["Crafting"], format(L["Cheaper conversion: %s x%s -> %s x%s"],
				convertedLink or convertedName or tostring(material.detail.itemID),
				FormatExpectedQuantity(sourceQuantity), link or name or tostring(material.itemID),
				FormatExpectedQuantity(resultQuantity)), "")
		end
	end
end

local function GetCraftSaleValue(data)
	if not data then
		return
	end
	for index = 1, #CRAFT_SALE_VALUE_FIELDS do
		local value = data[CRAFT_SALE_VALUE_FIELDS[index]]
		if value and value > 0 then
			return value
		end
	end
end

local function GetBreakdown(itemID, priceScope, priceDB)
	for index = 1, #breakdownDataModules do
		local breakdown = breakdownDataModules[index]:GetValue(itemID, priceScope, priceDB)
		if breakdown then
			return breakdown
		end
	end
end

local function FormatCraftingValue(result, multiplier, auctionData, auctionCut)
	if not result or not result.value then
		return "--"
	end
	local craftingValue = result.value * multiplier
	local value = addon:FormatMoney(craftingValue)
	local saleValue = GetCraftSaleValue(auctionData)
	if saleValue then
		-- Applicable Alchemy specializations increase expected saleable output
		-- without changing the recipe's crafting or material costs.
		local expectedReturn = addon:RoundMoney(saleValue * auctionCut * multiplier
			* result.expectedOutputMultiplier)
		local profit = expectedReturn - craftingValue
		local color = profit > 0 and GREEN_NUMBER or profit < 0 and RED_NUMBER or nil
		value = format(L["%s (%s)"], value, addon:FormatMoney(profit, true, color))
	end
	return result.stale and format(L["%s (stale)"], value) or value
end

function module:AddItemData(tooltip, itemID, scope, suppressRefresh)
	local activeScope, scopeDB, scopeName = GetContext(scope)
	local auctionHouseType = addon:GetAuctionHouseTypeForScope(activeScope)
	local data = scopeDB.auctionDB[itemID]
	local priceScope = activeScope == "realm" and "realm" or "factionrealm"
	local settings = addon.db.profile.tooltip
	local breakdown = (settings["10-breakdownValue"] or settings["11-breakdownResults"])
		and GetBreakdown(itemID, priceScope, scopeDB.auctionDB) or nil
	local conversion = (settings["21-conversionValue"] or settings["22-conversionResults"])
		and convertData:GetValue(itemID, priceScope, scopeDB.auctionDB) or nil
	local inventoryBuy = inventoryAverageBuy:GetValue(itemID)
	local allowAlchemySpecialization = usesSharedAuctionHouse
		or activeScope == "factionrealm"
	local factionCrafting = professionScanner:GetItemCrafting(
		itemID, scopeDB.auctionDB, false, allowAlchemySpecialization)
	local knownCraft = professionScanner:IsItemKnown(itemID, false)
	local personalRollingSaleRate = saleCollector:GetPersonalRollingSaleMetrics(itemID)
	local realmRollingSaleRate, realmRollingSalesPerDay, realmRollingAverageSaleValue =
		saleCollector:GetRealmRollingSaleMetrics(itemID, auctionHouseType)
	local _, _, _, _, _, _, _, _, _, _, vendorSell = C_Item.GetItemInfo(itemID)
	local vendorBuy = addon.db.global.vendorBuyPrices[itemID]
	if not data and not breakdown and not conversion and not inventoryBuy and not knownCraft
		and personalRollingSaleRate == nil and realmRollingSaleRate == nil
		and realmRollingSalesPerDay == nil and not vendorSell and not vendorBuy then
		return
	end
	data = data or {}

	local multiplier = GetCursorStackCount(itemID)
	local auctionCut = auctionHouseType == "Neutral" and 0.85 or 0.95
	local activeSection, addedHeader
	local function EnsureHeader()
		if not addedHeader then
			tooltip:AddLine(" ")
			tooltip:AddLine("YAAHA", 1, 0.82, 0)
			tooltip:AddLine(format(L["----- %s -----"], scopeName), 0.75, 0.75, 0.75)
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
		if settings[field[3]] and value and value > 0 then
			local isAuctionPrice = key == "minBid" or key == "minBuyout"
			local display = addon:FormatMoney(value * multiplier, false, nil, isAuctionPrice)
			local trend = key ~= "currentMarketValue" and data.trends and FormatTrend(data.trends[key], multiplier)
			if trend then
				display = display .. "  " .. trend
			end
			AddLine(AUCTIONS, L[field[2]], display)
		end
	end

	if settings["09-auctionQuantity"] and data.auctionQuantity and data.auctionQuantity >= 1 then
		AddLine(AUCTIONS, AUCTION_HOUSE_BROWSE_HEADER_QUANTITY, FormatQuantity(data.auctionQuantity))
	end

	for index = 1, #vendorPriceFields do
		local field = vendorPriceFields[index]
		local key = field[1]
		local value = key == "vendorSell" and vendorSell or vendorBuy
		if settings[field[3]] and value and value > 0 then
			local label = key == "vendorSell" and field[2] or L[field[2]]
			AddLine(L["Vendor prices"], label, addon:FormatMoney(value * multiplier))
		end
	end

	for index = 1, #saleFields do
		local field = saleFields[index]
		local key, kind = field[1], field[3]
		local value = key == "personalRollingSaleRate" and personalRollingSaleRate
			or key == "realmRollingSaleRate" and realmRollingSaleRate
			or key == "realmRollingSalesPerDay" and realmRollingSalesPerDay
			or key == "realmRollingAverageSaleValue" and realmRollingAverageSaleValue or data[key]
		if settings[field[4]] and value ~= nil then
			if kind == "rate" and value >= 0 and value <= 1 then
				AddLine(L["Sales"], L[field[2]], FormatRate(value))
			elseif kind == "decimal" and value >= 0 then
				AddLine(L["Sales"], L[field[2]], addon:FormatDecimal(value) or "")
			elseif kind == "quantity" and value >= 0 then
				AddLine(L["Sales"], L[field[2]], FormatQuantity(value))
			elseif kind == "money" and value > 0 then
				AddLine(L["Sales"], L[field[2]], addon:FormatMoney(value))
			end
		end
	end
	if settings["14-inventoryAverageBuy"] and inventoryBuy and inventoryBuy > 0 then
		AddLine(L["Purchases"], L["Inventory average buy"],
			addon:FormatMoney(inventoryBuy * multiplier))
	end
	if settings["19-craftingValue"] and knownCraft then
		AddLine(L["Crafting"], L["Crafting cost"],
			FormatCraftingValue(factionCrafting, multiplier, data, auctionCut))
	end
	AddCraftingLines(AddLine, factionCrafting, settings["20-craftingResults"], multiplier)

	if breakdown and settings["11-breakdownResults"] then
		for index = 1, #breakdown.results do
			local result = breakdown.results[index]
			local quantityScale = multiplier
				/ (result.requiredQuantity or breakdown.requiredQuantity or 1)
			local materialName, materialLink = C_Item.GetItemInfo(result.itemID)
			local label = materialLink or materialName or tostring(result.itemID)
			local value = format(L["%s x%s"], FormatRate(result.chance),
				FormatExpectedQuantity(result.expectedQuantity * quantityScale))
			if result.missingPrice then
				value = value .. "  |cff9d9d9d-- (" .. L["Not found in auction data"] .. ")|r"
			else
				value = value .. "  " .. addon:FormatMoney(result.expectedValue * quantityScale)
			end
			AddLine(L["Breakdown"], label, value)
		end
	end
	if breakdown and settings["10-breakdownValue"] then
		local expectedValue = breakdown.expectedUnitValue
			and breakdown.expectedUnitValue * multiplier
			or breakdown.expectedValue
			and breakdown.expectedValue * multiplier / (breakdown.requiredQuantity or 1)
		AddLine(L["Breakdown"], L["Expected breakdown value"],
			expectedValue and addon:FormatMoney(expectedValue, true) or "--")
	end

	if conversion and settings["21-conversionValue"] then
		AddLine(L["Conversion"], L["Conversion cost"],
			conversion.value and addon:FormatMoney(conversion.value * multiplier, true) or "--")
	end
	if conversion and settings["22-conversionResults"] then
		for index = 1, #conversion.results do
			local result = conversion.results[index]
			local sourceName, sourceLink = C_Item.GetItemInfo(result.itemID)
			local label = format(L["%s x%s"],
				sourceLink or sourceName or tostring(result.itemID),
				FormatExpectedQuantity(result.quantity * multiplier))
			AddLine(L["Conversion"], label,
				result.totalValue and addon:FormatMoney(result.totalValue * multiplier) or "--")
		end
	end
	if conversion and conversion.bestResult and data.currentMarketValue
		and conversion.bestResult.totalValue < data.currentMarketValue then
		local result = conversion.bestResult
		local sourceName, sourceLink = C_Item.GetItemInfo(result.itemID)
		local targetName, targetLink = C_Item.GetItemInfo(itemID)
		AddLine(L["Conversion"], format(L["Cheaper conversion: %s x%s -> %s x%s"],
			sourceLink or sourceName or tostring(result.itemID),
			FormatExpectedQuantity(result.quantity * multiplier),
			targetLink or targetName or tostring(itemID), FormatExpectedQuantity(multiplier)), "")
	end

	if addedHeader and not suppressRefresh then
		tooltip:Show()
	end
end

function module:AddRecipeData(tooltip, spellID, scope, reuseHeader, suppressRefresh)
	local activeScope, scopeDB, scopeName = GetContext(scope)
	if not professionScanner:IsRecipeKnown(spellID, false) then
		return
	end
	local allowAlchemySpecialization = usesSharedAuctionHouse
		or activeScope == "factionrealm"
	local factionCrafting = professionScanner:GetRecipeCrafting(
		spellID, scopeDB.auctionDB, false, allowAlchemySpecialization)
	local settings = addon.db.profile.tooltip
	if not settings["19-craftingValue"] and not settings["20-craftingResults"] then
		return
	end

	local activeSection
	local addedHeader = reuseHeader
	local function AddLine(section, label, value)
		if not addedHeader then
			tooltip:AddLine(" ")
			tooltip:AddLine("YAAHA", 1, 0.82, 0)
			tooltip:AddLine(format(L["----- %s -----"], scopeName), 0.75, 0.75, 0.75)
			addedHeader = true
		end
		if activeSection ~= section then
			tooltip:AddLine(section, 1, 0.82, 0)
			activeSection = section
		end
		tooltip:AddDoubleLine("  " .. label, value, 1, 1, 1, 1, 1, 1)
	end

	if settings["19-craftingValue"] then
		AddLine(L["Crafting"], L["Crafting cost"],
			FormatCraftingValue(factionCrafting, 1,
				factionCrafting and factionCrafting.outputItemID
					and scopeDB.auctionDB[factionCrafting.outputItemID],
				activeScope == "realm" and 0.85 or 0.95))
	end
	AddCraftingLines(AddLine, factionCrafting, settings["20-craftingResults"], 1)
	if addedHeader and not suppressRefresh then
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

function module:ProcessItemTooltip(tooltip, itemID, link, immediate)
	local state = tooltipState[tooltip]
	if not itemID or state and state.itemID == itemID and HasRenderedYAAHAData(tooltip) then
		return
	end
	if state and state.itemID == itemID and state.pending and not immediate then
		return
	end

	state = { itemID = itemID, link = link, pending = not immediate }
	tooltipState[tooltip] = state
	local sameDisplay = IsSameDisplay(tooltip, "item", itemID)
	if immediate or sameDisplay then
		module:AddItemData(tooltip, itemID, nil, sameDisplay)
		RememberDisplay(tooltip, "item", itemID)
		return
	end

	-- Profession tooltips can briefly identify one of a recipe's reagents as the
	-- displayed item before their craft callback supplies the real spell. Waiting
	-- until the current render finishes lets that callback replace this state and
	-- prevents both the false item section and a duplicate recipe section.
	C_Timer.After(0, function()
		if tooltipState[tooltip] ~= state or not tooltip:IsShown()
			or HasRenderedYAAHAData(tooltip) then
			return
		end
		state.pending = nil
		module:AddItemData(tooltip, itemID)
		RememberDisplay(tooltip, "item", itemID)
	end)
end

function module:ProcessSpellTooltip(tooltip, spellID)
	if not spellID then
		_, spellID = tooltip:GetSpell()
	end
	local state = tooltipState[tooltip]
	if not spellID or state and state.spellID == spellID and HasRenderedYAAHAData(tooltip) then
		return
	end
	local sameDisplay = IsSameDisplay(tooltip, "recipe", spellID)
	tooltipState[tooltip] = { spellID = spellID }
	module:AddRecipeData(tooltip, spellID, nil, false, sameDisplay)
	RememberDisplay(tooltip, "recipe", spellID)
end

function module:ProcessRecipeTooltip(tooltip, spellID)
	local state = tooltipState[tooltip]
	local hasRenderedData = HasRenderedYAAHAData(tooltip)
	if not spellID or state and state.spellID == spellID and hasRenderedData then
		return
	end
	-- Replace rather than mutate a pending item state. Its deferred callback uses
	-- table identity to recognize that this recipe superseded the transient item.
	local sameDisplay = IsSameDisplay(tooltip, "recipe", spellID)
	tooltipState[tooltip] = { spellID = spellID }
	module:AddRecipeData(tooltip, spellID, nil, hasRenderedData, sameDisplay)
	RememberDisplay(tooltip, "recipe", spellID)
end

function module:GetTooltipFrames()
	return tooltips
end

function module:ClearTooltipState(tooltip)
	tooltipState[tooltip] = nil
end

function module:ClearTooltipDisplayState(tooltip)
	tooltipState[tooltip] = nil
	tooltipDisplayState[tooltip] = nil
end