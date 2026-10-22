-- Loads Classic-family deterministic conversion definitions into ConvertData.

local LibStub = LibStub

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local isTBC = addon.isTBC
local isWrath = addon.isWrath
local module = addon:GetModule("ConvertData")

-- Vanilla is the Classic-family baseline. Forever may amend it later without
-- changing the baseline used by Classic Era, TBC, or Wrath.
module:AddReversibleConversion(10939, 10938, 3) -- Greater/Lesser Magic Essence
module:AddReversibleConversion(11082, 10998, 3) -- Greater/Lesser Astral Essence
module:AddReversibleConversion(11135, 11134, 3) -- Greater/Lesser Mystic Essence
module:AddReversibleConversion(11175, 11174, 3) -- Greater/Lesser Nether Essence
module:AddReversibleConversion(16203, 16202, 3) -- Greater/Lesser Eternal Essence

-- These consolidation recipes are useful tooltip knowledge even when the
-- current character is not a Leatherworker. Known recipes are priced by the
-- profession scanner rather than being assumed available for material costs.
module:AddConversion(2318, 2934, 3, true) -- Light Leather from Ruined Leather Scraps

if isTBC or isWrath then
	module:AddReversibleConversion(22446, 22447, 3) -- Greater/Lesser Planar Essence
	module:AddConversion(21885, 22578, 10) -- Primal Water from Motes
	module:AddConversion(22456, 22577, 10) -- Primal Shadow from Motes
	module:AddConversion(22457, 22576, 10) -- Primal Mana from Motes
	module:AddConversion(21886, 22575, 10) -- Primal Life from Motes
	module:AddConversion(21884, 22574, 10) -- Primal Fire from Motes
	module:AddConversion(22452, 22573, 10) -- Primal Earth from Motes
	module:AddConversion(22451, 22572, 10) -- Primal Air from Motes
	module:AddConversion(21887, 25649, 5, true) -- Knothide Leather from Scraps
end

if isWrath then
	module:AddConversion(33568, 33567, 5, true) -- Borean Leather from Scraps
	module:AddReversibleConversion(34055, 34056, 3) -- Greater/Lesser Cosmic Essence
	module:AddConversion(34052, 34053, 3) -- Dream Shard from Small Dream Shards
	module:AddReversibleConversion(35623, 37700, 10) -- Eternal/Crystallized Air
	module:AddReversibleConversion(35624, 37701, 10) -- Eternal/Crystallized Earth
	module:AddReversibleConversion(36860, 37702, 10) -- Eternal/Crystallized Fire
	module:AddReversibleConversion(35627, 37703, 10) -- Eternal/Crystallized Shadow
	module:AddReversibleConversion(35625, 37704, 10) -- Eternal/Crystallized Life
	module:AddReversibleConversion(35622, 37705, 10) -- Eternal/Crystallized Water

	-- Wrath Ink Traders exchange Ink of the Sea for older common inks at
	-- one-for-one, or ten Ink of the Sea for one Snowfall Ink.
	local commonInks = { 37101, 39469, 39774, 43116, 43118, 43120, 43122, 43124 }
	for index = 1, #commonInks do
		module:AddConversion(commonInks[index], 43126, 1)
	end
	module:AddConversion(43127, 43126, 10) -- Snowfall Ink from Ink of the Sea
end