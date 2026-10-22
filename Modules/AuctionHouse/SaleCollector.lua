-- Tracks auction outcomes, direct-trade sales, purchases, refunds, and sale-rate observations.

local AUCTION_OUTBID_MAIL_SUBJECT = AUCTION_OUTBID_MAIL_SUBJECT
local C_AuctionHouse = C_AuctionHouse
local C_Item = C_Item
local Enum = Enum
local abs = math.abs
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
local max = math.max
local min = math.min
local pairs = pairs
local stringByte = string.byte
local stringGsub = string.gsub
local stringMatch = string.match
local tableRemove = table.remove
local type = type
local wipe = wipe

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local module = addon:NewModule("SaleCollector", "AceEvent-3.0")
local inventoryAverageBuy
local scanner
local vendorFlipTracking
local invoices = {}
local mailboxOpen = false
local moneyMail = {}
local SECONDS_PER_DAY = addon.secondsPerDay
local SALE_HISTORY_DAYS = addon.saleHistoryDays
local SALE_HISTORY_SECONDS = addon.saleHistorySeconds
local SALE_MATCH_SECONDS = 2 * 60 * 60
local AUCTION_MAIL_LIFETIME_DAYS = 30
local AUCTION_HOUSE_TYPES = addon.usesSharedAuctionHouse
	and { "Shared" } or { "Alliance", "Horde", "Neutral" }
local playerFullName
local classicPurchaseHookClaim
local modernAuctions = {}
local pendingCommodityPurchase
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
		or not allowTrade and observation.source == "buyer"
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

local function SellerFingerprint(seller)
	local value = 0
	for index = 1, #seller do
		value = (value * 33 + stringByte(seller, index)) % 2147483647
	end
	return value
end

local function ApplyInvoiceSeller(purchase, seller)
	if not seller then
		return true
	elseif purchase.seller and purchase.seller ~= seller then
		return false
	end

	purchase.seller = seller
	purchase.matchSeller = seller
	return true
end

local function ResolveListingAuctionHouseType(scope, listing)
	-- Seller invoices omit the market type. Recover it from the ledger scope, which
	-- also repairs entries saved before listings stored auctionHouseType directly.
	local auctionHouseType = listing.auctionHouseType or addon:GetAuctionHouseTypeForScope(scope)
	if auctionHouseType then
		listing.auctionHouseType = auctionHouseType
	end
	return auctionHouseType
end

local function MatchKey(auctionHouseType, itemID, count, saleValue, seller, auctionID)
	-- Modern auction IDs are authoritative. Classic lacks them, so its fingerprint
	-- deliberately combines every invoice field available without exposing names.
	if not auctionHouseType then
		return
	elseif auctionID then
		return format("auction\031%s\031%d\031%d\031%d",
			auctionHouseType, auctionID, count, saleValue)
	elseif seller then
		return format("listing\031%s\031%d\031%d\031%d\031%d",
			auctionHouseType, SellerFingerprint(seller), itemID, count, saleValue)
	end
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

local function GetTrackingStarted(auctionHouseType, now)
	local _, resolvedType = addon:GetRealmSales(auctionHouseType)
	local trackingStarted = addon.db.realm.sales.trackingStarted
	local timestamp = trackingStarted[resolvedType]
	if type(timestamp) ~= "number" or timestamp > now then
		timestamp = now
		trackingStarted[resolvedType] = timestamp
	end
	return max(timestamp, now - SALE_HISTORY_SECONDS), resolvedType
end

local function MergeTrackingStarted(auctionHouseType, timestamp, now)
	if type(timestamp) ~= "number" or timestamp > now then
		return false
	end
	timestamp = max(timestamp, now - SALE_HISTORY_SECONDS)
	local current, resolvedType = GetTrackingStarted(auctionHouseType, now)
	if timestamp >= current then
		return false
	end
	addon.db.realm.sales.trackingStarted[resolvedType] = timestamp
	return true
end

local function InitializeTrackingStarted()
	local now = GetServerTime()
	for index = 1, #AUCTION_HOUSE_TYPES do
		local auctionHouseType = AUCTION_HOUSE_TYPES[index]
		local realmSales = addon:GetRealmSales(auctionHouseType)
		local earliest = now
		for _, data in pairs(realmSales) do
			for observationIndex = 1, #(data.observations or {}) do
				local timestamp = data.observations[observationIndex].timestamp
				if type(timestamp) == "number" and timestamp <= now then
					earliest = min(earliest, timestamp)
				end
			end
		end
		MergeTrackingStarted(auctionHouseType, earliest, now)
	end
end

local function RecordRealmObservation(auctionHouseType, itemID, attempted, sold, saleValue,
	source, transactionKey, resolutionKey, timestamp, matchKey, auctionID)
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
	MergeTrackingStarted(auctionHouseType, timestamp, now)
	PruneRealmSales(data, now)
	local observationIndex = #data.observations + 1
	addon.db.char.syncSequence = addon.db.char.syncSequence + 1
	data.observations[observationIndex] = {
		auctionID = auctionID,
		matchKey = matchKey,
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
	local auctionHouseType = ResolveListingAuctionHouseType(scope, listing)
	if not auctionHouseType then
		return false
	end
	local ledger = addon.db.char.saleLedger[scope]
	if not ledger then
		ledger = {}
		addon.db.char.saleLedger[scope] = ledger
	end
	PruneSaleLedger(scope, GetServerTime())
	ledger[#ledger + 1] = {
		auctionID = listing.auctionID,
		auctionHouseType = auctionHouseType,
		itemID = listing.itemID,
		name = listing.name,
		count = listing.count,
		minBid = listing.minBid,
		matchSeller = listing.matchSeller,
		buyout = listing.buyout,
		resolutionKey = listing.resolutionKey,
		seller = listing.seller,
		timestamp = GetServerTime(),
	}
	return true
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

local function RecordSale(scope, listing, saleValue, timestamp)
	local auctionHouseType = ResolveListingAuctionHouseType(scope, listing)
	if not auctionHouseType then
		return false
	end
	listing.seller = listing.seller or playerFullName
	-- A vanished owner listing is initially a cancellation or expiry. Seller mail can
	-- later prove that exact posting sold, in which case its provisional failure must
	-- be replaced rather than counted alongside the successful outcome.
	RemoveRealmFailure(auctionHouseType, listing.itemID, listing.resolutionKey)
	RemovePersonalFailure(listing.itemID, listing.resolutionKey)
	RecordPersonalObservation(listing.itemID, listing.count, listing.count, saleValue,
		"seller", listing.resolutionKey, timestamp)
	-- Realm rates describe outcomes resolved during the rolling window. The original
	-- posting may be hours or days older, so carry both sides of this outcome here.
	RecordRealmObservation(auctionHouseType, listing.itemID, listing.count, listing.count, saleValue,
		"seller", TransactionKey(listing.itemID, listing.count, saleValue),
		listing.resolutionKey, timestamp,
		MatchKey(auctionHouseType, listing.itemID, listing.count, saleValue,
			listing.matchSeller or listing.seller, listing.auctionID), listing.auctionID)
	return true
end

local function RecordFailure(scope, listing)
	if not listing.resolutionKey then
		return
	end
	local auctionHouseType = ResolveListingAuctionHouseType(scope, listing)
	if not auctionHouseType then
		return
	end
	RecordRealmObservation(auctionHouseType, listing.itemID, listing.count, 0, 0,
		"failure", listing.resolutionKey, listing.resolutionKey)
	RecordPersonalObservation(listing.itemID, listing.count, 0, 0,
		"failure", listing.resolutionKey)
end

local function TrackNewListing(scope, listing)
	listing.resolutionKey = NewResolutionKey()
	listing.seller = playerFullName
	listing.matchSeller = playerFullName
	if not AddSaleLedgerEntry(scope, listing) then
		return
	end
	inventoryAverageBuy:MoveOutOfInventory(listing.itemID, listing.count)
	vendorFlipTracking:PreserveQuantity(listing.itemID, listing.count)
end

local function RecordConfirmedPurchase(purchase, saleValue, timestamp)
	if purchase.realmSaleRecorded then
		return
	end
	-- A purchase confirms market activity but is not the player's sale. Purchases
	-- therefore affect only realm metrics, and transfers between known alts affect
	-- neither side because no external market participant was involved.
	if purchase.seller and addon:IsAlt(purchase.seller) then
		purchase.realmSaleRecorded = true
		return
	end

	local auctionHouseType = purchase.auctionHouseType
		or addon:GetAuctionHouseTypeForScope(purchase.scope)
	if not auctionHouseType or not purchase.itemID or not purchase.count
		or purchase.count < 1 or not saleValue or saleValue < 1 then
		return
	end
	purchase.realmSaleRecorded = true
	RecordRealmObservation(auctionHouseType, purchase.itemID, purchase.count,
		purchase.count, saleValue, "buyer",
		TransactionKey(purchase.itemID, purchase.count, saleValue), nil, timestamp,
		MatchKey(auctionHouseType, purchase.itemID, purchase.count, saleValue,
			purchase.matchSeller, purchase.auctionID), purchase.auctionID)
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
					if RecordSale(scope, match.listing, bidAmount > 0 and bidAmount or buyout) then
						RemoveSaleLedgerEntry(scope, match.listing)
					end
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
			RecordFailure(scope, matches[index])
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
					if RecordSale(scope, previousListing, unitPrice * count) then
						RemoveSaleLedgerEntry(scope, previousListing)
					end
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
			RecordFailure(scope, listing)
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

local function CacheModernItemAuctions(_, itemKey)
	if not itemKey or not itemKey.itemID then
		return
	end
	---@diagnostic disable-next-line: wrong-flavor-api
	for index = 1, C_AuctionHouse.GetNumItemSearchResults(itemKey) do
		---@diagnostic disable-next-line: wrong-flavor-api
		local result = C_AuctionHouse.GetItemSearchResultInfo(itemKey, index)
		if result and result.auctionID then
			modernAuctions[result.auctionID] = {
				auctionID = result.auctionID,
				buyout = result.buyoutAmount,
				count = result.quantity,
				itemID = itemKey.itemID,
			}
		end
	end
end

local function HookModernItemPurchase(auctionID, price)
	local listing = modernAuctions[auctionID]
	local scope = scanner:GetAuctionScope()
	if not listing or not scope or not listing.buyout or listing.buyout ~= price then
		return
	end

	local pending = addon.db.char.pendingPurchases
	for index = #pending, 1, -1 do
		if pending[index].auctionID == auctionID then
			pending[index].price = price
			pending[index].timestamp = GetServerTime()
			return
		end
	end
	pending[#pending + 1] = {
		action = "buy",
		auctionHouseType = addon:GetAuctionHouseTypeForScope(scope),
		auctionID = auctionID,
		buyout = price,
		count = listing.count,
		itemID = listing.itemID,
		price = price,
		scope = scope,
		timestamp = GetServerTime(),
	}
end

local function ConfirmModernItemPurchase(_, auctionID)
	for index = #addon.db.char.pendingPurchases, 1, -1 do
		local pending = addon.db.char.pendingPurchases[index]
		if pending.auctionID == auctionID then
			RecordConfirmedPurchase(pending, pending.price)
			return
		end
	end
end

local function HookModernCommodityPurchase(itemID, quantity)
	local scope = scanner:GetAuctionScope()
	if not scope or not itemID or not quantity or quantity < 1 then
		pendingCommodityPurchase = nil
		return
	end

	local remaining = quantity
	local components = {}
	-- A commodity purchase can consume several price tiers. Preserve those tiers as
	-- separate realm transactions while the later buyer invoice records one inventory cost.
	---@diagnostic disable-next-line: wrong-flavor-api
	for index = 1, C_AuctionHouse.GetNumCommoditySearchResults(itemID) do
		---@diagnostic disable-next-line: wrong-flavor-api
		local result = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, index)
		if result then
			local available = max(0, result.quantity - (result.numOwnerItems or 0))
			local count = min(remaining, available)
			if count > 0 then
				components[#components + 1] = {
					auctionHouseType = addon:GetAuctionHouseTypeForScope(scope),
					auctionID = result.auctionID,
					count = count,
					itemID = itemID,
					scope = scope,
					unitPrice = result.unitPrice,
				}
				remaining = remaining - count
				if remaining == 0 then
					break
				end
			end
		end
	end
	pendingCommodityPurchase = remaining == 0 and {
		components = components,
		count = quantity,
		itemID = itemID,
		scope = scope,
	} or nil
end

local function ConfirmModernCommodityPurchase()
	local purchase = pendingCommodityPurchase
	pendingCommodityPurchase = nil
	if not purchase then
		return
	end
	local totalPrice = 0
	for index = 1, #purchase.components do
		local component = purchase.components[index]
		local saleValue = component.count * component.unitPrice
		RecordConfirmedPurchase(component, saleValue)
		totalPrice = totalPrice + saleValue
	end
	-- Keep one aggregate purchase for inventory-cost collection when the buyer
	-- invoice arrives. Its realm transaction components were recorded above.
	addon.db.char.pendingPurchases[#addon.db.char.pendingPurchases + 1] = {
		action = "buy",
		count = purchase.count,
		itemID = purchase.itemID,
		price = totalPrice,
		realmSaleRecorded = true,
		scope = purchase.scope,
		timestamp = GetServerTime(),
	}
end

local function FailModernCommodityPurchase()
	pendingCommodityPurchase = nil
end

local function CloseAuctionHouseModern()
	wipe(modernAuctions)
	pendingCommodityPurchase = nil
end

local function ReadInvoice(index)
	-- Blizzard reports the seller for buyer invoices and the purchaser for seller
	-- invoices. Legacy mail does not expose the auction's numeric ID.
	local invoiceType, itemName, playerName, bid, buyout, _, consignment, _, _, _, count = GetInboxInvoiceInfo(index)
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
		playerName = addon:NormalizeCharacterName(playerName),
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
		-- Identical buyer invoices are separate auctions. Once an invoice has claimed
		-- a pending entry, later invoices in the same mailbox snapshot must use the
		-- next matching entry rather than repeatedly resolving the newest purchase.
		if not pending.inventoryCostRecorded
			and pending.itemID == invoice.itemID and pending.count == invoice.count
			and (not pending.price or pending.price == saleValue)
			and ApplyInvoiceSeller(pending, invoice.playerName) then
			RecordConfirmedPurchase(pending, saleValue, invoice.timestamp)
			if not pending.seller or not addon:IsAlt(pending.seller) then
				inventoryAverageBuy:RecordPurchaseOutsideInventory(
					pending.itemID, pending.count, saleValue)
			end
			pending.inventoryCostRecorded = true
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
				and (not pending.price or pending.price == saleValue)
				and ApplyInvoiceSeller(pending, invoice.playerName) then
				RecordConfirmedPurchase(pending, saleValue, invoice.timestamp)
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
				if RecordSale(scope, listing, saleValue, invoice.timestamp) then
					inventoryAverageBuy:RecordRemoval(listing.itemID, listing.count)
					vendorFlipTracking:RecordSale(listing.itemID, listing.count,
						saleValue - (invoice.consignment or 0))
					tableRemove(ledger, index)
					return
				end
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
	local seller = addon:NormalizeCharacterName(ownerFullName or owner)
	local matchSeller = seller

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
		end
	end
	local purchase = {
		auctionHouseType = addon:GetAuctionHouseTypeForScope(scope),
		itemID = itemID,
		count = count,
		action = action,
		buyout = buyout,
		dealType = dealType,
		minBid = minBid,
		matchSeller = matchSeller,
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
	-- YAAHA's deal buttons record richer metadata immediately before calling
	-- PlaceAuctionBid. Claim that exact synchronous hook invocation instead of
	-- guessing from item, price, and time; separate identical purchases must remain
	-- separate ledger entries.
	local claim = classicPurchaseHookClaim
	classicPurchaseHookClaim = nil
	if claim and claim.listType == listType and claim.index == index and claim.price == price then
		return
	end
	RecordPendingPurchase(listType, index, price)
end

function module:OnInitialize()
	inventoryAverageBuy = addon:GetModule("InventoryAverageBuy")
	scanner = addon:GetModule("Scanner")
	vendorFlipTracking = addon:GetModule("VendorFlipTracking")
	-- GetServerTime continues across logout. Clear the complete rolling sale window
	-- as soon as AceDB is available rather than waiting for a mailbox or sync event.
	PruneAllSales()
	-- The sales-per-day denominator begins when YAAHA starts observing a market.
	-- Existing observations can establish an earlier start after an update.
	InitializeTrackingStarted()
end

function module:OnEnable()
	local _, _, fullName = addon:GetPlayerIdentity()
	playerFullName = fullName
	self:RegisterEvent("MAIL_INBOX_UPDATE", CacheAuctionInvoices)
	self:RegisterEvent("MAIL_CLOSED", CloseMailbox)
	self:RegisterEvent("MAIL_SHOW", OpenMailbox)
	self:RegisterMessage("YAAHA_TRADE_SALE")
	if usesModernAuctionHouse then
		self:RegisterEvent("AUCTION_HOUSE_SHOW", QueryOwnedAuctionsModern)
		self:RegisterEvent("AUCTION_HOUSE_CLOSED", CloseAuctionHouseModern)
		self:RegisterEvent("AUCTION_HOUSE_PURCHASE_COMPLETED", ConfirmModernItemPurchase)
		self:RegisterEvent("COMMODITY_PURCHASE_FAILED", FailModernCommodityPurchase)
		self:RegisterEvent("COMMODITY_PURCHASE_SUCCEEDED", ConfirmModernCommodityPurchase)
		self:RegisterEvent("ITEM_SEARCH_RESULTS_ADDED", CacheModernItemAuctions)
		self:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED", CacheModernItemAuctions)
		self:RegisterEvent("OWNED_AUCTIONS_UPDATED", ReadOwnedAuctionsModern)
		---@diagnostic disable-next-line: wrong-flavor-api
		hooksecurefunc(C_AuctionHouse, "PlaceBid", HookModernItemPurchase)
		---@diagnostic disable-next-line: wrong-flavor-api
		hooksecurefunc(C_AuctionHouse, "ConfirmCommoditiesPurchase", HookModernCommodityPurchase)
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
	local purchase = RecordPendingPurchase(listType, index, price, action, dealType)
	classicPurchaseHookClaim = purchase and {
		listType = listType,
		index = index,
		price = price,
		purchase = purchase,
	} or nil
	return purchase
end

function module:ReleasePendingPurchaseHook(purchase)
	-- A module-local PlaceAuctionBid reference can bypass a later global wrapper.
	-- Do not let an unconsumed claim suppress the next unrelated auction action.
	if classicPurchaseHookClaim and classicPurchaseHookClaim.purchase == purchase then
		classicPurchaseHookClaim = nil
	end
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

function module:GetRealmSalesTrackingStarted(auctionHouseType)
	return GetTrackingStarted(auctionHouseType, GetServerTime())
end

function module:MergeRealmSalesTrackingStarted(auctionHouseType, timestamp)
	return MergeTrackingStarted(auctionHouseType, timestamp, GetServerTime())
end

function module:GetRealmRollingSaleMetrics(itemID, auctionHouseType)
	local realmSales = addon:GetRealmSales(auctionHouseType)
	local data = realmSales[itemID]
	if not data then
		return
	end

	local now = GetServerTime()
	if not PruneRealmSales(data, now) then
		realmSales[itemID] = nil
		return
	end
	local attempted, sold, totalSaleValue = 0, 0, 0
	local buyers, sellers = {}, {}
	for index = 1, #data.observations do
		local observation = data.observations[index]
		if observation.source == "buyer" then
			buyers[#buyers + 1] = observation
		elseif observation.source == "seller" then
			sellers[#sellers + 1] = observation
			attempted = attempted + observation.attempted
			sold = sold + observation.sold
			totalSaleValue = totalSaleValue + observation.totalSaleValue
		else
			attempted = attempted + observation.attempted
		end
	end

	-- A guild may observe the same transaction from its buyer and seller. Modern
	-- auctions expose a shared auction ID; Classic can still be paired when seller,
	-- item, quantity, value, and nearby timestamps agree. Uncertain observations
	-- remain independent rather than being silently discarded.
	local matchedSellers = {}
	for buyerIndex = 1, #buyers do
		local buyer = buyers[buyerIndex]
		local bestIndex, bestDistance
		for sellerIndex = 1, #sellers do
			local seller = sellers[sellerIndex]
			local exactAuction = buyer.auctionID and seller.auctionID
				and buyer.auctionID == seller.auctionID
				and buyer.sold == seller.sold
				and buyer.totalSaleValue == seller.totalSaleValue
			local matchingListing = buyer.matchKey and seller.matchKey
				and buyer.matchKey == seller.matchKey
				and abs(buyer.timestamp - seller.timestamp) <= SALE_MATCH_SECONDS
			if not matchedSellers[sellerIndex] and (exactAuction or matchingListing) then
				local distance = abs(buyer.timestamp - seller.timestamp)
				if not bestIndex or distance < bestDistance then
					bestIndex = sellerIndex
					bestDistance = distance
				end
			end
		end
		if bestIndex then
			matchedSellers[bestIndex] = true
		else
			attempted = attempted + buyer.attempted
			sold = sold + buyer.sold
			totalSaleValue = totalSaleValue + buyer.totalSaleValue
		end
	end
	if attempted == 0 and sold == 0 then
		realmSales[itemID] = nil
		return
	end

	local trackingStarted = GetTrackingStarted(auctionHouseType, now)
	-- A new installation reports against the time it has actually observed. The
	-- denominator grows continuously from one day and stops at the retained 60 days.
	local observedDays = min(SALE_HISTORY_DAYS,
		max(1, (now - trackingStarted) / SECONDS_PER_DAY))
	return attempted > 0 and sold / attempted or nil, sold / observedDays,
		sold > 0 and totalSaleValue / sold or nil
end

function module:GetPersonalRollingSaleMetrics(itemID)
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