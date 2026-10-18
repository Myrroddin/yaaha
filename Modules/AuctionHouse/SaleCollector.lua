-- Tracks auction outcomes, direct-trade sales, purchases, refunds, and sale-rate observations.

local AUCTION_OUTBID_MAIL_SUBJECT = AUCTION_OUTBID_MAIL_SUBJECT
local C_AuctionHouse = C_AuctionHouse
local C_Item = C_Item
local Enum = Enum
local floor = math.floor
local format = string.format
local GetAuctionItemInfo = GetAuctionItemInfo
local GetInboxHeaderInfo = GetInboxHeaderInfo
local GetInboxItem = GetInboxItem
local GetInboxInvoiceInfo = GetInboxInvoiceInfo
local GetInboxNumItems = GetInboxNumItems
local GetNumAuctionItems = GetNumAuctionItems
local GetServerTime = GetServerTime
local hooksecurefunc = hooksecurefunc
local LibStub = LibStub
local pairs = pairs
local stringGsub = string.gsub
local stringMatch = string.match
local tableRemove = table.remove
local type = type

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local module = addon:NewModule("SaleCollector", "AceEvent-3.0")
local inventoryAverageBuy
local scanner
local vendorFlipTracking
local invoices = {}
local mailboxOpen = false
local moneyMail = {}
local SECONDS_PER_DAY = 24 * 60 * 60
local SALE_HISTORY_DAYS = 60
local SALE_HISTORY_SECONDS = SALE_HISTORY_DAYS * SECONDS_PER_DAY
local AUCTION_MAIL_LIFETIME_DAYS = 30
local playerRealm
local OUTBID_MAIL_PATTERN = AUCTION_OUTBID_MAIL_SUBJECT
	and "^" .. stringGsub(AUCTION_OUTBID_MAIL_SUBJECT, "%%s", "(.+)") .. "$"
local usesModernAuctionHouse = C_AuctionHouse ~= nil and C_AuctionHouse.GetOwnedAuctions ~= nil

local function IsRecentTimestamp(timestamp, now)
	return type(timestamp) == "number" and timestamp <= now
		and now - timestamp < SALE_HISTORY_SECONDS
end

local function IsValidSaleObservation(observation, now, allowTrade)
	if type(observation) ~= "table" then
		return false
	end
	local validSource = observation.source == "seller" or observation.source == "failure"
		or allowTrade and observation.source == "trade"
	if not validSource
		or type(observation.attempted) ~= "number" or observation.attempted <= 0
		or type(observation.sold) ~= "number" or observation.sold < 0
		or observation.sold > observation.attempted
		or type(observation.totalSaleValue) ~= "number" or observation.totalSaleValue < 0
		or not IsRecentTimestamp(observation.timestamp, now) then
		return false
	end
	if observation.source == "failure" then
		return observation.sold == 0 and observation.totalSaleValue == 0
	end
	return observation.sold > 0 and observation.totalSaleValue > 0
end

local function TransactionKey(itemID, count, saleValue)
	return format("%s\031%d\031%d\031%d", addon:GetSyncSourceID(), itemID, count, saleValue)
end

local function PruneRealmSales(data, now)
	local observations = type(data) == "table" and data.observations
	if type(observations) ~= "table" then
		return false
	end
	local writeIndex = 1
	for index = 1, #observations do
		local observation = observations[index]
		if IsValidSaleObservation(observation, now, false) then
			observations[writeIndex] = observation
			writeIndex = writeIndex + 1
		end
	end
	for index = #observations, writeIndex, -1 do
		observations[index] = nil
	end
	return observations[1] ~= nil
end

local function PrunePersonalSales(data, now)
	local observations = type(data) == "table" and data.observations
	if type(observations) ~= "table" then
		return false
	end
	local writeIndex = 1
	for index = 1, #observations do
		local observation = observations[index]
		if IsValidSaleObservation(observation, now, true) then
			observations[writeIndex] = observation
			writeIndex = writeIndex + 1
		end
	end
	for index = #observations, writeIndex, -1 do
		observations[index] = nil
	end
	return observations[1] ~= nil
end

local function PruneAllSales()
	local now = GetServerTime()
	for _, realmSales in pairs(addon.db.realm.sales.auctionHouses) do
		for itemID, data in pairs(realmSales) do
			if not PruneRealmSales(data, now) then
				realmSales[itemID] = nil
			end
		end
	end
	for itemID, data in pairs(addon.db.realm.sales.personal) do
		if not PrunePersonalSales(data, now) then
			addon.db.realm.sales.personal[itemID] = nil
		end
	end
end

local function RecordRealmObservation(auctionHouseType, itemID, attempted, sold, saleValue,
	source, transactionKey, resolutionKey, timestamp)
	local realmSales = addon:GetRealmSales(auctionHouseType)
	local data = realmSales[itemID]
	if type(data) ~= "table" or type(data.observations) ~= "table" then
		data = { observations = {} }
		realmSales[itemID] = data
	end

	local now = GetServerTime()
	timestamp = timestamp or now
	if not IsRecentTimestamp(timestamp, now) then
		return
	end
	PruneRealmSales(data, now)
	local observationIndex = #data.observations + 1
	addon.db.char.syncSequence = addon.db.char.syncSequence + 1
	data.observations[observationIndex] = {
		privateSafe = true,
		timestamp = timestamp,
		attempted = attempted,
		sold = sold,
		totalSaleValue = saleValue or 0,
		source = source,
		transactionKey = transactionKey,
		resolutionKey = resolutionKey,
		syncID = format("%s\031%s\031%d\031%d", source, transactionKey,
			timestamp, addon.db.char.syncSequence),
	}
end

local function RecordPersonalObservation(itemID, attempted, sold, saleValue, source,
	resolutionKey, timestamp)
	local personalSales = addon.db.realm.sales.personal
	local data = personalSales[itemID]
	if type(data) ~= "table" or type(data.observations) ~= "table" then
		data = { observations = {} }
		personalSales[itemID] = data
	end

	local now = GetServerTime()
	timestamp = timestamp or now
	if not IsRecentTimestamp(timestamp, now) then
		return
	end
	PrunePersonalSales(data, now)
	data.observations[#data.observations + 1] = {
		attempted = attempted,
		resolutionKey = resolutionKey,
		sold = sold,
		source = source,
		timestamp = timestamp,
		totalSaleValue = saleValue or 0,
	}
end

local function NewResolutionKey()
	addon.db.char.syncSequence = addon.db.char.syncSequence + 1
	return format("%s\031%d\031%d", addon:GetSyncSourceID(),
		GetServerTime(), addon.db.char.syncSequence)
end

local function RemoveRealmFailure(auctionHouseType, itemID, resolutionKey)
	if not resolutionKey then
		return
	end
	local realmSales = addon:GetRealmSales(auctionHouseType)
	local data = realmSales[itemID]
	if not data then
		return
	end
	if not PruneRealmSales(data, GetServerTime()) then
		realmSales[itemID] = nil
		return
	end
	for index = #data.observations, 1, -1 do
		local observation = data.observations[index]
		if observation.source == "failure" and observation.resolutionKey == resolutionKey then
			tableRemove(data.observations, index)
			return
		end
	end
end

local function RemovePersonalFailure(itemID, resolutionKey)
	if not resolutionKey then
		return
	end
	local data = addon.db.realm.sales.personal[itemID]
	if not data or not PrunePersonalSales(data, GetServerTime()) then
		addon.db.realm.sales.personal[itemID] = nil
		return
	end
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
		if now - ledger[index].timestamp >= SALE_HISTORY_SECONDS then
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
		auctionHouseType = listing.auctionHouseType,
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

local function RecordSale(listing, saleValue, timestamp)
	-- A vanished owner listing is initially a cancellation or expiry. Seller mail can
	-- later prove that exact posting sold, in which case its provisional failure must
	-- be replaced rather than counted alongside the successful outcome.
	RemoveRealmFailure(listing.auctionHouseType, listing.itemID, listing.resolutionKey)
	RemovePersonalFailure(listing.itemID, listing.resolutionKey)
	RecordPersonalObservation(listing.itemID, listing.count, listing.count, saleValue,
		"seller", listing.resolutionKey, timestamp)
	-- Realm rates describe outcomes resolved during the rolling window. The original
	-- posting may be hours or days older, so carry both sides of this outcome here.
	RecordRealmObservation(listing.auctionHouseType, listing.itemID, listing.count, listing.count, saleValue,
		"seller", TransactionKey(listing.itemID, listing.count, saleValue),
		listing.resolutionKey, timestamp)
end

local function RecordFailure(listing)
	if not listing.resolutionKey then
		return
	end
	RecordRealmObservation(listing.auctionHouseType, listing.itemID, listing.count, 0, 0,
		"failure", listing.resolutionKey, listing.resolutionKey)
	RecordPersonalObservation(listing.itemID, listing.count, 0, 0,
		"failure", listing.resolutionKey)
end

local function TrackNewListing(scope, listing)
	listing.resolutionKey = NewResolutionKey()
	AddSaleLedgerEntry(scope, listing)
	inventoryAverageBuy:MoveOutOfInventory(listing.itemID, listing.count)
	vendorFlipTracking:PreserveQuantity(listing.itemID, listing.count)
end

-- Classic exposes owned auctions as an indexed list. Its entries lack stable
-- auction IDs, so matching uses listing properties and occurrence counts.
local function ReadOwnedAuctionsClassic()
	local scope = scanner:GetAuctionScope()
	if not scope then
		return
	end
	local auctionHouseType = addon:GetAuctionHouseTypeForScope(scope)

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
					RecordSale(match.listing, bidAmount > 0 and bidAmount or buyout)
					RemoveSaleLedgerEntry(scope, match.listing)
				end
			elseif count and count > 0 then
				local key = ListingKey(itemID, count, minBid, buyout)
				local occurrence = (currentCounts[key] or 0) + 1
				currentCounts[key] = occurrence
				current[key .. ":" .. occurrence] = {
					auctionHouseType = auctionHouseType,
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
				TrackNewListing(scope, listing)
			end
		end
	end

	-- Any unmatched previous posting disappeared without a sold status. Record it as
	-- a failure now; a later seller invoice can still replace this exact observation.
	for _, matches in pairs(previousByListing) do
		for index = 1, #matches do
			RecordFailure(matches[index])
		end
	end

	addon.db.char.ownedAuctions[scope] = current
end

local function ReadOwnedAuctionsModern()
	local scope = scanner:GetAuctionScope()
	---@diagnostic disable-next-line: wrong-flavor-api
	if not scope or not C_AuctionHouse.HasFullOwnedAuctionResults() then
		return
	end

	local previous = addon.db.char.ownedAuctions[scope] or {}
	local current = {}
	local sold = {}
	local auctionHouseType = addon:GetAuctionHouseTypeForScope(scope)
	---@diagnostic disable-next-line: wrong-flavor-api
	local auctions = C_AuctionHouse.GetOwnedAuctions()
	for index = 1, #auctions do
		local auction = auctions[index]
		local itemID = auction.itemKey and auction.itemKey.itemID
		if itemID and auction.quantity and auction.quantity > 0
			and not C_Item.GetItemNameByID(itemID) then
			C_Item.RequestLoadItemDataByID(itemID)
			return
		end
	end
	for index = 1, #auctions do
		local auction = auctions[index]
		local itemID = auction.itemKey and auction.itemKey.itemID
		local count = auction.quantity
		local unitBid = auction.bidAmount or 0
		local unitBuyout = auction.buyoutAmount or 0
		local name = itemID and C_Item.GetItemNameByID(itemID)
		if itemID and count and count > 0 and name then
			local listing = {
				auctionHouseType = auctionHouseType,
				auctionID = auction.auctionID,
				itemID = itemID,
				name = name,
				count = count,
				minBid = unitBid * count,
				buyout = unitBuyout * count,
			}
			local previousListing = previous[auction.auctionID]
			if auction.status == Enum.AuctionStatus.Sold then
				if previousListing then
					sold[auction.auctionID] = true
					local unitPrice = unitBid > 0 and unitBid or unitBuyout
					RecordSale(previousListing, unitPrice * count)
					RemoveSaleLedgerEntry(scope, previousListing)
				end
			else
				if previousListing then
					listing.resolutionKey = previousListing.resolutionKey
				else
					TrackNewListing(scope, listing)
				end
				current[auction.auctionID] = listing
			end
		end
	end

	for auctionID, listing in pairs(previous) do
		if not current[auctionID] and not sold[auctionID] then
			RecordFailure(listing)
		end
	end
	addon.db.char.ownedAuctions[scope] = current
end

local function QueryOwnedAuctionsModern()
	if not scanner:GetAuctionScope() then
		return
	end
	---@diagnostic disable-next-line: wrong-flavor-api
	C_AuctionHouse.QueryOwnedAuctions({ {
		sortOrder = Enum.AuctionHouseSortOrder.Name,
		reverseSort = false,
	} })
end

local function ReadInvoice(index)
	local invoiceType, itemName, _, bid, buyout, _, consignment, _, _, _, count = GetInboxInvoiceInfo(index)
	if invoiceType ~= "seller" and invoiceType ~= "buyer" or not itemName or not count or count < 1 then
		return
	end
	local _, itemID = GetInboxItem(index, 1)
	local _, _, _, _, _, _, daysLeft = GetInboxHeaderInfo(index)
	local now = GetServerTime()
	local timestamp = type(daysLeft) == "number"
		and now + (daysLeft - AUCTION_MAIL_LIFETIME_DAYS) * SECONDS_PER_DAY or now
	-- Auction mail lasts 30 days. Its remaining lifetime therefore recovers when
	-- the sale arrived instead of incorrectly dating it when the player loots it.
	timestamp = floor((timestamp <= now and timestamp or now) + 0.5)
	return {
		invoiceType = invoiceType,
		itemName = itemName,
		itemID = itemID,
		bid = bid,
		buyout = buyout,
		consignment = consignment,
		count = count,
		timestamp = timestamp,
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
				if not pending.seller or not addon:IsAlt(pending.seller) then
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
					and (not pending.seller or not addon:IsAlt(pending.seller)) then
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
				RecordSale(listing, saleValue, invoice.timestamp)
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
	PruneAllSales()
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
	if usesModernAuctionHouse then
		return
	end
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
	local vendorFlip = dealType == "vendor" or dealType == nil
		and addon:IsVendorDealProfitable(price, vendorReturn)
	local seller = ownerFullName and addon:NormalizeCharacterName(ownerFullName)
		or owner and addon:NormalizeCharacterName(owner, playerRealm)

	local now = GetServerTime()
	local pending = addon.db.char.pendingPurchases
	for pendingIndex = #pending, 1, -1 do
		local purchase = pending[pendingIndex]
		if now - purchase.timestamp >= 30 * SECONDS_PER_DAY then
			tableRemove(pending, pendingIndex)
		elseif action == "bid" and purchase.action == "bid" and purchase.vendorFlip
			and purchase.itemID == itemID and purchase.count == count and purchase.scope == scope
			and purchase.seller == seller then
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
		seller = seller,
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
	inventoryAverageBuy = addon:GetModule("InventoryAverageBuy")
	scanner = addon:GetModule("Scanner")
	vendorFlipTracking = addon:GetModule("VendorFlipTracking")
	-- GetServerTime continues across logout. Clear the complete rolling sale window
	-- as soon as AceDB is available rather than waiting for a mailbox or sync event.
	PruneAllSales()
end

function module:OnEnable()
	local _, realm = addon:GetPlayerIdentity()
	playerRealm = realm
	self:RegisterEvent("MAIL_INBOX_UPDATE", CacheAuctionInvoices)
	self:RegisterEvent("MAIL_CLOSED", CloseMailbox)
	self:RegisterEvent("MAIL_SHOW", OpenMailbox)
	self:RegisterMessage("YAAHA_TRADE_SALE")
	if usesModernAuctionHouse then
		self:RegisterEvent("AUCTION_HOUSE_SHOW", QueryOwnedAuctionsModern)
		self:RegisterEvent("OWNED_AUCTIONS_UPDATED", ReadOwnedAuctionsModern)
	else
		self:RegisterEvent("AUCTION_OWNED_LIST_UPDATE", ReadOwnedAuctionsClassic)
		self:RegisterEvent("PLAYER_ENTERING_WORLD")
	end
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
	PruneAllSales()
end

function module:GetRealmSaleData(itemID, auctionHouseType)
	local realmSales = addon:GetRealmSales(auctionHouseType)
	local data = realmSales[itemID]
	if not data then
		return
	end

	if not PruneRealmSales(data, GetServerTime()) then
		realmSales[itemID] = nil
		return
	end
	local attempted, sold, totalSaleValue = 0, 0, 0
	for index = 1, #data.observations do
		local observation = data.observations[index]
		attempted = attempted + observation.attempted
		sold = sold + observation.sold
		totalSaleValue = totalSaleValue + observation.totalSaleValue
	end
	if attempted == 0 and sold == 0 then
		realmSales[itemID] = nil
		return
	end

	return attempted > 0 and sold / attempted or nil, sold / SALE_HISTORY_DAYS,
		sold > 0 and totalSaleValue / sold or nil
end

function module:GetPersonalSaleData(itemID)
	local data = addon.db.realm.sales.personal[itemID]
	if not data or not PrunePersonalSales(data, GetServerTime()) then
		addon.db.realm.sales.personal[itemID] = nil
		return
	end

	local attempted, sold, totalSaleValue = 0, 0, 0
	for index = 1, #data.observations do
		local observation = data.observations[index]
		attempted = attempted + observation.attempted
		sold = sold + observation.sold
		totalSaleValue = totalSaleValue + observation.totalSaleValue
	end
	if attempted <= 0 then
		addon.db.realm.sales.personal[itemID] = nil
		return
	end

	return sold / attempted, sold > 0 and totalSaleValue / sold or nil
end

function module:YAAHA_TRADE_SALE(_, itemID, quantity, saleValue, timestamp)
	if type(itemID) ~= "number" or itemID < 1 or type(quantity) ~= "number"
		or quantity < 1 or type(saleValue) ~= "number" or saleValue < 1 then
		return
	end
	RecordPersonalObservation(itemID, quantity, quantity, saleValue, "trade", nil, timestamp)
end