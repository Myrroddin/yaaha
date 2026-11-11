-- Presents disenchanting, prospecting, and milling through one per-item breakdown interface.

local LibStub = LibStub

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local module = addon:NewModule("BreakdownData")
local sources = {
	{ breakdownType = "disenchanting", dataModule = addon:GetModule("DisenchantingData") },
	{ breakdownType = "prospecting", dataModule = addon:GetModule("ProspectingData", true) },
	{ breakdownType = "milling", dataModule = addon:GetModule("MillingData", true) },
}

local function DecorateResult(result, breakdownType)
	if not result then
		return
	end
	result.breakdownType = breakdownType
	result.requiredQuantity = result.requiredQuantity or 1
	-- Disenchanting already represents one input item. Prospecting and milling
	-- retain their five-item operation details but expose a comparable per-item value.
	result.expectedUnitValue = result.expectedUnitValue or result.expectedValue
	return result
end

function module:GetResults(itemInfo)
	for index = 1, #sources do
		local source = sources[index]
		local result = source.dataModule and source.dataModule:GetResults(itemInfo)
		if result then
			return DecorateResult(result, source.breakdownType)
		end
	end
end

function module:GetValue(itemInfo, scope, priceDB)
	for index = 1, #sources do
		local source = sources[index]
		local result = source.dataModule and source.dataModule:GetValue(itemInfo, scope, priceDB)
		if result then
			return DecorateResult(result, source.breakdownType)
		end
	end
end

function module:IsBreakable(itemInfo)
	for index = 1, #sources do
		local source = sources[index]
		if source.dataModule and source.dataModule:IsBreakable(itemInfo) then
			return true
		end
	end
	return false
end