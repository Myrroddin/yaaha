-- Defines disenchanting eligibility, result ranges, learned observations, and expected values.

local C_Item = C_Item
local format = string.format
local LibStub = LibStub
local max = math.max
local min = math.min
local next = next
local pairs = pairs
local sort = table.sort
local stringMatch = string.match
local tonumber = tonumber
local type = type

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local module = addon:NewModule("DisenchantingData")

local ARMOR = 4
local WEAPON = 2
local UNCOMMON = 2
local RARE = 3
local EPIC = 4
-- The client-appropriate static probabilities act as 100 virtual observations.
-- This keeps one lucky result from dominating while learned results accumulate.
local STATIC_SAMPLE_WEIGHT = 100

local data = {
	[WEAPON] = { [UNCOMMON] = {}, [RARE] = {}, [EPIC] = {} },
	[ARMOR] = { [UNCOMMON] = {}, [RARE] = {}, [EPIC] = {} },
}

local materials = {}
local nonDisenchantable = {}

-- All supported game versions have these items.
nonDisenchantable[38] = true -- Recruit's Shirt
nonDisenchantable[45] = true -- Squire's Shirt
nonDisenchantable[49] = true -- Footpad's Shirt
nonDisenchantable[53] = true -- Neophyte's Shirt
nonDisenchantable[127] = true -- Trapper's Shirt
nonDisenchantable[148] = true -- Rugged Trapper's Shirt
nonDisenchantable[154] = true -- Primitive Mantle
nonDisenchantable[2105] = true -- Thug Shirt
nonDisenchantable[2575] = true -- Red Linen Shirt
nonDisenchantable[2576] = true -- White Linen Shirt
nonDisenchantable[2577] = true -- Blue Linen Shirt
nonDisenchantable[2579] = true -- Green Linen Shirt
nonDisenchantable[2587] = true -- Gray Woolen Shirt
nonDisenchantable[3426] = true -- Bold Yellow Shirt
nonDisenchantable[3427] = true -- Stylish Black Shirt
nonDisenchantable[3428] = true -- Common Gray Shirt
nonDisenchantable[4330] = true -- Stylish Red Shirt
nonDisenchantable[4332] = true -- Bright Yellow Shirt
nonDisenchantable[4333] = true -- Dark Silk Shirt
nonDisenchantable[4334] = true -- Formal White Shirt
nonDisenchantable[4335] = true -- Rich Purple Silk Shirt
nonDisenchantable[4336] = true -- Black Swashbuckler's Shirt
nonDisenchantable[4344] = true -- Brown Linen Shirt
nonDisenchantable[5107] = true -- Deckhand's Shirt
nonDisenchantable[6096] = true -- Apprentice's Shirt
nonDisenchantable[6097] = true -- Acolyte's Shirt
nonDisenchantable[6117] = true -- Squire's Shirt
nonDisenchantable[6120] = true -- Recruit's Shirt
nonDisenchantable[6125] = true -- Brawler's Harness
nonDisenchantable[6134] = true -- Primitive Mantle
nonDisenchantable[6136] = true -- Thug Shirt
nonDisenchantable[6384] = true -- Stylish Blue Shirt
nonDisenchantable[6385] = true -- Stylish Green Shirt
nonDisenchantable[6795] = true -- White Swashbuckler's Shirt
nonDisenchantable[6796] = true -- Red Swashbuckler's Shirt
nonDisenchantable[6833] = true -- White Tuxedo Shirt
nonDisenchantable[10034] = true -- Tuxedo Shirt
nonDisenchantable[10052] = true -- Orange Martial Shirt
nonDisenchantable[10054] = true -- Lavender Mageweave Shirt
nonDisenchantable[10055] = true -- Pink Mageweave Shirt
nonDisenchantable[10056] = true -- Orange Mageweave Shirt
nonDisenchantable[11287] = true -- Lesser Magic Wand
nonDisenchantable[11288] = true -- Greater Magic Wand
nonDisenchantable[11289] = true -- Lesser Mystic Wand
nonDisenchantable[11290] = true -- Greater Mystic Wand
nonDisenchantable[13347] = true -- Crystal of Zin-Malor
nonDisenchantable[16059] = true -- Common Brown Shirt
nonDisenchantable[16060] = true -- Common White Shirt
nonDisenchantable[17723] = true -- Green Holiday Shirt
nonDisenchantable[18231] = true -- Sleeveless T-Shirt
nonDisenchantable[20406] = true -- Twilight Cultist Mantle
nonDisenchantable[20407] = true -- Twilight Cultist Robe
nonDisenchantable[20408] = true -- Twilight Cultist Cowl

-- Add items introduced in The Burning Crusade.
if addon.IsTBC or addon.IsWrath then
	nonDisenchantable[20897] = true -- Lookout's Tunic
	nonDisenchantable[20901] = true -- Warder's Shirt
	nonDisenchantable[21766] = true -- Opal Necklace of Impact
	nonDisenchantable[23345] = true -- Scout's Shirt
	nonDisenchantable[23473] = true -- Recruit's Shirt
	nonDisenchantable[23476] = true -- Squire's Shirt
	nonDisenchantable[24143] = true -- Initiate's Shirt
	nonDisenchantable[31279] = true -- Enchanted Illidari Tabard
end

-- Add items introduced in Wrath of the Lich King.
if addon.IsWrath then
	nonDisenchantable[41248] = true -- Red Lumberjack Shirt
	nonDisenchantable[41249] = true -- Blue Lumberjack Shirt
	nonDisenchantable[41250] = true -- Green Lumberjack Shirt
	nonDisenchantable[41251] = true -- Yellow Lumberjack Shirt
	nonDisenchantable[41252] = true -- Red Workman's Shirt
	nonDisenchantable[41253] = true -- Blue Workman's Shirt
	nonDisenchantable[41254] = true -- Rustic Workman's Shirt
	nonDisenchantable[41255] = true -- Green Workman's Shirt
	nonDisenchantable[42360] = true -- Ebon Filigreed Doublet
	nonDisenchantable[42361] = true -- Cerulean Filigreed Doublet
	nonDisenchantable[42363] = true -- Golden Filigreed Doublet
	nonDisenchantable[42365] = true -- Amber Filigreed Doublet
	nonDisenchantable[42368] = true -- Scarlet Filigreed Doublet
	nonDisenchantable[42369] = true -- Ebon Filigreed Shirt
	nonDisenchantable[42370] = true -- Cerulean Filigreed Shirt
	nonDisenchantable[42371] = true -- Amber Filigreed Shirt
	nonDisenchantable[42372] = true -- Scarlet Filigreed Shirt
	nonDisenchantable[42373] = true -- Golden Filigreed Shirt
	nonDisenchantable[42374] = true -- Blue Martial Shirt
	nonDisenchantable[42375] = true -- Green Martial Shirt
	nonDisenchantable[42376] = true -- Yellow Martial Shirt
	nonDisenchantable[42377] = true -- Purple Martial Shirt
	nonDisenchantable[42378] = true -- Red Martial Shirt
	nonDisenchantable[44693] = true -- Wound Dressing
	nonDisenchantable[44694] = true -- Antiseptic-Soaked Dressing
	nonDisenchantable[45664] = true -- Silvermoon Doublet
	nonDisenchantable[45666] = true -- Ironforge Doublet
	nonDisenchantable[45667] = true -- Stormwind Doublet
	nonDisenchantable[45668] = true -- Exodar Doublet
	nonDisenchantable[45669] = true -- Sen'jin Doublet
	nonDisenchantable[45670] = true -- Darnassus Doublet
	nonDisenchantable[45671] = true -- Gnomeregan Doublet
	nonDisenchantable[45672] = true -- Orgrimmar Doublet
	nonDisenchantable[45673] = true -- Thunder Bluff Doublet
	nonDisenchantable[45674] = true -- Undercity Doublet
	nonDisenchantable[48663] = true -- Tankard O' Terror
	nonDisenchantable[52252] = true -- Tabard of the Lightbringer
end

local function AddMistsNonDisenchantable()
	-- Mists is a separate baseline. These are older and contemporary items that
	-- remain present and non-disenchantable there; this function does not depend
	-- on the TBC or Wrath client guards above.
	nonDisenchantable[20897] = true -- Lookout's Tunic
	nonDisenchantable[20901] = true -- Warder's Shirt
	nonDisenchantable[21766] = true -- Opal Necklace of Impact
	nonDisenchantable[23345] = true -- Scout's Shirt
	nonDisenchantable[23473] = true -- Recruit's Shirt
	nonDisenchantable[23476] = true -- Squire's Shirt
	nonDisenchantable[24143] = true -- Initiate's Shirt
	nonDisenchantable[31279] = true -- Enchanted Illidari Tabard
	nonDisenchantable[41248] = true -- Red Lumberjack Shirt
	nonDisenchantable[41249] = true -- Blue Lumberjack Shirt
	nonDisenchantable[41250] = true -- Green Lumberjack Shirt
	nonDisenchantable[41251] = true -- Yellow Lumberjack Shirt
	nonDisenchantable[41252] = true -- Red Workman's Shirt
	nonDisenchantable[41253] = true -- Blue Workman's Shirt
	nonDisenchantable[41254] = true -- Rustic Workman's Shirt
	nonDisenchantable[41255] = true -- Green Workman's Shirt
	nonDisenchantable[42360] = true -- Ebon Filigreed Doublet
	nonDisenchantable[42361] = true -- Cerulean Filigreed Doublet
	nonDisenchantable[42363] = true -- Golden Filigreed Doublet
	nonDisenchantable[42365] = true -- Amber Filigreed Doublet
	nonDisenchantable[42368] = true -- Scarlet Filigreed Doublet
	nonDisenchantable[42369] = true -- Ebon Filigreed Shirt
	nonDisenchantable[42370] = true -- Cerulean Filigreed Shirt
	nonDisenchantable[42371] = true -- Amber Filigreed Shirt
	nonDisenchantable[42372] = true -- Scarlet Filigreed Shirt
	nonDisenchantable[42373] = true -- Golden Filigreed Shirt
	nonDisenchantable[42374] = true -- Blue Martial Shirt
	nonDisenchantable[42375] = true -- Green Martial Shirt
	nonDisenchantable[42376] = true -- Yellow Martial Shirt
	nonDisenchantable[42377] = true -- Purple Martial Shirt
	nonDisenchantable[42378] = true -- Red Martial Shirt
	nonDisenchantable[44693] = true -- Wound Dressing
	nonDisenchantable[44694] = true -- Antiseptic-Soaked Dressing
	nonDisenchantable[45664] = true -- Silvermoon Doublet
	nonDisenchantable[45666] = true -- Ironforge Doublet
	nonDisenchantable[45667] = true -- Stormwind Doublet
	nonDisenchantable[45668] = true -- Exodar Doublet
	nonDisenchantable[45669] = true -- Sen'jin Doublet
	nonDisenchantable[45670] = true -- Darnassus Doublet
	nonDisenchantable[45671] = true -- Gnomeregan Doublet
	nonDisenchantable[45672] = true -- Orgrimmar Doublet
	nonDisenchantable[45673] = true -- Thunder Bluff Doublet
	nonDisenchantable[45674] = true -- Undercity Doublet
	nonDisenchantable[48663] = true -- Tankard O' Terror
	nonDisenchantable[49567] = true -- Gilnean Adventurer's Shirt
	nonDisenchantable[52252] = true -- Tabard of the Lightbringer
	nonDisenchantable[52485] = true -- Jeweler's Ruby Monocle
	nonDisenchantable[52486] = true -- Jeweler's Sapphire Monocle
	nonDisenchantable[52487] = true -- Jeweler's Amber Monocle
	nonDisenchantable[52488] = true -- Jeweler's Sapphire Monocle
	nonDisenchantable[52548] = true -- Initiate's Tunic
	nonDisenchantable[53852] = true -- Embroidered Shirt
	nonDisenchantable[60223] = true -- High-Powered Bolt Gun
	nonDisenchantable[68611] = true -- Red Shirt
	nonDisenchantable[75274] = true -- Zen Alchemist Stone
	nonDisenchantable[84661] = true -- Dragon Fishing Pole
	nonDisenchantable[89586] = true -- Staff of Serenity
	for itemID = 97826, 97832 do
		nonDisenchantable[itemID] = true -- Latent Kor'kron equipment
	end
end

local function AddStandardNonDisenchantable()
	local itemIDs = {
		109262, 122604, 127842, 128023, 128024, 141408, 151607, 151771, 151772,
		152632, 152633, 152635, 152637, 167081, 167082,
		167177, 167178, 167179, 167180, 167181, 167182, 167183, 167184, 167185,
		167186, 167187, 167188, 167189, 167190, 167191, 167192, 167193, 167194,
		167195, 167196, 167197, 186056, 186058, 186163,
		231955, 231956, 231957, 231958, 231959, 231960, 231961, 231962, 231963,
		231964, 231965, 231966, 231967, 231968, 231969, 231970,
		234830, 234831, 234832, 234833, 234834, 234835, 234836, 234837,
		234881, 234882, 234883, 234884, 234885, 234886, 234887, 234888,
		234924, 234925, 234926, 234927, 234928, 234929, 234930, 234931,
	}
	for index = 1, #itemIDs do
		nonDisenchantable[itemIDs[index]] = true
	end
end

if addon.IsMists or addon.IsStandard then
	AddMistsNonDisenchantable()
	if addon.IsStandard then
		AddStandardNonDisenchantable()
	end
end

local function Result(itemID, chance, minQuantity, maxQuantity, expectedQuantity)
	materials[itemID] = true
	return {
		itemID = itemID,
		chance = chance,
		minQuantity = minQuantity,
		maxQuantity = maxQuantity,
		expectedQuantity = expectedQuantity,
	}
end

local function AddRange(classID, quality, minItemLevel, maxItemLevel, requiredSkill, results)
	data[classID][quality][#data[classID][quality] + 1] = {
		minItemLevel = minItemLevel,
		maxItemLevel = maxItemLevel,
		requiredSkill = requiredSkill,
		results = results,
	}
end

local function AddSharedRange(quality, minItemLevel, maxItemLevel, requiredSkill, results)
	AddRange(WEAPON, quality, minItemLevel, maxItemLevel, requiredSkill, results)
	AddRange(ARMOR, quality, minItemLevel, maxItemLevel, requiredSkill, results)
end

local function AddUncommonRange(minItemLevel, maxItemLevel, requiredSkill, dust, essence, shard)
	local armorResults = {
		Result(dust[1], dust[2], dust[3], dust[4], dust[5]),
		Result(essence[1], essence[2], essence[3], essence[4], essence[5]),
	}
	local weaponResults = {
		Result(dust[1], essence[2], dust[3], dust[4], dust[5] * essence[2] / dust[2]),
		Result(essence[1], dust[2], essence[3], essence[4], essence[5] * dust[2] / essence[2]),
	}
	if shard then
		armorResults[#armorResults + 1] = Result(shard[1], shard[2], shard[3], shard[4], shard[5])
		weaponResults[#weaponResults + 1] = Result(shard[1], shard[2], shard[3], shard[4], shard[5])
	end
	AddRange(ARMOR, UNCOMMON, minItemLevel, maxItemLevel, requiredSkill, armorResults)
	AddRange(WEAPON, UNCOMMON, minItemLevel, maxItemLevel, requiredSkill, weaponResults)
end

local function AddVanillaRanges()
	-- This is the unmodified Vanilla baseline. Forever-specific additions,
	-- replacements, and removals must never be added inside this function.
	-- Expected quantities are unconditional: a 75% chance of an average 1.5
	-- dust is represented as 1.125 dust per disenchant attempt.
	AddUncommonRange(5, 15, 1, { 10940, 0.80, 1, 2, 1.20 }, { 10938, 0.20, 1, 2, 0.30 })
	AddUncommonRange(16, 20, 1, { 10940, 0.75, 2, 3, 1.875 }, { 10939, 0.20, 1, 2, 0.30 }, { 10978, 0.05, 1, 1, 0.05 })
	AddUncommonRange(21, 25, 25, { 10940, 0.75, 4, 6, 3.75 }, { 10998, 0.15, 1, 2, 0.225 }, { 10978, 0.10, 1, 1, 0.10 })
	AddUncommonRange(26, 30, 50, { 11083, 0.75, 1, 2, 1.125 }, { 11082, 0.20, 1, 2, 0.30 }, { 11084, 0.05, 1, 1, 0.05 })
	AddUncommonRange(31, 35, 75, { 11083, 0.75, 2, 5, 2.625 }, { 11134, 0.20, 1, 2, 0.30 }, { 11138, 0.05, 1, 1, 0.05 })
	AddUncommonRange(36, 40, 100, { 11137, 0.75, 1, 2, 1.125 }, { 11135, 0.20, 1, 2, 0.30 }, { 11139, 0.05, 1, 1, 0.05 })
	AddUncommonRange(41, 45, 125, { 11137, 0.75, 2, 5, 2.625 }, { 11174, 0.20, 1, 2, 0.30 }, { 11177, 0.05, 1, 1, 0.05 })
	AddUncommonRange(46, 50, 150, { 11176, 0.75, 1, 2, 1.125 }, { 11175, 0.20, 1, 2, 0.30 }, { 11178, 0.05, 1, 1, 0.05 })
	AddUncommonRange(51, 55, 175, { 11176, 0.75, 2, 5, 2.625 }, { 16202, 0.20, 1, 2, 0.30 }, { 14343, 0.05, 1, 1, 0.05 })
	AddUncommonRange(56, 60, 200, { 16204, 0.75, 1, 2, 1.125 }, { 16203, 0.20, 1, 2, 0.30 }, { 14344, 0.05, 1, 1, 0.05 })
	AddUncommonRange(61, 65, 225, { 16204, 0.75, 2, 5, 2.625 }, { 16203, 0.20, 2, 3, 0.50 }, { 14344, 0.05, 1, 1, 0.05 })

	AddSharedRange(RARE, 1, 25, 25, { Result(10978, 1, 1, 1, 1) })
	AddSharedRange(RARE, 26, 30, 50, { Result(11084, 1, 1, 1, 1) })
	AddSharedRange(RARE, 31, 35, 75, { Result(11138, 1, 1, 1, 1) })
	AddSharedRange(RARE, 36, 40, 100, { Result(11139, 1, 1, 1, 1) })
	AddSharedRange(RARE, 41, 45, 125, { Result(11177, 1, 1, 1, 1) })
	AddSharedRange(RARE, 46, 50, 150, { Result(11178, 1, 1, 1, 1) })
	AddSharedRange(RARE, 51, 55, 175, { Result(14343, 1, 1, 1, 1) })
	AddSharedRange(RARE, 56, 65, 200, { Result(14344, 1, 1, 1, 1) })

	AddSharedRange(EPIC, 1, 25, 25, { Result(10978, 1, 1, 1, 1) })
	AddSharedRange(EPIC, 26, 30, 50, { Result(11084, 1, 1, 1, 1) })
	AddSharedRange(EPIC, 31, 35, 75, { Result(11138, 1, 1, 1, 1) })
	AddSharedRange(EPIC, 36, 40, 100, { Result(11139, 1, 1, 1, 1) })
	AddSharedRange(EPIC, 41, 45, 125, { Result(11177, 1, 2, 4, 3) })
	AddSharedRange(EPIC, 46, 50, 150, { Result(11178, 1, 2, 4, 3) })
	AddSharedRange(EPIC, 51, 55, 175, { Result(14343, 1, 2, 4, 3) })
	AddSharedRange(EPIC, 56, 94, 200, { Result(20725, 1, 1, 2, 1.666) })
end

if addon.IsForever then
	-- Forever starts from a private copy of the Vanilla ranges. Apply only
	-- confirmed Forever additions, replacements, or removals after this call.
	AddVanillaRanges()
elseif addon.IsClassicEra or addon.IsTBC or addon.IsWrath then
	AddVanillaRanges()
end

if addon.IsTBC or addon.IsWrath then
	AddUncommonRange(66, 79, 225, { 22445, 0.75, 1, 3, 1.50 }, { 22447, 0.22, 1, 3, 0.44 }, { 22448, 0.03, 1, 1, 0.03 })
	AddUncommonRange(80, 99, 225, { 22445, 0.75, 2, 3, 1.875 }, { 22447, 0.22, 2, 3, 0.55 }, { 22448, 0.03, 1, 1, 0.03 })
	AddUncommonRange(100, 120, 275, { 22445, 0.75, 2, 5, 2.625 }, { 22446, 0.22, 1, 2, 0.33 }, { 22449, 0.03, 1, 1, 0.03 })
	AddSharedRange(RARE, 66, 99, 225, { Result(22448, 1, 1, 1, 1) })
	AddSharedRange(RARE, 100, 120, 275, { Result(22449, 1, 1, 1, 1) })
	AddSharedRange(EPIC, 95, 164, 300, { Result(22450, 1, 1, 2, 1.666) })
end

if addon.IsWrath then
	-- These Wrath breakpoints form a stable prior which actual disenchants refine.
	-- AddUncommonRange swaps the dust and essence chances for weapons while keeping
	-- armor at the supplied 75% dust and 22% essence distribution.
	AddUncommonRange(130, 151, 325, { 34054, 0.75, 2, 3, 1.875 }, { 34056, 0.22, 1, 2, 0.33 }, { 34053, 0.03, 1, 1, 0.03 })
	AddUncommonRange(152, 200, 350, { 34054, 0.75, 4, 7, 4.125 }, { 34055, 0.22, 1, 2, 0.33 }, { 34052, 0.03, 1, 1, 0.03 })
	AddSharedRange(RARE, 130, 166, 325, { Result(34053, 1, 1, 1, 1) })
	AddSharedRange(RARE, 167, 200, 350, { Result(34052, 1, 1, 1, 1) })
	AddSharedRange(EPIC, 185, 199, 375, { Result(34057, 1, 1, 2, 1.5) })
	AddSharedRange(EPIC, 200, 284, 375, { Result(34057, 1, 1, 1, 1) })
end

local function GetItemDetails(itemInfo)
	local itemID = type(itemInfo) == "number" and itemInfo or C_Item.GetItemInfoInstant(itemInfo)
	if not itemID or nonDisenchantable[itemID] then
		return
	end
	local _, link, quality, itemLevel, _, _, _, _, _, _, _, classID = C_Item.GetItemInfo(itemInfo)
	if not link or quality < UNCOMMON or quality > EPIC or classID ~= WEAPON and classID ~= ARMOR then
		return
	end
	itemLevel = C_Item.GetDetailedItemLevelInfo(link) or itemLevel
	return itemID, link, quality, itemLevel, classID
end

local function FindRange(classID, quality, itemLevel)
	local ranges = data[classID] and data[classID][quality]
	if not ranges then
		return
	end
	for index = 1, #ranges do
		local range = ranges[index]
		if itemLevel >= range.minItemLevel and itemLevel <= range.maxItemLevel then
			return range
		end
	end
end

local function CopyResults(range)
	local results = {}
	for index = 1, #range.results do
		local source = range.results[index]
		results[index] = {
			itemID = source.itemID,
			chance = source.chance,
			minQuantity = source.minQuantity,
			maxQuantity = source.maxQuantity,
			expectedQuantity = source.expectedQuantity,
		}
	end
	return results
end

local function GetLearnedKey(classID, quality, itemLevel)
	return format("%d:%d:%d", classID, quality, itemLevel)
end

local function LearnedRangeIsValid(learned, allowed)
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

local function CopyLearnedRange(learned, allowed)
	if not LearnedRangeIsValid(learned, allowed) then
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

local function AddLearnedRange(aggregate, learned, allowed)
	if not LearnedRangeIsValid(learned, allowed) then
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

local function GetAllowedResults(range)
	local allowed = {}
	for index = 1, #range.results do
		allowed[range.results[index].itemID] = true
	end
	return allowed
end

function module:GetItemDetails(itemInfo)
	return GetItemDetails(itemInfo)
end

function module:IsMaterial(itemID)
	return materials[itemID] == true
end

function module:GetResults(itemInfo)
	local itemID, _, quality, itemLevel, classID = GetItemDetails(itemInfo)
	local range = itemID and FindRange(classID, quality, itemLevel)
	if not range then
		return
	end

	local results = CopyResults(range)
	local aggregate = { samples = 0, results = {} }
	local learnedKey = GetLearnedKey(classID, quality, itemLevel)
	local learned = addon.db.global.disenchantData[learnedKey]
	local byItemID = {}
	for index = 1, #results do
		byItemID[results[index].itemID] = results[index]
	end
	-- A captured disenchant may occasionally be paired with an unrelated locked
	-- item. Reject the complete learned range when it contains any impossible
	-- material; partially accepting that range would still distort probabilities.
	local learnedIsValid = LearnedRangeIsValid(learned, byItemID)
	if learned and not learnedIsValid then
		-- Discard the aggregate rather than salvage individual entries: its sample
		-- divisor belongs to the same bad captures and cannot be repaired safely.
		addon.db.global.disenchantData[learnedKey] = nil
		learned = nil
	end
	if learnedIsValid then
		AddLearnedRange(aggregate, learned, byItemID)
	end
	local syncedBySource = addon.db.global.collectorSyncData.disenchantData
	for sourceID, sourceData in pairs(syncedBySource) do
		local synced = type(sourceData) == "table" and sourceData[learnedKey]
		if synced and not AddLearnedRange(aggregate, synced, byItemID) then
			sourceData[learnedKey] = nil
			if not next(sourceData) then
				syncedBySource[sourceID] = nil
			end
		end
	end
	local sampleCount = aggregate.samples
	if sampleCount > 0 then
		for index = 1, #results do
			local result = results[index]
			local observation = aggregate.results[result.itemID]
			-- Every disenchant is also a non-occurrence for each material it did
			-- not produce, so every baseline result must share the larger divisor.
			result.chance = (result.chance * STATIC_SAMPLE_WEIGHT + (observation and observation.occurrences or 0)) / (STATIC_SAMPLE_WEIGHT + sampleCount)
			result.expectedQuantity = (result.expectedQuantity * STATIC_SAMPLE_WEIGHT + (observation and observation.quantity or 0)) / (STATIC_SAMPLE_WEIGHT + sampleCount)
			if observation then
				result.minQuantity = observation.minQuantity and min(result.minQuantity, observation.minQuantity) or result.minQuantity
				result.maxQuantity = observation.maxQuantity and max(result.maxQuantity, observation.maxQuantity) or result.maxQuantity
			end
		end
	end

	sort(results, function(left, right)
		return left.chance > right.chance or left.chance == right.chance and left.itemID < right.itemID
	end)
	return {
		itemID = itemID,
		classID = classID,
		quality = quality,
		itemLevel = itemLevel,
		requiredSkill = range.requiredSkill,
		sampleCount = sampleCount,
		results = results,
	}
end

function module:SanitizeLearnedData(learnedData)
	local sanitized = {}
	local sampleCount = 0
	for learnedKey, learned in pairs(type(learnedData) == "table" and learnedData or {}) do
		local classID, quality, itemLevel
		if type(learnedKey) == "string" then
			classID, quality, itemLevel = stringMatch(learnedKey, "^(%d+):(%d+):(%d+)$")
		end
		classID, quality, itemLevel = tonumber(classID), tonumber(quality), tonumber(itemLevel)
		local range = classID and FindRange(classID, quality, itemLevel)
		local copy = range and CopyLearnedRange(learned, GetAllowedResults(range))
		if copy then
			sanitized[learnedKey] = copy
			sampleCount = sampleCount + copy.samples
		end
	end
	return next(sanitized) and sanitized or nil, sampleCount
end

function module:RecordObservation(itemInfo, loot)
	local _, _, quality, itemLevel, classID = GetItemDetails(itemInfo)
	local range = classID and FindRange(classID, quality, itemLevel)
	if not range then
		return
	end
	local allowed = GetAllowedResults(range)
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

	local key = GetLearnedKey(classID, quality, itemLevel)
	local learned = addon.db.global.disenchantData[key]
	if not LearnedRangeIsValid(learned, allowed) then
		learned = { samples = 0, results = {} }
		addon.db.global.disenchantData[key] = learned
	end
	learned.samples = learned.samples + 1
	for materialID, quantity in pairs(loot) do
		if materials[materialID] and quantity > 0 then
			local observation = learned.results[materialID]
			if not observation then
				observation = { occurrences = 0, quantity = 0 }
				learned.results[materialID] = observation
			end
			observation.occurrences = observation.occurrences + 1
			observation.quantity = observation.quantity + quantity
			observation.minQuantity = observation.minQuantity and min(observation.minQuantity, quantity) or quantity
			observation.maxQuantity = observation.maxQuantity and max(observation.maxQuantity, quantity) or quantity
		end
	end
	return true
end

function module:GetValue(itemInfo, scope, priceDB)
	local disenchant = self:GetResults(itemInfo)
	if not disenchant then
		return
	end
	local auctionDB = priceDB or addon.db[scope or "factionrealm"].auctionDB
	local total = 0
	local complete = true
	for index = 1, #disenchant.results do
		local result = disenchant.results[index]
		local prices = auctionDB[result.itemID]
		result.marketValue = addon:GetCurrentMarketValue(prices)
		result.priceSource = result.marketValue and "currentMarketValue" or nil
		result.missingPrice = not result.marketValue
		if result.missingPrice then
			result.marketValue = nil
			result.expectedValue = nil
			complete = false
		else
			result.expectedValue = result.expectedQuantity * result.marketValue
			total = total + result.expectedValue
		end
	end
	disenchant.expectedValue = complete and total or nil
	disenchant.complete = complete
	return disenchant
end