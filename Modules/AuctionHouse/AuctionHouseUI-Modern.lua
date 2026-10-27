-- Builds YAAHA's workspace and navigation inside the modern auction-house frame.

local abs = math.abs
local AUCTION_HOUSE_FRAME_TITLE_SELL = AUCTION_HOUSE_FRAME_TITLE_SELL
local CreateFrame = CreateFrame
local FACTION_NEUTRAL = FACTION_NEUTRAL
local hooksecurefunc = hooksecurefunc
local ipairs = ipairs
local LibStub = LibStub
local OPTIONS = OPTIONS
local pairs = pairs
local PanelTemplates_DeselectTab = PanelTemplates_DeselectTab
local PanelTemplates_SelectTab = PanelTemplates_SelectTab
local PanelTemplates_SetNumTabs = PanelTemplates_SetNumTabs
local PanelTemplates_SetTab = PanelTemplates_SetTab
local PanelTemplates_TabResize = PanelTemplates_TabResize
local PlaySound = PlaySound
local SOUNDKIT = SOUNDKIT
local type = type
local UNKNOWN = UNKNOWN

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local isStandard = addon.isStandard
local usesSharedAuctionHouse = addon.usesSharedAuctionHouse
local module = addon:NewModule("AuctionHouseUI", "AceEvent-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("YAAHA")

local auctionFrame, workspace, yaahaTab
local pageIndices = {}
local pageKeysByButton = {}
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

local yaahaPages = {
	yaahaSearch = "search",
	yaahaPost = "post",
	yaahaCancelling = "cancelling",
	yaahaDeals = "deals",
}

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

local function DeselectBlizzardTabs()
	for _, tab in ipairs(auctionFrame.Tabs) do
		PanelTemplates_DeselectTab(tab)
	end
end

local function PageOnClick(button)
	SelectPage(pageKeysByButton[button])
end

local function OpenOptions()
	addon:OpenConfig()
end

local function ShowWorkspace(pageKey)
	-- An empty display mode asks Blizzard to hide every native auction pane without
	-- coupling YAAHA to the modern frame's expanding collection of child frames.
	auctionFrame:SetDisplayMode({})
	auctionFrame.displayMode = nil
	DeselectBlizzardTabs()
	PanelTemplates_SelectTab(yaahaTab)
	auctionFrame:SetTitle("YAAHA")
	workspace:Show()
	workspace:Raise()
	SelectPage(type(pageKey) == "string" and pageKey or selectedPage)
	PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
end

local function ShowBlizzardPage(pageKey)
	if pageKey == "bids" then
		auctionFrame:SetDisplayMode(AuctionHouseFrameDisplayMode.Auctions)
		auctionFrame.AuctionsFrame:SetTab(2)
	elseif pageKey == "auctions" then
		auctionFrame:SetDisplayMode(AuctionHouseFrameDisplayMode.Auctions)
		auctionFrame.AuctionsFrame:SetTab(1)
	else
		auctionFrame:SetDisplayMode(AuctionHouseFrameDisplayMode.Buy)
	end
end

local function OpenConfiguredPage()
	local configuredPage = addon.db.profile.auctionHouseOpeningPage
	local yaahaPage = yaahaPages[configuredPage]
	if yaahaPage then
		ShowWorkspace(yaahaPage)
		return
	end

	ShowBlizzardPage(configuredPage)
end

local function AuctionHouseDisplayModeChanged(_, displayMode)
	if displayMode and #displayMode > 0 then
		workspace:Hide()
		PanelTemplates_DeselectTab(yaahaTab)
	end
end

local function CreatePage(definition, index, previousButton)
	local button = CreateFrame("Button", "YAAHAAuctionHouseFrameTab" .. index, workspace,
		"PanelTabButtonTemplate")
	button:SetID(index)
	button:SetText(definition.label)
	PanelTemplates_TabResize(button, 0)
	if previousButton then
		button:SetPoint("TOPLEFT", previousButton, "TOPRIGHT", -14, 0)
	else
		button:SetPoint("TOPLEFT", workspace, "TOPLEFT", 14, -68)
	end
	pageKeysByButton[button] = definition.key
	button:SetScript("OnClick", PageOnClick)
	pageIndices[definition.key] = index

	local page = CreateFrame("Frame", nil, workspace)
	page:SetPoint("TOPLEFT", workspace, "TOPLEFT", 14, -99)
	page:SetPoint("BOTTOMRIGHT", workspace, "BOTTOMRIGHT", -14, 14)
	pages[definition.key] = page

	return button
end

local function CreateAuctionHouseTab()
	local tabRoot = CreateFrame("Frame", nil, auctionFrame)
	tabRoot:SetSize(10, 10)
	tabRoot:SetPoint("TOPLEFT", auctionFrame.Tabs[#auctionFrame.Tabs], "TOPRIGHT")

	local offsetX = isStandard and 3 or -14
	yaahaTab = CreateFrame("Button", "YAAHAAuctionHouseFrameDisplayModeTab", tabRoot,
		"AuctionHouseFrameDisplayModeTabTemplate")
	yaahaTab:SetText("YAAHA")
	PanelTemplates_TabResize(yaahaTab, 20, nil, 70)
	yaahaTab:SetPoint("TOPLEFT", tabRoot, "TOPLEFT", offsetX, 0)
	yaahaTab:SetHitRectInsets((abs(offsetX) - 3) / 2, (abs(offsetX) - 3) / 2, 0, 0)
	yaahaTab:SetScript("OnClick", ShowWorkspace)
	PanelTemplates_DeselectTab(yaahaTab)
end

local function CreateWorkspace()
	if workspace then
		return
	end

	-- The modern auction UI is load-on-demand, so its frame is resolved only after
	-- AUCTION_HOUSE_SHOW confirms Blizzard has constructed it.
	auctionFrame = AuctionHouseFrame
	if not auctionFrame then
		return
	end

	workspace = CreateFrame("Frame", "YAAHAAuctionHouseFrame", auctionFrame)
	workspace:SetPoint("TOPLEFT", auctionFrame, "TOPLEFT", 4, -27)
	workspace:SetPoint("BOTTOMRIGHT", auctionFrame, "BOTTOMRIGHT", -4, 29)
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
	optionsButton:SetScript("OnClick", OpenOptions)

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
	CreateAuctionHouseTab()

	-- Blizzard remains authoritative for native page changes. This hook only
	-- removes YAAHA's overlay when a non-empty Blizzard display mode is selected.
	hooksecurefunc(auctionFrame, "SetDisplayMode", AuctionHouseDisplayModeChanged)

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

	local scopeName
	if scope == "realm" then
		scopeName = usesSharedAuctionHouse and L["Shared"] or FACTION_NEUTRAL
	elseif scope == "factionrealm" then
		scopeName = addon.localizedPlayerFaction or addon.playerFaction
	end
	scopeText:SetFormattedText(L["Auction house: %s"], scopeName or UNKNOWN)
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
	if workspace then
		OpenConfiguredPage()
	end
end