local BANK_CONTAINER = BANK_CONTAINER
local C_Container = C_Container
local C_Item = C_Item
local C_Timer = C_Timer
local ceil = math.ceil
local GetMerchantItemInfo = GetMerchantItemInfo
local GetMerchantItemLink = GetMerchantItemLink
local GetMerchantNumItems = GetMerchantNumItems
local hooksecurefunc = hooksecurefunc
local ipairs = ipairs
local LibStub = LibStub
local max = math.max
local min = math.min
local NUM_BAG_SLOTS = NUM_BAG_SLOTS
local NUM_BANKBAGSLOTS = NUM_BANKBAGSLOTS
local pairs = pairs
local stringMatch = string.match
local tableRemove = table.remove
local tonumber = tonumber

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local module = addon:NewModule("InventoryAverageBuy", "AceEvent-3.0")

local bankOpen = false
local merchantCounts = {}
local merchantPending = {}

local function GetItemID(link)
	return link and tonumber(stringMatch(link, "item:(%d+)")) or nil
end

local function GetRecord(itemID)
	local records = addon.db.factionrealm.inventoryPurchases
	local record = records[itemID]
	if not record then
		record = { lots = {} }
		records[itemID] = record
	elseif record.freeQuantity then
		-- A free-only record is stored as one number. Inflate it only when a purchase
		-- needs the original free inventory represented ahead of it in the FIFO queue.
		record.lots = { { quantity = record.freeQuantity } }
		record.freeQuantity = nil
	end
	return record
end

local function CompactFreeRecord(itemID)
	local records = addon.db.factionrealm.inventoryPurchases
	local record = records[itemID]
	if not record or record.freeQuantity then
		return
	end

	local freeQuantity = 0
	for _, lot in ipairs(record.lots) do
		if lot.purchased then
			return
		end
		freeQuantity = freeQuantity + lot.quantity
	end
	if freeQuantity > 0 then
		records[itemID] = { freeQuantity = freeQuantity }
	else
		records[itemID] = nil
	end
end

local function AppendLot(itemID, quantity, totalCost)
	if not itemID or not quantity or quantity < 1 then
		return
	end

	local records = addon.db.factionrealm.inventoryPurchases
	local existing = records[itemID]
	local purchased = totalCost and totalCost > 0
	if not purchased and existing and existing.freeQuantity then
		existing.freeQuantity = existing.freeQuantity + quantity
		return
	elseif not purchased and not existing then
		records[itemID] = { freeQuantity = quantity }
		return
	end

	local lots = GetRecord(itemID).lots
	local previous = lots[#lots]
	local unitCost = purchased and totalCost / quantity or nil
	-- Adjacent units acquired in the same way can share a lot. Purchased lots only
	-- combine when their per-unit costs match, preserving truthful FIFO accounting.
	if previous and previous.purchased == purchased
		and (not purchased or previous.totalCost / previous.quantity == unitCost) then
		previous.quantity = previous.quantity + quantity
		if purchased then
			previous.totalCost = previous.totalCost + totalCost
		end
		return
	end
	lots[#lots + 1] = {
		quantity = quantity,
		totalCost = purchased and totalCost or nil,
		purchased = purchased or nil,
	}
end

local function RemoveFIFO(itemID, quantity)
	local records = addon.db.factionrealm.inventoryPurchases
	local record = records[itemID]
	if not record or quantity < 1 then
		return
	end
	if record.freeQuantity then
		record.freeQuantity = record.freeQuantity - quantity
		if record.freeQuantity <= 0 then
			records[itemID] = nil
		end
		return
	end

	local lots = record.lots
	while quantity > 0 and lots[1] do
		local lot = lots[1]
		local removed = min(quantity, lot.quantity)
		if lot.totalCost then
			lot.totalCost = lot.totalCost * (lot.quantity - removed) / lot.quantity
		end
		lot.quantity = lot.quantity - removed
		quantity = quantity - removed
		if lot.quantity == 0 then
			tableRemove(lots, 1)
		end
	end
	if not lots[1] then
		records[itemID] = nil
	else
		CompactFreeRecord(itemID)
	end
end

local function DiscoverContainer(container, itemIDs)
	for slot = 1, C_Container.GetContainerNumSlots(container) do
		local info = C_Container.GetContainerItemInfo(container, slot)
		if info and info.itemID then
			itemIDs[info.itemID] = true
		end
	end
end

local function DiscoverVisibleItems()
	local itemIDs = {}
	for bag = 0, NUM_BAG_SLOTS do
		DiscoverContainer(bag, itemIDs)
	end
	if bankOpen then
		DiscoverContainer(BANK_CONTAINER, itemIDs)
		for bag = NUM_BAG_SLOTS + 1, NUM_BAG_SLOTS + NUM_BANKBAGSLOTS do
			DiscoverContainer(bag, itemIDs)
		end
	end
	return itemIDs
end

local function ReconcileItem(itemID)
	if merchantPending[itemID] then
		return
	end
	local snapshot = addon.db.char.inventorySnapshot
	local previous = snapshot[itemID]
	local current = C_Item.GetItemCount(itemID, true)
	if previous == nil then
		-- Existing possessions establish free FIFO lots on the first observation. They
		-- participate in removal order but can never create or dilute an average buy.
		if current > 0 then
			local transfers = addon.db.factionrealm.inventoryTransfers
			local returning = min(current, transfers[itemID] or 0)
			if returning > 0 then
				transfers[itemID] = transfers[itemID] > returning and transfers[itemID] - returning or nil
			end
			if current > returning then
				AppendLot(itemID, current - returning)
			end
			snapshot[itemID] = current
		end
		return
	end

	if current > previous then
		local added = current - previous
		local transfers = addon.db.factionrealm.inventoryTransfers
		local returning = min(added, transfers[itemID] or 0)
		if returning > 0 then
			transfers[itemID] = transfers[itemID] > returning and transfers[itemID] - returning or nil
			added = added - returning
		end
		if added > 0 then
			AppendLot(itemID, added)
		end
	elseif current < previous then
		RemoveFIFO(itemID, previous - current)
	end
	snapshot[itemID] = current > 0 and current or nil
end

local function ReconcileInventory()
	local itemIDs = DiscoverVisibleItems()
	for itemID in pairs(addon.db.char.inventorySnapshot) do
		itemIDs[itemID] = true
	end
	for itemID in pairs(addon.db.factionrealm.inventoryPurchases) do
		itemIDs[itemID] = true
	end
	for itemID in pairs(itemIDs) do
		ReconcileItem(itemID)
	end
end

function module:RecordPurchase(itemID, quantity, totalCost)
	if not itemID or not quantity or quantity < 1 or not totalCost or totalCost < 1 then
		return
	end

	local snapshot = addon.db.char.inventorySnapshot
	local previous = snapshot[itemID] or max(C_Item.GetItemCount(itemID, true) - quantity, 0)
	local current = C_Item.GetItemCount(itemID, true)
	local unclassified = max(current - previous - quantity, 0)
	if unclassified > 0 then
		AppendLot(itemID, unclassified)
	end
	AppendLot(itemID, quantity, totalCost)
	-- Confirmed purchase collectors run when the items arrive. Advancing the snapshot
	-- here prevents BAG_UPDATE_DELAYED from recording the same units as free loot.
	snapshot[itemID] = max(current, previous + quantity)
end

function module:RecordPurchaseOutsideInventory(itemID, quantity, totalCost)
	if not itemID or not quantity or quantity < 1 or not totalCost or totalCost < 1 then
		return
	end
	AppendLot(itemID, quantity, totalCost)
	local transfers = addon.db.factionrealm.inventoryTransfers
	transfers[itemID] = (transfers[itemID] or 0) + quantity
end

function module:MoveOutOfInventory(itemID, quantity)
	if not itemID or not quantity or quantity < 1 then
		return
	end
	local transfers = addon.db.factionrealm.inventoryTransfers
	transfers[itemID] = (transfers[itemID] or 0) + quantity
	local snapshot = addon.db.char.inventorySnapshot
	if snapshot[itemID] then
		snapshot[itemID] = snapshot[itemID] > quantity and snapshot[itemID] - quantity or nil
	end
end

function module:RecordRemoval(itemID, quantity)
	if not itemID or not quantity or quantity < 1 then
		return
	end
	local transfers = addon.db.factionrealm.inventoryTransfers
	local outside = min(quantity, transfers[itemID] or 0)
	if outside > 0 then
		transfers[itemID] = transfers[itemID] > outside and transfers[itemID] - outside or nil
	end
	RemoveFIFO(itemID, quantity)
	local inBags = quantity - outside
	local snapshot = addon.db.char.inventorySnapshot
	if inBags > 0 and snapshot[itemID] then
		snapshot[itemID] = snapshot[itemID] > inBags and snapshot[itemID] - inBags or nil
	end
end

function module:GetValue(itemID)
	local record = addon.db.factionrealm.inventoryPurchases[itemID]
	if not record or not record.lots then
		return
	end
	local quantity, totalCost = 0, 0
	for _, lot in ipairs(record.lots) do
		if lot.purchased then
			quantity = quantity + lot.quantity
			totalCost = totalCost + lot.totalCost
		end
	end
	return quantity > 0 and totalCost / quantity or nil
end

local function SnapshotMerchantItems()
	merchantCounts = {}
	for index = 1, GetMerchantNumItems() do
		local link = GetMerchantItemLink(index)
		local itemID = GetItemID(link)
		if itemID then
			merchantCounts[itemID] = C_Item.GetItemCount(itemID, true)
		end
	end
end

local function CaptureMerchantPurchase(index)
	local _, _, price, batchSize, _, _, _, extendedCost = GetMerchantItemInfo(index)
	local itemID = GetItemID(GetMerchantItemLink(index))
	if not itemID or extendedCost or not price or price < 1 or not batchSize or batchSize < 1 then
		return
	end
	local pending = merchantPending[itemID]
	if not pending then
		pending = { count = merchantCounts[itemID] or C_Item.GetItemCount(itemID, true), price = price, batchSize = batchSize }
		merchantPending[itemID] = pending
	end
	C_Timer.After(0.1, function()
		local purchase = merchantPending[itemID]
		if not purchase then
			return
		end
		merchantPending[itemID] = nil
		local current = C_Item.GetItemCount(itemID, true)
		local quantity = current - purchase.count
		if quantity > 0 then
			module:RecordPurchase(itemID, quantity, ceil(quantity / purchase.batchSize) * purchase.price)
		end
		merchantCounts[itemID] = current
	end)
end

function module:BAG_UPDATE_DELAYED()
	ReconcileInventory()
end

function module:BANKFRAME_CLOSED()
	bankOpen = false
end

function module:BANKFRAME_OPENED()
	bankOpen = true
	ReconcileInventory()
end

function module:MERCHANT_SHOW()
	SnapshotMerchantItems()
end

function module:OnEnable()
	ReconcileInventory()
	self:RegisterEvent("BAG_UPDATE_DELAYED")
	self:RegisterEvent("BANKFRAME_CLOSED")
	self:RegisterEvent("BANKFRAME_OPENED")
	self:RegisterEvent("MERCHANT_SHOW")
	hooksecurefunc("BuyMerchantItem", CaptureMerchantPurchase)
end