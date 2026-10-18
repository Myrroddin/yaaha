-- Provides shared probability, observation, and valuation logic for client-specific milling and prospecting data.

local C_Item = C_Item
local LibStub = LibStub
local max = math.max
local min = math.min
local next = next
local pairs = pairs
local sort = table.sort
local type = type

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local module = addon:NewModule("MaterialBreakdownData")

---@class VariableConversionDataModule: AceModule
---@field variableConversionDefinitions table<integer, table>
---@field variableConversionMaterials table<integer, boolean>
---@field variableConversionSavedKey "millingData"|"prospectData"
---@field GetResults fun(self: VariableConversionDataModule, itemInfo: number|string): table?
---@field GetValue fun(self: VariableConversionDataModule, itemInfo: number|string, scope?: string, priceDB?: table): table?
---@field IsMaterial fun(self: VariableConversionDataModule, itemID: integer): boolean
---@field IsSource fun(self: VariableConversionDataModule, itemInfo: number|string): boolean
---@field RecordObservation fun(self: VariableConversionDataModule, itemInfo: number|string, loot: table<integer, number>): boolean?
---@field SanitizeLearnedData fun(self: VariableConversionDataModule, learnedData: table): table?, integer

-- Static estimates act as virtual observations. Actual player results gradually
-- refine them without allowing a few unusually lucky or unlucky attempts to dominate.
local STATIC_SAMPLE_WEIGHT = 100

local methods = {}

local function LearnedResultsAreValid(learned, allowed)
	if type(learned) ~= "table" or type(learned.samples) ~= "number" or learned.samples <= 0
		or learned.samples % 1 ~= 0 or type(learned.results) ~= "table" then
		return false
	end
	local hasResults = false
	for materialID, observation in pairs(learned.results) do
		if not allowed[materialID] or type(observation) ~= "table"
			or type(observation.occurrences) ~= "number" or observation.occurrences <= 0
			or observation.occurrences % 1 ~= 0 or observation.occurrences > learned.samples
			or type(observation.quantity) ~= "number" or observation.quantity < observation.occurrences
			or observation.quantity % 1 ~= 0
			or observation.minQuantity ~= nil and (type(observation.minQuantity) ~= "number"
				or observation.minQuantity <= 0 or observation.minQuantity % 1 ~= 0)
			or observation.maxQuantity ~= nil and (type(observation.maxQuantity) ~= "number"
				or observation.maxQuantity <= 0 or observation.maxQuantity % 1 ~= 0)
			or observation.minQuantity and observation.maxQuantity
				and observation.minQuantity > observation.maxQuantity then
			return false
		end
		hasResults = true
	end
	return hasResults
end

local function CopyLearnedResults(learned, allowed)
	if not LearnedResultsAreValid(learned, allowed) then
		return
	end
	local copy = { samples = learned.samples, results = {} }
	for materialID, observation in pairs(learned.results) do
		copy.results[materialID] = {
			maxQuantity = observation.maxQuantity,
			minQuantity = observation.minQuantity,
			occurrences = observation.occurrences,
			quantity = observation.quantity,
		}
	end
	return copy
end

local function AddLearnedResults(aggregate, learned, allowed)
	if not LearnedResultsAreValid(learned, allowed) then
		return false
	end
	aggregate.samples = aggregate.samples + learned.samples
	for materialID, observation in pairs(learned.results) do
		local combined = aggregate.results[materialID]
		if not combined then
			combined = { occurrences = 0, quantity = 0 }
			aggregate.results[materialID] = combined
		end
		combined.occurrences = combined.occurrences + observation.occurrences
		combined.quantity = combined.quantity + observation.quantity
		combined.minQuantity = observation.minQuantity and (combined.minQuantity
			and min(combined.minQuantity, observation.minQuantity) or observation.minQuantity)
			or combined.minQuantity
		combined.maxQuantity = observation.maxQuantity and (combined.maxQuantity
			and max(combined.maxQuantity, observation.maxQuantity) or observation.maxQuantity)
			or combined.maxQuantity
	end
	return true
end

local function GetItemID(itemInfo)
	if type(itemInfo) == "number" then
		return itemInfo
	end
	return itemInfo and C_Item.GetItemInfoInstant(itemInfo) or nil
end

local function CopyResults(results)
	local copy = {}
	for index = 1, #results do
		local result = results[index]
		copy[index] = {
			itemID = result.itemID,
			chance = result.chance,
			minQuantity = result.minQuantity,
			maxQuantity = result.maxQuantity,
			expectedQuantity = result.expectedQuantity,
		}
	end
	return copy
end

function methods:IsSource(itemInfo)
	local itemID = GetItemID(itemInfo)
	return itemID and self.variableConversionDefinitions[itemID] ~= nil or false
end

function methods:IsMaterial(itemID)
	return self.variableConversionMaterials[itemID] == true
end

function methods:GetResults(itemInfo)
	local itemID = GetItemID(itemInfo)
	local definition = itemID and self.variableConversionDefinitions[itemID]
	if not definition then
		return
	end

	local results = CopyResults(definition.results)
	local aggregate = { samples = 0, results = {} }
	local saved = addon.db.global[self.variableConversionSavedKey]
	local learned = saved[itemID]
	local byItemID = {}
	for index = 1, #results do
		byItemID[results[index].itemID] = results[index]
	end
	local learnedIsValid = LearnedResultsAreValid(learned, byItemID)
	if learned and not learnedIsValid then
		-- The sample divisor belongs to the same captures as every result. If one
		-- result is impossible, discard the aggregate rather than partially salvage it.
		saved[itemID] = nil
		learned = nil
	end
	if learnedIsValid then
		AddLearnedResults(aggregate, learned, byItemID)
	end
	local syncedBySource = addon.db.global.collectorSyncData[self.variableConversionSavedKey]
	for sourceID, sourceData in pairs(syncedBySource) do
		local synced = type(sourceData) == "table" and sourceData[itemID]
		if synced and not AddLearnedResults(aggregate, synced, byItemID) then
			sourceData[itemID] = nil
			if not next(sourceData) then
				syncedBySource[sourceID] = nil
			end
		end
	end
	local sampleCount = aggregate.samples
	if sampleCount > 0 then
		local divisor = STATIC_SAMPLE_WEIGHT + sampleCount
		for index = 1, #results do
			local result = results[index]
			local observation = aggregate.results[result.itemID]
			result.chance = (result.chance * STATIC_SAMPLE_WEIGHT
				+ (observation and observation.occurrences or 0)) / divisor
			result.expectedQuantity = (result.expectedQuantity * STATIC_SAMPLE_WEIGHT
				+ (observation and observation.quantity or 0)) / divisor
			if observation then
				result.minQuantity = observation.minQuantity
					and min(result.minQuantity, observation.minQuantity) or result.minQuantity
				result.maxQuantity = observation.maxQuantity
					and max(result.maxQuantity, observation.maxQuantity) or result.maxQuantity
			end
		end
	end

	sort(results, function(left, right)
		return left.chance > right.chance
			or left.chance == right.chance and left.itemID < right.itemID
	end)
	return {
		itemID = itemID,
		requiredQuantity = definition.requiredQuantity,
		requiredSkill = definition.requiredSkill,
		sampleCount = sampleCount,
		results = results,
	}
end

function methods:SanitizeLearnedData(learnedData)
	local sanitized = {}
	local sampleCount = 0
	for itemID, learned in pairs(type(learnedData) == "table" and learnedData or {}) do
		local definition = type(itemID) == "number" and self.variableConversionDefinitions[itemID]
		if definition then
			local allowed = {}
			for index = 1, #definition.results do
				allowed[definition.results[index].itemID] = true
			end
			local copy = CopyLearnedResults(learned, allowed)
			if copy then
				sanitized[itemID] = copy
				sampleCount = sampleCount + copy.samples
			end
		end
	end
	return next(sanitized) and sanitized or nil, sampleCount
end

function methods:RecordObservation(itemInfo, loot)
	local itemID = GetItemID(itemInfo)
	local definition = itemID and self.variableConversionDefinitions[itemID]
	if not definition then
		return
	end
	local allowed = {}
	for index = 1, #definition.results do
		allowed[definition.results[index].itemID] = true
	end
	local hasResults = false
	for materialID, quantity in pairs(loot) do
		if not allowed[materialID] or quantity <= 0 then
			return
		end
		hasResults = true
	end
	if not hasResults then
		return
	end

	local saved = addon.db.global[self.variableConversionSavedKey]
	local learned = saved[itemID]
	if not LearnedResultsAreValid(learned, allowed) then
		learned = { samples = 0, results = {} }
		saved[itemID] = learned
	end
	learned.samples = learned.samples + 1
	for materialID, quantity in pairs(loot) do
		local observation = learned.results[materialID]
		if not observation then
			observation = { occurrences = 0, quantity = 0 }
			learned.results[materialID] = observation
		end
		observation.occurrences = observation.occurrences + 1
		observation.quantity = observation.quantity + quantity
		observation.minQuantity = observation.minQuantity
			and min(observation.minQuantity, quantity) or quantity
		observation.maxQuantity = observation.maxQuantity
			and max(observation.maxQuantity, quantity) or quantity
	end
	return true
end

function methods:GetValue(itemInfo, scope, priceDB)
	local breakdown = self:GetResults(itemInfo)
	if not breakdown then
		return
	end

	local auctionDB = priceDB or addon.db[scope or "factionrealm"].auctionDB
	local total = 0
	local complete = true
	for index = 1, #breakdown.results do
		local result = breakdown.results[index]
		local prices = auctionDB[result.itemID]
		result.marketValue = addon:GetCurrentMarketValue(prices)
		result.priceSource = result.marketValue and "currentMarketValue" or nil
		result.missingPrice = not result.marketValue
		if result.missingPrice then
			result.expectedValue = nil
			complete = false
		else
			result.expectedValue = result.expectedQuantity * result.marketValue
			total = total + result.expectedValue
		end
	end
	breakdown.expectedValue = complete and total or nil
	breakdown.expectedUnitValue = complete and total / breakdown.requiredQuantity or nil
	breakdown.complete = complete
	return breakdown
end

---@param target VariableConversionDataModule
---@param savedKey "millingData"|"prospectData"
---@param definitions table<integer, table>
function module:InitializeDataModule(target, savedKey, definitions)
	local materials = {}
	for _, definition in pairs(definitions) do
		for index = 1, #definition.results do
			materials[definition.results[index].itemID] = true
		end
	end
	target.variableConversionDefinitions = definitions
	target.variableConversionMaterials = materials
	target.variableConversionSavedKey = savedKey
	for name, method in pairs(methods) do
		target[name] = method
	end
end