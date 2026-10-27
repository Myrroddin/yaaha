-- Finds and purchases complete Classic noncommodity listings at or below the
-- configured fraction of their expected disenchanting value.

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
local module = addon:NewModule("DisenchantingDeals", "AceEvent-3.0")
local auctionHouseUI = addon:GetModule("AuctionHouseUI")
local dataProcessing = addon:GetModule("DataProcessing")
local disenchantingData = addon:GetModule("DisenchantingData")
local saleCollector = addon:GetModule("SaleCollector")
local scanner = addon:GetModule("Scanner")
local tooltip
local L = LibStub("AceLocale-3.0"):GetLocale("YAAHA")

local GREEN_NUMBER = addon.positiveNumberColor
local POPUP_NAME = "YAAHA_DISENCHANTING_DEAL"
local QUERY_RETRY_LIMIT = 3
local QUERY_TIMEOUT = 10
local RESULTS_PER_PAGE = 50
local TRANSACTION_TIMEOUT = 10

local actionButton, statusText
local currentCandidate, currentPage, currentRequest, nextResultIndex
local pendingBidsByItem
local pendingListingIndex, pendingListingItemID, pendingListingPage
local pendingPurchase
local queue, queueIndex

local function SortByProfit(left, right)
	return left.profit > right.profit
end
local resumePage, running, searchPending, transactionListUpdated, transactionPending
local waitingForItemInfo, waitingForPurchaseRefresh, waitingForRequestItemInfo, waitingForResults
local listingItemInfoAttempts, queryAttempts, requestItemInfoAttempts = 0, 0, 0
local searchListUpdated
local searchDeadline, transactionDeadline
local statusElapsed = 0
local wasScannerBusy
local updateFrame = CreateFrame("Frame")

local function IsDisenchantingDeal(cost, value)
	return addon:IsBreakdownDeal(cost, value,
		addon.db.profile.disenchantingDealThreshold)
end

local function SetStatus(text)
	if statusText then
		statusText:SetText(text)
	end
end

local function ClearPendingListing()
	pendingListingIndex = nil
	pendingListingItemID = nil
	pendingListingPage = nil
	listingItemInfoAttempts = 0
end

local function GetCacheCounts()
	local scope = scanner:GetAuctionScope()
	local disenchantList = scope and addon.db[scope].disenchantList
	local numItems, numListings = 0, 0
	for _, itemData in pairs(disenchantList or {}) do
		local itemListings = 0
		for _, auction in pairs(itemData.auctions) do
			if IsDisenchantingDeal(auction.buyout, itemData.expectedValue) then
				itemListings = itemListings + (auction.numAuctions or 1)
			end
		end
		if itemListings > 0 then
			numItems = numItems + 1
			numListings = numListings + itemListings
		end
	end
	return numItems, numListings
end

local function ShowCacheReady()
	local numItems, numListings = GetCacheCounts()
	if numListings > 0 then
		SetStatus(format(L["Disenchanting cache ready: %d listings across %d items."], numListings, numItems))
	else
		SetStatus(L["Disenchanting cache ready: no candidate listings."])
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
	queue = nil
	if actionButton then
		actionButton:SetText(L["Disenchanting Deals"])
		actionButton:Enable()
	end
	SetStatus(message)
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
	SetStatus(L["Auction listing data unavailable; skipping."])
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
		-- A cold item cache is not evidence that the cached auction candidate is
		-- invalid. Request its name and resume this same entry when Blizzard supplies it.
		requestItemInfoAttempts = 0
		WaitForRequestItemInfo(request)
		return
	end
	FinishSearch(L["Disenchanting deal search complete."])
end

local function ContinueAfterCandidate(requery)
	currentCandidate = nil
	if requery then
		-- A failed or changed row may have reordered the result set. Restart the
		-- focused item query rather than resuming from a stale page cursor.
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
		SetStatus(L["Auction action accepted; refreshing results."])
		-- A purchased auction disappears and the next row moves into its index.
		-- Continue on the refreshed page at that index rather than re-querying it.
		-- Buying removes this row and shifts the following listing into its index.
		-- Resume at the same index after the refreshed page arrives.
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
		SetStatus(L["Auction action failed; refreshing results."])
		currentCandidate = nil
		currentPage = 0
		nextResultIndex = 1
		ScheduleSearch()
	end
end

local function ShowCandidate(listing)
	local scope = scanner:GetAuctionScope()
	local disenchant = scope and disenchantingData:GetValue(listing.itemID, scope)
	if not disenchant or not IsDisenchantingDeal(listing.buyout, disenchant.expectedValue) then
		return false
	end

	listing.expectedValue = disenchant.expectedValue
	currentCandidate = listing
	local profit = disenchant.expectedValue - listing.buyout
	local text = format(L["Disenchanting deal: %s\nBuyout: %s\nDisenchant value: %s\nExpected profit: %s"],
		listing.link or currentRequest.name, addon:FormatMoney(listing.buyout),
		addon:FormatMoney(disenchant.expectedValue), addon:FormatMoney(profit, true, GREEN_NUMBER))
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
			-- Keep the exact row pending while Classic resolves its item data, but do
			-- not let one permanently incomplete result block every later candidate.
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

local function BuildQueue(disenchantList, scope)
	local requests = {}
	local requestsByItem = {}
	-- Query each candidate item once, then evaluate every live buyout returned for
	-- it. Recalculate its expected value so a corrected learned range or newer
	-- material price invalidates an old candidate cache before any item queries.
	for itemID, itemData in pairs(disenchantList or {}) do
		local disenchant = disenchantingData:GetValue(itemID, scope)
		local expectedValue = disenchant and disenchant.expectedValue
		for _, auction in pairs(itemData.auctions) do
			if IsDisenchantingDeal(auction.buyout, expectedValue) then
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
	FinishSearch(message or L["Disenchanting deal search stopped."])
end

local function StartSearch()
	if running then
		StopSearch()
		return
	elseif scanner:IsScanning() then
		SetStatus(dataProcessing:IsProcessing() and L["Processing scan data..."]
			or L["Waiting for auction scan results..."])
		return
	end
	local scope = scanner:GetAuctionScope()
	local disenchantList = scope and addon.db[scope].disenchantList
	CachePendingBids(scope)
	queue = BuildQueue(disenchantList, scope)
	if #queue == 0 then
		local scanStats = scope and addon.db[scope].auctionStats
		if not scanStats or not scanStats.lastScan then
			SetStatus(L["No cached disenchanting deals are available. Scan this auction house first."])
		else
			SetStatus(L["No profitable disenchanting deals remain."])
		end
		return
	end

	module:SendMessage("YAAHA_DEAL_SEARCH_STARTED", "disenchant")
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
	actionButton:SetText(L["Stop Disenchanting Deals"])
	SetStatus(L["Searching cached disenchanting deals..."])
	AdvanceRequest()
end

local function CreateInterface()
	local page = auctionHouseUI:GetPage("deals")
	if not page or actionButton then
		return
	end
	actionButton = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	actionButton:SetSize(180, 24)
	actionButton:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -76)
	actionButton:SetText(L["Disenchanting Deals"])
	actionButton:SetScript("OnClick", StartSearch)

	statusText = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	statusText:SetPoint("TOPLEFT", actionButton, "BOTTOMLEFT", 0, -10)
	statusText:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -110)
	statusText:SetJustifyH("LEFT")
	statusText:SetText("")
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
	-- Re-read the live row and expected materials inside the protected click. The
	-- popup can outlive its cached price, owner, or disenchant value.
	local listing = ReadListing(candidate.index)
	local scope = scanner:GetAuctionScope()
	local disenchant = listing and scope and disenchantingData:GetValue(listing.itemID, scope)
	if not listing or not MatchesRequest(listing, candidate)
		or not disenchant or not IsDisenchantingDeal(listing.buyout, disenchant.expectedValue) then
		SetStatus(L["Auction listing changed; searching again."])
		ContinueAfterCandidate(true)
		return
	end
	if GetMoney() < listing.buyout then
		SetStatus(ERR_NOT_ENOUGH_MONEY)
		ContinueAfterCandidate(false)
		return
	end
	transactionPending = true
	transactionListUpdated = false
	waitingForPurchaseRefresh = false
	transactionDeadline = GetTime() + TRANSACTION_TIMEOUT
	SetStatus(L["Waiting for the auction house..."])
	pendingPurchase = saleCollector:RecordPendingPurchase("list", listing.index, listing.buyout, "buy", "disenchant")
	PlaceAuctionBid("list", listing.index, listing.buyout)
	saleCollector:ReleasePendingPurchaseHook(pendingPurchase)
end

function module:SkipCandidate(candidate)
	if running and candidate == currentCandidate then
		ContinueAfterCandidate(false)
	end
end

function module:YAAHA_DEAL_SEARCH_STARTED(_, dealType)
	if running and dealType ~= "disenchant" then
		StopSearch()
	end
end

function module:YAAHA_VENDOR_CACHE_READY(_, scope)
	if scope ~= scanner:GetAuctionScope() or not actionButton then
		return
	end
	wasScannerBusy = false
	actionButton:Enable()
	ShowCacheReady()
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
	updateFrame:SetScript("OnUpdate", function(_, elapsed)
		statusElapsed = statusElapsed + elapsed
		if statusElapsed >= 0.2 then
			statusElapsed = 0
			local scannerBusy = scanner:IsScanning()
			if scannerBusy then
				if running then
					StopSearch(L["Disenchanting deal search stopped for auction processing."])
				end
				actionButton:Disable()
				SetStatus(L["Processing scan data..."])
			elseif wasScannerBusy then
				actionButton:Enable()
				ShowCacheReady()
			end
			wasScannerBusy = scannerBusy
		end
		if running and transactionPending and GetTime() >= transactionDeadline then
			ResolveTransaction(false, false)
		elseif running and waitingForPurchaseRefresh and GetTime() >= transactionDeadline then
			waitingForPurchaseRefresh = false
			transactionDeadline = nil
			currentPage = 0
			nextResultIndex = 1
			ScheduleSearch()
		elseif running and resumePage then
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
			local canQuery = CanSendAuctionQuery()
			if canQuery then
				searchPending = false
				searchListUpdated = false
				waitingForResults = true
				queryAttempts = queryAttempts + 1
				searchDeadline = GetTime() + QUERY_TIMEOUT
				QueryAuctionItems(currentRequest.name, nil, nil, currentPage, false, nil, false, true, nil)
			elseif GetTime() >= searchDeadline then
				-- A throttle delay must not discard a cached opportunity.
				ScheduleSearch()
			end
		elseif running and waitingForItemInfo and GetTime() >= searchDeadline then
			RetryOrSkipPendingListing()
		elseif running and waitingForResults and GetTime() >= searchDeadline then
			waitingForResults = false
			if queryAttempts < QUERY_RETRY_LIMIT then
				ScheduleSearch()
			else
				SetStatus(L["Disenchanting search timed out; continuing."])
				AdvanceRequest()
			end
		end
	end)
end

function module:AUCTION_HOUSE_SHOW()
	CreateInterface()
	wasScannerBusy = scanner:IsScanning()
	if wasScannerBusy then
		actionButton:Disable()
		SetStatus(L["Processing scan data..."])
	else
		ShowCacheReady()
	end
end

function module:AUCTION_HOUSE_CLOSED()
	if running then
		StopSearch()
	end
end

function module:AUCTION_ITEM_LIST_UPDATE()
	if running and transactionPending then
		if ResultsMatchCurrentRequest() then
			transactionListUpdated = true
		end
		return
	elseif running and waitingForPurchaseRefresh then
		if not ResultsMatchCurrentRequest() then
			return
		end
		waitingForPurchaseRefresh = false
		transactionDeadline = nil
		self:ProcessCurrentPage()
		return
	end
	if running and waitingForResults then
		-- This payload-free event is shared with sorting and other addons' searches.
		-- Auctioneer likewise waits for both this event and query-throttle readiness;
		-- the event can arrive before Classic has finished publishing the result page.
		searchListUpdated = true
		ConsumeSearchResults()
		return
	elseif running and waitingForItemInfo then
		waitingForItemInfo = false
		self:ProcessCurrentPage()
	end
end

function module:GET_ITEM_INFO_RECEIVED(_, itemID, success)
	if running and waitingForRequestItemInfo and currentRequest and itemID == currentRequest.itemID then
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