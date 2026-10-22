-- Collects known recipes from the modern C_TradeSkillUI profession APIs.

local C_Timer = C_Timer
local C_TradeSkillUI = C_TradeSkillUI
local Enum = Enum
local GetProfessionInfo = GetProfessionInfo
local GetProfessions = GetProfessions
local ipairs = ipairs
local LibStub = LibStub
local select = select
local type = type

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local ALCHEMY_SKILL_LINE = addon.alchemySkillLineID
local module = addon:GetModule("ProfessionScanner")

local scanPending = false
local scanning = false

local function IsExternalProfession()
	return C_TradeSkillUI.IsNPCCrafting()
		or C_TradeSkillUI.IsTradeSkillGuild()
		or C_TradeSkillUI.IsTradeSkillGuildMember and C_TradeSkillUI.IsTradeSkillGuildMember()
		or C_TradeSkillUI.IsTradeSkillLinked()
end

local function IsProfessionReady()
	return C_TradeSkillUI.IsTradeSkillReady()
		and not C_TradeSkillUI.IsDataSourceChanging()
end

local function AddUniqueItemID(itemIDs, seen, itemID)
	if itemID and itemID > 0 and not seen[itemID] then
		seen[itemID] = true
		itemIDs[#itemIDs + 1] = itemID
	end
end

local function ReadOutputItemIDs(recipeID, recipeInfo, schematic)
	local itemIDs = {}
	local seen = {}
	AddUniqueItemID(itemIDs, seen, schematic.outputItemID)
	for _, itemID in ipairs(recipeInfo.qualityItemIDs or {}) do
		AddUniqueItemID(itemIDs, seen, itemID)
	end
	if C_TradeSkillUI.GetRecipeQualityItemIDs then
		for _, itemID in ipairs(C_TradeSkillUI.GetRecipeQualityItemIDs(recipeID) or {}) do
			AddUniqueItemID(itemIDs, seen, itemID)
		end
	end
	local outputInfo = C_TradeSkillUI.GetRecipeOutputItemData(recipeID)
	AddUniqueItemID(itemIDs, seen, outputInfo and outputInfo.itemID)
	return itemIDs
end

local function ReadReagentSlots(schematic)
	local slots = {}
	for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
		local reagentType = slot.reagentType
		local isBasic = reagentType == Enum.CraftingReagentType.Basic
		local isRequiredModifying = reagentType == Enum.CraftingReagentType.Modifying
			and slot.required
		-- Optional reagents represent a player's chosen variation, not the recipe's
		-- baseline cost. Required modifying slots remain mandatory and are retained.
		if isBasic or isRequiredModifying then
			local quantities = {}
			for _, variable in ipairs(slot.variableQuantities or {}) do
				local reagent = variable.reagent
				if reagent and reagent.itemID then
					quantities[reagent.itemID] = variable.quantity
				end
			end
			local items = {}
			for _, reagent in ipairs(slot.reagents or {}) do
				if reagent.itemID then
					items[#items + 1] = {
						itemID = reagent.itemID,
						quantity = quantities[reagent.itemID] or slot.quantityRequired,
					}
				end
			end
			-- Keep required currency-only or unresolved slots. An empty candidate
			-- list makes the shared calculator return unavailable instead of an
			-- incorrectly low crafting value.
			slots[#slots + 1] = {
				quantity = slot.quantityRequired,
				items = items,
			}
		end
	end
	return slots
end

local function GetRecipeRank(recipeInfo, recipeInfos)
	local rank = 1
	local previousRecipeID = recipeInfo.previousRecipeID
	local seen = {}
	while previousRecipeID do
		if seen[previousRecipeID] then
			return
		end
		seen[previousRecipeID] = true
		local previousInfo = recipeInfos[previousRecipeID]
		if not previousInfo then
			previousInfo = C_TradeSkillUI.GetRecipeInfo(previousRecipeID)
			recipeInfos[previousRecipeID] = previousInfo
		end
		if not previousInfo then
			return
		end
		rank = rank + 1
		previousRecipeID = previousInfo.previousRecipeID
	end
	return rank
end

local function ReadRecipe(recipeID, recipeInfo, rank, isAlchemy)
	local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
	if not schematic then
		return
	end
	local outputItemIDs = ReadOutputItemIDs(recipeID, recipeInfo, schematic)
	local alchemyCategory, expansionID
	if isAlchemy then
		local ready
		alchemyCategory, expansionID, ready = module:GetAlchemyRecipeData(
			outputItemIDs[1], recipeInfo.alternateVerb ~= nil
			and recipeInfo.alternateVerb ~= "")
		if not ready then
			return
		end
	end
	local minMade = schematic.quantityMin and schematic.quantityMin > 0
		and schematic.quantityMin or 1
	local maxMade = schematic.quantityMax and schematic.quantityMax > 0
		and schematic.quantityMax or minMade
	return {
		name = recipeInfo.name or schematic.name,
		spellID = recipeID,
		outputItemID = outputItemIDs[1],
		outputItemIDs = outputItemIDs,
		isEnchant = recipeInfo.isEnchantingRecipe,
		alchemyCategory = alchemyCategory,
		expansionID = expansionID,
		rank = rank,
		minMade = minMade,
		maxMade = maxMade,
		reagentSlots = ReadReagentSlots(schematic),
	}
end

local function GetCurrentProfessionInfo()
	local baseInfo = C_TradeSkillUI.GetBaseProfessionInfo()
	local childInfo = C_TradeSkillUI.GetChildProfessionInfo()
	if not baseInfo or not baseInfo.professionID or baseInfo.professionID == 0 then
		return
	end
	if not childInfo or not childInfo.professionID or childInfo.professionID == 0 then
		childInfo = baseInfo
	end
	return baseInfo, childInfo
end

local function ScanProfession()
	if scanning or IsExternalProfession() then
		return true
	end
	if not IsProfessionReady() then
		return false
	end
	local baseInfo, childInfo = GetCurrentProfessionInfo()
	if not baseInfo or childInfo.maxSkillLevel == 0 then
		return false
	end
	scanning = true
	local recipeIDs = C_TradeSkillUI.GetAllRecipeIDs()
	if not recipeIDs or #recipeIDs == 0 then
		scanning = false
		return false
	end
	local recipeInfos = {}
	for _, recipeID in ipairs(recipeIDs) do
		recipeInfos[recipeID] = C_TradeSkillUI.GetRecipeInfo(recipeID)
	end
	local parentSkillLineID = childInfo.parentProfessionID or baseInfo.professionID
	local isAlchemy = parentSkillLineID == ALCHEMY_SKILL_LINE
	local recipes = {}
	for _, recipeID in ipairs(recipeIDs) do
		local recipeInfo = recipeInfos[recipeID]
		local nextRecipeID = recipeInfo and recipeInfo.nextRecipeID
		local nextRecipeInfo = nextRecipeID and (recipeInfos[nextRecipeID]
			or C_TradeSkillUI.GetRecipeInfo(nextRecipeID))
		local hasLearnedHigherRank = nextRecipeInfo and nextRecipeInfo.learned
		-- Rank chains describe alternate versions of one recipe. Once a higher rank is
		-- learned, retaining its predecessor would create a duplicate, inferior path.
		if recipeInfo and recipeInfo.learned and not recipeInfo.isDummyRecipe
			and not recipeInfo.isRecraft and not recipeInfo.isGatheringRecipe
			and not recipeInfo.isSalvageRecipe and not hasLearnedHigherRank then
			local rank = GetRecipeRank(recipeInfo, recipeInfos)
			if not rank then
				scanning = false
				return false
			end
			local recipe = ReadRecipe(recipeID, recipeInfo, rank, isAlchemy)
			if not recipe then
				scanning = false
				return false
			end
			recipes[recipeID] = recipe
		end
	end
	local professionName = baseInfo.parentProfessionName
	if not professionName or professionName == "" then
		professionName = baseInfo.professionName
	end
	module:SaveProfession(childInfo.professionID, {
		collector = "modern",
		name = professionName,
		skillLineID = childInfo.professionID,
		parentSkillLineID = parentSkillLineID,
		skillLineName = childInfo.expansionName ~= "" and childInfo.expansionName
			or childInfo.professionName,
		isPrimary = baseInfo.isPrimaryProfession,
		alchemyMastery = isAlchemy and module:GetActiveAlchemyMastery() or nil,
		currentLevel = childInfo.skillLevel,
		maxLevel = childInfo.maxSkillLevel,
		recipes = recipes,
	})
	scanning = false
	return true
end

local QueueScan

-- A zero-second timer defers scanning until the next frame, after Blizzard
-- finishes the current profession event. Bounded retries wait for missing data.
QueueScan = function(delay, attempt)
	if scanPending then
		return
	end
	scanPending = true
	C_Timer.After(delay or 0, function()
		scanPending = false
		attempt = attempt or 1
		if not ScanProfession() and attempt < 11 then
			QueueScan(0.2, attempt + 1)
		end
	end)
end

local function ReconcileProfessions()
	local learnedSkillLines = {}
	local count = select("#", GetProfessions())
	for slot = 1, count do
		local professionIndex = select(slot, GetProfessions())
		if professionIndex then
			local _, _, _, _, _, _, skillLineID = GetProfessionInfo(professionIndex)
			if skillLineID then
				learnedSkillLines[skillLineID] = true
			end
		end
	end
	module:RemoveProfessions(function(_, profession)
		local parentSkillLineID = profession.parentSkillLineID or profession.skillLineID
		return profession.collector == "modern"
			and parentSkillLineID and not learnedSkillLines[parentSkillLineID]
	end)
end

function module:GetCraftRecipeSpellID(recipeID)
	return type(recipeID) == "number" and C_TradeSkillUI.GetRecipeInfo(recipeID)
		and recipeID or nil
end

function module:GetTradeSkillRecipeSpellID(recipeID)
	return self:GetCraftRecipeSpellID(recipeID)
end

function module:TRADE_SKILL_SHOW()
	QueueScan()
end

function module:TRADE_SKILL_LIST_UPDATE()
	QueueScan(0.05)
end

function module:TRADE_SKILL_DATA_SOURCE_CHANGED()
	QueueScan(0.05)
end

function module:NEW_RECIPE_LEARNED()
	QueueScan(0.05)
end

function module:SKILL_LINES_CHANGED()
	-- Let Blizzard finish updating skill lines before pruning saved professions.
	C_Timer.After(0, ReconcileProfessions)
end

function module:OnEnable()
	self:RegisterEvent("TRADE_SKILL_SHOW")
	self:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
	self:RegisterEvent("TRADE_SKILL_DATA_SOURCE_CHANGED")
	self:RegisterEvent("NEW_RECIPE_LEARNED")
	self:RegisterEvent("SKILL_LINES_CHANGED")
	-- Defer login reconciliation until Blizzard's skill-line data has settled.
	C_Timer.After(0, ReconcileProfessions)
end