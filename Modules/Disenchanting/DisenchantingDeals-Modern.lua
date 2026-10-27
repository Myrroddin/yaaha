-- Finds and purchases complete Modern noncommodity listings at or below the
-- configured fraction of their expected disenchanting value.

local BUYOUT = BUYOUT
local C_AuctionHouse = C_AuctionHouse
local C_Item = C_Item
local CreateFrame = CreateFrame
local ERR_NOT_ENOUGH_MONEY = ERR_NOT_ENOUGH_MONEY
local format = string.format
local GameTooltip_Hide = GameTooltip_Hide
local GetMoney = GetMoney
local GetTime = GetTime
local ipairs = ipairs
local LibStub = LibStub
local pairs = pairs
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

local AUCTION_MINIMUM_PRICE = addon.auctionHouseMinimumPrice
local GREEN_NUMBER = addon.positiveNumberColor
local POPUP_NAME = "YAAHA_DISENCHANTING_DEAL_MODERN"
local QUERY_RETRY_LIMIT = 3
local QUERY_TIMEOUT = 10
local TRANSACTION_TIMEOUT = 10
local PRICE_SORT = {
	{
		sortOrder = Enum.AuctionHouseSortOrder.Price,
		reverseSort = false,
	},
}

local actionButton, statusText
local currentCandidate, currentRequest
local pendingBidsByAuction, pendingPurchase
local queue, queueIndex
local running, resumeResults, searchPending, transactionPending
local waitingForInitialResults, waitingForItemInfo, waitingForMoreResults
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

local function IsDisenchantingDeal(cost, value)
	return addon:IsBreakdownDeal(cost, value,
		addon.db.profile.disenchantingDealThreshold)
end

local function SetStatus(text)
	if statusText then
		statusText:SetText(text)
	end
end

local function ItemKeysEqual(left, right)
	return left and right
		and left.itemID == right.itemID
		and left.itemLevel == right.itemLevel
		and left.itemSuffix == right.itemSuffix
		and left.battlePetSpeciesID == right.battlePetSpeciesID
end

local function GetExpectedValue(itemID)
	local scope = scanner:GetAuctionScope()
	local disenchant = scope and disenchantingData:GetValue(itemID, scope)
	return disenchant and disenchant.expectedValue
end

local function GetCacheCounts()
	local scope = scanner:GetAuctionScope()
	local disenchantList = scope and addon.db[scope].disenchantList
	local numItems, numListings = 0, 0
	for _, itemData in pairs(disenchantList or {}) do
		local itemListings = 0
		for _, auction in pairs(itemData.auctions) do
			if auction.count == 1 and IsDisenchantingDeal(auction.buyout, itemData.expectedValue) then
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

local function ResetSearchState()
	searchPending = false
	waitingForInitialResults = false
	waitingForMoreResults = false
	searchDeadline = nil
	queryAttempts = 0
end

local function FinishSearch(message)
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
	ResetSearchState()
	if actionButton then
		actionButton:SetText(L["Disenchanting Deals"])
		actionButton:Enable()
	end
	SetStatus(message)
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
		return true
	end
	-- Disenchantable equipment must be an individually listed noncommodity. Fail
	-- closed if incomplete or future client data classifies the item otherwise.
	if request.itemKeyInfo.isCommodity then
		return false
	end
	ScheduleSearch()
	return true
end

AdvanceRequest = function()
	currentCandidate = nil
	currentRequest = nil
	while queue and queueIndex < #queue do
		queueIndex = queueIndex + 1
		if BeginRequest(queue[queueIndex]) then
			return
		end
	end
	FinishSearch(L["Disenchanting deal search complete."])
end

ContinueAfterCandidate = function(requery)
	currentCandidate = nil
	if requery then
		nextResultIndex = 1
		queryAttempts = 0
		ScheduleSearch()
	else
		-- Let the current dialog finish hiding before displaying another result.
		resumeResults = true
	end
end

local function BuildQueue(disenchantList, scope)
	-- Cached deals are a prefilter and ordering hint only. One live item query can
	-- revalidate every listing after material values or auction prices change.
	local requests = {}
	for itemID, itemData in pairs(disenchantList or {}) do
		local disenchant = disenchantingData:GetValue(itemID, scope)
		local expectedValue = disenchant and disenchant.expectedValue
		local bestProfit
		for _, auction in pairs(itemData.auctions) do
			if auction.count == 1 and IsDisenchantingDeal(auction.buyout, expectedValue) then
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

local function RevalidateCandidate(candidate)
	local result = FindItemResult(candidate.auctionID)
	if not result or result.quantity ~= 1 or IsOwnItemResult(result) then
		return
	end
	local buyout = result.buyoutAmount
	local expectedValue = GetExpectedValue(candidate.itemID)
	if not buyout or buyout < AUCTION_MINIMUM_PRICE
		or not IsDisenchantingDeal(buyout, expectedValue) then
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

local function ShowCandidate(result)
	if result.quantity ~= 1 or IsOwnItemResult(result) then
		return false
	end
	local buyout = result.buyoutAmount
	local expectedValue = GetExpectedValue(currentRequest.itemID)
	if not buyout or buyout < AUCTION_MINIMUM_PRICE
		or not IsDisenchantingDeal(buyout, expectedValue) then
		return false
	end

	local candidate = {
		auctionID = result.auctionID,
		buyout = buyout,
		expectedValue = expectedValue,
		itemID = currentRequest.itemID,
		link = result.itemLink,
		name = currentRequest.name,
	}
	currentCandidate = candidate
	local profit = expectedValue - buyout
	local text = format(L["Disenchanting deal: %s\nBuyout: %s\nDisenchant value: %s\nExpected profit: %s"],
		candidate.link or candidate.name, addon:FormatMoney(buyout),
		addon:FormatMoney(expectedValue), addon:FormatMoney(profit, true, GREEN_NUMBER))
	local popup = StaticPopup_Show(POPUP_NAME, text, nil, candidate)
	if not popup then
		currentCandidate = nil
		return false
	end
	AttachPopupTooltip(popup, candidate.itemID)
	return true
end

function module:ProcessCurrentResults()
	if not running or not currentRequest then
		return
	end
	for index = nextResultIndex, C_AuctionHouse.GetNumItemSearchResults(currentRequest.itemKey) do
		local result = C_AuctionHouse.GetItemSearchResultInfo(currentRequest.itemKey, index)
		nextResultIndex = index + 1
		if result and ShowCandidate(result) then
			return
		end
	end
	AdvanceRequest()
end

ContinueResultsLoading = function()
	if not running or not currentRequest then
		return
	end
	if C_AuctionHouse.HasFullItemSearchResults(currentRequest.itemKey) then
		waitingForInitialResults = false
		waitingForMoreResults = false
		queryAttempts = 0
		nextResultIndex = 1
		module:ProcessCurrentResults()
		return
	end
	-- Modern result events can precede the complete listing set. Wait for the full
	-- result flag and request remaining chunks before evaluating any candidate.
	if not C_AuctionHouse.IsThrottledMessageSystemReady() then
		waitingForMoreResults = true
		searchDeadline = GetTime() + QUERY_TIMEOUT
		return
	end
	waitingForMoreResults = true
	searchDeadline = GetTime() + QUERY_TIMEOUT
	local hasFullResults = C_AuctionHouse.RequestMoreItemSearchResults(currentRequest.itemKey)
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
		SetStatus(L["Disenchanting search timed out; continuing."])
		AdvanceRequest()
	end
end

local function ResolveTransaction(succeeded, confirmedFailure)
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
	SetStatus(succeeded and L["Auction action accepted; refreshing results."]
		or L["Auction action failed; refreshing results."])
	currentCandidate = nil
	nextResultIndex = 1
	queryAttempts = 0
	ScheduleSearch()
end

function module:BuyCandidate(candidate)
	if not running or transactionPending or candidate ~= currentCandidate then
		return
	end
	-- Revalidate the stable auction ID, whole-item quantity, alt protection, and
	-- threshold inside the hardware click; the popup may have become stale.
	local result, buyout = RevalidateCandidate(candidate)
	if not result then
		SetStatus(L["Auction listing changed; searching again."])
		ContinueAfterCandidate(true)
		return
	end
	if GetMoney() < buyout then
		SetStatus(ERR_NOT_ENOUGH_MONEY)
		ContinueAfterCandidate(false)
		return
	end
	-- PlaceBid is also the modern noncommodity buyout API. Keep the protected call
	-- directly in the popup click and pass the listing's exact buyout amount.
	transactionPending = true
	transactionDeadline = GetTime() + TRANSACTION_TIMEOUT
	SetStatus(L["Waiting for the auction house..."])
	pendingPurchase = saleCollector:RecordModernPendingPurchase(
		result.auctionID, buyout, "buy", "disenchant", result)
	C_AuctionHouse.PlaceBid(result.auctionID, buyout)
	saleCollector:ReleaseModernPendingPurchaseHook(pendingPurchase)
end

function module:SkipCandidate(candidate)
	if running and candidate == currentCandidate then
		ContinueAfterCandidate(false)
	end
end

local function StopSearch(message)
	StaticPopup_Hide(POPUP_NAME)
	FinishSearch(message or L["Disenchanting deal search stopped."])
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
	currentRequest = nil
	resumeResults = false
	transactionPending = false
	waitingForItemInfo = false
	itemInfoAttempts = 0
	nextResultIndex = 1
	transactionDeadline = nil
	ResetSearchState()
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

local function AcceptPopup(_, candidate)
	module:BuyCandidate(candidate)
end

local function CancelPopup(_, candidate)
	module:SkipCandidate(candidate)
end

StaticPopupDialogs[POPUP_NAME] = {
	text = "%s",
	button1 = BUYOUT,
	button2 = RENOWN_LEVEL_UP_SKIP_BUTTON,
	OnAccept = AcceptPopup,
	OnCancel = CancelPopup,
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
				StopSearch(L["Disenchanting deal search stopped for auction processing."])
			end
			if actionButton then
				actionButton:Disable()
			end
			if dataProcessing:IsProcessing() then
				local processed, total = dataProcessing:GetProgress()
				SetStatus(format(L["Building deal caches: %d/%d steps."], processed, total))
			else
				SetStatus(L["Waiting for auction scan results..."])
			end
		elseif wasScannerBusy then
			if actionButton then
				actionButton:Enable()
			end
			ShowCacheReady()
		end
		wasScannerBusy = scannerBusy
	end

	if not running then
		return
	end
	if transactionPending and GetTime() >= transactionDeadline then
		ResolveTransaction(false, false)
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
	elseif searchPending and not transactionPending then
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

function module:OnInitialize()
	tooltip = addon:GetModule("Tooltip")
end

function module:OnEnable()
	self:RegisterEvent("AUCTION_HOUSE_SHOW")
	self:RegisterEvent("AUCTION_HOUSE_CLOSED")
	self:RegisterEvent("AUCTION_HOUSE_PURCHASE_COMPLETED")
	self:RegisterEvent("AUCTION_HOUSE_SHOW_ERROR")
	self:RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
	self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	self:RegisterEvent("ITEM_KEY_ITEM_INFO_RECEIVED")
	self:RegisterEvent("ITEM_SEARCH_RESULTS_ADDED")
	self:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
	self:RegisterMessage("YAAHA_DEAL_SEARCH_STARTED")
	self:RegisterMessage("YAAHA_VENDOR_CACHE_READY")
	updateFrame:SetScript("OnUpdate", OnUpdate)
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

function module:AUCTION_HOUSE_SHOW()
	CreateInterface()
	wasScannerBusy = scanner:IsScanning()
	if not actionButton then
		return
	elseif wasScannerBusy then
		actionButton:Disable()
	else
		ShowCacheReady()
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

function module:GET_ITEM_INFO_RECEIVED(_, itemID)
	if not running or not waitingForItemInfo or itemID ~= currentRequest.itemID then
		return
	end
	local name = C_Item.GetItemNameByID(itemID)
	local itemKeyInfo = C_AuctionHouse.GetItemKeyInfo(currentRequest.itemKey)
	if not name or not itemKeyInfo then
		return
	end
	currentRequest.name = name
	currentRequest.itemKeyInfo = itemKeyInfo
	waitingForItemInfo = false
	if itemKeyInfo.isCommodity then
		AdvanceRequest()
	else
		ScheduleSearch()
	end
end

function module:ITEM_KEY_ITEM_INFO_RECEIVED(_, itemID)
	self:GET_ITEM_INFO_RECEIVED(nil, itemID)
end

function module:AUCTION_HOUSE_PURCHASE_COMPLETED(_, auctionID)
	if transactionPending and currentCandidate and auctionID == currentCandidate.auctionID then
		ResolveTransaction(true, false)
	end
end

function module:AUCTION_HOUSE_SHOW_ERROR()
	if transactionPending then
		ResolveTransaction(false, true)
	end
end