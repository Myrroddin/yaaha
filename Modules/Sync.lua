local C_EncodingUtil = C_EncodingUtil
local C_Timer = C_Timer
local Enum = Enum
local FACTION_ALLIANCE = FACTION_ALLIANCE
local FACTION_HORDE = FACTION_HORDE
local FACTION_NEUTRAL = FACTION_NEUTRAL
local GetNormalizedRealmName = GetNormalizedRealmName
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
local tableConcat = table.concat
local tableRemove = table.remove
local type = type
local UnitFactionGroup = UnitFactionGroup
local UnitFullName = UnitFullName

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local module = addon:NewModule("Sync", "AceEvent-3.0")
local dataProcessing = addon:GetModule("DataProcessing")
local saleCollector = addon:GetModule("SaleCollector")
local L = LibStub("AceLocale-3.0"):GetLocale("YAAHA")
local storage

local COMM_PREFIX = "YAAHA1"
local PROTOCOL_VERSION = 1
local SECONDS_PER_DAY = 24 * 60 * 60
local MAX_HISTORY_SECONDS = 60 * SECONDS_PER_DAY
local playerFaction = UnitFactionGroup("player")
local playerName, playerRealm, playerFullName
local BASE64_VARIANT = Enum.Base64Variant.StandardUrlSafe
local oppositeFaction = playerFaction == "Alliance" and "Horde" or "Alliance"
local AUCTION_HOUSE_TYPES = { "Alliance", "Horde", "Neutral" }
local pendingPulls = {}
local seenPulls = {}

local function InitializePlayerIdentity()
	playerName, playerRealm = UnitFullName("player")
	playerRealm = playerRealm or GetNormalizedRealmName()
	playerFullName = playerRealm and playerRealm ~= "" and playerName .. "-" .. playerRealm or playerName
end

local function IsSelf(sender)
	return sender == playerName or sender == playerFullName
end

local function ScopeEnabled(auctionHouseType)
	return auctionHouseType == playerFaction and addon.db.profile.sendAndReceiveFactionRealm
		or auctionHouseType == oppositeFaction and addon.db.profile.sendAndReceiveOppositeFaction
		or auctionHouseType == "Neutral" and addon.db.profile.sendAndReceiveRealm
end

-- Wire scopes name the auction house itself, never its relationship to the
-- sender. A relayed Horde snapshot therefore remains Horde data even when an
-- Alliance character sends it. Only this function maps that stable identity to
-- the current character's AceDB scopes.
local function GetScopeDB(auctionHouseType, create)
	if auctionHouseType == playerFaction then
		return addon.db.factionrealm, "factionrealm"
	elseif auctionHouseType == "Neutral" then
		return addon.db.realm, "realm"
	elseif auctionHouseType == oppositeFaction then
		storage = storage or addon:GetModule("Storage")
		local scopeDB = create and storage:GetOrCreateOppositeFactionData()
			or storage:GetOppositeFactionData()
		return scopeDB, "factionrealm"
	end
end

local function AnySyncEnabled()
	return addon.db.profile.sendAndReceiveFactionRealm
		or addon.db.profile.sendAndReceiveOppositeFaction
		or addon.db.profile.sendAndReceiveRealm
end

local function CanSyncNow()
	return AnySyncEnabled() and not IsInInstance()
end

local function EncodePacket(kind, data)
	local serialized = addon:Serialize({ version = PROTOCOL_VERSION, kind = kind, data = data })
	local compressed = C_EncodingUtil.CompressString(serialized)
	return C_EncodingUtil.EncodeBase64(compressed, BASE64_VARIANT)
end

local function DecodePacket(text)
	if #text > 8 * 1024 * 1024 then
		return
	end
	local decoded = C_EncodingUtil.DecodeBase64(text, BASE64_VARIANT)
	local decompressed = C_EncodingUtil.DecompressString(decoded)
	local success, packet = addon:Deserialize(decompressed)
	if success and type(packet) == "table" and packet.version == PROTOCOL_VERSION
		and type(packet.kind) == "string" and type(packet.data) == "table" then
		return packet
	end
end

local function SendPacket(kind, data, distribution, target, priority)
	addon:SendCommMessage(COMM_PREFIX, EncodePacket(kind, data), distribution, target,
		priority or "BULK")
end

local function GetSaleIDs(saleData)
	local ids = {}
	local now = GetServerTime()
	for index = 1, #(saleData.observations or {}) do
		local observation = saleData.observations[index]
		if (observation.source == "seller" or observation.source == "failure")
			and observation.syncID and observation.timestamp
			and now - observation.timestamp < SECONDS_PER_DAY then
			ids[observation.syncID] = true
		end
	end
	return ids
end

local function StatsSignature(stats)
	return type(stats) == "table" and type(stats.lastScan) == "number"
		and stats.lastScan .. ":" .. (stats.totalListings or 0) .. ":" .. (stats.totalItems or 0) or nil
end

local function BuildScopeSummary(scopeDB)
	local now = GetServerTime()
	local summary = {
		historyCount = 0,
		historyNewest = 0,
		historyTimestampTotal = 0,
		historyValueTotal = 0,
		lastScan = scopeDB.auctionStats.lastScan or 0,
		saleCount = 0,
		saleNewest = 0,
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
	for itemID, saleData in pairs(scopeDB.realmSales) do
		for index = 1, #(saleData.observations or {}) do
			local observation = saleData.observations[index]
			if observation.timestamp and now - observation.timestamp < SECONDS_PER_DAY then
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
		"historyValueTotal", "saleCount", "saleNewest", "saleTotal", "snapshotCount",
		"snapshotTotal" }
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

local function BuildAdvertisement()
	local scopes = {}
	for _, auctionHouseType in pairs(AUCTION_HOUSE_TYPES) do
		local scopeDB = ScopeEnabled(auctionHouseType) and GetScopeDB(auctionHouseType)
		if scopeDB and (next(scopeDB.auctionDB) or next(scopeDB.realmSales)
			or StatsSignature(scopeDB.auctionStats)) then
			scopes[auctionHouseType] = BuildScopeSummary(scopeDB)
		end
	end
	return scopes
end

local function CopyMarketSnapshot(itemData, fullHistory)
	local delta = { history = {} }
	for _, field in pairs({ "auctionCount", "auctionQuantity", "currentMarketValue", "lastScan",
		"minBid", "minBuyout" }) do
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
		if (observation.source == "seller" or observation.source == "failure") and observation.syncID
			and wantedIDs[observation.syncID]
			and now - observation.timestamp < SECONDS_PER_DAY then
			observations[#observations + 1] = {
				attempted = observation.attempted,
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

local function BuildPush(scopeFilter, fullHistory)
	local scopes = {}
	for _, auctionHouseType in pairs(AUCTION_HOUSE_TYPES) do
		local scopeDB = (not scopeFilter or scopeFilter[auctionHouseType])
			and ScopeEnabled(auctionHouseType) and GetScopeDB(auctionHouseType)
		if scopeDB then
			local market = {}
			for itemID, itemData in pairs(scopeDB.auctionDB) do
				local delta = CopyMarketSnapshot(itemData, fullHistory)
				if delta then
					market[itemID] = delta
				end
			end
			local sales = {}
			for itemID, saleData in pairs(scopeDB.realmSales) do
				local delta = CopySaleDelta(saleData, GetSaleIDs(saleData))
				if delta then
					sales[itemID] = delta
				end
			end
			local stats = StatsSignature(scopeDB.auctionStats) and scopeDB.auctionStats or nil
			-- A pushed snapshot may relay separately stored opposite-faction data,
			-- but the stable auction-house key keeps all three markets isolated.
			if next(market) or next(sales) or stats then
				scopes[auctionHouseType] = {
					market = market,
					sales = sales,
					stats = stats,
				}
			end
		end
	end
	return { faction = playerFaction, scopes = scopes }
end

local function MergeSaleObservation(scopeDB, itemID, incoming)
	if type(incoming) ~= "table" or type(incoming.syncID) ~= "string"
		or type(incoming.timestamp) ~= "number"
		or type(incoming.transactionKey) ~= "string"
		or incoming.source ~= "seller" and incoming.source ~= "failure"
		or type(incoming.attempted) ~= "number" or type(incoming.sold) ~= "number"
		or incoming.resolutionKey ~= nil and type(incoming.resolutionKey) ~= "string"
		or incoming.source == "failure" and type(incoming.resolutionKey) ~= "string"
		or type(incoming.totalSaleValue) ~= "number" or incoming.attempted < 0
		or incoming.sold < 0 or incoming.sold > incoming.attempted
		or incoming.source == "failure" and (incoming.attempted <= 0
			or incoming.sold ~= 0 or incoming.totalSaleValue ~= 0)
		or incoming.totalSaleValue < 0 or incoming.timestamp > GetServerTime()
		or GetServerTime() - incoming.timestamp >= SECONDS_PER_DAY then
		return false
	end
	local realmSales = scopeDB.realmSales
	local data = realmSales[itemID]
	if not data then
		data = { observations = {} }
		realmSales[itemID] = data
	end
	local now = GetServerTime()
	for index = #data.observations, 1, -1 do
		local observation = data.observations[index]
		if not observation.timestamp or now - observation.timestamp >= SECONDS_PER_DAY then
			tableRemove(data.observations, index)
		elseif observation.syncID == incoming.syncID then
			return false
		end
	end
	data.observations[#data.observations + 1] = {
		attempted = incoming.attempted,
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
	local incomingScopes = type(delta.scopes) == "table" and delta.scopes or {}
	for auctionHouseType, incoming in pairs(incomingScopes) do
		local scopeDB, scope
		if ScopeEnabled(auctionHouseType) then
			scopeDB, scope = GetScopeDB(auctionHouseType, true)
		end
		if scopeDB and type(incoming) == "table" then
			local received = false
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
						if MergeSaleObservation(scopeDB, itemID, observations[index]) then
							received = true
						end
					end
				end
			end
			if received then
				receivedScopes[auctionHouseType] = true
				addon:Printf(L["Received auction data for the %s auction house."],
					auctionHouseType == "Neutral" and FACTION_NEUTRAL
						or auctionHouseType == "Alliance" and FACTION_ALLIANCE or FACTION_HORDE)
				addon:FireAPIEvent("AUCTION_HOUSE_DATA_UPDATED",
					auctionHouseType, "sync")
			end
		end
	end
	return receivedScopes
end

local function SendPush(distribution, push, encoded, kind)
	if not CanSyncNow() then
		return
	end
	push = push or BuildPush()
	if next(push.scopes) then
		encoded = encoded or EncodePacket(kind or "PUSH", push)
		addon:SendCommMessage(COMM_PREFIX, encoded, distribution, nil, "BULK")
		return encoded
	end
end

local function CompletePull(requestID)
	local pending = pendingPulls[requestID]
	if not pending then
		return
	end
	if not pending.returned then
		pendingPulls[requestID] = nil
		return
	end
	local filters = {}
	for auctionHouseType in pairs(pending.selections or {}) do
		filters[auctionHouseType] = true
	end
	-- Keep each auction house in its own multipart stream. A character may retain
	-- substantial data for all three markets, while the decoder's safety limit and
	-- an interrupted transmission should affect only one isolated partition.
	for auctionHouseType in pairs(filters) do
		local push = BuildPush({ [auctionHouseType] = true }, true)
		push.requestID = requestID
		SendPush(pending.distribution, push, nil, "RETURN")
	end
	if pending.timer then
		pending.timer:Cancel()
	end
	pendingPulls[requestID] = nil
end

local function FinishPull(requestID)
	local pending = pendingPulls[requestID]
	if not pending then
		return
	end
	local selections = {}
	for _, auctionHouseType in pairs(AUCTION_HOUSE_TYPES) do
		local scopeDB = ScopeEnabled(auctionHouseType) and GetScopeDB(auctionHouseType)
		local localSummary = scopeDB and BuildScopeSummary(scopeDB) or nil
		local localSignature = SummarySignature(localSummary)
		local selectedSignatures = {}
		for sender, advertisement in pairs(pending.advertisements) do
			local summary = advertisement[auctionHouseType]
			local signature = SummarySignature(summary)
			if signature ~= "" and signature ~= localSignature and not selectedSignatures[signature] then
				selections[auctionHouseType] = selections[auctionHouseType] or {}
				selections[auctionHouseType][sender] = true
				selectedSignatures[signature] = summary
			end
		end
	end
	if next(selections) then
		pending.selections = selections
		SendPacket("REQUEST", {
			requestID = requestID,
			selections = selections,
		}, pending.distribution, nil, "NORMAL")
		-- BULK auction histories can take substantially longer than an ordinary addon
		-- message. Keep reconciliation state for an hour so a valid slow transfer can
		-- still publish its merged union; logging out naturally discards this state.
		pending.timer = C_Timer.NewTimer(60 * 60, function()
			CompletePull(requestID)
		end)
	else
		pendingPulls[requestID] = nil
	end
end

local function RequestPush(distribution)
	if CanSyncNow() then
		addon.db.char.syncSequence = (addon.db.char.syncSequence or 0) + 1
		local requestID = tableConcat({
			playerFullName or playerName,
			GetServerTime(),
			addon.db.char.syncSequence,
		}, ":")
		pendingPulls[requestID] = {
			advertisements = {},
			distribution = distribution,
		}
		pendingPulls[requestID].timer = C_Timer.NewTimer(5, function()
			FinishPull(requestID)
		end)
		SendPacket("PULL", { faction = playerFaction, requestID = requestID },
			distribution, nil, "NORMAL")
	end
end

local function ScheduleAdvertisement(distribution, sender, requestID)
	if type(requestID) ~= "string" or seenPulls[requestID] then
		return
	end
	seenPulls[requestID] = true
	C_Timer.After(60, function()
		seenPulls[requestID] = nil
	end)
	-- Advertisements are small summaries. The requester compares every reply before
	-- asking one useful peer per auction-house type for its complete retained data.
	C_Timer.After(random(1, 3), function()
		local scopes = BuildAdvertisement()
		if next(scopes) then
			SendPacket("ADVERTISE", {
				requestID = requestID,
				scopes = scopes,
				target = sender,
			}, distribution, nil, "NORMAL")
		end
	end)
end

local function SendRequestedPush(distribution, sender, data)
	local filters = {}
	local selections = type(data.selections) == "table" and data.selections or {}
	for auctionHouseType, selectedSenders in pairs(selections) do
		if type(selectedSenders) == "table" and ScopeEnabled(auctionHouseType) then
			for selectedSender in pairs(selectedSenders) do
				if IsSelf(selectedSender) then
					filters[auctionHouseType] = true
					break
				end
			end
		end
	end
	if not next(filters) then
		return
	end
	for auctionHouseType in pairs(filters) do
		local push = BuildPush({ [auctionHouseType] = true }, true)
		push.requestID = data.requestID
		push.target = sender
		SendPush(distribution, push)
	end
end

local function ReturnMergedPush(sender, data)
	if type(data.requestID) ~= "string" or not IsSelf(data.target) then
		return
	end
	local pending = pendingPulls[data.requestID]
	if not pending then
		return
	end
	pending.returned = pending.returned or {}
	for auctionHouseType in pairs(type(data.scopes) == "table" and data.scopes or {}) do
		pending.returned[auctionHouseType .. ":" .. sender] = true
	end
	for auctionHouseType, selectedSenders in pairs(pending.selections or {}) do
		for selectedSender in pairs(selectedSenders) do
			if not pending.returned[auctionHouseType .. ":" .. selectedSender] then
				return
			end
		end
	end
	-- One bounded return publishes the complete union after every selected peer has
	-- replied. RETURN packets are merged but never answered, preventing echo loops.
	CompletePull(data.requestID)
end

function module:OnCommReceived(_, text, distribution, sender)
	-- Same-realm callbacks may use the short name while cross-realm callbacks use
	-- name-realm. Exact comparisons avoid rejecting an unrelated namesake.
	if IsSelf(sender) then
		return
	end
	if not CanSyncNow() then
		return
	end
	local success, packet = pcall(DecodePacket, text)
	if not success or type(packet) ~= "table" then
		return
	end
	-- Realm sales are rolling 24-hour observations. Sweep the character's local
	-- scopes before accepting peer data; touched relayed scopes are pruned below.
	saleCollector:PruneRealmSales()

	if packet.kind == "PULL" then
		ScheduleAdvertisement(distribution, sender, packet.data.requestID)
	elseif packet.kind == "ADVERTISE" then
		local pending = type(packet.data.requestID) == "string"
			and IsSelf(packet.data.target) and pendingPulls[packet.data.requestID]
		if pending and pending.distribution == distribution and type(packet.data.scopes) == "table" then
			pending.advertisements[sender] = packet.data.scopes
		end
	elseif packet.kind == "REQUEST" then
		SendRequestedPush(distribution, sender, packet.data)
	elseif packet.kind == "PUSH" then
		MergeDelta(packet.data)
		ReturnMergedPush(sender, packet.data)
	elseif packet.kind == "RETURN" then
		MergeDelta(packet.data)
	end
end

function module:YAAHA_SCAN_PROCESSED()
	if not CanSyncNow() then
		return
	end
	-- A completed local scan is the normal synchronization trigger. Receiving
	-- peer data never generates another message, preventing echo loops.
	for _, auctionHouseType in pairs(AUCTION_HOUSE_TYPES) do
		local push = BuildPush({ [auctionHouseType] = true })
		local encoded
		if IsInGuild() then
			encoded = SendPush("GUILD", push)
		end
		SendPush("YELL", push, encoded)
	end
end

function module:PLAYER_ENTERING_WORLD(_, isInitialLogin)
	if not isInitialLogin or not CanSyncNow() then
		return
	end
	-- Initial character login is the sole pull operation. Reloading or changing
	-- zones cannot request data, and an unanswered request remains silent.
	if IsInGuild() then
		RequestPush("GUILD")
	end
	RequestPush("YELL")
end

function module:OnEnable()
	InitializePlayerIdentity()
	addon:RegisterComm(COMM_PREFIX, function(...)
		module:OnCommReceived(...)
	end)
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	self:RegisterMessage("YAAHA_SCAN_PROCESSED")
end