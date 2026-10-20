-- Maps Wrath millable herbs to pigment yields and refines them with observed results.

local LibStub = LibStub

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
---@class MillingData: VariableConversionDataModule
local module = addon:NewModule("MillingData")
local definitions = {}

local function Result(itemID, chance, minQuantity, maxQuantity, expectedQuantity)
	return {
		itemID = itemID,
		chance = chance,
		minQuantity = minQuantity,
		maxQuantity = maxQuantity,
		expectedQuantity = expectedQuantity,
	}
end

local function AddGroup(itemIDs, requiredSkill, commonItemID, commonMaximum,
	commonExpected, rareItemID, rareChance, rareExpected)
	for index = 1, #itemIDs do
		local results = {
			Result(commonItemID, 1, 2, commonMaximum, commonExpected),
		}
		if rareItemID then
			results[#results + 1] = Result(rareItemID, rareChance, 1, 3, rareExpected)
		end
		definitions[itemIDs[index]] = {
			requiredQuantity = 5,
			requiredSkill = requiredSkill,
			results = results,
		}
	end
end

-- Milling was introduced in Wrath, where it can process herbs from every
-- preceding expansion as well as Northrend herbs.
AddGroup({ 765, 2447 }, 1, 39151, 3, 2.5) -- Silverleaf, Peacebloom; Alabaster Pigment
AddGroup({ 2449 }, 1, 39151, 4, 3) -- Earthroot; Alabaster Pigment

AddGroup({ 785, 2450, 2452 }, 25, 39334, 3, 2.5, 43103, 0.25, 0.25) -- Dusky/Verdant, low
AddGroup({ 2453, 3820 }, 25, 39334, 4, 3, 43103, 0.5, 0.5) -- Dusky/Verdant, high

AddGroup({ 3355, 3369 }, 75, 39338, 3, 2.5, 43104, 0.27, 0.27) -- Golden/Burnt, low
AddGroup({ 3356, 3357 }, 75, 39338, 4, 3, 43104, 0.5, 0.5) -- Golden/Burnt, high

AddGroup({ 3818, 3821 }, 125, 39339, 3, 2.5, 43105, 0.25, 0.25) -- Emerald/Indigo, low
AddGroup({ 3819, 3358 }, 125, 39339, 4, 3.5, 43105, 0.4, 0.4) -- Emerald/Indigo, high

AddGroup({ 4625, 8831, 8836, 8838 }, 175, 39340, 3, 2.5, 43106, 0.25, 0.25) -- Violet/Ruby, low
AddGroup({ 8845, 8839, 8846 }, 175, 39340, 4, 3, 43106, 0.5, 0.5) -- Violet/Ruby, high

AddGroup({ 13464, 13463 }, 225, 39341, 3, 2.5, 43107, 0.27, 0.27) -- Silvery/Sapphire, low
AddGroup({ 13465, 13466, 13467 }, 225, 39341, 4, 3, 43107, 0.5, 0.5) -- Silvery/Sapphire, high

AddGroup({ 22789, 22786, 22785, 22787 }, 275, 39342, 3, 2.5, 43108, 0.3, 0.3) -- Nether/Ebon, low
AddGroup({ 22790, 22792, 22793, 22791 }, 275, 39342, 4, 3, 43108, 0.55, 0.55) -- Nether/Ebon, high

AddGroup({ 36901, 36904, 36907, 37921, 39969, 39970 }, 325, 39343, 3, 2.5, 43109, 0.25, 0.25) -- Azure/Icy, low
AddGroup({ 36903, 36905, 36906 }, 325, 39343, 4, 3, 43109, 0.5, 0.5) -- Azure/Icy, high

addon:GetModule("MaterialBreakdownData"):InitializeDataModule(module, "millingData", definitions)