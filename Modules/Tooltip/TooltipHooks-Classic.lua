-- Connects YAAHA to the legacy tooltip scripts and profession tooltip setters.

local GameTooltip = GameTooltip
local hooksecurefunc = hooksecurefunc
local ItemRefTooltip = ItemRefTooltip
local LibStub = LibStub

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local module = addon:GetModule("Tooltip")
local professionScanner = addon:GetModule("ProfessionScanner")

local function OnTooltipSetItem(tooltip)
	local _, link = tooltip:GetItem()
	module:ProcessItemTooltip(tooltip, addon:GetItemID(link), link)
end

local function OnTooltipSetHyperlink(tooltip, link)
	-- ItemRefTooltip is dedicated to clicked chat links, so unlike GameTooltip it
	-- cannot be a transient reagent emitted while a profession recipe is rendered.
	module:ProcessItemTooltip(tooltip, addon:GetItemID(link), link, tooltip == ItemRefTooltip)
end

local function OnTooltipSetSpell(tooltip)
	module:ProcessSpellTooltip(tooltip)
end

local function OnTooltipSetCraftItem(tooltip, recipeIndex, reagentIndex)
	if reagentIndex then
		return
	end

	-- Classic Enchanting can describe an item-producing recipe with an enchant
	-- hyperlink. In that case neither the ordinary item nor spell tooltip scripts
	-- provide YAAHA with an identity, but SetCraftItem still supplies the recipe row.
	module:ProcessRecipeTooltip(tooltip, professionScanner:GetCraftRecipeSpellID(recipeIndex))
end

local function OnTooltipSetCraftSpell(tooltip, recipeIndex)
	-- Classic's Enchanting UI and replacement profession UIs use the Craft-frame
	-- row index here rather than the recipe's spell ID.
	module:ProcessRecipeTooltip(tooltip, professionScanner:GetCraftRecipeSpellID(recipeIndex))
end

local function OnTooltipSetTradeSkillItem(tooltip, recipeIndex, reagentIndex)
	if reagentIndex then
		return
	end
	module:ProcessRecipeTooltip(tooltip, professionScanner:GetTradeSkillRecipeSpellID(recipeIndex))
end

function module:OnEnable()
	local tooltips = self:GetTooltipFrames()
	for index = 1, #tooltips do
		local tooltip = tooltips[index]
		if tooltip:HasScript("OnTooltipSetItem") then
			tooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
		end
		if tooltip.SetHyperlink then
			hooksecurefunc(tooltip, "SetHyperlink", OnTooltipSetHyperlink)
		end
		if tooltip:HasScript("OnTooltipSetSpell") then
			tooltip:HookScript("OnTooltipSetSpell", OnTooltipSetSpell)
		end
		tooltip:HookScript("OnTooltipCleared", function(activeTooltip)
			module:ClearTooltipState(activeTooltip)
		end)
		-- Some replacement profession UIs hide and rebuild GameTooltip without
		-- invoking the clearing sequence above. Forget the deduplication state so
		-- the same recipe receives YAAHA's lines the next time it is displayed.
		tooltip:HookScript("OnHide", function(activeTooltip)
			module:ClearTooltipDisplayState(activeTooltip)
		end)
	end
	if GameTooltip.SetCraftItem then
		hooksecurefunc(GameTooltip, "SetCraftItem", OnTooltipSetCraftItem)
	end
	if GameTooltip.SetCraftSpell then
		hooksecurefunc(GameTooltip, "SetCraftSpell", OnTooltipSetCraftSpell)
	end
	if GameTooltip.SetTradeSkillItem then
		hooksecurefunc(GameTooltip, "SetTradeSkillItem", OnTooltipSetTradeSkillItem)
	end
end