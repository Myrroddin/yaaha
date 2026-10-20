-- Maps TBC and Wrath prospectable ores to gem yields and refines them with observed results.

local LibStub = LibStub

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
---@class ProspectingData: VariableConversionDataModule
local module = addon:NewModule("ProspectingData")
local definitions = {}

local uncommonGems = {
	36917, -- Bloodstone
	36923, -- Chalcedony
	36932, -- Dark Jade
	36929, -- Huge Citrine
	36926, -- Shadow Crystal
	36920, -- Sun Crystal
}
local rareGems = {
	36921, -- Autumn's Glow
	36933, -- Forest Emerald
	36930, -- Monarch Topaz
	36918, -- Scarlet Ruby
	36924, -- Sky Sapphire
	36927, -- Twilight Opal
}
local epicGems = {
	36931, -- Ametrine
	36919, -- Cardinal Ruby
	36928, -- Dreadstone
	36934, -- Eye of Zul
	36922, -- King's Amber
	36925, -- Majestic Zircon
}

local function AddResult(results, itemID, chance, expectedQuantity, maxQuantity)
	results[#results + 1] = {
		itemID = itemID,
		chance = chance,
		minQuantity = 1,
		maxQuantity = maxQuantity or 2,
		expectedQuantity = expectedQuantity,
	}
end

local function Result(itemID, chance, minQuantity, maxQuantity, expectedQuantity)
	return {
		itemID = itemID,
		chance = chance,
		minQuantity = minQuantity,
		maxQuantity = maxQuantity,
		expectedQuantity = expectedQuantity,
	}
end

local function AddDefinition(itemID, requiredSkill, results)
	definitions[itemID] = {
		requiredQuantity = 5,
		requiredSkill = requiredSkill,
		results = results,
	}
end

local function AddGemGroup(results, itemIDs, chance, expectedQuantity)
	for index = 1, #itemIDs do
		AddResult(results, itemIDs[index], chance, expectedQuantity)
	end
end

local function AddOre(itemID, requiredSkill, uncommonChance, uncommonExpected,
	rareChance, rareExpected, includeEpics)
	local results = {}
	AddGemGroup(results, uncommonGems, uncommonChance, uncommonExpected)
	AddGemGroup(results, rareGems, rareChance, rareExpected)
	if includeEpics then
		AddGemGroup(results, epicGems, 0.04, 0.04)
		-- Titanium Powder is an additional result rather than one of the gem rolls.
		AddResult(results, 46849, 0.57, 0.65, 5)
	end
	definitions[itemID] = {
		requiredQuantity = 5,
		requiredSkill = requiredSkill,
		results = results,
	}
end

-- Prospecting did not exist in Vanilla, but Vanilla ores form the shared
-- baseline for TBC and Wrath, the Classic-family clients which have it.
do
	AddDefinition(2770, 20, { -- Copper Ore
		Result(774, 0.5, 1, 1, 0.5), -- Malachite
		Result(818, 0.5, 1, 1, 0.5), -- Tigerseye
		Result(1210, 0.1, 1, 1, 0.1), -- Shadowgem
	})
	AddDefinition(2771, 50, { -- Tin Ore
		Result(1210, 0.375, 1, 2, 0.4), -- Shadowgem
		Result(1705, 0.375, 1, 2, 0.4), -- Lesser Moonstone
		Result(1206, 0.375, 1, 2, 0.4), -- Moss Agate
		Result(3864, 0.04, 1, 1, 0.04), -- Citrine
		Result(1529, 0.04, 1, 1, 0.04), -- Jade
		Result(7909, 0.04, 1, 1, 0.04), -- Aquamarine
	})
	AddDefinition(2772, 125, { -- Iron Ore
		Result(3864, 0.375, 1, 2, 0.375), -- Citrine
		Result(1705, 0.375, 1, 2, 0.375), -- Lesser Moonstone
		Result(1529, 0.375, 1, 2, 0.375), -- Jade
		Result(7909, 0.05, 1, 1, 0.05), -- Aquamarine
		Result(7910, 0.05, 1, 1, 0.05), -- Star Ruby
	})
	AddDefinition(3858, 175, { -- Mithril Ore
		Result(3864, 0.375, 1, 2, 0.375), -- Citrine
		Result(7910, 0.375, 1, 2, 0.375), -- Star Ruby
		Result(7909, 0.375, 1, 2, 0.375), -- Aquamarine
		Result(12800, 0.03, 1, 1, 0.03), -- Azerothian Diamond
		Result(12361, 0.03, 1, 1, 0.03), -- Blue Sapphire
		Result(12799, 0.03, 1, 1, 0.03), -- Large Opal
		Result(12364, 0.03, 1, 1, 0.03), -- Huge Emerald
	})
	AddDefinition(10620, 250, { -- Thorium Ore
		Result(7910, 0.15, 1, 2, 0.15), -- Star Ruby
		Result(12799, 0.30, 1, 2, 0.30), -- Large Opal
		Result(12361, 0.30, 1, 2, 0.30), -- Blue Sapphire
		Result(12800, 0.30, 1, 2, 0.30), -- Azerothian Diamond
		Result(12364, 0.30, 1, 2, 0.30), -- Huge Emerald
		Result(23077, 0.015, 1, 1, 0.015), -- Blood Garnet
		Result(21929, 0.015, 1, 1, 0.015), -- Flame Spessarite
		Result(23112, 0.015, 1, 1, 0.015), -- Golden Draenite
		Result(23079, 0.015, 1, 1, 0.015), -- Deep Peridot
		Result(23117, 0.015, 1, 1, 0.015), -- Azure Moonstone
		Result(23107, 0.015, 1, 1, 0.015), -- Shadow Draenite
	})
end

-- TBC ores extend the Vanilla ore table without changing that baseline.
do
	AddDefinition(23424, 275, { -- Fel Iron Ore
		Result(23077, 0.19, 1, 2, 0.19), -- Blood Garnet
		Result(21929, 0.19, 1, 2, 0.19), -- Flame Spessarite
		Result(23112, 0.19, 1, 2, 0.19), -- Golden Draenite
		Result(23079, 0.19, 1, 2, 0.19), -- Deep Peridot
		Result(23117, 0.19, 1, 2, 0.19), -- Azure Moonstone
		Result(23107, 0.19, 1, 2, 0.19), -- Shadow Draenite
		Result(23436, 0.011, 1, 1, 0.011), -- Living Ruby
		Result(23439, 0.011, 1, 1, 0.011), -- Noble Topaz
		Result(23440, 0.011, 1, 1, 0.011), -- Dawnstone
		Result(23437, 0.011, 1, 1, 0.011), -- Talasite
		Result(23438, 0.011, 1, 1, 0.011), -- Star of Elune
		Result(23441, 0.011, 1, 1, 0.011), -- Nightseye
	})
	AddDefinition(23425, 325, { -- Adamantite Ore
		Result(24243, 1, 1, 1, 1), -- Adamantite Powder
		Result(23077, 0.19, 1, 2, 0.19), -- Blood Garnet
		Result(21929, 0.19, 1, 2, 0.19), -- Flame Spessarite
		Result(23112, 0.19, 1, 2, 0.19), -- Golden Draenite
		Result(23079, 0.19, 1, 2, 0.19), -- Deep Peridot
		Result(23117, 0.19, 1, 2, 0.19), -- Azure Moonstone
		Result(23107, 0.19, 1, 2, 0.19), -- Shadow Draenite
		Result(23436, 0.03, 1, 1, 0.03), -- Living Ruby
		Result(23439, 0.03, 1, 1, 0.03), -- Noble Topaz
		Result(23440, 0.03, 1, 1, 0.03), -- Dawnstone
		Result(23437, 0.03, 1, 1, 0.03), -- Talasite
		Result(23438, 0.03, 1, 1, 0.03), -- Star of Elune
		Result(23441, 0.03, 1, 1, 0.03), -- Nightseye
	})
end

if addon.IsWrath then
	-- Wrath retains all preceding ores and adds the Northrend ores below.
	AddOre(36909, 350, 0.24, 0.25, 0.014, 0.013, false) -- Cobalt Ore
	AddOre(36912, 400, 0.18, 0.20, 0.04, 0.04, false) -- Saronite Ore
	AddOre(36910, 450, 0.23, 0.25, 0.04, 0.04, true) -- Titanium Ore
end

addon:GetModule("MaterialBreakdownData"):InitializeDataModule(module, "prospectData", definitions)