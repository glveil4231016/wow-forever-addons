local ADDON, PB = ...
local M = {}
PB.Market = M

M.REPLICATE_FIELDS = { id = 13, qty = 12, price = 11 }

function M.DepthFromLadder(ladder, capUnits)
  if type(ladder) ~= "table" or #ladder == 0 then return nil end
  table.sort(ladder, function(a, b) return a.p < b.p end)
  local cap = capUnits or math.huge
  local acc, cost = 0, 0
  for i = 1, #ladder do
    local row = ladder[i]
    if row.p > 0 and row.q > 0 and acc < cap then
      local take = math.min(row.q, cap - acc)
      if take > 0 then
        cost = cost + take * row.p
        acc = acc + take
      end
    end
  end
  if acc <= 0 then return nil end
  return cost / acc
end

function M.Aggregate(listings, interesting, opts)
  opts = opts or {}
  local maxLadder = opts.maxLadder or 200
  local pct = opts.depthPercent or 0.2
  local maxUnits = opts.depthMaxUnits or 1000
  local forcedCap = opts.capUnits
  local items, ladders = {}, {}

  for i = 1, #listings do
    local L = listings[i]
    local id, q, p = L.itemID, L.qty or 1, L.unit or 0
    if id and p > 0 then
      local it = items[id]
      if not it then
        it = { min = p, num = 0, qty = 0 }
        items[id] = it
      end
      if p < it.min then it.min = p end
      it.num = it.num + 1
      it.qty = it.qty + q
      if interesting and interesting[id] then
        local lad = ladders[id]
        if not lad then
          lad = {}
          ladders[id] = lad
        end
        if #lad < maxLadder then lad[#lad + 1] = { p = p, q = q } end
      end
    end
  end

  for id, lad in pairs(ladders) do
    local it = items[id]
    local cap = forcedCap or math.min(it.qty * pct, maxUnits)
    it.depth = M.DepthFromLadder(lad, cap)
    if not it.depth then it.depth = it.min end
    it.truncated = (#lad >= maxLadder)
  end

  for id, it in pairs(items) do
    if not it.depth then it.depth = it.min end
  end

  return items, ladders
end

function M.New(db, marketKey)
  db.markets = db.markets or {}
  db.markets[marketKey] = db.markets[marketKey] or { items = {}, ladders = {} }
  local m = db.markets[marketKey]
  m.items = m.items or {}
  m.ladders = m.ladders or {}
  local self = { db = db, key = marketKey, market = m }
  setmetatable(self, { __index = M })
  return self
end

function M:AppendHistory(itemID, day, value)
  local it = self.market.items[itemID]
  if not it then return end
  it.h = it.h or {}
  local n = #it.h
  if n >= 2 and it.h[n - 1] == day then
    it.h[n] = value
  elseif n == 0 or it.h[n - 1] ~= day then
    it.h[#it.h + 1] = day
    it.h[#it.h + 1] = value
  end
  local maxPairs = (PB.Config and PB.Config.Defaults.historyDays) or 30
  while #it.h > maxPairs * 2 do
    table.remove(it.h, 1)
    table.remove(it.h, 1)
  end
end

function M:MedianPrice(itemID, windowDays)
  local it = self.market.items[itemID]
  if not it or not it.h then return nil end
  local cutoff = PB.Util.Today() - (windowDays or 7)
  local values = {}
  for i = 1, #it.h, 2 do
    if it.h[i] >= cutoff then values[#values + 1] = it.h[i + 1] end
  end
  if #values < 3 then return nil end
  return PB.Util.Median(values)
end

function M:PriceOf(itemID)
  local it = self.market.items[itemID]
  if not it then return {} end
  return {
    ah = it.depth or it.min,
    min = it.min,
    num = it.num,
    qty = it.qty,
    vendor = PB.Profile.VendorPrice(itemID),
    updatedAt = it.t or 0,
    truncated = it.truncated,
  }
end

function M:SnapshotText()
  local out = {}
  for id, it in pairs(self.market.items) do
    out[#out + 1] = string.format("%d:%d:%d:%d:%d", id,
      it.min or 0, PB.Util.Round(it.depth or 0), it.num or 0, it.qty or 0)
  end
  return table.concat(out, ";")
end

function M:RestoreFromText(text)
  if type(text) ~= "string" or text == "" then return 0 end
  local n = 0
  for chunk in text:gmatch("[^;]+") do
    local id, minv, depth, num, qty = chunk:match("^(%d+):(%d+):(%d+):(%d+):(%d+)$")
    if id then
      self.market.items[tonumber(id)] = {
        min = tonumber(minv), depth = tonumber(depth),
        num = tonumber(num), qty = tonumber(qty), t = time(),
      }
      n = n + 1
    end
  end
  return n
end

local scanDriver, scanState

local function yieldFrame(co)
  if scanDriver then return end
  scanDriver = CreateFrame("Frame")
  scanDriver:SetScript("OnUpdate", function(self, elapsed)
    local spent = 0
    while spent < 0.006 do
      local ok, err = coroutine.resume(co)
      if not ok then
        self:SetScript("OnUpdate", nil)
        self:Hide()
        scanDriver = nil
        print("|cffff5555ProfitBoard|r 扫描异常：" .. tostring(err))
        return
      end
      if coroutine.status(co) == "dead" then
        self:SetScript("OnUpdate", nil)
        self:Hide()
        scanDriver = nil
        return
      end
      spent = spent + elapsed
    end
  end)
end

function M:Scan(callback)
  if scanState then return false, "已有扫描进行中" end
  if not PB.Profile.caps.ahReplicate then return false, "客户端缺少全量快照 API" end

  local cooldown = (PB.ConfigInstance and PB.ConfigInstance:Get("scanCooldownSec")) or 900
  local last = self.market.updatedAt or 0
  if time() - last < cooldown then
    return false, string.format("还需等待 %d 秒（全扫 15 分钟一次）", cooldown - (time() - last))
  end

  local okCall = pcall(C_AuctionHouse.ReplicateItems)
  if not okCall then return false, "ReplicateItems 调用失败" end

  scanState = { total = 0, done = false }
  local co = coroutine.create(function()
    local waited = 0
    while (C_AuctionHouse.GetNumReplicateItems() or 0) == 0 do
      waited = waited + 1
      if waited > 600 then
        scanState = nil
        if callback then callback(false, "等待快照超时") end
        return
      end
      coroutine.yield()
    end

    local total = C_AuctionHouse.GetNumReplicateItems()
    scanState.total = total
    local listings = {}
    local F = M.REPLICATE_FIELDS
    for i = 1, total do
      local ok, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13 = pcall(C_AuctionHouse.GetReplicateItemInfo, i)
      if ok then
        local id, qty, price = a13, a12, a11
        if F.id ~= 13 then id, qty, price = a3, a2, a1 end
        if type(id) == "number" and type(price) == "number" and price > 0 then
          listings[#listings + 1] = { itemID = id, qty = qty or 1, unit = price }
        end
      end
      if i % 200 == 0 then coroutine.yield() end
    end

    local cfg = PB.ConfigInstance
    local interesting = PB.RecipeSource.InterestingSet()
    local items, ladders = M.Aggregate(listings, interesting, {
      depthPercent = ((cfg and cfg:Get("depthPercent")) or 20) / 100,
      depthMaxUnits = (cfg and cfg:Get("depthMaxUnits")) or 1000,
      maxLadder = 200,
    })

    local day = PB.Util.Today()
    for id, it in pairs(items) do
      it.t = time()
      self.market.items[id] = it
      self:AppendHistory(id, day, PB.Util.Round(it.depth or it.min))
    end
    self.market.ladders = ladders
    self.market.updatedAt = time()
    self.market.scanCount = (self.market.scanCount or 0) + 1
    self.market.partial = false
    self.db.snapshotText = self:SnapshotText()
    scanState = nil
    if callback then callback(true, self.market.scanCount) end
  end)

  yieldFrame(co)
  return true
end

function M:Scanning()
  return scanState ~= nil
end
