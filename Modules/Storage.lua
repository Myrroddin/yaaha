local C_AutoComplete = C_AutoComplete
local C_EncodingUtil = C_EncodingUtil
local Enum = Enum
local FACTION_ALLIANCE = FACTION_ALLIANCE
local FACTION_HORDE = FACTION_HORDE
local FACTION_NEUTRAL = FACTION_NEUTRAL
local format = string.format
local GetNormalizedRealmName = GetNormalizedRealmName
local LibStub = LibStub
local next = next
local pairs = pairs
local pcall = pcall
local sort = table.sort
local stringGsub = string.gsub
local stringSub = string.sub
local type = type
local UnitFactionGroup = UnitFactionGroup

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local module = addon:NewModule("Storage", "AceEvent-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("YAAHA")

local BASE64_VARIANT = Enum.Base64Variant.StandardUrlSafe
local COMPRESSION_METHOD = Enum.CompressionMethod.Zlib
local FORMAT_VERSION = 1
local playerFaction, localizedPlayerFaction = UnitFactionGroup("player")
local oppositeFaction = playerFaction == "Alliance" and "Horde" or "Alliance"
local oppositeFactionName = oppositeFaction == "Alliance" and FACTION_ALLIANCE or FACTION_HORDE
local oppositeFactionData
local oppositeFactionLoaded = false
local previousPayloads = {}
local restoreFailed = {}
local SCOPES = { "factionrealm", "realm" }

local function ScopeName(scope)
	return scope == "realm" and FACTION_NEUTRAL
		or localizedPlayerFaction or playerFaction
end

local function EncodeAuctionDB(auctionDB)
	local succeeded, serialized = pcall(addon.Serialize, addon, auctionDB)
	if not succeeded or type(serialized) ~= "string" then
		return
	end

	succeeded, serialized = pcall(C_EncodingUtil.CompressString, serialized, COMPRESSION_METHOD)
	if not succeeded or type(serialized) ~= "string" then
		return
	end

	succeeded, serialized = pcall(C_EncodingUtil.EncodeBase64, serialized, BASE64_VARIANT)
	if succeeded and type(serialized) == "string" then
		return serialized
	end
end

local function DecodeAuctionDB(payload)
	if type(payload) ~= "string" then
		return
	end

	local succeeded, decoded = pcall(C_EncodingUtil.DecodeBase64, payload, BASE64_VARIANT)
	if not succeeded or type(decoded) ~= "string" then
		return
	end

	succeeded, decoded = pcall(C_EncodingUtil.DecompressString, decoded, COMPRESSION_METHOD)
	if not succeeded or type(decoded) ~= "string" then
		return
	end

	local called, deserialized, auctionDB = pcall(addon.Deserialize, addon, decoded)
	if called and deserialized and type(auctionDB) == "table" then
		return auctionDB
	end
end

local function DecodeStoredAuctionDB(stored)
	if type(stored) ~= "table" or stored.version ~= FORMAT_VERSION then
		return
	end
	return DecodeAuctionDB(stored.payload) or DecodeAuctionDB(stored.backupPayload)
end

local function NormalizeRealmName(realm)
	return realm and stringGsub(realm, "[%s%-%.]", "") or nil
end

local function LoadOppositeFactionData()
	oppositeFactionLoaded = true
	oppositeFactionData = nil

	local connectedRealms = {}
	local currentRealm = GetNormalizedRealmName()
	if currentRealm then
		connectedRealms[currentRealm] = true
	end
	local realms = C_AutoComplete.GetAutoCompleteRealms()
	for _, realm in pairs(realms or {}) do
		connectedRealms[realm] = true
	end

	local prefix = oppositeFaction .. " - "
	local candidates = {}
	for key, scopeDB in pairs(addon.db.sv.factionrealm or {}) do
		if stringSub(key, 1, #prefix) == prefix then
			local realm = NormalizeRealmName(stringSub(key, #prefix + 1))
			if realm and connectedRealms[realm] then
				candidates[#candidates + 1] = {
					db = scopeDB,
					lastScan = scopeDB.auctionStats and scopeDB.auctionStats.lastScan or 0,
				}
			end
		end
	end
	sort(candidates, function(left, right)
		return left.lastScan > right.lastScan
	end)

	for index = 1, #candidates do
		local scopeDB = candidates[index].db
		local auctionDB = type(scopeDB.auctionDB) == "table" and scopeDB.auctionDB
			or DecodeStoredAuctionDB(scopeDB.compressedAuctionDB)
		if auctionDB and next(auctionDB) then
			oppositeFactionData = {
				auctionDB = auctionDB,
				personalSales = scopeDB.personalSales or {},
				realmSales = scopeDB.realmSales or {},
			}
			return
		end
	end
end

local function RestoreScope(scope)
	local scopeDB = addon.db[scope]
	local stored = scopeDB.compressedAuctionDB
	if stored == nil then
		return
	end
	if type(stored) ~= "table" or stored.version ~= FORMAT_VERSION then
		restoreFailed[scope] = true
		addon:Print(format(
			L["YAAHA could not restore the %s auction database. Its compressed data was preserved."],
			ScopeName(scope)))
		return
	end

	local auctionDB = DecodeAuctionDB(stored.payload)
	local restoredPayload = stored.payload
	if not auctionDB and stored.backupPayload then
		auctionDB = DecodeAuctionDB(stored.backupPayload)
		restoredPayload = stored.backupPayload
		if auctionDB then
			addon:Print(format(L["YAAHA restored the previous copy of the %s auction database."],
				ScopeName(scope)))
		end
	end

	if not auctionDB then
		restoreFailed[scope] = true
		addon:Print(format(
			L["YAAHA could not restore the %s auction database. Its compressed data was preserved."],
			ScopeName(scope)))
		return
	end

	-- Keep the preceding valid payload in memory so the next save can retain one
	-- recoverable generation without leaving a second decompressed table resident.
	previousPayloads[scope] = restoredPayload
	scopeDB.auctionDB = auctionDB
	scopeDB.compressedAuctionDB = nil
end

local function StoreScope(scope)
	local scopeDB = addon.db[scope]
	if restoreFailed[scope] then
		-- Never replace an unreadable payload with the empty AceDB default. Keeping
		-- the original bytes gives a future YAAHA fix or manual recovery a chance.
		return
	end

	local auctionDB = scopeDB.auctionDB
	if type(auctionDB) ~= "table" or not next(auctionDB) then
		scopeDB.compressedAuctionDB = nil
		return
	end

	local payload = EncodeAuctionDB(auctionDB)
	if not payload then
		-- Compression is transactional: the ordinary table remains available for
		-- Blizzard's SavedVariables writer whenever any encoding stage fails.
		return
	end

	scopeDB.compressedAuctionDB = {
		version = FORMAT_VERSION,
		payload = payload,
		backupPayload = previousPayloads[scope],
	}
	scopeDB.auctionDB = nil
end

function module:OnEnable()
	LoadOppositeFactionData()
	self:RegisterEvent("PLAYER_LOGOUT")
end

function module:RestoreAuctionData()
	for _, scope in pairs(SCOPES) do
		RestoreScope(scope)
	end
end

function module:GetOppositeFactionData()
	if not oppositeFactionLoaded then
		LoadOppositeFactionData()
	end
	return oppositeFactionData, oppositeFactionName
end

function module:PLAYER_LOGOUT()
	for _, scope in pairs(SCOPES) do
		StoreScope(scope)
	end
end