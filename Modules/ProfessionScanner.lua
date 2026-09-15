local C_Item = C_Item
local C_Timer = C_Timer
local CollapseCraftSkillLine = CollapseCraftSkillLine
local CollapseSkillHeader = CollapseSkillHeader
local CollapseTradeSkillSubClass = CollapseTradeSkillSubClass
local ExpandCraftSkillLine = ExpandCraftSkillLine
local ExpandSkillHeader = ExpandSkillHeader
local ExpandTradeSkillSubClass = ExpandTradeSkillSubClass
local GetBuildInfo = GetBuildInfo
local GetCraftInfo = GetCraftInfo
local GetCraftDisplaySkillLine = GetCraftDisplaySkillLine
local GetCraftItemLink = GetCraftItemLink
local GetCraftNumReagents = GetCraftNumReagents
local GetCraftReagentInfo = GetCraftReagentInfo
local GetCraftReagentItemLink = GetCraftReagentItemLink
local GetCraftRecipeLink = GetCraftRecipeLink
local GetNumCrafts = GetNumCrafts
local GetNumSkillLines = GetNumSkillLines
local GetNumTradeSkills = GetNumTradeSkills
local GetProfessionInfo = GetProfessionInfo
local GetProfessions = GetProfessions
local GetServerTime = GetServerTime
local GetSkillLineInfo = GetSkillLineInfo
local GetTradeSkillInfo = GetTradeSkillInfo
local GetTradeSkillItemLink = GetTradeSkillItemLink
local GetTradeSkillLine = GetTradeSkillLine
local GetTradeSkillNumMade = GetTradeSkillNumMade
local GetTradeSkillNumReagents = GetTradeSkillNumReagents
local GetTradeSkillReagentInfo = GetTradeSkillReagentInfo
local GetTradeSkillReagentItemLink = GetTradeSkillReagentItemLink
local GetTradeSkillRecipeLink = GetTradeSkillRecipeLink
local IsTradeSkillLinked = IsTradeSkillLinked
local LibStub = LibStub
local match = string.match
local MINING = MINING
local next = next
local pairs = pairs
local select = select
local SMELTING = SMELTING
local sort = table.sort
local time = time
local tonumber = tonumber
local type = type
local UNKNOWN = UNKNOWN
local WOW_PROJECT_ID = WOW_PROJECT_ID
local WOW_PROJECT_WRATH_CLASSIC = WOW_PROJECT_WRATH_CLASSIC

local ALCHEMY_SKILL_LINE = 171
local ALCHEMY_MASTERY_BONUS = 1.2
local CONSUMABLE_CLASS = 0
local ELIXIR_SUBCLASS = 2
local ELIXIR_MASTERY = 2
local FLASK_SUBCLASS = 3
local POTION_SUBCLASS = 1
local POTION_MASTERY = 3
local TRANSMUTATION_MASTERY = 4

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local module = addon:NewModule("ProfessionScanner", "AceEvent-3.0")
local convertData = addon:GetModule("ConvertData")
-- The spell-to-scroll and vellum mapping is loaded only by Wrath-based clients.
local enchantingData = addon:GetModule("EnchantingData", true)

local currentBuild = select(2, GetBuildInfo())
local isWrath = WOW_PROJECT_ID == WOW_PROJECT_WRATH_CLASSIC
local recipeRevision = 0
local recipeIndexes = {}

local function GetPlayerFullName()
	local _, _, fullName = addon:GetPlayerIdentity()
	return fullName
end

local function GetSpellID(link)
	local spellID = link and (match(link, "enchant:(%d+)") or match(link, "spell:(%d+)"))
	return spellID and tonumber(spellID)
end

local function GetCraftOutputItemID(name, outputLink)
	local itemID = addon:GetItemID(outputLink)
	if itemID then
		return itemID
	end

	-- Classic's Enchanting window returns an enchant link for every recipe,
	-- including oils, wands, and rods which really do create an item. Blizzard's
	-- item lookup distinguishes those recipes by resolving their localized craft
	-- name; ordinary equipment enchants have no same-named item and remain nil.
	return C_Item.GetItemInfoInstant(name)
end

local function GetTimestamp()
	return GetServerTime and GetServerTime() or time()
end

local function ReadSkillLines()
	local count = GetNumSkillLines()
	if not count or count <= 0 then
		return
	end
	local collapsedHeaders = {}
	for index = 1, count do
		local skillName, isHeader, isExpanded = GetSkillLineInfo(index)
		if skillName and isHeader and not isExpanded then
			collapsedHeaders[skillName] = true
		end
	end
	if next(collapsedHeaders) then
		ExpandSkillHeader(0)
		count = GetNumSkillLines()
	end
	local skillLines = {}
	for index = 1, count do
		local skillName, isHeader = GetSkillLineInfo(index)
		if skillName and not isHeader then
			skillLines[skillName] = true
		end
	end
	if next(collapsedHeaders) then
		for index = GetNumSkillLines(), 1, -1 do
			local skillName, isHeader = GetSkillLineInfo(index)
			if isHeader and collapsedHeaders[skillName] then
				CollapseSkillHeader(index)
			end
		end
	end
	return next(skillLines) and skillLines or nil
end

local function ResolveSkillLineName(name, skillLines)
	if skillLines[name] then
		return name
	end
	-- Blizzard presents Mining's recipe window as Smelting. Using localized
	-- globals connects the two names without embedding English text.
	if name == SMELTING and MINING and skillLines[MINING] then
		return MINING
	end
end

local function GetProfessionIdentity(name)
	local primary1, primary2, archaeology, fishing, cooking = GetProfessions()
	local professions = { primary1, primary2, archaeology, fishing, cooking }
	for _, professionIndex in pairs(professions) do
		if professionIndex then
			local professionName, _, _, _, _, _, skillLineID, _, specializationIndex =
				GetProfessionInfo(professionIndex)
			if professionName == name or name == SMELTING and professionName == MINING then
				return skillLineID, professionIndex == primary1 or professionIndex == primary2,
					specializationIndex
			end
		end
	end
end

local function ReconcileProfessions()
	local playerFullName = GetPlayerFullName()
	if not playerFullName then
		return
	end
	local skillLines = ReadSkillLines()
	if not skillLines then
		-- An empty skill list during login or a UI transition is not proof that the
		-- character forgot every profession. Preserve data and try again later.
		return
	end

	local professions = addon.db.factionrealm.knownProfessions[playerFullName]
	local changed
	for professionKey, profession in pairs(professions) do
		-- skillLineName is set only when Blizzard's complete skill list verified the
		-- profession. Unverifiable Craft-frame categories are retained rather than
		-- deleted on circumstantial evidence.
		if profession.skillLineName and not skillLines[profession.skillLineName] then
			professions[professionKey] = nil
			changed = true
		end
	end
	if changed then
		recipeRevision = recipeRevision + 1
	end
end

local function ReadReagents(index, isCraft)
	local reagents = {}
	local count = isCraft and GetCraftNumReagents(index) or GetTradeSkillNumReagents(index)
	for reagentIndex = 1, count do
		local link = isCraft and GetCraftReagentItemLink(index, reagentIndex)
			or GetTradeSkillReagentItemLink(index, reagentIndex)
		local itemID = addon:GetItemID(link)
		local quantity
		if isCraft then
			_, _, quantity = GetCraftReagentInfo(index, reagentIndex)
		else
			_, _, quantity = GetTradeSkillReagentInfo(index, reagentIndex)
		end
		if itemID and quantity and quantity > 0 then
			reagents[itemID] = (reagents[itemID] or 0) + quantity
		end
	end
	return reagents
end

local function GetAlchemyMastery(outputItemID, altVerb)
	-- Alchemy transmutes use an alternate action verb while ordinary recipes use
	-- Create. Numeric item classes avoid relying on localized Potion/Elixir names;
	-- Classic's Enum.ItemConsumableSubclass values are known to be unreliable.
	if altVerb then
		return "transmutation"
	end
	if not outputItemID then
		return
	end
	local _, _, _, _, _, _, _, _, _, _, _, classID, subclassID =
		C_Item.GetItemInfo(outputItemID)
	if classID ~= CONSUMABLE_CLASS then
		return
	end
	if subclassID == POTION_SUBCLASS then
		return "potion"
	elseif subclassID == ELIXIR_SUBCLASS or subclassID == FLASK_SUBCLASS then
		return "elixir"
	end
end

local function GetMasteryYield(entry)
	if entry.skillLineID ~= ALCHEMY_SKILL_LINE then
		return 1
	end
	local mastery = entry.recipe.alchemyMastery
	local specialization = entry.specializationIndex
	if mastery == "potion" and specialization == POTION_MASTERY
		or mastery == "elixir" and specialization == ELIXIR_MASTERY
		or mastery == "transmutation" and specialization == TRANSMUTATION_MASTERY then
		return ALCHEMY_MASTERY_BONUS
	end
	return 1
end

local function ReadRecipe(index, name, isCraft, altVerb)
	local recipeLink = isCraft and GetCraftRecipeLink(index) or GetTradeSkillRecipeLink(index)
	local outputLink = isCraft and GetCraftItemLink(index) or GetTradeSkillItemLink(index)
	local spellID = GetSpellID(recipeLink) or GetSpellID(outputLink)
	local outputItemID = isCraft and GetCraftOutputItemID(name, outputLink) or addon:GetItemID(outputLink)
	if isWrath and enchantingData and spellID and not outputItemID then
		outputItemID = enchantingData:GetEnchant(spellID)
	end
	local minMade, maxMade
	if isCraft then
		-- Classic's separate Craft frame is used for direct enchants. Those recipes
		-- have a conceptual output of one enchant even though no item is created.
		minMade, maxMade = 1, 1
	else
		minMade, maxMade = GetTradeSkillNumMade(index)
	end
	minMade = minMade and minMade > 0 and minMade or 1
	maxMade = maxMade and maxMade > 0 and maxMade or minMade

	-- Some Classic Era profession views return no recipe hyperlink even though
	-- their result and reagents are available. The output index only needs a
	-- stable key within this snapshot; spell tooltips remain indexed only when
	-- Blizzard supplies the real spell ID.
	local recipeKey = spellID or "recipe:" .. name
	return recipeKey, {
		name = name,
		spellID = spellID,
		outputItemID = outputItemID,
		alchemyMastery = GetAlchemyMastery(outputItemID, altVerb),
		minMade = minMade,
		maxMade = maxMade,
		reagents = ReadReagents(index, isCraft),
	}
end

local function IsLinkedProfession()
	if not IsTradeSkillLinked then
		return false
	end
	local linked, owner = IsTradeSkillLinked()
	return linked or owner and owner ~= ""
end

local function SaveProfession(name, currentLevel, maxLevel, recipes)
	if not name or name == "" or name == UNKNOWN then
		return
	end
	local playerFullName = GetPlayerFullName()
	if not playerFullName then
		return
	end
	local skillLineID, isPrimary, specializationIndex = GetProfessionIdentity(name)
	local skillLines = ReadSkillLines()
	local skillLineName = skillLines and ResolveSkillLineName(name, skillLines)
	local character = addon.db.factionrealm.knownProfessions[playerFullName]
	-- GetProfessions omits some Classic Craft-frame categories, including First
	-- Aid. Their localized names remain safe fallback keys; verified skillLineName
	-- values still allow reconciliation to remove them if Blizzard does.
	local professionKey = skillLineID or name
	character[professionKey] = {
		name = name,
		skillLineID = skillLineID,
		skillLineName = skillLineName,
		isPrimary = isPrimary,
		specializationIndex = specializationIndex,
		build = currentBuild,
		currentLevel = currentLevel,
		maxLevel = maxLevel,
		lastScan = GetTimestamp(),
		recipes = recipes,
	}
	recipeRevision = recipeRevision + 1
end

local function ScanTradeSkill()
	if IsLinkedProfession() then
		return
	end
	local name, currentLevel, maxLevel = GetTradeSkillLine()
	if not name or name == UNKNOWN or not maxLevel or maxLevel == 0 then
		return
	end
	local collapsedHeaders = {}
	for index = 1, GetNumTradeSkills() do
		local headerName, headerType, _, isExpanded = GetTradeSkillInfo(index)
		if headerType == "header" and not isExpanded then
			collapsedHeaders[headerName] = true
		end
	end
	if next(collapsedHeaders) then
		ExpandTradeSkillSubClass(0)
	end

	local recipes = {}
	for index = 1, GetNumTradeSkills() do
		local recipeName, recipeType, _, _, altVerb = GetTradeSkillInfo(index)
		if recipeName and recipeType ~= "header" and recipeType ~= "subheader" then
			local recipeKey, recipe = ReadRecipe(index, recipeName, false, altVerb)
			if recipeKey then
				recipes[recipeKey] = recipe
			end
		end
	end
	SaveProfession(name, currentLevel, maxLevel, recipes)
	if next(collapsedHeaders) then
		for index = GetNumTradeSkills(), 1, -1 do
			local headerName, headerType = GetTradeSkillInfo(index)
			if headerType == "header" and collapsedHeaders[headerName] then
				CollapseTradeSkillSubClass(index)
			end
		end
	end
end

local function ScanCraft()
	-- GetCraftDisplaySkillLine is nil for the hunter pet-training window, which
	-- also uses CraftFrame. This keeps that unrelated spell list out of professions.
	local name = GetCraftDisplaySkillLine()
	if not name then
		return
	end
	local collapsedHeaders = {}
	for index = 1, GetNumCrafts() do
		local headerName, _, headerType, _, isExpanded = GetCraftInfo(index)
		if headerType == "header" and not isExpanded then
			collapsedHeaders[headerName] = true
		end
	end
	if next(collapsedHeaders) then
		ExpandCraftSkillLine(0)
	end
	local recipes = {}
	for index = 1, GetNumCrafts() do
		local recipeName, _, recipeType = GetCraftInfo(index)
		if recipeName and recipeType ~= "header" and recipeType ~= "subheader" then
			local recipeKey, recipe = ReadRecipe(index, recipeName, true)
			if recipeKey then
				recipes[recipeKey] = recipe
			end
		end
	end
	SaveProfession(name, nil, nil, recipes)
	if next(collapsedHeaders) then
		for index = GetNumCrafts(), 1, -1 do
			local headerName, _, headerType = GetCraftInfo(index)
			if headerType == "header" and collapsedHeaders[headerName] then
				CollapseCraftSkillLine(index)
			end
		end
	end
end

local function ResolveKnownCraftOutput(itemID, currentCharacterOnly)
	local itemName = C_Item.GetItemInfo(itemID)
	if not itemName then
		return
	end
	local playerFullName = GetPlayerFullName()
	local resolved
	for characterName, professions in pairs(addon.db.factionrealm.knownProfessions) do
		if not currentCharacterOnly or characterName == playerFullName then
			for _, profession in pairs(professions) do
				for _, recipe in pairs(profession.recipes or {}) do
					if not recipe.outputItemID and recipe.name == itemName then
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

local function BuildRecipeIndex(currentCharacterOnly, outputItemID)
	local playerFullName = GetPlayerFullName()
	local cacheKey = currentCharacterOnly and "character" or "factionrealm"
	local cached = recipeIndexes[cacheKey]
	if outputItemID and (not cached or not cached.recipesByOutput[outputItemID]) then
		-- The hovered item is necessarily cached, so it can resolve an Enchanting
		-- craft which was not in the item cache when its profession was scanned.
		ResolveKnownCraftOutput(outputItemID, currentCharacterOnly)
		cached = recipeIndexes[cacheKey]
	end
	if cached and cached.revision == recipeRevision then
		return cached.recipesBySpell, cached.recipesByOutput
	end
	local recipesBySpell = {}
	local recipesByOutput = {}
	for characterName, professions in pairs(addon.db.factionrealm.knownProfessions) do
		if not currentCharacterOnly or characterName == playerFullName then
			for _, profession in pairs(professions) do
				for recipeKey, recipe in pairs(profession.recipes or {}) do
					local spellID = recipe.spellID
					if spellID == nil and type(recipeKey) == "number" then
						spellID = recipeKey
					end
					local entry = {
						character = characterName,
						profession = profession.name,
						skillLineID = profession.skillLineID,
						specializationIndex = profession.specializationIndex,
						stale = profession.build ~= currentBuild,
						spellID = spellID,
						recipe = recipe,
					}
					-- A current-build scan is authoritative for a specific spell. The
					-- older snapshot remains available only when no fresh copy exists.
					local indexed = spellID and recipesBySpell[spellID]
					if spellID and (not indexed or indexed.stale and not entry.stale) then
						recipesBySpell[spellID] = entry
					end
					if recipe.outputItemID then
						local outputs = recipesByOutput[recipe.outputItemID]
						if not outputs then
							outputs = {}
							recipesByOutput[recipe.outputItemID] = outputs
						end
						outputs[#outputs + 1] = entry
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

local function Calculate(auctionDB, currentCharacterOnly, outputItemID)
	local recipesBySpell, recipesByOutput = BuildRecipeIndex(currentCharacterOnly, outputItemID)
	local itemCache = {}
	local recipeCache = {}
	local visitingItems = {}
	local visitingRecipes = {}
	local GetItemCost, GetRecipeCost
	-- Multiple recipes can create the same item. Once any current-build recipe is
	-- known, older-build alternatives no longer participate in the minimum cost.
	local function HasFreshRecipe(entries)
		for index = 1, #entries do
			if not entries[index].stale then
				return true
			end
		end
		return false
	end

	local function Consider(best, value, source, detail)
		if value and value > 0 and (not best or value < best.value) then
			return { value = value, source = source, detail = detail }
		end
		return best
	end

	function GetRecipeCost(entry)
		local cached = recipeCache[entry]
		if cached ~= nil then
			return cached or nil
		end
		if visitingRecipes[entry] then
			return
		end
		visitingRecipes[entry] = true
		local total = 0
		local materials = {}
		for itemID, quantity in pairs(entry.recipe.reagents) do
			local material = GetItemCost(itemID)
			if not material then
				visitingRecipes[entry] = nil
				recipeCache[entry] = false
				return
			end
			local subtotal = material.value * quantity
			total = total + subtotal
			materials[#materials + 1] = {
				itemID = itemID,
				quantity = quantity,
				unitValue = material.value,
				totalValue = subtotal,
				source = material.source,
				detail = material.detail,
			}
		end
		local vellumItemIDs
		if isWrath and enchantingData then
			vellumItemIDs = select(2, enchantingData:GetEnchant(entry.spellID))
		end
		if vellumItemIDs then
			local cheapest
			local cheapestItemID
			for index = 1, #vellumItemIDs do
				local itemID = vellumItemIDs[index]
				local material = GetItemCost(itemID)
				if material and (not cheapest or material.value < cheapest.value) then
					cheapest = material
					cheapestItemID = itemID
				end
			end
			if not cheapest then
				visitingRecipes[entry] = nil
				recipeCache[entry] = false
				return
			end
			total = total + cheapest.value
			materials[#materials + 1] = {
				itemID = cheapestItemID,
				quantity = 1,
				unitValue = cheapest.value,
				totalValue = cheapest.value,
				source = cheapest.source,
				detail = cheapest.detail,
			}
		end
		sort(materials, function(left, right)
			return left.itemID < right.itemID
		end)
		visitingRecipes[entry] = nil
		local outputQuantity = (entry.recipe.minMade + entry.recipe.maxMade) / 2
		local result = {
			value = total / outputQuantity,
			totalReagentValue = total,
			outputQuantity = outputQuantity,
			character = entry.character,
			profession = entry.profession,
			skillLineID = entry.skillLineID,
			specializationIndex = entry.specializationIndex,
			alchemyMastery = entry.recipe.alchemyMastery,
			masteryYield = GetMasteryYield(entry),
			stale = entry.stale,
			spellID = entry.spellID,
			outputItemID = entry.recipe.outputItemID,
			name = entry.recipe.name,
			materials = materials,
		}
		recipeCache[entry] = result
		return result
	end

	function GetItemCost(itemID)
		local cached = itemCache[itemID]
		if cached ~= nil then
			return cached or nil
		end
		if visitingItems[itemID] then
			return
		end
		visitingItems[itemID] = true
		local best
		local marketValue, marketSource = addon:GetFirstMarketValue(auctionDB and auctionDB[itemID])
		best = Consider(best, marketValue, "market", marketSource)
		best = Consider(best, addon.db.global.vendorBuyPrices[itemID], "vendor")

		-- Conversion prices deliberately use the source material's market value,
		-- not its vendor or crafting value. Those remain independent candidates in
		-- the outer minimum calculation and cannot feed conversion loops.
		local conversions = convertData:GetConversions(itemID)
		if conversions then
			for sourceItemID, quantity in pairs(conversions) do
				local sourceValue, sourceField = addon:GetFirstMarketValue(
					auctionDB and auctionDB[sourceItemID])
				best = Consider(best, sourceValue and sourceValue * quantity, "convert", {
					itemID = sourceItemID,
					quantity = quantity,
					priceSource = sourceField,
				})
			end
		end

		local outputRecipes = recipesByOutput[itemID] or {}
		local hasFreshRecipe = HasFreshRecipe(outputRecipes)
		for index = 1, #outputRecipes do
			local entry = outputRecipes[index]
			if not hasFreshRecipe or not entry.stale then
				local recipe = GetRecipeCost(entry)
				best = Consider(best, recipe and recipe.value, "crafting", recipe)
			end
		end
		visitingItems[itemID] = nil
		itemCache[itemID] = best or false
		return best
	end

	return {
		GetItem = function(_, itemID)
			return GetItemCost(itemID)
		end,
		GetRecipe = function(_, spellID)
			local entry = recipesBySpell[spellID]
			return entry and GetRecipeCost(entry)
		end,
		GetRecipesForItem = function(_, itemID)
			local results = {}
			local outputRecipes = recipesByOutput[itemID] or {}
			local hasFreshRecipe = HasFreshRecipe(outputRecipes)
			for index = 1, #outputRecipes do
				local entry = outputRecipes[index]
				if not hasFreshRecipe or not entry.stale then
					local result = GetRecipeCost(entry)
					if result then
						results[#results + 1] = result
					end
				end
			end
			return results
		end,
	}
end

function module:GetCharacterName()
	return GetPlayerFullName()
end

function module:IsItemKnown(itemID, currentCharacterOnly)
	local _, recipesByOutput = BuildRecipeIndex(currentCharacterOnly, itemID)
	return recipesByOutput[itemID] ~= nil
end

function module:IsRecipeKnown(spellID, currentCharacterOnly)
	local recipesBySpell = BuildRecipeIndex(currentCharacterOnly)
	return recipesBySpell[spellID] ~= nil
end

function module:GetItemCrafting(itemID, auctionDB, currentCharacterOnly)
	local calculator = Calculate(auctionDB, currentCharacterOnly, itemID)
	local best
	local recipes = calculator:GetRecipesForItem(itemID)
	for index = 1, #recipes do
		local result = recipes[index]
		if not best or result.value < best.value
			or result.value == best.value and result.masteryYield > best.masteryYield then
			best = result
		end
	end
	return best
end

function module:GetRecipeCrafting(spellID, auctionDB, currentCharacterOnly)
	return Calculate(auctionDB, currentCharacterOnly):GetRecipe(spellID)
end

function module:GetMaterialCost(itemID, auctionDB, currentCharacterOnly)
	return Calculate(auctionDB, currentCharacterOnly):GetItem(itemID)
end

function module:TRADE_SKILL_SHOW()
	C_Timer.After(0, ScanTradeSkill)
end

function module:CRAFT_SHOW()
	C_Timer.After(0, ScanCraft)
end

function module:SKILL_LINES_CHANGED()
	-- Blizzard updates the spellbook and profession slots during this event. Waiting
	-- one frame ensures the reconciliation observes their completed state.
	C_Timer.After(0, ReconcileProfessions)
end

function module:OnEnable()
	self:RegisterEvent("TRADE_SKILL_SHOW")
	self:RegisterEvent("CRAFT_SHOW")
	self:RegisterEvent("SKILL_LINES_CHANGED")
	-- AceAddon enables ordinary modules during PLAYER_LOGIN, so this performs the
	-- initial reconciliation without registering the event a second time.
	C_Timer.After(0, ReconcileProfessions)
end