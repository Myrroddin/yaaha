-- Maps Mists and Standard milling sources to expected material yields.
-- The Mists baseline contains Vanilla through Mists as represented by TSM's
-- Mists data. Standard replaces it with current data through Shadowlands;
-- Dragonflight and later require profession-specialization modeling.

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

local function SetDefinition(itemID, requiredSkill, results)
	definitions[itemID] = {
		requiredQuantity = 5,
		requiredSkill = requiredSkill,
		results = results,
	}
end

local function AddMistsBaseline()
	-- Mists is an independent Vanilla-through-Mists baseline using the yields
	-- current in the Mists client; no Classic-family table is inherited.
	SetDefinition(765, 1, { -- Silverleaf
		Result(39151, 1, 2, 4, 2.89), -- Alabaster Pigment (Ivory / Moonglow Ink)
	})
	SetDefinition(785, 25, { -- Mageroyal
		Result(39334, 1, 2, 4, 2.83), -- Dusky Pigment (Midnight Ink)
		Result(43103, 0.25, 1, 3, 0.2725), -- Verdant Pigment (Hunter's Ink)
	})
	SetDefinition(2447, 1, { -- Peacebloom
		Result(39151, 1, 2, 4, 2.89), -- Alabaster Pigment (Ivory / Moonglow Ink)
	})
	SetDefinition(2449, 1, { -- Earthroot
		Result(39151, 1, 2, 4, 3), -- Alabaster Pigment (Ivory / Moonglow Ink)
	})
	SetDefinition(2450, 25, { -- Briarthorn
		Result(39334, 1, 2, 4, 2.8825), -- Dusky Pigment (Midnight Ink)
		Result(43103, 0.25, 1, 3, 0.2725), -- Verdant Pigment (Hunter's Ink)
	})
	SetDefinition(2452, 25, { -- Swiftthistle
		Result(39334, 1, 2, 4, 2.9275), -- Dusky Pigment (Midnight Ink)
		Result(43103, 0.25, 1, 3, 0.2725), -- Verdant Pigment (Hunter's Ink)
	})
	SetDefinition(2453, 25, { -- Bruiseweed
		Result(39334, 1, 2, 4, 3), -- Dusky Pigment (Midnight Ink)
		Result(43103, 0.5, 1, 3, 0.5375), -- Verdant Pigment (Hunter's Ink)
	})
	SetDefinition(3355, 75, { -- Wild Steelbloom
		Result(39338, 1, 2, 4, 2.8825), -- Golden Pigment (Lion's Ink)
		Result(43104, 0.25, 1, 3, 0.2725), -- Burnt Pigment (Dawnstar Ink)
	})
	SetDefinition(3356, 75, { -- Kingsblood
		Result(39338, 1, 2, 4, 3), -- Golden Pigment (Lion's Ink)
		Result(43104, 0.5, 1, 3, 0.5375), -- Burnt Pigment (Dawnstar Ink)
	})
	SetDefinition(3357, 75, { -- Liferoot
		Result(39338, 1, 2, 4, 3), -- Golden Pigment (Lion's Ink)
		Result(43104, 0.5, 1, 3, 0.5375), -- Burnt Pigment (Dawnstar Ink)
	})
	SetDefinition(3358, 125, { -- Khadgar's Whisker
		Result(39339, 1, 2, 4, 2.86), -- Emerald Pigment (Jadefire Ink)
		Result(43105, 0.5, 1, 3, 0.5375), -- Indigo Pigment (Royal Ink)
	})
	SetDefinition(3369, 75, { -- Grave Moss
		Result(39338, 1, 2, 4, 2.8825), -- Golden Pigment (Lion's Ink)
		Result(43104, 0.25, 1, 3, 0.2725), -- Burnt Pigment (Dawnstar Ink)
	})
	SetDefinition(3818, 125, { -- Fadeleaf
		Result(39339, 1, 2, 3, 2.5), -- Emerald Pigment (Jadefire Ink)
		Result(43105, 0.25, 1, 3, 0.2725), -- Indigo Pigment (Royal Ink)
	})
	SetDefinition(3819, 125, { -- Wintersbite (Dragon's Teeth)
		Result(39339, 1, 2, 4, 2.86), -- Emerald Pigment (Jadefire Ink)
		Result(43105, 0.5, 1, 3, 0.5375), -- Indigo Pigment (Royal Ink)
	})
	SetDefinition(3820, 25, { -- Stranglekelp
		Result(39334, 1, 2, 4, 3), -- Dusky Pigment (Midnight Ink)
		Result(43103, 0.5, 1, 3, 0.5375), -- Verdant Pigment (Hunter's Ink)
	})
	SetDefinition(3821, 125, { -- Goldthorn
		Result(39339, 1, 2, 3, 2.5), -- Emerald Pigment (Jadefire Ink)
		Result(43105, 0.25, 1, 3, 0.2725), -- Indigo Pigment (Royal Ink)
	})
	SetDefinition(4625, 175, { -- Firebloom
		Result(39340, 1, 2, 3, 2.5), -- Violet Pigment (Celestial Ink)
		Result(43106, 0.25, 1, 3, 0.2725), -- Ruby Pigment (Fiery Ink)
	})
	SetDefinition(8831, 175, { -- Purple Lotus
		Result(39340, 1, 2, 3, 2.5), -- Violet Pigment (Celestial Ink)
		Result(43106, 0.25, 1, 3, 0.2725), -- Ruby Pigment (Fiery Ink)
	})
	SetDefinition(8836, 175, { -- Arthas' Tears
		Result(39340, 1, 2, 3, 2.5), -- Violet Pigment (Celestial Ink)
		Result(43106, 0.25, 1, 3, 0.2725), -- Ruby Pigment (Fiery Ink)
	})
	SetDefinition(8838, 175, { -- Sungrass
		Result(39340, 1, 2, 3, 2.5), -- Violet Pigment (Celestial Ink)
		Result(43106, 0.25, 1, 3, 0.2725), -- Ruby Pigment (Fiery Ink)
	})
	SetDefinition(8839, 175, { -- Blindweed
		Result(39340, 1, 2, 4, 3), -- Violet Pigment (Celestial Ink)
		Result(43106, 0.5, 1, 3, 0.5375), -- Ruby Pigment (Fiery Ink)
	})
	SetDefinition(8845, 175, { -- Ghost Mushroom
		Result(39340, 1, 2, 4, 3), -- Violet Pigment (Celestial Ink)
		Result(43106, 0.5, 1, 3, 0.5375), -- Ruby Pigment (Fiery Ink)
	})
	SetDefinition(8846, 175, { -- Gromsblood
		Result(39340, 1, 2, 4, 3), -- Violet Pigment (Celestial Ink)
		Result(43106, 0.5, 1, 3, 0.5375), -- Ruby Pigment (Fiery Ink)
	})
	SetDefinition(13463, 225, { -- Dreamfoil
		Result(39341, 1, 2, 3, 2.5), -- Silvery Pigment (Shimmering Ink)
		Result(43107, 0.25, 1, 3, 0.2725), -- Sapphire Pigment (Ink of the Sky)
	})
	SetDefinition(13464, 225, { -- Golden Sansam
		Result(39341, 1, 2, 3, 2.5), -- Silvery Pigment (Shimmering Ink)
		Result(43107, 0.25, 1, 3, 0.2725), -- Sapphire Pigment (Ink of the Sky)
	})
	SetDefinition(13465, 225, { -- Mountain Silversage
		Result(39341, 1, 2, 4, 3), -- Silvery Pigment (Shimmering Ink)
		Result(43107, 0.5, 1, 3, 0.5375), -- Sapphire Pigment (Ink of the Sky)
	})
	SetDefinition(13466, 225, { -- Plaguebloom (Sorrowmoss)
		Result(39341, 1, 2, 4, 3), -- Silvery Pigment (Shimmering Ink)
		Result(43107, 0.5, 1, 3, 0.5375), -- Sapphire Pigment (Ink of the Sky)
	})
	SetDefinition(13467, 225, { -- Icecap
		Result(39341, 1, 2, 4, 3), -- Silvery Pigment (Shimmering Ink)
		Result(43107, 0.5, 1, 3, 0.5375), -- Sapphire Pigment (Ink of the Sky)
	})
	SetDefinition(22785, 275, { -- Felweed
		Result(39342, 1, 2, 3, 2.5), -- Nether Pigment (Ethereal Ink)
		Result(43108, 0.25, 1, 3, 0.2725), -- Ebon Pigment (Darkflame Ink)
	})
	SetDefinition(22786, 275, { -- Dreaming Glory
		Result(39342, 1, 2, 3, 2.5), -- Nether Pigment (Ethereal Ink)
		Result(43108, 0.25, 1, 3, 0.2725), -- Ebon Pigment (Darkflame Ink)
	})
	SetDefinition(22787, 275, { -- Ragveil
		Result(39342, 1, 2, 3, 2.5), -- Nether Pigment (Ethereal Ink)
		Result(43108, 0.25, 1, 3, 0.2725), -- Ebon Pigment (Darkflame Ink)
	})
	SetDefinition(22789, 275, { -- Terocone
		Result(39342, 1, 2, 3, 2.5), -- Nether Pigment (Ethereal Ink)
		Result(43108, 0.25, 1, 3, 0.2725), -- Ebon Pigment (Darkflame Ink)
	})
	SetDefinition(22790, 275, { -- Ancient Lichen
		Result(39342, 1, 2, 4, 3), -- Nether Pigment (Ethereal Ink)
		Result(43108, 0.5, 1, 3, 0.5375), -- Ebon Pigment (Darkflame Ink)
	})
	SetDefinition(22791, 275, { -- Netherbloom
		Result(39342, 1, 2, 4, 3), -- Nether Pigment (Ethereal Ink)
		Result(43108, 0.5, 1, 3, 0.5375), -- Ebon Pigment (Darkflame Ink)
	})
	SetDefinition(22792, 275, { -- Nightmare Vine
		Result(39342, 1, 2, 4, 3), -- Nether Pigment (Ethereal Ink)
		Result(43108, 0.5, 1, 3, 0.5375), -- Ebon Pigment (Darkflame Ink)
	})
	SetDefinition(22793, 275, { -- Mana Thistle
		Result(39342, 1, 2, 4, 3), -- Nether Pigment (Ethereal Ink)
		Result(43108, 0.5, 1, 3, 0.5375), -- Ebon Pigment (Darkflame Ink)
	})
	SetDefinition(36901, 325, { -- Goldclover
		Result(39343, 1, 2, 3, 2.5), -- Azure Pigment (Ink of the Sea)
		Result(43109, 0.25, 1, 3, 0.2725), -- Icy Pigment (Snowfall Ink)
	})
	SetDefinition(36903, 325, { -- Adder's Tongue
		Result(39343, 1, 2, 4, 3), -- Azure Pigment (Ink of the Sea)
		Result(43109, 0.5, 1, 3, 0.5375), -- Icy Pigment (Snowfall Ink)
	})
	SetDefinition(36904, 325, { -- Tiger Lily
		Result(39343, 1, 2, 3, 2.5), -- Azure Pigment (Ink of the Sea)
		Result(43109, 0.25, 1, 3, 0.2725), -- Icy Pigment (Snowfall Ink)
	})
	SetDefinition(36905, 325, { -- Lichbloom
		Result(39343, 1, 2, 4, 3), -- Azure Pigment (Ink of the Sea)
		Result(43109, 0.5, 1, 3, 0.5375), -- Icy Pigment (Snowfall Ink)
	})
	SetDefinition(36906, 325, { -- Icethorn
		Result(39343, 1, 2, 4, 3), -- Azure Pigment (Ink of the Sea)
		Result(43109, 0.5, 1, 3, 0.5375), -- Icy Pigment (Snowfall Ink)
	})
	SetDefinition(36907, 325, { -- Talandra's Rose
		Result(39343, 1, 2, 3, 2.5), -- Azure Pigment (Ink of the Sea)
		Result(43109, 0.25, 1, 3, 0.2725), -- Icy Pigment (Snowfall Ink)
	})
	SetDefinition(37921, 325, { -- Deadnettle
		Result(39343, 1, 2, 3, 2.5), -- Azure Pigment (Ink of the Sea)
		Result(43109, 0.25, 1, 3, 0.2725), -- Icy Pigment (Snowfall Ink)
	})
	SetDefinition(39970, 325, { -- Fire Leaf
		Result(39343, 1, 2, 3, 2.5), -- Azure Pigment (Ink of the Sea)
		Result(43109, 0.25, 1, 3, 0.2725), -- Icy Pigment (Snowfall Ink)
	})
	SetDefinition(52983, 425, { -- Cinderbloom
		Result(61979, 1, 2, 4, 2.8), -- Ashen Pigment (Blackfallow Ink)
		Result(61980, 0.25, 1, 3, 0.275), -- Burning Embers (Inferno Ink)
	})
	SetDefinition(52984, 425, { -- Stormvine
		Result(61979, 1, 2, 4, 2.9275), -- Ashen Pigment (Blackfallow Ink)
		Result(61980, 0.25, 1, 3, 0.275), -- Burning Embers (Inferno Ink)
	})
	SetDefinition(52985, 425, { -- Azshara's Veil
		Result(61979, 1, 2, 4, 2.8), -- Ashen Pigment (Blackfallow Ink)
		Result(61980, 0.25, 1, 3, 0.275), -- Burning Embers (Inferno Ink)
	})
	SetDefinition(52986, 475, { -- Heartblossom
		Result(61979, 1, 2, 4, 2.9275), -- Ashen Pigment (Blackfallow Ink)
		Result(61980, 0.25, 1, 3, 0.275), -- Burning Embers (Inferno Ink)
	})
	SetDefinition(52987, 475, { -- Twilight Jasmine
		Result(61979, 1, 2, 4, 3), -- Ashen Pigment (Blackfallow Ink)
		Result(61980, 0.5, 1, 3, 0.5375), -- Burning Embers (Inferno Ink)
	})
	SetDefinition(52988, 475, { -- Whiptail
		Result(61979, 1, 2, 4, 3), -- Ashen Pigment (Blackfallow Ink)
		Result(61980, 0.5, 1, 3, 0.5375), -- Burning Embers (Inferno Ink)
	})
	SetDefinition(72234, 500, { -- Green Tea Leaf
		Result(79251, 1, 2, 4, 2.83), -- Shadow Pigment (Ink of Dreams)
		Result(79253, 0.4, 1, 3, 0.43), -- Misty Pigment (Starlight Ink)
	})
	SetDefinition(72235, 500, { -- Silkweed
		Result(79251, 1, 2, 4, 2.86), -- Shadow Pigment (Ink of Dreams)
		Result(79253, 0.42, 1, 3, 0.45), -- Misty Pigment (Starlight Ink)
	})
	SetDefinition(72237, 500, { -- Rain Poppy
		Result(79251, 1, 2, 4, 2.86), -- Shadow Pigment (Ink of Dreams)
		Result(79253, 0.42, 1, 3, 0.45), -- Misty Pigment (Starlight Ink)
	})
	SetDefinition(79010, 500, { -- Snow Lily
		Result(79251, 1, 2, 4, 2.89), -- Shadow Pigment (Ink of Dreams)
		Result(79253, 0.44, 1, 3, 0.47), -- Misty Pigment (Starlight Ink)
	})
	SetDefinition(79011, 500, { -- Fool's Cap
		Result(79251, 1, 2, 4, 3), -- Shadow Pigment (Ink of Dreams)
		Result(79253, 0.5, 1, 3, 0.5375), -- Misty Pigment (Starlight Ink)
	})
	SetDefinition(89639, 500, { -- Desecrated Herb
		Result(79251, 1, 2, 4, 2.89), -- Shadow Pigment (Ink of Dreams)
		Result(79253, 0.44, 1, 3, 0.47), -- Misty Pigment (Starlight Ink)
	})
end

local function ApplyStandardExtensions()
	-- Replace retained yields and add WoD through Shadowlands sources.
	SetDefinition(765, 0, { -- Silverleaf
		Result(39151, 1, 2, 4, 2.89), -- Alabaster Pigment (Ivory / Moonglow Ink)
	})
	SetDefinition(785, 0, { -- Mageroyal
		Result(39334, 1, 2, 4, 2.83), -- Dusky Pigment (Midnight Ink)
		Result(43103, 0.42, 1, 3, 0.4575), -- Verdant Pigment (Hunter's Ink)
	})
	SetDefinition(2447, 0, { -- Peacebloom
		Result(39151, 1, 2, 4, 2.89), -- Alabaster Pigment (Ivory / Moonglow Ink)
	})
	SetDefinition(2449, 0, { -- Earthroot
		Result(39151, 1, 2, 4, 3), -- Alabaster Pigment (Ivory / Moonglow Ink)
	})
	SetDefinition(2450, 0, { -- Briarthorn
		Result(39334, 1, 2, 4, 2.8825), -- Dusky Pigment (Midnight Ink)
		Result(43103, 0.42, 1, 3, 0.4575), -- Verdant Pigment (Hunter's Ink)
	})
	SetDefinition(2452, 0, { -- Swiftthistle
		Result(39334, 1, 2, 4, 2.9275), -- Dusky Pigment (Midnight Ink)
		Result(43103, 0.465, 1, 3, 0.5025), -- Verdant Pigment (Hunter's Ink)
	})
	SetDefinition(2453, 0, { -- Bruiseweed
		Result(39334, 1, 2, 4, 3), -- Dusky Pigment (Midnight Ink)
		Result(43103, 0.5, 1, 3, 0.5375), -- Verdant Pigment (Hunter's Ink)
	})
	SetDefinition(3355, 0, { -- Wild Steelbloom
		Result(39338, 1, 2, 4, 2.8825), -- Golden Pigment (Lion's Ink)
		Result(43104, 0.45, 1, 3, 0.4875), -- Burnt Pigment (Dawnstar Ink)
	})
	SetDefinition(3356, 0, { -- Kingsblood
		Result(39338, 1, 2, 4, 3), -- Golden Pigment (Lion's Ink)
		Result(43104, 0.5, 1, 3, 0.5375), -- Burnt Pigment (Dawnstar Ink)
	})
	SetDefinition(3357, 0, { -- Liferoot
		Result(39338, 1, 2, 4, 3), -- Golden Pigment (Lion's Ink)
		Result(43104, 0.5, 1, 3, 0.5375), -- Burnt Pigment (Dawnstar Ink)
	})
	SetDefinition(3358, 0, { -- Khadgar's Whisker
		Result(39339, 1, 2, 4, 2.86), -- Emerald Pigment (Jadefire Ink)
		Result(43105, 0.5, 1, 3, 0.5375), -- Indigo Pigment (Royal Ink)
	})
	SetDefinition(3369, 0, { -- Grave Moss
		Result(39338, 1, 2, 4, 2.8825), -- Golden Pigment (Lion's Ink)
		Result(43104, 0.45, 1, 3, 0.4875), -- Burnt Pigment (Dawnstar Ink)
	})
	SetDefinition(3818, 0, { -- Fadeleaf
		Result(39339, 1, 2, 3, 2.5), -- Emerald Pigment (Jadefire Ink)
		Result(43105, 0.42, 1, 3, 0.4575), -- Indigo Pigment (Royal Ink)
	})
	SetDefinition(3819, 0, { -- Dragon's Teeth
		Result(39339, 1, 2, 4, 2.86), -- Emerald Pigment (Jadefire Ink)
		Result(43105, 0.5, 1, 3, 0.5375), -- Indigo Pigment (Royal Ink)
	})
	SetDefinition(3820, 0, { -- Stranglekelp
		Result(39334, 1, 2, 4, 3), -- Dusky Pigment (Midnight Ink)
		Result(43103, 0.5, 1, 3, 0.5375), -- Verdant Pigment (Hunter's Ink)
	})
	SetDefinition(3821, 0, { -- Goldthorn
		Result(39339, 1, 2, 3, 2.5), -- Emerald Pigment (Jadefire Ink)
		Result(43105, 0.42, 1, 3, 0.4575), -- Indigo Pigment (Royal Ink)
	})
	SetDefinition(4625, 0, { -- Firebloom
		Result(39340, 1, 2, 4, 2.83), -- Violet Pigment (Celestial Ink)
		Result(43106, 0.4, 1, 3, 0.4375), -- Ruby Pigment (Fiery Ink)
	})
	SetDefinition(8831, 0, { -- Purple Lotus
		Result(39340, 1, 2, 4, 2.875), -- Violet Pigment (Celestial Ink)
		Result(43106, 0.45, 1, 3, 0.4875), -- Ruby Pigment (Fiery Ink)
	})
	SetDefinition(8836, 0, { -- Arthas' Tears
		Result(39340, 1, 2, 4, 2.83), -- Violet Pigment (Celestial Ink)
		Result(43106, 0.4, 1, 3, 0.4375), -- Ruby Pigment (Fiery Ink)
	})
	SetDefinition(8838, 0, { -- Sungrass
		Result(39340, 1, 2, 4, 2.875), -- Violet Pigment (Celestial Ink)
		Result(43106, 0.45, 1, 3, 0.4875), -- Ruby Pigment (Fiery Ink)
	})
	SetDefinition(8839, 0, { -- Blindweed
		Result(39340, 1, 2, 4, 3), -- Violet Pigment (Celestial Ink)
		Result(43106, 0.5, 1, 3, 0.5375), -- Ruby Pigment (Fiery Ink)
	})
	SetDefinition(8845, 0, { -- Ghost Mushroom
		Result(39340, 1, 2, 4, 3), -- Violet Pigment (Celestial Ink)
		Result(43106, 0.5, 1, 3, 0.5375), -- Ruby Pigment (Fiery Ink)
	})
	SetDefinition(8846, 0, { -- Gromsblood
		Result(39340, 1, 2, 4, 3), -- Violet Pigment (Celestial Ink)
		Result(43106, 0.5, 1, 3, 0.5375), -- Ruby Pigment (Fiery Ink)
	})
	SetDefinition(13463, 0, { -- Dreamfoil
		Result(39341, 1, 2, 4, 2.77), -- Silvery Pigment (Shimmering Ink)
		Result(43107, 0.4, 1, 3, 0.4375), -- Sapphire Pigment (Ink of the Sky)
	})
	SetDefinition(13464, 0, { -- Golden Sansam
		Result(39341, 1, 2, 4, 2.89), -- Silvery Pigment (Shimmering Ink)
		Result(43107, 0.44, 1, 3, 0.4775), -- Sapphire Pigment (Ink of the Sky)
	})
	SetDefinition(13465, 0, { -- Mountain Silversage
		Result(39341, 1, 2, 4, 3), -- Silvery Pigment (Shimmering Ink)
		Result(43107, 0.5, 1, 3, 0.5375), -- Sapphire Pigment (Ink of the Sky)
	})
	SetDefinition(13466, 0, { -- Sorrowmoss
		Result(39341, 1, 2, 4, 3), -- Silvery Pigment (Shimmering Ink)
		Result(43107, 0.5, 1, 3, 0.5375), -- Sapphire Pigment (Ink of the Sky)
	})
	SetDefinition(13467, 0, { -- Icecap
		Result(39341, 1, 2, 4, 3), -- Silvery Pigment (Shimmering Ink)
		Result(43107, 0.5, 1, 3, 0.5375), -- Sapphire Pigment (Ink of the Sky)
	})
	SetDefinition(22785, 0, { -- Felweed
		Result(39342, 1, 2, 4, 2.8), -- Nether Pigment (Ethereal Ink)
		Result(43108, 0.4, 1, 3, 0.4375), -- Ebon Pigment (Darkflame Ink)
	})
	SetDefinition(22786, 0, { -- Dreaming Glory
		Result(39342, 1, 2, 4, 2.8), -- Nether Pigment (Ethereal Ink)
		Result(43108, 0.4, 1, 3, 0.4375), -- Ebon Pigment (Darkflame Ink)
	})
	SetDefinition(22787, 0, { -- Ragveil
		Result(39342, 1, 2, 4, 2.8), -- Nether Pigment (Ethereal Ink)
		Result(43108, 0.4, 1, 3, 0.4375), -- Ebon Pigment (Darkflame Ink)
	})
	SetDefinition(22789, 0, { -- Terocone
		Result(39342, 1, 2, 4, 2.8), -- Nether Pigment (Ethereal Ink)
		Result(43108, 0.4, 1, 3, 0.4375), -- Ebon Pigment (Darkflame Ink)
	})
	SetDefinition(22790, 0, { -- Ancient Lichen
		Result(39342, 1, 2, 4, 3), -- Nether Pigment (Ethereal Ink)
		Result(43108, 0.5, 1, 3, 0.5375), -- Ebon Pigment (Darkflame Ink)
	})
	SetDefinition(22791, 0, { -- Netherbloom
		Result(39342, 1, 2, 4, 3), -- Nether Pigment (Ethereal Ink)
		Result(43108, 0.5, 1, 3, 0.5375), -- Ebon Pigment (Darkflame Ink)
	})
	SetDefinition(22792, 0, { -- Nightmare Vine
		Result(39342, 1, 2, 4, 3), -- Nether Pigment (Ethereal Ink)
		Result(43108, 0.5, 1, 3, 0.5375), -- Ebon Pigment (Darkflame Ink)
	})
	SetDefinition(22793, 0, { -- Mana Thistle
		Result(39342, 1, 2, 4, 3), -- Nether Pigment (Ethereal Ink)
		Result(43108, 0.5, 1, 3, 0.5375), -- Ebon Pigment (Darkflame Ink)
	})
	SetDefinition(36901, 0, { -- Goldclover
		Result(39343, 1, 2, 4, 2.68), -- Azure Pigment (Ink of the Sea)
		Result(43109, 0.4, 1, 3, 0.4375), -- Icy Pigment (Snowfall Ink)
	})
	SetDefinition(36903, 0, { -- Adder's Tongue
		Result(39343, 1, 2, 4, 3), -- Azure Pigment (Ink of the Sea)
		Result(43109, 0.5, 1, 3, 0.5375), -- Icy Pigment (Snowfall Ink)
	})
	SetDefinition(36904, 0, { -- Tiger Lily
		Result(39343, 1, 2, 4, 2.68), -- Azure Pigment (Ink of the Sea)
		Result(43109, 0.33, 1, 3, 0.4175), -- Icy Pigment (Snowfall Ink)
	})
	SetDefinition(36905, 0, { -- Lichbloom
		Result(39343, 1, 2, 4, 3), -- Azure Pigment (Ink of the Sea)
		Result(43109, 0.5, 1, 3, 0.5375), -- Icy Pigment (Snowfall Ink)
	})
	SetDefinition(36906, 0, { -- Icethorn
		Result(39343, 1, 2, 4, 3), -- Azure Pigment (Ink of the Sea)
		Result(43109, 0.5, 1, 3, 0.5375), -- Icy Pigment (Snowfall Ink)
	})
	SetDefinition(36907, 0, { -- Talandra's Rose
		Result(39343, 1, 2, 4, 2.68), -- Azure Pigment (Ink of the Sea)
		Result(43109, 0.33, 1, 3, 0.3775), -- Icy Pigment (Snowfall Ink)
	})
	SetDefinition(37921, 0, { -- Deadnettle
		Result(39343, 1, 2, 4, 2.68), -- Azure Pigment (Ink of the Sea)
		Result(43109, 0.4, 1, 3, 0.4375), -- Icy Pigment (Snowfall Ink)
	})
	SetDefinition(39970, 0, { -- Fire Leaf
		Result(39343, 1, 2, 4, 2.68), -- Azure Pigment (Ink of the Sea)
		Result(43109, 0.33, 1, 3, 0.3975), -- Icy Pigment (Snowfall Ink)
	})
	SetDefinition(52983, 0, { -- Cinderbloom
		Result(61979, 1, 2, 4, 2.8), -- Ashen Pigment (Blackfallow Ink)
		Result(61980, 0.42, 1, 3, 0.4575), -- Burning Embers (Inferno Ink)
	})
	SetDefinition(52984, 0, { -- Stormvine
		Result(61979, 1, 2, 4, 2.9275), -- Ashen Pigment (Blackfallow Ink)
		Result(61980, 0.46, 1, 3, 0.4975), -- Burning Embers (Inferno Ink)
	})
	SetDefinition(52985, 0, { -- Azshara's Veil
		Result(61979, 1, 2, 4, 2.8), -- Ashen Pigment (Blackfallow Ink)
		Result(61980, 0.4, 1, 3, 0.4375), -- Burning Embers (Inferno Ink)
	})
	SetDefinition(52986, 0, { -- Heartblossom
		Result(61979, 1, 2, 4, 2.9275), -- Ashen Pigment (Blackfallow Ink)
		Result(61980, 0.44, 1, 3, 0.4775), -- Burning Embers (Inferno Ink)
	})
	SetDefinition(52987, 0, { -- Twilight Jasmine
		Result(61979, 1, 2, 4, 3), -- Ashen Pigment (Blackfallow Ink)
		Result(61980, 0.5, 1, 3, 0.5375), -- Burning Embers (Inferno Ink)
	})
	SetDefinition(52988, 0, { -- Whiptail
		Result(61979, 1, 2, 4, 3), -- Ashen Pigment (Blackfallow Ink)
		Result(61980, 0.5, 1, 3, 0.5375), -- Burning Embers (Inferno Ink)
	})
	SetDefinition(72234, 0, { -- Green Tea Leaf
		Result(79251, 1, 2, 4, 2.83), -- Shadow Pigment (Ink of Dreams)
		Result(79253, 0.4, 1, 3, 0.43), -- Misty Pigment (Starlight Ink)
	})
	SetDefinition(72235, 0, { -- Silkweed
		Result(79251, 1, 2, 4, 2.86), -- Shadow Pigment (Ink of Dreams)
		Result(79253, 0.42, 1, 3, 0.45), -- Misty Pigment (Starlight Ink)
	})
	SetDefinition(72237, 0, { -- Rain Poppy
		Result(79251, 1, 2, 4, 2.86), -- Shadow Pigment (Ink of Dreams)
		Result(79253, 0.42, 1, 3, 0.45), -- Misty Pigment (Starlight Ink)
	})
	SetDefinition(79010, 0, { -- Snow Lily
		Result(79251, 1, 2, 4, 2.89), -- Shadow Pigment (Ink of Dreams)
		Result(79253, 0.44, 1, 3, 0.47), -- Misty Pigment (Starlight Ink)
	})
	SetDefinition(79011, 0, { -- Fool's Cap
		Result(79251, 1, 2, 4, 3), -- Shadow Pigment (Ink of Dreams)
		Result(79253, 0.5, 1, 3, 0.5375), -- Misty Pigment (Starlight Ink)
	})
	SetDefinition(89639, 0, { -- Desecrated Herb
		Result(79251, 1, 2, 4, 2.89), -- Shadow Pigment (Ink of Dreams)
		Result(79253, 0.44, 1, 3, 0.47), -- Misty Pigment (Starlight Ink)
	})
	SetDefinition(109124, 0, { -- Frostweed
		Result(114931, 1, 2, 3, 2.1), -- Cerulean Pigment (Warbinder's Ink)
	})
	SetDefinition(109125, 0, { -- Fireweed
		Result(114931, 1, 2, 3, 2.1), -- Cerulean Pigment (Warbinder's Ink)
	})
	SetDefinition(109126, 0, { -- Gorgrond Flytrap
		Result(114931, 1, 2, 3, 2.1), -- Cerulean Pigment (Warbinder's Ink)
	})
	SetDefinition(109127, 0, { -- Starflower
		Result(114931, 1, 2, 3, 2.1), -- Cerulean Pigment (Warbinder's Ink)
	})
	SetDefinition(109128, 0, { -- Nagrand Arrowbloom
		Result(114931, 1, 2, 3, 2.1), -- Cerulean Pigment (Warbinder's Ink)
	})
	SetDefinition(109129, 0, { -- Talador Orchid
		Result(114931, 1, 2, 3, 2.1), -- Cerulean Pigment (Warbinder's Ink)
	})
	SetDefinition(124101, 0, { -- Aethril
		Result(129032, 1, 2, 3, 2.1), -- Roseate Pigment (No Legion Ink)
		Result(129034, 0.22, 1, 1, 0.22), -- Sallow Pigment (No Legion Ink)
	})
	SetDefinition(124102, 0, { -- Dreamleaf
		Result(129032, 1, 2, 3, 2.1), -- Roseate Pigment (No Legion Ink)
		Result(129034, 0.22, 1, 1, 0.22), -- Sallow Pigment (No Legion Ink)
	})
	SetDefinition(124103, 0, { -- Foxflower
		Result(129032, 1, 2, 3, 2.1), -- Roseate Pigment (No Legion Ink)
		Result(129034, 0.22, 1, 1, 0.22), -- Sallow Pigment (No Legion Ink)
	})
	SetDefinition(124104, 0, { -- Fjarnskaggl
		Result(129032, 1, 2, 5, 2.33), -- Roseate Pigment (No Legion Ink)
		Result(129034, 0.24, 1, 2, 0.2475), -- Sallow Pigment (No Legion Ink)
	})
	SetDefinition(124105, 0, { -- Starlight Rose
		Result(129032, 1, 5, 8, 6.06), -- Roseate Pigment (No Legion Ink)
		Result(129034, 0.22, 1, 1, 0.22), -- Sallow Pigment (No Legion Ink)
	})
	SetDefinition(124106, 0, { -- Felwort
		Result(129032, 1, 2, 3, 2.1), -- Roseate Pigment (No Legion Ink)
		Result(129034, 1, 8, 14, 10.74), -- Sallow Pigment (No Legion Ink)
	})
	SetDefinition(128304, 0, { -- Yseralline Seed
		Result(129032, 0.99, 1, 1, 0.99), -- Roseate Pigment (No Legion Ink)
		Result(129034, 0.01, 1, 1, 0.01), -- Sallow Pigment (No Legion Ink)
	})
	SetDefinition(151565, 0, { -- Astral Glory
		Result(129032, 1, 2, 3, 2.1), -- Roseate Pigment (No Legion Ink)
		Result(129034, 0.22, 1, 1, 0.22), -- Sallow Pigment (No Legion Ink)
	})
	SetDefinition(152505, 0, { -- Riverbud
		Result(153635, 1, 2, 6, 3.75), -- Ultramarine Pigment (Ultramarine Ink)
		Result(153636, 0.66, 1, 4, 1.36), -- Crimson Pigment (Crimson Ink)
		Result(153669, 0.28, 1, 3, 0.555), -- Viridescent Pigment (Viridescent Ink)
	})
	SetDefinition(152506, 0, { -- Star Moss
		Result(153635, 1, 2, 6, 3.75), -- Ultramarine Pigment (Ultramarine Ink)
		Result(153636, 0.66, 1, 4, 1.36), -- Crimson Pigment (Crimson Ink)
		Result(153669, 0.28, 1, 3, 0.555), -- Viridescent Pigment (Viridescent Ink)
	})
	SetDefinition(152507, 0, { -- Akunda's Bite
		Result(153635, 1, 2, 6, 3.75), -- Ultramarine Pigment (Ultramarine Ink)
		Result(153636, 0.66, 1, 4, 1.36), -- Crimson Pigment (Crimson Ink)
		Result(153669, 0.28, 1, 3, 0.555), -- Viridescent Pigment (Viridescent Ink)
	})
	SetDefinition(152508, 0, { -- Winter's Kiss
		Result(153635, 1, 2, 6, 3.75), -- Ultramarine Pigment (Ultramarine Ink)
		Result(153636, 0.66, 1, 4, 1.36), -- Crimson Pigment (Crimson Ink)
		Result(153669, 0.28, 1, 3, 0.555), -- Viridescent Pigment (Viridescent Ink)
	})
	SetDefinition(152509, 0, { -- Siren's Pollen
		Result(153635, 1, 2, 6, 3.75), -- Ultramarine Pigment (Ultramarine Ink)
		Result(153636, 0.66, 1, 4, 1.36), -- Crimson Pigment (Crimson Ink)
		Result(153669, 0.28, 1, 3, 0.555), -- Viridescent Pigment (Viridescent Ink)
	})
	SetDefinition(152510, 0, { -- Anchor Weed
		Result(153635, 1, 2, 6, 3.75), -- Ultramarine Pigment (Ultramarine Ink)
		Result(153636, 0.66, 1, 4, 1.36), -- Crimson Pigment (Crimson Ink)
		Result(153669, 0.975, 1, 4, 1.575), -- Viridescent Pigment (Viridescent Ink)
	})
	SetDefinition(152511, 0, { -- Sea Stalk
		Result(153635, 1, 2, 6, 3.75), -- Ultramarine Pigment (Ultramarine Ink)
		Result(153636, 0.66, 1, 4, 1.36), -- Crimson Pigment (Crimson Ink)
		Result(153669, 0.28, 1, 3, 0.555), -- Viridescent Pigment (Viridescent Ink)
	})
	SetDefinition(168487, 0, { -- Zin'anthid
		Result(168662, 1, 2, 4, 3), -- Maroon Pigment (Maroon Ink)
	})
	SetDefinition(168583, 0, { -- Widowbloom
		Result(173056, 0.65, 1, 2, 0.975), -- Umbral Pigment (Umbral ink)
		Result(173057, 0.35, 1, 2, 0.525), -- Luminous Pigment (Luminous Ink)
		Result(175788, 0.03, 1, 1, 0.03), -- Tranquil Pigment (Tranquil Ink)
	})
	SetDefinition(168586, 0, { -- Rising Glory
		Result(173056, 0.35, 1, 2, 0.525), -- Umbral Pigment (Umbral ink)
		Result(173057, 0.65, 1, 2, 0.975), -- Luminous Pigment (Luminous Ink)
		Result(175788, 0.03, 1, 1, 0.03), -- Tranquil Pigment (Tranquil Ink)
	})
	SetDefinition(168589, 0, { -- Marrowroot
		Result(173056, 0.65, 1, 2, 0.975), -- Umbral Pigment (Umbral ink)
		Result(173057, 0.35, 1, 2, 0.525), -- Luminous Pigment (Luminous Ink)
		Result(175788, 0.03, 1, 1, 0.03), -- Tranquil Pigment (Tranquil Ink)
	})
	SetDefinition(169701, 0, { -- Death Blossom
		Result(173056, 0.5, 1, 2, 0.75), -- Umbral Pigment (Umbral ink)
		Result(173057, 0.5, 1, 2, 0.75), -- Luminous Pigment (Luminous Ink)
		Result(175788, 0.03, 1, 1, 0.03), -- Tranquil Pigment (Tranquil Ink)
	})
	SetDefinition(170554, 0, { -- Vigil's Torch
		Result(173056, 0.35, 1, 2, 0.525), -- Umbral Pigment (Umbral ink)
		Result(173057, 0.65, 1, 2, 0.975), -- Luminous Pigment (Luminous Ink)
		Result(175788, 0.03, 1, 1, 0.03), -- Tranquil Pigment (Tranquil Ink)
	})
	SetDefinition(171315, 0, { -- Nightshade
		Result(173056, 0.5, 1, 3, 1.25), -- Umbral Pigment (Umbral ink)
		Result(173057, 0.5, 1, 3, 1.25), -- Luminous Pigment (Luminous Ink)
		Result(175788, 1, 1, 2, 1.5), -- Tranquil Pigment (Tranquil Ink)
	})
	SetDefinition(187699, 0, { -- First Flower
		Result(173056, 0.5, 2, 3, 1.25), -- Umbral Pigment (Umbral ink)
		Result(173057, 0.5, 2, 3, 1.25), -- Luminous Pigment (Luminous Ink)
		Result(175788, 1, 2, 3, 2.5), -- Tranquil Pigment (Tranquil Ink)
	})
end

AddMistsBaseline()
if addon.IsStandard then
	ApplyStandardExtensions()
end

addon:GetModule("MaterialBreakdownData"):InitializeDataModule(module, "millingData", definitions)