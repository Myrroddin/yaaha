local _G = _G
local AUCTION_HOUSE_FRAME_TITLE_SELL = AUCTION_HOUSE_FRAME_TITLE_SELL
local CreateFrame = CreateFrame
local FACTION_NEUTRAL = FACTION_NEUTRAL
local hooksecurefunc = hooksecurefunc
local ipairs = ipairs
local LibStub = LibStub
local OPTIONS = OPTIONS
local pairs = pairs
local PanelTemplates_SetNumTabs = PanelTemplates_SetNumTabs
local PanelTemplates_SetTab = PanelTemplates_SetTab
local PanelTemplates_TabResize = PanelTemplates_TabResize
local PlaySound = PlaySound
local SOUNDKIT = SOUNDKIT
local type = type
local UnitFactionGroup = UnitFactionGroup
local UNKNOWN = UNKNOWN

local playerFaction, localizedPlayerFaction = UnitFactionGroup("player")
local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local module = addon:NewModule("AuctionHouseUI", "AceEvent-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("YAAHA")

local auctionFrame, workspace, yaahaTab
local pageIndices = {}
local pages = {}
local selectedPage = "post"
local scopeText, statusText

local pageDefinitions = {
	{
		key = "post",
		label = AUCTION_HOUSE_FRAME_TITLE_SELL,
	},
	{
		key = "search",
		label = L["Shopping"],
	},
	{
		key = "cancelling",
		label = L["Cancelling"],
	},
	{
		key = "deals",
		label = L["Deals"],
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
		pageKey = "post"
	end

	for key, page in pairs(pages) do
		page:SetShown(key == pageKey)
	end

	selectedPage = pageKey
	PanelTemplates_SetTab(workspace, pageIndices[pageKey])
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

local function CreatePage(definition, index, previousButton)
	-- Named PanelTabButtonTemplate children let Blizzard's panel helpers apply the
	-- familiar selected/unselected tab treatment instead of imitating tabs with
	-- ordinary push buttons.
	local button = CreateFrame("Button", "YAAHAAuctionHouseFrameTab" .. index, workspace, "PanelTabButtonTemplate")
	button:SetID(index)
	button:SetText(definition.label)
	PanelTemplates_TabResize(button, 0)
	if previousButton then
		button:SetPoint("TOPLEFT", previousButton, "TOPRIGHT", -14, 0)
	else
		button:SetPoint("TOPLEFT", workspace, "TOPLEFT", 14, -68)
	end
	button:SetScript("OnClick", function()
		SelectPage(definition.key)
	end)
	pageIndices[definition.key] = index

	local page = CreateFrame("Frame", nil, workspace)
	page:SetPoint("TOPLEFT", workspace, "TOPLEFT", 14, -99)
	page:SetPoint("BOTTOMRIGHT", workspace, "BOTTOMRIGHT", -14, 14)
	pages[definition.key] = page

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

	local optionsButton = CreateFrame("Button", "YAAHAOptionsButton", workspace, "UIPanelButtonTemplate")
	optionsButton:SetSize(100, 22)
	optionsButton:SetPoint("TOPLEFT", workspace, "TOPLEFT", 142, -10)
	optionsButton:SetText(OPTIONS)
	optionsButton:SetScript("OnClick", function()
		addon:OpenConfig()
	end)

	scopeText = workspace:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	scopeText:SetPoint("TOPLEFT", workspace, "TOPLEFT", 14, -42)
	scopeText:SetWidth(300)
	scopeText:SetJustifyH("LEFT")
	scopeText:SetFormattedText(L["Auction house: %s"], UNKNOWN)

	statusText = workspace:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	statusText:SetPoint("TOPLEFT", workspace, "TOPLEFT", 320, -42)
	statusText:SetPoint("TOPRIGHT", workspace, "TOPRIGHT", -14, -42)
	statusText:SetJustifyH("RIGHT")
	statusText:SetText(L["Scan unavailable."])

	local previousButton
	for index = 1, #pageDefinitions do
		previousButton = CreatePage(pageDefinitions[index], index, previousButton)
	end
	PanelTemplates_SetNumTabs(workspace, #pageDefinitions)

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

	local scopeName = scope == "realm" and FACTION_NEUTRAL
		or scope == "factionrealm" and (localizedPlayerFaction or playerFaction) or UNKNOWN
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