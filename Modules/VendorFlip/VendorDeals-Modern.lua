-- Finds Modern noncommodity listings or arbitrary commodity quantities whose
-- purchase cost does not exceed their NPC value under the break-even policy.

local BID = BID
local BUYOUT = BUYOUT
local CANCEL = CANCEL
local AUCTION_HOUSE_BUY_BUTTON = AUCTION_HOUSE_BUY_BUTTON
local C_AuctionHouse = C_AuctionHouse
local C_Item = C_Item
local CreateFrame = CreateFrame
local ERR_AUCTION_BID_PLACED = ERR_AUCTION_BID_PLACED
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
local module = addon:NewModule("VendorDeals", "AceEvent-3.0")
local auctionHouseUI = addon:GetModule("AuctionHouseUI")
local dataProcessing = addon:GetModule("DataProcessing")
local scanner = addon:GetModule("Scanner")
local saleCollector = addon:GetModule("SaleCollector")
local tooltip = addon:GetModule("Tooltip")
local L = LibStub("AceLocale-3.0"):GetLocale("YAAHA")

local ITEM_POPUP_NAME = "YAAHA_VENDOR_FLIP_MODERN_ITEM"
local COMMODITY_POPUP_NAME = "YAAHA_VENDOR_FLIP_MODERN_COMMODITY"
local COMMODITY_QUOTE_POPUP_NAME = "YAAHA_VENDOR_FLIP_MODERN_COMMODITY_QUOTE"
local QUERY_RETRY_LIMIT = 3
local QUERY_TIMEOUT = 10
local TRANSACTION_TIMEOUT = 10
local AUCTION_MINIMUM_PRICE = addon.auctionHouseMinimumPrice
local GREEN_NUMBER = addon.positiveNumberColor
local RED_NUMBER = addon.negativeNumberColor
local PRICE_SORT = {
	{
		sortOrder = Enum.AuctionHouseSortOrder.Price,
		reverseSort = false,
	},
}

local actionButton, restartButton, statusText
local currentCandidate, currentRequest, pendingCommodityQuote
local pendingPurchase
local queue, queueIndex
local running, resumeResults, searchPending, transactionPending
local waitingForInitialResults, waitingForItemInfo, waitingForMoreResults, waitingForQuote
local queryAttempts, itemInfoAttempts = 0, 0
local nextResultIndex = 1
local searchDeadline, transactionDeadline
local statusElapsed = 0
local pendingVendorBidsByAuction
local wasScannerBusy
local updateFrame = CreateFrame("Frame")
local AdvanceRequest, ContinueAfterCandidate, ContinueResultsLoading, ScheduleSearch

local function SortByBestProfit(left, right)
	return left.bestProfit > right.bestProfit
end

local function SetStatus(text)
	if statusText then
		statusText:SetText(text)
	end
end

local function FormatProfit(profit)
	return addon:FormatMoney(profit, true, profit > 0 and GREEN_NUMBER or nil)
end

local function FormatLoss(loss)
	return addon:FormatMoney(-loss, true, RED_NUMBER)
end

local function ItemKeysEqual(left, right)
	return left and right
		and left.itemID == right.itemID
		and left.itemLevel == right.itemLevel
		and left.itemSuffix == right.itemSuffix
		and left.battlePetSpeciesID == right.battlePetSpeciesID
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
				local profitableBid = bid and bid >= AUCTION_MINIMUM_PRICE
					and addon:IsVendorDealProfitable(bid, vendorReturn)
				local profitableBuyout = buyout and buyout >= AUCTION_MINIMUM_PRICE
					and addon:IsVendorDealProfitable(buyout, vendorReturn)
				if profitableBid or profitableBuyout then
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
	CancelCommodityQuote()
	running = false
	resumeResults = false
	transactionPending = false
	waitingForItemInfo = false
	itemInfoAttempts = 0
	transactionDeadline = nil
	currentCandidate = nil
	currentRequest = nil
	pendingPurchase = nil
	pendingVendorBidsByAuction = nil
	queue = nil
	ResetSearchState()
	if actionButton then
		actionButton:SetText(L["Start Vendor Flips"])
		actionButton:Enable()
	end
	if restartButton then
		restartButton:Enable()
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
		return
	end
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
		FinishSearch(L["Vendor flip search complete."])
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
		-- Let the current dialog finish hiding before displaying another result.
		resumeResults = true
	end
end

local function BuildQueue(vendorList)
	local requests = {}
	local requestsByItem = {}
	for itemID, vendorData in pairs(vendorList or {}) do
		local bestProfit
		for _, auction in ipairs(vendorData.auctions) do
			local vendorReturn = vendorData.vendorSell * auction.count
			local bid = auction.unitBid and floor(auction.unitBid * auction.count + 0.5)
			local buyout = auction.unitBuyout and floor(auction.unitBuyout * auction.count + 0.5)
			if bid and bid >= AUCTION_MINIMUM_PRICE and addon:IsVendorDealProfitable(bid, vendorReturn) then
				bestProfit = max(bestProfit or 0, vendorReturn - bid)
			end
			if buyout and buyout >= AUCTION_MINIMUM_PRICE
				and addon:IsVendorDealProfitable(buyout, vendorReturn) then
				bestProfit = max(bestProfit or 0, vendorReturn - buyout)
			end
		end
		if bestProfit then
			local request = {
				itemID = itemID,
				vendorSell = vendorData.vendorSell,
				bestProfit = bestProfit,
			}
			requestsByItem[itemID] = request
			requests[#requests + 1] = request
		end
	end

	-- Modern auction IDs remain stable for the life of a listing, while bidder
	-- GUIDs need not survive logout. Preserve account-wide bid protection by
	-- matching that ID and the exact live bid amount instead of persisting a GUID.
	pendingVendorBidsByAuction = {}
	local scope = scanner:GetAuctionScope()
	for _, purchase in ipairs(scope and saleCollector:GetPendingBids(scope, true) or {}) do
		-- Older Classic records have no auctionID and cannot identify a Modern
		-- listing safely. Leave them to normal expiry rather than guessing.
		if purchase.auctionID then
			local bids = pendingVendorBidsByAuction[purchase.auctionID]
			if not bids then
				bids = {}
				pendingVendorBidsByAuction[purchase.auctionID] = bids
			end
			bids[#bids + 1] = purchase

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
	end
	sort(requests, SortByBestProfit)
	return requests
end

local function GetCommodityPurchase(itemID, vendorSell, requestedQuantity)
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
				-- Results are price-sorted. Once a tier is not a vendor deal, every
				-- later tier is also too expensive.
				if not addon:IsVendorDealProfitable(result.unitPrice, vendorSell) then
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
	local pendingBids = pendingVendorBidsByAuction
		and pendingVendorBidsByAuction[result.auctionID]
	return saleCollector:IsModernAccountHighBidder(
		result, currentRequest.itemID, pendingBids)
end

local function RevalidateItemCandidate(candidate, action)
	local result = FindItemResult(candidate.auctionID)
	if not result or IsOwnItemResult(result) then
		return
	end
	local minBid = result.minBid
	local buyout = result.buyoutAmount
	if action == "bid" then
		-- Modern minBid is already the next required bid. It does not need the
		-- Classic bid increment added a second time.
		if not minBid or minBid < AUCTION_MINIMUM_PRICE
			or buyout and minBid >= buyout
			or not addon:IsVendorDealProfitable(minBid, candidate.vendorSell) then
			return
		end
		return result, minBid
	elseif buyout and buyout >= AUCTION_MINIMUM_PRICE
		and addon:IsVendorDealProfitable(buyout, candidate.vendorSell) then
		return result, buyout
	end
end

local function OnPopupHyperlinkEnter(popup, link)
	if popup.yaahaItemID then
		module:ShowItemTooltip(popup, link, popup.yaahaItemID)
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
	local minBid = result.minBid
	local buyout = result.buyoutAmount
	local vendorReturn = currentRequest.vendorSell
	local canBid = minBid and minBid >= AUCTION_MINIMUM_PRICE
		and (not buyout or minBid < buyout)
		and addon:IsVendorDealProfitable(minBid, vendorReturn) or false
	local canBuy = buyout and buyout >= AUCTION_MINIMUM_PRICE
		and addon:IsVendorDealProfitable(buyout, vendorReturn) or false
	if not canBid and not canBuy then
		return false
	end

	local candidate = {
		auctionID = result.auctionID,
		canBid = canBid,
		canBuy = canBuy,
		itemID = currentRequest.itemID,
		kind = "item",
		link = result.itemLink,
		name = currentRequest.name,
		vendorSell = vendorReturn,
	}
	currentCandidate = candidate
	local unavailable = "--"
	local bidText = minBid and addon:FormatMoney(minBid) or unavailable
	if canBid then
		bidText = format(L["%s (%s profit)"], bidText, FormatProfit(vendorReturn - minBid))
	elseif minBid then
		bidText = format(L["%s (%s loss)"], bidText, FormatLoss(minBid - vendorReturn))
	end
	local buyoutText = buyout and addon:FormatMoney(buyout) or unavailable
	if canBuy then
		buyoutText = format(L["%s (%s profit)"], buyoutText, FormatProfit(vendorReturn - buyout))
	elseif buyout then
		buyoutText = format(L["%s (%s loss)"], buyoutText, FormatLoss(buyout - vendorReturn))
	end
	local text = format(L["Vendor flip: %s x%d\nVendor return: %s\nBid: %s\nBuyout: %s"],
		candidate.link or candidate.name, 1, addon:FormatMoney(vendorReturn), bidText, buyoutText)
	local popup = StaticPopup_Show(ITEM_POPUP_NAME, text, nil, candidate)
	if not popup then
		currentCandidate = nil
		return false
	end
	AttachPopupTooltip(popup, candidate.itemID)
	return true
end

local function ShowCommodityCandidate()
	local maxQuantity = GetCommodityPurchase(currentRequest.itemID, currentRequest.vendorSell)
	if not maxQuantity or maxQuantity < 1 then
		return false
	end
	local candidate = {
		itemID = currentRequest.itemID,
		kind = "commodity",
		maxQuantity = maxQuantity,
		name = currentRequest.name,
		vendorSell = currentRequest.vendorSell,
	}
	currentCandidate = candidate
	local text = format(L["Vendor commodity: %s\nVendor return per item: %s\nMaximum affordable deal quantity: %d\nEnter purchase quantity:"],
		candidate.name, addon:FormatMoney(candidate.vendorSell), candidate.maxQuantity)
	local popup = StaticPopup_Show(COMMODITY_POPUP_NAME, text, nil, candidate)
	if not popup then
		currentCandidate = nil
		return false
	end
	return true
end

function module:ShowItemTooltip(owner, link, itemID)
	tooltip:ShowTooltip(owner, link, itemID, scanner:GetAuctionScope())
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
		SetStatus(L["Vendor search timed out; continuing."])
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
	SetStatus(succeeded and L["Auction action accepted; refreshing results."]
		or L["Auction action failed; refreshing results."])
	currentCandidate = nil
	nextResultIndex = 1
	queryAttempts = 0
	ScheduleSearch()
end

function module:ActOnItemCandidate(action, candidate)
	if not running or transactionPending or candidate ~= currentCandidate then
		return
	end
	local result, price = RevalidateItemCandidate(candidate, action)
	if not result then
		SetStatus(L["Vendor listing changed; searching again."])
		ContinueAfterCandidate(true)
		return
	end
	if GetMoney() < price then
		SetStatus(ERR_NOT_ENOUGH_MONEY)
		ContinueAfterCandidate(false)
		return
	end
	-- PlaceBid handles both modern bids and noncommodity buyouts and must remain
	-- directly in this popup click so Blizzard sees the player's hardware event.
	transactionPending = true
	transactionDeadline = GetTime() + TRANSACTION_TIMEOUT
	SetStatus(L["Waiting for the auction house..."])
	pendingPurchase = saleCollector:RecordModernPendingPurchase(
		result.auctionID, price, action, "vendor", result)
	C_AuctionHouse.PlaceBid(result.auctionID, price)
	saleCollector:ReleaseModernPendingPurchaseHook(pendingPurchase)
end

function module:StartCommodityQuote(candidate, quantity)
	if not running or transactionPending or waitingForQuote or candidate ~= currentCandidate then
		return
	end
	local availableQuantity, totalCost = GetCommodityPurchase(candidate.itemID, candidate.vendorSell, quantity)
	if not availableQuantity or availableQuantity ~= quantity or not totalCost then
		SetStatus(L["Vendor listing changed; searching again."])
		ContinueAfterCandidate(true)
		return
	end
	pendingCommodityQuote = {
		itemID = candidate.itemID,
		name = candidate.name,
		quantity = quantity,
		vendorSell = candidate.vendorSell,
	}
	waitingForQuote = true
	transactionDeadline = GetTime() + TRANSACTION_TIMEOUT
	SetStatus(L["Waiting for the auction house..."])
	-- The quote must begin inside the quantity dialog's hardware click. Its returned
	-- total is revalidated before YAAHA offers the protected confirmation action.
	C_AuctionHouse.StartCommoditiesPurchase(candidate.itemID, quantity)
end

function module:ConfirmCommodityPurchase(quote)
	if not running or transactionPending or quote ~= pendingCommodityQuote
		or not quote.totalPrice
		or not addon:IsVendorDealProfitable(quote.totalPrice, quote.vendorSell * quote.quantity) then
		CancelCommodityQuote()
		SetStatus(L["Commodity price changed; searching again."])
		ContinueAfterCandidate(true)
		return
	end
	if C_AuctionHouse.GetQuoteDurationRemaining() <= 0 then
		CancelCommodityQuote()
		SetStatus(L["Commodity quote expired; searching again."])
		ContinueAfterCandidate(true)
		return
	end
	if GetMoney() < quote.totalPrice then
		CancelCommodityQuote()
		SetStatus(ERR_NOT_ENOUGH_MONEY)
		ContinueAfterCandidate(false)
		return
	end
	-- Confirmation is a second protected action, so it stays in this second popup click.
	waitingForQuote = false
	transactionPending = true
	transactionDeadline = GetTime() + TRANSACTION_TIMEOUT
	SetStatus(L["Waiting for the auction house..."])
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
	if not unitPrice or unitPrice < AUCTION_MINIMUM_PRICE or not totalPrice
		or not addon:IsVendorDealProfitable(totalPrice, quote.vendorSell * quote.quantity) then
		CancelCommodityQuote()
		SetStatus(L["Commodity price changed; searching again."])
		ContinueAfterCandidate(true)
		return
	end
	quote.totalPrice = totalPrice
	local vendorReturn = quote.vendorSell * quote.quantity
	local text = format(L["Vendor commodity: %s x%d\nVendor return: %s\nPurchase price: %s\nExpected profit: %s"],
		quote.name, quote.quantity, addon:FormatMoney(vendorReturn), addon:FormatMoney(totalPrice),
		FormatProfit(vendorReturn - totalPrice))
	if not StaticPopup_Show(COMMODITY_QUOTE_POPUP_NAME, text, nil, quote) then
		CancelCommodityQuote()
		ContinueAfterCandidate(true)
	end
end

local function StopVendorFlips(message)
	StaticPopup_Hide(ITEM_POPUP_NAME)
	StaticPopup_Hide(COMMODITY_POPUP_NAME)
	StaticPopup_Hide(COMMODITY_QUOTE_POPUP_NAME)
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
	queue = BuildQueue(vendorList)
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
	local availableQuantity, totalCost = GetCommodityPurchase(candidate.itemID, candidate.vendorSell, quantity)
	if not availableQuantity or availableQuantity ~= quantity or not totalCost then
		totals:SetText(format(L["Total cost: %s\nExpected profit: %s"], "--", "--"))
		dialog:GetButton1():Disable()
		return
	end
	local profit = candidate.vendorSell * quantity - totalCost
	totals:SetText(format(L["Total cost: %s\nExpected profit: %s"],
		addon:FormatMoney(totalCost), FormatProfit(profit)))
	dialog:GetButton1():Enable()
end

StaticPopupDialogs[ITEM_POPUP_NAME] = {
	text = "%s",
	button1 = BID,
	button2 = BUYOUT,
	button3 = RENOWN_LEVEL_UP_SKIP_BUTTON,
	selectCallbackByIndex = true,
	OnButton1 = function(_, data)
		module:ActOnItemCandidate("bid", data)
	end,
	OnButton2 = function(_, data)
		module:ActOnItemCandidate("buy", data)
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
				StopVendorFlips(L["Vendor flip search stopped for auction processing."])
			end
			if actionButton then
				actionButton:Disable()
				restartButton:Disable()
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
				restartButton:Enable()
			end
			ShowCacheReady()
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
			SetStatus(L["Commodity purchase failed; searching again."])
			ContinueAfterCandidate(true)
		else
			ResolveItemTransaction(false)
		end
	elseif waitingForQuote and GetTime() >= transactionDeadline then
		CancelCommodityQuote()
		SetStatus(L["Commodity quote expired; searching again."])
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
	self:RegisterEvent("BID_ADDED")
	self:RegisterEvent("BIDS_UPDATED")
	self:RegisterEvent("CHAT_MSG_SYSTEM")
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
	self:RegisterMessage("YAAHA_VENDOR_CACHE_READY")
	self:RegisterMessage("YAAHA_DEAL_SEARCH_STARTED")
	updateFrame:SetScript("OnUpdate", OnUpdate)
end

function module:YAAHA_DEAL_SEARCH_STARTED(_, dealType)
	if running and dealType ~= "vendor" then
		StopVendorFlips()
	end
end

function module:YAAHA_VENDOR_CACHE_READY(_, scope)
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
	if not actionButton then
		return
	elseif wasScannerBusy then
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

function module:BID_ADDED()
	if transactionPending and currentCandidate and currentCandidate.kind == "item" then
		ResolveItemTransaction(true, false)
	end
end

function module:BIDS_UPDATED()
	if transactionPending and currentCandidate and currentCandidate.kind == "item" then
		ResolveItemTransaction(true, false)
	end
end

function module:CHAT_MSG_SYSTEM(_, message)
	if transactionPending and currentCandidate and currentCandidate.kind == "item"
		and message == ERR_AUCTION_BID_PLACED then
		ResolveItemTransaction(true, false)
	end
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
		SetStatus(L["Commodity purchase failed; searching again."])
		ContinueAfterCandidate(true)
	elseif transactionPending then
		ResolveItemTransaction(false, true)
	elseif waitingForQuote then
		CancelCommodityQuote()
		SetStatus(L["Commodity price changed; searching again."])
		ContinueAfterCandidate(true)
	end
end

function module:COMMODITY_PRICE_UPDATED(_, unitPrice, totalPrice)
	ShowCommodityQuote(unitPrice, totalPrice)
end

function module:COMMODITY_PRICE_UNAVAILABLE()
	if waitingForQuote then
		CancelCommodityQuote()
		SetStatus(L["Commodity price changed; searching again."])
		ContinueAfterCandidate(true)
	end
end

function module:COMMODITY_PURCHASE_SUCCEEDED()
	if transactionPending and pendingCommodityQuote then
		pendingCommodityQuote = nil
		transactionPending = false
		transactionDeadline = nil
		SetStatus(L["Auction action accepted; refreshing results."])
		ContinueAfterCandidate(true)
	end
end

function module:COMMODITY_PURCHASE_FAILED()
	if transactionPending and pendingCommodityQuote then
		pendingCommodityQuote = nil
		transactionPending = false
		transactionDeadline = nil
		SetStatus(L["Commodity purchase failed; searching again."])
		ContinueAfterCandidate(true)
	end
end