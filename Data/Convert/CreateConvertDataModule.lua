-- Creates the shared deterministic-conversion module used by crafting costs and tooltips.

local C_Item = C_Item
local LibStub = LibStub
local next = next
local pairs = pairs
local sort = table.sort
local type = type

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local module = addon:NewModule("ConvertData")

local function SortByItemID(left, right)
	return left.itemID < right.itemID
end

-- Cost conversions contain only transformations that every character can use.
-- Tooltip conversions also include profession-gated transformations so players
-- can evaluate materials without logging onto the character who can perform one.
local costConversions = {}
local tooltipConversions = {}

local function GetItemID(itemInfo)
	if type(itemInfo) == "number" then
		return itemInfo
	end
	return itemInfo and C_Item.GetItemInfoInstant(itemInfo) or nil
end

function module:AddConversion(targetItemID, sourceItemID, sourcePerTarget, tooltipOnly)
	if not tooltipOnly then
		local sources = costConversions[targetItemID]
		if not sources then
			sources = {}
			costConversions[targetItemID] = sources
		end
		sources[sourceItemID] = sourcePerTarget
	end

	local sources = tooltipConversions[targetItemID]
	if not sources then
		sources = {}
		tooltipConversions[targetItemID] = sources
	end
	sources[sourceItemID] = sourcePerTarget
end

function module:AddReversibleConversion(firstItemID, secondItemID, secondPerFirst, tooltipOnly)
	self:AddConversion(firstItemID, secondItemID, secondPerFirst, tooltipOnly)
	self:AddConversion(secondItemID, firstItemID, 1 / secondPerFirst, tooltipOnly)
end

function module:RemoveConversion(targetItemID, sourceItemID)
	local sources = costConversions[targetItemID]
	if sources then
		sources[sourceItemID] = nil
		if not next(sources) then
			costConversions[targetItemID] = nil
		end
	end
	local tooltipSources = tooltipConversions[targetItemID]
	if tooltipSources then
		tooltipSources[sourceItemID] = nil
		if not next(tooltipSources) then
			tooltipConversions[targetItemID] = nil
		end
	end
end

function module:GetConversions(itemID)
	return costConversions[itemID]
end

function module:GetValue(itemInfo, scope, priceDB)
	local itemID = GetItemID(itemInfo)
	local sources = itemID and tooltipConversions[itemID]
	if not sources then
		return
	end

	local auctionDB = priceDB or addon.db[scope or "factionrealm"].auctionDB
	local results = {}
	local conversionCost
	local conversionTotal = 0
	local pricedPaths = 0
	local allPathsPriced = true
	for sourceItemID, sourcePerTarget in pairs(sources) do
		local prices = auctionDB[sourceItemID]
		local marketValue = addon:GetCurrentMarketValue(prices)
		local totalValue = marketValue
			and addon:RoundMoney(marketValue * sourcePerTarget) or nil
		local result = {
			itemID = sourceItemID,
			quantity = sourcePerTarget,
			marketValue = marketValue,
			priceSource = marketValue and "currentMarketValue" or nil,
			missingPrice = not marketValue,
			totalValue = totalValue,
		}
		results[#results + 1] = result
		if not totalValue then
			allPathsPriced = false
		else
			conversionTotal = conversionTotal + totalValue
			pricedPaths = pricedPaths + 1
		end
	end
	if pricedPaths > 0 then
		-- Interchangeable paths form one stable expected-cost candidate. The
		-- broader material resolver compares this average with market, vendor,
		-- crafting, and other independently complete acquisition methods.
		conversionCost = addon:RoundMoney(conversionTotal / pricedPaths)
	end

	sort(results, SortByItemID)
	return {
		itemID = itemID,
		results = results,
		value = conversionCost,
		-- A single-source conversion can name an exact recommendation. No one
		-- source honestly represents an averaged family of alternatives.
		bestResult = pricedPaths == 1 and #results == 1 and results[1] or nil,
		alternatives = #results > 1,
		complete = pricedPaths > 0,
		allPathsPriced = allPathsPriced,
	}
end