local floor = math.floor
local GetMerchantItemInfo = GetMerchantItemInfo
local GetMerchantItemLink = GetMerchantItemLink
local GetMerchantNumItems = GetMerchantNumItems
local LibStub = LibStub
local match = string.match
local tonumber = tonumber

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local module = addon:NewModule("MerchantData", "AceEvent-3.0")

local function ReadMerchantPrices()
	local limitedItems = addon.db.global.limitedVendorItems
	local prices = addon.db.global.vendorBuyPrices
	for index = 1, GetMerchantNumItems() do
		local _, _, price, quantity, numAvailable, isPurchasable, _, extendedCost = GetMerchantItemInfo(index)
		local link = GetMerchantItemLink(index)
		local itemID = link and tonumber(match(link, "item:(%d+)"))
		if itemID and numAvailable and numAvailable >= 0 then
			-- Limited stock cannot support a dependable vendor-buy source. Remember the
			-- exclusion so visiting a different merchant cannot accidentally restore it.
			limitedItems[itemID] = true
			prices[itemID] = nil
		-- Alternative-currency purchases have no meaningful copper-only price.
		elseif itemID and not limitedItems[itemID] and isPurchasable and not extendedCost
			and price and price > 0 and quantity and quantity > 0 then
			prices[itemID] = floor(price / quantity + 0.5)
		end
	end
end

function module:OnEnable()
	self:RegisterEvent("MERCHANT_SHOW", ReadMerchantPrices)
	self:RegisterEvent("MERCHANT_UPDATE", ReadMerchantPrices)
end