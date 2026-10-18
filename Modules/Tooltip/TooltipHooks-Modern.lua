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

function module:OnEnable()
	local tooltips = self:GetTooltipFrames()
	for index = 1, #tooltips do
		local tooltip = tooltips[index]
		tooltip:HookScript("OnTooltipCleared", function(activeTooltip)
			module:ClearTooltipState(activeTooltip)
		end)
		tooltip:HookScript("OnHide", function(activeTooltip)
			module:ClearTooltipDisplayState(activeTooltip)
		end)
	end
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnTooltipSetItem)
end