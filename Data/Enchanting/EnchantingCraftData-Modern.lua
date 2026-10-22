-- Maps Mists and Standard enchanting recipe spell IDs to tangible crafted items.

local LibStub = LibStub

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local isStandard = addon.isStandard
local module = addon:NewModule("EnchantingCraftData")

-- Mists is a complete Vanilla-through-Mists baseline rather than an extension
-- of the Classic-family table. Standard applies confirmed changes to it.
-- [recipeSpellID] = craftedItemID
local craftedItems = {
	[7421] = 6218, -- Runed Copper Rod
	[14293] = 11287, -- Lesser Magic Wand
	[14807] = 11288, -- Greater Magic Wand
	[14809] = 11289, -- Lesser Mystic Wand
	[14810] = 11290, -- Greater Mystic Wand
	[15596] = 11811, -- Smoking Heart of the Mountain
	[17181] = 12810, -- Enchanted Leather
	[25124] = 20744, -- Minor Wizard Oil
	[25125] = 20745, -- Minor Mana Oil
	[25126] = 20746, -- Lesser Wizard Oil
	[25127] = 20747, -- Lesser Mana Oil
	[25128] = 20750, -- Wizard Oil
	[25129] = 20749, -- Brilliant Wizard Oil
	[25130] = 20748, -- Brilliant Mana Oil
	[28016] = 22521, -- Superior Mana Oil
	[28019] = 22522, -- Superior Wizard Oil
	[28027] = 22460, -- Prismatic Sphere
	[28028] = 22459, -- Void Sphere

	-- Cataclysm products in the Mists client.
	[93841] = 67274, -- Enchanted Lantern
	[93843] = 67275, -- Magic Lamp
	[104698] = 52721, -- Heavenly Shard (Maelstrom Shatter)

	-- Mists of Pandaria products.
	[116499] = 74248, -- Sha Crystal
	[118237] = 74249, -- Spirit Dust (Mysterious Diffusion)
}

if isStandard then
	-- Standard's profession API supplies recipe output item IDs directly. Keep
	-- this inherited map as a fallback and amend it only with confirmed changes.
end

function module:GetCraftedItem(spellID)
	return craftedItems[spellID]
end