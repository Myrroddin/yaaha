-- Provides the modern vendor-deals module until modern purchase workflows are implemented.

local LibStub = LibStub

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")

-- Modern vendor deals require separate commodity and item purchase workflows.
addon:NewModule("VendorDeals")