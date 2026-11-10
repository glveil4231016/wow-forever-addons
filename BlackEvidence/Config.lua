-- BlackEvidence / Config.lua
-- 默认配置、版本迁移、范围收敛。写入 BlackEvidenceDB.settings。

local ADDON, BE = ...
BE.Config = BE.Config or {}
local C = BE.Config

local VERSION = 2
local PROFILES = { "retail", "classic", "forever" }

local DEFAULTS = {
    -- 行为
    enabled             = true,
    warnOnPartyJoin     = true,
    sendToPartyChat     = false,     -- 默认只本地提示
    warnChannel         = "auto",
    warnCooldown        = 20,
    warnInLockdownQueue = true,
    localAlert          = true,
    localAlertSeconds   = 8,

    -- 采集
    autoChatLog         = true,
    screenshotOnAdd     = true,
    screenshotOnJoinWarn= false,
    screenshotDelay     = 0.15,
    noteDialogDelay     = 0.45,
    recordScope         = "instance",  -- instance | all
    timelineSeconds     = 180,
    timelineEntries     = 800,
    timelineChars       = 6000,
    snapshotKeep        = 50,
    snapshotTimelineLines = 300,

    -- 日志
    logLevel            = "debug",
    logRingSize         = 1000,
    verboseEvents       = false,
    backupKeep          = 3,
}

C.Defaults = DEFAULTS

local function clampInt(v, lo, hi, fallback)
    v = tonumber(v)
    if not v then return fallback end
    v = math.floor(v)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function clampNum(v, lo, hi, fallback)
    v = tonumber(v)
    if not v then return fallback end
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function ensureProfileTables(db)
    if type(db.profiles) ~= "table" then db.profiles = {} end
    for i = 1, #PROFILES do
        local id = PROFILES[i]
        local p = db.profiles[id]
        if type(p) ~= "table" then p = {}; db.profiles[id] = p end
        if type(p.blacklist) ~= "table" then p.blacklist = {} end
    end
end

-- v1（BlackBook 风格）的扁平 blacklist → 当前 profile
local function migrate(db)
    local from = tonumber(db.version) or 0
    if from >= VERSION then return false end

    if type(db.blacklist) == "table" then
        local id = (BE.Profile and BE.Profile.id) or "retail"
        local target = db.profiles[id]
        for k, v in pairs(db.blacklist) do
            if type(v) == "table" and type(v.key) == "string" and target.blacklist[k] == nil then
                target.blacklist[k] = v
            end
        end
        db.blacklist = nil
    end

    -- 老配置直接复用（键名兼容）
    if type(db.config) == "table" then
        if type(db.settings) ~= "table" then db.settings = {} end
        for k, v in pairs(db.config) do
            if db.settings[k] == nil then db.settings[k] = v end
        end
        db.config = nil
    end

    db.version = VERSION
    return true
end

function C:Validate()
    local db = _G.BlackEvidenceDB
    local s = db and db.settings
    if type(s) ~= "table" then return end

    s.enabled = s.enabled and true or false
    s.warnOnPartyJoin = s.warnOnPartyJoin and true or false
    s.sendToPartyChat = s.sendToPartyChat and true or false
    s.localAlert = s.localAlert and true or false
    s.autoChatLog = s.autoChatLog and true or false
    s.screenshotOnAdd = s.screenshotOnAdd and true or false
    s.screenshotOnJoinWarn = s.screenshotOnJoinWarn and true or false
    s.verboseEvents = s.verboseEvents and true or false
    s.warnInLockdownQueue = s.warnInLockdownQueue and true or false

    s.warnCooldown        = clampInt(s.warnCooldown, 5, 600, 20)
    s.localAlertSeconds   = clampInt(s.localAlertSeconds, 2, 30, 8)
    s.screenshotDelay     = clampNum(s.screenshotDelay, 0, 3, 0.15)
    s.noteDialogDelay     = clampNum(s.noteDialogDelay, 0, 3, 0.45)
    s.timelineSeconds     = clampInt(s.timelineSeconds, 60, 600, 180)
    s.timelineEntries     = clampInt(s.timelineEntries, 100, 1000, 800)
    s.timelineChars       = clampInt(s.timelineChars, 1000, 20000, 6000)
    s.snapshotKeep        = clampInt(s.snapshotKeep, 5, 50, 50)
    s.snapshotTimelineLines = clampInt(s.snapshotTimelineLines, 50, 300, 300)
    s.logRingSize         = clampInt(s.logRingSize, 100, 2000, 1000)
    s.backupKeep          = clampInt(s.backupKeep, 1, 5, 3)

    if s.recordScope ~= "all" then s.recordScope = "instance" end
    if s.warnChannel ~= "auto" and s.warnChannel ~= "PARTY"
        and s.warnChannel ~= "RAID" and s.warnChannel ~= "INSTANCE_CHAT" then
        s.warnChannel = "auto"
    end
    local lv = type(s.logLevel) == "string" and s.logLevel:lower() or "debug"
    if lv ~= "trace" and lv ~= "debug" and lv ~= "info"
        and lv ~= "warn" and lv ~= "error" and lv ~= "off" then
        lv = "debug"
    end
    s.logLevel = lv
end

function C:Load()
    local db = _G.BlackEvidenceDB
    if type(db) ~= "table" then
        db = {}
        _G.BlackEvidenceDB = db
    end

    ensureProfileTables(db)

    local migrated = migrate(db)

    if type(db.settings) ~= "table" then db.settings = {} end
    local s = db.settings
    for k, v in pairs(DEFAULTS) do
        if s[k] == nil then s[k] = v end
    end

    self:Validate()
    db.activeProfile = (BE.Profile and BE.Profile.id) or db.activeProfile or "retail"

    if migrated and BE.Log then
        BE.Log.Info("Config", "配置已迁移到 v%d（当前 profile=%s）", VERSION, tostring(db.activeProfile))
    end
    return db
end

function C:Get(key)
    local db = _G.BlackEvidenceDB
    local s = db and db.settings
    if type(s) == "table" and s[key] ~= nil then return s[key] end
    return DEFAULTS[key]
end

function C:Set(key, value)
    local db = _G.BlackEvidenceDB
    if type(db) ~= "table" then return false end
    if type(db.settings) ~= "table" then db.settings = {} end
    db.settings[key] = value
    self:Validate()
    return true
end

function C:Reset()
    local db = _G.BlackEvidenceDB
    if type(db) ~= "table" then return end
    db.settings = {}
    for k, v in pairs(DEFAULTS) do db.settings[k] = v end
end
