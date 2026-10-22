-- Maps Mists and Standard prospecting sources to expected material yields.
-- The Mists baseline contains Vanilla through Mists as represented by TSM's
-- Mists data. Standard replaces it with current data through Shadowlands;
-- Dragonflight and later require profession-specialization modeling.

local LibStub = LibStub

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local isStandard = addon.isStandard
---@class ProspectingData: VariableConversionDataModule
local module = addon:NewModule("ProspectingData")
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
	SetDefinition(2770, 20, { -- Copper Ore
		Result(774, 0.5, 1, 1, 0.5), -- Malachite
		Result(818, 0.5, 1, 1, 0.5), -- Tigerseye
		Result(1210, 0.1, 1, 1, 0.1), -- Shadowgem
	})
	SetDefinition(2771, 50, { -- Tin Ore
		Result(1206, 0.36, 1, 1, 0.36), -- Moss Agate
		Result(1210, 0.36, 1, 1, 0.36), -- Shadowgem
		Result(1529, 0.0325, 1, 1, 0.0325), -- Jade
		Result(1705, 0.36, 1, 1, 0.36), -- Lesser Moonstone
		Result(3864, 0.0325, 1, 1, 0.0325), -- Citrine
		Result(7909, 0.0325, 1, 1, 0.0325), -- Aquamarine
	})
	SetDefinition(2772, 125, { -- Iron Ore
		Result(1529, 0.33, 1, 1, 0.33), -- Jade
		Result(1705, 0.33, 1, 1, 0.33), -- Lesser Moonstone
		Result(3864, 0.33, 1, 1, 0.33), -- Citrine
		Result(7909, 0.05, 1, 1, 0.05), -- Aquamarine
		Result(7910, 0.05, 1, 1, 0.05), -- Star Ruby
	})
	SetDefinition(3858, 175, { -- Mithril Ore
		Result(3864, 0.33, 1, 1, 0.33), -- Citrine
		Result(7909, 0.33, 1, 1, 0.33), -- Aquamarine
		Result(7910, 0.33, 1, 1, 0.33), -- Star Ruby
		Result(12361, 0.0225, 1, 1, 0.0225), -- Blue Sapphire
		Result(12364, 0.0225, 1, 1, 0.0225), -- Huge Emerald
		Result(12799, 0.0225, 1, 1, 0.0225), -- Large Opal
		Result(12800, 0.0225, 1, 1, 0.0225), -- Azerothian Diamond
	})
	SetDefinition(10620, 250, { -- Thorium Ore
		Result(7910, 0.17, 1, 1, 0.17), -- Star Ruby
		Result(12361, 0.17, 1, 1, 0.17), -- Blue Sapphire
		Result(12364, 0.17, 1, 1, 0.17), -- Huge Emerald
		Result(12799, 0.17, 1, 1, 0.17), -- Large Opal
		Result(12800, 0.17, 1, 1, 0.17), -- Azerothian Diamond
	})
	SetDefinition(23424, 275, { -- Fel Iron Ore
		Result(21929, 0.165, 1, 1, 0.165), -- Flame Spessarite
		Result(23077, 0.165, 1, 1, 0.165), -- Blood Garnet
		Result(23079, 0.165, 1, 1, 0.165), -- Deep Peridot
		Result(23107, 0.165, 1, 1, 0.165), -- Shadow Draenite
		Result(23112, 0.165, 1, 1, 0.165), -- Golden Draenite
		Result(23117, 0.165, 1, 1, 0.165), -- Azure Moonstone
		Result(23436, 0.0125, 1, 1, 0.0125), -- Living Ruby
		Result(23437, 0.0125, 1, 1, 0.0125), -- Talasite
		Result(23438, 0.0125, 1, 1, 0.0125), -- Star of Elune
		Result(23439, 0.0125, 1, 1, 0.0125), -- Noble Topaz
		Result(23440, 0.0125, 1, 1, 0.0125), -- Dawnstone
		Result(23441, 0.0125, 1, 1, 0.0125), -- Nightseye
	})
	SetDefinition(23425, 325, { -- Adamantite Ore
		Result(21929, 0.17, 1, 1, 0.17), -- Flame Spessarite
		Result(23077, 0.17, 1, 1, 0.17), -- Blood Garnet
		Result(23079, 0.17, 1, 1, 0.17), -- Deep Peridot
		Result(23107, 0.17, 1, 1, 0.17), -- Shadow Draenite
		Result(23112, 0.17, 1, 1, 0.17), -- Golden Draenite
		Result(23117, 0.17, 1, 1, 0.17), -- Azure Moonstone
		Result(23436, 0.035, 1, 1, 0.035), -- Living Ruby
		Result(23437, 0.035, 1, 1, 0.035), -- Talasite
		Result(23438, 0.035, 1, 1, 0.035), -- Star of Elune
		Result(23439, 0.035, 1, 1, 0.035), -- Noble Topaz
		Result(23440, 0.035, 1, 1, 0.035), -- Dawnstone
		Result(23441, 0.035, 1, 1, 0.035), -- Nightseye
	})
	SetDefinition(36909, 350, { -- Cobalt Ore
		Result(36917, 0.16, 1, 2, 0.165), -- Bloodstone
		Result(36918, 0.01, 1, 2, 0.01), -- Scarlet Ruby
		Result(36920, 0.16, 1, 2, 0.165), -- Sun Crystal
		Result(36921, 0.01, 1, 2, 0.01), -- Autumn's Glow
		Result(36923, 0.16, 1, 2, 0.165), -- Chalcedony
		Result(36924, 0.01, 1, 2, 0.01), -- Sky Sapphire
		Result(36926, 0.16, 1, 2, 0.165), -- Shadow Crystal
		Result(36927, 0.01, 1, 2, 0.01), -- Twilight Opal
		Result(36929, 0.16, 1, 2, 0.165), -- Huge Citrine
		Result(36930, 0.01, 1, 2, 0.01), -- Monarch Topaz
		Result(36932, 0.16, 1, 2, 0.165), -- Dark Jade
		Result(36933, 0.01, 1, 2, 0.01), -- Forest Emerald
	})
	SetDefinition(36910, 450, { -- Titanium Ore
		-- TSM records these six rates as 0.5000 per ore rather than 0.0500;
		-- use the physically plausible per-prospect expectation.
		Result(36917, 0.235, 1, 2, 0.25), -- Bloodstone
		Result(36918, 0.04, 1, 2, 0.04), -- Scarlet Ruby
		Result(36919, 0.03, 1, 2, 0.0305), -- Cardinal Ruby
		Result(36920, 0.235, 1, 2, 0.25), -- Sun Crystal
		Result(36921, 0.04, 1, 2, 0.04), -- Autumn's Glow
		Result(36922, 0.03, 1, 2, 0.0305), -- King's Amber
		Result(36923, 0.235, 1, 2, 0.25), -- Chalcedony
		Result(36924, 0.04, 1, 2, 0.04), -- Sky Sapphire
		Result(36925, 0.03, 1, 2, 0.0305), -- Majestic Zircon
		Result(36926, 0.235, 1, 2, 0.25), -- Shadow Crystal
		Result(36927, 0.04, 1, 2, 0.04), -- Twilight Opal
		Result(36928, 0.03, 1, 2, 0.0305), -- Dreadstone
		Result(36929, 0.235, 1, 2, 0.25), -- Huge Citrine
		Result(36930, 0.04, 1, 2, 0.04), -- Monarch Topaz
		Result(36931, 0.03, 1, 2, 0.0305), -- Ametrine
		Result(36932, 0.235, 1, 2, 0.25), -- Dark Jade
		Result(36933, 0.04, 1, 2, 0.04), -- Forest Emerald
		Result(36934, 0.03, 1, 2, 0.0305), -- Eye of Zul
	})
	SetDefinition(36912, 400, { -- Saronite Ore
		Result(36917, 0.18, 1, 2, 0.1775), -- Bloodstone
		Result(36918, 0.035, 1, 2, 0.0355), -- Scarlet Ruby
		Result(36920, 0.18, 1, 2, 0.1775), -- Sun Crystal
		Result(36921, 0.035, 1, 2, 0.0355), -- Autumn's Glow
		Result(36923, 0.18, 1, 2, 0.1775), -- Chalcedony
		Result(36924, 0.035, 1, 2, 0.0355), -- Sky Sapphire
		Result(36926, 0.18, 1, 2, 0.1775), -- Shadow Crystal
		Result(36927, 0.035, 1, 2, 0.0355), -- Twilight Opal
		Result(36929, 0.18, 1, 2, 0.1775), -- Huge Citrine
		Result(36930, 0.035, 1, 2, 0.0355), -- Monarch Topaz
		Result(36932, 0.18, 1, 2, 0.1775), -- Dark Jade
		Result(36933, 0.035, 1, 2, 0.0355), -- Forest Emerald
	})
	SetDefinition(52183, 500, { -- Pyrite Ore
		Result(52177, 0.165, 1, 1, 0.165), -- Carnelian
		Result(52178, 0.165, 1, 1, 0.165), -- Zephyrite
		Result(52179, 0.165, 1, 1, 0.165), -- Alicite
		Result(52180, 0.165, 1, 1, 0.165), -- Nightstone
		Result(52181, 0.165, 1, 1, 0.165), -- Hessonite
		Result(52182, 0.165, 1, 1, 0.165), -- Jasper
		Result(52190, 0.075, 1, 2, 0.076), -- Inferno Ruby
		Result(52191, 0.075, 1, 2, 0.076), -- Ocean Sapphire
		Result(52192, 0.075, 1, 2, 0.076), -- Dream Emerald
		Result(52193, 0.075, 1, 2, 0.076), -- Ember Topaz
		Result(52194, 0.075, 1, 2, 0.076), -- Demonseye
		Result(52195, 0.075, 1, 2, 0.076), -- Amberjewel
	})
	SetDefinition(52185, 475, { -- Elementium Ore
		Result(52177, 0.18, 1, 2, 0.1825), -- Carnelian
		Result(52178, 0.18, 1, 2, 0.1825), -- Zephyrite
		Result(52179, 0.18, 1, 2, 0.1825), -- Alicite
		Result(52180, 0.18, 1, 2, 0.1825), -- Nightstone
		Result(52181, 0.18, 1, 2, 0.1825), -- Hessonite
		Result(52182, 0.18, 1, 2, 0.1825), -- Jasper
		Result(52190, 0.045, 1, 2, 0.0455), -- Inferno Ruby
		Result(52191, 0.045, 1, 2, 0.0455), -- Ocean Sapphire
		Result(52192, 0.045, 1, 2, 0.0455), -- Dream Emerald
		Result(52193, 0.045, 1, 2, 0.0455), -- Ember Topaz
		Result(52194, 0.045, 1, 2, 0.0455), -- Demonseye
		Result(52195, 0.045, 1, 2, 0.0455), -- Amberjewel
	})
	SetDefinition(53038, 425, { -- Obsidium Ore
		Result(52177, 0.235, 1, 2, 0.25), -- Carnelian
		Result(52178, 0.235, 1, 2, 0.25), -- Zephyrite
		Result(52179, 0.235, 1, 2, 0.25), -- Alicite
		Result(52180, 0.235, 1, 2, 0.25), -- Nightstone
		Result(52181, 0.235, 1, 2, 0.25), -- Hessonite
		Result(52182, 0.235, 1, 2, 0.25), -- Jasper
		Result(52190, 0.0125, 1, 1, 0.0125), -- Inferno Ruby
		Result(52191, 0.0125, 1, 1, 0.0125), -- Ocean Sapphire
		Result(52192, 0.0125, 1, 1, 0.0125), -- Dream Emerald
		Result(52193, 0.0125, 1, 1, 0.0125), -- Ember Topaz
		Result(52194, 0.0125, 1, 1, 0.0125), -- Demonseye
		Result(52195, 0.0125, 1, 1, 0.0125), -- Amberjewel
	})
	SetDefinition(72092, 500, { -- Ghost Iron Ore
		Result(76130, 0.2335, 1, 2, 0.247), -- Tiger Opal
		Result(76131, 0.045, 1, 2, 0.0455), -- Primordial Ruby
		Result(76133, 0.2335, 1, 2, 0.247), -- Lapis Lazuli
		Result(76134, 0.2335, 1, 2, 0.247), -- Sunstone
		Result(76135, 0.2335, 1, 2, 0.247), -- Roguestone
		Result(76136, 0.2335, 1, 2, 0.247), -- Pandarian Garnet
		Result(76137, 0.2335, 1, 2, 0.247), -- Alexandrite
		Result(76138, 0.045, 1, 2, 0.0455), -- River's Heart
		Result(76139, 0.045, 1, 2, 0.0455), -- Wild Jade
		Result(76140, 0.045, 1, 2, 0.0455), -- Vermillion Onyx
		Result(76141, 0.045, 1, 2, 0.0455), -- Imperial Amethyst
		Result(76142, 0.045, 1, 2, 0.0455), -- Sun's Radiance
	})
	SetDefinition(72093, 550, { -- Kyparite
		Result(76130, 0.2335, 1, 2, 0.247), -- Tiger Opal
		Result(76131, 0.045, 1, 2, 0.0455), -- Primordial Ruby
		Result(76133, 0.2335, 1, 2, 0.247), -- Lapis Lazuli
		Result(76134, 0.2335, 1, 2, 0.247), -- Sunstone
		Result(76135, 0.2335, 1, 2, 0.247), -- Roguestone
		Result(76136, 0.2335, 1, 2, 0.247), -- Pandarian Garnet
		Result(76137, 0.2335, 1, 2, 0.247), -- Alexandrite
		Result(76138, 0.045, 1, 2, 0.0455), -- River's Heart
		Result(76139, 0.045, 1, 2, 0.0455), -- Wild Jade
		Result(76140, 0.045, 1, 2, 0.0455), -- Vermillion Onyx
		Result(76141, 0.045, 1, 2, 0.0455), -- Imperial Amethyst
		Result(76142, 0.045, 1, 2, 0.0455), -- Sun's Radiance
	})
	SetDefinition(72094, 600, { -- Black Trillium Ore
		Result(76130, 0.16, 1, 1, 0.1705), -- Tiger Opal
		Result(76131, 0.16, 1, 3, 0.1705), -- Primordial Ruby
		Result(76133, 0.16, 1, 1, 0.1705), -- Lapis Lazuli
		Result(76134, 0.16, 1, 1, 0.1705), -- Sunstone
		Result(76135, 0.16, 1, 1, 0.1705), -- Roguestone
		Result(76136, 0.16, 1, 1, 0.1705), -- Pandarian Garnet
		Result(76137, 0.16, 1, 1, 0.1705), -- Alexandrite
		Result(76138, 0.16, 1, 3, 0.1705), -- River's Heart
		Result(76139, 0.16, 1, 3, 0.1705), -- Wild Jade
		Result(76140, 0.16, 1, 3, 0.1705), -- Vermillion Onyx
		Result(76141, 0.16, 1, 3, 0.1705), -- Imperial Amethyst
		Result(76142, 0.16, 1, 3, 0.1705), -- Sun's Radiance
	})
	SetDefinition(72103, 600, { -- White Trillium Ore
		Result(76130, 0.16, 1, 1, 0.1705), -- Tiger Opal
		Result(76131, 0.16, 1, 3, 0.1705), -- Primordial Ruby
		Result(76133, 0.16, 1, 1, 0.1705), -- Lapis Lazuli
		Result(76134, 0.16, 1, 1, 0.1705), -- Sunstone
		Result(76135, 0.16, 1, 1, 0.1705), -- Roguestone
		Result(76136, 0.16, 1, 1, 0.1705), -- Pandarian Garnet
		Result(76137, 0.16, 1, 1, 0.1705), -- Alexandrite
		Result(76138, 0.16, 1, 3, 0.1705), -- River's Heart
		Result(76139, 0.16, 1, 3, 0.1705), -- Wild Jade
		Result(76140, 0.16, 1, 3, 0.1705), -- Vermillion Onyx
		Result(76141, 0.16, 1, 3, 0.1705), -- Imperial Amethyst
		Result(76142, 0.16, 1, 3, 0.1705), -- Sun's Radiance
	})
end

local function ApplyStandardExtensions()
	-- Replace retained yields and add WoD through Shadowlands sources.
	SetDefinition(2770, 0, { -- Copper Ore
		Result(774, 0.5, 1, 1, 0.5), -- Malachite
		Result(818, 0.5, 1, 1, 0.5), -- Tigerseye
		Result(1210, 0.1, 1, 1, 0.1), -- Shadowgem
	})
	SetDefinition(2771, 0, { -- Tin Ore
		Result(1206, 0.38, 1, 2, 0.4), -- Moss Agate
		Result(1210, 0.38, 1, 2, 0.4), -- Shadowgem
		Result(1529, 0.0325, 1, 1, 0.0325), -- Jade
		Result(1705, 0.38, 1, 2, 0.4), -- Lesser Moonstone
		Result(3864, 0.0325, 1, 1, 0.0325), -- Citrine
		Result(7909, 0.0325, 1, 1, 0.0325), -- Aquamarine
	})
	SetDefinition(2772, 0, { -- Iron Ore
		Result(1529, 0.34, 1, 2, 0.35), -- Jade
		Result(1705, 0.34, 1, 2, 0.35), -- Lesser Moonstone
		Result(3864, 0.38, 1, 2, 0.3925), -- Citrine
		Result(7909, 0.05, 1, 1, 0.05), -- Aquamarine
		Result(7910, 0.05, 1, 1, 0.05), -- Star Ruby
	})
	SetDefinition(3858, 0, { -- Mithril Ore
		Result(3864, 0.36, 1, 2, 0.3725), -- Citrine
		Result(7909, 0.36, 1, 2, 0.3725), -- Aquamarine
		Result(7910, 0.36, 1, 2, 0.3725), -- Star Ruby
		Result(12361, 0.0225, 1, 1, 0.0225), -- Blue Sapphire
		Result(12364, 0.0225, 1, 1, 0.0225), -- Huge Emerald
		Result(12799, 0.0225, 1, 1, 0.0225), -- Large Opal
		Result(12800, 0.0225, 1, 1, 0.0225), -- Azerothian Diamond
	})
	SetDefinition(10620, 0, { -- Thorium Ore
		Result(7910, 0.16, 1, 2, 0.165), -- Star Ruby
		Result(12361, 0.305, 1, 2, 0.33), -- Blue Sapphire
		Result(12364, 0.305, 1, 2, 0.33), -- Huge Emerald
		Result(12799, 0.305, 1, 2, 0.33), -- Large Opal
		Result(12800, 0.305, 1, 2, 0.33), -- Azerothian Diamond
	})
	SetDefinition(23424, 0, { -- Fel Iron Ore
		Result(21929, 0.18, 1, 2, 0.1825), -- Flame Spessarite
		Result(23077, 0.18, 1, 2, 0.1825), -- Blood Garnet
		Result(23079, 0.18, 1, 2, 0.1825), -- Deep Peridot
		Result(23107, 0.18, 1, 2, 0.1825), -- Shadow Draenite
		Result(23112, 0.18, 1, 2, 0.1825), -- Golden Draenite
		Result(23117, 0.18, 1, 2, 0.1825), -- Azure Moonstone
		Result(23436, 0.015, 1, 1, 0.015), -- Living Ruby
		Result(23437, 0.015, 1, 1, 0.015), -- Talasite
		Result(23438, 0.015, 1, 1, 0.015), -- Star of Elune
		Result(23439, 0.015, 1, 1, 0.015), -- Noble Topaz
		Result(23440, 0.015, 1, 1, 0.015), -- Dawnstone
		Result(23441, 0.015, 1, 1, 0.015), -- Nightseye
	})
	SetDefinition(23425, 0, { -- Adamantite Ore
		Result(21929, 0.18, 1, 2, 0.1825), -- Flame Spessarite
		Result(23077, 0.18, 1, 2, 0.1825), -- Blood Garnet
		Result(23079, 0.18, 1, 2, 0.1825), -- Deep Peridot
		Result(23107, 0.18, 1, 2, 0.1825), -- Shadow Draenite
		Result(23112, 0.18, 1, 2, 0.1825), -- Golden Draenite
		Result(23117, 0.18, 1, 2, 0.1825), -- Azure Moonstone
		Result(23436, 0.04, 1, 1, 0.04), -- Living Ruby
		Result(23437, 0.04, 1, 1, 0.04), -- Talasite
		Result(23438, 0.04, 1, 1, 0.04), -- Star of Elune
		Result(23439, 0.04, 1, 1, 0.04), -- Noble Topaz
		Result(23440, 0.04, 1, 1, 0.04), -- Dawnstone
		Result(23441, 0.04, 1, 1, 0.04), -- Nightseye
	})
	SetDefinition(36909, 0, { -- Cobalt Ore
		-- Correct the same decimal-placement anomaly in TSM's Standard data.
		Result(36917, 0.235, 1, 2, 0.25), -- Bloodstone
		Result(36918, 0.015, 1, 2, 0.015), -- Scarlet Ruby
		Result(36920, 0.235, 1, 2, 0.25), -- Sun Crystal
		Result(36921, 0.015, 1, 2, 0.015), -- Autumn's Glow
		Result(36923, 0.235, 1, 2, 0.25), -- Chalcedony
		Result(36924, 0.015, 1, 2, 0.015), -- Sky Sapphire
		Result(36926, 0.235, 1, 2, 0.25), -- Shadow Crystal
		Result(36927, 0.015, 1, 2, 0.015), -- Twilight Opal
		Result(36929, 0.235, 1, 2, 0.25), -- Huge Citrine
		Result(36930, 0.015, 1, 2, 0.015), -- Monarch Topaz
		Result(36932, 0.235, 1, 2, 0.25), -- Dark Jade
		Result(36933, 0.015, 1, 2, 0.015), -- Forest Emerald
	})
	SetDefinition(36910, 0, { -- Titanium Ore
		Result(36917, 0.235, 1, 2, 0.25), -- Bloodstone
		Result(36918, 0.04, 1, 2, 0.0405), -- Scarlet Ruby
		Result(36919, 0.045, 1, 2, 0.0455), -- Cardinal Ruby
		Result(36920, 0.235, 1, 2, 0.25), -- Sun Crystal
		Result(36921, 0.04, 1, 2, 0.0405), -- Autumn's Glow
		Result(36922, 0.045, 1, 2, 0.0455), -- King's Amber
		Result(36923, 0.235, 1, 2, 0.25), -- Chalcedony
		Result(36924, 0.04, 1, 2, 0.0405), -- Sky Sapphire
		Result(36925, 0.045, 1, 2, 0.0455), -- Majestic Zircon
		Result(36926, 0.235, 1, 2, 0.25), -- Shadow Crystal
		Result(36927, 0.04, 1, 2, 0.0405), -- Twilight Opal
		Result(36928, 0.045, 1, 2, 0.0455), -- Dreadstone
		Result(36929, 0.235, 1, 2, 0.25), -- Huge Citrine
		Result(36930, 0.04, 1, 2, 0.0405), -- Monarch Topaz
		Result(36931, 0.045, 1, 2, 0.0455), -- Ametrine
		Result(36932, 0.235, 1, 2, 0.25), -- Dark Jade
		Result(36933, 0.04, 1, 2, 0.0405), -- Forest Emerald
		Result(36934, 0.045, 1, 2, 0.0455), -- Eye of Zul
	})
	SetDefinition(36912, 0, { -- Saronite Ore
		Result(36917, 0.18, 1, 2, 0.1825), -- Bloodstone
		Result(36918, 0.04, 1, 2, 0.0405), -- Scarlet Ruby
		Result(36920, 0.18, 1, 2, 0.1825), -- Sun Crystal
		Result(36921, 0.04, 1, 2, 0.0405), -- Autumn's Glow
		Result(36923, 0.18, 1, 2, 0.1825), -- Chalcedony
		Result(36924, 0.04, 1, 2, 0.0405), -- Sky Sapphire
		Result(36926, 0.18, 1, 2, 0.1825), -- Shadow Crystal
		Result(36927, 0.04, 1, 2, 0.0405), -- Twilight Opal
		Result(36929, 0.18, 1, 2, 0.1825), -- Huge Citrine
		Result(36930, 0.04, 1, 2, 0.0405), -- Monarch Topaz
		Result(36932, 0.18, 1, 2, 0.1825), -- Dark Jade
		Result(36933, 0.04, 1, 2, 0.0405), -- Forest Emerald
	})
	SetDefinition(52183, 0, { -- Pyrite Ore
		Result(52177, 0.165, 1, 1, 0.165), -- Carnelian
		Result(52178, 0.165, 1, 1, 0.165), -- Zephyrite
		Result(52179, 0.165, 1, 1, 0.165), -- Alicite
		Result(52180, 0.165, 1, 1, 0.165), -- Nightstone
		Result(52181, 0.165, 1, 1, 0.165), -- Hessonite
		Result(52182, 0.165, 1, 1, 0.165), -- Jasper
		Result(52190, 0.075, 1, 2, 0.076), -- Inferno Ruby
		Result(52191, 0.075, 1, 2, 0.076), -- Ocean Sapphire
		Result(52192, 0.075, 1, 2, 0.076), -- Dream Emerald
		Result(52193, 0.075, 1, 2, 0.076), -- Ember Topaz
		Result(52194, 0.075, 1, 2, 0.076), -- Demonseye
		Result(52195, 0.075, 1, 2, 0.076), -- Amberjewel
	})
	SetDefinition(52185, 0, { -- Elementium Ore
		Result(52177, 0.18, 1, 2, 0.1825), -- Carnelian
		Result(52178, 0.18, 1, 2, 0.1825), -- Zephyrite
		Result(52179, 0.18, 1, 2, 0.1825), -- Alicite
		Result(52180, 0.18, 1, 2, 0.1825), -- Nightstone
		Result(52181, 0.18, 1, 2, 0.1825), -- Hessonite
		Result(52182, 0.18, 1, 2, 0.1825), -- Jasper
		Result(52190, 0.045, 1, 2, 0.0455), -- Inferno Ruby
		Result(52191, 0.045, 1, 2, 0.0455), -- Ocean Sapphire
		Result(52192, 0.045, 1, 2, 0.0455), -- Dream Emerald
		Result(52193, 0.045, 1, 2, 0.0455), -- Ember Topaz
		Result(52194, 0.045, 1, 2, 0.0455), -- Demonseye
		Result(52195, 0.045, 1, 2, 0.0455), -- Amberjewel
	})
	SetDefinition(53038, 0, { -- Obsidium Ore
		Result(52177, 0.235, 1, 2, 0.25), -- Carnelian
		Result(52178, 0.235, 1, 2, 0.25), -- Zephyrite
		Result(52179, 0.235, 1, 2, 0.25), -- Alicite
		Result(52180, 0.235, 1, 2, 0.25), -- Nightstone
		Result(52181, 0.235, 1, 2, 0.25), -- Hessonite
		Result(52182, 0.235, 1, 2, 0.25), -- Jasper
		Result(52190, 0.0125, 1, 1, 0.0125), -- Inferno Ruby
		Result(52191, 0.0125, 1, 1, 0.0125), -- Ocean Sapphire
		Result(52192, 0.0125, 1, 1, 0.0125), -- Dream Emerald
		Result(52193, 0.0125, 1, 1, 0.0125), -- Ember Topaz
		Result(52194, 0.0125, 1, 1, 0.0125), -- Demonseye
		Result(52195, 0.0125, 1, 1, 0.0125), -- Amberjewel
	})
	SetDefinition(72092, 0, { -- Ghost Iron Ore
		Result(76130, 0.2335, 1, 2, 0.247), -- Tiger Opal
		Result(76131, 0.045, 1, 2, 0.0455), -- Primordial Ruby
		Result(76133, 0.2335, 1, 2, 0.247), -- Lapis Lazuli
		Result(76134, 0.2335, 1, 2, 0.247), -- Sunstone
		Result(76135, 0.2335, 1, 2, 0.247), -- Roguestone
		Result(76136, 0.2335, 1, 2, 0.247), -- Pandarian Garnet
		Result(76137, 0.2335, 1, 2, 0.247), -- Alexandrite
		Result(76138, 0.045, 1, 2, 0.0455), -- River's Heart
		Result(76139, 0.045, 1, 2, 0.0455), -- Wild Jade
		Result(76140, 0.045, 1, 2, 0.0455), -- Vermillion Onyx
		Result(76141, 0.045, 1, 2, 0.0455), -- Imperial Amethyst
		Result(76142, 0.045, 1, 2, 0.0455), -- Sun's Radiance
	})
	SetDefinition(72093, 0, { -- Kyparite
		Result(76130, 0.2335, 1, 2, 0.247), -- Tiger Opal
		Result(76131, 0.045, 1, 2, 0.0455), -- Primordial Ruby
		Result(76133, 0.2335, 1, 2, 0.247), -- Lapis Lazuli
		Result(76134, 0.2335, 1, 2, 0.247), -- Sunstone
		Result(76135, 0.2335, 1, 2, 0.247), -- Roguestone
		Result(76136, 0.2335, 1, 2, 0.247), -- Pandarian Garnet
		Result(76137, 0.2335, 1, 2, 0.247), -- Alexandrite
		Result(76138, 0.045, 1, 2, 0.0455), -- River's Heart
		Result(76139, 0.045, 1, 2, 0.0455), -- Wild Jade
		Result(76140, 0.045, 1, 2, 0.0455), -- Vermillion Onyx
		Result(76141, 0.045, 1, 2, 0.0455), -- Imperial Amethyst
		Result(76142, 0.045, 1, 2, 0.0455), -- Sun's Radiance
	})
	SetDefinition(72094, 0, { -- Black Trillium Ore
		Result(76130, 0.16, 1, 1, 0.1705), -- Tiger Opal
		Result(76131, 0.16, 1, 3, 0.1705), -- Primordial Ruby
		Result(76133, 0.16, 1, 1, 0.1705), -- Lapis Lazuli
		Result(76134, 0.16, 1, 1, 0.1705), -- Sunstone
		Result(76135, 0.16, 1, 1, 0.1705), -- Roguestone
		Result(76136, 0.16, 1, 1, 0.1705), -- Pandarian Garnet
		Result(76137, 0.16, 1, 1, 0.1705), -- Alexandrite
		Result(76138, 0.16, 1, 3, 0.1705), -- River's Heart
		Result(76139, 0.16, 1, 3, 0.1705), -- Wild Jade
		Result(76140, 0.16, 1, 3, 0.1705), -- Vermillion Onyx
		Result(76141, 0.16, 1, 3, 0.1705), -- Imperial Amethyst
		Result(76142, 0.16, 1, 3, 0.1705), -- Sun's Radiance
	})
	SetDefinition(72103, 0, { -- White Trillium Ore
		Result(76130, 0.16, 1, 1, 0.1705), -- Tiger Opal
		Result(76131, 0.16, 1, 3, 0.1705), -- Primordial Ruby
		Result(76133, 0.16, 1, 1, 0.1705), -- Lapis Lazuli
		Result(76134, 0.16, 1, 1, 0.1705), -- Sunstone
		Result(76135, 0.16, 1, 1, 0.1705), -- Roguestone
		Result(76136, 0.16, 1, 1, 0.1705), -- Pandarian Garnet
		Result(76137, 0.16, 1, 1, 0.1705), -- Alexandrite
		Result(76138, 0.16, 1, 3, 0.1705), -- River's Heart
		Result(76139, 0.16, 1, 3, 0.1705), -- Wild Jade
		Result(76140, 0.16, 1, 3, 0.1705), -- Vermillion Onyx
		Result(76141, 0.16, 1, 3, 0.1705), -- Imperial Amethyst
		Result(76142, 0.16, 1, 3, 0.1705), -- Sun's Radiance
	})
	SetDefinition(123918, 0, { -- Leystone Ore
		Result(130172, 0.05, 1, 2, 0.05), -- Sangrite
		Result(130173, 0.05, 1, 2, 0.05), -- Deep Amber
		Result(130174, 0.05, 1, 2, 0.05), -- Azsunite
		Result(130175, 0.05, 1, 2, 0.05), -- Chaotic Spinel
		Result(130176, 0.05, 1, 2, 0.05), -- Skystone
		Result(130177, 0.05, 1, 2, 0.05), -- Queen's Opal
		Result(130178, 0.01, 1, 1, 0.01), -- FuryStone
		Result(130179, 0.01, 1, 1, 0.01), -- Eye of Prophecy
		Result(130180, 0.01, 1, 1, 0.01), -- Dawnlight
		Result(130181, 0.01, 1, 1, 0.01), -- Pandemonite
		Result(130182, 0.01, 1, 1, 0.01), -- Maelstrom Sapphire
		Result(130183, 0.01, 1, 1, 0.01), -- Shadowruby
	})
	SetDefinition(123919, 0, { -- Felslate
		Result(130172, 0.05, 2, 5, 0.175), -- Sangrite
		Result(130173, 0.05, 2, 5, 0.175), -- Deep Amber
		Result(130174, 0.05, 2, 5, 0.175), -- Azsunite
		Result(130175, 0.05, 2, 5, 0.175), -- Chaotic Spinel
		Result(130176, 0.05, 2, 5, 0.175), -- Skystone
		Result(130177, 0.05, 2, 5, 0.175), -- Queen's Opal
		Result(130178, 0.01, 2, 5, 0.01), -- FuryStone
		Result(130179, 0.01, 2, 5, 0.01), -- Eye of Prophecy
		Result(130180, 0.01, 2, 5, 0.01), -- Dawnlight
		Result(130181, 0.01, 2, 5, 0.01), -- Pandemonite
		Result(130182, 0.01, 2, 5, 0.01), -- Maelstrom Sapphire
		Result(130183, 0.01, 2, 5, 0.01), -- Shadowruby
	})
	SetDefinition(151564, 0, { -- Empyrium
		Result(151579, 0.03, 1, 1, 0.03), -- Labradorite
		Result(151718, 0.03, 1, 1, 0.03), -- Argulite
		Result(151719, 0.03, 1, 1, 0.03), -- Lightsphene
		Result(151720, 0.03, 1, 1, 0.03), -- Chemirine
		Result(151721, 0.03, 1, 1, 0.03), -- Hesselian
		Result(151722, 0.03, 1, 1, 0.03), -- Florid Malachite
	})
	SetDefinition(152512, 0, { -- Monelite Ore
		Result(153700, 0.18, 1, 4, 0.275), -- Golden Beryl
		Result(153701, 0.18, 1, 4, 0.275), -- Rubellite
		Result(153702, 0.18, 1, 4, 0.275), -- Kubiline
		Result(153703, 0.18, 1, 4, 0.275), -- Solstone
		Result(153704, 0.18, 1, 4, 0.275), -- Viridium
		Result(153705, 0.18, 1, 4, 0.275), -- Kyanite
		Result(153706, 0.04, 1, 1, 0.04), -- Kraken's Eye
		Result(154120, 0.0425, 1, 2, 0.043), -- Owlseye
		Result(154121, 0.0425, 1, 2, 0.043), -- Scarlet Diamond
		Result(154122, 0.0425, 1, 2, 0.043), -- Tidal Amethyst
		Result(154123, 0.0425, 1, 2, 0.043), -- Amberblaze
		Result(154124, 0.0425, 1, 2, 0.043), -- Laribole
		Result(154125, 0.0425, 1, 2, 0.043), -- Royal Quartz
	})
	SetDefinition(152513, 0, { -- Platinum Ore
		Result(153700, 0.21, 1, 4, 0.33), -- Golden Beryl
		Result(153701, 0.21, 1, 4, 0.33), -- Rubellite
		Result(153702, 0.21, 1, 4, 0.33), -- Kubiline
		Result(153703, 0.21, 1, 4, 0.33), -- Solstone
		Result(153704, 0.21, 1, 4, 0.33), -- Viridium
		Result(153705, 0.21, 1, 4, 0.33), -- Kyanite
		Result(153706, 0.045, 1, 1, 0.045), -- Kraken's Eye
		Result(154120, 0.115, 1, 2, 0.1185), -- Owlseye
		Result(154121, 0.115, 1, 2, 0.1185), -- Scarlet Diamond
		Result(154122, 0.115, 1, 2, 0.1185), -- Tidal Amethyst
		Result(154123, 0.115, 1, 2, 0.1185), -- Amberblaze
		Result(154124, 0.115, 1, 2, 0.1185), -- Laribole
		Result(154125, 0.115, 1, 2, 0.1185), -- Royal Quartz
	})
	SetDefinition(152579, 0, { -- Storm Silver Ore
		Result(153700, 0.195, 1, 4, 0.301), -- Golden Beryl
		Result(153701, 0.195, 1, 4, 0.301), -- Rubellite
		Result(153702, 0.195, 1, 4, 0.301), -- Kubiline
		Result(153703, 0.195, 1, 4, 0.301), -- Solstone
		Result(153704, 0.195, 1, 4, 0.301), -- Viridium
		Result(153705, 0.195, 1, 4, 0.301), -- Kyanite
		Result(153706, 0.04, 1, 1, 0.04), -- Kraken's Eye
		Result(154120, 0.075, 1, 2, 0.076), -- Owlseye
		Result(154121, 0.075, 1, 2, 0.076), -- Scarlet Diamond
		Result(154122, 0.075, 1, 2, 0.076), -- Tidal Amethyst
		Result(154123, 0.075, 1, 2, 0.076), -- Amberblaze
		Result(154124, 0.075, 1, 2, 0.076), -- Laribole
		Result(154125, 0.075, 1, 2, 0.076), -- Royal Quartz
	})
	SetDefinition(168185, 0, { -- Osmenite Ore
		Result(168188, 0.165, 1, 1, 0.165), -- Sage Agate
		Result(168189, 0.165, 1, 1, 0.165), -- Dark Opal
		Result(168190, 0.165, 1, 1, 0.165), -- Lava Lazuli
		Result(168191, 0.165, 1, 1, 0.165), -- Sea Currant
		Result(168192, 0.165, 1, 1, 0.165), -- Sand Spinel
		Result(168193, 0.165, 1, 1, 0.165), -- Azsharine
		Result(168635, 0.15, 1, 1, 0.15), -- Leviathan's Eye
	})
	SetDefinition(171828, 0, { -- Laestrite Ore
		Result(173108, 0.3333, 1, 2, 0.5), -- Oriblase
		Result(173109, 0.3333, 1, 2, 0.5), -- Angerseye
		Result(173110, 0.3333, 1, 2, 0.5), -- Umbryl
		Result(173170, 0.0265, 1, 2, 0.04), -- Essence of Rebirth
		Result(173171, 0.0265, 1, 2, 0.04), -- Essence of Torment
		Result(173172, 0.0265, 1, 2, 0.04), -- Essence of Servitude
		Result(173173, 0.0265, 1, 2, 0.04), -- Essence of Valor
	})
	SetDefinition(171829, 0, { -- Solenium Ore
		Result(173108, 0.3333, 1, 2, 0.5), -- Oriblase
		Result(173109, 0.3333, 1, 2, 0.5), -- Angerseye
		Result(173110, 0.3333, 1, 2, 0.5), -- Umbryl
		Result(173173, 0.215, 1, 2, 0.3225), -- Essence of Valor
	})
	SetDefinition(171830, 0, { -- Oxxein Ore
		Result(173108, 0.3333, 1, 2, 0.5), -- Oriblase
		Result(173109, 0.3333, 1, 2, 0.5), -- Angerseye
		Result(173110, 0.3333, 1, 2, 0.5), -- Umbryl
		Result(173172, 0.215, 1, 2, 0.3225), -- Essence of Servitude
	})
	SetDefinition(171831, 0, { -- Phaedrum Ore
		Result(173108, 0.3333, 1, 2, 0.5), -- Oriblase
		Result(173109, 0.3333, 1, 2, 0.5), -- Angerseye
		Result(173110, 0.3333, 1, 2, 0.5), -- Umbryl
		Result(173170, 0.215, 1, 2, 0.3225), -- Essence of Rebirth
	})
	SetDefinition(171832, 0, { -- Sinvyr Ore
		Result(173108, 0.3333, 1, 2, 0.5), -- Oriblase
		Result(173109, 0.3333, 1, 2, 0.5), -- Angerseye
		Result(173110, 0.3333, 1, 2, 0.5), -- Umbryl
		Result(173171, 0.215, 1, 2, 0.3225), -- Essence of Torment
	})
	SetDefinition(171833, 0, { -- Elethium Ore
		Result(173108, 0.3333, 2, 4, 1), -- Oriblase
		Result(173109, 0.3333, 2, 4, 1), -- Angerseye
		Result(173110, 0.3333, 2, 4, 1), -- Umbryl
		Result(173170, 0.255, 1, 2, 0.3825), -- Essence of Rebirth
		Result(173171, 0.255, 1, 2, 0.3825), -- Essence of Torment
		Result(173172, 0.255, 1, 2, 0.3825), -- Essence of Servitude
		Result(173173, 0.255, 1, 2, 0.3825), -- Essence of Valor
	})
end

AddMistsBaseline()
if isStandard then
	ApplyStandardExtensions()
end

addon:GetModule("MaterialBreakdownData"):InitializeDataModule(module, "prospectData", definitions)