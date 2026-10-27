-- Stores known recipes and provides shared material and crafting-value calculations.

local C_Item = C_Item
local C_SpellBook = C_SpellBook
local GetBuildInfo = GetBuildInfo
local GetServerTime = GetServerTime
local ipairs = ipairs
local LibStub = LibStub
local max = math.max
local pairs = pairs
local select = select
local setmetatable = setmetatable
local sort = table.sort
local time = time
local type = type

local ALCHEMY_MASTERY_BONUS = 1.2
local LEGION_BFA_RANK_THREE_BONUS = 1.4
local BFA_EXPANSION = 7
local LEGION_EXPANSION = 6
local MISTS_EXPANSION = 4
local ELIXIR_MASTERY_SPELL = 28677
local POTION_MASTERY_SPELL = 28675
local TRANSMUTATION_MASTERY_SPELL = 28672
local CONSUMABLE_CLASS = 0
local ELIXIR_SUBCLASS = 2
local FLASK_SUBCLASS = 3
local POTION_SUBCLASS = 1
local MATERIAL_MARKET_VALUE_FIELD = "currentMarketValue"
local ITEM_BIND_ON_ACQUIRE = Enum.ItemBind.OnAcquire
local ITEM_BIND_QUEST = Enum.ItemBind.Quest
local COPPER_PER_GOLD = 10000

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local isClassicEra = addon.isClassicEra
local isForever = addon.isForever
local isMists = addon.isMists
local isStandard = addon.isStandard
local ALCHEMY_SKILL_LINE = addon.alchemySkillLineID
local module = addon:NewModule("ProfessionScanner", "AceEvent-3.0")
local supportsAlchemyMastery = not isClassicEra and not isForever
local usesUniversalVellum = isStandard or isMists
local convertData = addon:GetModule("ConvertData")
local derivedMaterialData = addon:GetModule("DerivedMaterialData")
-- Wrath and Mists load spell-to-scroll mappings; modern recipe APIs provide
-- their own output items.
local enchantingScrollData = addon:GetModule("EnchantingScrollData", true)

local currentBuild = select(2, GetBuildInfo())
local recipeRevision = 0
local recipeIndexes = {}
local knownReagentIndex
local knownReagentRevision = -1

local ENCHANTING_VELLUM_ITEM_ID = 38682

local function GetTimestamp()
	return GetServerTime and GetServerTime() or time()
end

local function GetProfessionStore()
	return addon.db.factionrealm.knownProfessions
end

local function RecipeHasReagent(recipe, itemID)
	if recipe.reagents and recipe.reagents[itemID] then
		return true
	end
	for _, slot in ipairs(recipe.reagentSlots or {}) do
		for _, candidate in ipairs(slot.items or {}) do
			if candidate.itemID == itemID then
				return true
			end
		end
	end
	return false
end

local function AddKnownReagents(index, professionStore)
	for _, professions in pairs(professionStore or {}) do
		for _, profession in pairs(professions or {}) do
			for _, recipe in pairs(profession.recipes or {}) do
				for itemID in pairs(recipe.reagents or {}) do
					if type(itemID) == "number" and itemID > 0 then
						index[itemID] = true
					end
				end
				for _, slot in ipairs(recipe.reagentSlots or {}) do
					for _, candidate in ipairs(slot.items or {}) do
						if type(candidate.itemID) == "number" and candidate.itemID > 0 then
							index[candidate.itemID] = true
						end
					end
				end
			end
		end
	end
end

local function GetKnownReagentIndex()
	if knownReagentRevision == recipeRevision then
		return knownReagentIndex
	end
	knownReagentIndex = {}
	-- Vendor prices are global, so retain reagents known on every saved
	-- faction-realm rather than pruning another faction's useful prices.
	for _, scopeDB in pairs(addon.db.sv.factionrealm or {}) do
		AddKnownReagents(knownReagentIndex, scopeDB.knownProfessions)
	end
	-- The active AceDB scope may contain default-backed data which has not yet
	-- been materialized in the raw saved-variable table.
	AddKnownReagents(knownReagentIndex, GetProfessionStore())
	knownReagentRevision = recipeRevision
	return knownReagentIndex
end

local function GetExpectedOutputMultiplier(entry, allowAlchemySpecialization)
	if entry.skillLineID ~= ALCHEMY_SKILL_LINE or not allowAlchemySpecialization then
		return 1
	end
	local expansionID = entry.recipe.expansionID
	if entry.recipe.rank == 3
		and (expansionID == LEGION_EXPANSION or expansionID == BFA_EXPANSION) then
		return LEGION_BFA_RANK_THREE_BONUS
	end
	if (expansionID and expansionID >= 0) and (expansionID <= MISTS_EXPANSION) and (entry.recipe.alchemyCategory == entry.alchemyMastery) then
		return ALCHEMY_MASTERY_BONUS
	end
	return 1
end

function module:GetActiveAlchemyMastery()
	if not supportsAlchemyMastery then
		return
	end
	if C_SpellBook.IsSpellKnown(POTION_MASTERY_SPELL) then
		return "potion"
	elseif C_SpellBook.IsSpellKnown(ELIXIR_MASTERY_SPELL) then
		return "elixir"
	elseif C_SpellBook.IsSpellKnown(TRANSMUTATION_MASTERY_SPELL) then
		return "transmutation"
	end
end

function module:GetAlchemyRecipeData(itemID, isTransmutation)
	if not itemID then
		return nil, nil, false
	end
	local itemName, _, _, _, _, _, _, _, _, _, _, classID, subclassID, _, expansionID = C_Item.GetItemInfo(itemID)
	if not itemName then
		C_Item.RequestLoadItemDataByID(itemID)
		return nil, nil, false
	end
	if isTransmutation then
		return "transmutation", expansionID, true
	elseif classID == CONSUMABLE_CLASS then
		if subclassID == POTION_SUBCLASS then
			return "potion", expansionID, true
		elseif subclassID == ELIXIR_SUBCLASS or subclassID == FLASK_SUBCLASS then
			return "elixir", expansionID, true
		end
	end
	return nil, expansionID, true
end

function module:InvalidateRecipes()
	recipeRevision = recipeRevision + 1
	self:SendMessage("YAAHA_KNOWN_RECIPES_UPDATED")
end

function module:IsKnownReagent(itemID)
	return type(itemID) == "number" and itemID > 0
		and GetKnownReagentIndex()[itemID] == true
end

function module:SaveProfession(professionKey, profession)
	local characterKey = addon:GetCharacterKey()
	if not characterKey or professionKey == nil or not profession then
		return false
	end
	profession.build = currentBuild
	profession.lastScan = GetTimestamp()
	profession.recipes = profession.recipes or {}
	local professions = GetProfessionStore()[characterKey]
	if (profession.parentSkillLineID or profession.skillLineID) == ALCHEMY_SKILL_LINE then
		-- Alchemy mastery belongs to the character, not to one expansion's
		-- profession entry. Refresh every saved Alchemy branch together.
		for _, savedProfession in pairs(professions) do
			if (savedProfession.parentSkillLineID or savedProfession.skillLineID) == ALCHEMY_SKILL_LINE then
				savedProfession.alchemyMastery = profession.alchemyMastery
			end
		end
	end
	professions[professionKey] = profession
	self:InvalidateRecipes()
	return true
end

function module:RemoveProfessions(predicate, context)
	local characterKey = addon:GetCharacterKey()
	if not characterKey then
		return false
	end
	local professions = GetProfessionStore()[characterKey]
	local changed = false
	for professionKey, profession in pairs(professions) do
		if predicate(professionKey, profession, context) then
			professions[professionKey] = nil
			changed = true
		end
	end
	if changed then
		self:InvalidateRecipes()
	end
	return changed
end

local function ResolveKnownCraftOutput(itemID, currentCharacterOnly)
	local itemName = C_Item.GetItemInfo(itemID)
	if not itemName then
		return
	end
	local characterKey = addon:GetCharacterKey()
	local resolved = false
	for characterName, professions in pairs(GetProfessionStore()) do
		if not currentCharacterOnly or characterName == characterKey then
			for _, profession in pairs(professions) do
				for _, recipe in pairs(profession.recipes or {}) do
					if not recipe.outputItemID and not recipe.outputItemIDs
						and recipe.name == itemName then
						recipe.outputItemID = itemID
						resolved = true
					end
				end
			end
		end
	end
	if resolved then
		recipeRevision = recipeRevision + 1
	end
end

local function AddOutputRecipe(recipesByOutput, itemID, entry)
	if not itemID then
		return
	end
	local entries = recipesByOutput[itemID]
	if not entries then
		entries = {}
		recipesByOutput[itemID] = entries
	end
	entries[#entries + 1] = entry
end

local function AddSpellRecipe(recipesBySpell, spellID, entry)
	if not spellID then
		return
	end
	local entries = recipesBySpell[spellID]
	if not entries then
		entries = {}
		recipesBySpell[spellID] = entries
	end
	entries[#entries + 1] = entry
end

local function BuildRecipeIndex(currentCharacterOnly, outputItemID)
	local characterKey = addon:GetCharacterKey()
	local cacheKey = currentCharacterOnly and "character" or "factionrealm"
	local cached = recipeIndexes[cacheKey]
	if outputItemID and (not cached or not cached.recipesByOutput[outputItemID]) then
		-- The hovered item is cached, so it can resolve an item-producing Classic
		-- Enchanting recipe whose result was unavailable during its profession scan.
		ResolveKnownCraftOutput(outputItemID, currentCharacterOnly)
		cached = recipeIndexes[cacheKey]
	end
	if cached and cached.revision == recipeRevision then
		return cached.recipesBySpell, cached.recipesByOutput
	end

	local recipesBySpell = {}
	local recipesByOutput = {}
	for characterName, professions in pairs(GetProfessionStore()) do
		if not currentCharacterOnly or characterName == characterKey then
			for _, profession in pairs(professions) do
				for recipeKey, recipe in pairs(profession.recipes or {}) do
					local spellID = recipe.spellID
					if spellID == nil and type(recipeKey) == "number" then
						spellID = recipeKey
					end
					local entry = {
						character = characterName,
						profession = profession.name,
						skillLineID = profession.parentSkillLineID or profession.skillLineID,
						alchemyMastery = profession.alchemyMastery,
						stale = profession.build ~= currentBuild,
						spellID = spellID,
						recipe = recipe,
					}
					AddSpellRecipe(recipesBySpell, spellID, entry)
					AddOutputRecipe(recipesByOutput, recipe.outputItemID, entry)
					for _, itemID in ipairs(recipe.outputItemIDs or {}) do
						if itemID ~= recipe.outputItemID then
							AddOutputRecipe(recipesByOutput, itemID, entry)
						end
					end
				end
			end
		end
	end
	recipeIndexes[cacheKey] = {
		revision = recipeRevision,
		recipesBySpell = recipesBySpell,
		recipesByOutput = recipesByOutput,
	}
	return recipesBySpell, recipesByOutput
end

local function GetMaterialMarketValue(auctionDB, itemID)
	local data = auctionDB and auctionDB[itemID]
	local value = addon:GetCurrentMarketValue(data)
	if value then
		return value, MATERIAL_MARKET_VALUE_FIELD
	end
end

local function GetSoulboundFallback(itemID)
	local itemName, _, _, _, _, _, _, _, _, _, sellPrice, _, _, bindType, expansionID = C_Item.GetItemInfo(itemID)
	if not itemName then
		C_Item.RequestLoadItemDataByID(itemID)
		return
	end
	if bindType ~= ITEM_BIND_ON_ACQUIRE and bindType ~= ITEM_BIND_QUEST then
		return
	end
	local expansionLevel = max((expansionID or 0) + 1, 1)
	return max(sellPrice or 0, expansionLevel * COPPER_PER_GOLD)
end

local function HasFreshRecipe(entries)
	for index = 1, #entries do
		if not entries[index].stale then
			return true
		end
	end
	return false
end

local function Consider(best, value, source, detail)
	-- TSM-style material prices are whole copper before the minimum source is
	-- selected. This matters for per-unit conversions such as one greater
	-- essence becoming three lesser essences.
	value = addon:RoundMoney(value)
	if value and value > 0 and (not best or value < best.value) then
		return { value = value, source = source, detail = detail }
	end
	return best
end

local function AddMaterial(materials, material, itemID, quantity)
	local entry = {
		itemID = itemID,
		quantity = quantity,
	}
	local subtotal
	if material then
		subtotal = material.value * quantity
		entry.unitValue = material.value
		entry.totalValue = subtotal
		entry.source = material.source
		entry.detail = material.detail
	end
	materials[#materials + 1] = entry
	return subtotal
end

local function IsBetterResult(result, best)
	if not best then
		return true
	elseif not result.value then
		return false
	elseif not best.value then
		return true
	end
	return result.value < best.value or result.value == best.value
		and result.expectedOutputMultiplier > best.expectedOutputMultiplier
end

local function SortMaterials(left, right)
	return left.itemID < right.itemID
end

local Calculator = {}
Calculator.__index = Calculator

function Calculator:GetRecipeCost(entry)
	local cached = self.recipeCache[entry]
	if cached ~= nil then
		return cached or nil
	end
	if self.visitingRecipes[entry] then
		return
	end
	self.visitingRecipes[entry] = true
	local total = 0
	local materials = {}
	local complete = true

	if entry.recipe.reagentSlots then
		for _, slot in ipairs(entry.recipe.reagentSlots) do
			local cheapest, cheapestItemID, cheapestQuantity, cheapestTotal
			for _, candidate in ipairs(slot.items or {}) do
				local material = self:GetItemCost(candidate.itemID)
				local quantity = candidate.quantity or slot.quantity or 1
				local candidateTotal = material and quantity and material.value * quantity
				if candidateTotal and (not cheapestTotal or candidateTotal < cheapestTotal) then
					cheapest = material
					cheapestItemID = candidate.itemID
					cheapestQuantity = quantity
					cheapestTotal = candidateTotal
				end
			end
			if cheapest then
				total = total + AddMaterial(materials, cheapest, cheapestItemID, cheapestQuantity)
			else
				local candidate = slot.items and slot.items[1]
				if candidate then
					AddMaterial(materials, nil, candidate.itemID,
						candidate.quantity or slot.quantity or 1)
				end
				complete = false
			end
		end
	else
		for itemID, quantity in pairs(entry.recipe.reagents or {}) do
			local material = self:GetItemCost(itemID)
			local subtotal = AddMaterial(materials, material, itemID, quantity)
			if subtotal then
				total = total + subtotal
			else
				complete = false
			end
		end
	end

	local vellumItemIDs
	if enchantingScrollData then
		vellumItemIDs = select(2, enchantingScrollData:GetEnchant(entry.spellID))
	end
	if not vellumItemIDs and usesUniversalVellum
		and entry.recipe.isEnchant then
		vellumItemIDs = {ENCHANTING_VELLUM_ITEM_ID}
	end
	if vellumItemIDs then
		for _, itemID in ipairs(vellumItemIDs) do
			if RecipeHasReagent(entry.recipe, itemID) then
				vellumItemIDs = nil
				break
			end
		end
	end
	if vellumItemIDs then
		local cheapest, cheapestItemID
		for _, itemID in ipairs(vellumItemIDs) do
			local material = self:GetItemCost(itemID)
			if material and (not cheapest or material.value < cheapest.value) then
				cheapest = material
				cheapestItemID = itemID
			end
		end
		if cheapest then
			total = total + AddMaterial(materials, cheapest, cheapestItemID, 1)
		else
			AddMaterial(materials, nil, vellumItemIDs[1], 1)
			complete = false
		end
	end

	sort(materials, SortMaterials)
	self.visitingRecipes[entry] = nil
	local minMade = entry.recipe.minMade or 1
	local maxMade = entry.recipe.maxMade or minMade
	local outputQuantity = (minMade + maxMade) / 2
	local result = {
		-- Expected extra output affects finished-item return, never reagent
		-- requirements or baseline crafting cost.
		value = complete and addon:RoundMoney(total / outputQuantity) or nil,
		totalReagentValue = complete and total or nil,
		outputQuantity = outputQuantity,
		character = entry.character,
		profession = entry.profession,
		skillLineID = entry.skillLineID,
		expectedOutputMultiplier = GetExpectedOutputMultiplier(entry, self.allowAlchemySpecialization),
		stale = entry.stale,
		spellID = entry.spellID,
		outputItemID = entry.recipe.outputItemID or (entry.recipe.outputItemIDs and entry.recipe.outputItemIDs[1]),
		name = entry.recipe.name,
		materials = materials,
	}
	self.recipeCache[entry] = result
	return result
end

function Calculator:GetCurrentMarketValue(itemID)
	return GetMaterialMarketValue(self.auctionDB, itemID)
end

function Calculator:GetItemCost(itemID)
	local cached = self.itemCache[itemID]
	if cached ~= nil then
		return cached or nil
	end
	if self.visitingItems[itemID] then
		return
	end
	self.visitingItems[itemID] = true
	local hasDerivedMethod = derivedMaterialData:HasMethod(itemID)
	if hasDerivedMethod then
		-- Like a TSM per-material custom value, a registered method replaces the
		-- default material-cost method in full. Never fall through to market,
		-- vendor, recipe, conversion, or soulbound-fallback candidates.
		local valuation = derivedMaterialData:GetValue(itemID, self)
		local result = Consider(nil, valuation and valuation.value, "derived", valuation)
		self.visitingItems[itemID] = nil
		self.itemCache[itemID] = result or false
		return result
	end

	-- A known unlimited NPC supply is dependable and authoritative. Auction
	-- listings do not guarantee the same availability and must not undercut it.
	local best = Consider(nil, addon.db.global.vendorBuyPrices[itemID], "vendor")
	if not best then
		local marketValue, marketSource = GetMaterialMarketValue(self.auctionDB, itemID)
		best = Consider(best, marketValue, "market", marketSource)

		-- Conversion prices deliberately use the source material's current market
		-- value, keeping conversion and crafting as independent minimum candidates.
		local conversions = convertData:GetConversions(itemID)
		if conversions then
			local conversionTotal = 0
			local conversionCount = 0
			local conversionDetail
			for sourceItemID, quantity in pairs(conversions) do
				local sourceValue, sourceField = GetMaterialMarketValue(self.auctionDB, sourceItemID)
				if sourceValue then
					local pathValue = addon:RoundMoney(sourceValue * quantity)
					conversionTotal = conversionTotal + pathValue
					conversionCount = conversionCount + 1
					conversionDetail = {
						itemID = sourceItemID,
						quantity = quantity,
						priceSource = sourceField,
					}
				end
			end
			if conversionCount > 0 then
				-- Average interchangeable conversion paths first, then compare that
				-- stable candidate with the broader material-acquisition methods.
				best = Consider(best, conversionTotal / conversionCount, "convert",
					conversionCount == 1 and conversionDetail or nil)
			end
		end

		local outputRecipes = self.recipesByOutput[itemID] or {}
		local hasFreshRecipe = HasFreshRecipe(outputRecipes)
		for index = 1, #outputRecipes do
			local entry = outputRecipes[index]
			if not hasFreshRecipe or not entry.stale then
				local recipe = self:GetRecipeCost(entry)
				best = Consider(best, recipe and recipe.value, "crafting", recipe)
			end
		end
	end
	-- A vendor-sell estimate is deliberately limited to soulbound reagents and
	-- is used only after every real acquisition or opportunity cost has failed.
	-- A tradeable material stays unknown only when its market, vendor, conversion,
	-- and recursively known crafting paths are all unavailable.
	if not best then
		best = Consider(best, GetSoulboundFallback(itemID), "soulboundFallback")
	end
	self.visitingItems[itemID] = nil
	self.itemCache[itemID] = best or false
	return best
end

function Calculator:GetRecipe(spellID)
	local entries = self.recipesBySpell[spellID] or {}
	local hasFreshRecipe = HasFreshRecipe(entries)
	local best
	for index = 1, #entries do
		local entry = entries[index]
		if not hasFreshRecipe or not entry.stale then
			local result = self:GetRecipeCost(entry)
			if result and IsBetterResult(result, best) then
				best = result
			end
		end
	end
	return best
end

function Calculator:GetRecipesForItem(itemID)
	local results = {}
	local outputRecipes = self.recipesByOutput[itemID] or {}
	local hasFreshRecipe = HasFreshRecipe(outputRecipes)
	for index = 1, #outputRecipes do
		local entry = outputRecipes[index]
		if not hasFreshRecipe or not entry.stale then
			local result = self:GetRecipeCost(entry)
			if result then
				results[#results + 1] = result
			end
		end
	end
	return results
end

local function Calculate(auctionDB, currentCharacterOnly, outputItemID, allowAlchemySpecialization)
	local recipesBySpell, recipesByOutput = BuildRecipeIndex(currentCharacterOnly, outputItemID)
	return setmetatable({
		auctionDB = auctionDB,
		allowAlchemySpecialization = allowAlchemySpecialization,
		itemCache = {},
		recipeCache = {},
		recipesByOutput = recipesByOutput,
		recipesBySpell = recipesBySpell,
		visitingItems = {},
		visitingRecipes = {},
	}, Calculator)
end

function module:GetCharacterName()
	return addon:GetCharacterKey()
end

function module:IsItemKnown(itemID, currentCharacterOnly)
	local _, recipesByOutput = BuildRecipeIndex(currentCharacterOnly, itemID)
	return recipesByOutput[itemID] ~= nil
end

function module:IsRecipeKnown(spellID, currentCharacterOnly)
	local recipesBySpell = BuildRecipeIndex(currentCharacterOnly)
	return recipesBySpell[spellID] ~= nil
end

function module:GetKnownRecipeSpellID(name)
	if not name then
		return
	end
	local characterKey = addon:GetCharacterKey()
	if not characterKey then
		return
	end
	for _, profession in pairs(GetProfessionStore()[characterKey]) do
		for recipeKey, recipe in pairs(profession.recipes or {}) do
			if recipe.name == name then
				return recipe.spellID or type(recipeKey) == "number" and recipeKey or nil
			end
		end
	end
end

function module:GetItemCrafting(itemID, auctionDB, currentCharacterOnly, allowAlchemySpecialization)
	local calculator = Calculate(auctionDB, currentCharacterOnly, itemID, allowAlchemySpecialization)
	local best
	for _, result in ipairs(calculator:GetRecipesForItem(itemID)) do
		if not best or result.value and (not best.value or result.value < best.value
			or result.value == best.value
			and result.expectedOutputMultiplier > best.expectedOutputMultiplier) then
			best = result
		end
	end
	if best and best.outputItemID ~= itemID then
		local result = {}
		for key, value in pairs(best) do
			result[key] = value
		end
		result.outputItemID = itemID
		return result
	end
	return best
end

function module:GetRecipeCrafting(spellID, auctionDB, currentCharacterOnly, allowAlchemySpecialization)
	return Calculate(auctionDB, currentCharacterOnly, nil, allowAlchemySpecialization):GetRecipe(spellID)
end

function module:GetMaterialCost(itemID, auctionDB, currentCharacterOnly, allowAlchemySpecialization)
	return Calculate(auctionDB, currentCharacterOnly, nil, allowAlchemySpecialization):GetItemCost(itemID)
end