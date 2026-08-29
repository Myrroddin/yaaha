local C_Container = C_Container
local GetLootSlotInfo = GetLootSlotInfo
local GetLootSlotLink = GetLootSlotLink
local GetNumLootItems = GetNumLootItems
local GetTime = GetTime
local LibStub = LibStub
local next = next
local tonumber = tonumber

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local module = addon:NewModule("DisenchantingCollector", "AceEvent-3.0")
local disenchantingData = addon:GetModule("DisenchantingData")

local DISENCHANT_SPELL_ID = 13262
local candidate, awaitingLoot

function module:ITEM_LOCK_CHANGED(_, bagID, slotID)
	if slotID == nil then
		return
	end
	local info = C_Container.GetContainerItemInfo(bagID, slotID)
	if not info or not info.isLocked then
		return
	end
	local itemID, link, _, itemLevel = disenchantingData:GetItemDetails(info.hyperlink)
	if itemID and itemLevel >= 130 then
		-- Cache the link before the cast destroys the source item. The later unlock
		-- event can no longer be relied upon to return a link for this slot.
		candidate = {
			link = link,
			time = GetTime(),
		}
	end
end

function module:UNIT_SPELLCAST_SUCCEEDED(_, unit, _, spellID)
	if unit ~= "player" or spellID ~= DISENCHANT_SPELL_ID then
		return
	end
	if candidate and GetTime() - candidate.time <= 5 then
		awaitingLoot = candidate
	end
	candidate = nil
end

function module:LOOT_OPENED()
	if not awaitingLoot then
		return
	end
	local loot = {}
	for slot = 1, GetNumLootItems() do
		local link = GetLootSlotLink(slot)
		local itemID = link and tonumber(link:match("item:(%d+)"))
		local _, _, quantity = GetLootSlotInfo(slot)
		if itemID and disenchantingData:IsMaterial(itemID) and quantity and quantity > 0 then
			loot[itemID] = (loot[itemID] or 0) + quantity
		end
	end
	if next(loot) then
		disenchantingData:RecordObservation(awaitingLoot.link, loot)
	end
	awaitingLoot = nil
end

function module:LOOT_CLOSED()
	awaitingLoot = nil
end

function module:OnEnable()
	self:RegisterEvent("ITEM_LOCK_CHANGED")
	self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
	self:RegisterEvent("LOOT_OPENED")
	self:RegisterEvent("LOOT_CLOSED")
end