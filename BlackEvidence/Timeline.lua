-- BlackEvidence / Timeline.lua
-- 最近 N 秒事件环形缓冲：聊天 / 掉落 / ROLL / 系统 + 手动打点。
-- 用 head 索引覆盖写入，禁止 table.remove(t,1)。
-- secret 文本（或副本内 lockdown 期间的所有聊天）只存占位符，绝不 gsub / 比较 / tonumber。
-- 不注册 COMBAT_LOG_EVENT_UNFILTERED：12.x 会触发 ADDON_ACTION_FORBIDDEN。

local ADDON, BE = ...
BE.Timeline = BE.Timeline or {}
local T = BE.Timeline

local DEFAULT_SECONDS = 180
local DEFAULT_ENTRIES = 800
local TEXT_CAP        = 1000   -- 单条文本上限（字节，UTF-8 安全）
local SNAPSHOT_CAP    = 300    -- Snapshot 最多返回的条数

local buffer = {}    -- 物理槽位 1..cap；未占用的槽位为 nil
local head   = 1     -- 下一个写入槽位
local size   = 0     -- 当前条数
local cap    = 0     -- 当前容量
local started = false

----------------------------------------------------------------------
-- 配置 / 时间
----------------------------------------------------------------------

local function setting(key, default)
    local C = BE.Config
    if type(C) == "table" and type(C.Get) == "function" then
        local ok, v = pcall(C.Get, C, key)
        if ok and v ~= nil then return v end
    end
    return default
end

local function maxAge()
    local n = tonumber(setting("timelineSeconds", DEFAULT_SECONDS))
    if not n or n <= 0 then return DEFAULT_SECONDS end
    return n
end

local function maxEntries()
    local n = tonumber(setting("timelineEntries", DEFAULT_ENTRIES))
    if not n then return DEFAULT_ENTRIES end
    n = math.floor(n)
    if n < 50 then return 50 end
    if n > 2000 then return 2000 end
    return n
end

local function utilNow()
    local U = BE.Util
    if U and type(U.Now) == "function" then
        local ok, v = pcall(U.Now)
        if ok and type(v) == "number" then return v end
    end
    return 0
end

local function wallNow()
    local ok, v = pcall(time)
    if ok and type(v) == "number" then return v end
    return 0
end

local function stampOf(wall)
    wall = tonumber(wall)
    if not wall or wall <= 0 then return "--:--:--" end
    local ok, s = pcall(date, "%H:%M:%S", wall)
    if ok and type(s) == "string" then return s end
    return "--:--:--"
end

----------------------------------------------------------------------
-- 环形缓冲
----------------------------------------------------------------------

local function oldestIndex()
    if cap <= 0 then return 1 end
    return ((head - size - 1) % cap) + 1
end

-- i：1 = 最旧，size = 最新
local function physicalAt(i)
    if cap <= 0 then return 1 end
    return ((oldestIndex() + i - 2) % cap) + 1
end

-- 容量变化时重建（保留最新的条目）
local function ensureCap(want)
    if want == cap and cap > 0 then return end

    local kept = {}
    if cap > 0 and size > 0 then
        local keep = size
        if keep > want then keep = want end
        for i = size - keep + 1, size do
            local src = buffer[physicalAt(i)]
            if src then kept[#kept + 1] = src end
        end
    end

    buffer = {}
    for i = 1, #kept do buffer[i] = kept[i] end

    cap = want
    size = #kept
    if size >= cap then head = 1 else head = size + 1 end
end

-- 丢弃窗口外/超量的最旧记录，返回丢弃条数
function T.Prune(now)
    if cap <= 0 then return 0 end

    -- 配置可能被改小，先对齐容量
    ensureCap(maxEntries())

    now = tonumber(now) or utilNow()
    local age = maxAge()
    local dropped = 0

    while size > 0 do
        local idx = oldestIndex()
        local rec = buffer[idx]
        local t = rec and tonumber(rec.t)
        if t and (now - t) <= age then break end
        buffer[idx] = nil
        size = size - 1
        dropped = dropped + 1
    end

    return dropped
end

local function copyRoll(r)
    if type(r) ~= "table" then return r end
    local out = {}
    for k, v in pairs(r) do
        if type(v) == "table" then
            local inner = {}
            for k2, v2 in pairs(v) do inner[k2] = v2 end
            out[k] = inner
        else
            out[k] = v
        end
    end
    return out
end

----------------------------------------------------------------------
-- 写入
----------------------------------------------------------------------

function T.Push(evt)
    if type(evt) ~= "table" then return nil end
    ensureCap(maxEntries())
    if cap <= 0 then return nil end

    local U = BE.Util
    local text = evt.text
    local secret = evt.secret and true or false

    if U and U.IsSecret and U.IsSecret(text) then
        text = "[受限内容]"
        secret = true
    elseif type(text) ~= "string" then
        text = ""
    elseif #text > TEXT_CAP and U and U.Truncate then
        text = U.Truncate(text, TEXT_CAP)
    end

    local actor = evt.actor
    if type(actor) ~= "string" or actor == "" or (U and U.IsSecret and U.IsSecret(actor)) then
        actor = nil
    end

    local guid = evt.guid
    if type(guid) ~= "string" or guid == "" or (U and U.IsSecret and U.IsSecret(guid)) then
        guid = nil
    end

    local itemLink = evt.itemLink
    if type(itemLink) ~= "string" or itemLink == ""
        or (U and U.IsSecret and U.IsSecret(itemLink)) then
        itemLink = nil
    end

    local rec = {
        t        = tonumber(evt.t) or utilNow(),
        wall     = tonumber(evt.wall) or wallNow(),
        kind     = (type(evt.kind) == "string" and evt.kind ~= "") and evt.kind or "chat",
        text     = text,
        actor    = actor,
        guid     = guid,
        itemLink = itemLink,
        channel  = (type(evt.channel) == "string" and evt.channel ~= "") and evt.channel or nil,
        roll     = type(evt.roll) == "table" and copyRoll(evt.roll) or nil,
        secret   = secret,
    }

    buffer[head] = rec
    head = (head % cap) + 1
    if size < cap then size = size + 1 end

    T.Prune(rec.t)

    if setting("verboseEvents", false) and BE.Log then
        pcall(BE.Log.Debug, "Timeline", "[%s] %s", rec.kind, rec.text)
    end

    return rec
end

-- 手动打点：触发时刻、加入黑名单等。不受 recordScope 限制。
function T.Mark(label)
    local text
    if type(label) == "string" then
        text = label
    elseif label == nil then
        text = "标记"
    else
        text = tostring(label)
    end
    return T.Push({ kind = "MARK", text = text })
end

function T.Count()
    return size
end

-- 当前窗口的深拷贝（数组，新的表），最多 300 条
function T.Snapshot()
    T.Prune()
    if size <= 0 then return {} end

    local n = size
    if n > SNAPSHOT_CAP then n = SNAPSHOT_CAP end

    local out = {}
    for i = size - n + 1, size do
        local src = buffer[physicalAt(i)]
        if src then
            out[#out + 1] = {
                t        = src.t,
                wall     = src.wall,
                kind     = src.kind,
                text     = src.text,
                actor    = src.actor,
                guid     = src.guid,
                itemLink = src.itemLink,
                channel  = src.channel,
                roll     = type(src.roll) == "table" and copyRoll(src.roll) or nil,
                secret   = src.secret,
            }
        end
    end
    return out
end

----------------------------------------------------------------------
-- 文本化
----------------------------------------------------------------------

local KIND_LABEL = {
    chat   = "聊天",
    loot   = "掉落",
    roll   = "ROLL",
    system = "系统",
    MARK   = "标记",
    mark   = "标记",
}

function T.Format(entries)
    entries = entries or T.Snapshot()

    local lines = {}
    lines[1] = ("== 最近 %d 秒时间线（%d 条）=="):format(maxAge(), #entries)

    for i = 1, #entries do
        local e = entries[i]
        if type(e) == "table" then
            local kind = KIND_LABEL[e.kind] or tostring(e.kind or "?")
            local tag = kind
            if type(e.channel) == "string" and e.channel ~= "" then
                tag = kind .. "·" .. e.channel
            end

            local body = e.text or ""
            if type(e.actor) == "string" and e.actor ~= "" then
                body = e.actor .. "：" .. body
            end
            lines[#lines + 1] = ("%s [%s] %s"):format(stampOf(e.wall), tag, body)
        end
    end

    return table.concat(lines, "\n")
end

----------------------------------------------------------------------
-- 事件定义
----------------------------------------------------------------------

-- chat = true：第 1 个参数是文本、第 2 个是发送者、第 12 个是 GUID
local EVENTS = {
    -- 聊天
    CHAT_MSG_PARTY                = { kind = "chat", label = "小队", chat = true },
    CHAT_MSG_PARTY_LEADER         = { kind = "chat", label = "小队", chat = true },
    CHAT_MSG_RAID                 = { kind = "chat", label = "团队", chat = true },
    CHAT_MSG_RAID_LEADER          = { kind = "chat", label = "团队", chat = true },
    CHAT_MSG_INSTANCE_CHAT        = { kind = "chat", label = "副本", chat = true },
    CHAT_MSG_INSTANCE_CHAT_LEADER = { kind = "chat", label = "副本", chat = true },
    CHAT_MSG_SAY                  = { kind = "chat", label = "说",   chat = true },
    CHAT_MSG_YELL                 = { kind = "chat", label = "喊话", chat = true },
    CHAT_MSG_WHISPER              = { kind = "chat", label = "密语", chat = true },

    -- 聊天式的掉落 / 货币 / 系统
    CHAT_MSG_LOOT                 = { kind = "loot",   label = "掉落", chat = true },
    CHAT_MSG_MONEY                = { kind = "loot",   label = "货币", chat = true },
    CHAT_MSG_SYSTEM               = { kind = "system", label = "系统", chat = true },

    -- 事件式掉落
    LOOT_OPENED                   = { kind = "loot", label = "拾取窗口" },
    LOOT_CLOSED                   = { kind = "loot", label = "拾取结束" },
    ENCOUNTER_LOOT_RECEIVED       = { kind = "loot", label = "首领掉落" },

    -- ROLL
    START_LOOT_ROLL               = { kind = "roll", label = "ROLL开始" },
    CANCEL_LOOT_ROLL              = { kind = "roll", label = "ROLL取消" },
    LOOT_ITEM_ROLL_WON            = { kind = "roll", label = "ROLL胜出" },
}

T.Events = EVENTS

----------------------------------------------------------------------
-- 聊天消息（secret 敏感）
----------------------------------------------------------------------

local SYSTEM_KEYWORDS = {
    "拾取", "获得", "掉落", "分配", "掷骰", "需求", "贪婪", "分解",
    "装备", "战利品", "金币",
    "roll", "loot", "receiv", "won", "need", "greed",
    "disenchant", "sold", "awarded", "assigned",
}

local function matchesSystem(text)
    if type(text) ~= "string" then return false end
    local U = BE.Util
    local lower = (U and U.AsciiLower) and U.AsciiLower(text) or text
    for i = 1, #SYSTEM_KEYWORDS do
        if lower:find(SYSTEM_KEYWORDS[i], 1, true) then return true end
    end
    return false
end

local function inInstance()
    if type(_G.IsInInstance) ~= "function" then return false end
    local ok, inside = pcall(_G.IsInInstance)
    return (ok and inside) and true or false
end

local function inLockdown()
    local P = BE.Profile
    if not (P and type(P.Cap) == "function" and P.Cap("lockdown")) then return false end
    local ci = _G.C_ChatInfo
    if type(ci) ~= "table" or type(ci.InChatMessagingLockdown) ~= "function" then
        return false
    end
    local ok, v = pcall(ci.InChatMessagingLockdown)
    return (ok and v) and true or false
end

local function pushChat(meta, ...)
    local U = BE.Util
    if not U then return nil end

    -- recordScope = instance 时，副本外不记聊天（手动打点仍可写入）
    if setting("recordScope", "instance") == "instance" and not inInstance() then
        return nil
    end

    local rawText    = select(1, ...)
    local playerName = select(2, ...)
    local rawGuid    = select(12, ...)

    local text, secret
    if U.IsSecret(rawText) or inLockdown() then
        -- 关键：不做 gsub / 比较 / tonumber，只存占位符
        text   = "[受限内容]"
        secret = true
    else
        text   = U.StripColors(rawText)
        secret = false
    end

    -- 系统频道噪声过滤（只对可读文本判断）
    if meta.kind == "system" and not secret and not matchesSystem(text) then
        return nil
    end

    local actor, guid
    if playerName ~= nil and not U.IsSecret(playerName)
        and type(playerName) == "string" and playerName ~= "" then
        local info
        local I = BE.Identity
        if I and type(I.FromChat) == "function" then
            local g = (not U.IsSecret(rawGuid)) and rawGuid or nil
            local ok, v = pcall(I.FromChat, playerName, g)
            if ok then info = v end
        end
        if info then
            actor = info.full or playerName
            guid  = info.guid
        else
            actor = playerName
        end
    end

    local itemLink
    if not secret then
        local _, link = U.ParseItemLink(text)
        if link then itemLink = link end
    end

    return T.Push({
        kind     = meta.kind,
        channel  = meta.label,
        text     = text,
        actor    = actor,
        guid     = guid,
        itemLink = itemLink,
        secret   = secret,
    })
end

----------------------------------------------------------------------
-- 掉落 / ROLL
----------------------------------------------------------------------

local function pushLootOpened()
    local count
    if type(_G.GetNumLootItems) == "function" then
        local ok, n = pcall(_G.GetNumLootItems)
        if ok and type(n) == "number" then count = n end
    end
    local text = "拾取窗口已打开"
    if count then text = text .. ("（%d 个槽位）"):format(count) end
    return T.Push({ kind = "loot", text = text })
end

local ROLL_TYPE = { [0] = "放弃", [1] = "需求", [2] = "贪婪", [3] = "分解" }

-- 新版客户端已删除 GetLootRollItemInfo / GetLootRollItemLink，
-- 只能用 C_TooltipInfo.GetLootRollItem 尽力取物品名（全程 pcall）。
local function pushRoll(event, ...)
    local isCancel = (event == "CANCEL_LOOT_ROLL")
    local rollID = select(1, ...)
    if type(rollID) ~= "number" then rollID = nil end

    local info = { rollID = rollID }
    local parts = { isCancel and "ROLL 已取消" or "开始 ROLL" }

    local tip = _G.C_TooltipInfo
    if rollID and type(tip) == "table" and type(tip.GetLootRollItem) == "function" then
        local ok, data = pcall(tip.GetLootRollItem, rollID)
        if ok and type(data) == "table" then
            if type(data.id) == "number" then info.itemID = data.id end

            local name
            if type(data.name) == "string" and data.name ~= ""
                and BE.Util.IsPlain(data.name) then
                name = data.name
            end
            if not name and type(data.lines) == "table" then
                for i = 1, math.min(#data.lines, 3) do
                    local line = data.lines[i]
                    local left = type(line) == "table" and line.leftText or nil
                    if type(left) == "string" and left ~= ""
                        and BE.Util.IsPlain(left) then
                        name = left
                        break
                    end
                end
            end
            if name then info.name = name end
        end
    end

    local cl = _G.C_Loot
    if rollID and type(cl) == "table" and type(cl.GetLootRollDuration) == "function" then
        local ok, v = pcall(cl.GetLootRollDuration, rollID)
        if ok and type(v) == "number" then info.duration = v end
    end

    if info.name then parts[#parts + 1] = "物品：" .. info.name end
    if info.itemID then parts[#parts + 1] = ("ID %d"):format(info.itemID) end
    if info.duration then parts[#parts + 1] = "时长 " .. tostring(info.duration) end
    if rollID then parts[#parts + 1] = ("rollID %d"):format(rollID) end

    return T.Push({ kind = "roll", text = table.concat(parts, "｜"), roll = info })
end

local function pushEncounterLoot(...)
    local encounterID, itemID, itemLink, quantity, itemName, fileName = ...
    local U = BE.Util
    if not U then return nil end

    local name, link
    if type(itemName) == "string" and itemName ~= "" and U.IsPlain(itemName) then
        name = itemName
    end
    if type(itemLink) == "string" and itemLink ~= "" and U.IsPlain(itemLink) then
        link = itemLink
        if not name then name = select(2, U.ParseItemLink(itemLink)) end
    end

    local label = name
    if not label and type(itemID) == "number" then label = "ID " .. itemID end

    local parts = { "首领掉落：" .. (label or "?") }
    if type(quantity) == "number" and quantity > 1 then
        parts[#parts + 1] = "x" .. quantity
    end
    if type(encounterID) == "number" and encounterID > 0 then
        parts[#parts + 1] = "首领ID " .. encounterID
    end
    if type(fileName) == "string" and fileName ~= "" and U.IsPlain(fileName) then
        parts[#parts + 1] = "来源：" .. fileName
    end

    return T.Push({ kind = "loot", text = table.concat(parts, "｜"), itemLink = link })
end

local function pushRollWon(...)
    local itemLink, rollQuantity, rollType, roll, upgraded = ...
    local U = BE.Util
    if not U then return nil end

    local name, link
    if type(itemLink) == "string" and itemLink ~= "" and U.IsPlain(itemLink) then
        link = itemLink
        name = select(2, U.ParseItemLink(itemLink))
    end

    local parts = { "ROLL 胜出：" .. (name or "物品") }
    if type(roll) == "number" then parts[#parts + 1] = ("点数 %d"):format(roll) end
    if type(rollType) == "number" and ROLL_TYPE[rollType] then
        parts[#parts + 1] = ROLL_TYPE[rollType]
    end
    if type(rollQuantity) == "number" and rollQuantity > 1 then
        parts[#parts + 1] = "x" .. rollQuantity
    end
    if upgraded == true then parts[#parts + 1] = "已升级" end

    return T.Push({
        kind     = "roll",
        text     = table.concat(parts, "｜"),
        itemLink = link,
        roll     = {
            quantity = (type(rollQuantity) == "number") and rollQuantity or nil,
            rollType = (type(rollType) == "number") and rollType or nil,
            roll     = (type(roll) == "number") and roll or nil,
        },
    })
end

local function handleEvent(event, meta, ...)
    if meta.chat then return pushChat(meta, ...) end
    if event == "LOOT_OPENED" then return pushLootOpened() end
    if event == "LOOT_CLOSED" then
        return T.Push({ kind = "loot", text = "拾取窗口已关闭" })
    end
    if event == "START_LOOT_ROLL" or event == "CANCEL_LOOT_ROLL" then
        return pushRoll(event, ...)
    end
    if event == "ENCOUNTER_LOOT_RECEIVED" then return pushEncounterLoot(...) end
    if event == "LOOT_ITEM_ROLL_WON" then return pushRollWon(...) end
    return nil
end

----------------------------------------------------------------------
-- 启动
----------------------------------------------------------------------

local function isEventValid(ev)
    local ce = _G.C_EventUtils
    if type(ce) == "table" and type(ce.IsEventValid) == "function" then
        local ok, v = pcall(ce.IsEventValid, ev)
        if ok then return v and true or false end
    end
    return true
end

function T.Start()
    if started then return true end
    started = true

    local okCount, invalid, failed = 0, {}, {}

    for ev, meta in pairs(EVENTS) do
        local e, m = ev, meta   -- 每轮新建局部变量，避免闭包捕获同一个循环变量
        if not isEventValid(e) then
            invalid[#invalid + 1] = e
        elseif not BE:RegisterEvent(e) then
            failed[#failed + 1] = e
        else
            BE:On(e, function(...)
                local ok, err = pcall(handleEvent, e, m, ...)
                if not ok and BE.Log then
                    pcall(BE.Log.Warn, "Timeline", "处理 %s 出错：%s", e, tostring(err))
                end
            end)
            okCount = okCount + 1
        end
    end

    if BE.Log then
        BE.Log.Info("Timeline", "已启动：注册 %d 个事件，窗口 %d 秒，上限 %d 条",
            okCount, maxAge(), maxEntries())
        if #invalid > 0 then
            BE.Log.Warn("Timeline", "本客户端不存在的事件（已跳过）：%s",
                table.concat(invalid, ", "))
        end
        if #failed > 0 then
            BE.Log.Warn("Timeline", "注册失败的事件：%s", table.concat(failed, ", "))
        end
    end

    -- 定期清理过期记录（长时间在线时避免残留）
    if type(_G.C_Timer) == "table" and type(_G.C_Timer.NewTicker) == "function" then
        pcall(_G.C_Timer.NewTicker, 20, function() T.Prune() end)
    end

    return true
end

function T.Init()
    ensureCap(maxEntries())
    return T.Start()
end
