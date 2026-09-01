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
local LE_GAME_ERR_AUCTION_BID_OWN = LE_GAME_ERR_AUCTION_BID_OWN
local LE_GAME_ERR_AUCTION_DATABASE_ERROR = LE_GAME_ERR_AUCTION_DATABASE_ERROR
local LE_GAME_ERR_AUCTION_HIGHER_BID = LE_GAME_ERR_AUCTION_HIGHER_BID
local LE_GAME_ERR_ITEM_MAX_COUNT = LE_GAME_ERR_ITEM_MAX_COUNT
local LE_GAME_ERR_ITEM_NOT_FOUND = LE_GAME_ERR_ITEM_NOT_FOUND
local LE_GAME_ERR_NOT_ENOUGH_MONEY = LE_GAME_ERR_NOT_ENOUGH_MONEY
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
local module = addon:NewModule("VendorDeals", "AceEvent-3.0")
local auctionHouseUI = addon:GetModule("AuctionHouseUI")
local dataProcessing = addon:GetModule("DataProcessing")
local scanner = addon:GetModule("Scanner")
local saleCollector = addon:GetModule("SaleCollector")
local tooltip = addon:GetModule("Tooltip")
local L = LibStub("AceLocale-3.0"):GetLocale("YAAHA")

local POPUP_NAME = "YAAHA_VENDOR_FLIP"
local QUERY_TIMEOUT = 10
local RESULTS_PER_PAGE = 50
local TRANSACTION_TIMEOUT = 10
local GREEN_NUMBER = "|cff20ff20"
local RED_NUMBER = "|cffff2020"

local actionButton, restartButton, statusText
local ContinueAfterCandidate
local currentCandidate, currentPage, currentRequest, nextResultIndex
local pendingPurchase
local queue, queueIndex
local running, searchPending, transactionPending, waitingForItemInfo, waitingForResults
local resumePage
local searchDeadline, transactionDeadline
local statusElapsed = 0
local highBidderNotices
local wasScannerBusy
local updateFrame = CreateFrame("Frame")

local playerName, playerRealm = UnitFullName("player")
local playerFullName = playerRealm and playerRealm ~= "" and playerName .. "-" .. playerRealm or playerName

local function IsProfitable(price, vendorReturn)
	if not price or price <= 0 then
		return false
	end

	if addon.db.profile.includeBreakEvenVendorFlips then
		return price <= vendorReturn
	end
	return price < vendorReturn
end

local function SetStatus(text)
	if statusText then
		statusText:SetText(text)
	end
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
				if IsProfitable(bid, vendorReturn) or IsProfitable(buyout, vendorReturn) then
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
	waitingForItemInfo = false
	waitingForResults = false
	searchDeadline = GetTime() + QUERY_TIMEOUT
end

local function IsPlayerAuction(owner, ownerFullName)
	return owner == playerName or owner == playerFullName or ownerFullName == playerFullName
end

local function ReadListing(index)
	local _, _, count, _, _, _, _, minBid, minIncrement, buyout, bidAmount, highBidder, bidderFullName, owner, ownerFullName, _, itemID, hasAllInfo = GetAuctionItemInfo("list", index)
	-- Classic may publish AUCTION_ITEM_LIST_UPDATE before every result has resolved
	-- its item data. Advancing past such a row permanently skips a valid deal, so
	-- distinguish "not loaded yet" from a genuinely unusable auction record.
	if hasAllInfo == false then
		return nil, true
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
		link = GetAuctionItemLink("list", index),
		count = count,
		minBid = minBid,
		payableBid = payableBid,
		buyout = buyout or 0,
		highBidder = highBidder,
		bidderFullName = bidderFullName,
		owner = owner,
		ownerFullName = ownerFullName,
	}
end

local function IsOwnHighBidder(listing)
	local highBidder = listing.bidderFullName or listing.highBidder
	if highBidder == true then
		-- Some Classic clients expose this return as a boolean meaning the player is
		-- currently winning rather than exposing the bidder's name.
		return true
	end
	return highBidder and addon.db.global.alts[highBidder] or false
end

local function MatchesRequest(listing, request)
	if listing.itemID ~= request.itemID or listing.count ~= request.count then
		return false
	end
	-- The payable bid is intentionally not compared with the cached value. Another
	-- bidder may have raised it since the scan; live profitability is checked before
	-- the popup and again when its Bid button is clicked.
	if request.buyout and listing.buyout ~= request.buyout then
		return false
	end
	if request.seller then
		local listingSeller = listing.ownerFullName
			or listing.owner and playerRealm and listing.owner .. "-" .. playerRealm
			or listing.owner
		if listingSeller ~= request.seller and listing.owner ~= request.seller then
			return false
		end
	end
	return not IsPlayerAuction(listing.owner, listing.ownerFullName)
end

local function FinishSearch(message)
	running = false
	searchPending = false
	transactionPending = false
	waitingForItemInfo = false
	waitingForResults = false
	resumePage = false
	searchDeadline = nil
	transactionDeadline = nil
	currentCandidate = nil
	currentRequest = nil
	queue = nil
	highBidderNotices = nil
	if actionButton then
		actionButton:SetText(L["Start Vendor Flips"])
		actionButton:Enable()
	end
	if restartButton then
		restartButton:Enable()
	end
	SetStatus(message)
end

local function ResolveTransaction(succeeded, confirmedFailure)
	transactionPending = false
	transactionDeadline = nil
	if not running or not currentRequest then
		return
	end

	if succeeded then
		pendingPurchase = nil
		SetStatus(L["Auction action accepted; refreshing results."])
		ContinueAfterCandidate(true)
	else
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

local function IsAuctionActionError(errorType)
	return errorType == LE_GAME_ERR_AUCTION_BID_OWN
		or errorType == LE_GAME_ERR_AUCTION_DATABASE_ERROR
		or errorType == LE_GAME_ERR_AUCTION_HIGHER_BID
		or errorType == LE_GAME_ERR_ITEM_MAX_COUNT
		or errorType == LE_GAME_ERR_ITEM_NOT_FOUND
		or errorType == LE_GAME_ERR_NOT_ENOUGH_MONEY
end

local function AdvanceRequest()
	currentCandidate = nil
	currentRequest = nil
	queueIndex = queueIndex + 1
	while queue and queueIndex <= #queue do
		local request = queue[queueIndex]
		if request.remaining > 0 then
			local name = GetItemInfo(request.itemID)
			if name then
				request.name = name
				currentRequest = request
				currentPage = 0
				nextResultIndex = 1
				ScheduleSearch()
				return
			end
		end
		queueIndex = queueIndex + 1
	end

	FinishSearch(L["Vendor flip search complete."])
end

function ContinueAfterCandidate(requery)
	currentCandidate = nil
	currentRequest.remaining = currentRequest.remaining - 1
	if currentRequest.remaining <= 0 then
		AdvanceRequest()
	elseif requery then
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
		or IsPlayerAuction(listing.owner, listing.ownerFullName) then
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
			or not IsProfitable(listing.payableBid, vendorReturn) then
			return
		end
		return listing, listing.payableBid
	elseif listing.buyout > 0 and IsProfitable(listing.buyout, vendorReturn) then
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
	transactionDeadline = GetTime() + TRANSACTION_TIMEOUT
	SetStatus(L["Waiting for the auction house..."])
	pendingPurchase = saleCollector:RecordPendingPurchase("list", listing.index, price, action)
	PlaceAuctionBid("list", listing.index, price)
end

function module:SkipCandidate(candidate)
	if running and candidate == currentCandidate then
		ContinueAfterCandidate(false)
	end
end

local function ShowCandidate(listing)
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
		and IsProfitable(listing.payableBid, vendorReturn)
	local canBuy = listing.buyout > 0 and IsProfitable(listing.buyout, vendorReturn)
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
	local function FormatProfit(profit)
		return addon:FormatMoney(profit, true, profit > 0 and GREEN_NUMBER or nil)
	end
	local function FormatLoss(loss)
		return addon:FormatMoney(-loss, true, RED_NUMBER)
	end
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
		local listing, itemInfoPending = ReadListing(index)
		if itemInfoPending then
			-- Resume at this exact row rather than restarting or advancing the item
			-- request. GET_ITEM_INFO_RECEIVED normally wakes us; the existing query
			-- deadline remains a safety net if the client never supplies the record.
			nextResultIndex = index
			waitingForItemInfo = true
			searchDeadline = GetTime() + QUERY_TIMEOUT
			return
		end
		if listing and MatchesRequest(listing, currentRequest) then
			currentRequest.foundListing = true
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

local function BuildQueue(vendorList, scope)
	local requests = {}
	for itemID, vendorData in pairs(vendorList or {}) do
		for _, auction in ipairs(vendorData.auctions) do
			local vendorReturn = vendorData.vendorSell * auction.count
			local bid = auction.unitBid and floor(auction.unitBid * auction.count + 0.5) or nil
			local buyout = auction.unitBuyout and floor(auction.unitBuyout * auction.count + 0.5) or 0
			local bestProfit
			if IsProfitable(bid, vendorReturn) then
				bestProfit = vendorReturn - bid
			end
			if IsProfitable(buyout, vendorReturn) and (not bestProfit or vendorReturn - buyout > bestProfit) then
				bestProfit = vendorReturn - buyout
			end
			if bestProfit then
				requests[#requests + 1] = {
					itemID = itemID,
					count = auction.count,
					bid = bid,
					buyout = buyout,
					vendorSell = vendorData.vendorSell,
					remaining = auction.numAuctions or 1,
					bestProfit = bestProfit,
				}
			end
		end
	end

	-- Pending vendor-flip bids survive cache rebuilds. Querying their exact live
	-- listings ensures the high-bidder feedback covers earlier runs as well as the
	-- current vendor cache. Records created before this tracking existed have no
	-- action and are intentionally not guessed to be bids rather than buyouts.
	for _, purchase in ipairs(saleCollector:GetPendingVendorBids(scope)) do
		requests[#requests + 1] = {
			itemID = purchase.itemID,
			count = purchase.count,
			buyout = purchase.buyout,
			seller = purchase.seller,
			vendorSell = purchase.vendorSell,
			remaining = 1,
			bestProfit = purchase.vendorSell and purchase.vendorSell * purchase.count - purchase.price or 0,
			pendingPurchase = purchase,
		}
	end

	-- Showing the greatest possible profit first helps the player spend limited
	-- gold on the strongest opportunities without automating any purchase decision.
	sort(requests, function(left, right)
		return left.bestProfit > right.bestProfit
	end)
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
		SetStatus(not vendorList or not next(vendorList)
			and L["No cached vendor deals are available. Scan this auction house first."]
			or L["No profitable vendor deals remain."])
		return
	end

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
	searchPending = false
	transactionPending = false
	waitingForItemInfo = false
	waitingForResults = false
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
	actionButton:SetPoint("TOPRIGHT", page, "TOP", -4, -125)
	actionButton:SetText(L["Start Vendor Flips"])
	actionButton:SetScript("OnClick", StartVendorFlips)

	restartButton = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	restartButton:SetSize(150, 24)
	restartButton:SetPoint("TOPLEFT", page, "TOP", 4, -125)
	restartButton:SetText(L["Restart Vendor Flips"])
	restartButton:SetScript("OnClick", RestartVendorFlips)

	statusText = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	statusText:SetPoint("TOP", page, "TOP", 0, -159)
	statusText:SetWidth(500)
	statusText:SetText("")
end

StaticPopupDialogs[POPUP_NAME] = {
	text = "%s",
	button1 = BID,
	button2 = BUYOUT,
	button3 = L["Skip"],
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
					SetStatus(format(L["Building vendor cache: %d/%d items."], processed, total))
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
		elseif running and resumePage then
			resumePage = false
			self:ProcessCurrentPage()
		end
		if running and not transactionPending and searchPending and not waitingForResults then
			local canQuery = CanSendAuctionQuery()
			if canQuery then
				searchPending = false
				waitingForResults = true
				searchDeadline = GetTime() + QUERY_TIMEOUT
				QueryAuctionItems(currentRequest.name, nil, nil, currentPage, false, nil, false, true, nil)
			elseif GetTime() >= searchDeadline then
				SetStatus(L["Vendor search timed out; continuing."])
				AdvanceRequest()
			end
		elseif running and waitingForItemInfo and GetTime() >= searchDeadline then
			-- Reissuing the exact search is safer than discarding the whole cached
			-- request merely because one result row did not resolve promptly.
			waitingForItemInfo = false
			ScheduleSearch()
		elseif running and waitingForResults and GetTime() >= searchDeadline then
			SetStatus(L["Vendor search timed out; continuing."])
			waitingForResults = false
			AdvanceRequest()
		end
	end)
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
	if running and (waitingForResults or waitingForItemInfo) then
		local receivedNewPage = waitingForResults
		waitingForResults = false
		waitingForItemInfo = false
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