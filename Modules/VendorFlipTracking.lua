local AceConfigRegistry
local C_Item = C_Item
local C_Timer = C_Timer
local COD_PAYMENT = COD_PAYMENT
local floor = math.floor
local format = string.format
local GetPlayerTradeMoney = GetPlayerTradeMoney
local GetSendMailCOD = GetSendMailCOD
local GetSendMailItem = GetSendMailItem
local GetSendMailItemLink = GetSendMailItemLink
local GetTargetTradeMoney = GetTargetTradeMoney
local GetTradePlayerItemInfo = GetTradePlayerItemInfo
local GetTradePlayerItemLink = GetTradePlayerItemLink
local GetTradeTargetItemInfo = GetTradeTargetItemInfo
local GetTradeTargetItemLink = GetTradeTargetItemLink
local GetUnitName = GetUnitName
local hooksecurefunc = hooksecurefunc
local LibStub = LibStub
local min = math.min
local pairs = pairs
local stringMatch = string.match
local tableRemove = table.remove
local tonumber = tonumber

AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local module = addon:NewModule("VendorFlipTracking", "AceEvent-3.0")
local auctionHouseUI = addon:GetModule("AuctionHouseUI")
local inventoryAverageBuy = addon:GetModule("InventoryAverageBuy")
local scanner = addon:GetModule("Scanner")
local L = LibStub("AceLocale-3.0"):GetLocale("YAAHA")

local GREEN_NUMBER = "|cff20ff20"
local RED_NUMBER = "|cffff2020"
local RETIRE_DELAY = 3
local itemCounts = {}
local merchantOpen = false
local outgoingMail
local pendingLosses = {}
local preservedQuantities = {}
local profitText
local tradeSnapshot

local function GetInventory()
	return addon.db.realm.vendorFlipInventory
end

local function GetItemID(itemLink)
	return itemLink and tonumber(stringMatch(itemLink, "item:(%d+)")) or nil
end

local function CharacterName(name)
	return name and name:match("^[^-]+") or nil
end

local function GetTrackedCount(itemID)
	return C_Item.GetItemCount(itemID, true)
end

local function RetireQuantity(itemID, quantity)
	local inventory = GetInventory()
	local outstanding = inventory[itemID]
	if not outstanding or outstanding < 1 or quantity < 1 then
		return
	end
	inventory[itemID] = outstanding > quantity and outstanding - quantity or nil
end

local function ScheduleRetirement(itemID, quantity)
	local pending = pendingLosses[itemID]
	if not pending then
		pending = { quantity = 0 }
		pendingLosses[itemID] = pending
	end
	pending.quantity = pending.quantity + quantity
	if pending.scheduled then
		return
	end
	pending.scheduled = true

	-- Bag changes arrive before some disposition events. The short grace period lets
	-- mail, trade, and auction callbacks classify a removal before it is treated as
	-- consumption or destruction. Cashflow is intentionally unchanged on retirement.
	C_Timer.After(RETIRE_DELAY, function()
		local loss = pendingLosses[itemID]
		if not loss then
			return
		end
		pendingLosses[itemID] = nil
		RetireQuantity(itemID, loss.quantity)
	end)
end

local function SnapshotTrackedItems()
	for itemID, quantity in pairs(GetInventory()) do
		if quantity > 0 then
			itemCounts[itemID] = GetTrackedCount(itemID)
		end
	end
end

function module:GetFormattedProfit()
	local profit = addon.db.realm.vendorFlipProfit
	local numberColor = profit > 0 and GREEN_NUMBER or profit < 0 and RED_NUMBER or nil
	return addon:FormatMoney(profit, true, numberColor)
end

function module:RefreshDisplay()
	if profitText then
		profitText:SetFormattedText(L["Vendor flip profit: %s"], self:GetFormattedProfit())
	end
	AceConfigRegistry:NotifyChange("YAAHA")
end

function module:RecordPurchase(itemID, quantity, purchaseValue)
	if not itemID or not quantity or quantity < 1 or not purchaseValue or purchaseValue < 1 then
		return
	end

	local inventory = GetInventory()
	inventory[itemID] = (inventory[itemID] or 0) + quantity
	itemCounts[itemID] = GetTrackedCount(itemID)
	addon.db.realm.vendorFlipProfit = addon.db.realm.vendorFlipProfit - purchaseValue
	self:RefreshDisplay()
end

function module:RecordSale(itemID, quantity, proceeds)
	local inventory = GetInventory()
	local outstanding = inventory[itemID]
	if not outstanding or outstanding < 1 or not quantity or quantity < 1
		or not proceeds or proceeds < 1 then
		return
	end

	local attributedQuantity = min(quantity, outstanding)
	-- Identical units in a stack share one per-unit sale price. If only part of the
	-- stack was bought as a vendor flip, credit the same fraction of actual proceeds.
	local attributedProceeds = floor(proceeds * attributedQuantity / quantity + 0.5)
	addon.db.realm.vendorFlipProfit = addon.db.realm.vendorFlipProfit + attributedProceeds
	inventory[itemID] = outstanding > attributedQuantity and outstanding - attributedQuantity or nil
	self:RefreshDisplay()
end

function module:PreserveQuantity(itemID, quantity)
	if not itemID or not quantity or quantity < 1 then
		return
	end

	local pending = pendingLosses[itemID]
	if pending then
		local preserved = min(quantity, pending.quantity)
		pending.quantity = pending.quantity - preserved
		quantity = quantity - preserved
		if pending.quantity == 0 then
			pendingLosses[itemID] = nil
		end
	end
	if quantity < 1 then
		return
	end

	-- Some disposition callbacks precede BAG_UPDATE_DELAYED. This one-shot credit is
	-- consumed by the matching bag loss and expires before it can mask a later loss.
	preservedQuantities[itemID] = (preservedQuantities[itemID] or 0) + quantity
	C_Timer.After(RETIRE_DELAY, function()
		local credit = preservedQuantities[itemID]
		if credit then
			preservedQuantities[itemID] = credit > quantity and credit - quantity or nil
		end
	end)
end

function module:Reset()
	addon.db.realm.vendorFlipCOD = {}
	addon.db.realm.vendorFlipInventory = {}
	addon.db.realm.vendorFlipProfit = 0
	itemCounts = {}
	pendingLosses = {}
	preservedQuantities = {}
	self:RefreshDisplay()
end

local function CreateDisplay()
	if profitText then
		return
	end
	local parent = auctionHouseUI:GetScanButtonParent()
	local scanButton = scanner:GetScanButton()
	if not parent or not scanButton then
		return
	end

	profitText = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	profitText:SetPoint("LEFT", scanButton, "RIGHT", 12, 0)
	profitText:SetWidth(205)
	profitText:SetJustifyH("LEFT")
	module:RefreshDisplay()
end

local function ReadTradeItems(infoFunction, linkFunction)
	local items = {}
	for index = 1, 6 do
		local _, _, quantity = infoFunction(index)
		local itemID = GetItemID(linkFunction(index))
		if itemID and quantity and quantity > 0 then
			items[itemID] = (items[itemID] or 0) + quantity
		end
	end
	return items
end

local function CountItemKinds(items)
	local count = 0
	local onlyItemID
	local onlyQuantity
	for itemID, quantity in pairs(items) do
		count = count + 1
		onlyItemID = itemID
		onlyQuantity = quantity
	end
	return count, onlyItemID, onlyQuantity
end

local function CaptureTrade()
	tradeSnapshot = {
		incoming = ReadTradeItems(GetTradeTargetItemInfo, GetTradeTargetItemLink),
		moneyGiven = GetPlayerTradeMoney(),
		moneyReceived = GetTargetTradeMoney(),
		outgoing = ReadTradeItems(GetTradePlayerItemInfo, GetTradePlayerItemLink),
		target = GetUnitName("NPC", true) or GetUnitName("target", true),
	}
end

local function CaptureOutgoingMail(recipient, subject)
	local items = {}
	for index = 1, ATTACHMENTS_MAX_SEND do
		local itemName, _, quantity = GetSendMailItem(index)
		if itemName and quantity and quantity > 0 then
			local itemLink = GetSendMailItemLink(index)
			local itemID = GetItemID(itemLink)
			if itemID then
				items[itemID] = (items[itemID] or 0) + quantity
			end
		end
	end
	outgoingMail = {
		cod = GetSendMailCOD(),
		items = items,
		recipient = recipient,
		subject = subject,
	}
end

function module:AUCTION_HOUSE_SHOW()
	CreateDisplay()
	self:RefreshDisplay()
end

function module:BAG_UPDATE_DELAYED()
	local inventory = GetInventory()
	for itemID, outstanding in pairs(inventory) do
		if outstanding > 0 then
			local previousCount = itemCounts[itemID]
			local currentCount = GetTrackedCount(itemID)
			if previousCount and currentCount < previousCount then
				local removed = previousCount - currentCount
				local credit = preservedQuantities[itemID] or 0
				local preserved = min(removed, credit)
				removed = removed - preserved
				preservedQuantities[itemID] = credit > preserved and credit - preserved or nil
				if removed > 0 and merchantOpen then
					local _, _, _, _, _, _, _, _, _, _, vendorSell = C_Item.GetItemInfo(itemID)
					if vendorSell and vendorSell > 0 then
						self:RecordSale(itemID, removed, vendorSell * removed)
					else
						ScheduleRetirement(itemID, removed)
					end
				elseif removed > 0 then
					ScheduleRetirement(itemID, removed)
				end
			end
			itemCounts[itemID] = currentCount
		end
	end
end

function module:MAIL_FAILED()
	outgoingMail = nil
end

function module:MAIL_SEND_SUCCESS()
	if not outgoingMail then
		return
	end
	local kindCount, itemID, quantity = CountItemKinds(outgoingMail.items)
	local recipientIsAlt = addon.db.global.alts[outgoingMail.recipient]
	for outgoingItemID, outgoingQuantity in pairs(outgoingMail.items) do
		if recipientIsAlt then
			inventoryAverageBuy:MoveOutOfInventory(outgoingItemID, outgoingQuantity)
		else
			inventoryAverageBuy:RecordRemoval(outgoingItemID, outgoingQuantity)
		end
	end
	if outgoingMail.cod > 0 then
		-- A single-item COD has an unambiguous price allocation. Mixed COD mail is
		-- deliberately ignored because no truthful per-item allocation is possible.
		if kindCount == 1 and GetInventory()[itemID] and GetInventory()[itemID] >= quantity then
			self:PreserveQuantity(itemID, quantity)
			addon.db.realm.vendorFlipCOD[#addon.db.realm.vendorFlipCOD + 1] = {
				itemID = itemID,
				quantity = quantity,
				proceeds = outgoingMail.cod,
				recipient = CharacterName(outgoingMail.recipient),
				subject = format(COD_PAYMENT, outgoingMail.subject),
			}
		end
	else
		for outgoingItemID, outgoingQuantity in pairs(outgoingMail.items) do
			self:PreserveQuantity(outgoingItemID, outgoingQuantity)
		end
	end
	outgoingMail = nil
end

function module:RecordMailProceeds(sender, subject, proceeds)
	if not sender or not subject or not proceeds or proceeds < 1 then
		return
	end
	local cod = addon.db.realm.vendorFlipCOD
	for index = #cod, 1, -1 do
		local pending = cod[index]
		if pending.recipient == CharacterName(sender) and pending.subject == subject
			and pending.proceeds == proceeds then
			self:RecordSale(pending.itemID, pending.quantity, proceeds)
			tableRemove(cod, index)
			return
		end
	end
end

function module:MERCHANT_CLOSED()
	merchantOpen = false
end

function module:MERCHANT_SHOW()
	merchantOpen = true
	SnapshotTrackedItems()
end

function module:TRADE_ACCEPT_UPDATE(_, playerAccepted, targetAccepted)
	if playerAccepted == 1 and targetAccepted == 1 then
		CaptureTrade()
	else
		tradeSnapshot = nil
	end
end

function module:TRADE_CLOSED()
	if not tradeSnapshot then
		return
	end
	local outgoingKinds, outgoingItemID, outgoingQuantity = CountItemKinds(tradeSnapshot.outgoing)
	local targetIsAlt = tradeSnapshot.target and addon.db.global.alts[tradeSnapshot.target]
	for itemID, quantity in pairs(tradeSnapshot.outgoing) do
		if targetIsAlt then
			inventoryAverageBuy:MoveOutOfInventory(itemID, quantity)
		else
			inventoryAverageBuy:RecordRemoval(itemID, quantity)
		end
	end
	if tradeSnapshot.moneyReceived > 0 then
		if outgoingKinds == 1 and GetInventory()[outgoingItemID]
			and GetInventory()[outgoingItemID] >= outgoingQuantity then
			self:PreserveQuantity(outgoingItemID, outgoingQuantity)
			self:RecordSale(outgoingItemID, outgoingQuantity, tradeSnapshot.moneyReceived)
		end
	else
		for itemID, quantity in pairs(tradeSnapshot.outgoing) do
			self:PreserveQuantity(itemID, quantity)
		end
	end

	local incomingKinds, incomingItemID, incomingQuantity = CountItemKinds(tradeSnapshot.incoming)
	if incomingKinds == 1 and outgoingKinds == 0 and tradeSnapshot.moneyGiven > 0
		and tradeSnapshot.moneyReceived == 0 and not targetIsAlt then
		inventoryAverageBuy:RecordPurchase(incomingItemID, incomingQuantity, tradeSnapshot.moneyGiven)
		local _, _, _, _, _, _, _, _, _, _, vendorSell = C_Item.GetItemInfo(incomingItemID)
		local vendorReturn = vendorSell and vendorSell * incomingQuantity or 0
		if vendorReturn > 0 and (addon.db.profile.includeBreakEvenVendorFlips
			and tradeSnapshot.moneyGiven <= vendorReturn or tradeSnapshot.moneyGiven < vendorReturn) then
			self:RecordPurchase(incomingItemID, incomingQuantity, tradeSnapshot.moneyGiven)
		end
	end
	tradeSnapshot = nil
end

function module:OnEnable()
	SnapshotTrackedItems()
	self:RegisterEvent("AUCTION_HOUSE_SHOW")
	self:RegisterEvent("BAG_UPDATE_DELAYED")
	self:RegisterEvent("MAIL_FAILED")
	self:RegisterEvent("MAIL_SEND_SUCCESS")
	self:RegisterEvent("MERCHANT_CLOSED")
	self:RegisterEvent("MERCHANT_SHOW")
	self:RegisterEvent("TRADE_ACCEPT_UPDATE")
	self:RegisterEvent("TRADE_CLOSED")
	hooksecurefunc("SendMail", CaptureOutgoingMail)
end