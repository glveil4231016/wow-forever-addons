-- 极简 WoW API stub，仅用于离线加载/初始化冒烟测试（不是游戏内完整模拟）
local function widget()
    local t = { __shown = false }
    return setmetatable(t, {
        __index = function(self, k)
            if k == "GetFont" then return function() return "Fonts\\FRIZQT__.TTF", 12, "" end end
            if k == "GetText" then return function() return rawget(self, "__text") or "" end end
            if k == "SetText" then return function(s, v) rawset(s, "__text", v) end end
            if k == "IsShown" then return function() return false end end
            if k == "GetHeight" then return function() return 100 end end
            if k == "GetWidth" then return function() return 100 end end
            if k == "GetName" then return function() return "stub" end end
            if k == "GetChecked" then return function() return false end end
            if k == "SetScript" then return function(s, name, fn) rawset(s, name, fn) end end
            if k == "GetScript" then return function(s, name) return rawget(s, name) end end
            if k == "HookScript" then return function() end end
            if k == "RegisterEvent" then return function(s, e) rawset(s, "__events", rawget(s, "__events") or {}); table.insert(rawget(s, "__events"), e) end end
            if k == "UnregisterEvent" then return function() end end
            if k == "CreateTexture" or k == "CreateFontString" then return function() return widget() end end
            if k == "CreateFontString" then return function() return widget() end end
            if k == "SetScrollChild" then return function() end end
            if k == "GetScrollChild" then return function() return widget() end end
            return function(...) return self end
        end,
    })
end

UIParent = widget()
ChatFontNormal = {}
GameFontNormal = {}
GameFontNormalLarge = {}
GameFontNormalSmall = {}
GameFontHighlightSmall = {}
GameFontDisableSmall = {}
SlashCmdList = {}
StaticPopupDialogs = {}
SOUNDKIT = {}
LE_PARTY_CATEGORY_INSTANCE = 1

function CreateFrame(kind, name, parent, template) return widget() end
function GetBuildInfo() return "1.60.1", "70450", "Oct 20 2026", 16001, "zhCN" end
function GetCVar(k) return "jpeg" end
function SetCVar() end

WOW_PROJECT_ID = 1
WOW_PROJECT_MAINLINE = 1

Constants = { CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = " " } }
function RegionalUniqueNamesEnabled() return true end

function UnitName(unit)
    if unit == "player" then return "Asha", "Brightvale" end
    return "Bob", "Nightfall"
end
UnitNameUnmodified = UnitName
function UnitGUID(unit) return "Player-1-0000A1B2" end
function GetRealmName() return "Test" end

C_ChatInfo = {
    SendChatMessage = function() end,
    IsLoggingChat = function() return true end,
    IsLoggingCombat = function() return false end,
    InChatMessagingLockdown = function() return false end,
}
C_LootHistory = {
    GetAllEncounterInfos = function() return {} end,
    GetInfoForEncounter = function() return nil end,
    GetLootHistoryTime = function() return 0 end,
    GetSortedDropsForEncounter = function() return nil end,
    GetSortedInfoForDrop = function() return nil end,
}
C_TooltipInfo = { GetLootRollItem = function() return nil end }
C_Loot = { GetLootRollDuration = function() return 10 end }
Menu = { ModifyMenu = function() end }

function Screenshot() end
function IsInInstance() return false end
function IsInGroup() return false end
function IsInRaid() return false end
function GetNumGroupMembers() return 0 end
function UnitExists() return false end
function UnitIsPlayer() return true end
function UnitIsUnit() return false end
function UnitClass() return "战士", "WARRIOR" end
function UnitGroupRolesAssigned() return "NONE" end
function InCombatLockdown() return false end
function PlaySound() end
function hooksecurefunc() end
function GetTime() return os and os.clock and os.clock() or 0 end
C_Timer = {
    After = function(_, fn) end,
    NewTicker = function() return { Cancel = function() end } end,
}
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function date(fmt, t) return '20261026-170000' end


function time() return os.time() end

