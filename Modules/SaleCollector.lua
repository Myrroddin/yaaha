local AUCTION_OUTBID_MAIL_SUBJECT = AUCTION_OUTBID_MAIL_SUBJECT
local C_Item = C_Item
local format = string.format
local GetAuctionItemInfo = GetAuctionItemInfo
local GetInboxHeaderInfo = GetInboxHeaderInfo
local GetInboxItem = GetInboxItem
local GetInboxInvoiceInfo = GetInboxInvoiceInfo
local GetInboxNumItems = GetInboxNumItems
local GetNumAuctionItems = GetNumAuctionItems
local GetNormalizedRealmName = GetNormalizedRealmName
local GetServerTime = GetServerTime
local hooksecurefunc = hooksecurefunc
local LibStub = LibStub
local pairs = pairs
local stringGsub = string.gsub
local stringMatch = string.match
local tableRemove = table.remove
local UnitFullName = UnitFullName

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local module = addon:NewModule("SaleCollector", "AceEvent-3.0")
local inventoryAverageBuy = addon:GetModule("InventoryAverageBuy")
local scanner = addon:GetModule("Scanner")
local vendorFlipTracking = addon:GetModule("VendorFlipTracking")
local invoices = {}
local mailboxOpen = false
local moneyMail = {}
local SECONDS_PER_DAY = 24 * 60 * 60
local SALE_LEDGER_LIFETIME = 60 * SECONDS_PER_DAY
local playerName, playerRealm, playerFullName
local OUTBID_MAIL_PATTERN = AUCTION_OUTBID_MAIL_SUBJECT
	and "^" .. stringGsub(AUCTION_OUTBID_MAIL_SUBJECT, "%%s", "(.+)") .. "$"

local function InitializePlayerIdentity()
	playerName, playerRealm = UnitFullName("player")
	playerRealm = playerRealm or GetNormalizedRealmName()
	playerFullName = playerRealm and playerRealm ~= "" and playerName .. "-" .. playerRealm or playerName
end

local function TransactionKey(seller, itemID, count, saleValue)
	return format("%s\031%d\031%d\031%d", seller or "", itemID, count, saleValue)
end

local function PruneRealmSales(data, now)
	local observations = data.observations
	local writeIndex = 1
	for index = 1, #observations do
		local observation = observations[index]
		if (observation.source == "seller" or observation.source == "failure")
			and now - observation.timestamp < SECONDS_PER_DAY then
			observations[writeIndex] = observation
			writeIndex = writeIndex + 1
		end
	end
	for index = #observations, writeIndex, -1 do
		observations[index] = nil
	end
end

local function PruneAllRealmSales()
	local now = GetServerTime()
	for _, scope in pairs({ "factionrealm", "realm" }) do
		local realmSales = addon.db[scope].realmSales
		for itemID, data in pairs(realmSales) do
			PruneRealmSales(data, now)
			if not data.observations[1] then
				realmSales[itemID] = nil
			end
		end
	end
end

local function RecordRealmObservation(scope, itemID, attempted, sold, saleValue, source, transactionKey, resolutionKey)
	local realmSales = addon.db[scope].realmSales
	local data = realmSales[itemID]
	if not data then
		data = { observations = {} }
		realmSales[itemID] = data
	end

	local now = GetServerTime()
	PruneRealmSales(data, now)
	local observationIndex = #data.observations + 1
	addon.db.char.syncSequence = addon.db.char.syncSequence + 1
	data.observations[observationIndex] = {
		timestamp = now,
		attempted = attempted,
		sold = sold,
		totalSaleValue = saleValue or 0,
		source = source,
		transactionKey = transactionKey,
		resolutionKey = resolutionKey,
		syncID = format("%s\031%s\031%d\031%d", source, transactionKey,
			now, addon.db.char.syncSequence),
	}
end

local function NewResolutionKey()
	addon.db.char.syncSequence = addon.db.char.syncSequence + 1
	return format("%s\031%d\031%d", playerFullName, GetServerTime(), addon.db.char.syncSequence)
end

local function RemoveRealmFailure(scope, itemID, resolutionKey)
	if not resolutionKey then
		return
	end
	local data = addon.db[scope].realmSales[itemID]
	if not data then
		return
	end
	PruneRealmSales(data, GetServerTime())
	for index = #data.observations, 1, -1 do
		local observation = data.observations[index]
		if observation.source == "failure" and observation.resolutionKey == resolutionKey then
			tableRemove(data.observations, index)
			return
		end
	end
end

local function ListingKey(itemID, count, minBid, buyout)
	return format("%d:%d:%d:%d", itemID, count, minBid, buyout)
end

local function PruneSaleLedger(scope, now)
	local ledger = addon.db.char.saleLedger[scope]
	if not ledger then
		return
	end
	for index = #ledger, 1, -1 do
		if now - ledger[index].timestamp >= SALE_LEDGER_LIFETIME then
			tableRemove(ledger, index)
		end
	end
end

local function AddSaleLedgerEntry(scope, listing)
	local ledger = addon.db.char.saleLedger[scope]
	if not ledger then
		ledger = {}
		addon.db.char.saleLedger[scope] = ledger
	end
	PruneSaleLedger(scope, GetServerTime())
	ledger[#ledger + 1] = {
		itemID = listing.itemID,
		name = listing.name,
		count = listing.count,
		minBid = listing.minBid,
		buyout = listing.buyout,
		resolutionKey = listing.resolutionKey,
		timestamp = GetServerTime(),
	}
end

local function RemoveSaleLedgerEntry(scope, listing)
	local ledger = addon.db.char.saleLedger[scope]
	if not ledger then
		return
	end
	for index = #ledger, 1, -1 do
		local pending = ledger[index]
		if pending.itemID == listing.itemID and pending.count == listing.count
			and pending.minBid == listing.minBid and pending.buyout == listing.buyout then
			tableRemove(ledger, index)
			return
		end
	end
end

local function RecordSale(scope, listing, saleValue)
	local personalSales = addon.db[scope].personalSales
	local data = personalSales[listing.itemID]
	if not data then
		data = { attempted = 0, sold = 0, totalSaleValue = 0 }
		personalSales[listing.itemID] = data
	end

	data.sold = data.sold + listing.count
	data.totalSaleValue = data.totalSaleValue + saleValue
	-- A vanished owner listing is initially a cancellation or expiry. Seller mail can
	-- later prove that exact posting sold, in which case its provisional failure must
	-- be replaced rather than counted alongside the successful outcome.
	RemoveRealmFailure(scope, listing.itemID, listing.resolutionKey)
	-- Realm rates describe outcomes resolved during the rolling window. The original
	-- posting may be hours or days older, so carry both sides of this outcome here.
	RecordRealmObservation(scope, listing.itemID, listing.count, listing.count, saleValue,
		"seller", TransactionKey(playerFullName, listing.itemID, listing.count, saleValue),
		listing.resolutionKey)
end

local function RecordFailure(scope, listing)
	if not listing.resolutionKey then
		return
	end
	RecordRealmObservation(scope, listing.itemID, listing.count, 0, 0,
		"failure", listing.resolutionKey, listing.resolutionKey)
end

local function ReadOwnedAuctions()
	local scope = scanner:GetAuctionScope()
	if not scope then
		return
	end

	local previous = addon.db.char.ownedAuctions[scope] or {}
	local numOwned = GetNumAuctionItems("owner")
	-- A partially resolved owner list can temporarily return nil item information.
	-- Never interpret that transient absence as a cancellation or expiration.
	for index = 1, numOwned do
		local name, _, _, _, _, _, _, minBid, _, buyout, _, _, _, _, _, _, itemID, hasAllInfo = GetAuctionItemInfo("owner", index)
		if hasAllInfo == false or not name or not minBid or not buyout or not itemID then
			return
		end
	end
	local previousByPrice = {}
	for key, listing in pairs(previous) do
		local priceKey = format("%d:%d:%d", listing.itemID, listing.minBid, listing.buyout)
		local matches = previousByPrice[priceKey]
		if not matches then
			matches = {}
			previousByPrice[priceKey] = matches
		end
		matches[#matches + 1] = { key = key, listing = listing }
	end

	local current = {}
	local currentCounts = {}
	local soldKeys = {}
	for index = 1, numOwned do
		local name, _, count, _, _, _, _, minBid, _, buyout, bidAmount, _, _, _, _, saleStatus, itemID = GetAuctionItemInfo("owner", index)
		if itemID and minBid and buyout and name then
			if saleStatus == 1 then
				local priceKey = format("%d:%d:%d", itemID, minBid, buyout)
				local matches = previousByPrice[priceKey]
				local match = matches and matches[#matches]
				if match and not soldKeys[match.key] then
					matches[#matches] = nil
					soldKeys[match.key] = true
					RecordSale(scope, match.listing, bidAmount > 0 and bidAmount or buyout)
					RemoveSaleLedgerEntry(scope, match.listing)
				end
			elseif count and count > 0 then
				local key = ListingKey(itemID, count, minBid, buyout)
				local occurrence = (currentCounts[key] or 0) + 1
				currentCounts[key] = occurrence
				current[key .. ":" .. occurrence] = {
					itemID = itemID,
					name = name,
					count = count,
					minBid = minBid,
					buyout = buyout,
				}
			end
		end
	end

	local previousByListing = {}
	for key, listing in pairs(previous) do
		if not soldKeys[key] then
			local listingKey = ListingKey(listing.itemID, listing.count, listing.minBid, listing.buyout)
			local matches = previousByListing[listingKey]
			if not matches then
				matches = {}
				previousByListing[listingKey] = matches
			end
			matches[#matches + 1] = listing
		end
	end

	for listingKey, count in pairs(currentCounts) do
		local previousMatches = previousByListing[listingKey]
		for occurrence = 1, count do
			local listing = current[listingKey .. ":" .. occurrence]
			local previousListing = previousMatches and previousMatches[#previousMatches]
			if previousListing then
				previousMatches[#previousMatches] = nil
				listing.resolutionKey = previousListing.resolutionKey
			else
				listing.resolutionKey = NewResolutionKey()
				local personalSales = addon.db[scope].personalSales
				local data = personalSales[listing.itemID]
				if not data then
					data = { attempted = 0, sold = 0, totalSaleValue = 0 }
					personalSales[listing.itemID] = data
				end
				data.attempted = data.attempted + listing.count
				AddSaleLedgerEntry(scope, listing)
				inventoryAverageBuy:MoveOutOfInventory(listing.itemID, listing.count)
				vendorFlipTracking:PreserveQuantity(listing.itemID, listing.count)
			end
		end
	end

	-- Any unmatched previous posting disappeared without a sold status. Record it as
	-- a failure now; a later seller invoice can still replace this exact observation.
	for _, matches in pairs(previousByListing) do
		for index = 1, #matches do
			RecordFailure(scope, matches[index])
		end
	end

	addon.db.char.ownedAuctions[scope] = current
end

local function ReadInvoice(index)
	local invoiceType, itemName, _, bid, buyout, _, consignment, _, _, _, count = GetInboxInvoiceInfo(index)
	if invoiceType ~= "seller" and invoiceType ~= "buyer" or not itemName or not count or count < 1 then
		return
	end
	local _, itemID = GetInboxItem(index, 1)
	return {
		invoiceType = invoiceType,
		itemName = itemName,
		itemID = itemID,
		bid = bid,
		buyout = buyout,
		consignment = consignment,
		count = count,
	}
end

local function InvoiceKey(invoice)
	return format("%s\031%s\031%s\031%d\031%d\031%d\031%d", invoice.invoiceType,
		invoice.itemName, invoice.itemID or "", invoice.bid or 0, invoice.buyout or 0,
		invoice.consignment or 0, invoice.count)
end

local function ReadAuctionInvoices()
	local current = {}
	for index = 1, GetInboxNumItems() do
		local invoice = ReadInvoice(index)
		if invoice then
			current[#current + 1] = invoice
		end
	end
	return current
end

local function RecordBuyerCost(invoice)
	if invoice.invoiceType ~= "buyer" or not invoice.itemID then
		return
	end
	local saleValue = invoice.bid and invoice.bid > 0 and invoice.bid or invoice.buyout
	for pendingIndex = #addon.db.char.pendingPurchases, 1, -1 do
		local pending = addon.db.char.pendingPurchases[pendingIndex]
		if pending.itemID == invoice.itemID and pending.count == invoice.count
			and (not pending.price or pending.price == saleValue) then
			if not pending.inventoryCostRecorded then
				if not pending.seller or not addon.db.global.alts[pending.seller] then
					inventoryAverageBuy:RecordPurchaseOutsideInventory(
						pending.itemID, pending.count, saleValue)
				end
				pending.inventoryCostRecorded = true
			end
			-- Fast mail addons can collect an attachment before YAAHA observes the
			-- invoice disappearing. Record the vendor-flip cost while the buyer
			-- invoice is visible; the flag keeps the disappearance fallback idempotent.
			if pending.vendorFlip and not pending.vendorFlipCostRecorded then
				vendorFlipTracking:RecordPurchase(pending.itemID, pending.count, saleValue)
				pending.vendorFlipCostRecorded = true
			end
			return pending
		end
	end
end

local function ReadMoneyMail()
	local current = {}
	for index = 1, GetInboxNumItems() do
		local _, _, sender, subject, money = GetInboxHeaderInfo(index)
		if sender and subject and money and money > 0 then
			current[#current + 1] = { sender = sender, subject = subject, money = money }
		end
	end
	return current
end

local function MoneyMailKey(mail)
	return format("%s\031%s\031%d", mail.sender, mail.subject, mail.money)
end

local function ResolveOutbidRefund(mail)
	local itemName = OUTBID_MAIL_PATTERN and stringMatch(mail.subject, OUTBID_MAIL_PATTERN)
	if not itemName then
		return false
	end

	for pendingIndex = #addon.db.char.pendingPurchases, 1, -1 do
		local pending = addon.db.char.pendingPurchases[pendingIndex]
		local pendingName = pending.name or C_Item.GetItemInfo(pending.itemID)
		if pending.action == "bid" and pending.price == mail.money and pendingName == itemName then
			-- A returned bid never entered vendor-flip accounting, so resolving it
			-- removes only the pending auction metadata and leaves profit unchanged.
			tableRemove(addon.db.char.pendingPurchases, pendingIndex)
			return true
		end
	end
	return false
end

local function CollectAuctionInvoice(invoice)
	local saleValue = invoice.bid and invoice.bid > 0 and invoice.bid or invoice.buyout

	if invoice.invoiceType == "buyer" then
		for pendingIndex = #addon.db.char.pendingPurchases, 1, -1 do
			local pending = addon.db.char.pendingPurchases[pendingIndex]
			if pending.itemID == invoice.itemID and pending.count == invoice.count
				and (not pending.price or pending.price == saleValue) then
				if not pending.inventoryCostRecorded
					and (not pending.seller or not addon.db.global.alts[pending.seller]) then
					inventoryAverageBuy:RecordPurchase(pending.itemID, pending.count, saleValue)
				end
				if pending.vendorFlip and not pending.vendorFlipCostRecorded then
					vendorFlipTracking:RecordPurchase(pending.itemID, pending.count, saleValue)
					pending.vendorFlipCostRecorded = true
				end
				tableRemove(addon.db.char.pendingPurchases, pendingIndex)
				return
			end
		end
		return
	end

	-- Seller invoices have no itemID or auction-house type. The unresolved-sale
	-- ledger survives owner-list refreshes, cancellations, logout, and mail delays.
	for scope, ledger in pairs(addon.db.char.saleLedger) do
		PruneSaleLedger(scope, GetServerTime())
		for index = #ledger, 1, -1 do
			local listing = ledger[index]
			if listing.name == invoice.itemName and listing.count == invoice.count and listing.buyout == invoice.buyout then
				RecordSale(scope, listing, saleValue)
				inventoryAverageBuy:RecordRemoval(listing.itemID, listing.count)
				vendorFlipTracking:RecordSale(listing.itemID, listing.count,
					saleValue - (invoice.consignment or 0))
				tableRemove(ledger, index)
				return
			end
		end
	end
end

local function CacheAuctionInvoices()
	if not mailboxOpen then
		return
	end

	local current = ReadAuctionInvoices()
	for _, invoice in pairs(current) do
		RecordBuyerCost(invoice)
	end
	local remaining = {}
	for _, invoice in pairs(current) do
		local key = InvoiceKey(invoice)
		remaining[key] = (remaining[key] or 0) + 1
	end

	-- Mail indices shift after every collection, so comparing by index loses track of
	-- bulk-looted messages. A multiset preserves identical invoices while identifying
	-- exactly how many successful auction messages disappeared from the inbox.
	for _, invoice in pairs(invoices) do
		local key = InvoiceKey(invoice)
		if remaining[key] and remaining[key] > 0 then
			remaining[key] = remaining[key] - 1
		else
			CollectAuctionInvoice(invoice)
		end
	end

	invoices = current

	local currentMoneyMail = ReadMoneyMail()
	local remainingMoneyMail = {}
	for _, mail in pairs(currentMoneyMail) do
		local key = MoneyMailKey(mail)
		remainingMoneyMail[key] = (remainingMoneyMail[key] or 0) + 1
	end
	for _, mail in pairs(moneyMail) do
		local key = MoneyMailKey(mail)
		if remainingMoneyMail[key] and remainingMoneyMail[key] > 0 then
			remainingMoneyMail[key] = remainingMoneyMail[key] - 1
		else
			if not ResolveOutbidRefund(mail) then
				vendorFlipTracking:RecordMailProceeds(mail.sender, mail.subject, mail.money)
			end
		end
	end
	moneyMail = currentMoneyMail
end

local function OpenMailbox()
	mailboxOpen = true
	PruneAllRealmSales()
	invoices = ReadAuctionInvoices()
	for _, invoice in pairs(invoices) do
		RecordBuyerCost(invoice)
	end
	moneyMail = ReadMoneyMail()
end

local function CloseMailbox()
	mailboxOpen = false
	invoices = {}
	moneyMail = {}
end

local function RecordPendingPurchase(listType, index, price, action, dealType)
	local scope = scanner:GetAuctionScope()
	if not scope or listType ~= "list" then
		return
	end

	local name, _, count, _, _, _, _, minBid, _, buyout, _, _, _, owner, ownerFullName, _, itemID = GetAuctionItemInfo(listType, index)
	if not itemID or not count or count < 1 then
		return
	end
	local _, _, _, _, _, _, _, _, _, _, vendorSell = C_Item.GetItemInfo(itemID)
	local vendorReturn = vendorSell and vendorSell * count or 0
	local vendorFlip = dealType == "vendor" or dealType == nil and price and price > 0 and vendorReturn > 0
		and (addon.db.profile.includeBreakEvenDeals and price <= vendorReturn or price < vendorReturn)

	local now = GetServerTime()
	local pending = addon.db.char.pendingPurchases
	for pendingIndex = #pending, 1, -1 do
		local purchase = pending[pendingIndex]
		if now - purchase.timestamp >= 30 * SECONDS_PER_DAY then
			tableRemove(pending, pendingIndex)
		elseif action == "bid" and purchase.action == "bid" and purchase.vendorFlip
			and purchase.itemID == itemID and purchase.count == count and purchase.scope == scope
			and purchase.seller == (ownerFullName or owner and playerRealm and owner .. "-" .. playerRealm or owner) then
			-- A later bid on the same live auction supersedes the earlier pending bid.
			-- Keeping one record prevents repeated searches for each bid increment.
			purchase.buyout = buyout
			purchase.minBid = minBid
			purchase.name = name
			purchase.price = price
			purchase.timestamp = now
			purchase.vendorSell = vendorSell
			return purchase
		elseif purchase.itemID == itemID and purchase.count == count and purchase.scope == scope
			and purchase.price == price and now - purchase.timestamp <= 2 then
			purchase.action = action or purchase.action
			purchase.buyout = buyout or purchase.buyout
			purchase.dealType = dealType or purchase.dealType
			purchase.minBid = minBid or purchase.minBid
			purchase.name = name or purchase.name
			purchase.vendorSell = vendorSell or purchase.vendorSell
			if not purchase.dealType then
				purchase.vendorFlip = purchase.vendorFlip or vendorFlip
			end
			return purchase
		end
	end
	local purchase = {
		itemID = itemID,
		count = count,
		action = action,
		buyout = buyout,
		dealType = dealType,
		minBid = minBid,
		name = name,
		scope = scope,
		seller = ownerFullName or owner and playerRealm and owner .. "-" .. playerRealm or owner,
		price = price,
		timestamp = now,
		vendorSell = vendorSell,
		vendorFlip = vendorFlip or nil,
	}
	pending[#pending + 1] = purchase
	return purchase
end

local function HookPendingPurchase(listType, index, price)
	RecordPendingPurchase(listType, index, price)
end

function module:OnInitialize()
	-- GetServerTime continues across logout. Clear the complete rolling realm window
	-- as soon as AceDB is available rather than waiting for a mailbox or sync event.
	PruneAllRealmSales()
end

function module:OnEnable()
	InitializePlayerIdentity()
	self:RegisterEvent("AUCTION_OWNED_LIST_UPDATE", ReadOwnedAuctions)
	self:RegisterEvent("MAIL_INBOX_UPDATE", CacheAuctionInvoices)
	self:RegisterEvent("MAIL_CLOSED", CloseMailbox)
	self:RegisterEvent("MAIL_SHOW", OpenMailbox)
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
end

function module:PLAYER_ENTERING_WORLD()
	-- This event follows addon initialization, so wrappers installed by auction or
	-- mail addons cannot replace the function underneath YAAHA's hook afterward.
	hooksecurefunc("PlaceAuctionBid", HookPendingPurchase)
	self:UnregisterEvent("PLAYER_ENTERING_WORLD")
end

function module:RecordPendingPurchase(listType, index, price, action, dealType)
	return RecordPendingPurchase(listType, index, price, action, dealType)
end

function module:GetPendingVendorBids(scope)
	local now = GetServerTime()
	local pending = addon.db.char.pendingPurchases
	local bids = {}
	for index = #pending, 1, -1 do
		local purchase = pending[index]
		if now - purchase.timestamp >= 30 * SECONDS_PER_DAY then
			tableRemove(pending, index)
		elseif purchase.scope == scope and purchase.vendorFlip and purchase.action == "bid" then
			bids[#bids + 1] = purchase
		end
	end
	return bids
end

function module:DiscardPendingPurchase(purchase)
	for index = #addon.db.char.pendingPurchases, 1, -1 do
		if addon.db.char.pendingPurchases[index] == purchase then
			tableRemove(addon.db.char.pendingPurchases, index)
			return
		end
	end
end

function module:PruneRealmSales()
	PruneAllRealmSales()
end

function module:GetRealmSaleData(itemID, scope, scopeDB)
	scopeDB = scopeDB or addon.db[scope]
	local data = scopeDB.realmSales[itemID]
	if not data then
		return
	end

	PruneRealmSales(data, GetServerTime())
	local attempted, sold, totalSaleValue = 0, 0, 0
	for index = 1, #data.observations do
		local observation = data.observations[index]
		attempted = attempted + observation.attempted
		sold = sold + observation.sold
		totalSaleValue = totalSaleValue + observation.totalSaleValue
	end
	if attempted == 0 and sold == 0 then
		scopeDB.realmSales[itemID] = nil
		return
	end

	return attempted > 0 and sold / attempted or nil, sold,
		sold > 0 and totalSaleValue / sold or nil
end

function module:GetPersonalSaleData(itemID, scope, scopeDB)
	scopeDB = scopeDB or addon.db[scope]
	local data = scopeDB.personalSales[itemID]
	if not data or data.attempted <= 0 then
		return
	end

	return data.sold / data.attempted,
		data.sold > 0 and data.totalSaleValue / data.sold or nil
end