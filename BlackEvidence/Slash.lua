-- BlackEvidence / Slash.lua
-- /be 与 /blackevidence 命令。所有模块调用都 pcall + 存在性判断，缺模块只提示不报错。
-- 除 warn ... send 与 Comms.Flush 外，本文件不向任何频道发送消息。

local ADDON, BE = ...
BE.Slash = BE.Slash or {}
local S = BE.Slash

local PREFIX = "|cff33ff99[BE]|r"
local FALLBACK_BYTES = 1800
local MAX_LIST = 30
local MAX_SEARCH = 20
local MAX_DUMP = 250

local LOG_LEVELS = { trace = true, debug = true, info = true, warn = true, error = true }
local PROFILE_IDS = { retail = true, classic = true, forever = true }
local PROFILE_LABEL = { retail = "正式服", classic = "经典时光服", forever = "无限服" }

local logFilter = ""

-- 顶层就把斜杠别名挂上，避免命令注册时机太晚
SLASH_BLACKEVIDENCE1 = "/be"
SLASH_BLACKEVIDENCE2 = "/blackevidence"

----------------------------------------------------------------------
-- 基础工具
----------------------------------------------------------------------

local function chatLine(line)
    local cf = _G.DEFAULT_CHAT_FRAME
    if cf and type(cf.AddMessage) == "function" then
        pcall(cf.AddMessage, cf, line)
        return true
    end
    if type(print) == "function" then
        pcall(print, line)
        return true
    end
    return false
end

local function fmtArgs(fmt, ...)
    if select("#", ...) == 0 then return tostring(fmt) end
    local ok, s = pcall(string.format, tostring(fmt), ...)
    if ok and type(s) == "string" then return s end
    return tostring(fmt)
end

local function Echo(fmt, ...)
    chatLine(PREFIX .. " " .. fmtArgs(fmt, ...))
end

local function okText(t) return "|cff40ff40" .. tostring(t) .. "|r" end
local function badText(t) return "|cffff5555" .. tostring(t) .. "|r" end
local function dim(t) return "|cff9aa0b5" .. tostring(t) .. "|r" end

local function trim(s)
    if type(s) ~= "string" then return "" end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function lower(s)
    local U = BE.Util
    if U and type(U.AsciiLower) == "function" then
        return U.AsciiLower(tostring(s or ""))
    end
    return tostring(s or ""):lower()
end

local function clip(s, n)
    s = tostring(s or "")
    local U = BE.Util
    if U and type(U.Truncate) == "function" then
        return U.Truncate(s, n or 80)
    end
    if #s <= (n or 80) then return s end
    return s:sub(1, n or 80) .. "…"
end

local function asText(v)
    if v == nil then return "" end
    if type(v) ~= "string" then return tostring(v) end
    local U = BE.Util
    if U and type(U.IsSecret) == "function" then
        local ok, secret = pcall(U.IsSecret, v)
        if ok and secret then return "[受限内容]" end
    end
    return v
end

local function splitHead(s)
    s = tostring(s or "")
    local word, tail = s:match("^%s*(%S+)%s*(.*)$")
    return word or "", tail or ""
end

local function firstWord(s)
    local w = tostring(s or ""):match("^%s*(%S+)")
    return w or ""
end

-- 名字含空格时允许用引号：/be add "Asha Brightvale" 备注
local function parseNameNote(rest)
    local s = tostring(rest or ""):gsub("^%s+", "")
    if s:sub(1, 1) == '"' then
        local name, tail = s:match('^"(.-)"%s*(.*)$')
        if name and name ~= "" then return name, tail or "" end
    end
    return splitHead(s)
end

-- 只吃名字的命令（del / ignore 等）也允许整串加引号
local function unquote(s)
    s = trim(s)
    if #s >= 2 and s:sub(1, 1) == '"' and s:sub(-1) == '"' then
        return trim(s:sub(2, -2))
    end
    return s
end

local function stamp(fmt)
    if type(date) ~= "function" or type(time) ~= "function" then return "?" end
    local ok, s = pcall(function()
        return date(fmt or "%Y-%m-%d %H:%M:%S", time())
    end)
    if ok and type(s) == "string" then return s end
    return "?"
end

local function stampOf(ts, fmt)
    ts = tonumber(ts)
    if not ts or ts <= 0 then return "?" end
    if type(date) ~= "function" then return tostring(ts) end
    local ok, s = pcall(date, fmt or "%m-%d %H:%M:%S", ts)
    if ok and type(s) == "string" then return s end
    return tostring(ts)
end

local function countTable(t)
    local n = 0
    if type(t) == "table" then
        for _ in pairs(t) do n = n + 1 end
    end
    return n
end

----------------------------------------------------------------------
-- 模块访问
----------------------------------------------------------------------

local function callModule(modName, fnName, ...)
    local m = BE[modName]
    if type(m) ~= "table" then
        Echo("%s 模块未加载（%s 不可用）", modName, fnName)
        return false
    end
    local fn = m[fnName]
    if type(fn) ~= "function" then
        Echo("%s.%s 不可用", modName, fnName)
        return false
    end
    local ok, a, b, c = pcall(fn, ...)
    if not ok then
        Echo("%s.%s 调用失败：%s", modName, fnName, tostring(a))
        return false
    end
    return true, a, b, c
end

local function cfgGet(key)
    local C = BE.Config
    if type(C) ~= "table" or type(C.Get) ~= "function" then return nil end
    local ok, v = pcall(C.Get, C, key)
    if ok then return v end
    return nil
end

local function cfgSet(key, value)
    local C = BE.Config
    if type(C) ~= "table" or type(C.Set) ~= "function" then return false end
    return (pcall(C.Set, C, key, value))
end

-- Logger 用数字 99 表示 off，展示时还原成人读的字符串
local function logLevelText()
    local L = BE.Log
    if type(L) ~= "table" then return "?" end
    if L.Level == 99 then return "off" end
    return tostring(L.Level)
end

local function refreshUI()
    local ui = BE.ManagerUI
    if type(ui) ~= "table" or type(ui.Refresh) ~= "function" then return false end
    local ok, res = pcall(ui.Refresh)
    if ok and res ~= false then return true end
    return (pcall(ui.Refresh, ui))
end

local function showLong(title, text)
    text = tostring(text or "")
    local ui = BE.ManagerUI
    if type(ui) == "table" and type(ui.ShowText) == "function" then
        local ok, res = pcall(ui.ShowText, title, text)
        if ok and res ~= false then return true end
        local ok2, res2 = pcall(ui.ShowText, ui, title, text)
        if ok2 and res2 ~= false then return true end
    end

    Echo("---- %s ----", title)
    local clipped, cut = text, false
    local U = BE.Util
    if U and type(U.Truncate) == "function" and #text > FALLBACK_BYTES then
        clipped = U.Truncate(text, FALLBACK_BYTES)
        cut = true
    end
    for line in (clipped .. "\n"):gmatch("([^\n]*)\n") do
        Echo("%s", line)
    end
    Echo("---- 结束 ----")
    if cut then
        Echo(dim("内容过长，仅显示前 %d 字节；完整内容见管理界面或 SavedVariables"),
            FALLBACK_BYTES)
    end
    return false
end

----------------------------------------------------------------------
-- 身份 / 条目查找
----------------------------------------------------------------------

local function profileLabel(pid)
    local P = BE.Profile
    if type(P) == "table" and P.id == pid and type(P.label) == "string" and P.label ~= "" then
        return P.label
    end
    return PROFILE_LABEL[pid] or tostring(pid or "?")
end

local function displayEntry(entry)
    if type(entry) ~= "table" then return "?" end
    local I = BE.Identity
    if type(I) == "table" and type(I.Display) == "function" then
        local ok, v = pcall(I.Display, entry)
        if ok and type(v) == "string" and v ~= "" then return v end
    end
    return tostring(entry.name or "?")
end

local function entryInfo(entry)
    if type(entry) ~= "table" or type(entry.key) ~= "string" or entry.key == "" then
        return nil
    end
    local info = {
        name = entry.name,
        surname = entry.surname,
        realm = entry.realm,
        guid = entry.guid,
        key = entry.key,
    }
    local I = BE.Identity
    if type(I) == "table" and type(I.Display) == "function" then
        local ok, full = pcall(I.Display, info)
        info.full = (ok and type(full) == "string") and full or tostring(entry.name or "?")
    else
        info.full = tostring(entry.name or "?")
    end
    return info
end

-- 从命令行里的一串名字构造身份（支持 名字-服务器 / 无限服的 名字 姓）
local function infoFromRaw(raw)
    local text = unquote(raw)
    if text == "" then return nil end

    local I = BE.Identity
    if type(I) ~= "table" or type(I.KeyFromParts) ~= "function" then return nil end

    local e = { name = text }
    local key, a, b

    if type(I.KeyFromFull) == "function" then
        local ok, k, na, nb = pcall(I.KeyFromFull, text)
        if ok and k then key, a, b = k, na, nb end
    end

    if key then
        e.key = key
        if type(a) == "string" and a ~= "" then e.name = a end

        local surnameMode = false
        local P = BE.Profile
        if type(P) == "table" and type(P.Cap) == "function" then
            local okC, v = pcall(P.Cap, "surname")
            surnameMode = okC and v and true or false
        end
        if surnameMode then e.surname = b else e.realm = b end
    else
        local ok, k = pcall(I.KeyFromParts, text, nil)
        if ok then key = k end
        e.key = key
    end

    if not e.key then return nil end

    if type(I.Display) == "function" then
        local ok, full = pcall(I.Display, e)
        e.full = (ok and type(full) == "string") and full or text
    else
        e.full = text
    end
    return e
end

-- 先按 key，再按全名解析，最后按名字唯一匹配
local function findEntryByRaw(raw)
    local text = unquote(raw)
    if text == "" then return nil end

    local B = BE.Blacklist
    if type(B) ~= "table" or type(B.Get) ~= "function" then
        return nil, "Blacklist 模块不可用"
    end
    local I = BE.Identity

    if type(I) == "table" and type(I.Normalize) == "function" then
        local ok, norm = pcall(I.Normalize, text)
        if ok and norm then
            local okG, e = pcall(B.Get, norm)
            if okG and e then return e end
        end
    end

    if type(I) == "table" and type(I.KeyFromFull) == "function" then
        local ok, key = pcall(I.KeyFromFull, text)
        if ok and key then
            local okG, e = pcall(B.Get, key)
            if okG and e then return e end
        end
    end

    if type(B.Store) == "function" then
        local okS, store = pcall(B.Store)
        if okS and type(store) == "table" then
            local target = lower(text)
            local hit, dup = nil, false
            for _, v in pairs(store) do
                if type(v) == "table" and lower(tostring(v.name or "")) == target then
                    if hit then dup = true else hit = v end
                end
            end
            if hit and dup then
                return nil, "同名条目不止一条，请用 名字-服务器（无限服为 名字 姓）指定"
            end
            if hit then return hit end
        end
    end
    return nil
end

local function triggerCount()
    local TR = BE.Trigger
    if type(TR) ~= "table" or type(TR.List) ~= "function" then return 0 end
    local ok, list = pcall(TR.List)
    if ok and type(list) == "table" then return #list end
    return 0
end

----------------------------------------------------------------------
-- 状态汇总（status / diag 共用）
----------------------------------------------------------------------

local function buildStatusLines()
    local out = {}
    local function add(fmt, ...) out[#out + 1] = fmtArgs(fmt, ...) end

    add("======== BlackEvidence 状态 ========")

    local P = BE.Profile
    if type(P) == "table" then
        if type(P.StatusLine) == "function" then
            local ok, line = pcall(P.StatusLine)
            add("客户端：%s", ok and tostring(line) or "读取失败")
        else
            add("客户端：profile=%s（StatusLine 不可用）", tostring(P.id))
        end
        if type(P.ApiReport) == "function" then
            add("---- API ----")
            local ok, rep = pcall(P.ApiReport)
            if ok and type(rep) == "string" and rep ~= "" then
                for line in (rep .. "\n"):gmatch("([^\n]*)\n") do
                    if line ~= "" then add("  %s", line) end
                end
            else
                add("  （不可读）")
            end
        end
    else
        add("客户端：Profile 模块未加载")
    end

    add("---- 模块 ----")
    local mods = {
        "Profile", "Config", "Log", "Util", "Identity", "Blacklist", "Timeline",
        "Trigger", "Comms", "Menu", "NoteDialog", "ManagerUI", "Export", "Slash",
    }
    local chunks = {}
    for i = 1, #mods do
        local name = mods[i]
        chunks[#chunks + 1] = (type(BE[name]) == "table") and okText(name) or badText(name)
    end
    add("%s", table.concat(chunks, " "))

    add("---- 数据 ----")
    local db = _G.BlackEvidenceDB
    if type(db) == "table" then
        local rows, total = {}, 0
        local ids = { "retail", "classic", "forever" }
        for i = 1, #ids do
            local pid = ids[i]
            local p = (type(db.profiles) == "table") and db.profiles[pid] or nil
            local n = (type(p) == "table" and type(p.blacklist) == "table")
                and countTable(p.blacklist) or 0
            total = total + n
            rows[#rows + 1] = ("%s=%d"):format(pid, n)
        end
        add("黑名单：%s｜合计 %d", table.concat(rows, " "), total)
        add("备份：%d 份｜设置项：%d",
            (type(db.backups) == "table") and #db.backups or 0,
            countTable(db.settings))
    else
        add("BlackEvidenceDB：不可用")
    end

    add("证据：%d 条", triggerCount())

    local log = _G.BlackEvidenceLog
    local ents = (type(log) == "table") and log.entries or nil
    local L = BE.Log
    add("日志：会话 #%s｜级别 %s｜缓冲 %s/%s｜累计 %s",
        tostring((type(L) == "table") and L.Session or 0),
        logLevelText(),
        tostring((type(ents) == "table") and ents.__count or 0),
        tostring((type(ents) == "table") and ents.__cap or 0),
        tostring((type(ents) == "table") and ents.__seq or 0))

    add("配置：enabled=%s｜进队预警=%s｜频道播报=%s｜日志级别=%s",
        tostring(cfgGet("enabled")),
        tostring(cfgGet("warnOnPartyJoin")),
        tostring(cfgGet("sendToPartyChat")),
        tostring(cfgGet("logLevel")))
    return out
end

----------------------------------------------------------------------
-- 帮助
----------------------------------------------------------------------

local HELP = {
    "/be help｜/be 显示本帮助",
    "/be add 名字 [备注]        加入黑名单",
    "/be del 名字               移出黑名单",
    "/be note 名字 备注          修改备注",
    "/be list                   列出当前 profile 黑名单",
    "/be search 关键字           搜索名字 / 服务器 / 备注",
    "/be export                 导出黑名单文本",
    "/be import                 打开导入窗口（需要管理界面）",
    "/be pack [记录ID]           生成证据包（省略 ID 用最近一条）",
    "/be scan                   立刻扫描队伍",
    "/be warn 名字 [send]        模拟进队预警（send 才尝试发频道）",
    "/be queue｜/be flush        查看 / 补发频道队列",
    "/be status                 profile、API、模块、数据总览",
    "/be selftest｜/be test      非破坏性自检",
    "/be diag                   诊断包（会话日志 + 锚点 + 状态）",
    "/be menu                   右键菜单实况",
    "/be time [n]               最近 n 条时间线（默认 20）",
    "/be evidence [n|记录ID]     证据列表 / 详情",
    "/be profile [retail|classic|forever]  只读查看；切换需重启客户端",
    "/be log <级别>              设置日志级别（trace/debug/info/warn/error/off）",
    "/be log dump [n]｜since [锚点]｜session｜trace on|off｜filter ...",
    "/be mark 说明               打一个日志锚点",
    "/be ignore 名字｜unignore 名字   本场豁免 / 取消豁免",
    "/be screenshot             立即截图",
    "/be reset                  清空当前 profile 黑名单（需确认）",
}

----------------------------------------------------------------------
-- 命令实现
----------------------------------------------------------------------

local function handleHelp()
    Echo("======== BlackEvidence 命令 ========")
    for i = 1, #HELP do Echo("%s", HELP[i]) end
    Echo(dim("名字含空格（无限服的 名字 姓）时用引号：/be add \"Asha Brightvale\" 备注"))
    Echo(dim("所有命令都不会在运行时切换 profile；切换需重启对应客户端。"))
end

local function handleAdd(rest)
    local name, note = parseNameNote(rest)
    if name == "" then
        Echo("用法：/be add 名字 [备注]（名字含空格时用引号）")
        return
    end
    local info = infoFromRaw(name)
    if not info then
        Echo("名字无效：%s", name)
        return
    end

    -- 已存在且没给备注时，不要清空原备注
    local B = BE.Blacklist
    local existing = nil
    if type(B) == "table" and type(B.Get) == "function" then
        local okE, v = pcall(B.Get, info.key)
        if okE then existing = v end
    end
    if existing and trim(note) == "" then
        Echo("已在黑名单中：%s（未填备注，保持原备注不变）", displayEntry(existing))
        return
    end

    local ok, entry, isNew = callModule("Blacklist", "Add", info, note or "", "slash")
    if not ok then return end
    if type(entry) ~= "table" then
        Echo("加入失败：Blacklist.Add 没有返回条目")
        return
    end
    local shown = displayEntry(entry)
    local one = asText(entry.note or ""):gsub("\n", " / ")
    if isNew then
        Echo("已加入黑名单：%s（备注：%s）", shown, one ~= "" and clip(one, 60) or "无")
    else
        Echo("已在黑名单中，已更新备注：%s（备注：%s）", shown, one ~= "" and clip(one, 60) or "无")
    end
    refreshUI()
end

local function handleDel(rest)
    local raw = unquote(rest)
    if raw == "" then
        Echo("用法：/be del 名字")
        return
    end
    local entry, err = findEntryByRaw(raw)
    if not entry then
        if err then Echo("%s", err) else Echo("黑名单里没有「%s」", raw) end
        return
    end
    local ok, removed = callModule("Blacklist", "Remove", entry.key)
    if not ok then return end
    if removed then
        Echo("已移出黑名单：%s", displayEntry(entry))
        refreshUI()
    else
        Echo("删除失败：条目已不在黑名单里")
    end
end

local function handleNote(rest)
    local name, note = parseNameNote(rest)
    if name == "" or trim(note) == "" then
        Echo("用法：/be note 名字 备注内容（名字含空格时用引号）")
        return
    end
    local entry, err = findEntryByRaw(name)
    if not entry then
        if err then Echo("%s", err) else Echo("黑名单里没有「%s」", name) end
        return
    end
    local ok, done = callModule("Blacklist", "Update", entry.key, note)
    if not ok then return end
    if done then
        Echo("已更新备注：%s", displayEntry(entry))
        refreshUI()
    else
        Echo("更新失败：条目不存在")
    end
end

local function handleList()
    local B = BE.Blacklist
    if type(B) ~= "table" or type(B.Iterate) ~= "function" then
        Echo("Blacklist 模块未加载")
        return
    end
    local ok, list = pcall(B.Iterate)
    if not ok or type(list) ~= "table" then
        Echo("读取黑名单失败：%s", tostring(list))
        return
    end

    local pid = (BE.Profile and BE.Profile.id) or "?"
    if #list == 0 then
        Echo("当前 profile（%s）黑名单为空", tostring(pid))
        return
    end

    Echo("当前 profile（%s）黑名单 %d 条：", tostring(pid), #list)
    local shown = #list
    if shown > MAX_LIST then shown = MAX_LIST end
    for i = 1, shown do
        local e = list[i]
        local note = asText(e.note or ""):gsub("\n", " / ")
        Echo("%d) %s｜命中 %d｜备注：%s", i, displayEntry(e), tonumber(e.hits) or 0,
            note ~= "" and clip(note, 60) or "（无）")
    end
    if #list > shown then
        Echo(dim("……其余 %d 条请用 /be search 或管理界面查看"), #list - shown)
    end
end

local function handleSearch(rest)
    local q = unquote(rest)
    if q == "" then
        Echo("用法：/be search 关键字")
        return
    end
    local ok, list = callModule("Blacklist", "Search", q)
    if not ok or type(list) ~= "table" then return end

    if #list == 0 then
        Echo("没有匹配「%s」的条目", q)
        return
    end

    Echo("匹配 %d 条：", #list)
    local shown = #list
    if shown > MAX_SEARCH then shown = MAX_SEARCH end
    for i = 1, shown do
        local e = list[i]
        local note = asText(e.note or ""):gsub("\n", " / ")
        Echo("%d) %s｜命中 %d｜%s", i, displayEntry(e), tonumber(e.hits) or 0,
            note ~= "" and clip(note, 60) or "（无备注）")
    end
    if #list > shown then
        Echo(dim("……仅显示前 %d 条"), MAX_SEARCH)
    end
end

local function handleExport(rest)
    local sub = lower(firstWord(rest))
    if sub ~= "" and sub ~= "list" and sub ~= "text" then
        Echo("用法：/be export（导出黑名单文本）")
        return
    end
    callModule("Export", "ShowList")
end

local function handleImport()
    callModule("Export", "ShowImport")
end

local function handlePack(rest)
    local id = firstWord(rest)
    local E = BE.Export
    if type(E) ~= "table" or type(E.Pack) ~= "function" then
        Echo("Export 模块未加载，无法打包证据")
        return
    end
    local ok, text, err = pcall(E.Pack, (id ~= "") and id or nil)
    if not ok then
        Echo("打包失败：%s", tostring(text))
        return
    end
    if type(text) ~= "string" or text == "" then
        Echo("%s", tostring(err or "没有可打包的证据"))
        return
    end
    showLong("证据包", text)
end

local function handleScan()
    local Comms = BE.Comms
    if type(Comms) ~= "table" then
        Echo("Comms 模块未加载")
        return
    end

    local fn, immediate = Comms.ScanNow, true
    if type(fn) ~= "function" then
        fn, immediate = Comms.Scan, false
    end
    if type(fn) ~= "function" then
        Echo("Comms 扫描接口不可用")
        return
    end

    local ok, n = pcall(fn, "slash")
    if not ok then
        Echo("扫描失败：%s", tostring(n))
        return
    end
    if immediate then
        Echo("扫描完成：本次预警 %d 人（不在队伍时为 0）", tonumber(n) or 0)
    else
        Echo("扫描已排队（约 0.4 秒后执行）")
    end
end

local function handleWarn(rest)
    local name, tail = parseNameNote(rest)
    if name == "" then
        Echo("用法：/be warn 名字 [send]（名字含空格时用引号）")
        return
    end

    local entry, err = findEntryByRaw(name)
    if not entry then
        if err then
            Echo("%s", err)
        else
            Echo("黑名单里没有「%s」，先用 /be add 加入", name)
        end
        return
    end

    local info = entryInfo(entry)
    if not info then
        Echo("条目缺少有效身份信息，无法模拟预警")
        return
    end

    local wantSend = lower(tail):find("%f[%a]send%f[%A]") ~= nil

    -- Comms.Warn 是否发频道取决于 sendToPartyChat：这里临时对齐成用户本次的意图，
    -- 调用后立刻恢复，避免 /be warn（不带 send）在配置开启时误发频道。
    local prev = cfgGet("sendToPartyChat")
    local changed = false
    if prev ~= wantSend then
        changed = cfgSet("sendToPartyChat", wantSend)
    end

    local ok, fired = callModule("Comms", "Warn", info)

    if changed then cfgSet("sendToPartyChat", prev) end

    if not ok then return end
    if fired then
        Echo("已模拟进队预警：%s（%s）", displayEntry(entry),
            wantSend and "已尝试发送频道" or "仅本地提示")
    else
        Echo("预警未触发：%s", displayEntry(entry))
        Echo(dim("可能已在本次组队预警过 / 处于冷却 / 预警开关关闭；详情见 /be status"))
    end
end

local function handleQueue()
    local ok, q = callModule("Comms", "Queue")
    if not ok then return end
    if type(q) ~= "table" or #q == 0 then
        Echo("预警队列为空")
        return
    end
    Echo("预警队列 %d 条：", #q)
    for i = 1, #q do
        local item = q[i]
        if type(item) == "table" then
            Echo("%d) [%s] %s｜%s", i, tostring(item.channel or "?"),
                stampOf(item.at), clip(asText(item.text or ""), 80))
        end
    end
end

local function handleFlush()
    local ok, n = callModule("Comms", "Flush")
    if not ok then return end
    local sent = tonumber(n) or 0
    Echo("补发完成：%d 条", sent)
    if sent == 0 and cfgGet("sendToPartyChat") == false then
        Echo(dim("频道播报已关闭，排队内容按设计丢弃（不会发送）"))
    end
end

local function handleStatus()
    local lines = buildStatusLines()
    for i = 1, #lines do Echo("%s", lines[i]) end
end

local function handleSelfTest()
    Echo("======== BlackEvidence 自检 ========")
    local pass, fail = 0, 0

    local function check(name, cond, extra)
        if cond then
            pass = pass + 1
            Echo("%s %s%s", okText("[通过]"), name,
                extra and ("  " .. dim(tostring(extra))) or "")
        else
            fail = fail + 1
            Echo("%s %s%s", badText("[失败]"), name,
                extra and ("  " .. dim(tostring(extra))) or "")
        end
        return cond
    end

    local P = BE.Profile
    check("profile 已探测", type(P) == "table" and PROFILE_IDS[P.id] == true,
        "id=" .. tostring((type(P) == "table") and P.id or nil))

    local B = BE.Blacklist
    local nB
    if type(B) == "table" and type(B.Count) == "function" then
        local ok, v = pcall(B.Count)
        if ok then nB = tonumber(v) end
    end
    check("黑名单可读", nB ~= nil,
        nB ~= nil and (tostring(nB) .. " 条")
        or ((type(B) == "table") and "Count 异常" or "Blacklist 缺失"))

    local TR = BE.Trigger
    local nT, triggerOk = nil, false
    if type(TR) == "table" and type(TR.List) == "function" then
        local ok, list = pcall(TR.List)
        if ok and type(list) == "table" then
            nT = #list
            triggerOk = true
        end
    end
    check("证据库可读", triggerOk, triggerOk and (tostring(nT) .. " 条") or "Trigger 不可用")

    local log = _G.BlackEvidenceLog
    local ents = (type(log) == "table") and log.entries or nil
    check("Logger 已绑定 SavedVariables", type(log) == "table" and type(ents) == "table",
        "BlackEvidenceLog=" .. type(log))

    local ui = BE.ManagerUI
    local nd = BE.NoteDialog
    local has = {}
    if type(ui) == "table" then
        if type(ui.ShowText) == "function" then has[#has + 1] = "ShowText" end
        if type(ui.ShowImport) == "function" then has[#has + 1] = "ShowImport" end
        if type(ui.Open) == "function" then has[#has + 1] = "Open" end
        if type(ui.Refresh) == "function" then has[#has + 1] = "Refresh" end
    end
    if type(nd) == "table" and type(nd.Open) == "function" then
        has[#has + 1] = "NoteDialog"
    end
    check("管理界面可用", #has > 0,
        #has > 0 and table.concat(has, "/") or "ManagerUI / NoteDialog 缺失")

    local menu = BE.Menu
    local mode = (type(menu) == "table" and type(menu.Stats) == "table"
        and menu.Stats.mode) or "none"
    check("右键菜单路径", mode == "modern" or mode == "legacy", "mode=" .. tostring(mode))

    local sendChat = nil
    if type(P) == "table" and type(P.Cap) == "function" then
        local ok, v = pcall(P.Cap, "sendChat")
        if ok then sendChat = v end
    end
    check("发送通道", sendChat ~= nil and sendChat ~= "none",
        "sendChat=" .. tostring(sendChat))

    local chatOn, chatSrc = nil, "不可读"
    local ci = _G.C_ChatInfo
    if type(ci) == "table" and type(ci.IsLoggingChat) == "function" then
        local ok, v = pcall(ci.IsLoggingChat)
        if ok then
            chatOn = v and true or false
            chatSrc = "C_ChatInfo"
        end
    elseif type(_G.GetCVar) == "function" then
        local ok, v = pcall(_G.GetCVar, "chatLog")
        if ok then
            chatOn = (v == "1" or v == 1)
            chatSrc = "CVar"
        end
    end
    check("聊天日志状态可读", chatOn ~= nil,
        chatOn == nil and "不可读" or ((chatOn and "开" or "关") .. " / " .. chatSrc))

    Echo("======== 自检结束：通过 %s，失败 %s ========",
        okText(tostring(pass)), fail == 0 and okText("0") or badText(tostring(fail)))
    Echo(dim("自检不写入任何数据；失败项请附 /be diag 的输出"))
    return pass, fail
end

local function handleDiag()
    local L = BE.Log
    if type(L) == "table" and type(L.CaptureStart) == "function" then
        pcall(L.CaptureStart)
    end

    local buf = {}
    local function add(fmt, ...) buf[#buf + 1] = fmtArgs(fmt, ...) end

    add("BlackEvidence 诊断｜%s", stamp())
    add("会话 #%s｜日志级别 %s", tostring((type(L) == "table") and L.Session or 0),
        logLevelText())

    add("")
    add("---- 状态 ----")
    local status = buildStatusLines()
    for i = 1, #status do add("%s", status[i]) end

    local log = _G.BlackEvidenceLog
    local marks = (type(log) == "table" and type(log.marks) == "table") and log.marks or {}
    add("")
    add("---- 锚点（共 %d 个，显示最近 %d 个）----", #marks, math.min(#marks, 10))
    if #marks == 0 then
        add("（没有锚点；/be mark 说明 可打一个）")
    else
        local from = #marks - 9
        if from < 1 then from = 1 end
        for i = from, #marks do
            local m = marks[i]
            if type(m) == "table" then
                add("  #%d %s｜%s", i, stampOf(m.t), asText(m.label or m.text or "?"))
            end
        end
    end

    add("")
    add("---- 本次会话日志 ----")
    local sessionText = ""
    if type(L) == "table" and type(L.DumpSession) == "function" then
        local ok, v = pcall(L.DumpSession)
        if ok and type(v) == "string" then sessionText = v end
    end
    add("%s", sessionText ~= "" and sessionText or "（没有日志）")

    add("")
    add("---- 最近 5 条日志 ----")
    local last5 = ""
    if type(L) == "table" and type(L.Dump) == "function" then
        local ok, v = pcall(L.Dump, 5)
        if ok and type(v) == "string" then last5 = v end
    end
    add("%s", last5 ~= "" and last5 or "（没有日志）")

    local captured = {}
    if type(L) == "table" and type(L.CaptureStop) == "function" then
        local ok, v = pcall(L.CaptureStop)
        if ok and type(v) == "table" then captured = v end
    end
    add("")
    add("---- 聊天镜像捕获：%d 行 ----", #captured)
    if #captured == 0 then
        add("（无）")
    else
        local n = #captured
        if n > 200 then n = 200 end
        for i = 1, n do add("%s", asText(captured[i])) end
        if #captured > n then add("（其余 %d 行省略）", #captured - n) end
    end

    showLong("BlackEvidence 诊断", table.concat(buf, "\n"))
end

local function handleMenu()
    local ok, rep = callModule("Menu", "LiveReport")
    if not ok then return end
    Echo("======== 右键菜单实况 ========")
    if type(rep) == "string" then
        for line in (rep .. "\n"):gmatch("([^\n]*)\n") do Echo("%s", line) end
    elseif type(rep) == "table" then
        for i = 1, #rep do Echo("%s", asText(rep[i])) end
    else
        Echo("菜单报告不可用")
    end
end

local function handleTime(arg)
    local TM = BE.Timeline
    if type(TM) ~= "table" or type(TM.Snapshot) ~= "function" then
        Echo("Timeline 模块未加载")
        return
    end

    local ok, snap = pcall(TM.Snapshot)
    if not ok or type(snap) ~= "table" then
        Echo("读取时间线失败：%s", tostring(snap))
        return
    end

    local total = #snap
    if total == 0 then
        Echo("时间线为空（最近 %s 秒没有采集到内容）",
            tostring(cfgGet("timelineSeconds") or 180))
        return
    end

    local keep = tonumber(arg) or 20
    keep = math.floor(keep)
    if keep < 1 then keep = 1 end
    if keep > 300 then keep = 300 end
    if keep > total then keep = total end

    local slice = {}
    for i = total - keep + 1, total do slice[#slice + 1] = snap[i] end

    local text = ""
    if type(TM.Format) == "function" then
        local okF, v = pcall(TM.Format, slice)
        if okF and type(v) == "string" then text = v end
    end
    if text == "" then
        local lines = {}
        for i = 1, #slice do
            local e = slice[i]
            if type(e) == "table" then
                lines[#lines + 1] = ("%s [%s] %s"):format(
                    stampOf(e.wall), tostring(e.kind or "?"), asText(e.text or ""))
            end
        end
        text = table.concat(lines, "\n")
    end

    Echo("最近 %d 条时间线（共 %d 条）：", keep, total)
    if text == "" then
        Echo("（没有内容）")
        return
    end
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do Echo("%s", line) end
end

local function showEvidenceDetail(rec)
    local target = type(rec.target) == "table" and rec.target or {}
    local shot = type(rec.screenshot) == "table" and rec.screenshot or {}
    local chat = type(rec.chatLog) == "table" and rec.chatLog or {}
    local party = type(rec.party) == "table" and rec.party or {}
    local timeline = type(rec.timeline) == "table" and rec.timeline or {}

    Echo("======== 证据 %s ========", tostring(rec.id))
    Echo("原因：%s｜时间：%s｜profile：%s",
        tostring(rec.reason), tostring(rec.at), tostring(rec.profile))
    Echo("记录者：%s", asText(rec.selfName))
    Echo("目标：%s｜key：%s", asText(target.full), tostring(target.key))
    if asText(target.guid) ~= "" then Echo("GUID：%s", asText(target.guid)) end

    local note = asText(target.note or ""):gsub("\n", " / ")
    Echo("备注：%s", note ~= "" and clip(note, 120) or "（无）")

    local names = {}
    for i = 1, #party do
        local p = party[i]
        if type(p) == "table" and asText(p.name) ~= "" then
            names[#names + 1] = asText(p.name)
        end
    end
    Echo("队伍：%d 人%s", #party,
        #names > 0 and ("（" .. clip(table.concat(names, "、"), 80) .. "）") or "")

    Echo("时间线：%d 条｜截图：%s｜聊天日志：%s", #timeline,
        asText(shot.predicted) ~= "" and asText(shot.predicted) or "未知",
        chat.enabled and "开" or "关")
    Echo(dim("完整证据包：/be pack %s"), tostring(rec.id))
end

local function handleEvidence(arg)
    local TR = BE.Trigger
    if type(TR) ~= "table" or type(TR.List) ~= "function" then
        Echo("Trigger 模块未加载")
        return
    end

    local id = trim(arg or "")
    if id ~= "" and type(TR.Get) == "function" then
        local okG, rec = pcall(TR.Get, id)
        if okG and type(rec) == "table" then
            showEvidenceDetail(rec)
            return
        end
    end

    local keep = tonumber(id) or 8
    keep = math.floor(keep)
    if keep < 1 then keep = 8 end
    if keep > 50 then keep = 50 end

    local ok, list = pcall(TR.List)
    if not ok or type(list) ~= "table" then
        Echo("读取证据失败：%s", tostring(list))
        return
    end
    if #list == 0 then
        Echo("证据库为空（右键菜单加入黑名单或 /be warn 会生成）")
        return
    end

    Echo("证据 %d 条，最近 %d 条：", #list, math.min(keep, #list))
    for i = 1, math.min(keep, #list) do
        local r = list[i]
        if type(r) == "table" then
            local tg = "?"
            if type(r.target) == "table" then
                tg = asText(r.target.full) ~= "" and asText(r.target.full)
                    or (asText(r.target.name) ~= "" and asText(r.target.name) or "?")
            end
            Echo("%d) %s｜%s｜%s｜%s", i, tostring(r.id), tostring(r.at),
                tostring(r.reason), tg)
        end
    end
    Echo(dim("详情：/be evidence <记录ID>；导出：/be pack <记录ID>"))
end

local function handleProfile(rest)
    local arg = lower(firstWord(rest))
    local P = BE.Profile
    if type(P) ~= "table" then
        Echo("Profile 模块未加载")
        return
    end

    local pid = tostring(P.id or "?")
    if arg ~= "" then
        if not PROFILE_IDS[arg] then
            Echo("未知 profile：%s（可选 retail / classic / forever）", arg)
            return
        end
        if arg ~= pid then
            Echo("切换 profile 需要重启客户端，当前为 %s（%s）", pid, profileLabel(pid))
            Echo(dim("运行时不会改写 BE.Profile.id / caps；请用对应客户端的 TOC 启动。"))
            return
        end
    end

    Echo("当前 profile：%s（%s）", pid, profileLabel(pid))
    Echo("Interface=%s｜版本 %s｜build %s",
        tostring(P.interface), tostring(P.version), tostring(P.build))

    if type(P.StatusLine) == "function" then
        local ok, line = pcall(P.StatusLine)
        if ok and type(line) == "string" then Echo("能力：%s", line) end
    end

    local caps = type(P.caps) == "table" and P.caps or {}
    local U = BE.Util
    local keys = (U and type(U.SortedKeys) == "function") and U.SortedKeys(caps) or nil
    if keys then
        for i = 1, #keys do
            local k = keys[i]
            Echo("  %s = %s", tostring(k), tostring(caps[k]))
        end
    end
    Echo(dim("只读展示；/be profile retail|classic|forever 不会切换运行时 profile"))
end

local function logMatches(line)
    if logFilter == "" then return true end
    local hay = lower(line)
    for part in logFilter:gmatch("[^,;%s]+") do
        if hay:find(lower(part), 1, true) then return true end
    end
    return false
end

local function emitLog(title, text)
    if type(text) ~= "string" or text == "" then
        Echo("%s：（没有内容）", title)
        return
    end

    Echo("---- %s ----", title)
    local shown, total = 0, 0
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        if line ~= "" then
            total = total + 1
            if logMatches(line) then
                shown = shown + 1
                if shown <= MAX_DUMP then Echo("%s", line) end
            end
        end
    end
    if logFilter ~= "" then
        Echo(dim("过滤「%s」：显示 %d / %d 行"), logFilter, shown, total)
    end
    if shown > MAX_DUMP then
        Echo(dim("仅显示前 %d 行（共 %d 行），完整内容请看 /be diag"), MAX_DUMP, shown)
    end
    Echo("---- 结束 ----")
end

local function listMarks()
    local log = _G.BlackEvidenceLog
    local marks = (type(log) == "table") and log.marks or nil
    if type(marks) ~= "table" or #marks == 0 then
        Echo("还没有锚点（先用 /be mark 说明）")
        return
    end
    Echo("现有锚点 %d 个（用法：/be log since 锚点文字）：", #marks)
    local from = #marks - 9
    if from < 1 then from = 1 end
    for i = from, #marks do
        local m = marks[i]
        if type(m) == "table" then
            Echo("  #%d [%s] %s", i, stampOf(m.t, "%m-%d %H:%M:%S"),
                asText(m.label or m.text or "?"))
        end
    end
end

local function setLogLevel(lv)
    local L = BE.Log
    if type(L) ~= "table" then
        Echo("Logger 模块未加载")
        return
    end

    if type(L.Info) == "function" then
        pcall(L.Info, "Slash", "日志级别变更为 %s", lv)
    end

    if lv == "off" then
        -- Logger.levelValue 接受数字：99 等价于全部关闭
        L.Level = 99
    else
        L.Level = lv
    end
    cfgSet("logLevel", lv)

    if lv == "off" then
        Echo("日志级别已设为 off（本次会话有效；重载后需重新设置）")
    else
        Echo("日志级别已设为 %s", lv)
    end
end

local function handleLog(rest)
    local sub, tail = splitHead(rest)
    sub = lower(sub)
    local L = BE.Log

    if sub == "" then
        Echo("日志：会话 #%s｜级别 %s｜过滤 %s",
            tostring((type(L) == "table") and L.Session or 0),
            logLevelText(),
            logFilter ~= "" and logFilter or "关")
        Echo(dim("  /be log trace|debug|info|warn|error|off"))
        Echo(dim("  /be log dump [n]｜since 锚点｜session｜trace on|off｜filter 关键字｜filter clear"))
        return
    end

    if sub == "dump" then
        if type(L) ~= "table" or type(L.Dump) ~= "function" then
            Echo("Logger 模块未加载")
            return
        end
        local n = tonumber(firstWord(tail)) or 100
        n = math.floor(n)
        if n < 1 then n = 100 end
        if n > 1000 then n = 1000 end
        local ok, text = pcall(L.Dump, n)
        if not ok then
            Echo("导出日志失败：%s", tostring(text))
            return
        end
        emitLog(("最近 %d 条日志"):format(n), text)
        return
    end

    if sub == "since" then
        if type(L) ~= "table" or type(L.DumpSince) ~= "function" then
            Echo("Logger 模块未加载")
            return
        end
        local anchor = trim(tail)
        if anchor == "" then
            listMarks()
            return
        end
        local ok, text, err, mark = pcall(L.DumpSince, anchor)
        if not ok then
            Echo("读取日志失败：%s", tostring(text))
            return
        end
        if type(text) ~= "string" or text == "" then
            Echo("%s", tostring(err or "锚点之后没有日志"))
            return
        end
        local title = "锚点「" .. anchor .. "」之后"
        if type(mark) == "table" then
            title = ("锚点「%s」之后（%s）"):format(
                asText(mark.label or mark.text or anchor),
                stampOf(mark.t, "%m-%d %H:%M:%S"))
        end
        emitLog(title, text)
        return
    end

    if sub == "session" then
        if type(L) ~= "table" or type(L.DumpSession) ~= "function" then
            Echo("Logger 模块未加载")
            return
        end
        local ok, text = pcall(L.DumpSession)
        if not ok then
            Echo("导出日志失败：%s", tostring(text))
            return
        end
        emitLog(("本次会话 #%s"):format(tostring((type(L) == "table") and L.Session or 0)), text)
        return
    end

    if sub == "trace" then
        local arg = lower(trim(tail))
        if arg == "" or arg == "on" then
            cfgSet("verboseEvents", true)
            if type(L) == "table" and L.Level ~= "trace" then
                setLogLevel("trace")
            end
            Echo("事件追踪已开启（Timeline 事件会写入 debug 日志；日志级别 %s）",
                logLevelText())
        elseif arg == "off" then
            cfgSet("verboseEvents", false)
            Echo("事件追踪已关闭（日志级别不变）")
        else
            Echo("用法：/be log trace on|off")
        end
        return
    end

    if sub == "filter" then
        local spec = trim(tail)
        if spec == "" or lower(spec) == "clear" or lower(spec) == "off" then
            logFilter = ""
            Echo("日志过滤已关闭（显示全部）")
        else
            logFilter = spec
            Echo("日志过滤已设为「%s」（按行内关键字匹配，逗号分隔；clear 取消）", spec)
        end
        return
    end

    if sub == "off" or LOG_LEVELS[sub] then
        setLogLevel(sub)
        return
    end

    Echo("未知日志子命令：%s（可用 trace/debug/info/warn/error/off）", sub)
end

local function handleMark(rest)
    local text = trim(rest)
    if text == "" then text = "手动锚点" end
    local ok, seq = callModule("Log", "Mark", text)
    if not ok then return end
    Echo("已打锚点「%s」（seq=%s）；之后用 /be log since %s",
        text, tostring(seq), text)
end

local function handleIgnore(rest, add)
    local raw = unquote(rest)
    if raw == "" then
        Echo("用法：/be %s 名字", add and "ignore" or "unignore")
        return
    end

    local state = BE.state
    if type(state) ~= "table" then
        BE.state = {}
        state = BE.state
    end
    if type(state.ignoreSession) ~= "table" then state.ignoreSession = {} end

    local entry = findEntryByRaw(raw)
    local key = entry and entry.key
    if not key then
        local info = infoFromRaw(raw)
        key = info and info.key
    end
    if not key then
        Echo("名字无效：%s", raw)
        return
    end

    local shown = entry and displayEntry(entry) or raw
    if add then
        state.ignoreSession[key] = true
        Echo("已在本场豁免：%s%s", shown,
            entry and "" or dim("（未在黑名单里，按名字生成 key，可能匹配不到队伍成员）"))
    else
        state.ignoreSession[key] = nil
        local I = BE.Identity
        if type(I) == "table" and type(I.Normalize) == "function" then
            local ok, norm = pcall(I.Normalize, raw)
            if ok and norm and state.ignoreSession[norm] then
                state.ignoreSession[norm] = nil
            end
        end
        Echo("已取消本场豁免：%s", shown)
    end
end

local function handleScreenshot()
    local api = (type(_G.Screenshot) == "function") and _G.Screenshot or _G.TakeScreenshot
    if type(api) ~= "function" then
        Echo("客户端没有截图 API")
        return
    end
    local ok, err = pcall(api)
    if ok then
        Echo("截图已触发（文件在 Screenshots 目录）")
    else
        Echo("截图失败：%s", tostring(err))
    end
end

local function clearProfileBlacklist(pid)
    local P = BE.Profile
    local current = (type(P) == "table") and P.id or nil
    if type(pid) == "string" and pid ~= "" and pid ~= current then
        Echo("只允许清空当前 profile（%s），已取消", tostring(current or "?"))
        return false
    end

    local B = BE.Blacklist
    if type(B) ~= "table" or type(B.Store) ~= "function" then
        Echo("Blacklist 模块未加载，无法清空")
        return false
    end
    local ok, store = pcall(B.Store)
    if not ok or type(store) ~= "table" then
        Echo("读取黑名单失败：%s", tostring(store))
        return false
    end

    local n = 0
    for k in pairs(store) do
        store[k] = nil
        n = n + 1
    end
    if type(B.RebuildIndex) == "function" then pcall(B.RebuildIndex) end
    refreshUI()

    Echo("已清空当前 profile（%s）的黑名单：%d 条", tostring(current or "?"), n)
    local L = BE.Log
    if type(L) == "table" and type(L.Warn) == "function" then
        pcall(L.Warn, "Slash", "用户清空黑名单：profile=%s，删除 %d 条",
            tostring(current or "?"), n)
    end
    return true
end

local function handleReset()
    if type(StaticPopupDialogs) ~= "table" or type(StaticPopup_Show) ~= "function" then
        Echo("客户端没有 StaticPopup，已取消（未做任何修改）")
        return
    end

    local P = BE.Profile
    local pid = (type(P) == "table") and P.id or "?"

    if StaticPopupDialogs["BLACKEVIDENCE_RESET"] == nil then
        StaticPopupDialogs["BLACKEVIDENCE_RESET"] = {
            text = "确定清空「%s」黑名单？此操作不可撤销。",
            button1 = "清空",
            button2 = "取消",
            OnAccept = function(self, data)
                local target = data
                if target == nil and type(self) == "table" then target = self.data end
                clearProfileBlacklist(target)
            end,
            timeout = 0,
            whileDead = 1,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end

    StaticPopup_Show("BLACKEVIDENCE_RESET",
        ("%s（%s）"):format(profileLabel(pid), tostring(pid)), nil, pid)
end

----------------------------------------------------------------------
-- 入口
----------------------------------------------------------------------

function S.Handle(msg)
    local cmd, rest = splitHead(msg)
    cmd = lower(cmd)

    if cmd == "" or cmd == "help" or cmd == "?" then
        handleHelp()
    elseif cmd == "add" then
        handleAdd(rest)
    elseif cmd == "del" or cmd == "remove" then
        handleDel(rest)
    elseif cmd == "note" then
        handleNote(rest)
    elseif cmd == "list" then
        handleList()
    elseif cmd == "search" then
        handleSearch(rest)
    elseif cmd == "export" then
        handleExport(rest)
    elseif cmd == "import" then
        handleImport()
    elseif cmd == "pack" then
        handlePack(rest)
    elseif cmd == "scan" then
        handleScan()
    elseif cmd == "warn" then
        handleWarn(rest)
    elseif cmd == "queue" then
        handleQueue()
    elseif cmd == "flush" then
        handleFlush()
    elseif cmd == "status" then
        handleStatus()
    elseif cmd == "selftest" or cmd == "test" then
        handleSelfTest()
    elseif cmd == "diag" then
        handleDiag()
    elseif cmd == "menu" then
        handleMenu()
    elseif cmd == "time" or cmd == "timeline" then
        handleTime(rest)
    elseif cmd == "evidence" or cmd == "ev" then
        handleEvidence(rest)
    elseif cmd == "profile" then
        handleProfile(rest)
    elseif cmd == "log" then
        handleLog(rest)
    elseif cmd == "mark" then
        handleMark(rest)
    elseif cmd == "ignore" then
        handleIgnore(rest, true)
    elseif cmd == "unignore" then
        handleIgnore(rest, false)
    elseif cmd == "screenshot" or cmd == "shot" then
        handleScreenshot()
    elseif cmd == "reset" then
        handleReset()
    else
        Echo("未知命令：%s（输入 /be help 查看全部命令）", tostring(cmd))
    end
end

function S.Init()
    if type(SlashCmdList) ~= "table" then
        local L = BE.Log
        if type(L) == "table" and type(L.Error) == "function" then
            pcall(L.Error, "Slash", "SlashCmdList 不可用，命令注册失败")
        end
        return false
    end

    SLASH_BLACKEVIDENCE1 = "/be"
    SLASH_BLACKEVIDENCE2 = "/blackevidence"

    SlashCmdList["BLACKEVIDENCE"] = function(msg)
        local ok, err = pcall(S.Handle, msg)
        if not ok then
            Echo("命令执行出错：%s", tostring(err))
            local L = BE.Log
            if type(L) == "table" and type(L.Error) == "function" then
                pcall(L.Error, "Slash", "命令出错（%s）：%s", tostring(msg), tostring(err))
            end
        end
    end

    local L = BE.Log
    if type(L) == "table" and type(L.Info) == "function" then
        pcall(L.Info, "Slash", "命令已注册：/be, /blackevidence")
    end
    return true
end
