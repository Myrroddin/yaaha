local abs = math.abs
local COPPER_AMOUNT_SYMBOL = COPPER_AMOUNT_SYMBOL
local COPPER_AMOUNT_TEXTURE = COPPER_AMOUNT_TEXTURE
local floor = math.floor
local format = string.format
local FormatLargeNumber = FormatLargeNumber
local GetNormalizedRealmName = GetNormalizedRealmName
local GOLD_AMOUNT_SYMBOL = GOLD_AMOUNT_SYMBOL
local GOLD_AMOUNT_TEXTURE = GOLD_AMOUNT_TEXTURE
local LE_GAME_ERR_AUCTION_BID_OWN = LE_GAME_ERR_AUCTION_BID_OWN
local LE_GAME_ERR_AUCTION_DATABASE_ERROR = LE_GAME_ERR_AUCTION_DATABASE_ERROR
local LE_GAME_ERR_AUCTION_HIGHER_BID = LE_GAME_ERR_AUCTION_HIGHER_BID
local LE_GAME_ERR_ITEM_MAX_COUNT = LE_GAME_ERR_ITEM_MAX_COUNT
local LE_GAME_ERR_ITEM_NOT_FOUND = LE_GAME_ERR_ITEM_NOT_FOUND
local LE_GAME_ERR_NOT_ENOUGH_MONEY = LE_GAME_ERR_NOT_ENOUGH_MONEY
local LibStub = LibStub
local pairs = pairs
local SILVER_AMOUNT_SYMBOL = SILVER_AMOUNT_SYMBOL
local SILVER_AMOUNT_TEXTURE = SILVER_AMOUNT_TEXTURE
local stringMatch = string.match
local stringSub = string.sub
local tableConcat = table.concat
local tonumber = tonumber
local UnitFullName = UnitFullName

---@class YAAHA: AceAddon, AceComm-3.0, AceConsole-3.0, AceSerializer-3.0, LibAboutPanel-2.0
---@field db AceDBObject-3.0!
---@field brokerObject table?
---@field FireAPIEvent fun(self: YAAHA, event: string, ...)
---@field GetFirstMarketValue fun(self: YAAHA, data: table?): number?, string?
---@field GetItemID fun(self: YAAHA, link: string?): integer?
---@field GetOptions fun(self: YAAHA): table
---@field GetPlayerIdentity fun(self: YAAHA): string?, string?, string?
---@field IsAlt fun(self: YAAHA, name: string?, fullName?: string): boolean
---@field IsAuctionActionError fun(self: YAAHA, errorType: number): boolean
---@field IsDealProfitable fun(self: YAAHA, cost: number?, value: number?): boolean
---@field IsPlayerAuction fun(self: YAAHA, owner: string?, ownerFullName?: string): boolean
---@field RefreshBrokerText fun(self: YAAHA)
local addon = LibStub("AceAddon-3.0"):NewAddon("YAAHA", "AceComm-3.0", "AceConsole-3.0", "AceSerializer-3.0", "LibAboutPanel-2.0")
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
			["19-craftingValue"] = true,
			["20-craftingResults"] = true,
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

local playerName, playerRealm, playerFullName

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

	-- Store one canonical identity. IsAlt handles Blizzard results which omit the realm.
	local _, _, fullName = self:GetPlayerIdentity()
	if fullName then
		self.db.global.alts[fullName] = true
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

function addon:GetPlayerIdentity()
	if not playerFullName then
		playerName, playerRealm = UnitFullName("player")
		playerRealm = playerRealm or GetNormalizedRealmName()
		if playerName and playerRealm and playerRealm ~= "" then
			playerFullName = playerName .. "-" .. playerRealm
		end
	end
	return playerName, playerRealm, playerFullName
end

function addon:IsDealProfitable(cost, value)
	if not cost or cost <= 0 or not value or value <= 0 then
		return false
	end
	return self.db.profile.includeBreakEvenDeals and cost <= value or cost < value
end

function addon:IsPlayerAuction(owner, ownerFullName)
	local name, _, fullName = self:GetPlayerIdentity()
	return owner == name or owner == fullName or ownerFullName == fullName
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

-- Blizzard may report auction, mail, and trade characters as either name or
-- name-realm. YAAHA stores only full names, but accepts either form when
-- recognizing an account character whose realm suffix was omitted.
function addon:IsAlt(name, fullName)
	local alts = self.db.global.alts
	if fullName and alts[fullName] or name and alts[name] then
		return true
	end

	local shortName = name and name:match("^([^-]+)")
		or fullName and fullName:match("^([^-]+)")
	if not shortName then
		return false
	end

	for altFullName, isAlt in pairs(alts) do
		if isAlt and altFullName:match("^([^-]+)-") == shortName then
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