-- Collects known recipes from the legacy Craft and TradeSkill profession APIs.

local C_Item = C_Item
local C_Spell = C_Spell
local C_Timer = C_Timer
local CollapseCraftSkillLine = CollapseCraftSkillLine
local CollapseSkillHeader = CollapseSkillHeader
local CollapseTradeSkillSubClass = CollapseTradeSkillSubClass
local ExpandCraftSkillLine = ExpandCraftSkillLine
local ExpandSkillHeader = ExpandSkillHeader
local ExpandTradeSkillSubClass = ExpandTradeSkillSubClass
local GetCraftDisplaySkillLine = GetCraftDisplaySkillLine
local GetCraftInfo = GetCraftInfo
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
local GetSkillLineInfo = GetSkillLineInfo
local GetTime = GetTime
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
local next = next
local select = select
local tonumber = tonumber
local UNKNOWN = UNKNOWN

local ALCHEMY_SKILL_LINE = 171
local MINING_SPELL_ID = 2575
local SMELTING_SPELL_ID = 2656

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local module = addon:GetModule("ProfessionScanner")
local enchantingCraftData = addon:GetModule("EnchantingCraftData")
-- Wrath and Mists map direct enchant spells to auctionable scroll items.
local enchantingScrollData = addon:GetModule("EnchantingScrollData", true)

local craftScanPending = false
local scanningCraft = false
local scanningTradeSkill = false
local tradeSkillScanPending = false
local ignoreCraftUpdatesUntil = 0
local ignoreTradeSkillUpdatesUntil = 0

local function GetSpellName(spellID)
	local info = C_Spell.GetSpellInfo(spellID)
	return info and info.name
end

local MINING_NAME = GetSpellName(MINING_SPELL_ID)
local SMELTING_NAME = GetSpellName(SMELTING_SPELL_ID)

local function GetSpellID(link)
	local spellID = link and (match(link, "enchant:(%d+)") or match(link, "spell:(%d+)"))
	return spellID and tonumber(spellID)
end

local function GetCraftOutputItemID(name, outputLink, spellID)
	local itemID = enchantingCraftData:GetCraftedItem(spellID)
	if itemID then
		return itemID
	end
	itemID = addon:GetItemID(outputLink)
	if itemID then
		return itemID
	end
	-- Classic Enchanting returns enchant links for item-producing oils, wands,
	-- and rods. A same-named item resolves those while direct enchants remain nil.
	return C_Item.GetItemInfoInstant(name)
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
	if name == SMELTING_NAME and MINING_NAME and skillLines[MINING_NAME] then
		return MINING_NAME
	end
end

local function GetProfessionIdentity(name)
	local primary1, primary2 = GetProfessions()
	local count = select("#", GetProfessions())
	for slot = 1, count do
		local professionIndex = select(slot, GetProfessions())
		if professionIndex then
			local professionName, _, _, _, _, _, skillLineID =
				GetProfessionInfo(professionIndex)
			if professionName == name or name == SMELTING_NAME and professionName == MINING_NAME then
				return skillLineID, professionIndex == primary1 or professionIndex == primary2
			end
		end
	end
end

local function ReconcileProfessions()
	local skillLines = ReadSkillLines()
	if not skillLines then
		return
	end
	module:RemoveProfessions(function(_, profession)
		return (not profession.collector or profession.collector == "classic")
			and profession.skillLineName and not skillLines[profession.skillLineName]
	end)
end

local function ReadReagents(index, isCraft)
	local reagents = {}
	local count = isCraft and GetCraftNumReagents(index) or GetTradeSkillNumReagents(index)
	if count == nil then
		return nil, false
	end
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
		if not itemID or not quantity or quantity <= 0 then
			return nil, false
		end
		reagents[itemID] = (reagents[itemID] or 0) + quantity
	end
	return reagents, true
end

local function ReadRecipe(index, name, isCraft, altVerb, isAlchemy)
	local recipeLink = isCraft and GetCraftRecipeLink(index) or GetTradeSkillRecipeLink(index)
	local outputLink = isCraft and GetCraftItemLink(index) or GetTradeSkillItemLink(index)
	local spellID = GetSpellID(recipeLink) or GetSpellID(outputLink)
	local isEnchant = match(outputLink or recipeLink or "", "enchant:") ~= nil
	local outputItemID = isCraft and GetCraftOutputItemID(name, outputLink, spellID)
		or addon:GetItemID(outputLink)
	if isEnchant and enchantingScrollData and spellID and not outputItemID then
		outputItemID = enchantingScrollData:GetEnchant(spellID)
	end
	local alchemyCategory, expansionID
	if isAlchemy then
		local ready
		alchemyCategory, expansionID, ready = module:GetAlchemyRecipeData(
			outputItemID, altVerb ~= nil and altVerb ~= "")
		if not ready then
			return nil, nil, false
		end
	end
	local minMade, maxMade
	if isCraft then
		minMade, maxMade = 1, 1
	else
		minMade, maxMade = GetTradeSkillNumMade(index)
	end
	minMade = minMade and minMade > 0 and minMade or 1
	maxMade = maxMade and maxMade > 0 and maxMade or minMade
	local reagents, complete = ReadReagents(index, isCraft)
	if not complete then
		return nil, nil, false
	end
	local recipeKey = spellID or "recipe:" .. name
	return recipeKey, {
		name = name,
		spellID = spellID,
		outputItemID = outputItemID,
		isEnchant = isEnchant,
		alchemyCategory = alchemyCategory,
		expansionID = expansionID,
		minMade = minMade,
		maxMade = maxMade,
		reagents = reagents,
	}, true
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
		return false
	end
	local skillLineID, isPrimary = GetProfessionIdentity(name)
	local skillLines = ReadSkillLines()
	local skillLineName = skillLines and ResolveSkillLineName(name, skillLines)
	return module:SaveProfession(skillLineID or name, {
		collector = "classic",
		name = name,
		skillLineID = skillLineID,
		skillLineName = skillLineName,
		isPrimary = isPrimary,
		alchemyMastery = skillLineID == ALCHEMY_SKILL_LINE
			and module:GetActiveAlchemyMastery() or nil,
		currentLevel = currentLevel,
		maxLevel = maxLevel,
		recipes = recipes,
	})
end

local function RestoreTradeSkillHeaders(collapsedHeaders)
	for index = GetNumTradeSkills(), 1, -1 do
		local headerName, headerType = GetTradeSkillInfo(index)
		if headerType == "header" and collapsedHeaders[headerName] then
			CollapseTradeSkillSubClass(index)
		end
	end
end

local function ScanTradeSkill()
	if scanningTradeSkill or IsLinkedProfession() then
		return true
	end
	local name, currentLevel, maxLevel = GetTradeSkillLine()
	if not name or name == UNKNOWN or not maxLevel or maxLevel == 0 then
		return false
	end
	scanningTradeSkill = true
	local skillLineID = GetProfessionIdentity(name)
	local isAlchemy = skillLineID == ALCHEMY_SKILL_LINE
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
	local complete = true
	local recipeCount = 0
	for index = 1, GetNumTradeSkills() do
		local recipeName, recipeType, _, _, altVerb = GetTradeSkillInfo(index)
		if recipeName and recipeType ~= "header" and recipeType ~= "subheader" then
			local recipeKey, recipe, recipeComplete = ReadRecipe(
				index, recipeName, false, altVerb, isAlchemy)
			if not recipeComplete then
				complete = false
				break
			end
			recipes[recipeKey] = recipe
			recipeCount = recipeCount + 1
		end
	end
	complete = complete and recipeCount > 0
	if complete then
		SaveProfession(name, currentLevel, maxLevel, recipes)
	end
	RestoreTradeSkillHeaders(collapsedHeaders)
	ignoreTradeSkillUpdatesUntil = GetTime() + 0.25
	scanningTradeSkill = false
	return complete
end

local function RestoreCraftHeaders(collapsedHeaders)
	for index = GetNumCrafts(), 1, -1 do
		local headerName, _, headerType = GetCraftInfo(index)
		if headerType == "header" and collapsedHeaders[headerName] then
			CollapseCraftSkillLine(index)
		end
	end
end

local function ScanCraft()
	if scanningCraft then
		return true
	end
	local name = GetCraftDisplaySkillLine()
	if not name then
		return true
	end
	scanningCraft = true
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
	local complete = true
	local recipeCount = 0
	for index = 1, GetNumCrafts() do
		local recipeName, _, recipeType = GetCraftInfo(index)
		if recipeName and recipeType ~= "header" and recipeType ~= "subheader" then
			local recipeKey, recipe, recipeComplete = ReadRecipe(index, recipeName, true)
			if not recipeComplete then
				complete = false
				break
			end
			recipes[recipeKey] = recipe
			recipeCount = recipeCount + 1
		end
	end
	complete = complete and recipeCount > 0
	if complete then
		SaveProfession(name, nil, nil, recipes)
	end
	RestoreCraftHeaders(collapsedHeaders)
	ignoreCraftUpdatesUntil = GetTime() + 0.25
	scanningCraft = false
	return complete
end

local QueueTradeSkillScan, QueueCraftScan

-- A zero-second timer defers scanning until the next frame, after Blizzard
-- finishes the current profession event. Bounded retries wait for missing data.
QueueTradeSkillScan = function(delay, attempt)
	if tradeSkillScanPending then
		return
	end
	tradeSkillScanPending = true
	C_Timer.After(delay or 0, function()
		tradeSkillScanPending = false
		attempt = attempt or 1
		if not ScanTradeSkill() and attempt < 6 then
			QueueTradeSkillScan(0.2, attempt + 1)
		end
	end)
end

QueueCraftScan = function(delay, attempt)
	if craftScanPending then
		return
	end
	craftScanPending = true
	C_Timer.After(delay or 0, function()
		craftScanPending = false
		attempt = attempt or 1
		if not ScanCraft() and attempt < 6 then
			QueueCraftScan(0.2, attempt + 1)
		end
	end)
end

function module:GetCraftRecipeSpellID(index)
	local spellID = GetSpellID(GetCraftRecipeLink(index))
	if spellID then
		return spellID
	end
	return self:GetKnownRecipeSpellID(GetCraftInfo(index))
end

function module:GetTradeSkillRecipeSpellID(index)
	local spellID = GetSpellID(GetTradeSkillRecipeLink(index))
	if spellID then
		return spellID
	end
	return self:GetKnownRecipeSpellID(GetTradeSkillInfo(index))
end

function module:TRADE_SKILL_SHOW()
	QueueTradeSkillScan()
end

function module:TRADE_SKILL_UPDATE()
	if not scanningTradeSkill and GetTime() >= ignoreTradeSkillUpdatesUntil then
		QueueTradeSkillScan(0.05)
	end
end

function module:CRAFT_SHOW()
	QueueCraftScan()
end

function module:CRAFT_UPDATE()
	if not scanningCraft and GetTime() >= ignoreCraftUpdatesUntil then
		QueueCraftScan(0.05)
	end
end

function module:SKILL_LINES_CHANGED()
	-- Let Blizzard finish updating skill lines before pruning saved professions.
	C_Timer.After(0, ReconcileProfessions)
end

function module:OnEnable()
	self:RegisterEvent("TRADE_SKILL_SHOW")
	self:RegisterEvent("TRADE_SKILL_UPDATE")
	self:RegisterEvent("CRAFT_SHOW")
	self:RegisterEvent("CRAFT_UPDATE")
	self:RegisterEvent("SKILL_LINES_CHANGED")
	-- Defer login reconciliation until Blizzard's skill-line data has settled.
	C_Timer.After(0, ReconcileProfessions)
end