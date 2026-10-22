-- Initializes YAAHA's shared client flags, saved-data defaults, identity helpers,
-- rounding rules, and money formatting.

local abs = math.abs
local COPPER_AMOUNT_SYMBOL = COPPER_AMOUNT_SYMBOL
local COPPER_AMOUNT_TEXTURE = COPPER_AMOUNT_TEXTURE
local DECIMAL_SEPERATOR = DECIMAL_SEPERATOR or "."
local Enum = Enum
local floor = math.floor
local FACTION_ALLIANCE = FACTION_ALLIANCE
local FACTION_HORDE = FACTION_HORDE
local format = string.format
local FormatLargeNumber = FormatLargeNumber
local GetNormalizedRealmName = GetNormalizedRealmName
local GetServerTime = GetServerTime
local GOLD_AMOUNT_SYMBOL = GOLD_AMOUNT_SYMBOL
local GOLD_AMOUNT_TEXTURE = GOLD_AMOUNT_TEXTURE
local LE_GAME_ERR_AUCTION_BID_OWN = LE_GAME_ERR_AUCTION_BID_OWN
local LE_GAME_ERR_AUCTION_DATABASE_ERROR = LE_GAME_ERR_AUCTION_DATABASE_ERROR
local LE_GAME_ERR_AUCTION_HIGHER_BID = LE_GAME_ERR_AUCTION_HIGHER_BID
local LE_GAME_ERR_ITEM_MAX_COUNT = LE_GAME_ERR_ITEM_MAX_COUNT
local LE_GAME_ERR_ITEM_NOT_FOUND = LE_GAME_ERR_ITEM_NOT_FOUND
local LE_GAME_ERR_NOT_ENOUGH_MONEY = LE_GAME_ERR_NOT_ENOUGH_MONEY
local LibStub = LibStub
local IsPlayerNeutral = IsPlayerNeutral
local NameUtil = NameUtil
local random = math.random
local rawset = rawset
local SILVER_AMOUNT_SYMBOL = SILVER_AMOUNT_SYMBOL
local SILVER_AMOUNT_TEXTURE = SILVER_AMOUNT_TEXTURE
local stringMatch = string.match
local stringSub = string.sub
local tableConcat = table.concat
local tonumber = tonumber
local UnitFactionGroup = UnitFactionGroup
local UnitFullName = UnitFullName
local WOW_PROJECT_BURNING_CRUSADE_CLASSIC = WOW_PROJECT_BURNING_CRUSADE_CLASSIC
local WOW_PROJECT_CAMELOT = WOW_PROJECT_CAMELOT
local WOW_PROJECT_CLASSIC = WOW_PROJECT_CLASSIC
local WOW_PROJECT_ID = WOW_PROJECT_ID
local WOW_PROJECT_MAINLINE = WOW_PROJECT_MAINLINE
local WOW_PROJECT_MISTS_CLASSIC = WOW_PROJECT_MISTS_CLASSIC
local WOW_PROJECT_WRATH_CLASSIC = WOW_PROJECT_WRATH_CLASSIC

---@class YAAHA: AceAddon, AceComm-3.0, AceConsole-3.0, AceEvent-3.0, AceSerializer-3.0, LibAboutPanel-2.0
---@field db AceDBObject-3.0!
---@field FireAPIEvent fun(self: YAAHA, event: string, ...)
---@field GetOptions fun(self: YAAHA): table
---@field GetSyncSourceID fun(self: YAAHA): string
---@field localizedPlayerFaction string
---@field oppositeFaction? "Alliance"|"Horde"
---@field oppositeFactionName? string
---@field playerFaction "Alliance"|"Horde"|"Neutral"
local addon = LibStub("AceAddon-3.0"):NewAddon("YAAHA", "AceComm-3.0", "AceConsole-3.0", "AceEvent-3.0", "AceSerializer-3.0", "LibAboutPanel-2.0")

addon.isClassicEra = WOW_PROJECT_ID == WOW_PROJECT_CLASSIC
addon.isTBC = WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC
addon.isWrath = WOW_PROJECT_ID == WOW_PROJECT_WRATH_CLASSIC
addon.isMists = WOW_PROJECT_ID == WOW_PROJECT_MISTS_CLASSIC
addon.isForever = WOW_PROJECT_ID == WOW_PROJECT_CAMELOT
addon.isStandard = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
local isForever = addon.isForever
local isMists = addon.isMists
local isStandard = addon.isStandard
addon.usesSharedAuctionHouse = isStandard or isMists
addon.auctionHouseMinimumPrice = addon.usesSharedAuctionHouse and 100 or 1
addon.alchemySkillLineID = 171
addon.base64Variant = Enum.Base64Variant.StandardUrlSafe
addon.compressionMethod = Enum.CompressionMethod.Zlib
addon.marketHistoryDays = 60
addon.negativeNumberColor = "|cffff2020"
addon.positiveNumberColor = "|cff20ff20"
addon.secondsPerDay = 24 * 60 * 60
addon.saleHistoryDays = 60
addon.saleHistorySeconds = addon.saleHistoryDays * addon.secondsPerDay

function addon:RefreshPlayerFaction()
	self.playerFaction, self.localizedPlayerFaction = UnitFactionGroup("player")
	self.oppositeFaction = self.playerFaction == "Alliance" and "Horde"
		or self.playerFaction == "Horde" and "Alliance" or nil
	self.oppositeFactionName = self.oppositeFaction == "Alliance" and FACTION_ALLIANCE
		or self.oppositeFaction == "Horde" and FACTION_HORDE or nil
end

addon:RefreshPlayerFaction()

local usesSharedAuctionHouse = addon.usesSharedAuctionHouse

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

local function NormalizeNumDecimals(value)
	value = tonumber(value)
	if not value or value ~= value then
		return 2
	end
	return value < 1 and 1 or value > 3 and 3 or floor(value + 0.5)
end

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
		collectorSyncData = {
			disenchantData = {},
			millingData = {},
			prospectData = {},
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
		syncSourceID = nil,
		vendorBuyPrices = {},
	},
	profile = {
		auctionHouseOpeningPage = "browse",
		coinDisplayStyle = "texture",
		disenchantingDealThreshold = 0.5,
		formatLargeNumbers = true,
		includeBreakEvenVendorDeals = true,
		millingDealThreshold = 0.5,
		numDecimals = 2,
		profitConsiderations = {
			["*"] = true,
		},
		prospectingDealThreshold = 0.5,
		syncData = true,
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
			trackingStarted = {},
		},
		vendorFlip = {
			cod = {},
			inventory = {},
			profit = 0,
		},
		vendorList = {},
	},
}

local playerName, playerSecondName, playerFullName

local function InitializeBroker()
	---@diagnostic disable-next-line: inject-field
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

	-- YAAHA stores Blizzard's display identity: name-realm on realm-based clients
	-- and firstName surname on Forever. Link-form inputs are normalized below.
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

	-- A neutral Pandaren remains in the same UI session after choosing a faction.
	-- Refresh shared faction state once Blizzard confirms that choice.
	if (isMists or isStandard) and IsPlayerNeutral() then
		self:RegisterEvent("NEUTRAL_FACTION_SELECT_RESULT")
	end
end

function addon:OpenConfig()
	AceConfigDialog:Open("YAAHA")
end

function addon:RoundDecimal(value, numDecimals)
	if type(value) ~= "number" or value ~= value then
		return
	end
	if value == 0 then
		return 0
	end

	numDecimals = NormalizeNumDecimals(numDecimals or self.db.profile.numDecimals)
	local factor = 10 ^ numDecimals
	local magnitude = abs(value)
	local rounded = floor(magnitude * factor + 0.5000000001) / factor
	-- Preserve a known nonzero value even when it is smaller than the selected
	-- display precision. Zero remains distinguishable from a very small value.
	if rounded == 0 then
		rounded = 1 / factor
	end
	return value < 0 and -rounded or rounded
end

function addon:FormatDecimal(value)
	local numDecimals = NormalizeNumDecimals(self.db.profile.numDecimals)
	local rounded = self:RoundDecimal(value, numDecimals)
	if rounded == nil then
		return
	end

	local text = format("%." .. numDecimals .. "f", rounded)
	text = text:gsub("0+$", "")
	text = text:gsub("%.$", "")
	return DECIMAL_SEPERATOR == "." and text or text:gsub("%.", DECIMAL_SEPERATOR)
end

function addon:RoundMoney(copper, auctionPrice)
	if type(copper) ~= "number" or copper ~= copper then
		return
	end
	if copper == 0 then
		return 0
	end

	local isNegative = copper < 0
	local rounded = floor(abs(copper) + 0.5)
	-- Only an actual auction price is subject to the auction house's
	-- minimum price. All other money rounds to whole copper, and a known nonzero
	-- value remains distinguishable from an exact zero.
	local minimum = auctionPrice and self.auctionHouseMinimumPrice or 1
	if rounded < minimum then
		rounded = minimum
	end
	return isNegative and -rounded or rounded
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

function addon:GetCurrentMarketValue(data)
	local value = data and data.currentMarketValue
	return value and value > 0 and value or nil
end

function addon:GetItemID(link)
	local itemID = link and stringMatch(link, "item:(%d+)")
	return itemID and tonumber(itemID)
end

function addon:GetCharacterKey()
	local _, _, fullName = self:GetPlayerIdentity()
	return fullName
end

function addon:GetSyncSourceID()
	local sourceID = self.db.global.syncSourceID
	if type(sourceID) ~= "string" or sourceID == "" then
		-- The opaque ID deduplicates relayed shared data without disclosing a character.
		sourceID = format("%x-%x-%x", GetServerTime(),
			random(100000000, 999999999), random(100000000, 999999999))
		self.db.global.syncSourceID = sourceID
	end
	return sourceID
end

function addon:GetAuctionHouseTypeForScope(scope)
	if usesSharedAuctionHouse then
		return "Shared"
	elseif scope == "realm" then
		return "Neutral"
	elseif scope == "factionrealm" then
		return self.playerFaction
	elseif scope == "opposite" then
		return self.oppositeFaction
	end
end

function addon:GetRealmSales(auctionHouseType)
	if usesSharedAuctionHouse then
		auctionHouseType = "Shared"
	elseif auctionHouseType ~= "Alliance" and auctionHouseType ~= "Horde"
		and auctionHouseType ~= "Neutral" then
		auctionHouseType = self.playerFaction
	end
	return self.db.realm.sales.auctionHouses[auctionHouseType], auctionHouseType
end

function addon:NEUTRAL_FACTION_SELECT_RESULT(event, success)
	if not success then
		return
	end

	self:RefreshPlayerFaction()
	if self.playerFaction ~= "Alliance" and self.playerFaction ~= "Horde" then
		return
	end

	-- AceDB establishes factionrealm when the database is created. Rebind YAAHA's
	-- active section because faction selection does not reload the user interface.
	-- Neutral starting areas have no auction houses, so there is no neutral market
	-- state to preserve or restore during this transition.
	local previousFactionrealmKey = self.db.keys.factionrealm
	local factionrealmKey = self.playerFaction .. " - " .. self.db.keys.realm
	if previousFactionrealmKey ~= factionrealmKey then
		local factionrealmregionKey = self.db.keys.factionrealmregion
		self.db.keys.faction = self.playerFaction
		self.db.keys.factionrealm = factionrealmKey
		if factionrealmregionKey then
			self.db.keys.factionrealmregion = factionrealmKey
				.. factionrealmregionKey:sub(#previousFactionrealmKey + 1)
		end
		rawset(self.db, "faction", nil)
		rawset(self.db, "factionrealm", nil)
		rawset(self.db, "factionrealmregion", nil)
	end
	self:UnregisterEvent(event)
end

function addon:NormalizeCharacterName(name, secondName)
	if not name or name == "" then
		return
	end
	-- Mail, auction, trade, sync, profession, and alt records all pass through this
	-- one resolver so every subsystem compares the same canonical identity.
	if isForever then
		-- Forever identities require both Given and Surname. Display-form names use
		-- a space while links can use a hyphen; normalize both to Blizzard's display
		-- form, and never guess a missing surname from another character.
		local firstName, surname = name:match("^([^%s%-]+)[%s%-](.+)$")
		if not firstName or not surname then
			firstName = name
			surname = secondName
		end
		return surname and surname ~= "" and NameUtil.GetFullNameWithoutRealm(firstName, surname) or nil
	end

	-- A missing realm suffix means the current realm. Canonicalizing it here makes
	-- Name and Name-CurrentRealm equal without conflating Name-OtherRealm.
	local characterName, realmName = name:match("^([^-]+)%-(.+)$")
	if characterName and realmName then
		return characterName .. "-" .. realmName
	end
	realmName = secondName and secondName ~= "" and secondName or GetNormalizedRealmName()
	return realmName and realmName ~= "" and name .. "-" .. realmName or nil
end

function addon:GetPlayerIdentity()
	if not playerFullName then
		playerName, playerSecondName = UnitFullName("player")
		if not isForever then
			playerSecondName = playerSecondName or GetNormalizedRealmName()
		end
		playerFullName = self:NormalizeCharacterName(playerName, playerSecondName)
	end
	return playerName, playerSecondName, playerFullName
end

function addon:IsVendorDealProfitable(cost, value)
	if not cost or cost <= 0 or not value or value <= 0 then
		return false
	end
	-- Deal searches evaluate YAAHA as the buyer. Compare against the raw vendor
	-- return; auction-house seller fees do not apply.
	return self.db.profile.includeBreakEvenVendorDeals and cost <= value or cost < value
end

function addon:IsBreakdownDeal(cost, value, threshold)
	if not cost or cost <= 0 or not value or value <= 0 then
		return false
	end
	threshold = tonumber(threshold)
	if not threshold or threshold ~= threshold then
		return false
	end
	-- Disenchanting, prospecting, and milling searches compare their purchase cost
	-- with the raw expected material value. No auction-house seller fee applies.
	threshold = threshold < 0.01 and 0.01 or threshold > 1 and 1 or threshold
	return cost <= value * threshold
end

function addon:IsPlayerAuction(owner, ownerFullName)
	local _, _, fullName = self:GetPlayerIdentity()
	local normalizedOwner = self:NormalizeCharacterName(ownerFullName or owner)
	return normalizedOwner == fullName or self:IsAlt(owner, ownerFullName)
end

function addon:IsAuctionActionError(errorType)
	return errorType == LE_GAME_ERR_AUCTION_BID_OWN
		or errorType == LE_GAME_ERR_AUCTION_DATABASE_ERROR
		or errorType == LE_GAME_ERR_AUCTION_HIGHER_BID
		or errorType == LE_GAME_ERR_ITEM_MAX_COUNT
		or errorType == LE_GAME_ERR_ITEM_NOT_FOUND
		or errorType == LE_GAME_ERR_NOT_ENOUGH_MONEY
end

-- Realm-based short names resolve to the current realm. Forever first names are
-- not unique, so only a complete Given Surname identity can match an alt.
function addon:IsAlt(name, fullName)
	local alts = self.db.global.alts
	local normalizedFullName = self:NormalizeCharacterName(fullName)
	local normalizedName = self:NormalizeCharacterName(name)
	return normalizedFullName and alts[normalizedFullName] == true or normalizedName and alts[normalizedName] == true or false
end

function addon:RefreshBrokerText()
	if self.brokerObject then
		self.brokerObject.text = self:GetModule("VendorFlipTracking"):GetFormattedProfit()
	end
end

local function AddMoneyValue(values, isNegative, numberColor, amount, symbol, texture, color, abbreviate, pad)
	if abbreviate and addon.db.profile.formatLargeNumbers then
		amount = FormatLargeNumber(amount)
	elseif pad then
		amount = format("%02d", amount)
	end
	if #values == 0 and isNegative then
		amount = "-" .. amount
	end
	local displayedAmount = numberColor and numberColor .. amount .. "|r" or amount
	if addon.db.profile.coinDisplayStyle == "texture" then
		-- Blizzard's texture globals include a numeric placeholder. Format them with
		-- zero, remove that zero, then prepend YAAHA's padded or abbreviated amount.
		values[#values + 1] = displayedAmount .. stringSub(format(texture, 0, 0, 0), 2)
	else
		values[#values + 1] = displayedAmount .. color .. symbol .. "|r"
	end
end

function addon:FormatMoney(copper, showZero, numberColor, auctionPrice)
	-- Keep semantic color on the numeric portion only. Denomination letters and
	-- coin textures retain their familiar gold, silver, and copper colors.
	copper = self:RoundMoney(copper, auctionPrice)
	if copper == nil then
		return ""
	end
	local isNegative = copper < 0
	copper = abs(copper)
	if isNegative and not numberColor then
		numberColor = "|cffff2020"
	end
	local gold = floor(copper / 10000)
	local silver = floor(copper % 10000 / 100)
	copper = copper % 100

	local values = {}
	if gold > 0 then
		-- Blizzard's formatter abbreviates large values (for example, 12.3K), so it
		-- belongs on gold only; silver and copper always remain two-digit magnitudes.
		AddMoneyValue(values, isNegative, numberColor, gold,
			GOLD_AMOUNT_SYMBOL, GOLD_AMOUNT_TEXTURE, "|cffffd700", true)
	end
	if silver > 0 then
		AddMoneyValue(values, isNegative, numberColor, silver,
			SILVER_AMOUNT_SYMBOL, SILVER_AMOUNT_TEXTURE, "|cffc7c7cf", false, true)
	end
	if copper > 0 then
		AddMoneyValue(values, isNegative, numberColor, copper,
			COPPER_AMOUNT_SYMBOL, COPPER_AMOUNT_TEXTURE, "|cffeda55f", false, true)
	end
	if showZero and #values == 0 then
		AddMoneyValue(values, isNegative, numberColor, 0,
			COPPER_AMOUNT_SYMBOL, COPPER_AMOUNT_TEXTURE, "|cffeda55f")
	end

	return tableConcat(values)
end