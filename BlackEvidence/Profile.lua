-- BlackEvidence / Profile.lua
-- 客户端能力探测：同一份代码在 正式服 / 经典时光服 / 无限服(Forever) 下自适应。
-- 其它模块只允许读 BE.Profile.caps，禁止散落 WOW_PROJECT_ID 判断。

local ADDON, BE = ...
BE.Profile = BE.Profile or {}
local P = BE.Profile

local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a = pcall(fn, ...)
    if ok then return a end
    return nil
end

local function hasTable(t)
    return type(t) == "table"
end

local function hasFunc(t, k)
    return type(t) == "table" and type(t[k]) == "function"
end

-- 无限服的姓名第二段是"姓"，不是服务器。
local function detectsSurname()
    local c = _G.Constants
    if hasTable(c) and hasTable(c.CharacterNameSeparatorConsts)
        and c.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR ~= nil then
        return true
    end
    if type(_G.RegionalUniqueNamesEnabled) == "function" then
        local ok, v = pcall(_G.RegionalUniqueNamesEnabled)
        if ok and v then return true end
    end
    return false
end

local function projectId()
    local id = _G.WOW_PROJECT_ID
    if id ~= nil then return id end
    return nil
end

local function projectMatches(name)
    local id = projectId()
    local const = _G[name]
    return id ~= nil and const ~= nil and id == const
end

local function buildCaps()
    local caps = {}

    caps.modernMenu   = hasFunc(_G.Menu, "ModifyMenu")
    caps.lootHistory  = hasTable(_G.C_LootHistory)
    caps.rollItemAPI  = hasFunc(_G.C_TooltipInfo, "GetLootRollItem")
    caps.secret       = type(_G.issecretvalue) == "function"
    caps.lockdown     = hasFunc(_G.C_ChatInfo, "InChatMessagingLockdown")
    caps.loggingChat  = type(_G.LoggingChat) == "function"
    caps.combatLogApi = hasTable(_G.C_CombatLog)
    caps.surname      = detectsSurname()

    -- 发送通道：12.x 只有 C_ChatInfo.SendChatMessage；旧客户端仍是全局函数。
    if hasFunc(_G.C_ChatInfo, "SendChatMessage") then
        caps.sendChat = "nameless"
    elseif type(_G.SendChatMessage) == "function" then
        caps.sendChat = "global"
    else
        caps.sendChat = "none"
    end

    return caps
end

local function guessId(caps)
    if caps.surname then return "forever" end
    if projectMatches("WOW_PROJECT_MAINLINE") then return "retail" end
    if projectMatches("WOW_PROJECT_CLASSIC")
        or projectMatches("WOW_PROJECT_BURNING_CRUSADE_CLASSIC")
        or projectMatches("WOW_PROJECT_WRATH_CLASSIC")
        or projectMatches("WOW_PROJECT_CATACLYSM_CLASSIC")
        or projectMatches("WOW_PROJECT_MISTS_CLASSIC") then
        return "classic"
    end

    -- 兜底：按 Interface 号段推断（拿不到项目常量时才会走到）
    local iface = P.interface or 0
    if iface >= 16001 and iface < 20000 then return "forever" end
    if iface >= 100000 then return "retail" end
    return "classic"
end

local LABELS = {
    retail  = "正式服",
    classic = "经典时光服",
    forever = "无限服",
}

local FLAVOR_LABELS = {
    WOW_PROJECT_MAINLINE                  = "正式服",
    WOW_PROJECT_CLASSIC                   = "经典旧世",
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC   = "燃烧的远征",
    WOW_PROJECT_WRATH_CLASSIC             = "巫妖王之怒",
    WOW_PROJECT_CATACLYSM_CLASSIC         = "大灾变",
    WOW_PROJECT_MISTS_CLASSIC             = "熊猫人之谜",
}

function P.Detect()
    local ok, version, build, _, iface = pcall(GetBuildInfo)
    if not ok then version, build, iface = "0.0.0", 0, 0 end

    P.version   = tostring(version or "0.0.0")
    P.build     = tonumber(build) or 0
    P.interface = tonumber(iface) or 0
    P.caps      = buildCaps()
    P.id        = guessId(P.caps)
    P.label     = LABELS[P.id] or P.id

    -- 经典服的细分名称（只用于显示）
    P.subLabel = nil
    local pid = projectId()
    if P.id ~= "forever" and pid ~= nil then
        for const, label in pairs(FLAVOR_LABELS) do
            if _G[const] == pid and type(_G[const]) == "number" then
                P.subLabel = label
                break
            end
        end
    end

    return P
end

function P.Is(id)
    return P.id == id
end

-- 返回布尔，或 sendChat 通道字符串
function P.Cap(name)
    return P.caps and P.caps[name] or nil
end

function P.StatusLine()
    local c = P.caps or {}
    local parts = {
        ("[%s] %s"):format(P.label or "?", "Interface " .. tostring(P.interface or 0)),
        "menu=" .. (c.modernMenu and "modern" or "legacy"),
        "name=" .. (c.surname and "surname" or "realm"),
        "sendChat=" .. tostring(c.sendChat),
        "lootHistory=" .. (c.lootHistory and "yes" or "no"),
        "secret=" .. (c.secret and "yes" or "no"),
    }
    if P.subLabel and P.subLabel ~= P.label then
        table.insert(parts, 2, "(" .. P.subLabel .. ")")
    end
    return table.concat(parts, " | ")
end

-- 供 /be status 使用：逐项列出关键 API
function P.ApiReport()
    local c = P.caps or {}
    local checks = {
        { "Menu.ModifyMenu", c.modernMenu },
        { "UnitPopupMenus",  type(_G.UnitPopupMenus) == "table" },
        { "C_ChatInfo.SendChatMessage", c.sendChat == "nameless" },
        { "SendChatMessage", c.sendChat == "global" },
        { "C_ChatInfo.InChatMessagingLockdown", c.lockdown },
        { "issecretvalue", c.secret },
        { "C_LootHistory", c.lootHistory },
        { "C_TooltipInfo.GetLootRollItem", c.rollItemAPI },
        { "LoggingChat", c.loggingChat },
        { "Screenshot", type(_G.Screenshot) == "function" },
    }
    local out = {}
    for _, row in ipairs(checks) do
        out[#out + 1] = ("%s %s"):format(row[2] and "OK  " or "MISS", row[1])
    end
    return table.concat(out, "\n")
end
