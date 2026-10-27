-- Finds and purchases arbitrary Modern commodity quantities at or below the
-- configured fraction of their expected prospecting or milling value.

local AUCTION_HOUSE_BUY_BUTTON = AUCTION_HOUSE_BUY_BUTTON
local AUCTION_MINIMUM_PRICE
local BUYOUT = BUYOUT
local C_AuctionHouse = C_AuctionHouse
local C_Item = C_Item
local CANCEL = CANCEL
local CreateFrame = CreateFrame
local ERR_NOT_ENOUGH_MONEY = ERR_NOT_ENOUGH_MONEY
local floor = math.floor
local format = string.format
local GameTooltip_Hide = GameTooltip_Hide
local GetMoney = GetMoney
local GetTime = GetTime
local ipairs = ipairs
local LibStub = LibStub
local max = math.max
local min = math.min
local pairs = pairs
local RENOWN_LEVEL_UP_SKIP_BUTTON = RENOWN_LEVEL_UP_SKIP_BUTTON
local sort = table.sort
local StaticPopupDialogs = StaticPopupDialogs
local StaticPopup_Hide = StaticPopup_Hide
local StaticPopup_Show = StaticPopup_Show
local tonumber = tonumber
local tostring = tostring

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local module = addon:NewModule("MaterialDeals", "AceEvent-3.0")
local auctionHouseUI = addon:GetModule("AuctionHouseUI")
local dataProcessing = addon:GetModule("DataProcessing")
local saleCollector = addon:GetModule("SaleCollector")
local scanner = addon:GetModule("Scanner")
local tooltip = addon:GetModule("Tooltip")
local L = LibStub("AceLocale-3.0"):GetLocale("YAAHA")

AUCTION_MINIMUM_PRICE = addon.auctionHouseMinimumPrice
local GREEN_NUMBER = addon.positiveNumberColor
local QUERY_RETRY_LIMIT = 3
local QUERY_TIMEOUT = 10
local TRANSACTION_TIMEOUT = 10
local PRICE_SORT = {
	{
		sortOrder = Enum.AuctionHouseSortOrder.Price,
		reverseSort = false,
	},
}

local configurations = {
	{
		buttonOffset = -138,
		cacheEmpty = "Prospecting cache ready: no candidate listings.",
		cacheReady = "Prospecting cache ready: %d listings across %d items.",
		commodityText = "Prospecting commodity: %s\nProspecting value per item: %s\nMaximum affordable deal quantity: %d\nEnter purchase quantity:",
		complete = "Prospecting deal search complete.",
		dataModule = addon:GetModule("ProspectingData", true),
		dealText = "Prospecting deal: %s x%d\nBuyout: %s\nProspecting value: %s\nExpected profit: %s",
		dealType = "prospect",
		label = "Prospecting Deals",
		listKey = "prospectList",
		noCache = "No cached prospecting deals are available. Scan this auction house first.",
		noDeals = "No profitable prospecting deals remain.",
		quoteText = "Prospecting commodity: %s x%d\nProspecting value: %s\nPurchase price: %s\nExpected profit: %s",
		searching = "Searching cached prospecting deals...",
		stopLabel = "Stop Prospecting Deals",
		stopped = "Prospecting deal search stopped.",
		stoppedForScan = "Prospecting deal search stopped for auction processing.",
		thresholdKey = "prospectingDealThreshold",
		timedOut = "Prospecting search timed out; continuing.",
	},
	{
		buttonOffset = -200,
		cacheEmpty = "Milling cache ready: no candidate listings.",
		cacheReady = "Milling cache ready: %d listings across %d items.",
		commodityText = "Milling commodity: %s\nMilling value per item: %s\nMaximum affordable deal quantity: %d\nEnter purchase quantity:",
		complete = "Milling deal search complete.",
		dataModule = addon:GetModule("MillingData", true),
		dealText = "Milling deal: %s x%d\nBuyout: %s\nMilling value: %s\nExpected profit: %s",
		dealType = "milling",
		label = "Milling Deals",
		listKey = "millingList",
		noCache = "No cached milling deals are available. Scan this auction house first.",
		noDeals = "No profitable milling deals remain.",
		quoteText = "Milling commodity: %s x%d\nMilling value: %s\nPurchase price: %s\nExpected profit: %s",
		searching = "Searching cached milling deals...",
		stopLabel = "Stop Milling Deals",
		stopped = "Milling deal search stopped.",
		stoppedForScan = "Milling deal search stopped for auction processing.",
		thresholdKey = "millingDealThreshold",
		timedOut = "Milling search timed out; continuing.",
	},
}
local configurationsByButton = {}

local ITEM_POPUP_NAME = "YAAHA_MATERIAL_DEAL_MODERN_ITEM"
local COMMODITY_POPUP_NAME = "YAAHA_MATERIAL_DEAL_MODERN_COMMODITY"
local COMMODITY_QUOTE_POPUP_NAME = "YAAHA_MATERIAL_DEAL_MODERN_COMMODITY_QUOTE"
local currentCandidate, currentConfiguration, currentRequest, pendingCommodityQuote
local pendingBidsByAuction, pendingPurchase
local queue, queueIndex
local running, resumeResults, searchPending, transactionPending
local waitingForInitialResults, waitingForItemInfo, waitingForMoreResults, waitingForQuote
local queryAttempts, itemInfoAttempts = 0, 0
local nextResultIndex = 1
local searchDeadline, transactionDeadline
local statusElapsed = 0
local wasScannerBusy
local updateFrame = CreateFrame("Frame")
local AdvanceRequest, ContinueAfterCandidate, ContinueResultsLoading, ScheduleSearch

local function SortByProfit(left, right)
	return left.profit > right.profit
end

local function IsDeal(configuration, cost, value)
	return addon:IsBreakdownDeal(cost, value,
		addon.db.profile[configuration.thresholdKey])
end

local function SetStatus(configuration, text)
	if configuration and configuration.statusText then
		configuration.statusText:SetText(text)
	end
end

local function FormatProfit(profit)
	return addon:FormatMoney(profit, true, GREEN_NUMBER)
end

local function ItemKeysEqual(left, right)
	return left and right
		and left.itemID == right.itemID
		and left.itemLevel == right.itemLevel
		and left.itemSuffix == right.itemSuffix
		and left.battlePetSpeciesID == right.battlePetSpeciesID
end

local function GetExpectedUnitValue(configuration, itemID, scope)
	local breakdown = configuration.dataModule:GetValue(itemID, scope)
	return breakdown and breakdown.expectedUnitValue
end

local function GetCacheCounts(configuration)
	local scope = scanner:GetAuctionScope()
	local dealList = scope and addon.db[scope][configuration.listKey]
	local numItems, numListings = 0, 0
	for _, itemData in pairs(dealList or {}) do
		local itemListings = 0
		if itemData.expectedUnitValue then
			for _, auction in pairs(itemData.auctions) do
				if IsDeal(configuration, auction.buyout,
					itemData.expectedUnitValue * auction.count) then
					itemListings = itemListings + (auction.numAuctions or 1)
				end
			end
		end
		if itemListings > 0 then
			numItems = numItems + 1
			numListings = numListings + itemListings
		end
	end
	return numItems, numListings
end

local function ShowCacheReady(configuration)
	if not configuration.dataModule then
		return
	end
	local numItems, numListings = GetCacheCounts(configuration)
	if numListings > 0 then
		SetStatus(configuration, format(L[configuration.cacheReady], numListings, numItems))
	else
		SetStatus(configuration, L[configuration.cacheEmpty])
	end
end

local function ShowAllCachesReady()
	for index = 1, #configurations do
		ShowCacheReady(configurations[index])
	end
end

local function ResetSearchState()
	searchPending = false
	waitingForInitialResults = false
	waitingForMoreResults = false
	searchDeadline = nil
	queryAttempts = 0
end

local function CancelCommodityQuote()
	if waitingForQuote or pendingCommodityQuote then
		C_AuctionHouse.CancelCommoditiesPurchase()
	end
	waitingForQuote = false
	pendingCommodityQuote = nil
	StaticPopup_Hide(COMMODITY_QUOTE_POPUP_NAME)
end

local function FinishSearch(message)
	local configuration = currentConfiguration
	CancelCommodityQuote()
	running = false
	resumeResults = false
	transactionPending = false
	waitingForItemInfo = false
	itemInfoAttempts = 0
	transactionDeadline = nil
	currentCandidate = nil
	currentRequest = nil
	pendingBidsByAuction = nil
	pendingPurchase = nil
	queue = nil
	currentConfiguration = nil
	ResetSearchState()
	if configuration and configuration.actionButton then
		configuration.actionButton:SetText(L[configuration.label])
		configuration.actionButton:Enable()
	end
	SetStatus(configuration, message)
end

ScheduleSearch = function()
	searchPending = true
	waitingForInitialResults = false
	waitingForMoreResults = false
	searchDeadline = GetTime() + QUERY_TIMEOUT
end

local function WaitForItemInfo()
	waitingForItemInfo = true
	itemInfoAttempts = itemInfoAttempts + 1
	searchDeadline = GetTime() + QUERY_TIMEOUT
	C_Item.RequestLoadItemDataByID(currentRequest.itemID)
end

local function BeginRequest(request)
	currentRequest = request
	currentCandidate = nil
	request.itemKey = C_AuctionHouse.MakeItemKey(request.itemID)
	request.itemKeyInfo = C_AuctionHouse.GetItemKeyInfo(request.itemKey)
	request.name = C_Item.GetItemNameByID(request.itemID)
	nextResultIndex = 1
	queryAttempts = 0
	itemInfoAttempts = 0
	waitingForItemInfo = false
	if not request.name or not request.itemKeyInfo then
		WaitForItemInfo()
		return
	end
	-- Ores and herbs are commodities on clients which load this module. Retaining
	-- the item-result branch makes the state machine fail safely if Blizzard ever
	-- reclassifies a prospectable or millable source without a parallel rewrite.
	request.isCommodity = request.itemKeyInfo.isCommodity
	ScheduleSearch()
end

AdvanceRequest = function()
	currentCandidate = nil
	currentRequest = nil
	queueIndex = queueIndex + 1
	if queue and queueIndex <= #queue then
		BeginRequest(queue[queueIndex])
	else
		FinishSearch(L[currentConfiguration.complete])
	end
end

ContinueAfterCandidate = function(requery)
	local candidate = currentCandidate
	currentCandidate = nil
	if requery then
		nextResultIndex = 1
		queryAttempts = 0
		ScheduleSearch()
	elseif candidate and candidate.kind == "commodity" then
		AdvanceRequest()
	else
		resumeResults = true
	end
end

local function BuildQueue(configuration, dealList, scope)
	-- The scan cache chooses and orders item queries; live search results remain
	-- authoritative. Collapse every cached price tier into one request per item.
	local requests = {}
	for itemID, itemData in pairs(dealList or {}) do
		local expectedUnitValue = GetExpectedUnitValue(configuration, itemID, scope)
		local bestProfit
		for _, auction in pairs(itemData.auctions) do
			local expectedValue = expectedUnitValue and expectedUnitValue * auction.count
			if IsDeal(configuration, auction.buyout, expectedValue) then
				local profit = expectedValue - auction.buyout
				if not bestProfit or profit > bestProfit then
					bestProfit = profit
				end
			end
		end
		if bestProfit then
			requests[#requests + 1] = {
				itemID = itemID,
				profit = bestProfit,
			}
		end
	end
	sort(requests, SortByProfit)
	return requests
end

local function CachePendingBids(scope)
	pendingBidsByAuction = {}
	if not scope then
		return
	end
	for _, purchase in ipairs(saleCollector:GetPendingBids(scope, true)) do
		if purchase.auctionID then
			local bids = pendingBidsByAuction[purchase.auctionID]
			if not bids then
				bids = {}
				pendingBidsByAuction[purchase.auctionID] = bids
			end
			bids[#bids + 1] = purchase
		end
	end
end

local function GetCommodityPurchase(itemID, expectedUnitValue, requestedQuantity)
	-- Walk the price tiers exactly as Blizzard will fill a commodity purchase.
	-- This provides both the maximum affordable deal quantity and an exact total
	-- for a player-entered quantity without pretending the tiers are stacks.
	local remainingMoney = GetMoney()
	local remainingQuantity = requestedQuantity
	local quantity, totalCost = 0, 0
	for index = 1, C_AuctionHouse.GetNumCommoditySearchResults(itemID) do
		local result = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, index)
		if result and result.unitPrice and result.unitPrice >= AUCTION_MINIMUM_PRICE then
			-- A result is a per-unit price tier. Its quantity is divisible availability,
			-- not a stack which must be purchased in full.
			local available = max(0, result.quantity - (result.numOwnerItems or 0))
			if available > 0 then
				-- Commodity tiers are price-sorted. Once a tier exceeds the selected
				-- breakdown threshold, every later tier can be ignored safely.
				if not IsDeal(currentConfiguration, result.unitPrice, expectedUnitValue) then
					break
				end
				local count = min(available, floor(remainingMoney / result.unitPrice))
				if remainingQuantity then
					count = min(count, remainingQuantity)
				end
				if count > 0 then
					quantity = quantity + count
					totalCost = totalCost + count * result.unitPrice
					remainingMoney = remainingMoney - count * result.unitPrice
					if remainingQuantity then
						remainingQuantity = remainingQuantity - count
						if remainingQuantity == 0 then
							return quantity, totalCost
						end
					end
				end
			end
		end
	end
	if remainingQuantity and remainingQuantity > 0 then
		return
	end
	return quantity, totalCost
end

local function FindItemResult(auctionID)
	if not currentRequest or not currentRequest.itemKey then
		return
	end
	for index = 1, C_AuctionHouse.GetNumItemSearchResults(currentRequest.itemKey) do
		local result = C_AuctionHouse.GetItemSearchResultInfo(currentRequest.itemKey, index)
		if result and result.auctionID == auctionID then
			return result
		end
	end
end

local function IsOwnItemResult(result)
	local pendingBids = pendingBidsByAuction and pendingBidsByAuction[result.auctionID]
	return saleCollector:IsModernAccountHighBidder(
		result, currentRequest.itemID, pendingBids)
end

local function RevalidateItemCandidate(candidate)
	local result = FindItemResult(candidate.auctionID)
	if not result or IsOwnItemResult(result) then
		return
	end
	local count = result.quantity or 1
	local buyout = result.buyoutAmount
	local scope = scanner:GetAuctionScope()
	local expectedUnitValue = scope and GetExpectedUnitValue(
		currentConfiguration, candidate.itemID, scope)
	local expectedValue = expectedUnitValue and expectedUnitValue * count
	if not buyout or buyout < AUCTION_MINIMUM_PRICE
		or not IsDeal(currentConfiguration, buyout, expectedValue) then
		return
	end
	return result, buyout, expectedValue
end

local function OnPopupHyperlinkEnter(popup, link)
	if popup.yaahaItemID then
		tooltip:ShowTooltip(popup, link, popup.yaahaItemID, scanner:GetAuctionScope())
	end
end

local function OnPopupHide(popup)
	popup.yaahaItemID = nil
	GameTooltip_Hide()
end

local function AttachPopupTooltip(popup, itemID)
	popup.yaahaItemID = itemID
	if popup.yaahaTooltipHooked then
		return
	end
	popup.yaahaTooltipHooked = true
	popup:SetHyperlinksEnabled(true)
	popup:HookScript("OnHyperlinkEnter", OnPopupHyperlinkEnter)
	popup:HookScript("OnHyperlinkLeave", GameTooltip_Hide)
	popup:HookScript("OnHide", OnPopupHide)
end

local function ShowItemCandidate(result)
	if IsOwnItemResult(result) then
		return false
	end
	local count = result.quantity or 1
	local buyout = result.buyoutAmount
	local scope = scanner:GetAuctionScope()
	local expectedUnitValue = scope and GetExpectedUnitValue(
		currentConfiguration, currentRequest.itemID, scope)
	local expectedValue = expectedUnitValue and expectedUnitValue * count
	if not buyout or buyout < AUCTION_MINIMUM_PRICE
		or not IsDeal(currentConfiguration, buyout, expectedValue) then
		return false
	end

	local candidate = {
		auctionID = result.auctionID,
		buyout = buyout,
		count = count,
		expectedValue = expectedValue,
		itemID = currentRequest.itemID,
		kind = "item",
		link = result.itemLink,
		name = currentRequest.name,
	}
	currentCandidate = candidate
	local text = format(L[currentConfiguration.dealText],
		candidate.link or candidate.name, count, addon:FormatMoney(buyout),
		addon:FormatMoney(expectedValue), FormatProfit(expectedValue - buyout))
	local popup = StaticPopup_Show(ITEM_POPUP_NAME, text, nil, candidate)
	if not popup then
		currentCandidate = nil
		return false
	end
	AttachPopupTooltip(popup, candidate.itemID)
	return true
end

local function ShowCommodityCandidate()
	local scope = scanner:GetAuctionScope()
	local expectedUnitValue = scope and GetExpectedUnitValue(
		currentConfiguration, currentRequest.itemID, scope)
	if not expectedUnitValue then
		return false
	end
	local maxQuantity = GetCommodityPurchase(currentRequest.itemID, expectedUnitValue)
	if not maxQuantity or maxQuantity < 1 then
		return false
	end
	local candidate = {
		expectedUnitValue = expectedUnitValue,
		itemID = currentRequest.itemID,
		kind = "commodity",
		maxQuantity = maxQuantity,
		name = currentRequest.name,
	}
	currentCandidate = candidate
	local text = format(L[currentConfiguration.commodityText], candidate.name,
		addon:FormatMoney(expectedUnitValue), candidate.maxQuantity)
	local popup = StaticPopup_Show(COMMODITY_POPUP_NAME, text, nil, candidate)
	if not popup then
		currentCandidate = nil
		return false
	end
	return true
end

function module:ProcessCurrentResults()
	if not running or not currentRequest then
		return
	end
	if currentRequest.isCommodity then
		if ShowCommodityCandidate() then
			return
		end
		AdvanceRequest()
		return
	end
	for index = nextResultIndex, C_AuctionHouse.GetNumItemSearchResults(currentRequest.itemKey) do
		local result = C_AuctionHouse.GetItemSearchResultInfo(currentRequest.itemKey, index)
		nextResultIndex = index + 1
		if result and ShowItemCandidate(result) then
			return
		end
	end
	AdvanceRequest()
end

ContinueResultsLoading = function()
	if not running or not currentRequest then
		return
	end
	local hasFullResults
	if currentRequest.isCommodity then
		hasFullResults = C_AuctionHouse.HasFullCommoditySearchResults(currentRequest.itemID)
	else
		hasFullResults = C_AuctionHouse.HasFullItemSearchResults(currentRequest.itemKey)
	end
	if hasFullResults then
		waitingForInitialResults = false
		waitingForMoreResults = false
		queryAttempts = 0
		nextResultIndex = 1
		module:ProcessCurrentResults()
		return
	end
	-- UPDATED and ADDED events can arrive before the complete result set. Do not
	-- evaluate or advance until HasFull* confirms that every price tier/listing is
	-- available, requesting further chunks only when the throttle permits it.
	if not C_AuctionHouse.IsThrottledMessageSystemReady() then
		waitingForMoreResults = true
		searchDeadline = GetTime() + QUERY_TIMEOUT
		return
	end
	waitingForMoreResults = true
	searchDeadline = GetTime() + QUERY_TIMEOUT
	if currentRequest.isCommodity then
		hasFullResults = C_AuctionHouse.RequestMoreCommoditySearchResults(currentRequest.itemID)
	else
		hasFullResults = C_AuctionHouse.RequestMoreItemSearchResults(currentRequest.itemKey)
	end
	if hasFullResults then
		waitingForMoreResults = false
		queryAttempts = 0
		nextResultIndex = 1
		module:ProcessCurrentResults()
	end
end

local function RetryOrAdvance()
	waitingForInitialResults = false
	waitingForMoreResults = false
	if queryAttempts < QUERY_RETRY_LIMIT then
		ScheduleSearch()
	else
		SetStatus(currentConfiguration, L[currentConfiguration.timedOut])
		AdvanceRequest()
	end
end

local function ResolveItemTransaction(succeeded, confirmedFailure)
	transactionPending = false
	transactionDeadline = nil
	if not running or not currentRequest then
		return
	end
	if succeeded then
		pendingPurchase = nil
	elseif confirmedFailure and pendingPurchase then
		saleCollector:DiscardPendingPurchase(pendingPurchase)
		pendingPurchase = nil
	end
	SetStatus(currentConfiguration, succeeded and L["Auction action accepted; refreshing results."]
		or L["Auction action failed; refreshing results."])
	currentCandidate = nil
	nextResultIndex = 1
	queryAttempts = 0
	ScheduleSearch()
end

function module:BuyItemCandidate(candidate)
	if not running or transactionPending or candidate ~= currentCandidate then
		return
	end
	-- A noncommodity fallback listing may change while its popup is open. Re-read
	-- the stable auction ID and threshold before the protected buyout call.
	local result, buyout = RevalidateItemCandidate(candidate)
	if not result then
		SetStatus(currentConfiguration, L["Auction listing changed; searching again."])
		ContinueAfterCandidate(true)
		return
	end
	if GetMoney() < buyout then
		SetStatus(currentConfiguration, ERR_NOT_ENOUGH_MONEY)
		ContinueAfterCandidate(false)
		return
	end
	transactionPending = true
	transactionDeadline = GetTime() + TRANSACTION_TIMEOUT
	SetStatus(currentConfiguration, L["Waiting for the auction house..."])
	pendingPurchase = saleCollector:RecordModernPendingPurchase(
		result.auctionID, buyout, "buy", currentConfiguration.dealType, result)
	C_AuctionHouse.PlaceBid(result.auctionID, buyout)
	saleCollector:ReleaseModernPendingPurchaseHook(pendingPurchase)
end

function module:StartCommodityQuote(candidate, quantity)
	if not running or transactionPending or waitingForQuote or candidate ~= currentCandidate then
		return
	end
	-- Commodity purchase is a two-click protected flow. Recompute the requested
	-- quantity first, then ask Blizzard for the authoritative time-limited quote.
	local availableQuantity, totalCost = GetCommodityPurchase(
		candidate.itemID, candidate.expectedUnitValue, quantity)
	if not availableQuantity or availableQuantity ~= quantity or not totalCost then
		SetStatus(currentConfiguration, L["Commodity price changed; searching again."])
		ContinueAfterCandidate(true)
		return
	end
	pendingCommodityQuote = {
		configuration = currentConfiguration,
		expectedUnitValue = candidate.expectedUnitValue,
		itemID = candidate.itemID,
		name = candidate.name,
		quantity = quantity,
	}
	waitingForQuote = true
	transactionDeadline = GetTime() + TRANSACTION_TIMEOUT
	SetStatus(currentConfiguration, L["Waiting for the auction house..."])
	C_AuctionHouse.StartCommoditiesPurchase(candidate.itemID, quantity)
end

function module:ConfirmCommodityPurchase(quote)
	-- The quoted total, rather than the earlier search tiers, is the final deal
	-- test. This prevents a price movement during the dialog from buying above the
	-- configured prospecting or milling threshold.
	local expectedValue = quote.expectedUnitValue * quote.quantity
	if not running or transactionPending or quote ~= pendingCommodityQuote
		or not quote.totalPrice or not IsDeal(quote.configuration, quote.totalPrice, expectedValue) then
		CancelCommodityQuote()
		SetStatus(currentConfiguration, L["Commodity price changed; searching again."])
		ContinueAfterCandidate(true)
		return
	end
	if C_AuctionHouse.GetQuoteDurationRemaining() <= 0 then
		CancelCommodityQuote()
		SetStatus(currentConfiguration, L["Commodity quote expired; searching again."])
		ContinueAfterCandidate(true)
		return
	end
	if GetMoney() < quote.totalPrice then
		CancelCommodityQuote()
		SetStatus(currentConfiguration, ERR_NOT_ENOUGH_MONEY)
		ContinueAfterCandidate(false)
		return
	end
	waitingForQuote = false
	transactionPending = true
	transactionDeadline = GetTime() + TRANSACTION_TIMEOUT
	SetStatus(currentConfiguration, L["Waiting for the auction house..."])
	C_AuctionHouse.ConfirmCommoditiesPurchase(quote.itemID, quote.quantity)
end

function module:SkipCandidate(candidate)
	if running and candidate == currentCandidate then
		ContinueAfterCandidate(false)
	end
end

local function ShowCommodityQuote(unitPrice, totalPrice)
	local quote = pendingCommodityQuote
	if not quote or not waitingForQuote then
		return
	end
	waitingForQuote = false
	transactionDeadline = nil
	local expectedValue = quote.expectedUnitValue * quote.quantity
	if not unitPrice or unitPrice < AUCTION_MINIMUM_PRICE or not totalPrice
		or not IsDeal(quote.configuration, totalPrice, expectedValue) then
		CancelCommodityQuote()
		SetStatus(currentConfiguration, L["Commodity price changed; searching again."])
		ContinueAfterCandidate(true)
		return
	end
	quote.totalPrice = totalPrice
	local text = format(L[quote.configuration.quoteText], quote.name, quote.quantity,
		addon:FormatMoney(expectedValue), addon:FormatMoney(totalPrice),
		FormatProfit(expectedValue - totalPrice))
	if not StaticPopup_Show(COMMODITY_QUOTE_POPUP_NAME, text, nil, quote) then
		CancelCommodityQuote()
		ContinueAfterCandidate(true)
	end
end

local function StopSearch(message)
	StaticPopup_Hide(ITEM_POPUP_NAME)
	StaticPopup_Hide(COMMODITY_POPUP_NAME)
	StaticPopup_Hide(COMMODITY_QUOTE_POPUP_NAME)
	local configuration = currentConfiguration
	FinishSearch(message or configuration and L[configuration.stopped])
end

local function StartSearch(configuration)
	if running then
		local sameConfiguration = currentConfiguration == configuration
		StopSearch()
		if sameConfiguration then
			return
		end
	end
	if scanner:IsScanning() then
		SetStatus(configuration, dataProcessing:IsProcessing() and L["Processing scan data..."]
			or L["Waiting for auction scan results..."])
		return
	end
	local scope = scanner:GetAuctionScope()
	local dealList = scope and addon.db[scope][configuration.listKey]
	CachePendingBids(scope)
	queue = BuildQueue(configuration, dealList, scope)
	if #queue == 0 then
		local scanStats = scope and addon.db[scope].auctionStats
		if not scanStats or not scanStats.lastScan then
			SetStatus(configuration, L[configuration.noCache])
		else
			SetStatus(configuration, L[configuration.noDeals])
		end
		return
	end

	module:SendMessage("YAAHA_DEAL_SEARCH_STARTED", configuration.dealType)
	currentConfiguration = configuration
	running = true
	queueIndex = 0
	currentCandidate = nil
	currentRequest = nil
	pendingCommodityQuote = nil
	resumeResults = false
	transactionPending = false
	waitingForItemInfo = false
	waitingForQuote = false
	itemInfoAttempts = 0
	nextResultIndex = 1
	transactionDeadline = nil
	ResetSearchState()
	configuration.actionButton:SetText(L[configuration.stopLabel])
	SetStatus(configuration, L[configuration.searching])
	AdvanceRequest()
end

local function ActionButtonOnClick(button)
	StartSearch(configurationsByButton[button])
end

local function CreateInterface()
	local page = auctionHouseUI:GetPage("deals")
	if not page then
		return
	end
	for index = 1, #configurations do
		local configuration = configurations[index]
		if configuration.dataModule and not configuration.actionButton then
			local actionButton = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
			actionButton:SetSize(180, 24)
			actionButton:SetPoint("TOPLEFT", page, "TOPLEFT", 0, configuration.buttonOffset)
			actionButton:SetText(L[configuration.label])
			configurationsByButton[actionButton] = configuration
			actionButton:SetScript("OnClick", ActionButtonOnClick)
			configuration.actionButton = actionButton

			local statusText = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			statusText:SetPoint("TOPLEFT", actionButton, "BOTTOMLEFT", 0, -10)
			statusText:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, configuration.buttonOffset - 34)
			statusText:SetJustifyH("LEFT")
			statusText:SetText("")
			configuration.statusText = statusText
		end
	end
end

local function GetCommodityPopupQuantity(dialog, candidate)
	local quantity = tonumber(dialog:GetEditBox():GetText())
	if not quantity or quantity ~= floor(quantity) or quantity < 1
		or quantity > candidate.maxQuantity then
		return
	end
	return quantity
end

local function UpdateCommodityPopup(dialog, candidate)
	local quantity = GetCommodityPopupQuantity(dialog, candidate)
	local totals = dialog.yaahaTotals
	if not quantity then
		totals:SetText(format(L["Total cost: %s\nExpected profit: %s"], "--", "--"))
		dialog:GetButton1():Disable()
		return
	end
	local availableQuantity, totalCost = GetCommodityPurchase(
		candidate.itemID, candidate.expectedUnitValue, quantity)
	if not availableQuantity or availableQuantity ~= quantity or not totalCost then
		totals:SetText(format(L["Total cost: %s\nExpected profit: %s"], "--", "--"))
		dialog:GetButton1():Disable()
		return
	end
	local profit = candidate.expectedUnitValue * quantity - totalCost
	totals:SetText(format(L["Total cost: %s\nExpected profit: %s"],
		addon:FormatMoney(totalCost), FormatProfit(profit)))
	dialog:GetButton1():Enable()
end

StaticPopupDialogs[ITEM_POPUP_NAME] = {
	text = "%s",
	button1 = BUYOUT,
	button2 = RENOWN_LEVEL_UP_SKIP_BUTTON,
	OnAccept = function(_, data)
		module:BuyItemCandidate(data)
	end,
	OnCancel = function(_, data)
		module:SkipCandidate(data)
	end,
	timeout = 0,
	whileDead = false,
	hideOnEscape = false,
}

StaticPopupDialogs[COMMODITY_POPUP_NAME] = {
	text = "%s",
	button1 = AUCTION_HOUSE_BUY_BUTTON,
	button2 = RENOWN_LEVEL_UP_SKIP_BUTTON,
	selectCallbackByIndex = true,
	hasEditBox = true,
	maxLetters = 10,
	OnShow = function(dialog, data)
		local editBox = dialog:GetEditBox()
		editBox:SetNumeric(true)
		if not dialog.yaahaTotals then
			dialog.yaahaTotals = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			dialog.yaahaTotals:SetPoint("LEFT", editBox, "RIGHT", 8, 0)
			dialog.yaahaTotals:SetWidth(175)
			dialog.yaahaTotals:SetJustifyH("LEFT")
		end
		dialog.yaahaOriginalWidth = dialog:GetWidth()
		dialog:SetWidth(520)
		dialog.yaahaTotals:Show()
		editBox:SetText(tostring(data.maxQuantity))
		editBox:HighlightText()
		editBox:SetFocus()
		UpdateCommodityPopup(dialog, data)
	end,
	OnButton1 = function(dialog, data)
		local quantity = GetCommodityPopupQuantity(dialog, data)
		if not quantity then
			return true
		end
		module:StartCommodityQuote(data, quantity)
	end,
	OnButton2 = function(_, data)
		module:SkipCandidate(data)
	end,
	EditBoxOnEnterPressed = function(editBox, data)
		local dialog = editBox:GetParent()
		local quantity = GetCommodityPopupQuantity(dialog, data)
		if quantity then
			module:StartCommodityQuote(data, quantity)
			dialog:Hide()
		end
	end,
	EditBoxOnTextChanged = function(editBox, data)
		UpdateCommodityPopup(editBox:GetParent(), data)
	end,
	OnHide = function(dialog)
		if dialog.yaahaTotals then
			dialog.yaahaTotals:Hide()
		end
		if dialog.yaahaOriginalWidth then
			dialog:SetWidth(dialog.yaahaOriginalWidth)
			dialog.yaahaOriginalWidth = nil
		end
	end,
	timeout = 0,
	whileDead = false,
	hideOnEscape = false,
}

StaticPopupDialogs[COMMODITY_QUOTE_POPUP_NAME] = {
	text = "%s",
	button1 = AUCTION_HOUSE_BUY_BUTTON,
	button2 = CANCEL,
	selectCallbackByIndex = true,
	OnButton1 = function(_, data)
		module:ConfirmCommodityPurchase(data)
	end,
	OnButton2 = function()
		CancelCommodityQuote()
		ContinueAfterCandidate(false)
	end,
	timeout = 0,
	whileDead = false,
	hideOnEscape = false,
}

local function OnUpdate(_, elapsed)
	statusElapsed = statusElapsed + elapsed
	if statusElapsed >= 0.2 then
		statusElapsed = 0
		local scannerBusy = scanner:IsScanning()
		if scannerBusy then
			if running then
				StopSearch(L[currentConfiguration.stoppedForScan])
			end
			for index = 1, #configurations do
				local configuration = configurations[index]
				if configuration.actionButton then
					configuration.actionButton:Disable()
					if dataProcessing:IsProcessing() then
						local processed, total = dataProcessing:GetProgress()
						SetStatus(configuration,
							format(L["Building deal caches: %d/%d steps."], processed, total))
					else
						SetStatus(configuration, L["Waiting for auction scan results..."])
					end
				end
			end
		elseif wasScannerBusy then
			for index = 1, #configurations do
				local configuration = configurations[index]
				if configuration.actionButton then
					configuration.actionButton:Enable()
				end
			end
			ShowAllCachesReady()
		end
		wasScannerBusy = scannerBusy
	end

	if not running then
		return
	end
	if transactionPending and GetTime() >= transactionDeadline then
		if pendingCommodityQuote then
			pendingCommodityQuote = nil
			transactionPending = false
			transactionDeadline = nil
			SetStatus(currentConfiguration, L["Commodity purchase failed; searching again."])
			ContinueAfterCandidate(true)
		else
			ResolveItemTransaction(false, false)
		end
	elseif waitingForQuote and GetTime() >= transactionDeadline then
		CancelCommodityQuote()
		SetStatus(currentConfiguration, L["Commodity quote expired; searching again."])
		ContinueAfterCandidate(true)
	elseif resumeResults then
		resumeResults = false
		module:ProcessCurrentResults()
	elseif waitingForItemInfo and GetTime() >= searchDeadline then
		if itemInfoAttempts < QUERY_RETRY_LIMIT then
			WaitForItemInfo()
		else
			waitingForItemInfo = false
			AdvanceRequest()
		end
	elseif searchPending and not transactionPending and not waitingForQuote then
		if C_AuctionHouse.IsThrottledMessageSystemReady() then
			searchPending = false
			waitingForInitialResults = true
			queryAttempts = queryAttempts + 1
			searchDeadline = GetTime() + QUERY_TIMEOUT
			C_AuctionHouse.SendSearchQuery(currentRequest.itemKey, PRICE_SORT, true)
		elseif GetTime() >= searchDeadline then
			searchDeadline = GetTime() + QUERY_TIMEOUT
		end
	elseif (waitingForInitialResults or waitingForMoreResults)
		and GetTime() >= searchDeadline then
		RetryOrAdvance()
	end
end

function module:OnEnable()
	self:RegisterEvent("AUCTION_HOUSE_SHOW")
	self:RegisterEvent("AUCTION_HOUSE_CLOSED")
	self:RegisterEvent("AUCTION_HOUSE_PURCHASE_COMPLETED")
	self:RegisterEvent("AUCTION_HOUSE_SHOW_ERROR")
	self:RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
	self:RegisterEvent("COMMODITY_PRICE_UNAVAILABLE")
	self:RegisterEvent("COMMODITY_PRICE_UPDATED")
	self:RegisterEvent("COMMODITY_PURCHASE_FAILED")
	self:RegisterEvent("COMMODITY_PURCHASE_SUCCEEDED")
	self:RegisterEvent("COMMODITY_SEARCH_RESULTS_ADDED")
	self:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
	self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	self:RegisterEvent("ITEM_KEY_ITEM_INFO_RECEIVED")
	self:RegisterEvent("ITEM_SEARCH_RESULTS_ADDED")
	self:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
	self:RegisterMessage("YAAHA_DEAL_SEARCH_STARTED")
	self:RegisterMessage("YAAHA_VENDOR_CACHE_READY")
	updateFrame:SetScript("OnUpdate", OnUpdate)
end

function module:YAAHA_DEAL_SEARCH_STARTED(_, dealType)
	if running and dealType ~= currentConfiguration.dealType then
		StopSearch()
	end
end

function module:YAAHA_VENDOR_CACHE_READY(_, scope)
	if scope ~= scanner:GetAuctionScope() then
		return
	end
	wasScannerBusy = false
	for index = 1, #configurations do
		local configuration = configurations[index]
		if configuration.actionButton then
			configuration.actionButton:Enable()
			ShowCacheReady(configuration)
		end
	end
end

function module:AUCTION_HOUSE_SHOW()
	CreateInterface()
	wasScannerBusy = scanner:IsScanning()
	for index = 1, #configurations do
		local configuration = configurations[index]
		if configuration.actionButton then
			configuration.actionButton:SetEnabled(not wasScannerBusy)
			if not wasScannerBusy then
				ShowCacheReady(configuration)
			end
		end
	end
end

function module:AUCTION_HOUSE_CLOSED()
	if running then
		StopSearch()
	end
end

function module:AUCTION_HOUSE_THROTTLED_SYSTEM_READY()
	if running and waitingForMoreResults then
		ContinueResultsLoading()
	end
end

function module:ITEM_SEARCH_RESULTS_UPDATED(_, itemKey)
	if running and waitingForInitialResults and ItemKeysEqual(itemKey, currentRequest.itemKey) then
		waitingForInitialResults = false
		ContinueResultsLoading()
	end
end

function module:ITEM_SEARCH_RESULTS_ADDED(_, itemKey)
	if running and waitingForMoreResults and ItemKeysEqual(itemKey, currentRequest.itemKey) then
		ContinueResultsLoading()
	end
end

function module:COMMODITY_SEARCH_RESULTS_UPDATED(_, itemID)
	if running and waitingForInitialResults and currentRequest.isCommodity
		and itemID == currentRequest.itemID then
		waitingForInitialResults = false
		ContinueResultsLoading()
	end
end

function module:COMMODITY_SEARCH_RESULTS_ADDED(_, itemID)
	if running and waitingForMoreResults and currentRequest.isCommodity
		and itemID == currentRequest.itemID then
		ContinueResultsLoading()
	end
end

function module:GET_ITEM_INFO_RECEIVED(_, itemID)
	if running and waitingForItemInfo and itemID == currentRequest.itemID then
		local name = C_Item.GetItemNameByID(itemID)
		local itemKeyInfo = C_AuctionHouse.GetItemKeyInfo(currentRequest.itemKey)
		if name and itemKeyInfo then
			currentRequest.name = name
			currentRequest.itemKeyInfo = itemKeyInfo
			currentRequest.isCommodity = itemKeyInfo.isCommodity
			waitingForItemInfo = false
			ScheduleSearch()
		end
	end
end

function module:ITEM_KEY_ITEM_INFO_RECEIVED(_, itemID)
	self:GET_ITEM_INFO_RECEIVED(nil, itemID)
end

function module:AUCTION_HOUSE_PURCHASE_COMPLETED(_, auctionID)
	if transactionPending and currentCandidate and currentCandidate.kind == "item"
		and auctionID == currentCandidate.auctionID then
		ResolveItemTransaction(true, false)
	end
end

function module:AUCTION_HOUSE_SHOW_ERROR()
	if transactionPending and pendingCommodityQuote then
		pendingCommodityQuote = nil
		transactionPending = false
		transactionDeadline = nil
		SetStatus(currentConfiguration, L["Commodity purchase failed; searching again."])
		ContinueAfterCandidate(true)
	elseif transactionPending then
		ResolveItemTransaction(false, true)
	elseif waitingForQuote then
		CancelCommodityQuote()
		SetStatus(currentConfiguration, L["Commodity price changed; searching again."])
		ContinueAfterCandidate(true)
	end
end

function module:COMMODITY_PRICE_UPDATED(_, unitPrice, totalPrice)
	ShowCommodityQuote(unitPrice, totalPrice)
end

function module:COMMODITY_PRICE_UNAVAILABLE()
	if waitingForQuote then
		CancelCommodityQuote()
		SetStatus(currentConfiguration, L["Commodity price changed; searching again."])
		ContinueAfterCandidate(true)
	end
end

function module:COMMODITY_PURCHASE_SUCCEEDED()
	if transactionPending and pendingCommodityQuote then
		-- Commodity results may have consumed several price tiers. Requery the item
		-- instead of trying to repair the old tier cursor locally.
		pendingCommodityQuote = nil
		transactionPending = false
		transactionDeadline = nil
		SetStatus(currentConfiguration, L["Auction action accepted; refreshing results."])
		ContinueAfterCandidate(true)
	end
end

function module:COMMODITY_PURCHASE_FAILED()
	if transactionPending and pendingCommodityQuote then
		pendingCommodityQuote = nil
		transactionPending = false
		transactionDeadline = nil
		SetStatus(currentConfiguration, L["Commodity purchase failed; searching again."])
		ContinueAfterCandidate(true)
	end
end