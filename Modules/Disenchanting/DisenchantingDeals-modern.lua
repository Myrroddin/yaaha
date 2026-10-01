-- Provides the modern disenchanting-deals module until modern searches are implemented.

local LibStub = LibStub

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")

-- Deal searches depend on the modern scanner's commodity and item snapshots.
addon:NewModule("DisenchantingDeals")