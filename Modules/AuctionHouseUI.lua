local _G = _G
local AUCTION_HOUSE_FRAME_TITLE_SELL = AUCTION_HOUSE_FRAME_TITLE_SELL
local CreateFrame = CreateFrame
local FACTION_NEUTRAL = FACTION_NEUTRAL
local hooksecurefunc = hooksecurefunc
local ipairs = ipairs
local LibStub = LibStub
local pairs = pairs
local PanelTemplates_SetNumTabs = PanelTemplates_SetNumTabs
local PanelTemplates_SetTab = PanelTemplates_SetTab
local PanelTemplates_TabResize = PanelTemplates_TabResize
local PlaySound = PlaySound
local SEARCH = SEARCH
local SOUNDKIT = SOUNDKIT
local type = type
local UnitFactionGroup = UnitFactionGroup
local UNKNOWN = UNKNOWN

local playerFaction = UnitFactionGroup("player")
local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local module = addon:NewModule("AuctionHouseUI", "AceEvent-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("YAAHA")

local auctionFrame, workspace, yaahaTab
local pageButtons = {}
local pages = {}
local selectedPage = "search"
local scopeText, statusText

local pageDefinitions = {
	{
		key = "search",
		label = SEARCH,
		title = SEARCH,
		description = L["Find a specific item, a batch of items, or an imported list of itemIDs."],
	},
	{
		key = "post",
		label = AUCTION_HOUSE_FRAME_TITLE_SELL,
		title = AUCTION_HOUSE_FRAME_TITLE_SELL,
		description = L["Create and manage auction listings."],
	},
	{
		key = "cancelling",
		label = L["Cancelling"],
		title = L["Cancel undercut auctions"],
		description = L["Find and quickly cancel your auctions which have been undercut."],
	},
	{
		key = "deals",
		label = L["Deals"],
		title = L["Find profitable deals"],
		description = L["Find vendor, disenchanting, milling, and prospecting opportunities."],
	},
}

local blizzardTabs = {
	browse = 1,
	bids = 2,
	auctions = 3,
}

local yaahaPages = {
	yaahaSearch = "search",
	yaahaPost = "post",
	yaahaCancelling = "cancelling",
	yaahaDeals = "deals",
}

local function HideBlizzardPages()
	-- Blizzard's tab handler normally performs this work. YAAHA uses its own click
	-- handler, so the three original page frames must be hidden explicitly.
	for _, frameName in ipairs({ "AuctionFrameBrowse", "AuctionFrameBid", "AuctionFrameAuctions" }) do
		local frame = _G[frameName]
		if frame then
			frame:Hide()
		end
	end
end

local function SelectPage(pageKey)
	if not pages[pageKey] then
		pageKey = "search"
	end

	for key, page in pairs(pages) do
		page:SetShown(key == pageKey)
		if key == pageKey then
			pageButtons[key]:LockHighlight()
		else
			pageButtons[key]:UnlockHighlight()
		end
	end

	selectedPage = pageKey
end

local function ShowWorkspace(pageKey)
	HideBlizzardPages()
	PanelTemplates_SetTab(auctionFrame, yaahaTab:GetID())
	workspace:Show()
	-- Other auction addons may leave sibling content visible when their tab loses
	-- selection. Raise YAAHA's opaque workspace each time to provide a clean canvas
	-- without hiding or altering frames owned by those addons.
	workspace:Raise()
	SelectPage(type(pageKey) == "string" and pageKey or selectedPage)
	PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
end

local function OpenConfiguredPage()
	local configuredPage = addon.db.profile.auctionHouseOpeningPage
	local yaahaPage = yaahaPages[configuredPage]
	if yaahaPage then
		ShowWorkspace(yaahaPage)
		return
	end

	local tab = _G["AuctionFrameTab" .. (blizzardTabs[configuredPage] or 1)]
	if tab then
		tab:Click()
	end
end

local function CreatePage(definition, previousButton)
	local button = CreateFrame("Button", nil, workspace, "UIPanelButtonTemplate")
	button:SetSize(105, 22)
	button:SetText(definition.label)
	if previousButton then
		button:SetPoint("LEFT", previousButton, "RIGHT", 4, 0)
	else
		button:SetPoint("TOPLEFT", workspace, "TOPLEFT", 14, -12)
	end
	button:SetScript("OnClick", function()
		SelectPage(definition.key)
	end)
	pageButtons[definition.key] = button

	local page = CreateFrame("Frame", nil, workspace)
	page:SetPoint("TOPLEFT", workspace, "TOPLEFT", 14, -66)
	page:SetPoint("BOTTOMRIGHT", workspace, "BOTTOMRIGHT", -14, 14)
	pages[definition.key] = page

	local title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOP", page, "TOP", 0, -55)
	title:SetText(definition.title)

	local description = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	description:SetPoint("TOP", title, "BOTTOM", 0, -12)
	description:SetWidth(520)
	description:SetJustifyH("CENTER")
	description:SetText(definition.description)

	return button
end

local function CreateWorkspace()
	if workspace then
		return
	end

	-- Every supported client currently uses the classic AuctionFrame. Resolve it
	-- only after Blizzard's load-on-demand auction UI has been created.
	auctionFrame = AuctionFrame
	if not auctionFrame then
		return
	end

	workspace = CreateFrame("Frame", "YAAHAAuctionHouseFrame", auctionFrame)
	workspace:SetPoint("TOPLEFT", auctionFrame, "TOPLEFT", 8, -58)
	workspace:SetPoint("BOTTOMRIGHT", auctionFrame, "BOTTOMRIGHT", -8, 8)
	workspace:SetFrameStrata("HIGH")
	workspace:SetToplevel(true)
	workspace:Hide()

	local background = workspace:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(0.035, 0.035, 0.035, 1)

	scopeText = workspace:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	scopeText:SetPoint("TOPLEFT", workspace, "TOPLEFT", 14, -39)
	scopeText:SetWidth(300)
	scopeText:SetJustifyH("LEFT")
	scopeText:SetFormattedText(L["Auction house: %s"], UNKNOWN)

	statusText = workspace:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	statusText:SetPoint("TOPRIGHT", workspace, "TOPRIGHT", -14, -39)
	statusText:SetWidth(190)
	statusText:SetJustifyH("RIGHT")
	statusText:SetText(L["Scan unavailable."])

	local previousButton
	for index = 1, #pageDefinitions do
		previousButton = CreatePage(pageDefinitions[index], previousButton)
	end

	-- PanelTemplates discovers classic tabs by their AuctionFrameTabN global names.
	-- Using the next index also allows YAAHA to coexist with addons loaded before it.
	local tabID = auctionFrame.numTabs or 3
	repeat
		tabID = tabID + 1
	until not _G["AuctionFrameTab" .. tabID]

	yaahaTab = CreateFrame("Button", "AuctionFrameTab" .. tabID, auctionFrame, "AuctionTabTemplate")
	yaahaTab:SetID(tabID)
	yaahaTab:SetText("YAAHA")
	PanelTemplates_TabResize(yaahaTab, 0)

	local previousTab = _G["AuctionFrameTab" .. (tabID - 1)] or AuctionFrameTab3
	yaahaTab:SetPoint("TOPLEFT", previousTab, "TOPRIGHT", -8, 0)
	yaahaTab:SetScript("OnClick", ShowWorkspace)
	PanelTemplates_SetNumTabs(auctionFrame, tabID)

	-- Blizzard's original tab handler remains authoritative for its own pages. The
	-- post-hook merely removes YAAHA's overlay whenever any original tab is chosen.
	hooksecurefunc("AuctionFrameTab_OnClick", function(tab)
		if tab ~= yaahaTab then
			workspace:Hide()
		end
	end)

	SelectPage(selectedPage)
end

function module:GetPage(pageKey)
	CreateWorkspace()
	return pages[pageKey]
end

function module:GetScanButtonParent()
	CreateWorkspace()
	return workspace
end

function module:SetAuctionScope(scope)
	if not scopeText then
		return
	end

	local scopeName = scope == "realm" and FACTION_NEUTRAL or scope == "factionrealm" and playerFaction or UNKNOWN
	scopeText:SetFormattedText(L["Auction house: %s"], scopeName)
end

function module:SetScanStatus(status)
	if statusText then
		statusText:SetText(status)
	end
end

function module:OnEnable()
	self:RegisterEvent("AUCTION_HOUSE_SHOW")
end

function module:AUCTION_HOUSE_SHOW()
	CreateWorkspace()
	OpenConfiguredPage()
end