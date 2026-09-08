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
local LE_GAME_ERR_AUCTION_BID_OWN = LE_GAME_ERR_AUCTION_BID_OWN
local LE_GAME_ERR_AUCTION_DATABASE_ERROR = LE_GAME_ERR_AUCTION_DATABASE_ERROR
local LE_GAME_ERR_AUCTION_HIGHER_BID = LE_GAME_ERR_AUCTION_HIGHER_BID
local LE_GAME_ERR_ITEM_MAX_COUNT = LE_GAME_ERR_ITEM_MAX_COUNT
local LE_GAME_ERR_ITEM_NOT_FOUND = LE_GAME_ERR_ITEM_NOT_FOUND
local LE_GAME_ERR_NOT_ENOUGH_MONEY = LE_GAME_ERR_NOT_ENOUGH_MONEY
local LibStub = LibStub
local next = next
local pairs = pairs
local PlaceAuctionBid = PlaceAuctionBid
local QueryAuctionItems = QueryAuctionItems
local sort = table.sort
local StaticPopupDialogs = StaticPopupDialogs
local StaticPopup_Hide = StaticPopup_Hide
local StaticPopup_Show = StaticPopup_Show
local UnitFullName = UnitFullName

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local module = addon:NewModule("DisenchantingDeals", "AceEvent-3.0")
local auctionHouseUI = addon:GetModule("AuctionHouseUI")
local dataProcessing = addon:GetModule("DataProcessing")
local disenchantingData = addon:GetModule("DisenchantingData")
local saleCollector = addon:GetModule("SaleCollector")
local scanner = addon:GetModule("Scanner")
local tooltip = addon:GetModule("Tooltip")
local L = LibStub("AceLocale-3.0"):GetLocale("YAAHA")

local GREEN_NUMBER = "|cff20ff20"
local POPUP_NAME = "YAAHA_DISENCHANTING_DEAL"
local QUERY_RETRY_LIMIT = 3
local QUERY_TIMEOUT = 10
local RESULTS_PER_PAGE = 50
local TRANSACTION_TIMEOUT = 10

local actionButton, statusText
local currentCandidate, currentPage, currentRequest, nextResultIndex
local pendingPurchase
local queue, queueIndex
local advanceAfterPurchaseRefresh, resumePage, running, searchPending, transactionListUpdated, transactionPending
local waitingForItemInfo, waitingForPurchaseRefresh, waitingForResults
local queryAttempts = 0
local searchDeadline, transactionDeadline
local statusElapsed = 0
local wasScannerBusy
local updateFrame = CreateFrame("Frame")

local playerName, playerRealm = UnitFullName("player")
local playerFullName = playerRealm and playerRealm ~= "" and playerName .. "-" .. playerRealm or playerName

local function IsProfitable(buyout, expectedValue)
	if not buyout or buyout <= 0 or not expectedValue or expectedValue <= 0 then
		return false
	end
	return addon.db.profile.includeBreakEvenDeals and buyout <= expectedValue or buyout < expectedValue
end

local function SetStatus(text)
	if statusText then
		statusText:SetText(text)
	end
end

local function GetCacheCounts()
	local scope = scanner:GetAuctionScope()
	local disenchantList = scope and addon.db[scope].disenchantList
	local numItems, numListings = 0, 0
	for _, itemData in pairs(disenchantList or {}) do
		local itemListings = 0
		for _, auction in pairs(itemData.auctions) do
			if IsProfitable(auction.buyout, itemData.expectedValue) then
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
	waitingForItemInfo = false
	waitingForResults = false
	searchDeadline = GetTime() + QUERY_TIMEOUT
end

local function IsPlayerAuction(owner, ownerFullName)
	return owner == playerName or owner == playerFullName or ownerFullName == playerFullName
		or owner and addon.db.global.alts[owner]
		or ownerFullName and addon.db.global.alts[ownerFullName]
end

local function ReadListing(index)
	local _, _, count, _, _, _, _, _, _, buyout, _, _, _, owner, ownerFullName, _, itemID, hasAllInfo = GetAuctionItemInfo("list", index)
	if hasAllInfo == false then
		return nil, true
	end
	if not itemID or not count or count < 1 or not buyout or buyout <= 0 then
		return
	end
	return {
		index = index,
		itemID = itemID,
		link = GetAuctionItemLink("list", index),
		count = count,
		buyout = buyout,
		owner = owner,
		ownerFullName = ownerFullName,
	}
end

local function MatchesRequest(listing, request)
	return listing.itemID == request.itemID and listing.count == request.count
		and listing.buyout == request.buyout
		and not IsPlayerAuction(listing.owner, listing.ownerFullName)
end

local function FinishSearch(message)
	running = false
	searchPending = false
	transactionPending = false
	waitingForItemInfo = false
	waitingForResults = false
	resumePage = false
	advanceAfterPurchaseRefresh = false
	transactionListUpdated = false
	waitingForPurchaseRefresh = false
	queryAttempts = 0
	searchDeadline = nil
	transactionDeadline = nil
	currentCandidate = nil
	currentRequest = nil
	queue = nil
	if actionButton then
		actionButton:SetText(L["Disenchanting Deals"])
		actionButton:Enable()
	end
	SetStatus(message)
end

local function AdvanceRequest()
	currentCandidate = nil
	currentRequest = nil
	queueIndex = queueIndex + 1
	while queue and queueIndex <= #queue do
		local request = queue[queueIndex]
		if request.remaining > 0 then
			local name = C_Item.GetItemInfo(request.itemID)
			if name then
				request.name = name
				currentRequest = request
				currentPage = 0
				nextResultIndex = 1
				queryAttempts = 0
				ScheduleSearch()
				return
			end
		end
		queueIndex = queueIndex + 1
	end
	FinishSearch(L["Disenchanting deal search complete."])
end

local function ContinueAfterCandidate(requery)
	currentCandidate = nil
	currentRequest.remaining = currentRequest.remaining - 1
	if currentRequest.remaining <= 0 then
		AdvanceRequest()
	elseif requery then
		currentPage = 0
		nextResultIndex = 1
		ScheduleSearch()
	else
		resumePage = true
	end
end

local function IsAuctionActionError(errorType)
	return errorType == LE_GAME_ERR_AUCTION_BID_OWN
		or errorType == LE_GAME_ERR_AUCTION_DATABASE_ERROR
		or errorType == LE_GAME_ERR_AUCTION_HIGHER_BID
		or errorType == LE_GAME_ERR_ITEM_MAX_COUNT
		or errorType == LE_GAME_ERR_ITEM_NOT_FOUND
		or errorType == LE_GAME_ERR_NOT_ENOUGH_MONEY
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
		nextResultIndex = currentCandidate.index
		currentCandidate = nil
		currentRequest.remaining = currentRequest.remaining - 1
		advanceAfterPurchaseRefresh = currentRequest.remaining <= 0
		if transactionListUpdated then
			transactionDeadline = nil
			transactionListUpdated = false
			if advanceAfterPurchaseRefresh then
				advanceAfterPurchaseRefresh = false
				AdvanceRequest()
			else
				resumePage = true
			end
		else
			waitingForPurchaseRefresh = true
			transactionDeadline = GetTime() + TRANSACTION_TIMEOUT
		end
	else
		transactionDeadline = nil
		advanceAfterPurchaseRefresh = false
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
	if not disenchant or not IsProfitable(listing.buyout, disenchant.expectedValue) then
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
		local listing, itemInfoPending = ReadListing(index)
		if itemInfoPending then
			nextResultIndex = index
			waitingForItemInfo = true
			searchDeadline = GetTime() + QUERY_TIMEOUT
			return
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

local function BuildQueue(disenchantList)
	local requests = {}
	for itemID, itemData in pairs(disenchantList or {}) do
		for _, auction in pairs(itemData.auctions) do
			if IsProfitable(auction.buyout, itemData.expectedValue) then
				requests[#requests + 1] = {
					itemID = itemID,
					count = auction.count,
					buyout = auction.buyout,
					remaining = auction.numAuctions or 1,
					profit = itemData.expectedValue - auction.buyout,
				}
			end
		end
	end
	sort(requests, function(left, right)
		return left.profit > right.profit
	end)
	return requests
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
	queue = BuildQueue(disenchantList)
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
	advanceAfterPurchaseRefresh = false
	transactionListUpdated = false
	searchPending = false
	transactionPending = false
	waitingForItemInfo = false
	waitingForPurchaseRefresh = false
	waitingForResults = false
	queryAttempts = 0
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
	button2 = L["Skip"],
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
	local listing = ReadListing(candidate.index)
	local scope = scanner:GetAuctionScope()
	local disenchant = listing and scope and disenchantingData:GetValue(listing.itemID, scope)
	if not listing or not MatchesRequest(listing, candidate)
		or not disenchant or not IsProfitable(listing.buyout, disenchant.expectedValue) then
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
			if advanceAfterPurchaseRefresh then
				advanceAfterPurchaseRefresh = false
				AdvanceRequest()
			else
				currentPage = 0
				nextResultIndex = 1
				ScheduleSearch()
			end
		elseif running and resumePage then
			resumePage = false
			module:ProcessCurrentPage()
		end
		if running and not transactionPending and searchPending and not waitingForResults then
			local canQuery = CanSendAuctionQuery()
			if canQuery then
				searchPending = false
				waitingForResults = true
				queryAttempts = queryAttempts + 1
				searchDeadline = GetTime() + QUERY_TIMEOUT
				QueryAuctionItems(currentRequest.name, nil, nil, currentPage, false, nil, false, true, nil)
			elseif GetTime() >= searchDeadline then
				-- A throttle delay must not discard a cached opportunity.
				ScheduleSearch()
			end
		elseif running and waitingForItemInfo and GetTime() >= searchDeadline then
			waitingForItemInfo = false
			ScheduleSearch()
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
		transactionListUpdated = true
		return
	elseif running and waitingForPurchaseRefresh then
		waitingForPurchaseRefresh = false
		transactionDeadline = nil
		if advanceAfterPurchaseRefresh then
			advanceAfterPurchaseRefresh = false
			AdvanceRequest()
		else
			self:ProcessCurrentPage()
		end
		return
	end
	if running and (waitingForResults or waitingForItemInfo) then
		local receivedNewPage = waitingForResults
		waitingForResults = false
		waitingForItemInfo = false
		queryAttempts = 0
		if receivedNewPage then
			nextResultIndex = 1
		end
		self:ProcessCurrentPage()
	end
end

function module:GET_ITEM_INFO_RECEIVED()
	if running and waitingForItemInfo then
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
	if transactionPending and IsAuctionActionError(errorType) then
		ResolveTransaction(false, true)
	end
end