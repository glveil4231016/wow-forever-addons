local ADDON, PB = ...
local P = {}
PB.Profile = P

P.SELL_PRICE_INDEX = 11
P.caps = { ahReplicate = false, itemInfo = nil, tradeSkill = false, gameRules = false, recipeAll = false }

local RULESETS = {
  { "PvPRuleset", "pvp" },
  { "RoleplayingRuleset", "rp" },
  { "RoleplayingPvPRuleset", "rppvp" },
  { "HardcoreRuleset", "hc" },
}

function P.Detect()
  local _, _, _, iface = GetBuildInfo()
  P.interface = iface or 0
  P.caps.ahReplicate = type(C_AuctionHouse) == "table" and type(C_AuctionHouse.ReplicateItems) == "function"
  P.caps.tradeSkill = type(C_TradeSkillUI) == "table"
  P.caps.gameRules = type(C_GameRules) == "table"
  P.caps.recipeAll = P.caps.tradeSkill and type(C_TradeSkillUI.GetAllRecipeIDs) == "function"
  if type(C_Item) == "table" and type(C_Item.GetItemInfo) == "function" then
    P.caps.itemInfo = "C_Item"
  elseif type(GetItemInfo) == "function" then
    P.caps.itemInfo = "global"
  end
  P.ruleset = P.Ruleset()
  local faction = UnitFactionGroup("player")
  P.faction = (faction == "Horde") and "horde" or "alliance"
end

function P.Ruleset()
  if type(C_GameRules) ~= "table" or type(C_GameRules.IsGameRuleActive) ~= "function" then return "normal" end
  local enum = type(Enum) == "table" and Enum.GameRule or nil
  if not enum then return "normal" end
  for i = 1, #RULESETS do
    local value = enum[RULESETS[i][1]]
    if value then
      local ok, active = pcall(C_GameRules.IsGameRuleActive, value)
      if ok and active then return RULESETS[i][2] end
    end
  end
  return "normal"
end

function P.MarketKey()
  return tostring(P.ruleset or "unknown") .. "|" .. tostring(P.faction or "unknown")
end

function P.VendorPrice(itemID)
  if not itemID or not P.caps.itemInfo then return nil end
  local ok, v
  if P.caps.itemInfo == "C_Item" then
    ok, v = pcall(function() return select(P.SELL_PRICE_INDEX, C_Item.GetItemInfo(itemID)) end)
  else
    ok, v = pcall(function() return select(P.SELL_PRICE_INDEX, GetItemInfo(itemID)) end)
  end
  if ok and type(v) == "number" and v > 0 then return v end
  return nil
end

function P.StatusLine()
  return string.format("接口 %s · 市场 %s · AH %s · 专业 %s · 配方全量 %s",
    tostring(P.interface), P.MarketKey(),
    P.caps.ahReplicate and "可用" or "缺失",
    P.caps.tradeSkill and "可用" or "缺失",
    P.caps.recipeAll and "可用" or "未知")
end
