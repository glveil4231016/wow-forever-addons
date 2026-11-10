-- BlackEvidence / Trigger.lua
-- 唯一证据采集入口：时间线打点 → 快照 → 截图 → 写入 BlackEvidenceSnapshots。
-- 顺序固定为 Mark → Snapshot → ScheduleScreenshot → 组装 record → insert。
-- 任何模块缺失（Timeline / Blacklist / Identity）都必须降级，不得抛错。

local ADDON, BE = ...
BE.Trigger = BE.Trigger or {}
local TR = BE.Trigger

local DEFAULT_KEEP  = 50
local MAX_KEEP      = 50
local DEFAULT_LINES = 300
local MAX_LINES     = 300
local DEFAULT_CHARS = 6000
local DEFAULT_DELAY = 0.15

-- 每秒一个 seq；不做 % 100，避免同一秒内 ID 回绕
local idSecond, idSeq = nil, 0

----------------------------------------------------------------------
-- 基础
----------------------------------------------------------------------

local function setting(key, default)
    local C = BE.Config
    if type(C) == "table" and type(C.Get) == "function" then
        local ok, v = pcall(C.Get, C, key)
        if ok and v ~= nil then return v end
    end
    return default
end

local function log(level, fmt, ...)
    local L = BE.Log
    if type(L) ~= "table" then return end
    local fn = L[level]
    if type(fn) == "function" then pcall(fn, "Trigger", fmt, ...) end
end

local function wallNow()
    local ok, v = pcall(time)
    if ok and type(v) == "number" then return v end
    return 0
end

local function dateFmt(fmt, ts)
    local ok, s = pcall(date, fmt, ts)
    if ok and type(s) == "string" then return s end
    return ""
end

local function store()
    local s = _G.BlackEvidenceSnapshots
    if type(s) ~= "table" then
        s = {}
        _G.BlackEvidenceSnapshots = s
    end
    if type(s.records) ~= "table" then s.records = {} end
    return s
end

local function plainStr(v)
    if type(v) ~= "string" or v == "" then return nil end
    local U = BE.Util
    if U and type(U.IsSecret) == "function" and U.IsSecret(v) then return nil end
    return v
end

local function displayOf(info)
    if type(info) ~= "table" then return "?" end
    local U = BE.Util
    if U and type(U.IsSecret) == "function" and U.IsSecret(info.name) then
        return "[受限内容]"
    end

    local I = BE.Identity
    if type(I) == "table" and type(I.Display) == "function" then
        local ok, v = pcall(I.Display, info)
        if ok and type(v) == "string" and v ~= "" then return v end
    end

    local full = plainStr(info.full)
    if full then return full end
    local name = plainStr(info.name)
    if name then return name end
    return "?"
end

----------------------------------------------------------------------
-- ID
----------------------------------------------------------------------

local function exists(id)
    local list = store().records
    for i = 1, #list do
        local r = list[i]
        if type(r) == "table" and r.id == id then return true end
    end
    return false
end

local function nextId()
    local sec = dateFmt("%Y%m%d-%H%M%S", wallNow())
    if sec ~= idSecond then
        idSecond = sec
        idSeq = 0
    end

    local sess = 0
    if BE.Log and type(BE.Log.Session) == "number" then
        sess = math.floor(BE.Log.Session)
    end

    local id
    repeat
        idSeq = idSeq + 1
        id = ("BE-%s-%d-%d"):format(sec, sess, idSeq)
    until not exists(id)
    return id
end

----------------------------------------------------------------------
-- 队伍快照
----------------------------------------------------------------------

local function partySnapshot()
    local out = {}
    if type(_G.GetNumGroupMembers) ~= "function" then return out end

    local ok, n = pcall(_G.GetNumGroupMembers)
    if not ok or type(n) ~= "number" or n < 1 then return out end
    if n > 40 then n = 40 end

    local isRaid = false
    if type(_G.IsInRaid) == "function" then
        local ok2, v = pcall(_G.IsInRaid)
        if ok2 then isRaid = v and true or false end
    end

    for i = 1, n do
        local unit
        if isRaid then
            unit = "raid" .. i
        elseif i == 1 then
            unit = "player"
        else
            unit = "party" .. (i - 1)
        end

        local info
        local I = BE.Identity
        if type(I) == "table" and type(I.Unit) == "function" then
            local okU, v = pcall(I.Unit, unit)
            if okU then info = v end
        end

        local name = info and plainStr(info.full) or nil
        if not name and type(_G.UnitName) == "function" then
            local okN, v = pcall(_G.UnitName, unit)
            if okN then name = plainStr(v) end
        end

        if name then
            local class, classFile
            if type(_G.UnitClass) == "function" then
                local okC, cn, cf = pcall(_G.UnitClass, unit)
                if okC then
                    class, classFile = plainStr(cn), plainStr(cf)
                end
            end

            local role
            if type(_G.UnitGroupRolesAssigned) == "function" then
                local okR, r = pcall(_G.UnitGroupRolesAssigned, unit)
                if okR then role = plainStr(r) end
            end

            out[#out + 1] = {
                unit      = unit,
                name      = name,
                key       = info and plainStr(info.key) or nil,
                guid      = info and plainStr(info.guid) or nil,
                class     = class,
                classFile = classFile,
                role      = role,
            }
        end
    end

    return out
end

----------------------------------------------------------------------
-- 截图
----------------------------------------------------------------------

local function shotExt()
    local fmt
    if type(_G.GetCVar) == "function" then
        local ok, v = pcall(_G.GetCVar, "screenshotFormat")
        if ok and type(v) == "string" then fmt = v end
    end

    local U = BE.Util
    local lower = (U and type(U.AsciiLower) == "function") and U.AsciiLower(fmt) or (fmt or "")
    if lower == "jpeg" or lower == "jpg" then return "jpg" end
    if lower == "png" then return "png" end
    if lower == "tga" then return "tga" end
    return "jpg"
end

-- 返回 shot 表：{ predicted=文件名, ok=是否成功, scheduled, delay, at }
function TR.ScheduleScreenshot(delay)
    local d = tonumber(delay)
    if not d then d = tonumber(setting("screenshotDelay", DEFAULT_DELAY)) end
    if not d then d = DEFAULT_DELAY end
    if d < 0 then d = 0 end

    local shot = {
        predicted = dateFmt("WoWScrnShot_%m%d%y_%H%M%S.", wallNow()) .. shotExt(),
        ok        = false,
        scheduled = true,
        delay     = d,
        at        = nil,
    }

    local function run()
        local api
        if type(_G.Screenshot) == "function" then
            api = _G.Screenshot
        elseif type(_G.TakeScreenshot) == "function" then
            api = _G.TakeScreenshot
        end

        if not api then
            shot.ok  = false
            shot.err = "客户端没有 Screenshot()"
            log("Warn", "截图跳过：%s", shot.err)
            return
        end

        local ok, err = pcall(api)
        shot.ok = ok and true or false
        shot.at = wallNow()
        if not ok then
            shot.err = tostring(err)
            log("Warn", "截图失败：%s", shot.err)
        end
    end

    if type(_G.C_Timer) == "table" and type(_G.C_Timer.After) == "function" then
        local ok, err = pcall(_G.C_Timer.After, d, run)
        if ok then return shot end
        shot.err = tostring(err)
        log("Warn", "C_Timer.After 失败（%s），改为立即截图", tostring(err))
    end

    run()
    return shot
end

----------------------------------------------------------------------
-- 文本裁剪（按字节，UTF-8 安全）
----------------------------------------------------------------------

local CLIP_PREFIX = "…（更早内容已截断）\n"

local function capText(text, limit)
    if type(text) ~= "string" then return "" end
    limit = tonumber(limit)
    if not limit or limit < 1 then limit = DEFAULT_CHARS end
    if #text <= limit then return text end

    local prefix = CLIP_PREFIX
    local room = limit - #prefix
    if room < 1 then
        prefix = ""
        room = limit
    end

    local start = #text - room + 1
    local U = BE.Util
    if U and type(U.Utf8SafeStart) == "function" then
        start = U.Utf8SafeStart(text, start)
    end
    if start < 1 then start = 1 end
    return prefix .. text:sub(start)
end

local function clipEntries(entries, limit)
    if type(entries) ~= "table" then return {} end
    if #entries <= limit then return entries end

    local out = {}
    for i = #entries - limit + 1, #entries do
        out[#out + 1] = entries[i]
    end
    return out
end

----------------------------------------------------------------------
-- 主入口
----------------------------------------------------------------------

-- reason：manual_add / party_join / manual ……
-- info  ：BE.Identity.Unit 的结果（或至少含 name/key/guid）
-- note  ：备注；nil 时取黑名单条目里的备注
function TR.Fire(reason, info, note)
    reason = type(reason) == "string" and reason or "manual"
    if type(info) ~= "table" then info = nil end
    local wall = wallNow()

    -- 1) 时间线打点（必须早于快照，标记才会出现在本次证据里）
    local tm = BE.Timeline
    if type(tm) == "table" and type(tm.Mark) == "function" then
        pcall(tm.Mark, ("★ 触发证据：%s（%s）"):format(displayOf(info), reason))
    end

    -- 2) 时间线快照
    local entries = {}
    if type(tm) == "table" and type(tm.Snapshot) == "function" then
        local ok, v = pcall(tm.Snapshot)
        if ok and type(v) == "table" then entries = v end
    end

    -- 3) 截图（异步；返回预测文件名）
    local shot = TR.ScheduleScreenshot()

    -- 4) 组装 record
    local lineCap = tonumber(setting("snapshotTimelineLines", DEFAULT_LINES))
    if not lineCap then lineCap = DEFAULT_LINES end
    lineCap = math.floor(lineCap)
    if lineCap < 1 then lineCap = DEFAULT_LINES end
    if lineCap > MAX_LINES then lineCap = MAX_LINES end

    local lines = clipEntries(entries, lineCap)

    local timelineText
    if type(tm) == "table" and type(tm.Format) == "function" then
        local ok, v = pcall(tm.Format, lines)
        timelineText = (ok and type(v) == "string") and v
            or ("共 %d 条（时间线格式化失败）"):format(#lines)
    else
        timelineText = ("共 %d 条（时间线模块不可用）"):format(#lines)
    end
    timelineText = capText(timelineText, setting("timelineChars", DEFAULT_CHARS))

    -- 黑名单命中：命中则计数 +1，备注缺省取存档里的
    local B = BE.Blacklist
    local entry
    if info and type(B) == "table" and type(B.Find) == "function" then
        local ok, v = pcall(B.Find, info)
        if ok then entry = v end
    end

    if note == nil then
        note = entry and entry.note or ""
    end
    if type(note) ~= "string" then note = "" end
    local U = BE.Util
    if U and type(U.IsSecret) == "function" and U.IsSecret(note) then note = "" end

    if entry and type(B) == "table" and type(B.Hit) == "function" then
        pcall(B.Hit, entry.key)
    end

    local full = displayOf(info)
    if full == "?" and entry then full = displayOf(entry) end

    local target = {
        key     = (info and plainStr(info.key)) or (entry and plainStr(entry.key)) or nil,
        name    = (info and plainStr(info.name)) or (entry and plainStr(entry.name)) or nil,
        surname = (info and plainStr(info.surname)) or (entry and plainStr(entry.surname)) or nil,
        realm   = (info and plainStr(info.realm)) or (entry and plainStr(entry.realm)) or nil,
        guid    = (info and plainStr(info.guid)) or (entry and plainStr(entry.guid)) or nil,
        full    = full,
        note    = note,
    }

    -- 自己的名字
    local selfName = "?"
    local I = BE.Identity
    if type(I) == "table" and type(I.Unit) == "function" then
        local ok, me = pcall(I.Unit, "player")
        if ok and type(me) == "table" then
            selfName = plainStr(me.full) or plainStr(me.name) or "?"
        end
    end
    if selfName == "?" and type(_G.UnitName) == "function" then
        local ok, v = pcall(_G.UnitName, "player")
        if ok then selfName = plainStr(v) or "?" end
    end

    -- 聊天日志开关（LoggingChat 是否开启）
    local chatLogEnabled = false
    local ci = _G.C_ChatInfo
    if type(ci) == "table" and type(ci.IsLoggingChat) == "function" then
        local ok, v = pcall(ci.IsLoggingChat)
        if ok then chatLogEnabled = v and true or false end
    elseif type(_G.GetCVar) == "function" then
        local ok, v = pcall(_G.GetCVar, "chatLog")
        if ok and v == "1" then chatLogEnabled = true end
    end

    local record = {
        id           = nextId(),
        reason       = reason,
        at           = dateFmt("%Y-%m-%d %H:%M:%S", wall),
        wall         = wall,
        profile      = (BE.Profile and BE.Profile.id) or "retail",
        selfName     = selfName,
        target       = target,
        party        = partySnapshot(),
        timeline     = lines,
        timelineText = timelineText,
        screenshot   = shot,
        chatLog      = { enabled = chatLogEnabled },
    }

    -- 5) 入库（FIFO，保留最近 snapshotKeep 条）
    local s = store()
    table.insert(s.records, 1, record)
    s.updatedAt = wall
    TR.Keep()

    log("Info", "证据 %s | %s | %s | 时间线 %d 条 | 截图 %s",
        record.id, target.full, reason, #lines, shot.predicted or "-")
    if #lines == 0 then
        log("Warn", "时间线为空：确认这 %d 秒内确实有聊天/掉落，或 recordScope 是否限制在副本内",
            tonumber(setting("timelineSeconds", 180)) or 180)
    end

    return record
end

----------------------------------------------------------------------
-- 查询 / 维护
----------------------------------------------------------------------

function TR.List()
    return store().records
end

function TR.Get(id)
    if type(id) ~= "string" or id == "" then return nil end
    local list = store().records
    for i = 1, #list do
        local r = list[i]
        if type(r) == "table" and r.id == id then return r end
    end
    return nil
end

function TR.Remove(id)
    if type(id) ~= "string" or id == "" then return false end
    local list = store().records
    for i = 1, #list do
        local r = list[i]
        if type(r) == "table" and r.id == id then
            table.remove(list, i)
            log("Info", "已删除证据 %s", id)
            return true
        end
    end
    return false
end

-- 保留最近 n 条；上限 50
function TR.Keep(n)
    n = tonumber(n)
    if not n then n = tonumber(setting("snapshotKeep", DEFAULT_KEEP)) end
    if not n then n = DEFAULT_KEEP end
    n = math.floor(n)
    if n < 1 then n = 1 end
    if n > MAX_KEEP then n = MAX_KEEP end

    local list = store().records
    while #list > n do table.remove(list) end
    return #list
end

function TR.LatestID()
    local list = store().records
    local r = list[1]
    if type(r) == "table" then return r.id end
    return nil
end

function TR.Init()
    local s = store()
    local list = s.records

    -- 清洗被外部改坏的记录，避免 UI 崩
    for i = #list, 1, -1 do
        local r = list[i]
        if type(r) ~= "table" or type(r.id) ~= "string" or r.id == "" then
            table.remove(list, i)
        end
    end

    TR.Keep()
    s.updatedAt = s.updatedAt or 0

    log("Info", "证据库已就绪：%d 条（上限 %d）", #list,
        tonumber(setting("snapshotKeep", DEFAULT_KEEP)) or DEFAULT_KEEP)
    return true
end
