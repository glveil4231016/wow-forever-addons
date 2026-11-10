local ADDON = ...
local lines = {}

local function add(fmt, ...)
  lines[#lines + 1] = string.format(fmt, ...)
end

local function api(label, tbl, key)
  add("%s %s", (type(tbl) == "table" and type(tbl[key]) ~= "nil") and "[OK]  " or "[MISS]", label)
end

local function dump(label, ...)
  local n = select("#", ...)
  local parts = {}
  for i = 1, n do
    parts[#parts + 1] = string.format("%d=%s", i, tostring((select(i, ...))))
  end
  add("%s -> %s", label, table.concat(parts, " | "))
end

local function probeStatic()
  local b1, b2, b3, b4 = GetBuildInfo()
  add("build=%s.%s date=%s interface=%s locale=%s",
    tostring(b1), tostring(b2), tostring(b3), tostring(b4), tostring(GetLocale()))
  add("projectID=%s", tostring(WOW_PROJECT_ID))
  add("--- namespaces ---")
  api("C_AuctionHouse.ReplicateItems", C_AuctionHouse, "ReplicateItems")
  api("C_AuctionHouse.GetNumReplicateItems", C_AuctionHouse, "GetNumReplicateItems")
  api("C_AuctionHouse.GetReplicateItemInfo", C_AuctionHouse, "GetReplicateItemInfo")
  api("C_AuctionHouse.GetReplicateItemLink", C_AuctionHouse, "GetReplicateItemLink")
  api("C_TradeSkillUI.GetAllRecipeIDs", C_TradeSkillUI, "GetAllRecipeIDs")
  api("C_TradeSkillUI.GetRecipeInfo", C_TradeSkillUI, "GetRecipeInfo")
  api("C_TradeSkillUI.GetRecipeOutputItems", C_TradeSkillUI, "GetRecipeOutputItems")
  api("C_TradeSkillUI.GetRecipeReagentItems", C_TradeSkillUI, "GetRecipeReagentItems")
  api("C_TradeSkillUI.GetRecipeSchematic", C_TradeSkillUI, "GetRecipeSchematic")
  api("C_TradeSkillUI.IsRecipeLearned", C_TradeSkillUI, "IsRecipeLearned")
  api("C_Item.GetItemInfo", C_Item, "GetItemInfo")
  api("C_Item.GetItemNameByID", C_Item, "GetItemNameByID")
  api("C_GameRules.IsGameRuleActive", C_GameRules, "IsGameRuleActive")
  api("global.GetItemInfo", _G, "GetItemInfo")
  add("--- professions ---")
  local okProf, p1, p2 = pcall(GetProfessions)
  add("GetProfessions ok=%s v1=%s v2=%s", tostring(okProf), tostring(p1), tostring(p2))
  if okProf and p1 then
    local ok2, name, _, skill, maxLevel = pcall(GetProfessionInfo, p1)
    add("prof1 ok=%s name=%s skill=%s/%s", tostring(ok2), tostring(name), tostring(skill), tostring(maxLevel))
  end
  add("--- item api shape (2589) ---")
  if C_Item and C_Item.GetItemInfo then dump("C_Item.GetItemInfo(2589)", C_Item.GetItemInfo(2589)) end
  if type(GetItemInfo) == "function" then dump("GetItemInfo(2589)", GetItemInfo(2589)) end
  add("--- GameRule enum ---")
  if type(Enum) == "table" and type(Enum.GameRule) == "table" then
    for k, v in pairs(Enum.GameRule) do add("GameRule.%s=%s", tostring(k), tostring(v)) end
  end
end

local probeFrame, scanStart, collect

local function finish()
  add("--- auction house snapshot ---")
  add("total=%s elapsed=%.2fs", tostring(collect and collect.total), scanStart and (GetTime() - scanStart) or -1)
  for i = 1, math.min(3, (collect and collect.total) or 0) do
    dump("Replicate[" .. i .. "]", C_AuctionHouse.GetReplicateItemInfo(i))
    local ok, link = pcall(C_AuctionHouse.GetReplicateItemLink, i)
    add("Replicate[%d].link ok=%s %s", i, tostring(ok), tostring(link))
  end
  print("===== ProfitProbe start =====")
  for i = 1, #lines do print(lines[i]) end
  print("===== ProfitProbe end =====")
end

local function onUpdate()
  if not collect then return end
  if GetTime() - scanStart > 120 then
    add("TIMEOUT after 120s, read=%s/%s", tostring(collect.i), tostring(collect.total))
    probeFrame:Hide()
    finish()
    return
  end
  local spent = 0
  local i = collect.i
  while i < collect.total and spent < 0.006 do
    local t0 = GetTime()
    pcall(C_AuctionHouse.GetReplicateItemInfo, i)
    i = i + 1
    spent = spent + (GetTime() - t0)
  end
  collect.i = i
  if i >= collect.total then
    probeFrame:Hide()
    finish()
  end
end

local function startScan()
  if not (C_AuctionHouse and C_AuctionHouse.ReplicateItems) then
    add("AH replicate API missing")
    finish()
    return
  end
  add("ReplicateItems ok=%s", tostring(pcall(C_AuctionHouse.ReplicateItems)))
  scanStart = GetTime()
  collect = { i = 1, total = 0 }
  probeFrame = CreateFrame("Frame")
  probeFrame:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
  probeFrame:SetScript("OnEvent", function()
    collect.total = C_AuctionHouse.GetNumReplicateItems() or 0
    add("REPLICATE_ITEM_LIST_UPDATE total=%s", tostring(collect.total))
    probeFrame:SetScript("OnUpdate", onUpdate)
  end)
  C_Timer.After(15, function()
    if collect and collect.total == 0 then
      add("no REPLICATE_ITEM_LIST_UPDATE within 15s (AH not open?)")
      probeFrame:Hide()
      finish()
    end
  end)
end

SLASH_PROFITPROBE1 = "/probe"
SlashCmdList["PROFITPROBE"] = function()
  lines = {}
  probeStatic()
  startScan()
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, _, name)
  if name == ADDON then
    print("ProfitProbe 已加载。打开拍卖行后输入 /probe，把输出整段贴回。")
  end
end)
