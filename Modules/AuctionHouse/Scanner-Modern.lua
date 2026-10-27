-- Scans modern auction listings and sends complete snapshots for market-data processing.

local C_AuctionHouse = C_AuctionHouse
local C_Item = C_Item
local ceil = math.ceil
local CreateFrame = CreateFrame
local floor = math.floor
local format = string.format
local GetServerTime = GetServerTime
local GetTime = GetTime
local hooksecurefunc = hooksecurefunc
local LibStub = LibStub
local min = math.min
local pairs = pairs
local strsplit = strsplit
local tonumber = tonumber
local UnitFactionGroup = UnitFactionGroup
local UnitGUID = UnitGUID

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local isForever = addon.isForever
local usesSharedAuctionHouse = addon.usesSharedAuctionHouse
local module = addon:NewModule("Scanner", "AceEvent-3.0")
local auctionHouseUI = addon:GetModule("AuctionHouseUI")
local dataProcessing
local L = LibStub("AceLocale-3.0"):GetLocale("YAAHA")

local FULL_SCAN_COOLDOWN = 15 * 60
local INITIAL_RESPONSE_TIMEOUT = 15
local REPLICATE_PROGRESS_TIMEOUT = 30
local ITEM_INFO_TIMEOUT = 15
local REPLICATE_BATCH_SIZE = 500
local RETRY_INTERVAL = 0.25

-- Forever retains faction and neutral auction houses despite using the modern
-- auction APIs. Known NPCs avoid unreliable faction results from goblin units;
-- UnitFactionGroup() covers new faction auctioneers Blizzard may add later.
local auctioneerFactions = {
	[8661]	= "Neutral",	-- Auctioneer Beardo
	[8669]	= "Alliance",	-- Auctioneer Tolon
	[8670]	= "Alliance",	-- Auctioneer Chilton
	[8671]	= "Alliance",	-- Auctioneer Buckler
	[8672]	= "Horde",		-- Auctioneer Leeka
	[8673]	= "Horde",		-- Auctioneer Thathung
	[8674]	= "Horde",		-- Auctioneer Stampi
	[8719]	= "Alliance",	-- Auctioneer Fitch
	[8720]	= "Alliance",	-- Auctioneer Redmuse
	[8721]	= "Horde",		-- Auctioneer Epitwee
	[8722]	= "Horde",		-- Auctioneer Gullem
	[8723]	= "Alliance",	-- Auctioneer Golothas
	[8724]	= "Horde",		-- Auctioneer Wabang
	[9856]	= "Horde",		-- Auctioneer Grimful
	[9857]	= "Neutral",	-- Auctioneer Grizzlin
	[9858]	= "Neutral",	-- Auctioneer Kresky
	[9859]	= "Alliance",	-- Auctioneer Lympkin
	[15659]	= "Alliance",	-- Auctioneer Jaxon
	[15675]	= "Horde",		-- Auctioneer Stockton
	[15676]	= "Horde",		-- Auctioneer Yarly
	[15677]	= "Neutral",	-- Auctioneer Graves
	[15678]	= "Alliance",	-- Auctioneer Silva'las
	[15679]	= "Alliance",	-- Auctioneer Cazarez
	[15681]	= "Neutral",	-- Auctioneer O'reely
	[15682]	= "Horde",		-- Auctioneer Cain
	[15683]	= "Horde",		-- Auctioneer Naxxremis
	[15684]	= "Horde",		-- Auctioneer Tricket
	[15686]	= "Horde",		-- Auctioneer Rhyker
	[16627]	= "Horde",		-- Ithillan
	[16628]	= "Horde",		-- Caidori
	[16629]	= "Horde",		-- Tandron
	[16707]	= "Alliance",	-- Eoch
	[17627]	= "Horde",		-- Jenath
	[17628]	= "Horde",		-- Vynna
	[17629]	= "Horde",		-- Feynna
	[18348]	= "Alliance",	-- Fanin
	[18349]	= "Alliance",	-- Iressa
	[18761]	= "Horde",		-- Darise
	[35594]	= "Alliance",	-- Brassbolt Mechawrench
	[35607]	= "Horde",		-- Reginald Arcfire
}

local scanButton, auctionScope, scanScope, scanning, lastFullScan
local auctionDB, numReplicateItems, nextReplicateIndex, numListings
local unresolvedIndices, unresolvedCursor, nextUnresolvedIndices, unresolvedRetryAt
local requestedItemIDs, responseDeadline, itemInfoDeadline
local scanStage, replicatedScanStartedAt, lastReplicateCount
local UpdateScanButton

local processingFrame = CreateFrame("Frame")
processingFrame:Hide()

local function GetNPCID()
	local guid = UnitGUID("npc")
	if not guid then
		return
	end

	local _, _, _, _, _, npcID = strsplit("-", guid)
	return tonumber(npcID)
end

local function GetAuctionScope()
	if usesSharedAuctionHouse then
		return "realm"
	end
	if not isForever then
		return
	end

	local npcID = GetNPCID()
	local auctioneerFaction = npcID and auctioneerFactions[npcID]
	if not auctioneerFaction then
		auctioneerFaction = UnitFactionGroup("npc")
	end
	if auctioneerFaction == "Neutral" then
		return "realm"
	end
	if auctioneerFaction == addon.playerFaction then
		return "factionrealm"
	end
end

local function ResetReplicateState()
	auctionDB = nil
	numReplicateItems = nil
	nextReplicateIndex = nil
	numListings = nil
	unresolvedIndices = nil
	unresolvedCursor = nil
	nextUnresolvedIndices = nil
	unresolvedRetryAt = nil
	requestedItemIDs = nil
	responseDeadline = nil
	itemInfoDeadline = nil
	scanStage = nil
	replicatedScanStartedAt = nil
	lastReplicateCount = nil
	processingFrame:Hide()
end

local function AddAuction(itemID, count, minBid, minIncrement, buyoutPrice, bidAmount)
	local currentDB = auctionDB
	if not currentDB then
		return false
	end
	if not itemID or itemID < 1 or itemID ~= floor(itemID) then
		return false
	end
	if not count or count < 1 or count ~= floor(count) then
		return false
	end
	if not minBid or minBid < 0 or not minIncrement or minIncrement < 0
		or not buyoutPrice or buyoutPrice < 0 or not bidAmount or bidAmount < 0 then
		return false
	end
	if minBid == 0 and buyoutPrice == 0 then
		return false
	end

	-- ReplicateItemInfo retains the legacy-shaped bid fields even on modern clients.
	-- Live ItemSearchResultInfo instead returns its already-actionable minBid.
	local payableBid = minBid > 0 and (bidAmount > 0 and bidAmount + minIncrement or minBid) or 0
	local itemKeyInfo = C_AuctionHouse.GetItemKeyInfo(C_AuctionHouse.MakeItemKey(itemID))
	if itemKeyInfo and itemKeyInfo.isCommodity then
		payableBid = 0
	end

	local itemData = currentDB[itemID]
	if not itemData then
		itemData = {}
		currentDB[itemID] = itemData
	end
	-- For commodities, count is the available volume represented by this replicated
	-- price tier, not an indivisible auction stack. Deal searches use it only to
	-- prefilter itemIDs; their live commodity queries choose any desired quantity.
	itemData.auctionQuantity = (itemData.auctionQuantity or 0) + count
	itemData.auctionCount = (itemData.auctionCount or 0) + 1
	local perUnit = 1 / count

	if payableBid > 0 then
		local unitBid = payableBid * perUnit
		if not itemData.minBid or unitBid < itemData.minBid then
			itemData.minBid = unitBid
		end
	end

	if buyoutPrice > 0 then
		local unitBuyout = buyoutPrice * perUnit
		if not itemData.minBuyout or unitBuyout < itemData.minBuyout then
			itemData.minBuyout = unitBuyout
		end

		-- Commodity quantities and classic-style stacks both contribute one market
		-- observation per item at the listing's per-unit price.
		local buyouts = itemData.buyouts
		if not buyouts then
			buyouts = {}
			itemData.buyouts = buyouts
		end
		buyouts[unitBuyout] = (buyouts[unitBuyout] or 0) + count

		local buyoutListings = itemData.buyoutListings
		if not buyoutListings then
			buyoutListings = {}
			itemData.buyoutListings = buyoutListings
		end
		buyoutListings[unitBuyout] = (buyoutListings[unitBuyout] or 0) + 1
	end

	-- Preserve replicated rows for deal-search prefiltering. Live commodity searches
	-- later aggregate current price tiers and never treat count as a required stack size.
	local unitBid = payableBid > 0 and payableBid * perUnit or 0
	local unitBuyout = buyoutPrice > 0 and buyoutPrice * perUnit or 0
	local auctions = itemData.auctions
	if not auctions then
		auctions = {}
		itemData.auctions = auctions
	end
	local byCount = auctions[count]
	if not byCount then
		byCount = {}
		auctions[count] = byCount
	end
	local byBid = byCount[unitBid]
	if not byBid then
		byBid = {}
		byCount[unitBid] = byBid
	end
	byBid[unitBuyout] = (byBid[unitBuyout] or 0) + 1
	return true
end

local function ReadReplicateItem(index)
	local requested = requestedItemIDs
	if not requested then
		return false
	end

	local _, _, count, _, _, _, _, minBid, minIncrement, buyoutPrice, bidAmount,
		_, _, _, _, _, itemID, hasAllInfo = C_AuctionHouse.GetReplicateItemInfo(index)
	if not hasAllInfo then
		if itemID and itemID > 0 and not requested[itemID] then
			requested[itemID] = true
			C_Item.RequestLoadItemDataByID(itemID)
		end
		return false
	end

	if AddAuction(itemID, count, minBid, minIncrement, buyoutPrice, bidAmount) then
		numListings = numListings + 1
	end
	return true
end

local function OnScanProcessed(success, scope)
	scanning = false
	scanScope = nil
	UpdateScanButton()
	if success then
		module:SendMessage("YAAHA_SCAN_PROCESSED", scope)
	end
	module:SendMessage("YAAHA_VENDOR_CACHE_READY", scope)
end

local function FinishScan()
	local numItems = 0
	for _ in pairs(auctionDB) do
		numItems = numItems + 1
	end
	addon:Printf(L["Finished scanning %d listings across %d items."], numListings, numItems)

	local completedDB = auctionDB
	local scope = scanScope
	ResetReplicateState()
	auctionHouseUI:SetScanStatus(L["Processing scan data..."])
	local started = dataProcessing:ProcessScan(scope, completedDB, {
		totalItems = numItems,
		totalListings = numListings,
	}, OnScanProcessed)
	if not started then
		scanning = false
		scanScope = nil
		auctionHouseUI:SetScanStatus(L["Scan unavailable."])
	end
end

local function FailScan()
	ResetReplicateState()
	scanning = false
	scanScope = nil
	auctionHouseUI:SetScanStatus(L["Scan unavailable."])
	UpdateScanButton()
end

local function ProcessInitialBatch()
	local nextIndex = nextReplicateIndex
	local total = numReplicateItems
	local pending = unresolvedIndices
	if not nextIndex or not total or not pending then
		FailScan()
		return
	end

	local lastIndex = min(nextIndex + REPLICATE_BATCH_SIZE - 1, total - 1)
	for index = nextIndex, lastIndex do
		if not ReadReplicateItem(index) then
			pending[#pending + 1] = index
		end
	end
	nextReplicateIndex = lastIndex + 1
	if nextReplicateIndex < total then
		return
	end

	if #pending == 0 then
		FinishScan()
		return
	end

	scanStage = "resolving"
	unresolvedCursor = 1
	nextUnresolvedIndices = {}
	itemInfoDeadline = GetTime() + ITEM_INFO_TIMEOUT
end

local function ProcessUnresolvedBatch()
	local cursorStart = unresolvedCursor
	local pending = unresolvedIndices
	local nextPending = nextUnresolvedIndices
	if not cursorStart or not pending or not nextPending or not itemInfoDeadline then
		FailScan()
		return
	end

	local lastCursor = min(cursorStart + REPLICATE_BATCH_SIZE - 1, #pending)
	for cursor = cursorStart, lastCursor do
		local index = pending[cursor]
		if not ReadReplicateItem(index) then
			nextPending[#nextPending + 1] = index
		end
	end
	unresolvedCursor = lastCursor + 1
	if unresolvedCursor <= #pending then
		return
	end

	if #nextPending == 0 then
		FinishScan()
		return
	end
	if GetTime() >= itemInfoDeadline then
		FailScan()
		return
	end

	unresolvedIndices = nextPending
	nextUnresolvedIndices = nil
	unresolvedRetryAt = GetTime() + RETRY_INTERVAL
	unresolvedCursor = 1
	scanStage = "retryWait"
end

local function ProcessScanUpdate()
	if scanStage == "waiting" then
		local now = GetTime()
		local replicateCount = C_AuctionHouse.GetNumReplicateItems()
		if replicateCount > (lastReplicateCount or 0) then
			lastReplicateCount = replicateCount
			responseDeadline = now + REPLICATE_PROGRESS_TIMEOUT
		end
		if now >= responseDeadline then
			FailScan()
		end
	elseif scanStage == "reading" then
		ProcessInitialBatch()
	elseif scanStage == "resolving" then
		ProcessUnresolvedBatch()
	elseif scanStage == "retryWait" and unresolvedRetryAt
		and GetTime() >= unresolvedRetryAt then
		scanStage = "resolving"
		nextUnresolvedIndices = {}
		unresolvedRetryAt = nil
	end
end

processingFrame:SetScript("OnUpdate", ProcessScanUpdate)

local function IsFullScanAPIReady()
	return C_AuctionHouse.IsThrottledMessageSystemReady()
end

local function SaveCooldownStart()
	lastFullScan = GetTime()
	addon.db.char.fullScanCooldownExpires = GetServerTime() + FULL_SCAN_COOLDOWN
end

local function BeginScan(scope)
	if scanning or not scope or dataProcessing:IsProcessing() then
		return false
	end

	scanScope = scope
	scanning = true
	scanStage = "waiting"
	responseDeadline = GetTime() + INITIAL_RESPONSE_TIMEOUT
	if scanButton then
		scanButton:Disable()
	end
	auctionHouseUI:SetScanStatus(L["Scanning auction house..."])
	processingFrame:Show()
	return true
end

local function ObserveReplicatedScan()
	-- ReplicateItems always requests a complete snapshot. Sharing its result lets
	-- YAAHA process a full scan initiated by Blizzard's UI or another addon without
	-- consuming a second cooldown.
	if BeginScan(auctionScope) then
		replicatedScanStartedAt = GetTime()
		lastReplicateCount = 0
	end
end

local function RestoreCooldown()
	local expires = addon.db.char.fullScanCooldownExpires
	if not expires then
		return
	end

	local remaining = expires - GetServerTime()
	if remaining > 0 then
		lastFullScan = GetTime() - (FULL_SCAN_COOLDOWN - remaining)
	else
		lastFullScan = nil
		addon.db.char.fullScanCooldownExpires = nil
	end
end

local function CanScan()
	if dataProcessing:IsProcessing() then
		return false
	end
	if lastFullScan and GetTime() - lastFullScan < FULL_SCAN_COOLDOWN then
		return false
	end
	return IsFullScanAPIReady()
end

local function GetCooldownRemaining()
	if not lastFullScan then
		return 0
	end

	local remaining = ceil(FULL_SCAN_COOLDOWN - (GetTime() - lastFullScan))
	if remaining <= 0 then
		lastFullScan = nil
		addon.db.char.fullScanCooldownExpires = nil
		return 0
	end
	return remaining
end

local function FormatCooldown(remaining)
	return format("%d:%02d", floor(remaining / 60), remaining % 60)
end

local function StartScan()
	if scanning or not CanScan() then
		return
	end

	if not BeginScan(auctionScope) then
		return
	end
	replicatedScanStartedAt = GetTime()
	lastReplicateCount = 0
	C_AuctionHouse.ReplicateItems()
end

UpdateScanButton = function()
	if not scanButton or scanning then
		return
	end
	if not auctionScope then
		auctionScope = GetAuctionScope()
	end
	auctionHouseUI:SetAuctionScope(auctionScope)

	if dataProcessing:IsProcessing() then
		scanButton:Disable()
		scanButton:SetText(L["Scan"])
		auctionHouseUI:SetScanStatus(L["Processing scan data..."])
		return
	end

	local remaining = GetCooldownRemaining()
	if remaining > 0 then
		scanButton:Disable()
		scanButton:SetText(L["Scan"])
		auctionHouseUI:SetScanStatus(format(L["Scan available in %s."],
			FormatCooldown(remaining)))
		return
	end

	local canScan = auctionScope ~= nil and CanScan()
	scanButton:SetEnabled(canScan)
	scanButton:SetText(L["Scan"])
	auctionHouseUI:SetScanStatus(canScan and L["Ready to scan."] or L["Scan unavailable."])
end

local function CreateScanButton()
	local parent = auctionHouseUI:GetScanButtonParent()
	if not parent then
		return
	end

	if not scanButton then
		scanButton = CreateFrame("Button", "YAAHAScanButton", parent, "UIPanelButtonTemplate")
		scanButton:SetSize(120, 22)
		scanButton:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, -10)
		scanButton:SetText(L["Scan"])
		scanButton:SetScript("OnClick", StartScan)
		scanButton:SetScript("OnUpdate", function(self, elapsed)
			self.updateElapsed = (self.updateElapsed or 0) + elapsed
			if self.updateElapsed >= 0.5 then
				self.updateElapsed = 0
				UpdateScanButton()
			end
		end)
	end

	scanButton:SetParent(parent)
	scanButton:Show()
	UpdateScanButton()
end

function module:OnInitialize()
	dataProcessing = addon:GetModule("DataProcessing")
end

function module:OnEnable()
	self:RegisterEvent("AUCTION_HOUSE_SHOW")
	self:RegisterEvent("AUCTION_HOUSE_CLOSED")
	self:RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
	self:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
	-- TODO: Recheck after WoWLua-LS updates. Every client which loads this file
	-- provides ReplicateItems, but version 0.35.2 still reports a flavor mismatch.
	---@diagnostic disable-next-line: wrong-flavor-api
	hooksecurefunc(C_AuctionHouse, "ReplicateItems", ObserveReplicatedScan)
end

function module:AUCTION_HOUSE_SHOW()
	auctionScope = GetAuctionScope()
	RestoreCooldown()
	auctionHouseUI:SetAuctionScope(auctionScope)
	CreateScanButton()
end

function module:AUCTION_HOUSE_CLOSED()
	ResetReplicateState()
	scanning = false
	auctionScope = nil
	scanScope = nil

	if scanButton then
		scanButton:Hide()
	end
end

function module:AUCTION_HOUSE_THROTTLED_SYSTEM_READY()
	UpdateScanButton()
end

function module:REPLICATE_ITEM_LIST_UPDATE()
	-- ReplicateItems clears the old snapshot immediately and can announce that
	-- empty state in the request frame. Wait for the later completion event.
	if replicatedScanStartedAt == GetTime() then
		return
	end
	if not scanning or scanStage ~= "waiting" then
		return
	end

	-- Start the cooldown when Blizzard confirms a successful response, not when the
	-- request is sent. Later update events merely announce item-cache progress.
	SaveCooldownStart()
	auctionDB = {}
	numReplicateItems = C_AuctionHouse.GetNumReplicateItems()
	nextReplicateIndex = 0
	numListings = 0
	unresolvedIndices = {}
	requestedItemIDs = {}
	responseDeadline = nil
	scanStage = "reading"
end

function module:GetAuctionScope()
	return auctionScope
end

function module:GetScanButton()
	return scanButton
end

function module:IsScanning()
	return scanning or dataProcessing:IsProcessing()
end