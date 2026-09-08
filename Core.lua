local abs = math.abs
local COPPER_AMOUNT_SYMBOL = COPPER_AMOUNT_SYMBOL
local COPPER_AMOUNT_TEXTURE = COPPER_AMOUNT_TEXTURE
local floor = math.floor
local format = string.format
local FormatLargeNumber = FormatLargeNumber
local GOLD_AMOUNT_SYMBOL = GOLD_AMOUNT_SYMBOL
local GOLD_AMOUNT_TEXTURE = GOLD_AMOUNT_TEXTURE
local LibStub = LibStub
local SILVER_AMOUNT_SYMBOL = SILVER_AMOUNT_SYMBOL
local SILVER_AMOUNT_TEXTURE = SILVER_AMOUNT_TEXTURE
local stringSub = string.sub
local tableConcat = table.concat
local UnitFullName = UnitFullName

---@class YAAHA: AceAddon, AceComm-3.0, AceConsole-3.0, AceSerializer-3.0, LibAboutPanel-2.0
---@field db AceDBObject-3.0!
---@field brokerObject table?
---@field FireAPIEvent fun(self: YAAHA, event: string, ...)
---@field GetOptions fun(self: YAAHA): table
---@field RefreshBrokerText fun(self: YAAHA)
local addon = LibStub("AceAddon-3.0"):NewAddon("YAAHA", "AceComm-3.0", "AceConsole-3.0", "AceSerializer-3.0", "LibAboutPanel-2.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local LibDataBroker = LibStub("LibDataBroker-1.1")
local LibDBIcon = LibStub("LibDBIcon-1.0")
local L = LibStub("AceLocale-3.0"):GetLocale("YAAHA")

local BROKER_ICON = "Interface\\Icons\\INV_Misc_Coin_01"

local defaults = {
	char = {
		fullScanCooldownExpires = nil,
		inventorySnapshot = {},
		ownedAuctions = {},
		pendingPurchases = {},
		saleLedger = {},
		syncSequence = 0,
	},
	factionrealm = {
		auctionDB = {},
		compressedAuctionDB = nil,
		auctionStats = {},
		disenchantList = {},
		knownProfessions = {
			["*"] = {},
		},
		inventoryPurchases = {},
		inventoryTransfers = {},
		millingList = {},
		prospectList = {},
		personalSales = {},
		realmSales = {},
		vendorList = {},
	},
	global = {
		alts = {
			["*"] = false,
		},
		disenchantData = {},
		limitedVendorItems = {},
		minimap = {
			hide = false,
			lock = true,
			lockOnDegree = true,
			minimapPos = 90,
			showInCompartment = true,
		},
		millingData = {},
		prospectData = {},
		vendorBuyPrices = {},
	},
	profile = {
		auctionHouseOpeningPage = "browse",
		coinDisplayStyle = "texture",
		formatLargeNumbers = true,
		includeBreakEvenDeals = true,
		profitConsiderations = {
			["*"] = true,
		},
		sendAndReceiveFactionRealm = true,
		sendAndReceiveRealm = true,
		sendAndReceiveOppositeFaction = true,
		trendDisplay = "percent",
		tooltip = {
			["02-minBuyout"] = true,
			["03-currentMarketValue"] = true,
			["04-midweekMarketValue"] = true,
			["12-vendorSell"] = true,
			["13-vendorBuy"] = true,
			["*"] = false,
		},
	},
	realm = {
		auctionDB = {},
		compressedAuctionDB = nil,
		auctionStats = {},
		disenchantList = {},
		millingList = {},
		prospectList = {},
		personalSales = {},
		realmSales = {},
		vendorFlipCOD = {},
		vendorFlipInventory = {},
		vendorFlipProfit = 0,
		vendorList = {},
	},
}

local char, factionrealm, global, profile, realm

function addon:RefreshBrokerText()
	if self.brokerObject then
		self.brokerObject.text = self:GetModule("VendorFlipTracking"):GetFormattedProfit()
	end
end

local function InitializeBroker()
	addon.brokerObject = LibDataBroker:NewDataObject("YAAHA", {
		type = "data source",
		tocname = "YAAHA",
		label = "YAAHA",
		icon = BROKER_ICON,
		text = addon:GetModule("VendorFlipTracking"):GetFormattedProfit(),
		OnClick = function()
			addon:OpenConfig()
		end,
		OnTooltipShow = function(tooltip)
			tooltip:AddLine("YAAHA")
			tooltip:AddLine(format(L["Vendor flip profit: %s"],
				addon:GetModule("VendorFlipTracking"):GetFormattedProfit()))
			tooltip:AddLine(L["Click for configuration."])
			tooltip:Show()
		end,
	})
	LibDBIcon:Register("YAAHA", addon.brokerObject, addon.db.global.minimap)
end

function addon:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("YAAHADB", defaults, true)
	self:GetModule("Storage"):RestoreAuctionData()

	-- Bidder information may omit the realm. Remember both forms for every
	-- character which loads YAAHA so vendor deals never compete with an account alt.
	local playerName, playerRealm = UnitFullName("player")
	self.db.global.alts[playerName] = true
	if playerRealm and playerRealm ~= "" then
		self.db.global.alts[playerName .. "-" .. playerRealm] = true
	end

	local options = self:GetOptions()
	options.args.profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
	options.args.profiles.order = 900

	LibStub("AceConfig-3.0"):RegisterOptionsTable("YAAHA", options)
	AceConfigDialog:AddToBlizOptions("YAAHA")

	self:RegisterChatCommand("yaaha", "OpenConfig")
	InitializeBroker()
end

function addon:OpenConfig()
	AceConfigDialog:Open("YAAHA")
end

function addon:FormatMoney(copper, showZero, numberColor)
	-- Keep semantic color on the numeric portion only. Denomination letters and
	-- coin textures retain their familiar gold, silver, and copper colors.
	local isNegative = copper < 0
	local magnitude = abs(copper)
	-- A real positive value must never disappear merely because its per-unit average
	-- is below one copper. All other values use the agreed half-up rounding rule.
	copper = magnitude > 0 and magnitude < 1 and 1 or floor(magnitude + 0.5)
	if isNegative and not numberColor then
		numberColor = "|cffff2020"
	end
	local gold = floor(copper / 10000)
	local silver = floor(copper % 10000 / 100)
	copper = copper % 100

	local values = {}
	local function AddValue(amount, symbol, texture, color, abbreviate, pad)
		if abbreviate and self.db.profile.formatLargeNumbers then
			amount = FormatLargeNumber(amount)
		elseif pad then
			amount = format("%02d", amount)
		end
		if #values == 0 and isNegative then
			amount = "-" .. amount
		end
		local displayedAmount = numberColor and numberColor .. amount .. "|r" or amount
		if self.db.profile.coinDisplayStyle == "texture" then
			-- Blizzard's texture globals include a numeric placeholder. Format them with
			-- zero, remove that zero, then prepend YAAHA's padded or abbreviated amount.
			values[#values + 1] = displayedAmount .. stringSub(format(texture, 0, 0, 0), 2)
		else
			values[#values + 1] = displayedAmount .. color .. symbol .. "|r"
		end
	end

	if gold > 0 then
		-- Blizzard's formatter abbreviates large values (for example, 12.3K), so it
		-- belongs on gold only; silver and copper always remain two-digit magnitudes.
		AddValue(gold, GOLD_AMOUNT_SYMBOL, GOLD_AMOUNT_TEXTURE, "|cffffd700", true)
	end
	if silver > 0 then
		AddValue(silver, SILVER_AMOUNT_SYMBOL, SILVER_AMOUNT_TEXTURE, "|cffc7c7cf", false, true)
	end
	if copper > 0 then
		AddValue(copper, COPPER_AMOUNT_SYMBOL, COPPER_AMOUNT_TEXTURE, "|cffeda55f", false, true)
	end
	if showZero and #values == 0 then
		AddValue(0, COPPER_AMOUNT_SYMBOL, COPPER_AMOUNT_TEXTURE, "|cffeda55f")
	end

	return tableConcat(values)
end