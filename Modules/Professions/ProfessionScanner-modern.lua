-- Provides the modern profession-scanner contract until C_TradeSkillUI collection is implemented.

local LibStub = LibStub

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local module = addon:NewModule("ProfessionScanner")

-- Modern profession recipes require C_TradeSkillUI-backed collection. These
-- methods keep shared tooltip and API callers safe until that collector lands.
function module:GetCharacterName()
	return addon:GetCharacterKey()
end

function module:IsItemKnown()
	return false
end

function module:IsRecipeKnown()
	return false
end

function module:GetCraftRecipeSpellID()
end

function module:GetTradeSkillRecipeSpellID()
end

function module:GetItemCrafting()
end

function module:GetRecipeCrafting()
end

function module:GetMaterialCost()
end