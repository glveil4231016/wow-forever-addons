-- BlackEvidence / Export.lua
-- 黑名单导出 / 导入 + 证据包文本。
-- 格式 #BE-LIST v2：备注不转义，note= 之后直到单独的 --- 行全部算备注原文。
-- 备注里任何一行恰好是 --- 时无法无损表达：导出跳过该条并记 warn，导入也跳过。

local ADDON, BE = ...
BE.Export = BE.Export or {}
local E = BE.Export

E.FORMAT = "#BE-LIST v2"

local KNOWN_PROFILE = { retail = true, classic = true, forever = true }
local FALLBACK_BYTES = 1800
local NOTE_LIMIT = 2000

----------------------------------------------------------------------
-- 基础工具
----------------------------------------------------------------------

local function log(level, fmt, ...)
    local L = BE.Log
    if type(L) ~= "table" then return end
    local fn = L[level]
    if type(fn) == "function" then pcall(fn, "Export", fmt, ...) end
end

local function plain(v)
    if type(v) ~= "string" then return nil end
    local U = BE.Util
    if U and type(U.IsSecret) == "function" then
        local ok, secret = pcall(U.IsSecret, v)
        if ok and secret then return nil end
    end
    return v
end

local function str(v)
    return plain(v) or ""
end

local function trim(s)
    if type(s) ~= "string" then return "" end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function wallNow()
    if type(time) == "function" then
        local ok, v = pcall(time)
        if ok and type(v) == "number" then return v end
    end
    return 0
end

local function stampOf(ts, fmt)
    ts = tonumber(ts)
    if not ts or ts <= 0 then return "?" end
    if type(date) ~= "function" then return tostring(ts) end
    local ok, v = pcall(date, fmt or "%Y-%m-%d %H:%M:%S", ts)
    if ok and type(v) == "string" then return v end
    return tostring(ts)
end

local function currentProfile()
    local P = BE.Profile
    if type(P) == "table" and type(P.id) == "string" and P.id ~= "" then
        return P.id
    end
    return "retail"
end

local function resolveProfile(profileId)
    local pid = profileId
    if type(pid) ~= "string" or pid == "" then
        return currentProfile(), false
    end
    pid = pid:lower()
    if not KNOWN_PROFILE[pid] then
        log("Warn", "未知 profile「%s」，改用当前 %s", tostring(profileId), currentProfile())
        return currentProfile(), true
    end
    return pid, false
end

-- 当前 profile 的分仓（不经过 Blacklist，便于导出任意 profile）
local function storeFor(pid)
    local db = _G.BlackEvidenceDB
    if type(db) ~= "table" or type(db.profiles) ~= "table" then return nil end
    local p = db.profiles[pid]
    if type(p) ~= "table" or type(p.blacklist) ~= "table" then return nil end
    return p.blacklist
end

local function sortValue(e)
    return (tonumber(e.lastSeen) or 0) * 1000000000 + (tonumber(e.createdAt) or 0)
end

local function sortedEntries(store)
    local out = {}
    if type(store) ~= "table" then return out end
    for _, e in pairs(store) do
        if type(e) == "table" and type(e.name) == "string" and e.name ~= "" then
            out[#out + 1] = e
        end
    end
    table.sort(out, function(a, b)
        local va, vb = sortValue(a), sortValue(b)
        if va == vb then
            return tostring(a.key or a.name) < tostring(b.key or b.name)
        end
        return va > vb
    end)
    return out
end

local function oneLine(v)
    local s = str(v)
    s = s:gsub("\r\n", " "):gsub("[\r\n]", " ")
    return s
end

local function splitLines(s)
    local out = {}
    for line in (s .. "\n"):gmatch("([^\n]*)\n") do
        out[#out + 1] = line
    end
    if #out == 0 then out[1] = "" end
    return out
end

-- 备注里出现"整行恰好是 ---"就无法无歧义地落进格式里
local function separatorLine(lines)
    for i = 1, #lines do
        if trim(lines[i]) == "---" then return i end
    end
    return nil
end

local function noteHasSeparator(note)
    if type(note) ~= "string" or note == "" then return false end
    for line in (note .. "\n"):gmatch("([^\n]*)\n") do
        if trim(line) == "---" then return true end
    end
    return false
end

local function normalizeNote(note)
    if type(note) ~= "string" then return "" end
    local s = note:gsub("\r\n", "\n"):gsub("\r", "\n")
    local U = BE.Util
    if U and type(U.Truncate) == "function" then
        s = U.Truncate(s, NOTE_LIMIT)
    end
    return s
end

----------------------------------------------------------------------
-- 聊天窗兜底
----------------------------------------------------------------------

local PREFIX = "|cff33ff99[BE]|r"

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

local function printBlock(title, text)
    chatLine(PREFIX .. " ---- " .. tostring(title) .. " ----")
    local clipped, cut = text, false
    local U = BE.Util
    if U and type(U.Truncate) == "function" and #text > FALLBACK_BYTES then
        clipped = U.Truncate(text, FALLBACK_BYTES)
        cut = true
    end
    for line in (clipped .. "\n"):gmatch("([^\n]*)\n") do
        chatLine(PREFIX .. " " .. line)
    end
    chatLine(PREFIX .. " ---- 结束 ----")
    if cut then
        chatLine(PREFIX .. " 内容过长，仅显示前 " .. FALLBACK_BYTES .. " 字节；"
            .. "完整内容请看管理界面或 SavedVariables")
    end
end

-- ManagerUI 尚未加载（或调用失败）时退回聊天窗
local function showText(title, text)
    text = tostring(text or "")
    local ui = BE.ManagerUI
    if type(ui) == "table" and type(ui.ShowText) == "function" then
        local ok, res = pcall(ui.ShowText, title, text)
        if ok and res ~= false then return true end
        local ok2, res2 = pcall(ui.ShowText, ui, title, text)
        if ok2 and res2 ~= false then return true end
        log("Warn", "ManagerUI.ShowText 调用失败，改用聊天窗输出")
    end
    printBlock(title, text)
    return false
end

local function refreshUI()
    local ui = BE.ManagerUI
    if type(ui) ~= "table" or type(ui.Refresh) ~= "function" then return false end
    local ok, res = pcall(ui.Refresh)
    if ok and res ~= false then return true end
    local ok2 = pcall(ui.Refresh, ui)
    return ok2
end

----------------------------------------------------------------------
-- 导出
----------------------------------------------------------------------

function E.List(profileId)
    local pid = resolveProfile(profileId)
    local store = storeFor(pid)
    local list = store and sortedEntries(store) or {}

    local out = { E.FORMAT }
    local skipped = 0

    for i = 1, #list do
        local e = list[i]
        local name = oneLine(e.name)
        if name == "" then
            skipped = skipped + 1
            log("Warn", "条目 %s 缺少 name，跳过导出", tostring(e.key))
        else
            local lines = splitLines(str(e.note))
            local bad = separatorLine(lines)
            if bad then
                skipped = skipped + 1
                log("Warn", "条目 %s 的备注第 %d 行是分隔行 ---，跳过导出", tostring(e.key), bad)
            else
                out[#out + 1] = "profile=" .. pid
                out[#out + 1] = "name=" .. name
                out[#out + 1] = "surname=" .. oneLine(e.surname)
                out[#out + 1] = "realm=" .. oneLine(e.realm)
                out[#out + 1] = "guid=" .. oneLine(e.guid)
                out[#out + 1] = "hits=" .. tostring(tonumber(e.hits) or 0)
                out[#out + 1] = "note=" .. lines[1]
                for j = 2, #lines do out[#out + 1] = lines[j] end
                out[#out + 1] = "---"
            end
        end
    end

    if #list == 0 then
        log("Debug", "%s 黑名单为空", pid)
    elseif skipped > 0 then
        log("Warn", "导出 %s：写入 %d 条，跳过 %d 条", pid, #list - skipped, skipped)
    else
        log("Debug", "导出 %s：%d 条", pid, #list)
    end
    return table.concat(out, "\n")
end

----------------------------------------------------------------------
-- 解析
----------------------------------------------------------------------

-- 返回 { {profile,name,surname,realm,guid,hits,note}, ... }
-- 容忍 CRLF、空行、注释行，以及"一行一个名字"的旧格式。
function E.Parse(text)
    local entries = {}
    if type(text) ~= "string" or text == "" then return entries end

    local input = text
    if input:sub(1, 3) == "\239\187\191" then input = input:sub(4) end   -- 去 BOM
    if input:sub(-1) == "\n" then input = input:sub(1, -2) end            -- 行尾终止符不算空行

    local cur, inNote = nil, false

    local function flush()
        if not cur then return end
        local name = trim(cur.name or "")
        if name ~= "" then
            cur.name = name
            cur.profile = type(cur.profile) == "string" and cur.profile or ""
            cur.surname = type(cur.surname) == "string" and cur.surname or ""
            cur.realm = type(cur.realm) == "string" and cur.realm or ""
            cur.guid = type(cur.guid) == "string" and cur.guid or ""
            cur.hits = tonumber(cur.hits) or 0
            if type(cur.note) ~= "string" then cur.note = "" end
            entries[#entries + 1] = cur
        end
        cur, inNote = nil, false
    end

    for raw in (input .. "\n"):gmatch("([^\n]*)\n") do
        local line = raw:gsub("\r$", "")
        local t = trim(line)

        if inNote then
            if t == "---" then
                flush()
            else
                cur.note = (cur.note or "") .. "\n" .. line
            end
        elseif t == "" then
            -- 条目之间 / 表头里的空行：忽略
        elseif t:sub(1, 1) == "#" then
            -- 表头注释：忽略
        elseif t == "---" then
            flush()
        else
            local k, v = t:match("^([%a_][%w_]*)%s*=%s*(.*)$")
            if k then
                k = k:lower()
                -- 缺了分隔行时，第二个 name= 视为下一条，避免两条挤成一条
                if k == "name" and cur and cur.name ~= nil then flush() end
                if not cur then cur = {} end
                if k == "note" then
                    cur.note = v
                    inNote = true
                elseif k == "hits" then
                    cur.hits = tonumber(v)
                else
                    cur[k] = v
                end
            else
                -- 旧格式：一行一个名字
                flush()
                entries[#entries + 1] = {
                    profile = "", name = t, surname = "", realm = "",
                    guid = "", hits = 0, note = "",
                }
            end
        end
    end
    flush()

    return entries
end

----------------------------------------------------------------------
-- 导入
----------------------------------------------------------------------

local function infoFromParsed(it)
    local I = BE.Identity
    if type(I) ~= "table" or type(I.KeyFromParts) ~= "function" then
        return nil, "Identity 模块不可用"
    end

    local name = trim(it.name or "")
    if name == "" then return nil, "缺少名字" end
    if not plain(name) then return nil, "名字不可读" end

    local surname = trim(it.surname or "")
    local realm = trim(it.realm or "")
    local guid = trim(it.guid or "")
    if surname == "" then surname = nil end
    if realm == "" then realm = nil end
    if guid == "" or not plain(guid) then guid = nil end
    if surname and not plain(surname) then surname = nil end
    if realm and not plain(realm) then realm = nil end

    local surnameMode = false
    local P = BE.Profile
    if type(P) == "table" and type(P.Cap) == "function" then
        local ok, v = pcall(P.Cap, "surname")
        surnameMode = ok and v and true or false
    end

    local second = surnameMode and surname or realm
    local key = I.KeyFromParts(name, second)
    if not key then
        -- 兜底：名字本身可能已经是"全名"
        if type(I.KeyFromFull) == "function" then
            local ok, k = pcall(I.KeyFromFull, name)
            if ok and k then key = k end
        end
    end
    if not key then return nil, "名字无法归一化" end

    local info = {
        name = name,
        key = key,
        guid = guid,
        surname = surnameMode and surname or nil,
        realm = surnameMode and nil or realm,
    }
    if type(I.Display) == "function" then
        local ok, full = pcall(I.Display, info)
        info.full = ok and type(full) == "string" and full or name
    else
        info.full = name
    end
    return info
end

-- 单条应用：先校验、后写入（尽量做到单条原子）
local function applyOne(it, scope, pid, out)
    local name = trim(it.name or "")
    if name == "" or not plain(name) then
        out.failed = out.failed + 1
        log("Warn", "跳过一条没有有效名字的记录")
        return
    end

    local tag = trim(it.profile or ""):lower()
    if scope == "current" and tag ~= "" and tag ~= pid then
        out.failed = out.failed + 1
        log("Info", "跳过 profile=%s 的条目（当前 %s）：%s", tag, pid, name)
        return
    end

    local note = normalizeNote(it.note)
    if noteHasSeparator(note) then
        out.failed = out.failed + 1
        log("Warn", "条目 %s 的备注含分隔行 ---，跳过导入", name)
        return
    end

    local info, err = infoFromParsed(it)
    if not info then
        out.failed = out.failed + 1
        log("Warn", "条目 %s 无法导入：%s", name, tostring(err))
        return
    end

    local B = BE.Blacklist
    local existing = B.Get(info.key)
    if not existing and info.guid and type(B.FindByGUID) == "function" then
        existing = B.FindByGUID(info.guid)
    end

    if existing then
        -- 已存在：只更新备注 / updatedAt，保留 createdAt / hits / 名字
        if note ~= "" and note ~= existing.note then
            existing.note = note
            existing.updatedAt = wallNow()
        end
        out.updated = out.updated + 1
        return
    end

    local entry = B.Add(info, note, "import")
    if type(entry) ~= "table" then
        out.failed = out.failed + 1
        log("Warn", "条目 %s 写入失败", name)
        return
    end

    local hits = tonumber(it.hits) or 0
    if hits > 0 then entry.hits = math.floor(hits) end
    out.added = out.added + 1
end

-- opts.profile = "current"（默认，只导入当前分仓）| "all"（不看 profile= 标记，全部导入当前分仓）
function E.Import(text, opts)
    local out = { parsed = 0, added = 0, updated = 0, failed = 0 }

    local B = BE.Blacklist
    if type(B) ~= "table" or type(B.Add) ~= "function" or type(B.Get) ~= "function" then
        log("Error", "Blacklist 未加载，导入中止")
        return out
    end

    local entries = E.Parse(text)
    out.parsed = #entries
    if out.parsed == 0 then
        log("Warn", "导入：没有解析出任何条目")
        return out
    end

    local pid = currentProfile()
    local scope = "current"
    local want = (type(opts) == "table") and opts.profile or nil
    if type(want) == "string" then want = want:lower() end
    if want == "all" then
        scope = "all"
    elseif want ~= nil and want ~= "current" then
        log("Warn", "未知 opts.profile=%s，按 current 处理", tostring(opts.profile))
    end

    for i = 1, #entries do
        local ok, err = pcall(applyOne, entries[i], scope, pid, out)
        if not ok then
            out.failed = out.failed + 1
            log("Error", "第 %d 条导入异常：%s", i, tostring(err))
        end
    end

    if out.added > 0 or out.updated > 0 then
        if type(B.RebuildIndex) == "function" then pcall(B.RebuildIndex) end
        refreshUI()
    end

    log("Info", "导入完成（profile=%s，范围=%s）：解析 %d｜新增 %d｜更新 %d｜失败 %d",
        pid, scope, out.parsed, out.added, out.updated, out.failed)
    return out
end

----------------------------------------------------------------------
-- 证据包
----------------------------------------------------------------------

local function packParty(add, party)
    if type(party) ~= "table" or #party == 0 then
        add("队伍      ：（无队伍信息）")
        return
    end
    add("队伍      ：%d 人", #party)
    local n = #party
    if n > 40 then n = 40 end
    for i = 1, n do
        local p = party[i]
        if type(p) == "table" then
            local cls = str(p.class)
            add("  %d) %s%s", i, str(p.name) ~= "" and str(p.name) or "?",
                cls ~= "" and ("（" .. cls .. "）") or "")
        end
    end
end

function E.Pack(id)
    local TR = BE.Trigger
    if type(TR) ~= "table" or type(TR.Get) ~= "function" then
        return nil, "Trigger 模块不可用"
    end

    local rid = trim(id or "")
    if rid == "" and type(TR.LatestID) == "function" then
        local ok, v = pcall(TR.LatestID)
        if ok then rid = trim(v or "") end
    end
    if rid == "" then return nil, "没有可打包的证据记录（先加入一个黑名单或 /be warn）" end

    local ok, rec = pcall(TR.Get, rid)
    if not ok or type(rec) ~= "table" then
        return nil, "找不到证据记录：" .. rid
    end

    local target = type(rec.target) == "table" and rec.target or {}
    local shot = type(rec.screenshot) == "table" and rec.screenshot or {}
    local chat = type(rec.chatLog) == "table" and rec.chatLog or {}
    local party = type(rec.party) == "table" and rec.party or {}
    local timeline = type(rec.timeline) == "table" and rec.timeline or {}

    local lines = {}
    local function add(fmt, ...)
        if select("#", ...) > 0 then
            local okF, s = pcall(string.format, fmt, ...)
            lines[#lines + 1] = (okF and type(s) == "string") and s or tostring(fmt)
        else
            lines[#lines + 1] = tostring(fmt)
        end
    end

    local recId = str(rec.id) ~= "" and str(rec.id) or rid

    add("【BlackEvidence 证据包】%s", recId)
    add("记录 ID   ：%s", recId)
    add("触发原因  ：%s", str(rec.reason) ~= "" and str(rec.reason) or "?")
    add("记录时间  ：%s", str(rec.at) ~= "" and str(rec.at) or stampOf(rec.wall))

    local pid = str(rec.profile) ~= "" and str(rec.profile) or currentProfile()
    local label = pid
    if type(BE.Profile) == "table" and BE.Profile.id == pid
        and type(BE.Profile.label) == "string" and BE.Profile.label ~= "" then
        label = BE.Profile.label
    end
    add("客户端    ：%s（profile=%s）", label, pid)
    add("记录者    ：%s", str(rec.selfName) ~= "" and str(rec.selfName) or "?")

    add("目标      ：%s", str(target.full) ~= "" and str(target.full)
        or (str(target.name) ~= "" and str(target.name) or "?"))
    add("目标 key  ：%s", str(target.key) ~= "" and str(target.key) or "?")
    if str(target.guid) ~= "" then add("GUID      ：%s", str(target.guid)) end
    if str(target.surname) ~= "" then add("姓        ：%s", str(target.surname)) end
    if str(target.realm) ~= "" then add("服务器    ：%s", str(target.realm)) end

    local note = str(target.note)
    if note == "" then
        add("备注      ：（无）")
    else
        add("备注      ：")
        for line in (note .. "\n"):gmatch("([^\n]*)\n") do
            add("  %s", line)
        end
    end

    packParty(add, party)

    add("")
    add("---- 时间线（%d 条）----", #timeline)
    local timelineText = str(rec.timelineText)
    if timelineText == "" and type(BE.Timeline) == "table"
        and type(BE.Timeline.Format) == "function" and #timeline > 0 then
        local okF, v = pcall(BE.Timeline.Format, timeline)
        if okF and type(v) == "string" then timelineText = v end
    end
    add("%s", timelineText ~= "" and timelineText or "（没有采集到时间线内容）")

    add("")
    add("---- 截图 / 录像 ----")
    add("截图预测文件名：%s",
        str(shot.predicted) ~= "" and str(shot.predicted) or "（未知）")
    if shot.ok then
        add("截图调用    ：成功%s", tonumber(shot.at) and ("（" .. stampOf(shot.at) .. "）") or "")
    elseif shot.scheduled then
        add("截图调用    ：已排队（延迟 %.2f 秒）", tonumber(shot.delay) or 0)
    elseif str(shot.err) ~= "" then
        add("截图调用    ：失败（%s）", str(shot.err))
    else
        add("截图调用    ：未触发")
    end
    add("聊天日志    ：%s", chat.enabled and "已开启" or "未开启")
    add("录像目录    ：由外部录像助手按已知前缀归档（与上面的 WoWScrnShot_* 文件名匹配，"
        .. "插件本身不写文件）")

    local text = table.concat(lines, "\n")
    log("Info", "已打包证据 %s（%d 字）", recId, #text)
    return text
end

----------------------------------------------------------------------
-- 对外入口
----------------------------------------------------------------------

function E.ShowList(profileId)
    local pid = resolveProfile(profileId)
    local text = E.List(pid)
    local n = 0
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        if line == "---" then n = n + 1 end
    end
    local title = ("导出黑名单（%s，%d 条）"):format(pid, n)
    showText(title, text)
    log("Info", "已生成黑名单导出：%s，%d 条，%d 字节", pid, n, #text)
    return text
end

function E.ShowImport()
    local ui = BE.ManagerUI
    if type(ui) == "table" and type(ui.ShowImport) == "function" then
        local ok, res = pcall(ui.ShowImport)
        if ok and res ~= false then return true end
        local ok2, res2 = pcall(ui.ShowImport, ui)
        if ok2 and res2 ~= false then return true end
        log("Warn", "ManagerUI.ShowImport 调用失败")
    end
    chatLine(PREFIX .. " 管理界面不可用，无法打开导入窗口（请确认 ManagerUI 已加载：/be status）")
    chatLine(PREFIX .. " 导入需要在管理界面的导入框中粘贴文本；格式见 /be export 的输出")
    return false
end

function E.Init()
    log("Debug", "Export 就绪（格式 %s）", E.FORMAT)
    return true
end
