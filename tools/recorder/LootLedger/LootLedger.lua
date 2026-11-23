-- LootLedger：掉落记录器（开发用，只记录不交互）
-- 数据只进 LootLedgerDB，写盘靠 /reload 或退出角色；导出交给
-- tools/holybulwark/convert_observed_loot.py 转成 observed_loot.json。
-- 原则：只读检查掉落窗口，不调用 LootSlot()，任何 API 缺失都退让，绝不改动游戏行为。

local ADDON = ...

local PREFIX = "|cff33ff99[LL]|r "
local DB_VERSION = 1
local MAX_RECORDS = 4000      -- 最多保存的 (物品, 来源) 组合数
local BOSS_TTL = 120          -- ENCOUNTER_END 之后多少秒内的掉落算这个 boss
local UNKNOWN = "未知"

local DB                       -- SavedVariables 表，ensureDB() 之后保证存在
local state = { count = 0, bossName = nil, bossAt = 0, warned = false, ready = false }

local function echo(msg)
  print(PREFIX .. tostring(msg))
end

local function safeDate(ts)
  -- 返回 YYYYMMDD 整数；不传 ts 就用当前时间。date() 异常时退化成 0
  local ok, d
  if ts and ts > 0 then
    ok, d = pcall(date, "*t", ts)
  else
    ok, d = pcall(date, "*t")
  end
  if ok and type(d) == "table" and d.year then
    return d.year * 10000 + (d.month or 1) * 100 + (d.day or 1)
  end
  return 0
end

local function now()
  local ok, t = pcall(time)
  if ok and type(t) == "number" then return t end
  return 0
end

local function buildString()
  local ok, version, build = pcall(GetBuildInfo)
  if not ok then return "unknown" end
  version = tostring(version or "")
  if type(build) == "string" and build:match("^%d+$") and not version:find(build, 1, true) then
    return version .. "." .. build
  end
  return version ~= "" and version or "unknown"
end

-- ---- 存储：初始化 / 迁移 / 计数 ----------------------------------------

local function recount()
  local n = 0
  if type(DB) == "table" and type(DB.items) == "table" then
    for _, item in pairs(DB.items) do
      if type(item) == "table" and type(item.sources) == "table" then
        for _ in pairs(item.sources) do n = n + 1 end
      end
    end
  end
  state.count = n
end

local function ensureDB()
  -- 本客户端的 SavedVariables 偶尔回空表/丢字段，任何情况都重建可用结构
  if type(LootLedgerDB) ~= "table" then LootLedgerDB = {} end
  DB = LootLedgerDB

  DB.version = DB_VERSION            -- 只认 version = 1，缺字段就地补齐
  if type(DB.items) ~= "table" then DB.items = {} end
  if type(DB.enabled) ~= "boolean" then DB.enabled = true end
  if type(DB.build) ~= "string" or DB.build == "" then DB.build = buildString() end
  if type(DB.locale) ~= "string" or DB.locale == "" then
    local ok, loc = pcall(GetLocale)
    DB.locale = (ok and type(loc) == "string" and loc) or "unknown"
  end
  if type(DB.updatedAt) ~= "number" then DB.updatedAt = now() end

  for id, item in pairs(DB.items) do
    if type(item) ~= "table" or type(item.sources) ~= "table" then
      DB.items[id] = nil              -- 坏行直接丢掉，宁可少记也不要崩
    end
  end

  recount()
end

-- 超过上限时丢弃 last 最旧的一条；只警告一次
local function prune()
  if state.count <= MAX_RECORDS then return end
  local guard = 0
  while state.count > MAX_RECORDS and guard < 128 do
    guard = guard + 1
    local oldestItem, oldestKey, oldestLast
    for id, item in pairs(DB.items) do
      for key, src in pairs(item.sources) do
        local last = tonumber(src.last) or 0
        if oldestLast == nil or last < oldestLast then
          oldestLast, oldestItem, oldestKey = last, id, key
        end
      end
    end
    if oldestKey == nil then state.count = 0 break end
    DB.items[oldestItem].sources[oldestKey] = nil
    if next(DB.items[oldestItem].sources) == nil then DB.items[oldestItem] = nil end
    state.count = state.count - 1
  end
  if not state.warned then
    state.warned = true
    echo(("来源记录已达上限 %d 条，开始丢弃最旧记录"):format(MAX_RECORDS))
  end
end

-- ---- 掉落来源归属 -----------------------------------------------------

local function zoneName()
  local ok, name = pcall(function()
    if type(C_Map) ~= "table" or type(C_Map.GetBestMapForUnit) ~= "function" then
      return nil
    end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return nil end
    local info = C_Map.GetMapInfo(mapID)
    return info and info.name
  end)
  if ok and type(name) == "string" and name ~= "" then return name end

  local ok2, zone = pcall(GetZoneText)
  if ok2 and type(zone) == "string" and zone ~= "" then return zone end
  return UNKNOWN
end

-- Creature-0-<服>-<实例>-<区域>-<npcID>-<spawnUID>，取倒数第二段
local function npcIDFromGUID(guid)
  if type(guid) ~= "string" or guid:sub(1, 8) ~= "Creature" then return 0 end
  local parts = {}
  for part in guid:gmatch("[^-]+") do parts[#parts + 1] = part end
  if #parts >= 7 then
    return tonumber(parts[#parts - 1]) or 0
  end
  return 0
end

local function targetName()
  local ok, name = pcall(UnitName, "target")
  if not ok or type(name) ~= "string" or name == "" then return nil end
  local okE, exists = pcall(UnitExists, "target")
  -- 不同客户端分别返回 true/false 或 1/0，两种都认
  if okE and (exists == false or exists == 0 or exists == nil) then return nil end
  local okA, attackable = pcall(UnitCanAttack, "player", "target")
  if not okA or attackable == false or attackable == 0 or attackable == nil then return nil end
  return name
end

-- 返回 npcName, npcID, ctx
local function attribute()
  local t = now()
  if state.bossName and (t - (state.bossAt or 0)) <= BOSS_TTL then
    return state.bossName, 0, "boss"
  end
  local name = targetName()
  if name then
    local ok, guid = pcall(UnitGUID, "target")
    local id = (ok and npcIDFromGUID(guid)) or 0
    return name, id, "target"
  end
  return UNKNOWN, 0, "unknown"
end

-- ---- 记账 -------------------------------------------------------------

local function recordDrop(itemID, itemName, npcName, npcID, ctx, qty)
  if type(itemID) ~= "string" and type(itemID) ~= "number" then return end
  itemID = tostring(itemID)
  if itemID == "" or itemID == "0" then return end
  if type(DB) ~= "table" or DB.enabled == false then return end

  qty = tonumber(qty) or 1
  if qty < 1 then qty = 1 elseif qty > 1000 then qty = 1000 end

  local items = DB.items
  local item = items[itemID]
  if type(item) ~= "table" then
    item = { name = itemName or ("物品 " .. itemID), sources = {} }
    items[itemID] = item
  end
  if type(item.sources) ~= "table" then item.sources = {} end
  if itemName and itemName ~= "" then item.name = itemName end

  local zone = zoneName()
  local key = string.format("%s|%s|%d", tostring(npcName or UNKNOWN), zone, tonumber(npcID) or 0)
  local today = safeDate(now())
  local src = item.sources[key]

  if type(src) ~= "table" then
    src = { n = 0, first = today, last = today, ctx = ctx or "unknown" }
    item.sources[key] = src
    state.count = state.count + 1
  end

  src.n = (tonumber(src.n) or 0) + qty
  local first = tonumber(src.first) or today
  if today > 0 and (first == 0 or today < first) then first = today end
  src.first = first
  if today > 0 then src.last = today end
  if ctx then src.ctx = ctx end

  DB.updatedAt = now()

  prune()
end

-- ---- 事件 -------------------------------------------------------------

-- GetLootSlotInfo 的返回顺序各版本不同：跳过 icon，取第一个合理的数量字段
local function pickQty(a, b, c, d)
  for i = 2, 4 do
    local v = select(i, a, b, c, d)
    if type(v) == "number" and v >= 1 and v <= 1000 then return math.floor(v) end
  end
  return 1
end

local function onLootOpened()
  if type(DB) ~= "table" or DB.enabled == false then return end
  if type(GetNumLootItems) ~= "function" or type(GetLootSlotLink) ~= "function" then return end

  local ok, total = pcall(GetNumLootItems)
  if not ok or type(total) ~= "number" or total < 1 then return end

  local npcName, npcID, ctx = attribute()
  for i = 1, total do
    local okl, link = pcall(GetLootSlotLink, i)
    if okl and type(link) == "string" then
      local id = link:match("item:(%d+)")
      if id and id ~= "0" then
        local qty = 1
        if type(GetLootSlotInfo) == "function" then
          local okq, a, b, c, d = pcall(GetLootSlotInfo, i)
          if okq then qty = pickQty(a, b, c, d) end
        end
        local name = link:match("%[(.-)%]")
        recordDrop(id, name, npcName, npcID, ctx, qty)
      end
    end
  end
end

-- ENCOUNTER_END(encounterID, encounterName, difficultyID, groupSize, success)
local function onEncounterEnd(_, encounterName, _, _, success)
  if type(encounterName) ~= "string" or encounterName == "" then return end
  if success == false then return end          -- 失败的尝试没有掉落，不占用归属窗口
  state.bossName = encounterName
  state.bossAt = now()
end

local function onChatLoot(msg)
  if type(DB) ~= "table" or DB.enabled == false then return end
  if type(msg) ~= "string" then return end
  local id = msg:match("item:(%d+)")
  if not id or id == "0" then return end

  local npcName, npcID = attribute()           -- 自动拾取：借用 boss 归属，ctx 记 chat
  local qty = tonumber(msg:match("x(%d+)")) or 1

  local name = msg:match("%[(.-)%]")
  if not name and type(GetItemInfo) == "function" then
    local ok, n = pcall(GetItemInfo, tonumber(id))
    if ok and type(n) == "string" then name = n end
  end
  if not name and type(GetItemInfoInstant) == "function" then
    local ok, _, n = pcall(GetItemInfoInstant, tonumber(id))
    if ok and type(n) == "string" then name = n end
  end

  recordDrop(id, name, npcName, npcID, "chat", qty)
end

local function onAddonLoaded(loaded)
  if loaded and loaded ~= ADDON then return end
  ensureDB()
end

local function onPlayerLogin()
  if not DB then ensureDB() end
  DB.build = buildString()
  if not state.ready then
    state.ready = true
    echo("就绪 (/ll 查看)")
  end
end

-- ---- 斜杠命令 ---------------------------------------------------------

local function countItems()
  local n = 0
  if type(DB) == "table" then
    for _ in pairs(DB.items or {}) do n = n + 1 end
  end
  return n
end

-- 导出摘要：按物品 ID 排序，取前 5 件
local function handleExport()
  echo("数据在 LootLedgerDB，写盘需要 /reload。")
  local ids = {}
  for id in pairs((DB and DB.items) or {}) do ids[#ids + 1] = id end
  table.sort(ids, function(x, y) return tonumber(x) < tonumber(y) end)

  local shown = 0
  for _, id in ipairs(ids) do
    if shown >= 5 then break end
    local item = DB.items[id]
    local name, total, topKey = item.name or ("物品 " .. id), 0, nil
    for key, src in pairs(item.sources or {}) do
      local n = tonumber(src.n) or 0
      if n > total then total, topKey = n, key end
    end
    if topKey then
      local npc, zone = topKey:match("^(.-)|(.-)|")
      shown = shown + 1
      echo(("%s %s ← %s/%s ×%d"):format(id, name, npc or UNKNOWN, zone or UNKNOWN, total))
    end
  end
  if shown == 0 then echo("还没有记录。") end
end

local function wipeRecords()
  for id in pairs(DB.items or {}) do DB.items[id] = nil end
  state.count = 0
  state.warned = false
  DB.updatedAt = now()
  echo("已清空全部记录")
end

local function handleClear()
  if type(StaticPopupDialogs) ~= "table" or type(StaticPopup_Show) ~= "function" then
    echo("客户端没有 StaticPopup，拒绝清空（未做任何修改）")
    return
  end

  StaticPopupDialogs["LOOTLEDGER_CLEAR"] = {
    text = "确定清空 LootLedger 的全部掉落记录？此操作不可撤销。",
    button1 = "清空",
    button2 = "取消",
    OnAccept = function() wipeRecords() end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = true,
    preferredIndex = 3,
  }
  pcall(StaticPopup_Show, "LOOTLEDGER_CLEAR", nil, nil, nil)
end

local function handleStatus()
  if not DB then ensureDB() end
  echo("记录：" .. (DB.enabled and "开" or "关"))
  echo(("物品 %d 件 / 来源 %d 条"):format(countItems(), state.count))
  echo(("构建 %s · %s"):format(tostring(DB.build or "unknown"), tostring(DB.locale or "unknown")))
  echo("命令：/ll on | /ll off | /ll clear | /ll export")
end

local function handle(msg)
  ensureDB()
  local cmd = tostring(msg or ""):match("^%s*(%S*)"):lower()

  if cmd == "" or cmd == "status" then
    handleStatus()
  elseif cmd == "on" then
    DB.enabled = true
    echo("记录：开")
  elseif cmd == "off" then
    DB.enabled = false
    echo("记录：关")
  elseif cmd == "clear" then
    handleClear()
  elseif cmd == "export" then
    handleExport()
  else
    echo("未知命令：" .. cmd .. "（/ll 查看状态）")
  end
end

-- ---- 启动 -------------------------------------------------------------

local frame = CreateFrame("Frame")
local function onEvent(_, event, ...)
  -- 每个事件单独 pcall：记录器绝不能因为某个 API 不存在影响游戏
  if event == "ADDON_LOADED" then pcall(onAddonLoaded, ...)
  elseif event == "PLAYER_LOGIN" then pcall(onPlayerLogin)
  elseif event == "LOOT_OPENED" then pcall(onLootOpened)
  elseif event == "ENCOUNTER_END" then pcall(onEncounterEnd, ...)
  elseif event == "CHAT_MSG_LOOT" then pcall(onChatLoot, ...)
  end
end
frame:SetScript("OnEvent", onEvent)

for _, event in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "LOOT_OPENED", "ENCOUNTER_END", "CHAT_MSG_LOOT" }) do
  pcall(frame.RegisterEvent, frame, event)
end

if type(SlashCmdList) == "table" then
  SLASH_LOOTLEDGER1 = "/ll"
  SlashCmdList["LOOTLEDGER"] = function(msg) pcall(handle, msg) end
end
