-- Provides the modern scanner contract until commodity and item searches are implemented.

local LibStub = LibStub

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local module = addon:NewModule("Scanner")

-- Modern clients require commodity and item search workflows rather than the
-- paged or replicated Classic scan. Keep the shared contract safe meanwhile.
function module:GetAuctionScope()
	if addon.UsesSharedAuctionHouse then
		return "realm"
	end
end

function module:GetScanButton()
end

function module:IsScanning()
	return false
end