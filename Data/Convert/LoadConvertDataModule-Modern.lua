-- Loads Mists and Standard deterministic conversion definitions into ConvertData.

local LibStub = LibStub
local pairs = pairs

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local isStandard = addon.isStandard
local module = addon:GetModule("ConvertData")

local MISTS_COMMON_INKS = { 37101, 39469, 39774, 43116, 43118, 43120, 43122, 43124, 43126, 61978 }
local MISTS_RARE_INKS = { 43127, 61981, 79255 }
local STANDARD_COMMON_INKS = {
	39469, 39774, 43116, 43118, 43120, 43122, 43124, 43126, 61978,
	79254, 113111, 129032, 129034, 158187, 158188, 168663,
}
local STANDARD_RARE_INKS = { 43125, 43127, 61981, 79255, 158189 }

local function AddInkTrades(currencyItemID, commonInks, rareInks)
	for index = 1, #commonInks do
		module:AddConversion(commonInks[index], currencyItemID, 1)
	end
	for index = 1, #rareInks do
		module:AddConversion(rareInks[index], currencyItemID, 10)
	end
end

local function RemoveInkTrades(currencyItemID, commonInks, rareInks)
	for index = 1, #commonInks do
		module:RemoveConversion(commonInks[index], currencyItemID)
	end
	for index = 1, #rareInks do
		module:RemoveConversion(rareInks[index], currencyItemID)
	end
end

local function AddMistsBaseline()
	-- Mists is a complete Vanilla-through-Mists baseline using the conversions
	-- current in the Mists client. It does not inherit Classic-family tables.
	module:AddConversion(33568, 33567, 5, true) -- Borean Leather from Scraps
	module:AddConversion(2318, 2934, 3, true) -- Light Leather from Ruined Leather Scraps
	module:AddConversion(21887, 25649, 5, true) -- Knothide Leather from Scraps
	module:AddConversion(52976, 52977, 5, true) -- Savage Leather from Scraps
	module:AddConversion(72120, 72162, 5, true) -- Mist-Touched Leather from Sha-Touched Leather

	module:AddReversibleConversion(10939, 10938, 3) -- Greater/Lesser Magic Essence
	module:AddReversibleConversion(11082, 10998, 3) -- Greater/Lesser Astral Essence
	module:AddReversibleConversion(11135, 11134, 3) -- Greater/Lesser Mystic Essence
	module:AddReversibleConversion(11175, 11174, 3) -- Greater/Lesser Nether Essence
	module:AddReversibleConversion(16203, 16202, 3) -- Greater/Lesser Eternal Essence
	module:AddReversibleConversion(22446, 22447, 3) -- Greater/Lesser Planar Essence
	module:AddReversibleConversion(34055, 34056, 3) -- Greater/Lesser Cosmic Essence
	module:AddReversibleConversion(52719, 52718, 3) -- Greater/Lesser Celestial Essence

	module:AddConversion(34052, 34053, 3) -- Dream Shard from Small Dream Shards
	module:AddConversion(52721, 52720, 3) -- Heavenly Shard from Small Heavenly Shards
	module:AddConversion(74247, 74252, 3) -- Ethereal Shard from Small Ethereal Shards
	module:AddConversion(74248, 105718, 3) -- Sha Crystal from Fragments

	module:AddConversion(21885, 22578, 10) -- Primal Water from Motes
	module:AddConversion(22456, 22577, 10) -- Primal Shadow from Motes
	module:AddConversion(22457, 22576, 10) -- Primal Mana from Motes
	module:AddConversion(21886, 22575, 10) -- Primal Life from Motes
	module:AddConversion(21884, 22574, 10) -- Primal Fire from Motes
	module:AddConversion(22452, 22573, 10) -- Primal Earth from Motes
	module:AddConversion(22451, 22572, 10) -- Primal Air from Motes
	module:AddReversibleConversion(35623, 37700, 10) -- Eternal/Crystallized Air
	module:AddReversibleConversion(35624, 37701, 10) -- Eternal/Crystallized Earth
	module:AddReversibleConversion(36860, 37702, 10) -- Eternal/Crystallized Fire
	module:AddReversibleConversion(35627, 37703, 10) -- Eternal/Crystallized Shadow
	module:AddReversibleConversion(35625, 37704, 10) -- Eternal/Crystallized Life
	module:AddReversibleConversion(35622, 37705, 10) -- Eternal/Crystallized Water

	module:AddConversion(72092, 97512, 10) -- Ghost Iron Ore from Nuggets
	module:AddConversion(72093, 97546, 10) -- Kyparite from Nuggets
	module:AddConversion(72234, 97619, 10) -- Green Tea Leaf from Torn Leaves
	module:AddConversion(79010, 97622, 10) -- Snow Lily from Petals
	module:AddConversion(79011, 97623, 10) -- Fool's Cap from Spores
	module:AddConversion(72237, 97620, 10) -- Rain Poppy from Petals
	module:AddConversion(72235, 97621, 10) -- Silkweed from Stems
	module:AddConversion(89639, 97624, 10) -- Desecrated Herb from Pods
	module:AddConversion(76061, 89112, 10) -- Spirit of Harmony from Motes
	module:AddConversion(76734, 90407, 10) -- Serpent's Eye from Sparkling Shards
	module:AddConversion(90636, 90637, 10) -- Darkmoon Card from Splinters of Hate

	-- Ink Traders exchange Ink of Dreams for common inks at one-for-one,
	-- or ten Ink of Dreams for one rare ink.
	AddInkTrades(79254, MISTS_COMMON_INKS, MISTS_RARE_INKS)
end

local function AddStandardExtensions()
	-- Standard replaces Mists' Ink of Dreams exchanges rather than retaining
	-- both generations of Ink Trader currency.
	RemoveInkTrades(79254, MISTS_COMMON_INKS, MISTS_RARE_INKS)

	-- These three older essence conversions no longer exist in Standard.
	module:RemoveConversion(11082, 10998)
	module:RemoveConversion(10998, 11082)
	module:RemoveConversion(11135, 11134)
	module:RemoveConversion(11134, 11135)
	module:RemoveConversion(11175, 11174)
	module:RemoveConversion(11174, 11175)

	module:AddReversibleConversion(156930, 16204, 3) -- Rich/Light Illusion Dust
	module:AddConversion(111245, 115502, 10) -- Luminous Shard from Fragments
	module:AddConversion(113588, 115504, 10) -- Temporal Crystal from Fragments
	module:AddReversibleConversion(190324, 190322, 10) -- Awakened/Rousing Order
	module:AddReversibleConversion(190327, 190326, 10) -- Awakened/Rousing Air
	module:AddReversibleConversion(190321, 190320, 10) -- Awakened/Rousing Fire
	module:AddReversibleConversion(190331, 190330, 10) -- Awakened/Rousing Decay
	module:AddReversibleConversion(190329, 190328, 10) -- Awakened/Rousing Frost
	module:AddReversibleConversion(190316, 190315, 10) -- Awakened/Rousing Earth
	module:AddReversibleConversion(190450, 190451, 10) -- Awakened/Rousing Ire
	module:AddConversion(110609, 110610, 10, true) -- Raw Beast Hide from Scraps
	module:AddConversion(52979, 112156, 10, true) -- Blackened Dragonscale from Fragments
	module:AddConversion(52982, 112155, 10, true) -- Deepsea Scale from Fragments
	module:AddConversion(79101, 112157, 10, true) -- Prismatic Scale from Fragments
	module:AddConversion(38557, 112158, 10, true) -- Icy Dragonscale from Fragments
	module:AddConversion(38558, 112177, 10, true) -- Nerubian Chitin from Fragments
	module:AddConversion(38561, 112178, 10, true) -- Jormungar Scale from Fragments
	module:AddConversion(25708, 112179, 10, true) -- Thick Clefthoof Leather from Patches
	module:AddConversion(25699, 112180, 10, true) -- Crystal-Infused Leather from Patches
	module:AddConversion(25700, 112181, 10, true) -- Fel Scales from Fragments
	module:AddConversion(25707, 112182, 10, true) -- Fel Hide from Patches
	module:AddConversion(29548, 112183, 10, true) -- Nether Dragonscales from Fragments
	module:AddConversion(29539, 112184, 10, true) -- Cobra Scales from Fragments
	module:AddConversion(29547, 112185, 10, true) -- Wind Scales from Fragments

	module:AddConversion(109137, 111601, 1 / 4) -- Crescent Saberfish Flesh from Enormous fish
	module:AddConversion(109137, 111595, 1 / 2) -- Crescent Saberfish Flesh from normal fish
	module:AddConversion(109137, 111589, 1) -- Crescent Saberfish Flesh from Small fish
	module:AddConversion(109138, 111676, 1 / 4) -- Jawless Skulker Flesh from Enormous fish
	module:AddConversion(109138, 111669, 1 / 2) -- Jawless Skulker Flesh from normal fish
	module:AddConversion(109138, 111650, 1) -- Jawless Skulker Flesh from Small fish
	module:AddConversion(109139, 111675, 1 / 4) -- Fat Sleeper Flesh from Enormous fish
	module:AddConversion(109139, 111668, 1 / 2) -- Fat Sleeper Flesh from normal fish
	module:AddConversion(109139, 111651, 1) -- Fat Sleeper Flesh from Small fish
	module:AddConversion(109140, 111674, 1 / 4) -- Blind Lake Sturgeon Flesh from Enormous fish
	module:AddConversion(109140, 111667, 1 / 2) -- Blind Lake Sturgeon Flesh from normal fish
	module:AddConversion(109140, 111652, 1) -- Blind Lake Sturgeon Flesh from Small fish
	module:AddConversion(109141, 111673, 1 / 4) -- Fire Ammonite Tentacle from Enormous fish
	module:AddConversion(109141, 111666, 1 / 2) -- Fire Ammonite Tentacle from normal fish
	module:AddConversion(109141, 111656, 1) -- Fire Ammonite Tentacle from Small fish
	module:AddConversion(109142, 111672, 1 / 4) -- Sea Scorpion Segment from Enormous fish
	module:AddConversion(109142, 111665, 1 / 2) -- Sea Scorpion Segment from normal fish
	module:AddConversion(109142, 111658, 1) -- Sea Scorpion Segment from Small fish
	module:AddConversion(109143, 111671, 1 / 4) -- Abyssal Gulper Eel Flesh from Enormous fish
	module:AddConversion(109143, 111664, 1 / 2) -- Abyssal Gulper Eel Flesh from normal fish
	module:AddConversion(109143, 111659, 1) -- Abyssal Gulper Eel Flesh from Small fish
	module:AddConversion(109144, 111670, 1 / 4) -- Blackwater Whiptail Flesh from Enormous fish
	module:AddConversion(109144, 111663, 1 / 2) -- Blackwater Whiptail Flesh from normal fish
	module:AddConversion(109144, 111662, 1) -- Blackwater Whiptail Flesh from Small fish

	local fishOilSources = { 152543, 152544, 152545, 152546, 152547, 152548, 152549, 168302, 168646, 174327, 174328 }
	for index = 1, #fishOilSources do
		module:AddConversion(160711, fishOilSources[index], 1) -- Aromatic Fish Oil
	end

	local oreNuggets = {
		[2771] = 108295, [2772] = 108297, [2775] = 108294, [2776] = 108296,
		[3858] = 108300, [7911] = 108299, [10620] = 108298, [23424] = 108301,
		[23425] = 108302, [23426] = 108304, [23427] = 108303, [36909] = 108305,
		[36910] = 108391, [36912] = 108306, [52183] = 108309, [52185] = 108308,
		[53038] = 108307, [109118] = 109992, [109119] = 109991,
	}
	for oreItemID, nuggetItemID in pairs(oreNuggets) do
		module:AddConversion(oreItemID, nuggetItemID, 10)
	end

	local herbParts = {
		[785] = 108318, [2449] = 108319, [2450] = 108320, [2452] = 108321,
		[2453] = 108322, [3355] = 108323, [3356] = 108324, [3357] = 108325,
		[3358] = 108326, [3369] = 108327, [3818] = 108328, [3819] = 108329,
		[3820] = 108330, [3821] = 108331, [4625] = 108332, [8831] = 108333,
		[8838] = 108335, [8839] = 108336, [8845] = 108337, [8846] = 108338,
		[13463] = 108339, [13464] = 108340, [13465] = 108341, [13466] = 108342,
		[13467] = 108343, [22785] = 108344, [22786] = 108345, [22787] = 108346,
		[22789] = 108347, [22790] = 108348, [22791] = 108349, [22792] = 108350,
		[22793] = 108351, [36901] = 108352, [36903] = 108353, [36904] = 108354,
		[36905] = 108355, [36906] = 108356, [36907] = 108357, [37921] = 108358,
		[39970] = 108359, [52983] = 108360, [52984] = 108361, [52985] = 108362,
		[52986] = 108363, [52988] = 108365, [109124] = 109624, [109125] = 109625,
		[109126] = 109626, [109127] = 109627, [109128] = 109628, [109129] = 109629,
		[168583] = 169698, [168586] = 169550, [168589] = 168591,
		[169701] = 169700, [170554] = 169699,
	}
	for herbItemID, partItemID in pairs(herbParts) do
		module:AddConversion(herbItemID, partItemID, 10)
	end

	-- Standard's Ink Traders use Umbral Ink for the same fixed exchanges.
	AddInkTrades(173058, STANDARD_COMMON_INKS, STANDARD_RARE_INKS)
end

AddMistsBaseline()
if isStandard then
	AddStandardExtensions()
end