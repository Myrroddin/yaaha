local LibStub = LibStub
local WOW_PROJECT_BURNING_CRUSADE_CLASSIC = WOW_PROJECT_BURNING_CRUSADE_CLASSIC
local WOW_PROJECT_ID = WOW_PROJECT_ID
local WOW_PROJECT_WRATH_CLASSIC = WOW_PROJECT_WRATH_CLASSIC

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local module = addon:NewModule("EnchantingCraftData")

local isTBC = WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC
local isWrath = WOW_PROJECT_ID == WOW_PROJECT_WRATH_CLASSIC

-- The Classic Craft API returns enchant hyperlinks for both equipment enchants
-- and recipes which create tangible items. These stable spell-to-item mappings
-- distinguish the latter without depending on the client's transient item cache.
local craftedItems = {
	[7421] = 6218, -- Runed Copper Rod
	[7795] = 6339, -- Runed Silver Rod
	[13628] = 11130, -- Runed Golden Rod
	[13702] = 11145, -- Runed Truesilver Rod
	[14293] = 11287, -- Lesser Magic Wand
	[14807] = 11288, -- Greater Magic Wand
	[14809] = 11289, -- Lesser Mystic Wand
	[14810] = 11290, -- Greater Mystic Wand
	[15596] = 11811, -- Smoking Heart of the Mountain
	[17180] = 12655, -- Enchanted Thorium Bar
	[17181] = 12810, -- Enchanted Leather
	[20051] = 16207, -- Runed Arcanite Rod
	[25124] = 20744, -- Minor Wizard Oil
	[25125] = 20745, -- Minor Mana Oil
	[25126] = 20746, -- Lesser Wizard Oil
	[25127] = 20747, -- Lesser Mana Oil
	[25128] = 20750, -- Wizard Oil
	[25129] = 20749, -- Brilliant Wizard Oil
	[25130] = 20748, -- Brilliant Mana Oil
}

-- Add tangible items introduced in The Burning Crusade.
if isTBC or isWrath then
	craftedItems[28016] = 22521 -- Superior Mana Oil
	craftedItems[28019] = 22522 -- Superior Wizard Oil
	craftedItems[28021] = 22445 -- Arcane Dust
	craftedItems[28022] = 22449 -- Large Prismatic Shard
	craftedItems[28027] = 22460 -- Prismatic Sphere
	craftedItems[28028] = 22459 -- Void Sphere
	craftedItems[32664] = 22461 -- Runed Fel Iron Rod
	craftedItems[32665] = 22462 -- Runed Adamantite Rod
	craftedItems[32667] = 22463 -- Runed Eternium Rod
	craftedItems[42613] = 22448 -- Nexus Transformation
	craftedItems[42615] = 22448 -- Small Prismatic Shard
	craftedItems[45765] = 22449 -- Void Shatter
end

-- Wrath equipment-enchant scrolls remain in the separate Wrath-only
-- EnchantingData module because they additionally require vellums.
if isWrath then
	craftedItems[60619] = 44452 -- Runed Titanium Rod
end

function module:GetCraftedItem(spellID)
	return craftedItems[spellID]
end