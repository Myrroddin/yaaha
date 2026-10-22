-- Tracks the player's outstanding vendor-flip inventory and realized profit.

local AceConfigRegistry
local C_Item = C_Item
local C_Timer = C_Timer
local COD_PAYMENT = COD_PAYMENT
local floor = math.floor
local format = string.format
local GetPlayerTradeMoney = GetPlayerTradeMoney
local GetServerTime = GetServerTime
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
local LE_GAME_ERR_TRADE_COMPLETE = LE_GAME_ERR_TRADE_COMPLETE
local LibStub = LibStub
local min = math.min
local pairs = pairs
local tableRemove = table.remove

AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local module = addon:NewModule("VendorFlipTracking", "AceEvent-3.0")
local auctionHouseUI = addon:GetModule("AuctionHouseUI")
local inventoryAverageBuy = addon:GetModule("InventoryAverageBuy")
local L = LibStub("AceLocale-3.0"):GetLocale("YAAHA")

local GREEN_NUMBER = addon.positiveNumberColor
local RED_NUMBER = addon.negativeNumberColor
local RETIRE_DELAY = 3
local itemCounts = {}
local merchantOpen = false
local outgoingMail
local pendingLosses = {}
local preservedQuantities = {}
local profitText
local tradeSnapshot

local function GetInventory()
	return addon.db.realm.vendorFlip.inventory
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
	local profit = addon.db.realm.vendorFlip.profit
	local numberColor = profit > 0 and GREEN_NUMBER or profit < 0 and RED_NUMBER or nil
	return addon:FormatMoney(profit, true, numberColor)
end

function module:RefreshDisplay()
	if profitText then
		profitText:SetFormattedText(L["Vendor flip profit: %s"], self:GetFormattedProfit())
	end
	addon:RefreshBrokerText()
	AceConfigRegistry:NotifyChange("YAAHA")
end

function module:RecordPurchase(itemID, quantity, purchaseValue)
	if not itemID or not quantity or quantity < 1 or not purchaseValue or purchaseValue < 1 then
		return
	end

	local inventory = GetInventory()
	inventory[itemID] = (inventory[itemID] or 0) + quantity
	itemCounts[itemID] = GetTrackedCount(itemID)
	addon.db.realm.vendorFlip.profit = addon.db.realm.vendorFlip.profit - purchaseValue
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
	addon.db.realm.vendorFlip.profit = addon.db.realm.vendorFlip.profit + attributedProceeds
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
	addon.db.realm.vendorFlip.cod = {}
	addon.db.realm.vendorFlip.inventory = {}
	addon.db.realm.vendorFlip.profit = 0
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
	if not parent then
		return
	end

	profitText = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	profitText:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -14, -16)
	profitText:SetWidth(300)
	profitText:SetJustifyH("RIGHT")
	module:RefreshDisplay()
end

local function ReadTradeItems(infoFunction, linkFunction)
	local items = {}
	for index = 1, 6 do
		local _, _, quantity = infoFunction(index)
		local itemID = addon:GetItemID(linkFunction(index))
		if itemID and quantity and quantity > 0 then
			items[itemID] = (items[itemID] or 0) + quantity
		end
	end
	return items
end

local function CountItemKinds(items)
	-- Multiple stacks or trade slots of the same item remain one item kind; their
	-- quantities were combined by ReadTradeItems.
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
			local itemID = addon:GetItemID(itemLink)
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
	local recipientIsAlt = addon:IsAlt(outgoingMail.recipient)
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
		local recipient = addon:NormalizeCharacterName(outgoingMail.recipient)
		if kindCount == 1 and recipient
			and GetInventory()[itemID] and GetInventory()[itemID] >= quantity then
			self:PreserveQuantity(itemID, quantity)
			local cod = addon.db.realm.vendorFlip.cod
			cod[#cod + 1] = {
				itemID = itemID,
				quantity = quantity,
				proceeds = outgoingMail.cod,
				recipient = recipient,
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
	local normalizedSender = addon:NormalizeCharacterName(sender)
	if not normalizedSender then
		return
	end
	local cod = addon.db.realm.vendorFlip.cod
	for index = #cod, 1, -1 do
		local pending = cod[index]
		if pending.recipient == normalizedSender and pending.subject == subject
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
	-- Keep the latest accepted state, but do not treat closing the window as success.
	-- Blizzard confirms completion separately through UI_INFO_MESSAGE.
	if (playerAccepted == 1 or targetAccepted == 1)
		and not (GetTradePlayerItemLink(7) or GetTradeTargetItemLink(7)) then
		CaptureTrade()
	else
		tradeSnapshot = nil
	end
end

local function CompleteTrade()
	if not tradeSnapshot then
		return
	end
	local completedTrade = tradeSnapshot
	tradeSnapshot = nil
	local outgoingKinds, outgoingItemID, outgoingQuantity = CountItemKinds(completedTrade.outgoing)
	local incomingKinds, incomingItemID, incomingQuantity = CountItemKinds(completedTrade.incoming)
	local targetIsAlt = completedTrade.target and addon:IsAlt(completedTrade.target)
	for itemID, quantity in pairs(completedTrade.outgoing) do
		if targetIsAlt then
			inventoryAverageBuy:MoveOutOfInventory(itemID, quantity)
		else
			inventoryAverageBuy:RecordRemoval(itemID, quantity)
		end
	end
	-- Coins can be assigned truthfully only when one item kind moves in one direction.
	-- Multiple stacks of that item are valid because ReadTradeItems combines them.
	local isSale = outgoingKinds == 1 and incomingKinds == 0
		and completedTrade.moneyReceived > 0 and completedTrade.moneyGiven == 0
		and not targetIsAlt
	if isSale then
		module:SendMessage("YAAHA_TRADE_SALE", outgoingItemID, outgoingQuantity,
			completedTrade.moneyReceived, GetServerTime())
		if GetInventory()[outgoingItemID]
			and GetInventory()[outgoingItemID] >= outgoingQuantity then
			module:PreserveQuantity(outgoingItemID, outgoingQuantity)
			module:RecordSale(outgoingItemID, outgoingQuantity, completedTrade.moneyReceived)
		end
	elseif completedTrade.moneyReceived == 0 then
		for itemID, quantity in pairs(completedTrade.outgoing) do
			module:PreserveQuantity(itemID, quantity)
		end
	end

	if incomingKinds == 1 and outgoingKinds == 0 and completedTrade.moneyGiven > 0
		and completedTrade.moneyReceived == 0 and not targetIsAlt then
		inventoryAverageBuy:RecordPurchase(incomingItemID, incomingQuantity, completedTrade.moneyGiven)
		local _, _, _, _, _, _, _, _, _, _, vendorSell = C_Item.GetItemInfo(incomingItemID)
		local vendorReturn = vendorSell and vendorSell * incomingQuantity or 0
		if addon:IsVendorDealProfitable(completedTrade.moneyGiven, vendorReturn) then
			module:RecordPurchase(incomingItemID, incomingQuantity, completedTrade.moneyGiven)
		end
	end
end

function module:UI_INFO_MESSAGE(_, _, message)
	if message == LE_GAME_ERR_TRADE_COMPLETE then
		CompleteTrade()
	end
end

function module:TRADE_CLOSED()
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
	self:RegisterEvent("UI_INFO_MESSAGE")
	hooksecurefunc("SendMail", CaptureOutgoingMail)
end