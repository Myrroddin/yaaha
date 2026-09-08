local LibStub = LibStub
local WOW_PROJECT_BURNING_CRUSADE_CLASSIC = WOW_PROJECT_BURNING_CRUSADE_CLASSIC
local WOW_PROJECT_ID = WOW_PROJECT_ID
local WOW_PROJECT_WRATH_CLASSIC = WOW_PROJECT_WRATH_CLASSIC

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local module = addon:NewModule("ConvertData")

local isTBC = WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC
local isWrath = WOW_PROJECT_ID == WOW_PROJECT_WRATH_CLASSIC

-- Each keyed material can be obtained from the nested source material. The
-- quantity is how much of that source is required for one unit of the key.
-- Keeping the target as the outer key makes later cost calculations read as
-- "cost this material using these alternatives."
local conversions = {
	[10939] = { [10938] = 3 }, -- Greater Magic Essence from Lesser Magic Essence
	[10938] = { [10939] = 1 / 3 }, -- Lesser Magic Essence from Greater Magic Essence
	[11082] = { [10998] = 3 }, -- Greater Astral Essence from Lesser Astral Essence
	[10998] = { [11082] = 1 / 3 }, -- Lesser Astral Essence from Greater Astral Essence
	[11135] = { [11134] = 3 }, -- Greater Mystic Essence from Lesser Mystic Essence
	[11134] = { [11135] = 1 / 3 }, -- Lesser Mystic Essence from Greater Mystic Essence
	[11175] = { [11174] = 3 }, -- Greater Nether Essence from Lesser Nether Essence
	[11174] = { [11175] = 1 / 3 }, -- Lesser Nether Essence from Greater Nether Essence
	[16203] = { [16202] = 3 }, -- Greater Eternal Essence from Lesser Eternal Essence
	[16202] = { [16203] = 1 / 3 }, -- Lesser Eternal Essence from Greater Eternal Essence
}

-- Add conversions introduced in The Burning Crusade.
if isTBC or isWrath then
	conversions[22446] = { [22447] = 3 } -- Greater Planar Essence from Lesser Planar Essence
	conversions[22447] = { [22446] = 1 / 3 } -- Lesser Planar Essence from Greater Planar Essence
end

-- Add conversions introduced in Wrath of the Lich King.
if isWrath then
	conversions[34055] = { [34056] = 3 } -- Greater Cosmic Essence from Lesser Cosmic Essence
	conversions[34056] = { [34055] = 1 / 3 } -- Lesser Cosmic Essence from Greater Cosmic Essence
	conversions[34052] = { [34053] = 3 } -- Dream Shard from Small Dream Shard
	conversions[34053] = { [34052] = 1 / 3 } -- Small Dream Shard from Dream Shard
end

function module:GetConversions(itemID)
	return conversions[itemID]
end