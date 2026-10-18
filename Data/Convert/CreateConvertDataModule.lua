-- Creates the shared deterministic-conversion module used by crafting costs and tooltips.

local C_Item = C_Item
local huge = math.huge
local LibStub = LibStub
local next = next
local pairs = pairs
local sort = table.sort
local type = type

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local module = addon:NewModule("ConvertData")

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

---@param targetItemID integer
---@param sourceItemID integer
---@param sourcePerTarget number
---@param tooltipOnly? boolean
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

---@param firstItemID integer
---@param secondItemID integer
---@param secondPerFirst number
---@param tooltipOnly? boolean
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
	local bestResult
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
		if totalValue and totalValue < (conversionCost or huge) then
			conversionCost = totalValue
			bestResult = result
		end
	end

	sort(results, function(left, right)
		return left.itemID < right.itemID
	end)
	return {
		itemID = itemID,
		results = results,
		value = conversionCost,
		bestResult = bestResult,
		alternatives = #results > 1,
	}
end