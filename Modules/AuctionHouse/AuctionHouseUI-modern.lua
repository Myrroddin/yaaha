-- Provides the modern auction-house UI module contract until its workspace is implemented.

local LibStub = LibStub

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local module = addon:NewModule("AuctionHouseUI")

-- Modern auction-house clients use a different frame hierarchy. This adapter
-- preserves the shared module contract until the modern workspace is built.
function module:GetPage()
end

function module:GetScanButtonParent()
end

function module:SetAuctionScope()
end

function module:SetScanStatus()
end