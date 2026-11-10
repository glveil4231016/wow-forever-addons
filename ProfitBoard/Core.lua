local ADDON, PB = ...
PB.addonName = ADDON

local listeners = {}
local started = false

function PB:On(event, fn)
  listeners[event] = listeners[event] or {}
  listeners[event][#listeners[event] + 1] = fn
end

function PB:Fire(event, ...)
  local list = listeners[event]
  if not list then return end
  for i = 1, #list do
    local ok, err = pcall(list[i], ...)
    if not ok then print("|cffff5555ProfitBoard|r 事件 " .. tostring(event) .. " 失败：" .. tostring(err)) end
  end
end

local function initDB()
  if type(ProfitBoardDB) ~= "table" then ProfitBoardDB = {} end
  if type(ProfitBoardCache) ~= "table" then ProfitBoardCache = {} end
  ProfitBoardDB.markets = ProfitBoardDB.markets or {}
end

local function safeInit(label, fn)
  local ok, err = pcall(fn)
  if not ok then
    print(string.format("|cffff5555ProfitBoard|r 模块 %s 初始化失败：%s", label, tostring(err)))
  end
  return ok
end

local function start()
  if started then return end
  started = true
  initDB()

  safeInit("Profile", function() PB.Profile.Detect() end)
  safeInit("Config", function() PB.ConfigInstance = PB.Config.New(ProfitBoardDB) end)
  safeInit("Market", function()
    PB.MarketInstance = PB.Market.New(ProfitBoardDB, PB.Profile.MarketKey())
    if next(PB.MarketInstance.market.items) == nil
      and type(ProfitBoardDB.snapshotText) == "string"
      and ProfitBoardDB.snapshotText ~= "" then
      local n = PB.MarketInstance:RestoreFromText(ProfitBoardDB.snapshotText)
      if n > 0 then
        print("|cff516cefProfitBoard|r 已从文本快照恢复 " .. n .. " 个物品价格")
      end
    end
  end)
  safeInit("Recipes", function()
    local n = PB.RecipeSource.Refresh()
    print("|cff516cefProfitBoard|r 配方载入 " .. tostring(n) .. " 条")
  end)
  safeInit("Compute", function()
    if PB.MarketInstance then
      PB.Compute.Run(PB.MarketInstance, ProfitBoardDB.settings)
    end
  end)
  print(PB.Profile.StatusLine())
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("AUCTION_HOUSE_SHOW")
f:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 == ADDON then start() end
    return
  end
  if event == "PLAYER_LOGIN" then
    start()
    print("|cff516cefProfitBoard|r 打开拍卖行后输入 /pb scan 更新价格")
    return
  end
  if event == "AUCTION_HOUSE_SHOW" then
    local market = PB.MarketInstance
    local cfg = PB.ConfigInstance
    if market and cfg then
      if time() - (market.market.updatedAt or 0) >= cfg:Get("scanCooldownSec") then
        print("|cff516cefProfitBoard|r 价格已过期，输入 /pb scan 全量扫描")
      end
    end
  end
end)
