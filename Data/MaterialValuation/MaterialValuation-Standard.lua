-- Provides Standard-only expected-cost formulas for materials with multi-output acquisition paths.

local C_Item = C_Item
local LibStub = LibStub
local max = math.max

local SPARE_PARTS_ITEM_ID = 166846
local SENTRY_FISH_ITEM_ID = 168262
local RECYCLABLE_BUNDLE_ITEM_ID = 168258
local AVERAGE_SPARE_PARTS_PER_BUNDLE = 124.585
local AVERAGE_SPARE_PARTS_PER_FISH = 2.5

local bundleInputs = {
	{ itemID = 168217, quantity = 30 }, -- Hardened Spring
	{ itemID = 168216, quantity = 10 }, -- Tempered Plating
	{ itemID = 168215, quantity = 5 }, -- Machined Gear Assembly
}

local bundleCoproducts = {
	-- Expected quantities from 200 observed Bundle of Recyclable Parts openings.
	{ itemID = 166971, quantity = 1.17 }, -- Empty Energy Cell
	{ itemID = 166970, quantity = 0.13 }, -- Energy Cell
	{ itemID = 168327, quantity = 0.195 }, -- Chain Ignitercoil
}

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local module = addon:NewModule("MaterialValuationData")

local function GetVendorSell(itemID)
	local itemName, _, _, _, _, _, _, _, _, _, sellPrice = C_Item.GetItemInfo(itemID)
	if not itemName then
		C_Item.RequestLoadItemDataByID(itemID)
		return
	end
	return sellPrice or 0
end

local function GetRequiredInputValue(resolveCost, inputs)
	local total = 0
	for index = 1, #inputs do
		local input = inputs[index]
		local material = resolveCost(input.itemID)
		if not material or not material.value then
			return
		end
		total = total + material.value * input.quantity
	end
	return total
end

local function GetCoproductCredit(coproducts)
	-- Vendor values are independent, immediately realizable credits. Using a
	-- crafting value here could lead back through Spare Parts and create a cycle.
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

local function GetBundlePath(resolveCost)
	local inputValue = GetRequiredInputValue(resolveCost, bundleInputs)
	local coproductCredit = GetCoproductCredit(bundleCoproducts)
	local vendorFloor = GetVendorSell(SPARE_PARTS_ITEM_ID)
	if not inputValue or coproductCredit == nil or vendorFloor == nil then
		return
	end

	-- Spare Parts receive only the bundle cost not recovered through independently
	-- valued coproducts. The vendor floor prevents a positive material from
	-- becoming zero or negative when the coproduct credit exceeds the inputs.
	return {
		value = max(vendorFloor, (inputValue - coproductCredit)
			/ AVERAGE_SPARE_PARTS_PER_BUNDLE),
		kind = "bundleResidual",
		itemID = RECYCLABLE_BUNDLE_ITEM_ID,
	}
end

local function GetSentryFishPath(resolveCost)
	local spareParts = resolveCost(SPARE_PARTS_ITEM_ID)
	if not spareParts or not spareParts.value then
		return
	end
	return {
		-- One fish produces two or three Spare Parts, for an expected yield of 2.5.
		value = spareParts.value * AVERAGE_SPARE_PARTS_PER_FISH,
		kind = "expectedOutput",
		itemID = SPARE_PARTS_ITEM_ID,
	}
end

local pathBuilders = {
	[SPARE_PARTS_ITEM_ID] = { GetBundlePath },
	[SENTRY_FISH_ITEM_ID] = { GetSentryFishPath },
}

function module:GetValue(itemID, resolveCost)
	local builders = pathBuilders[itemID]
	if not builders then
		return
	end

	local paths = {}
	local total = 0
	for index = 1, #builders do
		local path = builders[index](resolveCost)
		-- Only individually complete paths enter the average. An unresolved path
		-- is omitted rather than being treated as free or fabricated data.
		if path and path.value and path.value > 0 then
			paths[#paths + 1] = path
			total = total + path.value
		end
	end
	if #paths == 0 then
		return
	end
	return {
		value = total / #paths,
		paths = paths,
	}
end