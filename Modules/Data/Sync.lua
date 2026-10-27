-- Exchanges normalized auction data, realm-sale observations, and learned material
-- breakdown results only with guild members in the same Connected Realm group.

local C_EncodingUtil = C_EncodingUtil
local C_Timer = C_Timer
local FACTION_ALLIANCE = FACTION_ALLIANCE
local FACTION_HORDE = FACTION_HORDE
local FACTION_NEUTRAL = FACTION_NEUTRAL
local GetServerTime = GetServerTime
local IsInGuild = IsInGuild
local IsInInstance = IsInInstance
local LibStub = LibStub
local max = math.max
local min = math.min
local next = next
local pairs = pairs
local pcall = pcall
local random = math.random
local sort = table.sort
local stringByte = string.byte
local tableConcat = table.concat
local tableRemove = table.remove
local type = type

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local module = addon:NewModule("Sync", "AceEvent-3.0")
local usesSharedAuctionHouse = addon.usesSharedAuctionHouse
local dataProcessing = addon:GetModule("DataProcessing")
local collectorModules = {
	disenchantData = addon:GetModule("DisenchantingData"),
	millingData = addon:GetModule("MillingData", true),
	prospectData = addon:GetModule("ProspectingData", true),
}
local saleCollector = addon:GetModule("SaleCollector")
local L = LibStub("AceLocale-3.0"):GetLocale("YAAHA")
local storage

local COMM_PREFIX = "YAAHA1"
local PROTOCOL_VERSION = 1
local SYNC_DISTRIBUTION = "GUILD"
local INITIAL_PULL_DELAY = 60
local SECONDS_PER_DAY = addon.secondsPerDay
local MAX_HISTORY_SECONDS = 60 * SECONDS_PER_DAY
local SALE_HISTORY_SECONDS = addon.saleHistorySeconds
local playerFullName
local BASE64_VARIANT = addon.base64Variant
local COMPRESSION_METHOD = addon.compressionMethod
-- Sync transports YAAHA's normalized data rather than Blizzard auction results.
-- The wire key names the actual market. Faction-separated clients retain three
-- markets, while Mists and Retail normalize every request to their shared house.
local AUCTION_HOUSE_TYPES = usesSharedAuctionHouse
	and { "Shared" } or { "Alliance", "Horde", "Neutral" }
local SYNC_MARKET_FIELDS = {
	"auctionCount",
	"auctionQuantity",
	"currentMarketValue",
	"lastScan",
	"minBid",
	"minBuyout",
}
local COLLECTOR_KEYS = { "disenchantData", "millingData", "prospectData" }
local pendingPulls = {}
local seenPulls = {}

local function IsSelf(sender)
	local normalizedSender = addon:NormalizeCharacterName(sender)
	return normalizedSender == playerFullName
end

local function ScopeEnabled(auctionHouseType)
	if usesSharedAuctionHouse then
		return auctionHouseType == "Shared"
	end
	return auctionHouseType == "Alliance" or auctionHouseType == "Horde"
		or auctionHouseType == "Neutral"
end

-- Wire scopes name the auction house itself, never its relationship to the
-- sender. A relayed Horde snapshot therefore remains Horde data even when an
-- Alliance character sends it. Only this function maps that stable identity to
-- the current character's AceDB scopes.
local function GetScopeDB(auctionHouseType, create)
	if usesSharedAuctionHouse and auctionHouseType == "Shared" then
		return addon.db.realm, "realm"
	elseif auctionHouseType == addon.playerFaction then
		return addon.db.factionrealm, "factionrealm"
	elseif auctionHouseType == "Neutral" then
		return addon.db.realm, "realm"
	elseif auctionHouseType == addon.oppositeFaction then
		storage = storage or addon:GetModule("Storage")
		local scopeDB = create and storage:GetOrCreateOppositeFactionData()
			or storage:GetOppositeFactionData()
		return scopeDB, "factionrealm"
	end
end

local function CanSyncNow()
	return addon.db.profile.syncData and IsInGuild() and not IsInInstance()
end

local function EncodePacket(kind, data)
	local realmGroup = addon:GetConnectedRealmKey()
	if not realmGroup then
		return
	end
	local serialized = addon:Serialize({
		version = PROTOCOL_VERSION,
		kind = kind,
		realmGroup = realmGroup,
		data = data,
	})
	-- Compressed output is binary. Base64 makes it safe for WoW's addon channel;
	-- no raw table or serialized text is ever handed to AceComm.
	local compressed = C_EncodingUtil.CompressString(serialized, COMPRESSION_METHOD)
	return C_EncodingUtil.EncodeBase64(compressed, BASE64_VARIANT)
end

local function DecodePacket(text)
	if type(text) ~= "string" or #text > 8 * 1024 * 1024 then
		return
	end
	-- Reverse the channel-safe encoding and compression before deserializing.
	-- OnCommReceived protects this entire path because peer data is untrusted.
	local decoded = C_EncodingUtil.DecodeBase64(text, BASE64_VARIANT)
	local decompressed = C_EncodingUtil.DecompressString(decoded, COMPRESSION_METHOD)
	local success, packet = addon:Deserialize(decompressed)
	if success and type(packet) == "table" and packet.version == PROTOCOL_VERSION
		and packet.realmGroup == addon:GetConnectedRealmKey()
		and type(packet.kind) == "string" and type(packet.data) == "table" then
		return packet
	end
end

local function SendPacket(kind, data, priority)
	local encoded = EncodePacket(kind, data)
	if encoded then
		addon:SendCommMessage(COMM_PREFIX, encoded, SYNC_DISTRIBUTION, nil,
			priority or "BULK")
	end
end

local function GetCollectorSourceID()
	return addon:GetSyncSourceID()
end

local function BuildCollectorData()
	-- Only learned observations cross the wire. Every installation already has
	-- the same client-specific baseline tables, so serializing them would add
	-- traffic and incorrectly multiply their virtual sample weight.
	local collections = {}
	local ownSourceID = GetCollectorSourceID()
	for index = 1, #COLLECTOR_KEYS do
		local savedKey = COLLECTOR_KEYS[index]
		local dataModule = collectorModules[savedKey]
		if dataModule then
			local bySource = {}
			local syncedBySource = addon.db.global.collectorSyncData[savedKey]
			for sourceID, learnedData in pairs(syncedBySource) do
				if sourceID ~= ownSourceID then
					local sanitized = dataModule:SanitizeLearnedData(learnedData)
					if sanitized then
						bySource[sourceID] = sanitized
					else
						syncedBySource[sourceID] = nil
					end
				end
			end
			local ownData = dataModule:SanitizeLearnedData(addon.db.global[savedKey])
			if ownData then
				bySource[ownSourceID] = ownData
			end
			if next(bySource) then
				collections[savedKey] = bySource
			end
		end
	end
	return collections
end

local function LearnedKeyValue(key)
	if type(key) == "number" then
		return key
	end
	if type(key) ~= "string" then
		return 0
	end
	local value = 0
	for index = 1, #key do
		value = value + stringByte(key, index) * index
	end
	return value
end

local function CollectorSignature(collections)
	local parts = {}
	for index = 1, #COLLECTOR_KEYS do
		local savedKey = COLLECTOR_KEYS[index]
		for sourceID, learnedData in pairs(type(collections) == "table"
			and collections[savedKey] or {}) do
			local entryCount, keyTotal, materialTotal = 0, 0, 0
			local sampleCount, occurrenceTotal, quantityTotal = 0, 0, 0
			for learnedKey, learned in pairs(learnedData) do
				entryCount = entryCount + 1
				keyTotal = keyTotal + LearnedKeyValue(learnedKey)
				sampleCount = sampleCount + learned.samples
				for materialID, observation in pairs(learned.results) do
					materialTotal = materialTotal + materialID
					occurrenceTotal = occurrenceTotal + observation.occurrences
					quantityTotal = quantityTotal + observation.quantity
				end
			end
			parts[#parts + 1] = tableConcat({ savedKey, sourceID, entryCount,
				keyTotal, materialTotal, sampleCount, occurrenceTotal, quantityTotal }, ":")
		end
	end
	sort(parts)
	return tableConcat(parts, "|")
end

local function CollectorSampleCount(collections)
	local samples = 0
	for index = 1, #COLLECTOR_KEYS do
		local savedKey = COLLECTOR_KEYS[index]
		for _, learnedData in pairs(type(collections) == "table"
			and collections[savedKey] or {}) do
			for _, learned in pairs(learnedData) do
				samples = samples + learned.samples
			end
		end
	end
	return samples
end

local function MergeCollectorData(incomingCollections)
	-- Preserve one cumulative snapshot per opaque installation ID. Relayed copies
	-- then replace, rather than double-count, observations learned at their source.
	local received = false
	local ownSourceID = GetCollectorSourceID()
	for index = 1, #COLLECTOR_KEYS do
		local savedKey = COLLECTOR_KEYS[index]
		local dataModule = collectorModules[savedKey]
		local incomingBySource = type(incomingCollections) == "table"
			and incomingCollections[savedKey]
		if dataModule and type(incomingBySource) == "table" then
			local storedBySource = addon.db.global.collectorSyncData[savedKey]
			for sourceID, learnedData in pairs(incomingBySource) do
				if type(sourceID) == "string" and sourceID ~= "" and sourceID ~= ownSourceID then
					local sanitized, incomingSamples = dataModule:SanitizeLearnedData(learnedData)
					if sanitized then
						local _, storedSamples = dataModule:SanitizeLearnedData(storedBySource[sourceID])
						if incomingSamples > storedSamples then
							storedBySource[sourceID] = sanitized
							received = true
						end
					end
				end
			end
		end
	end
	return received
end

local function GetSaleIDs(saleData)
	local ids = {}
	local now = GetServerTime()
	for index = 1, #(saleData.observations or {}) do
		local observation = saleData.observations[index]
		if type(observation) == "table" and observation.privateSafe == true
			and (observation.source == "seller" or observation.source == "buyer"
				or observation.source == "failure")
			and type(observation.syncID) == "string"
			and type(observation.timestamp) == "number" and observation.timestamp <= now
			and now - observation.timestamp < SALE_HISTORY_SECONDS then
			ids[observation.syncID] = true
		end
	end
	return ids
end

local function StatsSignature(stats)
	return type(stats) == "table" and type(stats.lastScan) == "number"
		and stats.lastScan .. ":" .. (stats.totalListings or 0) .. ":" .. (stats.totalItems or 0) or nil
end

local function BuildScopeSummary(scopeDB, realmSales, auctionHouseType)
	local now = GetServerTime()
	local summary = {
		historyCount = 0,
		historyNewest = 0,
		historyTimestampTotal = 0,
		historyValueTotal = 0,
		lastScan = scopeDB.auctionStats.lastScan or 0,
		saleCount = 0,
		saleNewest = 0,
		saleTrackingStarted = saleCollector:GetRealmSalesTrackingStarted(auctionHouseType),
		saleTotal = 0,
		snapshotCount = 0,
		snapshotTotal = 0,
	}
	for itemID, itemData in pairs(scopeDB.auctionDB) do
		if itemData.lastScan then
			summary.snapshotCount = summary.snapshotCount + 1
			summary.snapshotTotal = summary.snapshotTotal + itemID + itemData.lastScan
				+ (itemData.currentMarketValue or 0) + (itemData.minBid or 0)
				+ (itemData.minBuyout or 0) + (itemData.auctionCount or 0)
				+ (itemData.auctionQuantity or 0)
		end
		for index = 1, #(itemData.history or {}) do
			local observation = itemData.history[index]
			if observation.timestamp and observation.value and observation.timestamp <= now
				and now - observation.timestamp < MAX_HISTORY_SECONDS then
				summary.historyCount = summary.historyCount + 1
				summary.historyNewest = max(summary.historyNewest, observation.timestamp)
				summary.historyTimestampTotal = summary.historyTimestampTotal
					+ observation.timestamp + itemID
				summary.historyValueTotal = summary.historyValueTotal + observation.value
			end
		end
	end
	for itemID, saleData in pairs(realmSales) do
		for index = 1, #(saleData.observations or {}) do
			local observation = saleData.observations[index]
			if type(observation) == "table" and observation.privateSafe == true
				and observation.timestamp
				and observation.timestamp <= now
				and now - observation.timestamp < SALE_HISTORY_SECONDS then
				summary.saleCount = summary.saleCount + 1
				summary.saleNewest = max(summary.saleNewest, observation.timestamp)
				summary.saleTotal = summary.saleTotal + itemID + observation.timestamp
					+ (observation.attempted or 0) + (observation.sold or 0)
					+ (observation.totalSaleValue or 0)
			end
		end
	end
	return summary
end

local function SummarySignature(summary)
	if type(summary) ~= "table" then
		return ""
	end
	local fields = { "lastScan", "historyCount", "historyNewest", "historyTimestampTotal",
		"historyValueTotal", "saleCount", "saleNewest", "saleTrackingStarted", "saleTotal",
		"snapshotCount", "snapshotTotal" }
	local values = {}
	for index = 1, #fields do
		local value = summary[fields[index]]
		if type(value) ~= "number" or value < 0 then
			return ""
		end
		values[index] = value
	end
	return tableConcat(values, ":")
end

local function AdvertisementSignature(advertisement)
	local scopes = type(advertisement) == "table"
		and type(advertisement.scopes) == "table" and advertisement.scopes or {}
	local parts = {}
	for index = 1, #AUCTION_HOUSE_TYPES do
		local auctionHouseType = AUCTION_HOUSE_TYPES[index]
		parts[#parts + 1] = auctionHouseType .. "="
			.. SummarySignature(scopes[auctionHouseType])
	end
	parts[#parts + 1] = "collectors=" .. (type(advertisement) == "table"
		and type(advertisement.collectorSignature) == "string"
		and advertisement.collectorSignature or "")
	return tableConcat(parts, "|")
end

local function AdvertisementFreshness(advertisement)
	local freshness = 0
	local scopes = type(advertisement) == "table"
		and type(advertisement.scopes) == "table" and advertisement.scopes or {}
	for _, summary in pairs(scopes) do
		if SummarySignature(summary) ~= "" then
			freshness = max(freshness, summary.lastScan, summary.historyNewest,
				summary.saleNewest)
		end
	end
	return freshness
end

local function AdvertisementCoverage(advertisement)
	local coverage = type(advertisement) == "table"
		and type(advertisement.collectorSamples) == "number"
		and max(0, advertisement.collectorSamples) or 0
	local scopes = type(advertisement) == "table"
		and type(advertisement.scopes) == "table" and advertisement.scopes or {}
	for _, summary in pairs(scopes) do
		if SummarySignature(summary) ~= "" then
			coverage = coverage + summary.historyCount + summary.saleCount
				+ summary.snapshotCount
		end
	end
	return coverage
end

local function BuildAdvertisement()
	local scopes = {}
	for index = 1, #AUCTION_HOUSE_TYPES do
		local auctionHouseType = AUCTION_HOUSE_TYPES[index]
		local scopeDB = ScopeEnabled(auctionHouseType) and GetScopeDB(auctionHouseType)
		if scopeDB then
			local realmSales = addon:GetRealmSales(auctionHouseType)
			if next(scopeDB.auctionDB) or next(realmSales)
				or StatsSignature(scopeDB.auctionStats) then
				scopes[auctionHouseType] = BuildScopeSummary(scopeDB, realmSales, auctionHouseType)
			end
		end
	end
	return scopes
end

local function CopyMarketSnapshot(itemData, fullHistory)
	local delta = { history = {} }
	for index = 1, #SYNC_MARKET_FIELDS do
		local field = SYNC_MARKET_FIELDS[index]
		delta[field] = itemData[field]
	end
	-- Rolling values are deterministic products of retained scan history. A full
	-- reconciliation shares every valid observation; routine scan pushes carry only
	-- the new observation so ordinary updates remain small.
	local now = GetServerTime()
	for index = 1, #(itemData.history or {}) do
		local observation = itemData.history[index]
		if type(observation) == "table" and type(observation.timestamp) == "number"
			and type(observation.value) == "number" and observation.value > 0
			and observation.timestamp <= now
			and now - observation.timestamp < MAX_HISTORY_SECONDS
			and (fullHistory or observation.timestamp == itemData.lastScan) then
			delta.history[#delta.history + 1] = {
				timestamp = observation.timestamp,
				value = observation.value,
			}
		end
	end
	-- An item missing from the latest scan has no current snapshot, but its rolling
	-- history remains useful until the final 60-day observation expires.
	if itemData.lastScan or (fullHistory and #delta.history > 0) then
		return delta
	end
end

local function CopySaleDelta(saleData, wantedIDs)
	local observations = {}
	local now = GetServerTime()
	for index = 1, #(saleData.observations or {}) do
		local observation = saleData.observations[index]
		if type(observation) == "table" and observation.privateSafe == true
			and (observation.source == "seller" or observation.source == "buyer"
				or observation.source == "failure")
			and observation.syncID
			and wantedIDs[observation.syncID]
			and observation.timestamp <= now
			and now - observation.timestamp < SALE_HISTORY_SECONDS then
			observations[#observations + 1] = {
				attempted = observation.attempted,
				auctionID = observation.auctionID,
				matchKey = observation.matchKey,
				privateSafe = true,
				resolutionKey = observation.resolutionKey,
				sold = observation.sold,
				source = observation.source,
				syncID = observation.syncID,
				timestamp = observation.timestamp,
				totalSaleValue = observation.totalSaleValue,
				transactionKey = observation.transactionKey,
			}
		end
	end
	return #observations > 0 and { observations = observations } or nil
end

local function BuildPush(scopeFilter, fullHistory, includeCollectors)
	local scopes = {}
	for index = 1, #AUCTION_HOUSE_TYPES do
		local auctionHouseType = AUCTION_HOUSE_TYPES[index]
		local scopeDB = (not scopeFilter or scopeFilter[auctionHouseType])
			and ScopeEnabled(auctionHouseType) and GetScopeDB(auctionHouseType)
		if scopeDB then
			local realmSales = addon:GetRealmSales(auctionHouseType)
			local market = {}
			for itemID, itemData in pairs(scopeDB.auctionDB) do
				local delta = CopyMarketSnapshot(itemData, fullHistory)
				if delta then
					market[itemID] = delta
				end
			end
			local sales = {}
			for itemID, saleData in pairs(realmSales) do
				local delta = CopySaleDelta(saleData, GetSaleIDs(saleData))
				if delta then
					sales[itemID] = delta
				end
			end
			local stats = StatsSignature(scopeDB.auctionStats) and scopeDB.auctionStats or nil
			-- A pushed snapshot may relay separately stored market data, but its
			-- stable auction-house key preserves the client's actual market boundary.
			if next(market) or next(sales) or stats then
				scopes[auctionHouseType] = {
					market = market,
					saleTrackingStarted = saleCollector:GetRealmSalesTrackingStarted(auctionHouseType),
					sales = sales,
					stats = stats,
				}
			end
		end
	end
	return {
		collectors = includeCollectors and BuildCollectorData() or nil,
		scopes = scopes,
	}
end

local function MergeSaleObservation(realmSales, itemID, incoming)
	if type(incoming) ~= "table" or type(incoming.syncID) ~= "string"
		or incoming.privateSafe ~= true
		or type(incoming.timestamp) ~= "number"
		or type(incoming.transactionKey) ~= "string"
		or incoming.source ~= "seller" and incoming.source ~= "buyer"
			and incoming.source ~= "failure"
		or type(incoming.attempted) ~= "number" or type(incoming.sold) ~= "number"
		or incoming.auctionID ~= nil and (type(incoming.auctionID) ~= "number"
			or incoming.auctionID <= 0 or incoming.auctionID % 1 ~= 0)
		or incoming.matchKey ~= nil and (type(incoming.matchKey) ~= "string"
			or incoming.matchKey == "")
		or incoming.resolutionKey ~= nil and type(incoming.resolutionKey) ~= "string"
		or incoming.source == "failure" and type(incoming.resolutionKey) ~= "string"
		or type(incoming.totalSaleValue) ~= "number" or incoming.attempted < 0
		or incoming.sold < 0 or incoming.sold > incoming.attempted
		or incoming.source == "failure" and (incoming.attempted <= 0
			or incoming.sold ~= 0 or incoming.totalSaleValue ~= 0)
		or incoming.source ~= "failure" and (incoming.attempted <= 0
			or incoming.sold <= 0 or incoming.totalSaleValue <= 0)
		or incoming.totalSaleValue < 0 or incoming.timestamp > GetServerTime()
		or GetServerTime() - incoming.timestamp >= SALE_HISTORY_SECONDS then
		return false
	end
	local data = realmSales[itemID]
	if type(data) ~= "table" or type(data.observations) ~= "table" then
		data = { observations = {} }
		realmSales[itemID] = data
	end
	local now = GetServerTime()
	for index = #data.observations, 1, -1 do
		local observation = data.observations[index]
		if type(observation) ~= "table" or type(observation.timestamp) ~= "number"
			or observation.timestamp > now
			or now - observation.timestamp >= SALE_HISTORY_SECONDS then
			tableRemove(data.observations, index)
		elseif observation.syncID == incoming.syncID then
			return false
		end
	end
	data.observations[#data.observations + 1] = {
		attempted = incoming.attempted,
		auctionID = incoming.auctionID,
		matchKey = incoming.matchKey,
		privateSafe = true,
		resolutionKey = incoming.resolutionKey,
		sold = incoming.sold,
		source = incoming.source,
		syncID = incoming.syncID,
		synced = true,
		timestamp = incoming.timestamp,
		totalSaleValue = incoming.totalSaleValue,
		transactionKey = incoming.transactionKey,
	}

	-- A disappeared posting is provisionally a cancellation or expiry. If seller
	-- mail later proves that exact posting sold, retain the sale and discard its
	-- failure regardless of which observation reached this peer first.
	if incoming.resolutionKey then
		local failureIDs = {}
		local numResolvedSales = 0
		for index = 1, #data.observations do
			local observation = data.observations[index]
			if observation.resolutionKey == incoming.resolutionKey then
				if observation.source == "seller" then
					numResolvedSales = numResolvedSales + 1
				elseif observation.source == "failure" then
					failureIDs[#failureIDs + 1] = observation.syncID
				end
			end
		end
		sort(failureIDs)
		local resolvedFailureIDs = {}
		for index = 1, min(numResolvedSales, #failureIDs) do
			resolvedFailureIDs[failureIDs[index]] = true
		end
		for index = #data.observations, 1, -1 do
			if resolvedFailureIDs[data.observations[index].syncID] then
				tableRemove(data.observations, index)
			end
		end
	end
	return true
end

local function MergeDelta(delta)
	local receivedScopes = {}
	local receivedCollectors = MergeCollectorData(delta.collectors)
	local incomingScopes = type(delta.scopes) == "table" and delta.scopes or {}
	for auctionHouseType, incoming in pairs(incomingScopes) do
		local scopeDB, scope
		if ScopeEnabled(auctionHouseType) then
			scopeDB, scope = GetScopeDB(auctionHouseType, true)
		end
		if scopeDB and type(incoming) == "table" then
			local realmSales = addon:GetRealmSales(auctionHouseType)
			local received = saleCollector:MergeRealmSalesTrackingStarted(
				auctionHouseType, incoming.saleTrackingStarted)
			local incomingStats = incoming.stats
			if type(incomingStats) == "table" and type(incomingStats.lastScan) == "number"
				and type(incomingStats.totalListings) == "number" and type(incomingStats.totalItems) == "number"
				and incomingStats.lastScan >= 0 and incomingStats.totalListings >= 0
				and incomingStats.totalItems >= 0
				and incomingStats.lastScan <= GetServerTime()
				and (incomingStats.lastScan > ((scopeDB.auctionStats or {}).lastScan or 0)
					or incomingStats.lastScan == ((scopeDB.auctionStats or {}).lastScan or 0)
					and StatsSignature(incomingStats) > (StatsSignature(scopeDB.auctionStats) or "")) then
				local auctionDB = scopeDB.auctionDB
				for itemID, itemData in pairs(auctionDB) do
					if itemData.lastScan and itemData.lastScan < incomingStats.lastScan then
						local history = itemData.history
						auctionDB[itemID] = next(history or {}) and {
							biweeklyMarketValue = itemData.biweeklyMarketValue,
							bimonthlyMarketValue = itemData.bimonthlyMarketValue,
							history = history,
							midweekMarketValue = itemData.midweekMarketValue,
							monthlyMarketValue = itemData.monthlyMarketValue,
							trends = itemData.trends,
							weeklyMarketValue = itemData.weeklyMarketValue,
						} or nil
					end
				end
				scopeDB.auctionStats = {
					lastScan = incomingStats.lastScan,
					totalItems = incomingStats.totalItems,
					totalListings = incomingStats.totalListings,
				}
				received = true
			end
			local incomingMarket = type(incoming.market) == "table" and incoming.market or {}
			for itemID, itemData in pairs(incomingMarket) do
				if type(itemID) == "number" and itemID > 0 and type(itemData) == "table" then
					if dataProcessing:MergeSyncedMarketItem(scope, itemID, itemData, scopeDB) then
						received = true
					end
				end
			end
			local incomingSales = type(incoming.sales) == "table" and incoming.sales or {}
			for itemID, saleData in pairs(incomingSales) do
				if type(itemID) == "number" and itemID > 0 and type(saleData) == "table" then
					local observations = type(saleData.observations) == "table"
						and saleData.observations or {}
					for index = 1, #observations do
						if MergeSaleObservation(realmSales, itemID, observations[index]) then
							saleCollector:MergeRealmSalesTrackingStarted(
								auctionHouseType, observations[index].timestamp)
							received = true
						end
					end
				end
			end
			if received then
				receivedScopes[auctionHouseType] = true
				addon:Printf(L["Received auction data for the %s auction house."],
					auctionHouseType == "Shared" and L["Shared"]
						or auctionHouseType == "Neutral" and FACTION_NEUTRAL
						or auctionHouseType == "Alliance" and FACTION_ALLIANCE or FACTION_HORDE)
				addon:FireAPIEvent("AUCTION_HOUSE_DATA_UPDATED",
					auctionHouseType, "sync")
			end
		end
	end
	return receivedScopes, receivedCollectors
end

local function SendPush(push, kind)
	if not CanSyncNow() then
		return
	end
	push = push or BuildPush()
	if next(push.scopes) or next(push.collectors or {}) then
		SendPacket(kind or "PUSH", push)
	end
end

local function FinishPull(requestID)
	local pending = pendingPulls[requestID]
	if not pending then
		return
	end
	local localCollectors = BuildCollectorData()
	local localAdvertisement = {
		collectorSignature = CollectorSignature(localCollectors),
		scopes = BuildAdvertisement(),
	}
	local localSignature = AdvertisementSignature(localAdvertisement)
	local selectedSender, selectedAdvertisement
	local selectedFreshness, selectedCoverage = -1, -1
	for sender, advertisement in pairs(pending.advertisements) do
		local signature = AdvertisementSignature(advertisement)
		if signature ~= localSignature then
			local freshness = AdvertisementFreshness(advertisement)
			local coverage = AdvertisementCoverage(advertisement)
			if not selectedSender or freshness > selectedFreshness
				or freshness == selectedFreshness and coverage > selectedCoverage
				or freshness == selectedFreshness and coverage == selectedCoverage
				and sender < selectedSender then
				selectedSender = sender
				selectedAdvertisement = advertisement
				selectedFreshness = freshness
				selectedCoverage = coverage
			end
		end
	end
	if selectedSender then
		pending.selectedSender = selectedSender
		pending.expectedScopes = {}
		local scopes = type(selectedAdvertisement.scopes) == "table"
			and selectedAdvertisement.scopes or {}
		for index = 1, #AUCTION_HOUSE_TYPES do
			local auctionHouseType = AUCTION_HOUSE_TYPES[index]
			if SummarySignature(scopes[auctionHouseType]) ~= "" then
				pending.expectedScopes[auctionHouseType] = true
			end
		end
		pending.expectedCollectors = type(selectedAdvertisement.collectorSignature) == "string"
			and selectedAdvertisement.collectorSignature ~= ""
		SendPacket("REQUEST", {
			requestID = requestID,
			selectedSender = selectedSender,
		}, "NORMAL")
		-- Multipart auction histories can take longer than ordinary addon messages.
		-- This timer only discards request bookkeeping; received parts merge at once.
		pending.timer = C_Timer.NewTimer(10 * 60, function()
			pendingPulls[requestID] = nil
		end)
	else
		pendingPulls[requestID] = nil
	end
end

local function RequestPush()
	if CanSyncNow() then
		addon.db.char.syncSequence = (addon.db.char.syncSequence or 0) + 1
		local requestID = tableConcat({
			addon:GetSyncSourceID(),
			GetServerTime(),
			addon.db.char.syncSequence,
		}, ":")
		pendingPulls[requestID] = {
			advertisements = {},
		}
		pendingPulls[requestID].timer = C_Timer.NewTimer(5, function()
			FinishPull(requestID)
		end)
		SendPacket("PULL", { requestID = requestID }, "NORMAL")
	end
end

local function RequestInitialPush()
	-- Eligibility may change during the login delay, particularly if the player
	-- enters an instance. Recheck before sending rather than trusting old state.
	if CanSyncNow() then
		RequestPush()
	end
end

local function ScheduleAdvertisement(sender, requestID)
	if type(requestID) ~= "string" or seenPulls[requestID] then
		return
	end
	seenPulls[requestID] = true
	C_Timer.After(60, function()
		seenPulls[requestID] = nil
	end)
	-- Advertisements are small summaries. The requester compares every reply before
	-- asking useful peers for complete retained auction and collector data.
	C_Timer.After(random(1, 3), function()
		local scopes = BuildAdvertisement()
		local collectors = BuildCollectorData()
		local collectorSignature = CollectorSignature(collectors)
		if next(scopes) or collectorSignature ~= "" then
			SendPacket("ADVERTISE", {
				collectorSamples = CollectorSampleCount(collectors),
				collectorSignature = collectorSignature,
				requestID = requestID,
				scopes = scopes,
				target = sender,
			}, "NORMAL")
		end
	end)
end

local function SendRequestedPush(sender, data)
	if type(data.requestID) ~= "string" or not IsSelf(data.selectedSender) then
		return
	end
	-- The requester elects exactly one responder from compact advertisements.
	-- Keep each market in its own multipart stream so one interrupted partition
	-- cannot invalidate the others.
	for index = 1, #AUCTION_HOUSE_TYPES do
		local auctionHouseType = AUCTION_HOUSE_TYPES[index]
		local push = BuildPush({ [auctionHouseType] = true }, true, false)
		push.requestID = data.requestID
		push.target = sender
		SendPush(push)
	end
	local push = BuildPush({}, false, true)
	push.requestID = data.requestID
	push.target = sender
	SendPush(push)
end

local function ReturnMergedPush(sender, data)
	if type(data.requestID) ~= "string" or not IsSelf(data.target) then
		return
	end
	local pending = pendingPulls[data.requestID]
	if not pending then
		return
	end
	if sender ~= pending.selectedSender then
		return
	end
	pending.received = pending.received or {}
	for auctionHouseType in pairs(type(data.scopes) == "table" and data.scopes or {}) do
		pending.received[auctionHouseType] = true
	end
	if next(type(data.collectors) == "table" and data.collectors or {}) then
		pending.receivedCollectors = true
	end
	for auctionHouseType in pairs(pending.expectedScopes or {}) do
		if not pending.received[auctionHouseType] then
			return
		end
	end
	if pending.expectedCollectors and not pending.receivedCollectors then
		return
	end
	if pending.timer then
		pending.timer:Cancel()
	end
	-- PUSH packets use the guild channel, so every eligible peer has already seen
	-- and merged the elected responder's data. A second return broadcast is wasteful.
	pendingPulls[data.requestID] = nil
end

function module:OnCommReceived(_, text, distribution, sender)
	-- Core expands ordinary short names to the current realm and requires Forever's
	-- complete Given Surname identity, preventing both cross-realm and first-name
	-- collisions during self-message detection.
	if distribution ~= SYNC_DISTRIBUTION or IsSelf(sender) then
		return
	end
	if not CanSyncNow() then
		return
	end
	local success, packet = pcall(DecodePacket, text)
	if not success or type(packet) ~= "table" then
		return
	end
	-- Realm sales are rolling 60-day observations. Sweep the character's local
	-- scopes before accepting peer data; touched relayed scopes are pruned below.
	saleCollector:PruneRealmSales()

	if packet.kind == "PULL" then
		ScheduleAdvertisement(sender, packet.data.requestID)
	elseif packet.kind == "ADVERTISE" then
		local pending = type(packet.data.requestID) == "string"
			and IsSelf(packet.data.target) and pendingPulls[packet.data.requestID]
		if pending and type(packet.data.scopes) == "table" then
			pending.advertisements[sender] = packet.data
		end
	elseif packet.kind == "REQUEST" then
		SendRequestedPush(sender, packet.data)
	elseif packet.kind == "PUSH" then
		MergeDelta(packet.data)
		ReturnMergedPush(sender, packet.data)
	end
end

function module:YAAHA_SCAN_PROCESSED()
	if not CanSyncNow() then
		return
	end
	-- A completed local scan is the normal synchronization trigger. Receiving
	-- peer data never generates another message, preventing echo loops.
	for index = 1, #AUCTION_HOUSE_TYPES do
		local auctionHouseType = AUCTION_HOUSE_TYPES[index]
		local push = BuildPush({ [auctionHouseType] = true }, false, false)
		SendPush(push)
	end
end

function module:YAAHA_BREAKDOWN_OBSERVED()
	if CanSyncNow() then
		SendPush(BuildPush({}, false, true))
	end
end

function module:PLAYER_ENTERING_WORLD(_, isInitialLogin)
	if not isInitialLogin then
		return
	end
	-- Initial character login is the sole pull operation. Reloading or changing
	-- zones cannot request data, and an unanswered request remains silent. Waiting
	-- gives the client and other addons time to finish their own login work, while
	-- naturally avoiding traffic from characters which log out again immediately.
	C_Timer.After(INITIAL_PULL_DELAY, RequestInitialPush)
end

local function OnCommReceived(...)
	module:OnCommReceived(...)
end

function module:OnEnable()
	if #AUCTION_HOUSE_TYPES == 0 then
		return
	end
	local _, _, fullName = addon:GetPlayerIdentity()
	playerFullName = fullName
	addon:RegisterComm(COMM_PREFIX, OnCommReceived)
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	self:RegisterMessage("YAAHA_BREAKDOWN_OBSERVED")
	self:RegisterMessage("YAAHA_SCAN_PROCESSED")
end