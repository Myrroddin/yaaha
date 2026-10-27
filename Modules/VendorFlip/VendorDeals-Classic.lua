-- Finds and presents complete Classic auction stacks whose bid or buyout does
-- not exceed their NPC value under the configured break-even policy.

local BID = BID
local BUYOUT = BUYOUT
local CanSendAuctionQuery = CanSendAuctionQuery
local C_Item = C_Item
local CreateFrame = CreateFrame
local ERR_AUCTION_BID_PLACED = ERR_AUCTION_BID_PLACED
local ERR_NOT_ENOUGH_MONEY = ERR_NOT_ENOUGH_MONEY
local floor = math.floor
local format = string.format
local GameTooltip_Hide = GameTooltip_Hide
local GetAuctionItemInfo = GetAuctionItemInfo
local GetAuctionItemLink = GetAuctionItemLink
local GetItemInfo = C_Item.GetItemInfo
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
local module = addon:NewModule("VendorDeals", "AceEvent-3.0")
local auctionHouseUI = addon:GetModule("AuctionHouseUI")
local dataProcessing = addon:GetModule("DataProcessing")
local scanner = addon:GetModule("Scanner")
local saleCollector = addon:GetModule("SaleCollector")
local tooltip = addon:GetModule("Tooltip")
local L = LibStub("AceLocale-3.0"):GetLocale("YAAHA")

local POPUP_NAME = "YAAHA_VENDOR_FLIP"
local QUERY_RETRY_LIMIT = 3
local QUERY_TIMEOUT = 10
local RESULTS_PER_PAGE = 50
local TRANSACTION_TIMEOUT = 10
local GREEN_NUMBER = addon.positiveNumberColor
local RED_NUMBER = addon.negativeNumberColor

local actionButton, restartButton, statusText
local AdvanceRequest, ContinueAfterCandidate
local currentCandidate, currentPage, currentRequest, nextResultIndex
local pendingListingIndex, pendingListingItemID, pendingListingPage
local pendingPurchase
local queue, queueIndex

local function SortByBestProfit(left, right)
	return left.bestProfit > right.bestProfit
end
local running, searchPending, transactionPending, waitingForItemInfo, waitingForRequestItemInfo, waitingForResults
local resumePage, transactionListUpdated, waitingForPurchaseRefresh
local listingItemInfoAttempts, queryAttempts, requestItemInfoAttempts = 0, 0, 0
local searchListUpdated
local searchDeadline, transactionDeadline
local statusElapsed = 0
local highBidderNotices
local pendingVendorBidsByItem
local wasScannerBusy
local updateFrame = CreateFrame("Frame")

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

local function GetVendorCacheCounts()
	local scope = scanner:GetAuctionScope()
	local vendorList = scope and addon.db[scope].vendorList
	local numItems, numListings = 0, 0
	if vendorList then
		for _, vendorData in pairs(vendorList) do
			local itemListings = 0
			for _, auction in ipairs(vendorData.auctions) do
				local vendorReturn = vendorData.vendorSell * auction.count
				local bid = auction.unitBid and floor(auction.unitBid * auction.count + 0.5)
				local buyout = auction.unitBuyout and floor(auction.unitBuyout * auction.count + 0.5)
				if addon:IsVendorDealProfitable(bid, vendorReturn) or addon:IsVendorDealProfitable(buyout, vendorReturn) then
					itemListings = itemListings + (auction.numAuctions or 1)
				end
			end
			if itemListings > 0 then
				numItems = numItems + 1
				numListings = numListings + itemListings
			end
		end
	end
	return numItems, numListings
end

local function ShowCacheReady()
	local numItems, numListings = GetVendorCacheCounts()
	if numListings > 0 then
		SetStatus(format(L["Vendor cache ready: %d listings across %d items."], numListings, numItems))
	else
		SetStatus(L["Vendor cache ready: no candidate listings."])
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
	local name, _, count, _, _, _, _, minBid, minIncrement, buyout, bidAmount, highBidder, bidderFullName, owner, ownerFullName, _, itemID, hasAllInfo = GetAuctionItemInfo("list", index)
	-- Classic may publish AUCTION_ITEM_LIST_UPDATE before every result has resolved
	-- its item data. Advancing past such a row permanently skips a valid deal, so
	-- distinguish "not loaded yet" from a genuinely unusable auction record.
	if hasAllInfo == false then
		return nil, true, itemID
	end
	if not itemID or not count or count < 1 or not minBid or minBid < 1
		or not minIncrement or minIncrement < 0 or not bidAmount or bidAmount < 0
		or not buyout or buyout < 0 then
		return
	end

	local payableBid = bidAmount and bidAmount > 0 and bidAmount + minIncrement or minBid
	return {
		index = index,
		itemID = itemID,
		name = name,
		link = GetAuctionItemLink("list", index),
		count = count,
		minBid = minBid,
		payableBid = payableBid,
		buyout = buyout or 0,
		bidAmount = bidAmount,
		highBidder = highBidder,
		bidderFullName = bidderFullName,
		owner = owner,
		ownerFullName = ownerFullName,
	}
end

local function IsOwnHighBidder(listing)
	local pendingBids = pendingVendorBidsByItem and pendingVendorBidsByItem[listing.itemID]
	return saleCollector:IsClassicAccountHighBidder(listing, pendingBids)
end

local function MatchesRequest(listing, request)
	return listing.itemID == request.itemID
		and not addon:IsPlayerAuction(listing.owner, listing.ownerFullName)
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
	queue = nil
	highBidderNotices = nil
	pendingVendorBidsByItem = nil
	if actionButton then
		actionButton:SetText(L["Start Vendor Flips"])
		actionButton:Enable()
	end
	if restartButton then
		restartButton:Enable()
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

local function ResolveTransaction(succeeded, confirmedFailure)
	transactionPending = false
	if not running or not currentRequest then
		transactionDeadline = nil
		return
	end

	if succeeded then
		pendingPurchase = nil
		SetStatus(L["Auction action accepted; refreshing results."])
		-- Blizzard removes a purchased auction from the loaded page and shifts the
		-- following row into the same index. Resume there after the list-update event
		-- instead of issuing a fresh query and risking another throttle or timeout.
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
		-- A failed action does not consume the cached candidate. Search from the first
		-- page again because a competing bid or purchase may have reordered results.
		SetStatus(L["Auction action failed; refreshing results."])
		currentCandidate = nil
		currentPage = 0
		nextResultIndex = 1
		ScheduleSearch()
	end
end

function AdvanceRequest()
	currentCandidate = nil
	currentRequest = nil
	queueIndex = queueIndex + 1
	while queue and queueIndex <= #queue do
		local request = queue[queueIndex]
		local name = GetItemInfo(request.itemID)
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

	FinishSearch(L["Vendor flip search complete."])
end

function ContinueAfterCandidate(requery)
	currentCandidate = nil
	if requery then
		currentPage = 0
		nextResultIndex = 1
		ScheduleSearch()
	else
		-- Allow StaticPopup to finish hiding the current dialog before requesting
		-- another one from the same results page on the following frame.
		resumePage = true
	end
end

function module:ShowItemTooltip(owner, link, itemID)
	tooltip:ShowTooltip(owner, link, itemID, scanner:GetAuctionScope())
end

local function RevalidateCandidate(candidate, action)
	local listing = ReadListing(candidate.index)
	if not listing or listing.itemID ~= candidate.itemID or listing.count ~= candidate.count
		or listing.minBid ~= candidate.minBid or listing.buyout ~= candidate.buyout
		or candidate.owner and listing.owner and listing.owner ~= candidate.owner
		or candidate.ownerFullName and listing.ownerFullName and listing.ownerFullName ~= candidate.ownerFullName
		or addon:IsPlayerAuction(listing.owner, listing.ownerFullName) then
		return
	end

	local vendorReturn = candidate.vendorSell * listing.count
	-- A character on this account is already winning the auction. Buying it out
	-- would replace a potentially larger vendor profit with an unnecessary cost.
	if IsOwnHighBidder(listing) then
		return
	end
	if action == "bid" then
		-- At the buyout price, PlaceAuctionBid buys the listing instead of placing
		-- a conventional bid, so that action belongs exclusively to Buyout.
		if (listing.buyout > 0 and listing.payableBid >= listing.buyout)
			or not addon:IsVendorDealProfitable(listing.payableBid, vendorReturn) then
			return
		end
		return listing, listing.payableBid
	elseif listing.buyout > 0 and addon:IsVendorDealProfitable(listing.buyout, vendorReturn) then
		return listing, listing.buyout
	end
end

function module:ActOnCandidate(action, candidate)
	if not running or transactionPending or candidate ~= currentCandidate then
		return
	end

	local listing, price = RevalidateCandidate(candidate, action)
	if not listing then
		SetStatus(L["Vendor listing changed; searching again."])
		ContinueAfterCandidate(true)
		return
	end
	if GetMoney() < price then
		SetStatus(ERR_NOT_ENOUGH_MONEY)
		ContinueAfterCandidate(false)
		return
	end

	-- This call remains directly inside the popup button's hardware event. Blizzard
	-- rejects programmatic bids and buyouts which are not initiated by the player.
	-- Do not search again until Blizzard confirms success or reports failure; querying
	-- while the purchase is still pending can produce avoidable internal auction errors.
	transactionPending = true
	transactionListUpdated = false
	waitingForPurchaseRefresh = false
	transactionDeadline = GetTime() + TRANSACTION_TIMEOUT
	SetStatus(L["Waiting for the auction house..."])
	pendingPurchase = saleCollector:RecordPendingPurchase("list", listing.index, price, action, "vendor")
	PlaceAuctionBid("list", listing.index, price)
	saleCollector:ReleasePendingPurchaseHook(pendingPurchase)
end

function module:SkipCandidate(candidate)
	if running and candidate == currentCandidate then
		ContinueAfterCandidate(false)
	end
end

local function FormatProfit(profit)
	return addon:FormatMoney(profit, true, profit > 0 and GREEN_NUMBER or nil)
end

local function FormatLoss(loss)
	return addon:FormatMoney(-loss, true, RED_NUMBER)
end

local function ShowCandidate(listing)
	if not running or not currentRequest or not highBidderNotices then
		return false
	end

	-- Do not offer another action when the player or a known alt is already the
	-- high bidder. The account will receive the item unless somebody outbids it.
	if IsOwnHighBidder(listing) then
		if not highBidderNotices[listing.itemID] then
			highBidderNotices[listing.itemID] = true
			addon:Print(format(L["You are the high bidder on %s."], listing.link or currentRequest.name))
		end
		return false
	end
	-- An older pending bid may predate cached vendor data or may no longer be
	-- profitable. It is still queried so YAAHA can report that the account remains
	-- the high bidder, but no further action can be offered without a vendor value.
	if not currentRequest.vendorSell or currentRequest.vendorSell <= 0 then
		return false
	end

	local vendorReturn = currentRequest.vendorSell * listing.count
	local canBid = (listing.buyout <= 0 or listing.payableBid < listing.buyout)
		and addon:IsVendorDealProfitable(listing.payableBid, vendorReturn)
	local canBuy = listing.buyout > 0 and addon:IsVendorDealProfitable(listing.buyout, vendorReturn)
	if not canBid and not canBuy then
		return false
	end

	listing.vendorSell = currentRequest.vendorSell
	listing.canBid = canBid
	listing.canBuy = canBuy
	listing.bidProfit = canBid and vendorReturn - listing.payableBid or nil
	listing.buyProfit = canBuy and vendorReturn - listing.buyout or nil
	currentCandidate = listing

	local unavailable = "--"
	local bidText = addon:FormatMoney(listing.payableBid)
	if canBid then
		bidText = format(L["%s (%s profit)"], bidText, FormatProfit(listing.bidProfit))
	end
	local buyoutText = listing.buyout > 0 and addon:FormatMoney(listing.buyout) or unavailable
	if canBuy then
		buyoutText = format(L["%s (%s profit)"], buyoutText, FormatProfit(listing.buyProfit))
	elseif listing.buyout > 0 then
		buyoutText = format(L["%s (%s loss)"], buyoutText, FormatLoss(listing.buyout - vendorReturn))
	end
	local text = format(L["Vendor flip: %s x%d\nVendor return: %s\nBid: %s\nBuyout: %s"],
		listing.link or currentRequest.name, listing.count, addon:FormatMoney(vendorReturn),
		bidText, buyoutText)
	local popup = StaticPopup_Show(POPUP_NAME, text, nil, listing)
	if not popup then
		currentCandidate = nil
		return false
	end
	popup.yaahaItemID = listing.itemID
	popup.yaahaItemLink = listing.link
	if not popup.yaahaTooltipHooked then
		popup.yaahaTooltipHooked = true
		popup:SetHyperlinksEnabled(true)
		popup:HookScript("OnHyperlinkEnter", function(self, link)
			if self.yaahaItemID then
				module:ShowItemTooltip(self, link, self.yaahaItemID)
			end
		end)
		popup:HookScript("OnHyperlinkLeave", GameTooltip_Hide)
		popup:HookScript("OnHide", function(self)
			self.yaahaItemID = nil
			self.yaahaItemLink = nil
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
			-- Resume at this exact row rather than restarting or advancing the item
			-- request. A permanently incomplete row is retried only a bounded number
			-- of times, then skipped so it cannot stall the entire deal search.
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
		-- A missing auction is ambiguous: another buyer may have taken it, or our bid
		-- may have won and its invoice may not have reached the mailbox yet. Preserve
		-- pending bids until an invoice resolves them or their safety window expires.
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

local function BuildQueue(vendorList, scope)
	local requests = {}
	local requestsByItem = {}
	-- One exact-name query returns every live listing for an item. Keep only the
	-- strongest cached profit for ordering; expanding every cached price/stack shape
	-- into its own query needlessly multiplied throttle waits and repeated pages.
	for itemID, vendorData in pairs(vendorList or {}) do
		for _, auction in ipairs(vendorData.auctions) do
			local vendorReturn = vendorData.vendorSell * auction.count
			local bid = auction.unitBid and floor(auction.unitBid * auction.count + 0.5) or nil
			local buyout = auction.unitBuyout and floor(auction.unitBuyout * auction.count + 0.5) or 0
			local bestProfit
			if addon:IsVendorDealProfitable(bid, vendorReturn) then
				bestProfit = vendorReturn - bid
			end
			if addon:IsVendorDealProfitable(buyout, vendorReturn)
				and (not bestProfit or vendorReturn - buyout > bestProfit) then
				bestProfit = vendorReturn - buyout
			end
			if bestProfit then
				local request = requestsByItem[itemID]
				if request then
					if bestProfit > request.bestProfit then
						request.bestProfit = bestProfit
					end
				else
					request = {
						itemID = itemID,
						vendorSell = vendorData.vendorSell,
						bestProfit = bestProfit,
					}
					requestsByItem[itemID] = request
					requests[#requests + 1] = request
				end
			end
		end
	end

	-- Every known account bid protects its matching listing from an alt. The
	-- vendor-flip subset also survives cache rebuilds so its exact live listings
	-- can remain in this search's result queue. Records created before action
	-- tracking existed are not guessed to be bids rather than buyouts.
	local pendingBids = scope and saleCollector:GetPendingBids(scope, true) or {}
	pendingVendorBidsByItem = {}
	for _, purchase in ipairs(pendingBids) do
		local itemBids = pendingVendorBidsByItem[purchase.itemID]
		if not itemBids then
			itemBids = {}
			pendingVendorBidsByItem[purchase.itemID] = itemBids
		end
		itemBids[#itemBids + 1] = purchase

		if purchase.vendorFlip then
			local bestProfit = purchase.vendorSell
				and purchase.vendorSell * purchase.count - purchase.price or 0
			local request = requestsByItem[purchase.itemID]
			if request then
				request.vendorSell = request.vendorSell or purchase.vendorSell
				if bestProfit > request.bestProfit then
					request.bestProfit = bestProfit
				end
			else
				request = {
					itemID = purchase.itemID,
					vendorSell = purchase.vendorSell,
					bestProfit = bestProfit,
				}
				requestsByItem[purchase.itemID] = request
				requests[#requests + 1] = request
			end
		end
	end

	-- Showing the greatest possible profit first helps the player spend limited
	-- gold on the strongest opportunities without automating any purchase decision.
	sort(requests, SortByBestProfit)
	return requests
end

local function StopVendorFlips(message)
	StaticPopup_Hide(POPUP_NAME)
	FinishSearch(message or L["Vendor flip search stopped."])
end

local function StartVendorFlips()
	if running then
		StopVendorFlips()
		return
	elseif scanner:IsScanning() then
		SetStatus(dataProcessing:IsProcessing() and L["Processing scan data..."]
			or L["Waiting for auction scan results..."])
		return
	end

	local scope = scanner:GetAuctionScope()
	local vendorList = scope and addon.db[scope].vendorList
	queue = BuildQueue(vendorList, scope)
	if #queue == 0 then
		local scanStats = scope and addon.db[scope].auctionStats
		if not scanStats or not scanStats.lastScan then
			SetStatus(L["No cached vendor deals are available. Scan this auction house first."])
		else
			SetStatus(L["No profitable vendor deals remain."])
		end
		return
	end

	module:SendMessage("YAAHA_DEAL_SEARCH_STARTED", "vendor")
	-- A new run always begins from a clean cursor. Most of these fields are also
	-- cleared when a run finishes, but resetting them here makes Start independent
	-- from how the preceding run ended (completion, timeout, stop, or AH closure).
	running = true
	highBidderNotices = {}
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
	actionButton:SetText(L["Stop Vendor Flips"])
	SetStatus(L["Searching cached vendor deals..."])
	AdvanceRequest()
end

local function RestartVendorFlips()
	if running then
		StopVendorFlips()
	end
	StartVendorFlips()
end

local function CreateInterface()
	local page = auctionHouseUI:GetPage("deals")
	if not page or actionButton then
		return
	end

	actionButton = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	actionButton:SetSize(150, 24)
	actionButton:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -14)
	actionButton:SetText(L["Start Vendor Flips"])
	actionButton:SetScript("OnClick", StartVendorFlips)

	restartButton = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	restartButton:SetSize(150, 24)
	restartButton:SetPoint("LEFT", actionButton, "RIGHT", 8, 0)
	restartButton:SetText(L["Restart Vendor Flips"])
	restartButton:SetScript("OnClick", RestartVendorFlips)

	statusText = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	statusText:SetPoint("TOPLEFT", actionButton, "BOTTOMLEFT", 0, -10)
	statusText:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -48)
	statusText:SetJustifyH("LEFT")
	statusText:SetText("")
end

StaticPopupDialogs[POPUP_NAME] = {
	text = "%s",
	button1 = BID,
	button2 = BUYOUT,
	button3 = RENOWN_LEVEL_UP_SKIP_BUTTON,
	selectCallbackByIndex = true,
	OnButton1 = function(_, data)
		module:ActOnCandidate("bid", data)
	end,
	OnButton2 = function(_, data)
		module:ActOnCandidate("buy", data)
	end,
	OnButton3 = function(_, data)
		module:SkipCandidate(data)
	end,
	DisplayButton1 = function(_, data)
		return data and data.canBid
	end,
	DisplayButton2 = function(_, data)
		return data and data.canBuy
	end,
	timeout = 0,
	whileDead = false,
	hideOnEscape = false,
}

function module:OnEnable()
	self:RegisterEvent("AUCTION_HOUSE_SHOW")
	self:RegisterEvent("AUCTION_HOUSE_CLOSED")
	self:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
	self:RegisterEvent("CHAT_MSG_SYSTEM")
	self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	self:RegisterEvent("UI_ERROR_MESSAGE")
	self:RegisterMessage("YAAHA_VENDOR_CACHE_READY")
	self:RegisterMessage("YAAHA_DEAL_SEARCH_STARTED")
	updateFrame:SetScript("OnUpdate", function(_, elapsed)
		statusElapsed = statusElapsed + elapsed
		if statusElapsed >= 0.2 then
			statusElapsed = 0
			local scannerBusy = scanner:IsScanning()
			if scannerBusy then
				if running then
					StopVendorFlips(L["Vendor flip search stopped for auction processing."])
				end
				actionButton:Disable()
				restartButton:Disable()
				if dataProcessing:IsProcessing() then
					local processed, total = dataProcessing:GetProgress()
					SetStatus(format(L["Building deal caches: %d/%d steps."], processed, total))
				else
					SetStatus(L["Waiting for auction scan results..."])
				end
			elseif wasScannerBusy then
				actionButton:Enable()
				restartButton:Enable()
				ShowCacheReady()
			end
			wasScannerBusy = scannerBusy
		end

		if running and transactionPending and GetTime() >= transactionDeadline then
			ResolveTransaction(false, false)
		elseif running and waitingForPurchaseRefresh and GetTime() >= transactionDeadline then
			-- If Classic never publishes the post-purchase refresh, recover with a
			-- focused query rather than leaving the workflow stalled.
			waitingForPurchaseRefresh = false
			transactionDeadline = nil
			currentPage = 0
			nextResultIndex = 1
			ScheduleSearch()
		elseif running and resumePage then
			resumePage = false
			self:ProcessCurrentPage()
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
				-- A throttle is not proof that the candidate is gone. Keep waiting for
				-- permission rather than silently skipping it.
				ScheduleSearch()
			end
		elseif running and waitingForItemInfo and GetTime() >= searchDeadline then
			RetryOrSkipPendingListing()
		elseif running and waitingForResults and GetTime() >= searchDeadline then
			waitingForResults = false
			if queryAttempts < QUERY_RETRY_LIMIT then
				ScheduleSearch()
			else
				SetStatus(L["Vendor search timed out; continuing."])
				AdvanceRequest()
			end
		end
	end)
end

function module:YAAHA_DEAL_SEARCH_STARTED(_, dealType)
	if running and dealType ~= "vendor" then
		StopVendorFlips()
	end
end

function module:YAAHA_VENDOR_CACHE_READY(_, scope)
	-- The scan processor commits the replacement cache before sending this message.
	-- Update the active auction house immediately so the first click is actionable.
	if scope ~= scanner:GetAuctionScope() or not actionButton then
		return
	end

	wasScannerBusy = false
	actionButton:Enable()
	restartButton:Enable()
	ShowCacheReady()
end

function module:AUCTION_HOUSE_SHOW()
	CreateInterface()
	wasScannerBusy = scanner:IsScanning()
	if wasScannerBusy then
		actionButton:Disable()
		restartButton:Disable()
	else
		ShowCacheReady()
	end
end

function module:AUCTION_HOUSE_CLOSED()
	if running then
		StopVendorFlips()
	end
end

function module:AUCTION_ITEM_LIST_UPDATE()
	if running and transactionPending then
		-- The list refresh can arrive before the chat confirmation. Remember it so
		-- ResolveTransaction can continue immediately once success is confirmed.
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
		-- AUCTION_ITEM_LIST_UPDATE has no query identifier and can also be fired by
		-- sorting or another addon's search. Auctioneer likewise waits for both this
		-- event and query-throttle readiness before treating the result page as final.
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
		local name = GetItemInfo(itemID)
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