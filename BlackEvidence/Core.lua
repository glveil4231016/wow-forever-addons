-- BlackEvidence / Core.lua
-- 初始化顺序、事件总线、DB 备份。各模块 Init 独立 pcall，互不影响。

local ADDON, BE = ...
BE.addonName = ADDON
BE.state = BE.state or {
    started = false,
    warned = {},          -- 本次组队会话内已预警的 key
    ignoreSession = {},   -- 本场豁免的 key
}
BE.modules = BE.modules or {}

local listeners = {}      -- event -> { fn, ... }
local registered = {}     -- event -> true
local frame

local function log(...)
    if BE.Log then BE.Log.Info("Core", ...) end
end

local function logErr(...)
    if BE.Log then BE.Log.Error("Core", ...) end
end

----------------------------------------------------------------------
-- 事件总线
----------------------------------------------------------------------

function BE:On(event, fn)
    if type(event) ~= "string" or type(fn) ~= "function" then return false end
    local list = listeners[event]
    if not list then list = {}; listeners[event] = list end
    for i = 1, #list do
        if list[i] == fn then return true end
    end
    list[#list + 1] = fn
    return true
end

function BE:RegisterEvent(event)
    if type(event) ~= "string" then return false end
    if registered[event] then return true end
    if not frame then return false end
    local ok = pcall(frame.RegisterEvent, frame, event)
    if ok then registered[event] = true end
    return ok
end

function BE:Fire(event, ...)
    local list = listeners[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then logErr("监听器出错 %s: %s", tostring(event), tostring(err)) end
    end
end

function BE:Debug(...)
    if BE.Log then BE.Log.Debug("Core", ...) end
end

----------------------------------------------------------------------
-- DB 备份（放在 SavedVariables 里，纯文本，便于抢救）
----------------------------------------------------------------------

local BACKUP_LIMIT = 200 * 1024

local function serializeStore(store)
    local lines = {}
    for _, e in pairs(store) do
        if type(e) == "table" and type(e.key) == "string" then
            local note = tostring(e.note or ""):gsub("\\", "\\\\"):gsub("\n", "\\n"):gsub("\t", "\\t")
            lines[#lines + 1] = table.concat({
                e.key, tostring(e.name or ""), tostring(e.surname or ""),
                tostring(e.realm or ""), note, tostring(e.guid or ""),
                tostring(tonumber(e.hits) or 0), tostring(tonumber(e.createdAt) or 0),
            }, "\t")
        end
    end
    return table.concat(lines, "\n")
end

local function backupDB()
    local db = _G.BlackEvidenceDB
    if type(db) ~= "table" then return end

    local pid = (BE.Profile and BE.Profile.id) or "retail"
    local profiles = db.profiles
    local store = profiles and profiles[pid] and profiles[pid].blacklist
    if type(store) ~= "table" then return end

    local text = serializeStore(store)
    if text == "" then return end
    if #text > BACKUP_LIMIT then
        text = BE.Util.Truncate(text, BACKUP_LIMIT)
    end

    if type(db.backups) ~= "table" then db.backups = {} end
    local list = db.backups
    list[#list + 1] = { at = time(), profile = pid, text = text }

    local keep = (BE.Config and BE.Config:Get("backupKeep")) or 3
    while #list > keep do table.remove(list, 1) end
end

----------------------------------------------------------------------
-- 初始化
----------------------------------------------------------------------

local INIT_ORDER = {
    "Blacklist", "Timeline", "Trigger", "Comms",
    "Menu", "NoteDialog", "ManagerUI", "Export", "Slash",
}

local function initModules()
    for i = 1, #INIT_ORDER do
        local name = INIT_ORDER[i]
        local mod = BE[name]
        if type(mod) == "table" and type(mod.Init) == "function" then
            local ok, err = pcall(mod.Init, mod)
            if not ok then
                logErr("模块 %s 初始化失败：%s", name, tostring(err))
            else
                BE.Log.Debug("Core", "模块 %s 已初始化", name)
            end
        elseif mod == nil then
            BE.Log.Warn("Core", "模块 %s 未加载", name)
        end
    end
end

local function onAddonLoaded(name)
    if name ~= ADDON then return end

    if BE.Profile then BE.Profile.Detect() end

    -- 先备份上一份存档，再做迁移
    local okBackup, errBackup = pcall(backupDB)
    if not okBackup then
        -- 此时 Logger 可能还没绑定，用 pcall 保护
        pcall(function() BE.Log.Warn("Core", "DB 备份失败：%s", tostring(errBackup)) end)
    end

    if BE.Config then
        local ok, err = pcall(BE.Config.Load, BE.Config)
        if not ok then
            _G.BlackEvidenceDB = _G.BlackEvidenceDB or {}
            _G.BlackEvidenceDB.settings = _G.BlackEvidenceDB.settings or {}
            pcall(function() BE.Log.Error("Core", "配置加载失败，已用默认值：%s", tostring(err)) end)
        end
    end

    if BE.Log then
        pcall(BE.Log.InstallErrorHandler)
        BE.Log.Info("Core", "BlackEvidence %s 启动 | %s",
            "0.1.0", BE.Profile and BE.Profile.StatusLine() or "unknown")
        if BE.Profile then
            for line in (BE.Profile.ApiReport() or ""):gmatch("[^\n]+") do
                BE.Log.Debug("Profile", "%s", line)
            end
        end
    end

    BE:RegisterEvent("PLAYER_LOGIN")
    BE:RegisterEvent("PLAYER_ENTERING_WORLD")
end

local function onPlayerLogin()
    if BE.state.started then return end
    BE.state.started = true

    if BE.Log then
        BE.Log.Info("Core", "进入游戏：%s（会话 %s）",
            BE.Util.ClientFlavorLabel(), tostring(BE.Log.Session or 0))
    end
    initModules()
end

local function onEnteringWorld()
    if BE.Log then
        BE.Log.Debug("Core", "PLAYER_ENTERING_WORLD | inInstance=%s inGroup=%s",
            tostring(IsInInstance and select(1, IsInInstance()) or false),
            tostring(IsInGroup and IsInGroup() or false))
    end
end

----------------------------------------------------------------------
-- 启动
----------------------------------------------------------------------

frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        onAddonLoaded(...)
    elseif event == "PLAYER_LOGIN" then
        onPlayerLogin()
    elseif event == "PLAYER_ENTERING_WORLD" then
        onEnteringWorld()
        BE:Fire("PLAYER_ENTERING_WORLD", ...)
    else
        BE:Fire(event, ...)
    end
end)

frame:RegisterEvent("ADDON_LOADED")

-- 暴露给测试/诊断
function BE:InitManual()
    onAddonLoaded(ADDON)
    onPlayerLogin()
end

