local abs = math.abs
local C_Item = C_Item
local coroutineCreate = coroutine.create
local coroutineResume = coroutine.resume
local coroutineStatus = coroutine.status
local coroutineYield = coroutine.yield
local CreateFrame = CreateFrame
local floor = math.floor
local format = string.format
local geterrorhandler = geterrorhandler
local GetItemInfo = C_Item.GetItemInfo
local GetServerTime = GetServerTime
local GetTime = GetTime
local LibStub = LibStub
local max = math.max
local next = next
local pairs = pairs
local RequestLoadItemDataByID = C_Item.RequestLoadItemDataByID
local select = select
local sort = table.sort
local sqrt = math.sqrt
local tostring = tostring
local type = type
local UnitFactionGroup = UnitFactionGroup

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local module = addon:NewModule("DataProcessing")
local disenchantingData = addon:GetModule("DisenchantingData")
local L = LibStub("AceLocale-3.0"):GetLocale("YAAHA")
local playerFaction = UnitFactionGroup("player")

local SECONDS_PER_DAY = 24 * 60 * 60
local MAX_HISTORY_DAYS = 60
local ITEMS_PER_FRAME = 100
local ITEM_DATA_TIMEOUT = 5

-- These are the published relative weights used by AuctionDB. For YAAHA's longer
-- horizons, observations older than fourteen days remain at the final weight of
-- five. Old data therefore reaches a minimum influence instead of becoming stronger.
local marketWeights = {
	[0] = 132,
	[1] = 125,
	[2] = 100,
	[3] = 75,
	[4] = 45,
	[5] = 34,
	[6] = 33,
	[7] = 38,
	[8] = 28,
	[9] = 21,
	[10] = 15,
	[11] = 10,
	[12] = 7,
	[13] = 5,
}

local function NormalizeWeights(lastDay)
	-- The published weights are relative: 132 means "more influential than 100,"
	-- not "multiply the final price by 132." Their average must therefore become
	-- one. For example, normalized weights of 1.5 and 0.5 still total two for two
	-- days, but make the newer day three times as influential as the older day.
	local total = 0
	for age = 0, lastDay do
		total = total + (marketWeights[age] or marketWeights[13])
	end

	local normalized = {}
	-- There are lastDay + 1 entries because age zero is today. Dividing that count
	-- by the original total produces the multiplier which makes all new weights
	-- add up to the number of days while preserving their relative proportions.
	local scale = (lastDay + 1) / total
	for age = 0, lastDay do
		normalized[age] = (marketWeights[age] or marketWeights[13]) * scale
	end
	return normalized
end

local midweekWeights = NormalizeWeights(2)
local weeklyWeights = NormalizeWeights(6)
local biweeklyWeights = NormalizeWeights(13)
local monthlyWeights = NormalizeWeights(29)
local bimonthlyWeights = NormalizeWeights(59)
-- Current market value intentionally has no trend: it reflects one scan and is
-- too volatile to present as meaningful movement to the user.
local trendFields = {
	"midweekMarketValue",
	"weeklyMarketValue",
	"biweeklyMarketValue",
	"monthlyMarketValue",
	"bimonthlyMarketValue",
}

local processingFrame = CreateFrame("Frame")
processingFrame:Hide()

local worker, completed
local totalItems = 0
local processedItems = 0

local function CalculateCurrentMarketValue(buyouts)
	local prices = {}
	local numPrices = 0
	local numObservations = 0

	for price, count in pairs(buyouts) do
		numPrices = numPrices + 1
		prices[numPrices] = price
		numObservations = numObservations + count
	end
	if numObservations == 0 then
		return
	end

	sort(prices)

	-- Work from only the cheapest 30% of observations. Expensive listings are often
	-- speculative outliers rather than representative prices. Every item in a stack
	-- contributes one observation at its unit price, but the histogram lets us count
	-- those observations without constructing a large table containing duplicates.
	local maxObservations = floor(numObservations * 0.30)
	if maxObservations < 1 then
		maxObservations = 1
	end

	local accepted = 0
	local total = 0
	local previousPrice
	for index = 1, numPrices do
		local price = prices[index]
		local firstPosition = accepted + 1
		-- Do not consider a sudden 20% price jump after the cheapest 15% has already
		-- been seen. This detects the boundary between the competitively priced group
		-- and a much more expensive group before the later statistics are calculated.
		if previousPrice and firstPosition > numObservations * 0.15 and price >= previousPrice * 1.20 then
			break
		end

		local count = buyouts[price]
		local remaining = maxObservations - accepted
		if count > remaining then
			count = remaining
		end
		accepted = accepted + count
		total = total + price * count
		previousPrice = price
		if accepted == maxObservations then
			break
		end
	end

	-- The arithmetic mean is the center of the accepted prices: their combined
	-- value divided by how many individual item observations were accepted.
	local mean = total / accepted
	local variance = 0
	local remaining = accepted
	for index = 1, numPrices do
		local price = prices[index]
		local count = buyouts[price]
		if count > remaining then
			count = remaining
		end
		-- Each difference says how far a price is from the mean. Squaring it makes
		-- negative and positive distances comparable and makes distant prices matter
		-- more than nearby ones. Multiplying by count accounts for repeated items.
		variance = variance + (price - mean) ^ 2 * count
		remaining = remaining - count
		if remaining == 0 then
			break
		end
	end

	-- Variance is the average squared distance from the mean. Its unit is therefore
	-- copper squared; the square root converts it back into copper. The result is
	-- standard deviation, a practical measure of the normal price spread.
	local deviation = sqrt(variance / accepted)
	local correctedTotal = 0
	local correctedCount = 0
	remaining = accepted
	for index = 1, numPrices do
		local price = prices[index]
		local count = buyouts[price]
		if count > remaining then
			count = remaining
		end
		-- Keep prices no farther than one-and-a-half standard deviations from the
		-- mean, removing unusually distant values before calculating the final mean.
		if abs(mean - price) <= 1.5 * deviation then
			correctedTotal = correctedTotal + price * count
			correctedCount = correctedCount + count
		end
		remaining = remaining - count
		if remaining == 0 then
			break
		end
	end

	-- A zero deviation means every accepted observation is identical. The fallback
	-- also protects against floating-point boundary noise excluding the whole slice.
	local correctedMean = correctedCount > 0 and correctedTotal / correctedCount or mean
	return floor(correctedMean + 0.5)
end

local function CopyAndPruneHistory(history, scanTime)
	local result = {}
	if history then
		for index = 1, #history do
			local observation = history[index]
			local timestamp = observation.timestamp
			local value = observation.value

			-- Expiration happens only while processing a completed scan. Until then,
			-- even data older than sixty days remains untouched in SavedVariables.
			local age = timestamp and scanTime - timestamp
			if value and age and age >= 0
				and age < MAX_HISTORY_DAYS * SECONDS_PER_DAY then
				result[#result + 1] = {
					timestamp = timestamp,
					value = value,
					synced = observation.synced,
				}
			end
		end
	end
	sort(result, function(left, right)
		return left.timestamp < right.timestamp
			or left.timestamp == right.timestamp and left.value < right.value
	end)
	return result
end

local function BuildRollingBands(history, scanTime)
	local bands = {}
	for index = 1, #history do
		local observation = history[index]
		-- Band zero is the rolling 24 hours immediately before this scan, band one
		-- is the preceding 24 hours, and so forth. The boundaries therefore follow
		-- the scan time rather than midnight or the player's local time zone.
		local age = floor((scanTime - observation.timestamp) / SECONDS_PER_DAY)
		if age >= 0 and age < MAX_HISTORY_DAYS then
			local band = bands[age]
			if not band then
				band = { total = 0, count = 0 }
				bands[age] = band
			end
			band.total = band.total + observation.value
			band.count = band.count + 1
		end
	end
	return bands
end

local function CalculateRollingValue(bands, numDays, weights)
	local total = 0
	local totalWeight = 0

	for age = 0, numDays - 1 do
		local band = bands[age]
		if band and band.count > 0 then
			-- TSM first averages all scans in an age band, preventing a day on which
			-- the user scans frequently from overpowering a day with only one scan.
			local value = band.total / band.count
			-- The longer horizons hold at the curve's minimum after day fourteen, so
			-- older observations remain useful without regaining influence.
			local weight = weights[age]
			total = total + value * weight
			totalWeight = totalWeight + weight
		end
	end

	-- Dividing the weighted total by the weights actually used produces a weighted
	-- average. Missing days contribute neither a value nor a weight, so they cannot
	-- artificially drag the result toward zero. Prices are rounded to whole copper.
	return totalWeight > 0 and floor(total / totalWeight + 0.5) or nil
end

local function ProcessItem(oldData, scanData, scanTime)
	local history = CopyAndPruneHistory(oldData and oldData.history, scanTime)
	local currentMarketValue

	if scanData and scanData.buyouts then
		-- Current market value belongs exclusively to this scan. Every completed value
		-- enters history; the rolling calculations normalize market movement over time.
		currentMarketValue = CalculateCurrentMarketValue(scanData.buyouts)
		if currentMarketValue then
			history[#history + 1] = { timestamp = scanTime, value = currentMarketValue }
		end
	end

	local bands = BuildRollingBands(history, scanTime)
	local result = {
		auctionCount = scanData and scanData.auctionCount or nil,
		auctionQuantity = scanData and scanData.auctionQuantity or nil,
		minBid = scanData and scanData.minBid or nil,
		minBuyout = scanData and scanData.minBuyout or nil,
		currentMarketValue = currentMarketValue,
		-- This timestamp describes the current scan value only. Historical observations
		-- retain their own timestamps when an item is absent from the current scan.
		lastScan = scanData and scanTime or nil,
		history = history,
		midweekMarketValue = CalculateRollingValue(bands, 3, midweekWeights),
		weeklyMarketValue = CalculateRollingValue(bands, 7, weeklyWeights),
		biweeklyMarketValue = CalculateRollingValue(bands, 14, biweeklyWeights),
		monthlyMarketValue = CalculateRollingValue(bands, 30, monthlyWeights),
		bimonthlyMarketValue = CalculateRollingValue(bands, 60, bimonthlyWeights),
	}

	-- Each horizon is compared only with its own value from the preceding scan.
	-- Keeping the comparisons keyed by price field makes tooltip lookup unambiguous.
	local trends = {}
	for index = 1, #trendFields do
		local field = trendFields[index]
		local previousValue = oldData and oldData[field]
		local currentValue = result[field]
		if previousValue and previousValue > 0 and currentValue then
			-- Divide the price difference by the previous value to express the change
			-- relative to where it began; multiplying by 100 converts it to a percentage.
			-- Example: (120 - 100) / 100 * 100 is a 20% increase.
			local change = (currentValue - previousValue) / previousValue * 100
			trends[field] = {
				direction = change > 0 and "up" or change < 0 and "down" or "none",
				percent = abs(change),
				value = abs(currentValue - previousValue),
			}
		end
	end
	if next(trends) then
		result.trends = trends
	end

	return next(history) and result or scanData and result or nil
end

local function LoadVendorItemData(scanDB)
	local pending = {}
	for itemID, scanData in pairs(scanDB) do
		if scanData.auctions and select(11, GetItemInfo(itemID)) == nil then
			pending[itemID] = true
			RequestLoadItemDataByID(itemID)
		end
	end

	-- Replicated results may arrive before the item cache. Give requested records a
	-- bounded opportunity to load; an unavailable item is safely omitted from flips.
	local deadline = GetTime() + ITEM_DATA_TIMEOUT
	while next(pending) and GetTime() < deadline do
		local checked = 0
		for itemID in pairs(pending) do
			if select(11, GetItemInfo(itemID)) ~= nil then
				pending[itemID] = nil
			end
			checked = checked + 1
			if checked % ITEMS_PER_FRAME == 0 then
				coroutineYield()
			end
		end
		if next(pending) then
			coroutineYield()
		end
	end
end

local function IsVendorFlipCandidate(price, vendorSell)
	return price > 0 and price <= vendorSell
end

local function BuildVendorItem(itemID, scanData)
	if not scanData or not scanData.auctions then
		return
	end

	local vendorSell = select(11, GetItemInfo(itemID))
	if not vendorSell or vendorSell <= 0 then
		return
	end

	local result = { vendorSell = vendorSell, auctions = {} }
	-- Cache break-even listings as well as profitable ones. The profile option is
	-- applied by the future vendor-flip scan, so changing it never requires a new
	-- throttled full scan merely to recover equal-price auctions.
	for count, byCount in pairs(scanData.auctions) do
		for unitBid, byBid in pairs(byCount) do
			for unitBuyout, numAuctions in pairs(byBid) do
				if IsVendorFlipCandidate(unitBid, vendorSell) or IsVendorFlipCandidate(unitBuyout, vendorSell) then
					result.auctions[#result.auctions + 1] = {
						count = count,
						unitBid = unitBid > 0 and unitBid or nil,
						unitBuyout = unitBuyout > 0 and unitBuyout or nil,
						numAuctions = numAuctions,
					}
				end
			end
		end
	end

	return #result.auctions > 0 and result or nil
end

local function BuildDisenchantItem(itemID, scanData, priceDB)
	if not scanData or not scanData.auctions then
		return
	end

	local disenchant = disenchantingData:GetValue(itemID, nil, priceDB)
	if not disenchant or not disenchant.expectedValue or disenchant.expectedValue <= 0 then
		return
	end

	local result = {
		expectedValue = disenchant.expectedValue,
		auctions = {},
	}
	-- Equipment cannot stack, but identical copies at the same buyout are combined.
	-- The live deal search still resolves and purchases each physical listing alone.
	for count, byCount in pairs(scanData.auctions) do
		for _, byBid in pairs(byCount) do
			for unitBuyout, numAuctions in pairs(byBid) do
				if unitBuyout > 0 and unitBuyout <= disenchant.expectedValue then
					local key = format("%d:%d", count, unitBuyout)
					local auction = result.auctions[key]
					if auction then
						auction.numAuctions = auction.numAuctions + numAuctions
					else
						result.auctions[key] = {
							count = count,
							buyout = unitBuyout * count,
							numAuctions = numAuctions,
						}
					end
				end
			end
		end
	end

	return next(result.auctions) and result or nil
end

local function FinishProcessing(success, result, vendorList, disenchantList, scope, scanStats, callback)
	processingFrame:Hide()
	worker = nil
	completed = nil

	if success then
		-- The live database changes only after the complete snapshot and its history
		-- have been processed, so tooltips can never observe a half-updated scan.
		addon.db[scope].auctionDB = result
		addon.db[scope].auctionStats = scanStats
		addon.db[scope].disenchantList = disenchantList
		addon.db[scope].vendorList = vendorList
		addon:FireAPIEvent("AUCTION_HOUSE_DATA_UPDATED",
			scope == "realm" and "Neutral" or playerFaction, "scan")
	end

	if callback then
		callback(success)
	end
end

processingFrame:SetScript("OnUpdate", function()
	local success, result, vendorList, disenchantList, scope, scanStats, callback = coroutineResume(worker)
	if not success then
		geterrorhandler()(format(L["YAAHA auction data processing failed: %s"], tostring(result)))
		FinishProcessing(false, nil, nil, nil, completed.scope, nil, completed.callback)
	elseif coroutineStatus(worker) == "dead" then
		FinishProcessing(true, result, vendorList, disenchantList, scope, scanStats, callback)
	end
end)

function module:IsProcessing()
	return worker ~= nil
end

function module:GetProgress()
	return processedItems, totalItems
end

function module:ProcessScan(scope, scanDB, scanStats, callback)
	if worker then
		return false
	end

	local oldDB = addon.db[scope].auctionDB
	local itemIDs = {}
	local seen = {}
	local scanItemIDs = {}
	for itemID in pairs(scanDB) do
		itemIDs[#itemIDs + 1] = itemID
		scanItemIDs[#scanItemIDs + 1] = itemID
		seen[itemID] = true
	end
	for itemID in pairs(oldDB) do
		if not seen[itemID] then
			itemIDs[#itemIDs + 1] = itemID
		end
	end

	totalItems = #itemIDs + #scanItemIDs
	processedItems = 0
	completed = { scope = scope, callback = callback }
	worker = coroutineCreate(function()
		local result = {}
		local vendorList = {}
		local disenchantList = {}
		local scanTime = GetServerTime()
		scanStats.lastScan = scanTime

		LoadVendorItemData(scanDB)

		for index = 1, #itemIDs do
			local itemID = itemIDs[index]
			local currentScanData = scanDB[itemID]
			local itemData = ProcessItem(oldDB[itemID], currentScanData, scanTime)
			if itemData then
				result[itemID] = itemData
			end
			local vendorItem = BuildVendorItem(itemID, currentScanData)
			if vendorItem then
				vendorList[itemID] = vendorItem
			end

			processedItems = index
			if index % ITEMS_PER_FRAME == 0 then
				coroutineYield()
			end
		end

		-- Disenchant values must use the complete newly processed price database;
		-- calculating them during the first loop could miss a material processed later.
		for index = 1, #scanItemIDs do
			local itemID = scanItemIDs[index]
			local disenchantItem = BuildDisenchantItem(itemID, scanDB[itemID], result)
			if disenchantItem then
				disenchantList[itemID] = disenchantItem
			end
			processedItems = #itemIDs + index
			if index % ITEMS_PER_FRAME == 0 then
				coroutineYield()
			end
		end

		return result, vendorList, disenchantList, scope, scanStats, callback
	end)

	processingFrame:Show()
	return true
end

function module:MergeSyncedMarketItem(scope, itemID, incoming, scopeDB)
	scopeDB = scopeDB or addon.db[scope]
	local stored = scopeDB.auctionDB[itemID] or {}
	-- Copy only synchronized market state. Deal-cache and other scope-local fields
	-- must not leak into a peer's canonical item record during a merge.
	local current = {
		auctionCount = stored.auctionCount,
		auctionQuantity = stored.auctionQuantity,
		currentMarketValue = stored.currentMarketValue,
		currentSynced = stored.currentSynced,
		history = stored.history,
		lastScan = stored.lastScan,
		minBid = stored.minBid,
		minBuyout = stored.minBuyout,
	}
	local changed = false
	local now = GetServerTime()
	local history = CopyAndPruneHistory(current.history, now)
	local seen = {}
	for index = 1, #history do
		local observation = history[index]
		seen[format("%d:%d", observation.timestamp, observation.value)] = true
	end
	local incomingHistory = type(incoming.history) == "table" and incoming.history or {}
	for index = 1, #incomingHistory do
		local observation = incomingHistory[index]
		if type(observation) == "table" and type(observation.timestamp) == "number"
			and type(observation.value) == "number" and observation.value > 0
			and observation.timestamp <= now
			and now - observation.timestamp < MAX_HISTORY_DAYS * SECONDS_PER_DAY then
			local key = format("%d:%d", observation.timestamp, observation.value)
			if not seen[key] then
				history[#history + 1] = {
					timestamp = observation.timestamp,
					value = observation.value,
					synced = true,
				}
				seen[key] = true
				changed = true
			end
		end
	end
	sort(history, function(left, right)
		return left.timestamp < right.timestamp
			or left.timestamp == right.timestamp and left.value < right.value
	end)

	-- Two scans can share a one-second server timestamp. Comparing every snapshot
	-- field supplies a stable tie-breaker so both peers retain the same snapshot.
	local function SnapshotKey(data)
		return format("%.17g:%.17g:%.17g:%.17g:%.17g", data.currentMarketValue or 0,
			data.minBid or 0, data.minBuyout or 0, data.auctionCount or 0,
			data.auctionQuantity or 0)
	end

	if type(incoming.lastScan) == "number" and incoming.lastScan <= now
		and (incoming.lastScan > (current.lastScan or 0)
			or incoming.lastScan == (current.lastScan or 0)
			and SnapshotKey(incoming) > SnapshotKey(current)) then
		current.auctionCount = type(incoming.auctionCount) == "number" and incoming.auctionCount or nil
		current.auctionQuantity = type(incoming.auctionQuantity) == "number" and incoming.auctionQuantity or nil
		current.currentMarketValue = type(incoming.currentMarketValue) == "number"
			and incoming.currentMarketValue or nil
		current.lastScan = incoming.lastScan
		current.minBid = type(incoming.minBid) == "number" and incoming.minBid or nil
		current.minBuyout = type(incoming.minBuyout) == "number" and incoming.minBuyout or nil
		current.currentSynced = true
		changed = true
	end

	current.history = history
	-- Recalculate against the newest shared observation rather than each receiver's
	-- wall clock. Identical input sets therefore land in identical rolling bands.
	local referenceTime = current.lastScan or 0
	for index = 1, #history do
		referenceTime = max(referenceTime, history[index].timestamp)
	end
	local bands = BuildRollingBands(history, referenceTime > 0 and referenceTime or now)
	current.midweekMarketValue = CalculateRollingValue(bands, 3, midweekWeights)
	current.weeklyMarketValue = CalculateRollingValue(bands, 7, weeklyWeights)
	current.biweeklyMarketValue = CalculateRollingValue(bands, 14, biweeklyWeights)
	current.monthlyMarketValue = CalculateRollingValue(bands, 30, monthlyWeights)
	current.bimonthlyMarketValue = CalculateRollingValue(bands, 60, bimonthlyWeights)
	local trends = {}
	local previousReference = 0
	for index = 1, #history do
		local timestamp = history[index].timestamp
		if timestamp < referenceTime then
			previousReference = max(previousReference, timestamp)
		end
	end
	if previousReference > 0 then
		local previousBands = BuildRollingBands(history, previousReference)
		local previousValues = {
			midweekMarketValue = CalculateRollingValue(previousBands, 3, midweekWeights),
			weeklyMarketValue = CalculateRollingValue(previousBands, 7, weeklyWeights),
			biweeklyMarketValue = CalculateRollingValue(previousBands, 14, biweeklyWeights),
			monthlyMarketValue = CalculateRollingValue(previousBands, 30, monthlyWeights),
			bimonthlyMarketValue = CalculateRollingValue(previousBands, 60, bimonthlyWeights),
		}
		for index = 1, #trendFields do
			local field = trendFields[index]
			local previousValue = previousValues[field]
			local currentValue = current[field]
			if previousValue and previousValue > 0 and currentValue then
				local change = (currentValue - previousValue) / previousValue * 100
				trends[field] = {
					direction = change > 0 and "up" or change < 0 and "down" or "none",
					percent = abs(change),
					value = abs(currentValue - previousValue),
				}
			end
		end
	end
	current.trends = next(trends) and trends or nil
	scopeDB.auctionDB[itemID] = next(history) and current or current.lastScan and current or nil
	return changed
end