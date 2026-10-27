-- Finds and purchases complete Classic ore or herb stacks at or below the
-- configured fraction of their expected prospecting or milling value.

local BUYOUT = BUYOUT
local CanSendAuctionQuery = CanSendAuctionQuery
local C_Item = C_Item
local CreateFrame = CreateFrame
local ERR_AUCTION_BID_PLACED = ERR_AUCTION_BID_PLACED
local ERR_NOT_ENOUGH_MONEY = ERR_NOT_ENOUGH_MONEY
local format = string.format
local GameTooltip_Hide = GameTooltip_Hide
local GetAuctionItemInfo = GetAuctionItemInfo
local GetAuctionItemLink = GetAuctionItemLink
local GetMoney = GetMoney
local GetNumAuctionItems = GetNumAuctionItems
local GetTime = GetTime
local ipairs = ipairs
local LibStub = LibStub
local pairs = pairs
local PlaceAuctionBid = PlaceAuctionBid
local QueryAuctionItems = QueryAuctionItems
local RENOWN_LEVEL_UP_SKIP_BUTTON = RENOWN_LEVEL_UP_SKIP_BUTTON
local sort = table.sort
local StaticPopupDialogs = StaticPopupDialogs
local StaticPopup_Hide = StaticPopup_Hide
local StaticPopup_Show = StaticPopup_Show

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local module = addon:NewModule("MaterialDeals", "AceEvent-3.0")
local auctionHouseUI = addon:GetModule("AuctionHouseUI")
local dataProcessing = addon:GetModule("DataProcessing")
local saleCollector = addon:GetModule("SaleCollector")
local scanner = addon:GetModule("Scanner")
local tooltip
local L = LibStub("AceLocale-3.0"):GetLocale("YAAHA")

local GREEN_NUMBER = addon.positiveNumberColor
local QUERY_RETRY_LIMIT = 3
local QUERY_TIMEOUT = 10
local RESULTS_PER_PAGE = 50
local TRANSACTION_TIMEOUT = 10

local configurations = {
	{
		buttonOffset = -138,
		cacheEmpty = "Prospecting cache ready: no candidate listings.",
		cacheReady = "Prospecting cache ready: %d listings across %d items.",
		complete = "Prospecting deal search complete.",
		dataModule = addon:GetModule("ProspectingData", true),
		dealText = "Prospecting deal: %s x%d\nBuyout: %s\nProspecting value: %s\nExpected profit: %s",
		dealType = "prospect",
		label = "Prospecting Deals",
		listKey = "prospectList",
		noCache = "No cached prospecting deals are available. Scan this auction house first.",
		noDeals = "No profitable prospecting deals remain.",
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
		complete = "Milling deal search complete.",
		dataModule = addon:GetModule("MillingData", true),
		dealText = "Milling deal: %s x%d\nBuyout: %s\nMilling value: %s\nExpected profit: %s",
		dealType = "milling",
		label = "Milling Deals",
		listKey = "millingList",
		noCache = "No cached milling deals are available. Scan this auction house first.",
		noDeals = "No profitable milling deals remain.",
		searching = "Searching cached milling deals...",
		stopLabel = "Stop Milling Deals",
		stopped = "Milling deal search stopped.",
		stoppedForScan = "Milling deal search stopped for auction processing.",
		thresholdKey = "millingDealThreshold",
		timedOut = "Milling search timed out; continuing.",
	},
}
local configurationsByButton = {}

local POPUP_NAME = "YAAHA_MATERIAL_DEAL_CLASSIC"
local currentCandidate, currentConfiguration, currentPage, currentRequest, nextResultIndex
local pendingBidsByItem
local pendingListingIndex, pendingListingItemID, pendingListingPage
local pendingPurchase
local queue, queueIndex
local resumePage, running, searchPending, transactionListUpdated, transactionPending
local waitingForItemInfo, waitingForPurchaseRefresh, waitingForRequestItemInfo, waitingForResults
local listingItemInfoAttempts, queryAttempts, requestItemInfoAttempts = 0, 0, 0
local searchListUpdated
local searchDeadline, transactionDeadline
local statusElapsed = 0
local wasScannerBusy
local updateFrame = CreateFrame("Frame")

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

local function ClearPendingListing()
	pendingListingIndex = nil
	pendingListingItemID = nil
	pendingListingPage = nil
	listingItemInfoAttempts = 0
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

local function ScheduleSearch()
	searchPending = true
	searchListUpdated = false
	waitingForItemInfo = false
	waitingForRequestItemInfo = false
	waitingForResults = false
	searchDeadline = GetTime() + QUERY_TIMEOUT
end

local function ReadListing(index)
	local name, _, count, _, _, _, _, minBid, _, buyout, bidAmount, highBidder,
		bidderFullName, owner, ownerFullName, _, itemID, hasAllInfo = GetAuctionItemInfo("list", index)
	if hasAllInfo == false then
		return nil, true, itemID
	end
	if not itemID or not count or count < 1 or not buyout or buyout <= 0 then
		return
	end
	return {
		index = index,
		itemID = itemID,
		name = name,
		link = GetAuctionItemLink("list", index),
		count = count,
		minBid = minBid,
		buyout = buyout,
		bidAmount = bidAmount,
		highBidder = highBidder,
		bidderFullName = bidderFullName,
		owner = owner,
		ownerFullName = ownerFullName,
	}
end

local function MatchesRequest(listing, request)
	return listing.itemID == request.itemID
		and not addon:IsPlayerAuction(listing.owner, listing.ownerFullName)
		and not saleCollector:IsClassicAccountHighBidder(
			listing, pendingBidsByItem and pendingBidsByItem[listing.itemID])
end

local function FinishSearch(message)
	local configuration = currentConfiguration
	running = false
	searchPending = false
	transactionPending = false
	waitingForItemInfo = false
	waitingForRequestItemInfo = false
	waitingForResults = false
	resumePage = false
	searchListUpdated = false
	transactionListUpdated = false
	waitingForPurchaseRefresh = false
	queryAttempts = 0
	requestItemInfoAttempts = 0
	ClearPendingListing()
	searchDeadline = nil
	transactionDeadline = nil
	currentCandidate = nil
	currentRequest = nil
	pendingBidsByItem = nil
	pendingPurchase = nil
	queue = nil
	currentConfiguration = nil
	if configuration and configuration.actionButton then
		configuration.actionButton:SetText(L[configuration.label])
		configuration.actionButton:Enable()
	end
	SetStatus(configuration, message)
end

local function BeginRequest(request, name)
	ClearPendingListing()
	request.name = name
	currentRequest = request
	currentPage = 0
	nextResultIndex = 1
	queryAttempts = 0
	requestItemInfoAttempts = 0
	waitingForRequestItemInfo = false
	ScheduleSearch()
end

local function RetryOrSkipPendingListing()
	-- Classic can publish a result row before its item data. Preserve the exact
	-- cursor across bounded retries; one permanently incomplete row must not stall
	-- every later prospecting or milling candidate.
	waitingForItemInfo = false
	if listingItemInfoAttempts < QUERY_RETRY_LIMIT then
		listingItemInfoAttempts = listingItemInfoAttempts + 1
		if pendingListingItemID then
			C_Item.RequestLoadItemDataByID(pendingListingItemID)
		end
		ScheduleSearch()
		return
	end

	local skippedIndex = pendingListingIndex or nextResultIndex
	ClearPendingListing()
	nextResultIndex = skippedIndex + 1
	SetStatus(currentConfiguration, L["Auction listing data unavailable; skipping."])
	module:ProcessCurrentPage()
end

local function WaitForRequestItemInfo(request)
	currentRequest = request
	waitingForRequestItemInfo = true
	requestItemInfoAttempts = requestItemInfoAttempts + 1
	searchDeadline = GetTime() + QUERY_TIMEOUT
	C_Item.RequestLoadItemDataByID(request.itemID)
end

local function AdvanceRequest()
	currentCandidate = nil
	currentRequest = nil
	queueIndex = queueIndex + 1
	while queue and queueIndex <= #queue do
		local request = queue[queueIndex]
		local name = C_Item.GetItemInfo(request.itemID)
		if name then
			BeginRequest(request, name)
			return
		end
		requestItemInfoAttempts = 0
		WaitForRequestItemInfo(request)
		return
	end
	FinishSearch(L[currentConfiguration.complete])
end

local function ContinueAfterCandidate(requery)
	currentCandidate = nil
	if requery then
		-- A changed or failed listing can reorder the full result set, so restart the
		-- focused item query instead of trusting the old page and row positions.
		currentPage = 0
		nextResultIndex = 1
		ScheduleSearch()
	else
		resumePage = true
	end
end

local function ResolveTransaction(succeeded, confirmedFailure)
	transactionPending = false
	if not running or not currentRequest then
		transactionDeadline = nil
		return
	end
	if succeeded then
		pendingPurchase = nil
		SetStatus(currentConfiguration, L["Auction action accepted; refreshing results."])
		-- Buying removes this row and shifts the following listing into its index.
		-- Resume there after Blizzard publishes the refreshed page.
		nextResultIndex = currentCandidate.index
		currentCandidate = nil
		if transactionListUpdated then
			transactionDeadline = nil
			transactionListUpdated = false
			resumePage = true
		else
			waitingForPurchaseRefresh = true
			transactionDeadline = GetTime() + TRANSACTION_TIMEOUT
		end
	else
		transactionDeadline = nil
		transactionListUpdated = false
		waitingForPurchaseRefresh = false
		if confirmedFailure and pendingPurchase then
			saleCollector:DiscardPendingPurchase(pendingPurchase)
		end
		pendingPurchase = nil
		SetStatus(currentConfiguration, L["Auction action failed; refreshing results."])
		currentCandidate = nil
		currentPage = 0
		nextResultIndex = 1
		ScheduleSearch()
	end
end

local function ShowCandidate(listing)
	local scope = scanner:GetAuctionScope()
	local expectedUnitValue = scope and GetExpectedUnitValue(
		currentConfiguration, listing.itemID, scope)
	local expectedValue = expectedUnitValue and expectedUnitValue * listing.count
	if not expectedValue or not IsDeal(currentConfiguration, listing.buyout, expectedValue) then
		return false
	end

	listing.expectedValue = expectedValue
	currentCandidate = listing
	local profit = expectedValue - listing.buyout
	local text = format(L[currentConfiguration.dealText],
		listing.link or currentRequest.name, listing.count, addon:FormatMoney(listing.buyout),
		addon:FormatMoney(expectedValue), addon:FormatMoney(profit, true, GREEN_NUMBER))
	local popup = StaticPopup_Show(POPUP_NAME, text, nil, listing)
	if not popup then
		currentCandidate = nil
		return false
	end
	popup.yaahaItemID = listing.itemID
	if not popup.yaahaTooltipHooked then
		popup.yaahaTooltipHooked = true
		popup:SetHyperlinksEnabled(true)
		popup:HookScript("OnHyperlinkEnter", function(self, link)
			if self.yaahaItemID then
				tooltip:ShowTooltip(self, link, self.yaahaItemID, scanner:GetAuctionScope())
			end
		end)
		popup:HookScript("OnHyperlinkLeave", GameTooltip_Hide)
		popup:HookScript("OnHide", function(self)
			self.yaahaItemID = nil
			GameTooltip_Hide()
		end)
	end
	return true
end

function module:ProcessCurrentPage()
	if not running or not currentRequest then
		return
	end
	local numResults, totalResults = GetNumAuctionItems("list")
	for index = nextResultIndex, numResults do
		local listing, itemInfoPending, pendingItemID = ReadListing(index)
		if itemInfoPending then
			if pendingListingPage ~= currentPage or pendingListingIndex ~= index
				or pendingListingItemID ~= pendingItemID then
				pendingListingPage = currentPage
				pendingListingIndex = index
				pendingListingItemID = pendingItemID
				listingItemInfoAttempts = 1
				searchDeadline = GetTime() + QUERY_TIMEOUT
				if pendingItemID then
					C_Item.RequestLoadItemDataByID(pendingItemID)
				end
			end
			nextResultIndex = index
			waitingForItemInfo = true
			return
		end
		if pendingListingPage == currentPage and pendingListingIndex == index then
			ClearPendingListing()
		end
		if listing and MatchesRequest(listing, currentRequest) then
			nextResultIndex = index + 1
			if ShowCandidate(listing) then
				return
			end
		end
	end
	if (currentPage + 1) * RESULTS_PER_PAGE < totalResults then
		-- Legacy searches expose fixed-size pages. Follow every page before moving
		-- to the next cached item or valid deals near the end would be omitted.
		currentPage = currentPage + 1
		nextResultIndex = 1
		ScheduleSearch()
	else
		AdvanceRequest()
	end
end

local function ResultsMatchCurrentRequest()
	local numResults = GetNumAuctionItems("list")
	for index = 1, numResults do
		local name, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, hasAllInfo = GetAuctionItemInfo("list", index)
		if hasAllInfo ~= false and name and name ~= currentRequest.name then
			return false
		end
	end
	return true
end

local function ConsumeSearchResults()
	if not running or not waitingForResults or not searchListUpdated or not CanSendAuctionQuery() then
		return
	end

	searchListUpdated = false
	if not ResultsMatchCurrentRequest() then
		waitingForResults = false
		ScheduleSearch()
		return
	end

	waitingForResults = false
	waitingForItemInfo = false
	queryAttempts = 0
	nextResultIndex = 1
	module:ProcessCurrentPage()
end

local function BuildQueue(configuration, dealList, scope)
	-- The scan cache is only a prefilter. Query each item once, order items by their
	-- strongest cached opportunity, and revalue every live stack before purchase.
	local requests = {}
	local requestsByItem = {}
	for itemID, itemData in pairs(dealList or {}) do
		local expectedUnitValue = GetExpectedUnitValue(configuration, itemID, scope)
		for _, auction in pairs(itemData.auctions) do
			local expectedValue = expectedUnitValue and expectedUnitValue * auction.count
			if IsDeal(configuration, auction.buyout, expectedValue) then
				local profit = expectedValue - auction.buyout
				local request = requestsByItem[itemID]
				if request then
					if profit > request.profit then
						request.profit = profit
					end
				else
					request = { itemID = itemID, profit = profit }
					requestsByItem[itemID] = request
					requests[#requests + 1] = request
				end
			end
		end
	end
	sort(requests, SortByProfit)
	return requests
end

local function CachePendingBids(scope)
	pendingBidsByItem = {}
	if not scope then
		return
	end
	for _, purchase in ipairs(saleCollector:GetPendingBids(scope, true)) do
		local bids = pendingBidsByItem[purchase.itemID]
		if not bids then
			bids = {}
			pendingBidsByItem[purchase.itemID] = bids
		end
		bids[#bids + 1] = purchase
	end
end

local function StopSearch(message)
	StaticPopup_Hide(POPUP_NAME)
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
	currentPage = 0
	currentRequest = nil
	nextResultIndex = 1
	resumePage = false
	transactionListUpdated = false
	searchPending = false
	transactionPending = false
	waitingForItemInfo = false
	waitingForPurchaseRefresh = false
	waitingForRequestItemInfo = false
	waitingForResults = false
	queryAttempts = 0
	requestItemInfoAttempts = 0
	searchListUpdated = false
	searchDeadline = nil
	transactionDeadline = nil
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

StaticPopupDialogs[POPUP_NAME] = {
	text = "%s",
	button1 = BUYOUT,
	button2 = RENOWN_LEVEL_UP_SKIP_BUTTON,
	OnAccept = function(_, data)
		module:BuyCandidate(data)
	end,
	OnCancel = function(_, data)
		module:SkipCandidate(data)
	end,
	timeout = 0,
	whileDead = false,
	hideOnEscape = false,
}

function module:BuyCandidate(candidate)
	if not running or transactionPending or candidate ~= currentCandidate then
		return
	end
	-- The popup may outlive the auction row. Re-read owner, price, quantity, and
	-- breakdown value immediately inside the player's protected purchase action.
	local listing = ReadListing(candidate.index)
	if not listing then
		SetStatus(currentConfiguration, L["Auction listing changed; searching again."])
		ContinueAfterCandidate(true)
		return
	end
	local scope = scanner:GetAuctionScope()
	local expectedUnitValue = scope and GetExpectedUnitValue(
		currentConfiguration, listing.itemID, scope)
	local expectedValue = expectedUnitValue and expectedUnitValue * listing.count
	if not MatchesRequest(listing, candidate)
		or not IsDeal(currentConfiguration, listing.buyout, expectedValue) then
		SetStatus(currentConfiguration, L["Auction listing changed; searching again."])
		ContinueAfterCandidate(true)
		return
	end
	if GetMoney() < listing.buyout then
		SetStatus(currentConfiguration, ERR_NOT_ENOUGH_MONEY)
		ContinueAfterCandidate(false)
		return
	end
	transactionPending = true
	transactionListUpdated = false
	waitingForPurchaseRefresh = false
	transactionDeadline = GetTime() + TRANSACTION_TIMEOUT
	SetStatus(currentConfiguration, L["Waiting for the auction house..."])
	pendingPurchase = saleCollector:RecordPendingPurchase(
		"list", listing.index, listing.buyout, "buy", currentConfiguration.dealType)
	PlaceAuctionBid("list", listing.index, listing.buyout)
	saleCollector:ReleasePendingPurchaseHook(pendingPurchase)
end

function module:SkipCandidate(candidate)
	if running and candidate == currentCandidate then
		ContinueAfterCandidate(false)
	end
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
		ResolveTransaction(false, false)
	elseif waitingForPurchaseRefresh and GetTime() >= transactionDeadline then
		waitingForPurchaseRefresh = false
		transactionDeadline = nil
		currentPage = 0
		nextResultIndex = 1
		ScheduleSearch()
	elseif resumePage then
		resumePage = false
		module:ProcessCurrentPage()
	end
	if running and waitingForResults and searchListUpdated then
		ConsumeSearchResults()
	end
	if running and waitingForRequestItemInfo and GetTime() >= searchDeadline then
		if requestItemInfoAttempts < QUERY_RETRY_LIMIT then
			WaitForRequestItemInfo(currentRequest)
		else
			waitingForRequestItemInfo = false
			requestItemInfoAttempts = 0
			AdvanceRequest()
		end
	elseif running and not transactionPending and searchPending and not waitingForResults then
		if CanSendAuctionQuery() then
			searchPending = false
			searchListUpdated = false
			waitingForResults = true
			queryAttempts = queryAttempts + 1
			searchDeadline = GetTime() + QUERY_TIMEOUT
			-- exactMatch keeps similarly named ore or herbs out of this item's pages.
			QueryAuctionItems(currentRequest.name, nil, nil, currentPage, false, nil, false, true, nil)
		elseif GetTime() >= searchDeadline then
			ScheduleSearch()
		end
	elseif running and waitingForItemInfo and GetTime() >= searchDeadline then
		RetryOrSkipPendingListing()
	elseif running and waitingForResults and GetTime() >= searchDeadline then
		waitingForResults = false
		if queryAttempts < QUERY_RETRY_LIMIT then
			ScheduleSearch()
		else
			SetStatus(currentConfiguration, L[currentConfiguration.timedOut])
			AdvanceRequest()
		end
	end
end

function module:OnInitialize()
	tooltip = addon:GetModule("Tooltip")
end

function module:OnEnable()
	self:RegisterEvent("AUCTION_HOUSE_SHOW")
	self:RegisterEvent("AUCTION_HOUSE_CLOSED")
	self:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
	self:RegisterEvent("CHAT_MSG_SYSTEM")
	self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	self:RegisterEvent("UI_ERROR_MESSAGE")
	self:RegisterMessage("YAAHA_DEAL_SEARCH_STARTED")
	self:RegisterMessage("YAAHA_VENDOR_CACHE_READY")
	updateFrame:SetScript("OnUpdate", OnUpdate)
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

function module:AUCTION_ITEM_LIST_UPDATE()
	-- This payload-free event also fires for sorting and other addons' queries.
	-- Consume it only in the state that requested it and verify the returned names
	-- before treating the page as belonging to the active item.
	if not running then
		return
	end
	if transactionPending then
		if ResultsMatchCurrentRequest() then
			transactionListUpdated = true
		end
		return
	elseif waitingForPurchaseRefresh then
		if not ResultsMatchCurrentRequest() then
			return
		end
		waitingForPurchaseRefresh = false
		transactionDeadline = nil
		self:ProcessCurrentPage()
		return
	elseif waitingForResults then
		searchListUpdated = true
		ConsumeSearchResults()
		return
	elseif waitingForItemInfo then
		waitingForItemInfo = false
		self:ProcessCurrentPage()
	end
end

function module:GET_ITEM_INFO_RECEIVED(_, itemID, success)
	if running and waitingForRequestItemInfo and currentRequest
		and itemID == currentRequest.itemID then
		local name = C_Item.GetItemInfo(itemID)
		if name then
			BeginRequest(currentRequest, name)
		elseif success == false and requestItemInfoAttempts >= QUERY_RETRY_LIMIT then
			waitingForRequestItemInfo = false
			requestItemInfoAttempts = 0
			AdvanceRequest()
		elseif success == false then
			WaitForRequestItemInfo(currentRequest)
		end
		return
	end
	if running and waitingForItemInfo and pendingListingItemID == itemID then
		if success == false then
			RetryOrSkipPendingListing()
			return
		end
		waitingForItemInfo = false
		self:ProcessCurrentPage()
	end
end

function module:CHAT_MSG_SYSTEM(_, message)
	if transactionPending and message == ERR_AUCTION_BID_PLACED then
		ResolveTransaction(true, false)
	end
end

function module:UI_ERROR_MESSAGE(_, errorType)
	if transactionPending and addon:IsAuctionActionError(errorType) then
		ResolveTransaction(false, true)
	end
end