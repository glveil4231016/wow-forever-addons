-- BlackEvidence / Identity.lua
-- 唯一身份入口。三个 profile 的姓名模型不同：
--   retail / classic ：UnitName(unit) -> name, realm     （第二段是服务器，可能为空）
--   forever          ：UnitName(unit) -> name, surname   （第二段是"姓"）
-- 其它模块禁止自己拼名字，一律走这里。

local ADDON, BE = ...
BE.Identity = BE.Identity or {}
local I = BE.Identity

local function isPlain(v)
    if type(v) ~= "string" then return false end
    if type(_G.issecretvalue) == "function" then
        local ok, r = pcall(_G.issecretvalue, v)
        if ok and r then return false end
    end
    return true
end

local function trim(s)
    if type(s) ~= "string" then return nil end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- 只对 ASCII A-Z 做小写，避免动到 UTF-8 字节
local function asciiLower(s)
    if type(s) ~= "string" then return nil end
    return (s:gsub("%u", function(ch)
        return string.char(ch:byte() + 32)
    end))
end

local function splitOn(s, sep)
    if type(s) ~= "string" or type(sep) ~= "string" or sep == "" then return s, nil end
    local i = s:find(sep, 1, true)
    if not i then return s, nil end
    return s:sub(1, i - 1), s:sub(i + #sep)
end

local cachedSep
local function surnameSep()
    if cachedSep then return cachedSep end
    local c = _G.Constants
    local s = c and c.CharacterNameSeparatorConsts
        and c.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR
    if type(s) == "string" and s ~= "" then
        cachedSep = s
    else
        cachedSep = " "   -- 兜底：空格（永不服实测后若不同，改这里）
    end
    return cachedSep
end

local function isSurnameMode()
    return BE.Profile and BE.Profile.Cap and BE.Profile.Cap("surname")
end

function I.Normalize(s)
    local t = trim(s)
    if not t then return nil end
    return asciiLower(t)
end

function I.Separator()
    return isSurnameMode() and surnameSep() or "-"
end

-- 第二段的语义：forever = 姓，其余 = 服务器
function I.SecondLabel()
    return isSurnameMode() and "姓" or "服务器"
end

-- 由两段构造归一化 key（小写）
function I.KeyFromParts(name, second)
    local n = trim(name)
    if not n or n == "" or not isPlain(n) then return nil end
    local s = trim(second)
    if s ~= nil and s == "" then s = nil end
    if s and not isPlain(s) then s = nil end

    local full
    if s then
        full = n .. (isSurnameMode() and surnameSep() or "-") .. s
    else
        full = n
    end
    return asciiLower(trim(full))
end

function I.Key(unit)
    local info = I.Unit(unit)
    return info and info.key or nil
end

-- 从"完整显示名"反推 key（聊天事件、导出导入用）
function I.KeyFromFull(full, guid)
    local t = trim(full)
    if not t or t == "" or not isPlain(t) then return nil end
    local sep = isSurnameMode() and surnameSep() or "-"
    local a, b = splitOn(t, sep)
    if not b then
        -- 兼容 "Name - Realm" 的带空格写法
        a, b = t:match("^(.-)%s*%-%s*(.+)$")
    end
    local key = I.KeyFromParts(a or t, b)
    if key then return key, a, b end
    return nil
end

-- 读取单位信息（全部 pcall，secret 视为不可用）
function I.Unit(unit)
    if not unit then return nil end

    local name, second
    if type(_G.UnitNameUnmodified) == "function" then
        local ok, n, s = pcall(_G.UnitNameUnmodified, unit)
        if ok then name, second = n, s end
    end
    if (not name) and type(_G.UnitName) == "function" then
        local ok, n, s = pcall(_G.UnitName, unit)
        if ok then name, second = n, s end
    end
    if not name or name == "" or not isPlain(name) then return nil end

    local surname, realm
    if isSurnameMode() then
        surname = trim(second)
        if surname == "" or (surname and not isPlain(surname)) then surname = nil end
        -- 兜底：UnitName 有时把两段拼在第一个返回值里
        if not surname then
            local a, b = splitOn(name, surnameSep())
            if b then name, surname = a, b end
        end
    else
        realm = trim(second)
        if realm == "" then realm = nil end
    end

    local guid
    if type(_G.UnitGUID) == "function" then
        local ok, g = pcall(_G.UnitGUID, unit)
        if ok and isPlain(g) and g ~= "" then guid = g end
    end

    local key = I.KeyFromParts(name, isSurnameMode() and surname or realm)
    if not key then return nil end

    return {
        name    = name,
        surname = surname,
        realm   = realm,
        guid    = guid,
        key     = key,
        unit    = unit,
        full    = I.Display({ name = name, surname = surname, realm = realm }),
    }
end

-- 显示名：entry 表 或 (name, second)
function I.Display(entry, second)
    local name, surname, realm
    if type(entry) == "table" then
        name, surname, realm = entry.name, entry.surname, entry.realm
    else
        name = entry
        if isSurnameMode() then surname = second else realm = second end
    end

    name = trim(name)
    if not name then return "?" end

    if isSurnameMode() then
        local s = trim(surname)
        if s and s ~= "" then return name .. surnameSep() .. s end
        return name
    end

    local r = trim(realm)
    if r and r ~= "" then return name .. "-" .. r end
    return name
end

-- 从聊天事件构造（playerName 可能是完整名，guid 在第 12 个参数）
function I.FromChat(playerName, guid)
    local key, a, b = I.KeyFromFull(playerName, guid)
    if not key then return nil end
    local e = {
        name = a or playerName,
        key  = key,
        guid = (isPlain(guid) and guid ~= "") and guid or nil,
    }
    if isSurnameMode() then e.surname = b else e.realm = b end
    e.full = I.Display(e)
    return e
end
