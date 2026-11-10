local ADDON, PB = ...

local function say(fmt, ...)
  print("|cff516cefProfitBoard|r " .. string.format(fmt, ...))
end

local function fmtResult(r)
  local rp = r.recipe
  local name = rp.name or ("配方#" .. tostring(rp.id))
  if r.missing then
    local names = {}
    local list = r.missingItems or {}
    for i = 1, math.min(3, #list) do names[#names + 1] = PB.Util.ItemName(list[i]) end
    local suffix = #names > 0 and (" 缺价：" .. table.concat(names, "、")) or ""
    return string.format("%s |cff999999缺价 %d%s|r", name, r.missingCount or 0, suffix)
  end
  return string.format("%s → %s | 成本 %s | 售价 %s | 利润 %s | 利润率 %.0f%%",
    name, PB.Util.ItemName(rp.result.itemID),
    PB.Util.FormatMoney(r.cost), PB.Util.FormatMoney(r.value),
    PB.Util.FormatMoney(r.profit), r.margin or 0)
end

local handlers = {}

function handlers.scan()
  local market = PB.MarketInstance
  if not market then return say("尚未初始化") end
  local ok, err = market:Scan(function(success, detail)
    if success then
      say("扫描完成，第 %d 次", detail or 0)
      PB.Compute.Run(market, PB.ConfigInstance.db.settings)
    else
      say("扫描未完成：%s", tostring(detail or err))
    end
  end)
  if not ok then say("%s", tostring(err)) end
end

function handlers.top(rest)
  local n = tonumber(rest) or 20
  local results = PB.Compute.results or {}
  if #results == 0 then return say("还没有结果：先 /pb scan，再 /pb top") end
  say("利润前 %d 条：", n)
  for i = 1, math.min(n, #results) do
    say("%d. %s", i, fmtResult(results[i]))
  end
end

function handlers.price(rest)
  local itemID = tonumber(rest)
  if not itemID and rest then itemID = tonumber(rest:match("item:(%d+)")) end
  if not itemID then return say("用法：/pb price 2589") end
  local market = PB.MarketInstance
  if not market then return say("尚未初始化") end
  local p = market:PriceOf(itemID)
  if not p.min then return say("物品 %d 没有价格数据", itemID) end
  say("%s（%d）：最低 %s · 深度 %s · 挂单 %s · 总量 %s · 卖店 %s", PB.Util.ItemName(itemID), itemID,
    PB.Util.FormatMoney(p.min), PB.Util.FormatMoney(PB.Util.Round(p.ah or 0)),
    tostring(p.num or 0), tostring(p.qty or 0),
    p.vendor and PB.Util.FormatMoney(p.vendor) or "无")
  local med = market:MedianPrice(itemID, 7)
  say("7 日中位：%s", med and PB.Util.FormatMoney(PB.Util.Round(med)) or "历史不足")
end

function handlers.status()
  say("%s", PB.Profile.StatusLine())
  local market = PB.MarketInstance
  if market then
    local n = 0
    for _ in pairs(market.market.items) do n = n + 1 end
    say("价格库：%d 个物品 · 扫描 %d 次 · 上次 %s", n, market.market.scanCount or 0,
      (market.market.updatedAt or 0) > 0 and date("%m-%d %H:%M", market.market.updatedAt) or "从未")
    if market.market.partial then say("|cffffaa00上次扫描不完整|r") end
  end
  say("配方：%d 条（静态表版本：%s）", PB.RecipeSource.Count(),
    (PB.StaticRecipes and PB.StaticRecipes.version ~= "" and PB.StaticRecipes.version) or "无")
  say("结果：%d 条", #(PB.Compute.results or {}))
end

function handlers.filter(rest)
  local key, value = (rest or ""):match("^(%S+)%s+(.+)$")
  if not key then
    return say("用法：/pb filter profit 10000 | margin 20 | listings 10 | learned 1 | missing 0")
  end
  local cfg = PB.ConfigInstance
  if not cfg then return say("尚未初始化") end
  if key == "profit" then
    local v = PB.Util.ParseMoney(value)
    if not v then return say("数值无效") end
    cfg:Set("minProfit", v)
  elseif key == "margin" then
    cfg:Set("minMarginPercent", tonumber(value) or 0)
  elseif key == "listings" then
    cfg:Set("maxListings", tonumber(value) or 0)
  elseif key == "learned" then
    cfg:Set("onlyLearned", value == "1" or value == "true")
  elseif key == "missing" then
    cfg:Set("hideMissingPrices", not (value == "1" or value == "true"))
  else
    return say("未知筛选键 %s", key)
  end
  if PB.UI then PB.UI.Refresh() end
  say("已设置 %s = %s", key, value)
end

function handlers.export()
  if PB.Export then PB.Export.CSV() end
end

function handlers.import(rest)
  if PB.Export then PB.Export.Import(rest) end
end

function handlers.reset(rest)
  local which = (rest or ""):match("^(%S+)") or "all"
  local db = ProfitBoardDB
  if which == "market" or which == "all" then db.markets = {} end
  if which == "config" or which == "all" then db.settings = {} end
  PB.ConfigInstance:Load(db)
  PB.MarketInstance = PB.Market.New(db, PB.Profile.MarketKey())
  say("已重置 %s", which)
end

local function dispatch(msg)
  local cmd, rest = (msg or ""):match("^(%S*)%s*(.-)$")
  cmd = (cmd or ""):lower()
  if cmd == "" then
    if PB.UI then PB.UI.Toggle() end
    return
  end
  local fn = handlers[cmd]
  if not fn then
    return say("未知命令 %s。可用：scan / top / price / filter / export / import / status / reset", cmd)
  end
  local ok, err = pcall(fn, rest)
  if not ok then say("命令出错：%s", tostring(err)) end
end

SLASH_PROFITBOARD1 = "/pb"
SLASH_PROFITBOARD2 = "/profitboard"
SlashCmdList["PROFITBOARD"] = dispatch
