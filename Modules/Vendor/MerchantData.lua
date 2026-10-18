-- Records per-unit unlimited-supply NPC prices only for known recipe reagents.

local C_MerchantFrame = C_MerchantFrame
local GetMerchantItemInfo = GetMerchantItemInfo
local GetMerchantItemID = GetMerchantItemID
local GetMerchantNumItems = GetMerchantNumItems
local LibStub = LibStub

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local module = addon:NewModule("MerchantData", "AceEvent-3.0")
local professionScanner = addon:GetModule("ProfessionScanner")

local function GetItemInfo(index)
	if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
		---@diagnostic disable-next-line: wrong-flavor-api
		local info = C_MerchantFrame.GetItemInfo(index)
		if info then
			return info.price, info.stackCount, info.numAvailable, info.isPurchasable,
				info.hasExtendedCost
		end
	elseif GetMerchantItemInfo then
		local _, _, price, quantity, numAvailable, isPurchasable, _, extendedCost =
			GetMerchantItemInfo(index)
		return price, quantity, numAvailable, isPurchasable, extendedCost
	end
end

local function ReadMerchantPrices()
	local limitedItems = addon.db.global.limitedVendorItems
	local prices = addon.db.global.vendorBuyPrices
	for index = 1, GetMerchantNumItems() do
		local price, quantity, numAvailable, isPurchasable, extendedCost = GetItemInfo(index)
		local itemID = GetMerchantItemID(index)
		if itemID and not professionScanner:IsKnownReagent(itemID) then
			limitedItems[itemID] = nil
			prices[itemID] = nil
		elseif itemID and numAvailable and numAvailable >= 0 then
			-- Limited stock cannot support a dependable vendor-buy source. Remember the
			-- exclusion so visiting a different merchant cannot accidentally restore it.
			limitedItems[itemID] = true
			prices[itemID] = nil
		-- Alternative-currency purchases have no meaningful copper-only price.
		elseif itemID and not limitedItems[itemID] and isPurchasable and not extendedCost
			and price and price > 0 and quantity and quantity > 0 then
			-- Match TSM's per-unit treatment of vendor batches while preserving
			-- YAAHA's nonzero whole-copper floor.
			prices[itemID] = addon:RoundMoney(price / quantity)
		end
	end
end

local function PruneMerchantPrices()
	local limitedItems = addon.db.global.limitedVendorItems
	local prices = addon.db.global.vendorBuyPrices
	for itemID in pairs(prices) do
		if not professionScanner:IsKnownReagent(itemID) then
			prices[itemID] = nil
		end
	end
	for itemID in pairs(limitedItems) do
		if not professionScanner:IsKnownReagent(itemID) then
			limitedItems[itemID] = nil
		end
	end
end

function module:OnEnable()
	PruneMerchantPrices()
	self:RegisterMessage("YAAHA_KNOWN_RECIPES_UPDATED", PruneMerchantPrices)
	self:RegisterEvent("MERCHANT_SHOW", ReadMerchantPrices)
	self:RegisterEvent("MERCHANT_UPDATE", ReadMerchantPrices)
end