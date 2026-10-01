local abs = math.abs
local C_NameUtil = C_NameUtil
local COPPER_AMOUNT_SYMBOL = COPPER_AMOUNT_SYMBOL
local COPPER_AMOUNT_TEXTURE = COPPER_AMOUNT_TEXTURE
local floor = math.floor
local format = string.format
local FormatLargeNumber = FormatLargeNumber
local GetNormalizedRealmName = GetNormalizedRealmName
local GOLD_AMOUNT_SYMBOL = GOLD_AMOUNT_SYMBOL
local GOLD_AMOUNT_TEXTURE = GOLD_AMOUNT_TEXTURE
local LE_EXPANSION_CLASSIC = LE_EXPANSION_CLASSIC
local LE_EXPANSION_LEVEL_CURRENT = LE_EXPANSION_LEVEL_CURRENT
local LE_GAME_ERR_AUCTION_BID_OWN = LE_GAME_ERR_AUCTION_BID_OWN
local LE_GAME_ERR_AUCTION_DATABASE_ERROR = LE_GAME_ERR_AUCTION_DATABASE_ERROR
local LE_GAME_ERR_AUCTION_HIGHER_BID = LE_GAME_ERR_AUCTION_HIGHER_BID
local LE_GAME_ERR_ITEM_MAX_COUNT = LE_GAME_ERR_ITEM_MAX_COUNT
local LE_GAME_ERR_ITEM_NOT_FOUND = LE_GAME_ERR_ITEM_NOT_FOUND
local LE_GAME_ERR_NOT_ENOUGH_MONEY = LE_GAME_ERR_NOT_ENOUGH_MONEY
local LibStub = LibStub
local NameUtil = NameUtil
local pairs = pairs
local SILVER_AMOUNT_SYMBOL = SILVER_AMOUNT_SYMBOL
local SILVER_AMOUNT_TEXTURE = SILVER_AMOUNT_TEXTURE
local stringMatch = string.match
local stringSub = string.sub
local tableConcat = table.concat
local tonumber = tonumber
local UnitFactionGroup = UnitFactionGroup
local UnitFullName = UnitFullName
local WOW_PROJECT_ID = WOW_PROJECT_ID
local WOW_PROJECT_MAINLINE = WOW_PROJECT_MAINLINE
local WOW_PROJECT_MISTS_CLASSIC = WOW_PROJECT_MISTS_CLASSIC

---@class YAAHA: AceAddon, AceComm-3.0, AceConsole-3.0, AceSerializer-3.0, LibAboutPanel-2.0
---@field db AceDBObject-3.0!
---@field brokerObject table?
---@field FireAPIEvent fun(self: YAAHA, event: string, ...)
---@field GetCharacterKey fun(self: YAAHA): string?
---@field GetAuctionHouseTypeForScope fun(self: YAAHA, scope: string?): string?
---@field GetFirstMarketValue fun(self: YAAHA, data: table?): number?, string?
---@field GetItemID fun(self: YAAHA, link: string?): integer?
---@field GetOptions fun(self: YAAHA): table
---@field GetPlayerIdentity fun(self: YAAHA): string?, string?, string?
---@field GetRealmSales fun(self: YAAHA, auctionHouseType?: string): table, string
---@field IsAlt fun(self: YAAHA, name: string?, fullName?: string): boolean
---@field IsAuctionActionError fun(self: YAAHA, errorType: number): boolean
---@field IsDealProfitable fun(self: YAAHA, cost: number?, value: number?): boolean
---@field IsForever boolean
---@field UsesSharedAuctionHouse boolean
---@field IsPlayerAuction fun(self: YAAHA, owner: string?, ownerFullName?: string): boolean
---@field NormalizeCharacterName fun(self: YAAHA, name: string?, secondName?: string): string?
---@field RefreshBrokerText fun(self: YAAHA)
local addon = LibStub("AceAddon-3.0"):NewAddon("YAAHA", "AceComm-3.0", "AceConsole-3.0", "AceSerializer-3.0", "LibAboutPanel-2.0")

---@flavor-narrows forever
---@return boolean
local function IsForever()
	return (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE) and (LE_EXPANSION_LEVEL_CURRENT == LE_EXPANSION_CLASSIC)
end

addon.IsForever = IsForever()
addon.UsesSharedAuctionHouse = not addon.IsForever
	and (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE or WOW_PROJECT_ID == WOW_PROJECT_MISTS_CLASSIC)

local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local LibDataBroker = LibStub("LibDataBroker-1.1")
local LibDBIcon = LibStub("LibDBIcon-1.0")
local L = LibStub("AceLocale-3.0"):GetLocale("YAAHA")

local BROKER_ICON = "Interface\\Icons\\INV_Misc_Coin_01"
local MARKET_VALUE_FIELDS = {
	"currentMarketValue",
	"midweekMarketValue",
	"weeklyMarketValue",
	"biweeklyMarketValue",
	"monthlyMarketValue",
	"bimonthlyMarketValue",
}

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
			["*"] = {
				["*"] = {}
			},
		},
		inventoryPurchases = {},
		inventoryTransfers = {},
		millingList = {},
		prospectList = {},
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
		synchronization = {
			currentFaction = true,
			neutral = true,
			oppositeFaction = true,
			shared = true,
		},
		trendDisplay = "percent",
		tooltip = {
			["02-minBuyout"] = true,
			["03-currentMarketValue"] = true,
			["04-midweekMarketValue"] = true,
			["12-vendorSell"] = true,
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
		sales = {
			auctionHouses = {
				["*"] = {},
			},
			personal = {},
		},
		vendorFlip = {
			cod = {},
			inventory = {},
			profit = 0,
		},
		vendorList = {},
	},
}

local playerFaction = UnitFactionGroup("player")
local oppositeFaction = playerFaction == "Alliance" and "Horde" or "Alliance"
local playerName, playerSecondName, playerFullName

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
	-- YAAHA keeps lockOnDegree beside LibDBIcon's keys. The library accepts extra
	-- addon-owned fields, although WoWLua-LS's narrow DB definition does not.
	---@diagnostic disable-next-line: inject-field
	LibDBIcon:Register("YAAHA", addon.brokerObject, addon.db.global.minimap)
end

function addon:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("YAAHADB", defaults, true)
	self:GetModule("Storage"):RestoreAuctionData()

	-- YAAHA's identity key follows the form Blizzard uses in links and messages:
	-- name-realm on existing clients and firstName-surname on Forever.
	local characterKey = self:GetCharacterKey()
	if characterKey then
		self.db.global.alts[characterKey] = true
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

function addon:GetFirstMarketValue(data)
	if not data then
		return
	end
	for index = 1, #MARKET_VALUE_FIELDS do
		local field = MARKET_VALUE_FIELDS[index]
		local value = data[field]
		if value and value > 0 then
			return value, field
		end
	end
end

function addon:GetItemID(link)
	local itemID = link and stringMatch(link, "item:(%d+)")
	return itemID and tonumber(itemID)
end

function addon:GetCharacterKey()
	local _, _, fullName = self:GetPlayerIdentity()
	return fullName
end

function addon:GetAuctionHouseTypeForScope(scope)
	if self.UsesSharedAuctionHouse then
		return "Shared"
	elseif scope == "realm" then
		return "Neutral"
	elseif scope == "factionrealm" then
		return playerFaction
	elseif scope == "opposite" then
		return oppositeFaction
	end
end

function addon:GetRealmSales(auctionHouseType)
	if self.UsesSharedAuctionHouse then
		auctionHouseType = "Shared"
	elseif auctionHouseType ~= "Alliance" and auctionHouseType ~= "Horde"
		and auctionHouseType ~= "Neutral" then
		auctionHouseType = playerFaction
	end
	return self.db.realm.sales.auctionHouses[auctionHouseType], auctionHouseType
end

function addon:NormalizeCharacterName(name, secondName)
	if not name or name == "" then
		return
	end
	if self.IsForever then
		local fullName = secondName and secondName ~= ""
			and NameUtil.GetFullNameWithoutRealm(name, secondName) or name
		---@diagnostic disable-next-line: wrong-flavor-api
		return C_NameUtil.ReplaceSurnameSeparatorWithLinkSeparator(fullName)
	end
	return secondName and secondName ~= "" and name .. "-" .. secondName or name
end

function addon:GetPlayerIdentity()
	if not playerFullName then
		playerName, playerSecondName = UnitFullName("player")
		if not self.IsForever then
			playerSecondName = playerSecondName or GetNormalizedRealmName()
		end
		playerFullName = self:NormalizeCharacterName(playerName, playerSecondName)
	end
	return playerName, playerSecondName, playerFullName
end

function addon:IsDealProfitable(cost, value)
	if not cost or cost <= 0 or not value or value <= 0 then
		return false
	end
	return self.db.profile.includeBreakEvenDeals and cost <= value or cost < value
end

function addon:IsPlayerAuction(owner, ownerFullName)
	local name, _, fullName = self:GetPlayerIdentity()
	local normalizedOwner = self:NormalizeCharacterName(ownerFullName or owner)
	return normalizedOwner == fullName or not self.IsForever and owner == name
		or self:IsAlt(owner, ownerFullName)
end

function addon:IsAuctionActionError(errorType)
	return errorType == LE_GAME_ERR_AUCTION_BID_OWN
		or errorType == LE_GAME_ERR_AUCTION_DATABASE_ERROR
		or errorType == LE_GAME_ERR_AUCTION_HIGHER_BID
		or errorType == LE_GAME_ERR_ITEM_MAX_COUNT
		or errorType == LE_GAME_ERR_ITEM_NOT_FOUND
		or errorType == LE_GAME_ERR_NOT_ENOUGH_MONEY
end

-- Existing clients can omit the realm for same-realm characters, so their short
-- names remain a necessary fallback. Forever first names are not unique; accept
-- only its complete, link-form firstName-surname identity.
function addon:IsAlt(name, fullName)
	local alts = self.db.global.alts
	local normalizedFullName = self:NormalizeCharacterName(fullName)
	local normalizedName = self:NormalizeCharacterName(name)
	if normalizedFullName and alts[normalizedFullName]
		or normalizedName and alts[normalizedName] then
		return true
	end
	if self.IsForever then
		return false
	end

	local reportedName = normalizedName or normalizedFullName
	local shortName = reportedName and reportedName:match("^([^-]+)")
	if not shortName then
		return false
	end

	for altFullName, isAlt in pairs(alts) do
		local altName = altFullName:match("^([^-]+)")
		if isAlt and altName == shortName then
			return true
		end
	end
	return false
end

function addon:RefreshBrokerText()
	if self.brokerObject then
		self.brokerObject.text = self:GetModule("VendorFlipTracking"):GetFormattedProfit()
	end
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
