-- Provides authoritative, client-aware valuation methods for materials whose
-- opportunity cost cannot be represented by an ordinary recipe or conversion.

local C_Item = C_Item
local LibStub = LibStub
local max = math.max
local pairs = pairs

local COPPER_PER_GOLD = 10000

local MOTE_OF_HARMONY = 89112
local SPIRIT_OF_HARMONY = 76061
local PRIMAL_SPIRIT = 120945
local BLOOD_OF_SARGERAS = 124124
local PRIMAL_SARGERITE = 151568
local EXPULSOM = 152668
local SPARE_PARTS = 166846
local SENTRY_FISH = 168262
local RECYCLABLE_BUNDLE = 168258

-- Community testing found one Expulsom per 6.5 scrapped bracers on average.
-- https://www.wowhead.com/news/wow-economy-weekly-wrap-up-developer-q-a-goblin-crash-course-tailoring-deep-dive-289941?page=6
-- https://www.youtube.com/watch?v=eT-ZWzksycI&t=7s
local AVERAGE_EXPULSOM_SCRAPS = 6.5
-- Two 100-bundle samples yielded 12,463 and 12,454 Spare Parts respectively.
-- The same observation supplies the coproduct averages used below.
-- https://www.wowhead.com/item=168258/bundle-of-recyclable-parts#comments
local AVERAGE_SPARE_PARTS_PER_BUNDLE = 124.585
-- Each Sentry Fish produces two or three Spare Parts, for an expected 2.5.
-- https://www.wowhead.com/item=168262/sentry-fish#comments
local AVERAGE_SPARE_PARTS_PER_FISH = 2.5
-- In Mists Classic, one Mote costs 400 Honor, and Blizzard values excess Honor
-- at 35 silver per point: 400 * 35s = 140g.
-- https://www.wowhead.com/tbc/news/motes-of-harmony-now-available-through-honor-justice-point-exchange-mists-of-377947
-- https://worldofwarcraft.blizzard.com/en-us/news/16071433
local MISTS_MOTE_OPPORTUNITY_COST = 140 * COPPER_PER_GOLD

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local isMists = addon.isMists
local isStandard = addon.isStandard
local module = addon:NewModule("DerivedMaterialData")
local valuationMethods = {}

local function GetVendorSell(itemID)
	local itemName, _, _, _, _, _, _, _, _, _, sellPrice = C_Item.GetItemInfo(itemID)
	if not itemName then
		C_Item.RequestLoadItemDataByID(itemID)
		return
	end
	return sellPrice or 0
end

local function Average(values)
	-- Average only independently complete paths. Missing paths are unknown, not
	-- free, and therefore cannot contribute a fabricated zero to the result.
	local total = 0
	local count = 0
	for _, value in pairs(values) do
		if value and value > 0 then
			total = total + value
			count = count + 1
		end
	end
	return count > 0 and total / count or nil
end

local function Maximum(values)
	local best
	for _, value in pairs(values) do
		if value and value > 0 and (not best or value > best) then
			best = value
		end
	end
	return best
end

local function Minimum(values)
	local best
	for _, value in pairs(values) do
		if value and value > 0 and (not best or value < best) then
			best = value
		end
	end
	return best
end

local function GetMaterialValue(resolver, itemID, quantity)
	local material = resolver:GetItemCost(itemID)
	return material and material.value and material.value * (quantity or 1) or nil
end

local function GetMarketValue(resolver, itemID, quantity)
	local value = resolver:GetCurrentMarketValue(itemID)
	return value and value * (quantity or 1) or nil
end

local function GetInputTotal(resolver, inputs)
	local total = 0
	for index = 1, #inputs do
		local input = inputs[index]
		local value = GetMaterialValue(resolver, input.itemID, input.quantity)
		if not value then
			return
		end
		total = total + value
	end
	return total
end

local function GetCoproductCredit(coproducts)
	-- Vendor values are independent, immediately realizable credits. Using a
	-- material value here could lead back through Spare Parts and create a cycle.
	local total = 0
	for index = 1, #coproducts do
		local coproduct = coproducts[index]
		local value = GetVendorSell(coproduct.itemID)
		if value == nil then
			return
		end
		total = total + value * coproduct.quantity
	end
	return total
end

local function Register(itemID, method)
	valuationMethods[itemID] = method
end

local harmonyOutputs = {
	{ itemID = 79255, quantity = 1 }, -- Starlight Ink
	{ itemID = 74247, quantity = 1 }, -- Ethereal Shard
	{ itemID = 76734, quantity = 1 }, -- Serpent's Eye
	{ itemID = 72238, quantity = 2 }, -- Golden Lotus
	{ itemID = 74250, quantity = 5 }, -- Mysterious Essence
	{ itemID = 72094, quantity = 5 }, -- Black Trillium Ore
	{ itemID = 72103, quantity = 5 }, -- White Trillium Ore
	{ itemID = 72988, quantity = 20 }, -- Windwool Cloth
	{ itemID = 74249, quantity = 20 }, -- Spirit Dust
	{ itemID = 72092, quantity = 20 }, -- Ghost Iron Ore
	{ itemID = 72093, quantity = 20 }, -- Kyparite
	{ itemID = 72120, quantity = 20 }, -- Exotic Leather
	{ itemID = 79101, quantity = 20 }, -- Prismatic Scale
}

-- One Spirit buys the quantities below from the Spirit of Harmony vendor.
-- https://www.wowhead.com/mop-classic/item=76061/spirit-of-harmony#currency-for
-- Pandaria Herbs is a random BoP container, not a selectable stack of one herb.
-- Exclude it until its complete expected contents can be valued honestly.

local function GetHarmonyExchangeValue(resolver)
	local values = {}
	for index = 1, #harmonyOutputs do
		local output = harmonyOutputs[index]
		values[index] = GetMarketValue(resolver, output.itemID, output.quantity)
	end
	return Maximum(values)
end

-- Harmony conversion is one-way: ten Motes make one Spirit, but a Spirit
-- cannot be split. Resolve Motes independently before using them as one of
-- the competing Spirit acquisition paths.
local function GetMoteOfHarmonyValue(resolver)
	local value = max(GetVendorSell(MOTE_OF_HARMONY) or 0,
		isMists and MISTS_MOTE_OPPORTUNITY_COST
		or GetMarketValue(resolver, MOTE_OF_HARMONY) or 0)
	if value <= 0 then
		return
	end
	return value and {
		value = value,
		method = isMists and "honorOpportunity" or "marketOpportunity",
	} or nil
end

local function GetSpiritOfHarmonyValue(resolver)
	local moteValue = GetMoteOfHarmonyValue(resolver)
	local values = {}
	values[#values + 1] = moteValue and moteValue.value * 10 or nil
	values[#values + 1] = GetHarmonyExchangeValue(resolver)
	if isStandard then
		values[#values + 1] = GetMarketValue(resolver, SPIRIT_OF_HARMONY)
	end
	local value = Minimum(values)
	if not value then
		return
	end
	return {
		value = max(GetVendorSell(SPIRIT_OF_HARMONY) or 0, value),
		method = "harmonyExchange",
	}
end

if isMists or isStandard then
	Register(MOTE_OF_HARMONY, GetMoteOfHarmonyValue)
	Register(SPIRIT_OF_HARMONY, GetSpiritOfHarmonyValue)
end

local primalSpiritInputs = {
	111557, -- Sumptuous Fur
	109118, -- Blackrock Ore
	109119, -- True Iron Ore
	110609, -- Raw Beast Hide
	109124, -- Frostweed
	109125, -- Fireweed
	109126, -- Gorgrond Flytrap
	109127, -- Starflower
	109128, -- Nagrand Arrowbloom
	109129, -- Talador Orchid
}

-- Each rotating Garrison trader exchanges five of one listed reagent for one
-- Primal Spirit. Average the independently complete paths because availability
-- rotates and no one input is a dependable permanent minimum.
-- https://www.wowhead.com/guide/garrisons/town-hall-daily-quests#profession-quests
local function GetPrimalSpiritValue(resolver)
	local paths = {}
	for index = 1, #primalSpiritInputs do
		paths[index] = GetMarketValue(resolver, primalSpiritInputs[index], 5)
	end
	local value = Average(paths)
	return value and {
		value = max(GetVendorSell(PRIMAL_SPIRIT) or 0, value),
		method = "primalSpiritExchange",
	} or nil
end

-- One Blood of Sargeras buys any one of the listed material bundles.
-- https://www.wowhead.com/news/patch-7-1-ptr-preview-profession-and-blood-of-sargeras-updates-256536
local bloodOfSargerasOutputs = {
	{ itemID = 124101, quantity = 10 }, -- Aethril
	{ itemID = 124102, quantity = 10 }, -- Dreamleaf
	{ itemID = 124103, quantity = 10 }, -- Foxflower
	{ itemID = 124104, quantity = 10 }, -- Fjarnskaggl
	{ itemID = 123918, quantity = 10 }, -- Leystone Ore
	{ itemID = 124113, quantity = 10 }, -- Stonehide Leather
	{ itemID = 124115, quantity = 10 }, -- Stormscale
	{ itemID = 124440, quantity = 10 }, -- Arkhana
	{ itemID = 124437, quantity = 10 }, -- Shal'dorei Silk
	{ itemID = 123919, quantity = 5 }, -- Felslate
	{ itemID = 124105, quantity = 3 }, -- Starlight Rose
	{ itemID = 124441, quantity = 3 }, -- Leylight Shard
}

-- One Primal Sargerite buys any one bundle; gems cost ten Sargerite, hence the
-- 0.1 quantity used to express their per-Sargerite opportunity value.
-- https://www.wowhead.com/news/wow-economy-weekly-wrap-up-patch-7-3-2-rare-spawns-best-profession-mobile-armory-274959?page=4
local primalSargeriteOutputs = {
	{ itemID = 151565, quantity = 10 }, -- Astral Glory
	{ itemID = 151564, quantity = 10 }, -- Empyrium
	{ itemID = 151566, quantity = 10 }, -- Fiendish Leather
	{ itemID = 151567, quantity = 10 }, -- Lightweave Cloth
	{ itemID = 151579, quantity = 0.1 }, -- Labradorite
	{ itemID = 151722, quantity = 0.1 }, -- Florid Malachite
	{ itemID = 151720, quantity = 0.1 }, -- Chemirine
	{ itemID = 151718, quantity = 0.1 }, -- Argulite
	{ itemID = 151721, quantity = 0.1 }, -- Hesselian
	{ itemID = 151719, quantity = 0.1 }, -- Lightsphene
}

local function GetBestExchangeValue(resolver, itemID, outputs, method)
	local values = { GetVendorSell(itemID) }
	for index = 1, #outputs do
		local output = outputs[index]
		values[#values + 1] = GetMarketValue(resolver, output.itemID, output.quantity)
	end
	local value = Maximum(values)
	return value and {
		value = value,
		method = method,
	} or nil
end

local expulsomInputs = {
	{
		{ itemID = 152576, quantity = 10 }, -- Tidespray Linen
		{ itemID = 159959, quantity = 4 }, -- Nylon Thread
	},
	{
		{ itemID = 152541, quantity = 6 }, -- Coarse Leather
		{ itemID = 154164, quantity = 4 }, -- Blood-Stained Bone
	},
	{
		{ itemID = 153050, quantity = 6 }, -- Shimmerscale
		{ itemID = 154164, quantity = 4 }, -- Blood-Stained Bone
	},
}

local function GetExpulsomValue(resolver)
	-- Average the complete cloth, leather, and mail bracer paths before applying
	-- the observed scrap rate. A temporary cheapest path is not a stable expected
	-- acquisition cost, and this custom value replaces the default material method.
	local paths = {}
	for index = 1, #expulsomInputs do
		paths[index] = GetInputTotal(resolver, expulsomInputs[index])
	end
	local value = Average(paths)
	return value and {
		value = max(GetVendorSell(EXPULSOM) or 0, value * AVERAGE_EXPULSOM_SCRAPS),
		method = "expulsomScrapping",
	} or nil
end

local bundleInputs = {
	{ itemID = 168217, quantity = 30 }, -- Hardened Spring
	{ itemID = 168216, quantity = 10 }, -- Tempered Plating
	{ itemID = 168215, quantity = 5 }, -- Machined Gear Assembly
}

-- A Bundle of Recyclable Parts requires exactly these three Mechagon components.
-- https://www.wowhead.com/item=168258/bundle-of-recyclable-parts#comments
local bundleCoproducts = {
	-- Expected quantities from the same 200 observed bundle openings cited above.
	{ itemID = 166971, quantity = 1.17 }, -- Empty Energy Cell
	{ itemID = 166970, quantity = 0.13 }, -- Energy Cell
	{ itemID = 168327, quantity = 0.195 }, -- Chain Ignitercoil
}

local function GetSparePartsValue(resolver)
	local inputValue = GetInputTotal(resolver, bundleInputs)
	local coproductCredit = GetCoproductCredit(bundleCoproducts)
	if not inputValue or coproductCredit == nil then
		return
	end
	return {
		-- Spare Parts receive only the bundle cost not recovered through independently
		-- valued coproducts. The vendor floor prevents a positive material from
		-- becoming zero or negative when the coproduct credit exceeds the inputs.
		value = max(GetVendorSell(SPARE_PARTS) or 0,
			(inputValue - coproductCredit) / AVERAGE_SPARE_PARTS_PER_BUNDLE),
		method = "recyclableBundleResidual",
		itemID = RECYCLABLE_BUNDLE,
	}
end

local function GetSentryFishValue(resolver)
	local spareParts = GetMaterialValue(resolver, SPARE_PARTS)
	return spareParts and {
		value = max(GetVendorSell(SENTRY_FISH) or 0,
			spareParts * AVERAGE_SPARE_PARTS_PER_FISH),
		method = "sentryFishConversion",
		itemID = SPARE_PARTS,
	} or nil
end

if isStandard then
	Register(PRIMAL_SPIRIT, GetPrimalSpiritValue)
	Register(BLOOD_OF_SARGERAS, function(resolver)
		return GetBestExchangeValue(resolver, BLOOD_OF_SARGERAS,
			bloodOfSargerasOutputs, "bloodTraderExchange")
	end)
	Register(PRIMAL_SARGERITE, function(resolver)
		return GetBestExchangeValue(resolver, PRIMAL_SARGERITE,
			primalSargeriteOutputs, "primalSargeriteExchange")
	end)
	Register(EXPULSOM, GetExpulsomValue)
	Register(SPARE_PARTS, GetSparePartsValue)
	Register(SENTRY_FISH, GetSentryFishValue)
end

function module:HasMethod(itemID)
	return valuationMethods[itemID] ~= nil
end

function module:GetValue(itemID, resolver)
	local method = valuationMethods[itemID]
	return method and method(resolver) or nil
end