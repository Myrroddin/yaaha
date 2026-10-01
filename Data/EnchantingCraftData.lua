-- Maps enchanting recipe spell IDs to the tangible items those recipes create.

local LibStub = LibStub
local WOW_PROJECT_BURNING_CRUSADE_CLASSIC = WOW_PROJECT_BURNING_CRUSADE_CLASSIC
local WOW_PROJECT_ID = WOW_PROJECT_ID
local WOW_PROJECT_MISTS_CLASSIC = WOW_PROJECT_MISTS_CLASSIC
local WOW_PROJECT_WRATH_CLASSIC = WOW_PROJECT_WRATH_CLASSIC

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local module = addon:NewModule("EnchantingCraftData")

local isTBC = WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC
local isMists = WOW_PROJECT_ID == WOW_PROJECT_MISTS_CLASSIC
local isWrath = WOW_PROJECT_ID == WOW_PROJECT_WRATH_CLASSIC

-- Enchanting APIs identify both equipment enchants and recipes which create
-- tangible items by spell. These stable spell-to-item mappings distinguish the
-- latter without depending on the client's transient item cache.
-- [recipeSpellID] = craftedItemID
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

-- Forever replaces one Classic recipe and adds tangible enchanting products.
if addon.IsForever then
	craftedItems[14810] = nil -- Greater Mystic Wand (item 11290)

	craftedItems[439134] = 217287 -- Greater Mystic Wand
	craftedItems[439156] = 217308 -- Enchanted Sigil: Innovation
	craftedItems[448624] = 220792 -- Scroll of Spatial Mending
	craftedItems[463866] = 228978 -- Enchanted Sigil: Flowing Waters
	craftedItems[463869] = 228980 -- Conductive Shield Coating
	craftedItems[471400] = 232611 -- Magnificent Trollshine
	craftedItems[1230643] = 279976 -- Enchanted Lute
	craftedItems[1245320] = 247786 -- Mote of Magic
	craftedItems[1245321] = 247789 -- Novice's Practice Wand
	craftedItems[1248461] = 249144 -- Twisted Nether Wand
	craftedItems[1248505] = 249232 -- Lesser Eternal Wand
	craftedItems[1248509] = 249234 -- Dreambough Wand
	craftedItems[1248515] = 249237 -- Greater Eternal Wand
	craftedItems[1248650] = 249385 -- Brilliant Wand
	craftedItems[1248703] = 249392 -- Glimmering Staff
	craftedItems[1248739] = 249393 -- Soulstaff
	craftedItems[1248745] = 249394 -- Orb of Mystic Insight
	craftedItems[1248748] = 249395 -- Orb of Souls
	craftedItems[1248752] = 249396 -- Mystic Mushroom
	craftedItems[1248754] = 249397 -- Tenets of the Silver Hand
	craftedItems[1248755] = 249398 -- Polished Driftwood Icon
	craftedItems[1248974] = 249441 -- Talons of Wrath
	craftedItems[1249006] = 249442 -- Libram of Invocation
	craftedItems[1249015] = 249443 -- Totem of Ancestral Protection
	craftedItems[1249061] = 249453 -- Radiant Staff
	craftedItems[1249064] = 249454 -- Dreamstaff
	craftedItems[1249069] = 249455 -- Truesilver Conduit
	craftedItems[1249070] = 249456 -- Twisting Essence Jar
	craftedItems[1249107] = 249469 -- Frozen Heart of the Mountain
	craftedItems[1249112] = 249470 -- Molten Heart of the Mountain
	craftedItems[1249114] = 249473 -- Dormant Heart of the Mountain
	craftedItems[1249128] = 220606 -- Idol of the Dream
	craftedItems[1249152] = 228175 -- Libram of Holy Alacrity
	craftedItems[1249154] = 228176 -- Totem of Thunder
	craftedItems[1263056] = 279985 -- Arcane Salvager
	craftedItems[1263082] = 279987 -- Arcane Forge
	craftedItems[1306520] = 279246 -- Torch of Light
	craftedItems[1306521] = 279247 -- Steadfast Libram
	craftedItems[1306522] = 279248 -- Libram of Infusion
	craftedItems[1306523] = 279249 -- Totem of Urgency
	craftedItems[1306524] = 279250 -- Idol of Swiftness
	craftedItems[1306525] = 279251 -- Idol of the Ursine Twins
end

-- Add tangible items introduced in The Burning Crusade.
if isTBC or isWrath or isMists then
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
-- EnchantingScrollData module because they additionally require vellums.
if isWrath or isMists then
	craftedItems[60619] = 44452 -- Runed Titanium Rod
end

-- Mists Classic incorporates both Cataclysm and Mists changes. Equipment
-- enchant scrolls are not direct recipe products and remain outside this map.
if isMists then
	-- Recipes removed before Mists Classic.
	craftedItems[7795] = nil -- Runed Silver Rod (item 6339)
	craftedItems[13628] = nil -- Runed Golden Rod (item 11130)
	craftedItems[13702] = nil -- Runed Truesilver Rod (item 11145)
	craftedItems[17180] = nil -- Enchanted Thorium Bar (item 12655)
	craftedItems[20051] = nil -- Runed Arcanite Rod (item 16207)
	craftedItems[28021] = nil -- Arcane Dust (item 22445)
	craftedItems[28022] = nil -- Large Prismatic Shard (item 22449)
	craftedItems[32664] = nil -- Runed Fel Iron Rod (item 22461)
	craftedItems[32665] = nil -- Runed Adamantite Rod (item 22462)
	craftedItems[32667] = nil -- Runed Eternium Rod (item 22463)
	craftedItems[42613] = nil -- Nexus Transformation (item 22448)
	craftedItems[42615] = nil -- Small Prismatic Shard (item 22448)
	craftedItems[45765] = nil -- Void Shatter (item 22449)
	craftedItems[60619] = nil -- Runed Titanium Rod (item 44452)

	-- Tangible products introduced in Cataclysm.
	craftedItems[93841] = 67274 -- Enchanted Lantern
	craftedItems[93843] = 67275 -- Magic Lamp
	craftedItems[104698] = 52721 -- Heavenly Shard (Maelstrom Shatter)

	-- Tangible products introduced in Mists of Pandaria.
	craftedItems[116499] = 74248 -- Sha Crystal
	craftedItems[118237] = 74249 -- Spirit Dust (Mysterious Diffusion)
end

function module:GetCraftedItem(spellID)
	return craftedItems[spellID]
end