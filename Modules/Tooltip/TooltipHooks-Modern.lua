-- Connects YAAHA to the modern TooltipDataProcessor used by Forever and Retail.

local Enum = Enum
local LibStub = LibStub
local TooltipDataProcessor = TooltipDataProcessor

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local module = addon:GetModule("Tooltip")

local function OnTooltipSetItem(tooltip, data)
	if tooltip.IsForbidden and tooltip:IsForbidden() then
		return
	end
	local _, link = tooltip:GetItem()
	local itemID = data and data.id or addon:GetItemID(link)
	-- Modern bag and inventory tooltips are populated through C_TooltipInfo, so
	-- Classic's OnTooltipSetItem script and SetHyperlink hook do not fire.
	module:ProcessItemTooltip(tooltip, itemID, link, true)
end

local function OnTooltipCleared(tooltip)
	module:ClearTooltipState(tooltip)
end

local function OnTooltipHidden(tooltip)
	module:ClearTooltipDisplayState(tooltip)
end

function module:OnEnable()
	local tooltips = self:GetTooltipFrames()
	for index = 1, #tooltips do
		local tooltip = tooltips[index]
		tooltip:HookScript("OnTooltipCleared", OnTooltipCleared)
		tooltip:HookScript("OnHide", OnTooltipHidden)
	end
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnTooltipSetItem)
end