-- Learns prospecting results by matching the consumed ore stack to its loot.

local C_Container = C_Container
local GetLootSlotInfo = GetLootSlotInfo
local GetLootSlotLink = GetLootSlotLink
local GetNumLootItems = GetNumLootItems
local GetTime = GetTime
local hooksecurefunc = hooksecurefunc
local LibStub = LibStub
local next = next

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local module = addon:NewModule("ProspectingCollector", "AceEvent-3.0")
local prospectingData

local PROSPECTING_SPELL_ID = 31252
local candidate, awaitingLoot

local function CaptureCandidate(itemInfo)
	if not prospectingData:IsSource(itemInfo) then
		return false
	end
	candidate = {
		link = itemInfo,
		time = GetTime(),
	}
	return true
end

local function ContainerItemUsed(bagID, slotID)
	-- Secure hooks run after UseContainerItem, when the spell cursor may already
	-- be clear. Remember only known ore; the matching spell event below must
	-- immediately claim it before it can be used as an observation.
	local link = C_Container.GetContainerItemLink(bagID, slotID)
	if link then
		CaptureCandidate(link)
	end
end

function module:UNIT_SPELLCAST_SENT(_, unit, target, castGUID, spellID)
	if unit ~= "player" or spellID ~= PROSPECTING_SPELL_ID then
		return
	end
	awaitingLoot = nil
	-- Prefer the event target for macros and non-bag selection. The container hook
	-- remains the fallback on clients which omit the target.
	local capturedTarget = target and target ~= "" and CaptureCandidate(target)
	if not capturedTarget and (not candidate or GetTime() - candidate.time > 1) then
		candidate = nil
	end
	if candidate then
		candidate.castGUID = castGUID
	end
end

function module:UNIT_SPELLCAST_SUCCEEDED(_, unit, castGUID, spellID)
	if unit ~= "player" or spellID ~= PROSPECTING_SPELL_ID then
		return
	end
	if candidate and GetTime() - candidate.time <= 5
		and (not candidate.castGUID or candidate.castGUID == castGUID) then
		awaitingLoot = candidate
		awaitingLoot.time = GetTime()
	end
	candidate = nil
end

function module:UNIT_SPELLCAST_FAILED(_, unit, _, spellID)
	if unit == "player" and spellID == PROSPECTING_SPELL_ID then
		candidate = nil
	end
end

module.UNIT_SPELLCAST_INTERRUPTED = module.UNIT_SPELLCAST_FAILED
module.UNIT_SPELLCAST_FAILED_QUIET = module.UNIT_SPELLCAST_FAILED

function module:LOOT_OPENED()
	if not awaitingLoot or GetTime() - awaitingLoot.time > 5 then
		awaitingLoot = nil
		return
	end
	local loot = {}
	for slot = 1, GetNumLootItems() do
		local itemID = addon:GetItemID(GetLootSlotLink(slot))
		local _, _, quantity = GetLootSlotInfo(slot)
		if itemID and quantity and quantity > 0 then
			loot[itemID] = (loot[itemID] or 0) + quantity
		end
	end
	if next(loot) then
		if prospectingData:RecordObservation(awaitingLoot.link, loot) then
			module:SendMessage("YAAHA_BREAKDOWN_OBSERVED")
		end
	end
	awaitingLoot = nil
end

function module:LOOT_CLOSED()
	awaitingLoot = nil
end

function module:OnInitialize()
	prospectingData = addon:GetModule("ProspectingData")
	hooksecurefunc(C_Container, "UseContainerItem", ContainerItemUsed)
end

function module:OnEnable()
	self:RegisterEvent("UNIT_SPELLCAST_SENT")
	self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
	self:RegisterEvent("UNIT_SPELLCAST_FAILED")
	self:RegisterEvent("UNIT_SPELLCAST_FAILED_QUIET")
	self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
	self:RegisterEvent("LOOT_OPENED")
	self:RegisterEvent("LOOT_CLOSED")
end