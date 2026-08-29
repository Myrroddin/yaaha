local floor = math.floor
local LibStub = LibStub
local next = next
local type = type
local UnitFactionGroup = UnitFactionGroup

local playerFaction = UnitFactionGroup("player")
local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local saleCollector = addon:GetModule("SaleCollector")
local disenchantingData = addon:GetModule("DisenchantingData")

-- API versions are independent of addon releases. Increment this only when a
-- change to the public contract requires consumers to distinguish API behavior.
local API_VERSION = 1

---@alias YAAHA_API.AuctionHouseType "Alliance"|"Horde"|"Neutral"
---@alias YAAHA_API.DataUpdateSource "scan"|"sync"
---@alias YAAHA_API.DataUpdateEvent "AUCTION_HOUSE_DATA_UPDATED"
---@alias YAAHA_API.MarketValueSource "currentMarketValue"|"midweekMarketValue"|"weeklyMarketValue"|"biweeklyMarketValue"|"monthlyMarketValue"|"bimonthlyMarketValue"

---@class YAAHA_API.ItemData
---@field auctionCount? integer Number of listings in the current snapshot.
---@field auctionQuantity? integer Number of individual items in the current snapshot.
---@field lastScan? integer Server timestamp of the current item snapshot.
---@field minBid? integer Lowest payable per-unit bid in copper.
---@field minBuyout? integer Lowest per-unit buyout in copper.
---@field currentMarketValue? integer Current-scan market value in copper.
---@field midweekMarketValue? integer Weighted rolling three-day market value in copper.
---@field weeklyMarketValue? integer Weighted rolling seven-day market value in copper.
---@field biweeklyMarketValue? integer Weighted rolling fourteen-day market value in copper.
---@field monthlyMarketValue? integer Weighted rolling thirty-day market value in copper.
---@field bimonthlyMarketValue? integer Weighted rolling sixty-day market value in copper.

---@class YAAHA_API.AuctionHouseStats
---@field lastScan integer Server timestamp of the latest complete snapshot.
---@field totalItems integer Number of distinct item IDs in the snapshot.
---@field totalListings integer Number of auction listings in the snapshot.

---@class YAAHA_API.DisenchantMaterial
---@field itemID integer Resulting enchanting-material item ID.
---@field chance number Decimal probability of receiving this material.
---@field minQuantity integer Minimum possible quantity.
---@field maxQuantity integer Maximum possible quantity.
---@field expectedQuantity number Probability-adjusted expected quantity.

---@class YAAHA_API.DisenchantResults
---@field requiredSkill integer Required Enchanting skill.
---@field sampleCount integer Number of learned Wrath observations used.
---@field results YAAHA_API.DisenchantMaterial[] Possible material results.

---@class YAAHA_API.PricedDisenchantMaterial: YAAHA_API.DisenchantMaterial
---@field marketValue? integer Selected per-unit material value in copper.
---@field priceSource? YAAHA_API.MarketValueSource Market-value source used for this material.
---@field expectedValue? integer Probability-adjusted material value in copper.
---@field missingPrice boolean Whether no positive material market value was available.

---@class YAAHA_API.PricedDisenchantResults
---@field expectedValue? integer Complete expected disenchant value in copper.
---@field requiredSkill integer Required Enchanting skill.
---@field sampleCount integer Number of learned Wrath observations used.
---@field results YAAHA_API.PricedDisenchantMaterial[] Priced material results.

---@alias YAAHA_API.DataUpdatedCallback fun(event: YAAHA_API.DataUpdateEvent, auctionHouseType: YAAHA_API.AuctionHouseType, source: YAAHA_API.DataUpdateSource)

-- YAAHA's public API is a normal global table rather than a LibStub library.
-- Keep the surface deliberately small: functions are added only when their
-- backing data and return contracts are ready for other addons to depend upon.
---@class YAAHA_API
---@field version integer Public API version.
---@field RegisterCallback fun(receiver: any, event: YAAHA_API.DataUpdateEvent, method?: string|YAAHA_API.DataUpdatedCallback, arg?: any)
---@field UnregisterCallback fun(receiver: any, event: YAAHA_API.DataUpdateEvent)
---@field UnregisterAllCallbacks fun(receiver: any)
local API = {
	version = API_VERSION,
}
---@type YAAHA_API
---@diagnostic disable-next-line: create-global
YAAHA_API = API

local callbackRegistry = LibStub("CallbackHandler-1.0"):New(API)

-- Data producers call this only after committing a complete update. Consumers
-- can therefore query the public API immediately from inside their callback.
function addon:FireAPIEvent(event, ...)
	callbackRegistry:Fire(event, ...)
end

---@return integer version
function API.GetVersion()
	return API_VERSION
end

local copperFields = {
	"minBid",
	"minBuyout",
	"currentMarketValue",
	"midweekMarketValue",
	"weeklyMarketValue",
	"biweeklyMarketValue",
	"monthlyMarketValue",
	"bimonthlyMarketValue",
}

local function GetAuctionScope(auctionHouseType)
	auctionHouseType = auctionHouseType or playerFaction
	if auctionHouseType == "Neutral" then
		return "realm"
	end
	if auctionHouseType == playerFaction then
		return "factionrealm"
	end
end

local function GetAuctionDB(auctionHouseType)
	local scope = GetAuctionScope(auctionHouseType)
	return scope and addon.db[scope].auctionDB
end

local function NormalizeCopper(value)
	if type(value) ~= "number" or value <= 0 then
		return nil
	end

	-- Preserve any real positive value as at least one copper; otherwise use the
	-- conventional half-up rule instead of Lua's platform-dependent formatting.
	return value < 1 and 1 or floor(value + 0.5)
end

local function NormalizeQuantity(value)
	if type(value) ~= "number" or value < 0 then
		return nil
	end

	return floor(value + 0.5)
end

local function NormalizeRate(value)
	if type(value) ~= "number" or value < 0 or value > 1 then
		return nil
	end

	return floor(value * 1000 + 0.5) / 1000
end

local function GetItemSource(itemID, auctionHouseType)
	if type(itemID) ~= "number" or itemID <= 0 or itemID ~= floor(itemID) then
		return nil
	end

	local auctionDB = GetAuctionDB(auctionHouseType)
	return auctionDB and auctionDB[itemID]
end

local function GetItemValue(itemID, auctionHouseType, field)
	local data = API.GetItemData(itemID, auctionHouseType)
	return data and data[field]
end

local function GetRealmSaleData(itemID, auctionHouseType)
	if type(itemID) ~= "number" or itemID <= 0 or itemID ~= floor(itemID) then
		return
	end
	auctionHouseType = auctionHouseType or playerFaction
	local scope = auctionHouseType == "Neutral" and "realm"
		or auctionHouseType == playerFaction and "factionrealm"
	if scope then
		return saleCollector:GetRealmSaleData(itemID, scope)
	end
end

---@param itemID integer
---@param auctionHouseType? YAAHA_API.AuctionHouseType
---@return YAAHA_API.ItemData? data
function API.GetItemData(itemID, auctionHouseType)
	local source = GetItemSource(itemID, auctionHouseType)
	if not source then
		return nil
	end

	-- Copy only the stable, calculated public surface. In particular, consumers
	-- cannot mutate YAAHA's database or inspect its raw observation history.
	local data = {}
	for index = 1, #copperFields do
		local field = copperFields[index]
		data[field] = NormalizeCopper(source[field])
	end
	if type(source.auctionQuantity) == "number" and source.auctionQuantity > 0 then
		data.auctionQuantity = NormalizeQuantity(source.auctionQuantity)
	end
	if type(source.auctionCount) == "number" and source.auctionCount > 0 then
		data.auctionCount = NormalizeQuantity(source.auctionCount)
	end
	if type(source.lastScan) == "number" and source.lastScan > 0 then
		data.lastScan = NormalizeQuantity(source.lastScan)
	end

	return next(data) and data or nil
end

---@param itemID integer
---@param auctionHouseType? YAAHA_API.AuctionHouseType
---@return integer? minBid
function API.GetMinBid(itemID, auctionHouseType)
	return GetItemValue(itemID, auctionHouseType, "minBid")
end

---@param itemID integer
---@param auctionHouseType? YAAHA_API.AuctionHouseType
---@return integer? auctionQuantity
function API.GetAuctionQuantity(itemID, auctionHouseType)
	return GetItemValue(itemID, auctionHouseType, "auctionQuantity")
end

---@param itemID integer
---@param auctionHouseType? YAAHA_API.AuctionHouseType
---@return integer? auctionCount
function API.GetAuctionCount(itemID, auctionHouseType)
	return GetItemValue(itemID, auctionHouseType, "auctionCount")
end

---@param itemID integer
---@param auctionHouseType? YAAHA_API.AuctionHouseType
---@return integer? minBuyout
function API.GetMinBuyout(itemID, auctionHouseType)
	return GetItemValue(itemID, auctionHouseType, "minBuyout")
end

---@param itemID integer
---@param auctionHouseType? YAAHA_API.AuctionHouseType
---@return integer? currentMarketValue
function API.GetCurrentMarketValue(itemID, auctionHouseType)
	return GetItemValue(itemID, auctionHouseType, "currentMarketValue")
end

---@param itemID integer
---@param auctionHouseType? YAAHA_API.AuctionHouseType
---@return integer? midweekMarketValue
function API.GetMidweekMarketValue(itemID, auctionHouseType)
	return GetItemValue(itemID, auctionHouseType, "midweekMarketValue")
end

---@param itemID integer
---@param auctionHouseType? YAAHA_API.AuctionHouseType
---@return integer? weeklyMarketValue
function API.GetWeeklyMarketValue(itemID, auctionHouseType)
	return GetItemValue(itemID, auctionHouseType, "weeklyMarketValue")
end

---@param itemID integer
---@param auctionHouseType? YAAHA_API.AuctionHouseType
---@return integer? biweeklyMarketValue
function API.GetBiweeklyMarketValue(itemID, auctionHouseType)
	return GetItemValue(itemID, auctionHouseType, "biweeklyMarketValue")
end

---@param itemID integer
---@param auctionHouseType? YAAHA_API.AuctionHouseType
---@return integer? monthlyMarketValue
function API.GetMonthlyMarketValue(itemID, auctionHouseType)
	return GetItemValue(itemID, auctionHouseType, "monthlyMarketValue")
end

---@param itemID integer
---@param auctionHouseType? YAAHA_API.AuctionHouseType
---@return integer? bimonthlyMarketValue
function API.GetBimonthlyMarketValue(itemID, auctionHouseType)
	return GetItemValue(itemID, auctionHouseType, "bimonthlyMarketValue")
end

---@param itemID integer
---@param auctionHouseType? YAAHA_API.AuctionHouseType
---@return integer? lastScan
function API.GetLastScanTime(itemID, auctionHouseType)
	return GetItemValue(itemID, auctionHouseType, "lastScan")
end

---@param auctionHouseType? YAAHA_API.AuctionHouseType
---@return YAAHA_API.AuctionHouseStats? stats
function API.GetAuctionHouseStats(auctionHouseType)
	local scope = GetAuctionScope(auctionHouseType)
	local source = scope and addon.db[scope].auctionStats
	if not source or type(source.lastScan) ~= "number" or source.lastScan <= 0
		or type(source.totalItems) ~= "number" or source.totalItems < 0
		or type(source.totalListings) ~= "number" or source.totalListings < 0 then
		return nil
	end

	return {
		lastScan = floor(source.lastScan + 0.5),
		totalItems = floor(source.totalItems + 0.5),
		totalListings = floor(source.totalListings + 0.5),
	}
end

---@param itemID integer
---@param auctionHouseType? YAAHA_API.AuctionHouseType
---@return number? realmSaleRate
function API.GetRealmSaleRate(itemID, auctionHouseType)
	local rate = GetRealmSaleData(itemID, auctionHouseType)
	return NormalizeRate(rate)
end

---@param itemID integer
---@param auctionHouseType? YAAHA_API.AuctionHouseType
---@return integer? realmSoldPerDay
function API.GetRealmSoldPerDay(itemID, auctionHouseType)
	local _, sold = GetRealmSaleData(itemID, auctionHouseType)
	return NormalizeQuantity(sold)
end

---@param itemID integer
---@param auctionHouseType? YAAHA_API.AuctionHouseType
---@return integer? realmAverageSaleValue
function API.GetRealmAverageSaleValue(itemID, auctionHouseType)
	local _, _, value = GetRealmSaleData(itemID, auctionHouseType)
	return NormalizeCopper(value)
end

---@param itemID integer
---@return boolean isDisenchantable
function API.IsDisenchantable(itemID)
	if type(itemID) ~= "number" or itemID <= 0 or itemID ~= floor(itemID) then
		return false
	end
	return disenchantingData:GetResults(itemID) ~= nil
end

---@param itemID integer
---@return YAAHA_API.DisenchantResults? results
function API.GetDisenchantResults(itemID)
	if type(itemID) ~= "number" or itemID <= 0 or itemID ~= floor(itemID) then
		return nil
	end
	local source = disenchantingData:GetResults(itemID)
	if not source then
		return nil
	end
	local data = {
		requiredSkill = source.requiredSkill,
		sampleCount = source.sampleCount,
		results = {},
	}
	for index = 1, #source.results do
		local result = source.results[index]
		data.results[index] = {
			itemID = result.itemID,
			chance = result.chance,
			minQuantity = result.minQuantity,
			maxQuantity = result.maxQuantity,
			expectedQuantity = result.expectedQuantity,
		}
	end
	return data
end

---@param itemID integer
---@param auctionHouseType? YAAHA_API.AuctionHouseType
---@param fullResults? boolean
---@return integer|YAAHA_API.PricedDisenchantResults|nil value
function API.GetDisenchantValue(itemID, auctionHouseType, fullResults)
	if type(itemID) ~= "number" or itemID <= 0 or itemID ~= floor(itemID) then
		return nil
	end
	if fullResults ~= nil and type(fullResults) ~= "boolean" then
		return nil
	end
	local auctionDB = GetAuctionDB(auctionHouseType)
	if not auctionDB then
		return nil
	end
	local scope = auctionDB == addon.db.realm.auctionDB and "realm" or "factionrealm"
	local data = disenchantingData:GetValue(itemID, scope)
	if not data then
		return nil
	end
	local expectedValue = NormalizeCopper(data.expectedValue)
	if not fullResults then
		return expectedValue
	end

	local result = {
		expectedValue = expectedValue,
		requiredSkill = data.requiredSkill,
		sampleCount = data.sampleCount,
		results = {},
	}
	for index = 1, #data.results do
		local source = data.results[index]
		result.results[index] = {
			itemID = source.itemID,
			chance = source.chance,
			minQuantity = source.minQuantity,
			maxQuantity = source.maxQuantity,
			expectedQuantity = source.expectedQuantity,
			marketValue = NormalizeCopper(source.marketValue),
			priceSource = source.priceSource,
			expectedValue = NormalizeCopper(source.expectedValue),
			missingPrice = source.missingPrice,
		}
	end
	return result
end