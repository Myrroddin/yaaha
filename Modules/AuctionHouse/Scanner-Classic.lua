-- Scans Classic auction listings and sends complete snapshots for market-data processing.

local C_AuctionHouse = C_AuctionHouse
local CanSendAuctionQuery = CanSendAuctionQuery
local ceil = math.ceil
local CreateFrame = CreateFrame
local floor = math.floor
local format = string.format
local GetAuctionItemInfo = GetAuctionItemInfo
local GetNumAuctionItems = GetNumAuctionItems
local GetServerTime = GetServerTime
local GetTime = GetTime
local hooksecurefunc = hooksecurefunc
local LibStub = LibStub
local pairs = pairs
local QueryAuctionItems = QueryAuctionItems
local strsplit = strsplit
local tonumber = tonumber
local UnitGUID = UnitGUID

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local isWrath = addon.isWrath
local playerFaction = addon.playerFaction
local module = addon:NewModule("Scanner", "AceEvent-3.0")
local auctionHouseUI = addon:GetModule("AuctionHouseUI")
local dataProcessing
local L = LibStub("AceLocale-3.0"):GetLocale("YAAHA")

-- UnitFactionGroup() is unreliable for some NPCs, particularly goblins. Explicit
-- NPC factions keep neutral scans separate without depending on localized names.
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

local scanButton, auctionScope, scanScope, scanning, scanDeadline, lastFullScan
local externalFullScanObserved, legacyResultsReadyAt, replicatedScanStartedAt
local lastReplicateCount
local UpdateScanButton
local FULL_SCAN_COOLDOWN = 15 * 60
local SCAN_RESPONSE_TIMEOUT = 15
local REPLICATE_PROGRESS_TIMEOUT = 30

local function GetNPCID()
	local guid = UnitGUID("npc")
	if not guid then
		return
	end

	local _, _, _, _, _, npcID = strsplit("-", guid)
	return tonumber(npcID)
end

local function GetAuctionScope()
	local npcID = GetNPCID()
	local auctioneerFaction = npcID and auctioneerFactions[npcID]
	if auctioneerFaction == "Neutral" then
		return "realm"
	end

	if auctioneerFaction == playerFaction then
		return "factionrealm"
	end
end

local function AddAuction(auctionDB, itemID, count, minBid, minIncrement, buyoutPrice, bidAmount)
	if not itemID or itemID < 1 or itemID ~= floor(itemID) then
		return
	end
	if not count or count < 1 or count ~= floor(count) then
		return
	end
	-- Every valid auction has a starting bid of at least one copper. A zero buyout
	-- means bid-only, but a positive buyout never makes a zero-bid record valid.
	if not minBid or minBid < 1 or not buyoutPrice or buyoutPrice < 0 then
		return
	end
	if not minIncrement or minIncrement < 0 or not bidAmount or bidAmount < 0 then
		return
	end

	-- Once bidding has started, the actionable price is the current bid plus
	-- Blizzard's minimum increment rather than the auction's original starting bid.
	local payableBid = bidAmount > 0 and bidAmount + minIncrement or minBid
	local itemData = auctionDB[itemID]
	if not itemData then
		itemData = {}
		auctionDB[itemID] = itemData
	end
	-- This is the number of individual items represented by this itemID, not the
	-- number of auction rows. It remains independent from price weighting even
	-- though both calculations use stack quantity.
	itemData.auctionQuantity = (itemData.auctionQuantity or 0) + count
	itemData.auctionCount = (itemData.auctionCount or 0) + 1
	local perUnit = 1 / count

	if payableBid > 0 then
		local unitBid = payableBid * perUnit
		if not itemData.minBid or unitBid < itemData.minBid then
			itemData.minBid = unitBid
		end
	end

	if buyoutPrice and buyoutPrice > 0 then
		local unitBuyout = buyoutPrice * perUnit
		if not itemData.minBuyout or unitBuyout < itemData.minBuyout then
			itemData.minBuyout = unitBuyout
		end

		-- Each item in a stack is one observation at the auction's per-unit price.
		-- The histogram preserves that weighting without allocating one entry per item.
		local buyouts = itemData.buyouts
		if not buyouts then
			buyouts = {}
			itemData.buyouts = buyouts
		end
		buyouts[unitBuyout] = (buyouts[unitBuyout] or 0) + count

		-- Keep a second transient histogram by listing rather than quantity. Market
		-- processing uses it only to confirm that several cheaper auctions establish
		-- a price cluster before rejecting an extreme early jump.
		local buyoutListings = itemData.buyoutListings
		if not buyoutListings then
			buyoutListings = {}
			itemData.buyoutListings = buyoutListings
		end
		buyoutListings[unitBuyout] = (buyoutListings[unitBuyout] or 0) + 1
	end

	-- Vendor-flip candidates must retain listing-level stack and price combinations.
	-- Nested numeric keys group identical auctions without relying on unstable IDs.
	local unitBid = payableBid and payableBid > 0 and payableBid * perUnit or 0
	local unitBuyout = buyoutPrice and buyoutPrice > 0 and buyoutPrice * perUnit or 0
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
end

local function OnScanProcessed(success, scope)
	scanning = false
	scanScope = nil
	UpdateScanButton()
	if success then
		module:SendMessage("YAAHA_SCAN_PROCESSED", scope)
	end
	-- Notify dependent UI immediately. Waiting for its periodic state check leaves
	-- a brief interval where the cache is ready but the Deals button ignores a click.
	module:SendMessage("YAAHA_VENDOR_CACHE_READY", scope)
end

---@param numListings number
local function FinishScan(auctionDB, numListings)
	local numItems = 0
	-- The scan count describes auction rows, while the database keys describe
	-- distinct items. Stack quantities influence price weighting, not either count.
	for _ in pairs(auctionDB) do
		numItems = numItems + 1
	end
	addon:Printf(L["Finished scanning %d listings across %d items."], numListings, numItems)

	local scope = scanScope
	auctionHouseUI:SetScanStatus(L["Processing scan data..."])
	local started = dataProcessing:ProcessScan(scope, auctionDB, {
		totalItems = numItems,
		totalListings = numListings,
	}, OnScanProcessed)
	if not started then
		scanning = false
		scanScope = nil
		auctionHouseUI:SetScanStatus(L["Scan unavailable."])
	end
end

local function ReadLegacyAuctions()
	local auctionDB = {}
	local numAuctions = GetNumAuctionItems("list")

	for index = 1, numAuctions do
		local _, _, count, _, _, _, _, minBid, minIncrement, buyoutPrice, bidAmount, _, _, _, _, _, itemID = GetAuctionItemInfo("list", index)
		AddAuction(auctionDB, itemID, count, minBid, minIncrement, buyoutPrice, bidAmount)
	end

	FinishScan(auctionDB, numAuctions)
end

local ReadReplicatedAuctions
local CanStartReplicatedScan = function()
	return false
end
local StartReplicatedScan = function() end
if isWrath then
	-- Titan Reforged exposes the modern replicated-auction API. Keeping these
	-- lookups inside the project guard prevents Era from evaluating unavailable APIs.
	CanStartReplicatedScan = C_AuctionHouse.IsThrottledMessageSystemReady
	StartReplicatedScan = C_AuctionHouse.ReplicateItems
	local GetNumReplicateItems = C_AuctionHouse.GetNumReplicateItems
	local GetReplicateItemInfo = C_AuctionHouse.GetReplicateItemInfo

	ReadReplicatedAuctions = function()
		local auctionDB = {}
		local numAuctions = GetNumReplicateItems()

		for index = 0, numAuctions - 1 do
			local _, _, count, _, _, _, _, minBid, minIncrement, buyoutPrice, bidAmount, _, _, _, _, _, itemID = GetReplicateItemInfo(index)
			AddAuction(auctionDB, itemID, count, minBid, minIncrement, buyoutPrice, bidAmount)
		end

		FinishScan(auctionDB, numAuctions)
	end
end

local function IsFullScanAPIReady()
	if isWrath then
		return CanStartReplicatedScan()
	end

	local _, canQueryAll = CanSendAuctionQuery()
	return canQueryAll
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
	scanDeadline = GetTime() + SCAN_RESPONSE_TIMEOUT
	if scanButton then
		scanButton:Disable()
	end
	auctionHouseUI:SetScanStatus(L["Scanning auction house..."])
	return true
end

local function ObserveLegacyFullScan(_, _, _, _, _, _, getAll)
	-- Classic page and item searches are incomplete snapshots. Only adopt the
	-- explicit getAll request used by YAAHA, Zygor, Auctioneer, and similar scanners.
	if getAll then
		externalFullScanObserved = true
		scanDeadline = GetTime() + SCAN_RESPONSE_TIMEOUT
		BeginScan(auctionScope)
	end
end

local function ObserveReplicatedScan()
	-- Wrath uses the replicated full-market API. The response event is unique to
	-- that operation, so YAAHA can safely share a scan initiated by another addon.
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

	-- A UI reload preserves Blizzard's full-scan throttle, while logging out resets
	-- it. Trust Blizzard's readiness result first so a saved expiry never imposes a
	-- cooldown which the server has already cleared after a new login.
	if IsFullScanAPIReady() then
		lastFullScan = nil
		addon.db.char.fullScanCooldownExpires = nil
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
	-- Minutes remain compact while seconds always occupy two digits, preventing a
	-- value such as 9:5 from being mistaken for either 9:05 or 9:50.
	return format("%d:%02d", floor(remaining / 60), remaining % 60)
end

local function StartScan()
	if scanning or not CanScan() then
		return
	end

	if not BeginScan(auctionScope) then
		return
	end

	if isWrath then
		replicatedScanStartedAt = GetTime()
		lastReplicateCount = 0
		StartReplicatedScan()
	else
		QueryAuctionItems("", nil, nil, 0, false, nil, true, false, nil)
	end
end

UpdateScanButton = function()
	if not scanButton or scanning then
		return
	end
	if not auctionScope then
		auctionScope = GetAuctionScope()
	end
	-- AuctionHouseUI and Scanner both receive AUCTION_HOUSE_SHOW, but AceEvent
	-- does not guarantee their callback order. Reapply the scope after the UI
	-- exists, and keep retrying while Blizzard's npc unit is not yet available.
	auctionHouseUI:SetAuctionScope(auctionScope)

	if dataProcessing:IsProcessing() then
		scanButton:Disable()
		scanButton:SetText(L["Scan"])
		auctionHouseUI:SetScanStatus(L["Processing scan data..."])
		return
	end

	local remaining = GetCooldownRemaining()
	if remaining > 0 then
		local cooldown = FormatCooldown(remaining)
		scanButton:Disable()
		scanButton:SetText(L["Scan"])
		auctionHouseUI:SetScanStatus(format(L["Scan available in %s."], cooldown))
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
	self:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	if isWrath then
		self:RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
		self:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
	end
end

function module:AUCTION_HOUSE_SHOW()
	auctionScope = GetAuctionScope()
	RestoreCooldown()
	auctionHouseUI:SetAuctionScope(auctionScope)
	CreateScanButton()
	if externalFullScanObserved and not scanning then
		BeginScan(auctionScope)
	end
end

function module:AUCTION_HOUSE_CLOSED()
	scanning = false
	auctionScope = nil
	scanScope = nil
	scanDeadline = nil
	externalFullScanObserved = nil
	legacyResultsReadyAt = nil
	replicatedScanStartedAt = nil
	lastReplicateCount = nil

	if scanButton then
		scanButton:Hide()
	end
end

function module:AUCTION_ITEM_LIST_UPDATE()
	if not scanning and externalFullScanObserved then
		BeginScan(auctionScope)
	end
	if scanning and not isWrath then
		-- Full scans may emit an immediate empty notification followed by the real
		-- data. Wait until the next frame after the latest notification before reading.
		legacyResultsReadyAt = GetTime()
	end
end

function module:REPLICATE_ITEM_LIST_UPDATE()
	-- ReplicateItems clears the old snapshot immediately and can announce that
	-- empty state in the request frame. Wait for the later completion event.
	if replicatedScanStartedAt == GetTime() then
		return
	end
	if scanning and ReadReplicatedAuctions then
		-- Start the cooldown when Blizzard confirms a successful response, not when
		-- the request is sent. This prevents network delay from shortening the wait.
		SaveCooldownStart()
		scanning = false
		scanDeadline = nil
		replicatedScanStartedAt = nil
		lastReplicateCount = nil
		ReadReplicatedAuctions()
	end
end

function module:PLAYER_ENTERING_WORLD()
	-- Install after every addon has loaded so a later global wrapper cannot replace
	-- this observer. Post-hooks do not alter or delay the initiating addon's scan.
	if isWrath then
		hooksecurefunc(C_AuctionHouse, "ReplicateItems", ObserveReplicatedScan)
	else
		hooksecurefunc("QueryAuctionItems", ObserveLegacyFullScan)
	end
	self:UnregisterEvent("PLAYER_ENTERING_WORLD")
end

function module:AUCTION_HOUSE_THROTTLED_SYSTEM_READY()
	UpdateScanButton()
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

local scanWatchdog = CreateFrame("Frame")
scanWatchdog:SetScript("OnUpdate", function()
	if scanning and isWrath and replicatedScanStartedAt then
		-- TODO: Recheck after WoWLua-LS updates. This branch runs only on Wrath,
		-- where Blizzard provides the replicated-auction API.
		---@diagnostic disable-next-line: wrong-flavor-api
		local replicateCount = C_AuctionHouse.GetNumReplicateItems()
		if replicateCount > (lastReplicateCount or 0) then
			lastReplicateCount = replicateCount
			scanDeadline = GetTime() + REPLICATE_PROGRESS_TIMEOUT
		end
	end
	if scanning and legacyResultsReadyAt and GetTime() > legacyResultsReadyAt then
		legacyResultsReadyAt = nil
		SaveCooldownStart()
		scanning = false
		scanDeadline = nil
		externalFullScanObserved = nil
		ReadLegacyAuctions()
	elseif (scanning or externalFullScanObserved) and scanDeadline
		and GetTime() >= scanDeadline then
		-- A failed external request must not leave YAAHA permanently busy. The
		-- cooldown begins only after Blizzard delivers the corresponding response.
		scanning = false
		scanScope = nil
		scanDeadline = nil
		externalFullScanObserved = nil
		legacyResultsReadyAt = nil
		replicatedScanStartedAt = nil
		lastReplicateCount = nil
		auctionHouseUI:SetScanStatus(L["Scan unavailable."])
		UpdateScanButton()
	end
end)