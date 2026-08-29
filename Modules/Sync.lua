local C_EncodingUtil = C_EncodingUtil
local C_Timer = C_Timer
local Enum = Enum
local FACTION_NEUTRAL = FACTION_NEUTRAL
local GetNormalizedRealmName = GetNormalizedRealmName
local GetServerTime = GetServerTime
local IsInGuild = IsInGuild
local IsInInstance = IsInInstance
local LibStub = LibStub
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

local COMM_PREFIX = "YAAHA1"
local PROTOCOL_VERSION = 1
local SECONDS_PER_DAY = 24 * 60 * 60
local playerFaction = UnitFactionGroup("player")
local playerName, playerRealm, playerFullName
local manifestCooldown = {}
local BASE64_VARIANT = Enum.Base64Variant.StandardUrlSafe

local function InitializePlayerIdentity()
	playerName, playerRealm = UnitFullName("player")
	playerRealm = playerRealm or GetNormalizedRealmName()
	playerFullName = playerRealm and playerRealm ~= "" and playerName .. "-" .. playerRealm or playerName
end

local function IsSelf(sender)
	return sender == playerName or sender == playerFullName
end

local function ScopeEnabled(scope)
	return scope == "factionrealm" and addon.db.profile.sendAndReceiveFactionRealm
		or scope == "realm" and addon.db.profile.sendAndReceiveRealm
end

local function ScopeAllowed(scope, faction)
	return ScopeEnabled(scope) and (scope == "realm" or faction == playerFaction)
end

local function AnySyncEnabled()
	return addon.db.profile.sendAndReceiveFactionRealm or addon.db.profile.sendAndReceiveRealm
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

local function MarketSignature(itemData)
	local parts = {}
	if itemData.lastScan then
		parts[#parts + 1] = "C:" .. itemData.lastScan .. ":" .. (itemData.currentMarketValue or 0)
			.. ":" .. (itemData.minBid or 0) .. ":" .. (itemData.minBuyout or 0)
			.. ":" .. (itemData.auctionCount or 0) .. ":" .. (itemData.auctionQuantity or 0)
	end
	for index = 1, #(itemData.history or {}) do
		local observation = itemData.history[index]
		if observation.timestamp and observation.value then
			parts[#parts + 1] = "H:" .. observation.timestamp .. ":" .. observation.value
		end
	end
	sort(parts)
	return tableConcat(parts, "|")
end

local function StatsSignature(stats)
	return type(stats) == "table" and type(stats.lastScan) == "number"
		and stats.lastScan .. ":" .. (stats.totalListings or 0) .. ":" .. (stats.totalItems or 0) or nil
end

local function BuildManifest()
	local scopes = {}
	for _, scope in pairs({ "factionrealm", "realm" }) do
		if ScopeEnabled(scope) then
			local market = {}
			for itemID, itemData in pairs(addon.db[scope].auctionDB) do
				local signature = MarketSignature(itemData)
				if signature ~= "" then
					market[itemID] = signature
				end
			end
			local sales = {}
			for itemID, saleData in pairs(addon.db[scope].realmSales) do
				local ids = GetSaleIDs(saleData)
				if next(ids) then
					sales[itemID] = ids
				end
			end
			-- Auction databases are keyed by itemID, so #table cannot describe whether
			-- they contain data. Do not advertise an enabled but empty scope.
			local stats = StatsSignature(addon.db[scope].auctionStats)
			if next(market) or next(sales) or stats then
				scopes[scope] = { market = market, sales = sales, stats = stats }
			end
		end
	end
	return { faction = playerFaction, scopes = scopes }
end

local function SendManifest(target)
	if not CanSyncNow() then
		return
	end
	SendPacket("MANIFEST", BuildManifest(), "WHISPER", target, "NORMAL")
end

local function SendManifestIfNeeded(target)
	local now = GetServerTime()
	if (manifestCooldown[target] or 0) > now then
		return
	end
	manifestCooldown[target] = now + 60
	C_Timer.After(random(1, 3), function()
		SendManifest(target)
	end)
end

local function BuildRequest(manifest)
	local scopes = {}
	local remoteScopes = type(manifest.scopes) == "table" and manifest.scopes or {}
	for scope, remote in pairs(remoteScopes) do
		if ScopeAllowed(scope, manifest.faction) and type(remote) == "table" then
			local market = {}
			local remoteMarket = type(remote.market) == "table" and remote.market or {}
			for itemID, signature in pairs(remoteMarket) do
				local localData = addon.db[scope].auctionDB[itemID]
				if type(itemID) == "number" and type(signature) == "string"
					and signature ~= (localData and MarketSignature(localData) or "") then
					market[itemID] = true
				end
			end
			local sales = {}
			local remoteSales = type(remote.sales) == "table" and remote.sales or {}
			for itemID, remoteIDs in pairs(remoteSales) do
				local localData = addon.db[scope].realmSales[itemID]
				if type(itemID) == "number" and type(remoteIDs) == "table" then
					local knownIDs = localData and GetSaleIDs(localData) or {}
					local missing = {}
					for syncID in pairs(remoteIDs) do
						if type(syncID) == "string" and not knownIDs[syncID] then
							missing[syncID] = true
						end
					end
					if next(missing) then
						sales[itemID] = missing
					end
				end
			end
			local stats = type(remote.stats) == "string"
				and remote.stats ~= StatsSignature(addon.db[scope].auctionStats) or false
			if stats then
				-- A scan-wide snapshot also communicates absence. Request every item in
				-- that snapshot before clearing older current values locally.
				for itemID in pairs(remoteMarket) do
					if type(itemID) == "number" then
						market[itemID] = true
					end
				end
			end
			if next(market) or next(sales) or stats then
				scopes[scope] = { market = market, sales = sales, stats = stats }
			end
		end
	end
	return { faction = playerFaction, scopes = scopes }
end

local function CopyMarketDelta(itemData)
	local delta = { history = {} }
	if itemData.lastScan then
		for _, field in pairs({ "auctionCount", "auctionQuantity", "currentMarketValue", "lastScan",
			"minBid", "minBuyout" }) do
			delta[field] = itemData[field]
		end
	end
	for index = 1, #(itemData.history or {}) do
		local observation = itemData.history[index]
		if observation.timestamp then
			delta.history[#delta.history + 1] = {
				timestamp = observation.timestamp,
				value = observation.value,
			}
		end
	end
	return (delta.lastScan or #delta.history > 0) and delta or nil
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

local function BuildDelta(request)
	local scopes = {}
	local requestedScopes = type(request.scopes) == "table" and request.scopes or {}
	for scope, wanted in pairs(requestedScopes) do
		if ScopeAllowed(scope, request.faction) and type(wanted) == "table" then
			local market = {}
			local wantedMarket = type(wanted.market) == "table" and wanted.market or {}
			for itemID, requested in pairs(wantedMarket) do
				local itemData = type(itemID) == "number" and requested == true
					and addon.db[scope].auctionDB[itemID]
				local delta = itemData and CopyMarketDelta(itemData)
				if delta then
					market[itemID] = delta
				end
			end
			local sales = {}
			local wantedSales = type(wanted.sales) == "table" and wanted.sales or {}
			for itemID, wantedIDs in pairs(wantedSales) do
				local saleData = addon.db[scope].realmSales[itemID]
				local delta = saleData and type(wantedIDs) == "table"
					and CopySaleDelta(saleData, wantedIDs)
				if delta then
					sales[itemID] = delta
				end
			end
			local stats = wanted.stats == true and addon.db[scope].auctionStats or nil
			if next(market) or next(sales) or stats then
				scopes[scope] = { market = market, sales = sales, stats = stats }
			end
		end
	end
	return { faction = playerFaction, scopes = scopes }
end

local function MergeSaleObservation(scope, itemID, incoming)
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
	local realmSales = addon.db[scope].realmSales
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
	local incomingScopes = type(delta.scopes) == "table" and delta.scopes or {}
	for scope, incoming in pairs(incomingScopes) do
		if ScopeAllowed(scope, delta.faction) and type(incoming) == "table" then
			local received = false
			local incomingStats = incoming.stats
			if type(incomingStats) == "table" and type(incomingStats.lastScan) == "number"
				and type(incomingStats.totalListings) == "number" and type(incomingStats.totalItems) == "number"
				and incomingStats.lastScan >= 0 and incomingStats.totalListings >= 0
				and incomingStats.totalItems >= 0
				and incomingStats.lastScan <= GetServerTime()
				and (incomingStats.lastScan > ((addon.db[scope].auctionStats or {}).lastScan or 0)
					or incomingStats.lastScan == ((addon.db[scope].auctionStats or {}).lastScan or 0)
					and StatsSignature(incomingStats) > (StatsSignature(addon.db[scope].auctionStats) or "")) then
				local auctionDB = addon.db[scope].auctionDB
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
				addon.db[scope].auctionStats = {
					lastScan = incomingStats.lastScan,
					totalItems = incomingStats.totalItems,
					totalListings = incomingStats.totalListings,
				}
				received = true
			end
			local incomingMarket = type(incoming.market) == "table" and incoming.market or {}
			for itemID, itemData in pairs(incomingMarket) do
				if type(itemID) == "number" and itemID > 0 and type(itemData) == "table" then
					if dataProcessing:MergeSyncedMarketItem(scope, itemID, itemData) then
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
						if MergeSaleObservation(scope, itemID, observations[index]) then
							received = true
						end
					end
				end
			end
			if received then
				addon:Printf(L["Received auction data for the %s auction house."],
					scope == "realm" and FACTION_NEUTRAL or playerFaction)
				addon:FireAPIEvent("AUCTION_HOUSE_DATA_UPDATED",
					scope == "realm" and "Neutral" or playerFaction, "sync")
			end
		end
	end
end

local function SendDiscovery(distribution)
	if not CanSyncNow() then
		return
	end
	SendPacket("HELLO", { faction = playerFaction }, distribution, nil, "NORMAL")
end

function module:OnCommReceived(_, text, _, sender)
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
	-- Realm sales are rolling 24-hour observations. Sweep both auction-house
	-- scopes before comparing or accepting peer data so offline time always counts.
	saleCollector:PruneRealmSales()

	if packet.kind == "HELLO" then
		SendManifestIfNeeded(sender)
	elseif packet.kind == "MANIFEST" then
		-- A manifest doubles as peer discovery. Reply at most once per cooldown so
		-- both peers compare data without bouncing manifests forever.
		SendManifestIfNeeded(sender)
		local request = BuildRequest(packet.data)
		if next(request.scopes) then
			SendPacket("REQUEST", request, "WHISPER", sender, "NORMAL")
		end
	elseif packet.kind == "REQUEST" then
		local delta = BuildDelta(packet.data)
		if next(delta.scopes) then
			SendPacket("DELTA", delta, "WHISPER", sender)
		end
	elseif packet.kind == "DELTA" then
		MergeDelta(packet.data)
	end
end

function module:OnEnable()
	InitializePlayerIdentity()
	addon:RegisterComm(COMM_PREFIX, function(...)
		module:OnCommReceived(...)
	end)
	self:RegisterEvent("AUCTION_HOUSE_SHOW")
	if not CanSyncNow() then
		return
	end
	if IsInGuild() then
		C_Timer.After(random(2, 4), function()
			SendDiscovery("GUILD")
		end)
	end
end

function module:AUCTION_HOUSE_SHOW()
	if not CanSyncNow() then
		return
	end
	-- Guild discovery is scheduled first at login. Keeping nearby discovery later
	-- reduces duplicate handshakes when those audiences overlap.
	C_Timer.After(random(8, 10), function()
		SendDiscovery("YELL")
	end)
end