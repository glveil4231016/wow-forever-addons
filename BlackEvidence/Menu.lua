-- BlackEvidence / Menu.lua
-- 把「加入黑名单」放进单位右键菜单。双路径，按 Profile 能力门控：
--   modern：Menu.ModifyMenu（retail / forever）
--   legacy：UnitPopupMenus + UnitPopup_OnClick（仅 Classic Era，永不进 modern 客户端）
-- 注入成功与否以「handler 实际被执行过」为准，不拿 pcall 结果当成功。

local ADDON, BE = ...
BE.Menu = BE.Menu or {}
local M = BE.Menu

local MENU_LABEL   = "加入黑名单"
local MENU_TAG     = "BLACKEVIDENCE_ADD"
local LEGACY_VALUE = "BLACKEVIDENCE_ADD"

-- 只处理玩家相关菜单，避免误加 NPC / 自己
local MODERN_IDS = {
    "MENU_UNIT_PLAYER",
    "MENU_UNIT_TARGET",
    "MENU_UNIT_PARTY",
    "MENU_UNIT_RAID_PLAYER",
}

local LEGACY_KEYS = { "PLAYER", "PARTY", "RAID_PLAYER", "RAID", "TARGET" }

M.Stats = {
    mode       = "none",     -- modern | legacy | none
    injected   = false,      -- 以观测到的实际执行/插入为准
    expanded   = 0,          -- 菜单被展开并执行到本模块的次数
    clicked    = 0,          -- 用户点击「加入黑名单」的次数
    lastTarget = nil,
    lastAt     = nil,
    -- 诊断细节
    registered = {},         -- modern: menuId -> 注册是否成功
    perMenu    = {},         -- menuId / which -> 展开次数
    skipped    = {},         -- modern: menuId -> 最近一次跳过原因
    buildErrors = 0,
    hookShowMenu = false,
    hookOnClick  = false,
    lastMenuId   = nil,
    legacyMenus  = 0,         -- legacy: 实际写入的菜单个数
}

local started = false
local verifyScheduled = false

-- legacy：ShowMenu 时缓存"这次右键的是谁"，点击时菜单可能已关闭
local legacyUnit, legacyName, legacyWhich = nil, nil, nil
local lastFireKey, lastFireAt = nil, nil

----------------------------------------------------------------------
-- 小工具
----------------------------------------------------------------------

local function logDebug(fmt, ...)
    if BE.Log then BE.Log.Debug("Menu", fmt, ...) end
end

local function logInfo(fmt, ...)
    if BE.Log then BE.Log.Info("Menu", fmt, ...) end
end

local function logWarn(fmt, ...)
    if BE.Log then BE.Log.Warn("Menu", fmt, ...) end
end

local function logError(fmt, ...)
    if BE.Log then BE.Log.Error("Menu", fmt, ...) end
end

local function cap(name)
    if BE.Profile and type(BE.Profile.Cap) == "function" then
        local ok, v = pcall(BE.Profile.Cap, name)
        if ok then return v end
    end
    return nil
end

local function setting(key)
    if BE.Config and type(BE.Config.Get) == "function" then
        local ok, v = pcall(BE.Config.Get, BE.Config, key)
        if ok then return v end
    end
    return nil
end

local function wallTime()
    if type(time) == "function" then
        local ok, v = pcall(time)
        if ok then return tonumber(v) or 0 end
    end
    return 0
end

local function unitExists(unit)
    if type(unit) ~= "string" or unit == "" then return false end
    if type(UnitExists) ~= "function" then return true end
    local ok, v = pcall(UnitExists, unit)
    return ok and v and true or false
end

local function unitIsSelf(unit)
    if type(unit) ~= "string" or unit == "" then return false end
    if type(UnitIsUnit) == "function" then
        local ok, v = pcall(UnitIsUnit, unit, "player")
        if ok and v then return true end
    end
    return unit == "player"
end

-- 三态：true / false / nil（读不到）
local function unitIsPlayer(unit)
    if type(unit) ~= "string" or unit == "" then return nil end
    if type(UnitIsPlayer) ~= "function" then return nil end
    local ok, v = pcall(UnitIsPlayer, unit)
    if not ok then return nil end
    return v and true or false
end

local function modeText(mode)
    if mode == "modern" then return "现代 Menu.ModifyMenu" end
    if mode == "legacy" then return "经典 UnitPopupMenus" end
    return "未启用"
end

----------------------------------------------------------------------
-- 统一取身份
----------------------------------------------------------------------

-- 返回 info, 来源。contextData 优先 unit，其次 name/surname。
function M.ResolveUnit(menuId, contextData)
    local ctx = type(contextData) == "table" and contextData or {}
    local unit = ctx.unit or ctx.unitToken

    if type(unit) == "string" and unit ~= "" and unitExists(unit) then
        local ok, info = pcall(BE.Identity.Unit, unit)
        if ok and type(info) == "table" and info.key then
            return info, "unit:" .. unit
        end
        logDebug("[%s] %s 身份读取失败，改用菜单字段", tostring(menuId), tostring(unit))
    end

    -- 退路：菜单只给了显示名（经典客户端常见）
    local name = ctx.name
    if type(name) == "string" and name ~= "" then
        local surname = type(ctx.surname) == "string" and ctx.surname or nil
        local realm = type(ctx.realm) == "string" and ctx.realm or nil
        local guid = type(ctx.guid) == "string" and ctx.guid or nil

        local second = cap("surname") and surname or realm
        local key = BE.Identity.KeyFromParts(name, second)
        if key then
            local e = {
                name  = name,
                key   = key,
                guid  = guid,
                unit  = unit,
            }
            if cap("surname") then e.surname = surname else e.realm = realm end
            e.full = BE.Identity.Display(e)
            return e, "context"
        end

        -- forever：surname 可能缺失，name 里可能已含全名
        local e2 = BE.Identity.FromChat(name, guid)
        if e2 then
            e2.unit = unit
            return e2, "context:full"
        end
    end

    return nil, "none"
end

----------------------------------------------------------------------
-- 打开备注框
----------------------------------------------------------------------

function M.OpenTarget(info)
    if type(info) ~= "table" or type(info.key) ~= "string" or info.key == "" then
        return false
    end

    local st = M.Stats
    st.clicked = st.clicked + 1
    st.lastTarget = info.full or info.name or info.key
    st.lastAt = wallTime()

    local ui = BE.UI
    if type(ui) ~= "table" or type(ui.OpenNote) ~= "function" then
        logWarn("BE.UI 尚未加载，无法打开备注框：%s", tostring(info.full or info.name))
        return false
    end

    local existing = BE.Blacklist.Find(info)
    local mode = existing and "edit" or "add"

    local ok, err = pcall(ui.OpenNote, info, { mode = mode })
    if not ok then
        logError("打开备注框失败（%s）：%s", mode, tostring(err))
        return false
    end

    logInfo("%s：%s", mode == "edit" and "编辑备注" or "加入黑名单",
        tostring(info.full or info.name))
    return true
end

----------------------------------------------------------------------
-- modern：Menu.ModifyMenu
----------------------------------------------------------------------

local function scheduleVerify()
    if verifyScheduled then return end
    verifyScheduled = true
    if type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then return end

    pcall(C_Timer.After, 60, function()
        local st = M.Stats
        if st.expanded == 0 then
            logWarn("右键菜单已注册，但 60 秒内未观测到展开；无法确认是否真正生效（可在菜单打开后执行 /be menu）")
        else
            logInfo("右键菜单已确认生效：展开 %d 次，点击 %d 次", st.expanded, st.clicked)
        end
    end)
end

local function buildModernEntry(menuId, owner, rootDescription, contextData)
    local st = M.Stats

    -- 只要 handler 被执行过，就说明注入这条路通了
    st.expanded = st.expanded + 1
    st.injected = true
    st.perMenu[menuId] = (st.perMenu[menuId] or 0) + 1

    if type(rootDescription) ~= "table" then
        st.skipped[menuId] = "rootDescription 无效"
        logWarn("[%s] rootDescription 无效，跳过", tostring(menuId))
        return
    end

    if setting("enabled") == false then
        st.skipped[menuId] = "插件总开关关闭"
        return
    end

    local ctx = type(contextData) == "table" and contextData or {}
    local unit = ctx.unit or ctx.unitToken
    if not unit and type(owner) == "table" then
        unit = owner.unit or owner.unitToken or owner.displayedUnit
    end

    if type(unit) == "string" and unit ~= "" then
        if unitIsSelf(unit) then
            st.skipped[menuId] = "目标是自己"
            return
        end
        if unitIsPlayer(unit) == false then
            st.skipped[menuId] = "目标不是玩家"
            logDebug("[%s] %s 不是玩家，跳过", tostring(menuId), tostring(unit))
            return
        end
    end

    -- 归一化给 ResolveUnit：unit 可能来自 owner.unit
    local lookup = {
        unit    = unit,
        name    = ctx.name,
        surname = ctx.surname,
        realm   = ctx.realm,
        guid    = ctx.guid,
    }
    local info = M.ResolveUnit(menuId, lookup)
    if not info then
        st.skipped[menuId] = "读不到身份"
        logWarn("[%s] 读不到目标身份，菜单项不显示", tostring(menuId))
        return
    end

    st.skipped[menuId] = nil
    st.lastTarget = info.full or info.name
    st.lastAt = wallTime()
    st.lastMenuId = menuId

    local click = function()
        M.OpenTarget(info)
    end

    if type(rootDescription.CreateButton) ~= "function" then
        st.skipped[menuId] = "菜单没有 CreateButton"
        logWarn("[%s] 菜单缺少 CreateButton", tostring(menuId))
        return
    end

    local ok, btn = pcall(rootDescription.CreateButton, rootDescription, MENU_LABEL)
    if not ok or type(btn) ~= "table" then
        st.buildErrors = st.buildErrors + 1
        logError("[%s] CreateButton 失败：%s", tostring(menuId), tostring(btn))
        return
    end

    -- 当前 API：SetTag + SetOnClick；旧版退到 SetOnClickHandler
    if type(btn.SetTag) == "function" then
        pcall(btn.SetTag, btn, MENU_TAG)
    end

    local attached = false
    if type(btn.SetOnClick) == "function" then
        local okc, err = pcall(btn.SetOnClick, btn, click)
        attached = okc and true or false
        if not okc then logWarn("[%s] SetOnClick 失败：%s", tostring(menuId), tostring(err)) end
    elseif type(btn.SetOnClickHandler) == "function" then
        local okc, err = pcall(btn.SetOnClickHandler, btn, click)
        attached = okc and true or false
        if not okc then logWarn("[%s] SetOnClickHandler 失败：%s", tostring(menuId), tostring(err)) end
    else
        -- 两者都没有时挂到 onClick 字段，至少不报错
        local okf, errf = pcall(function() btn.onClick = click end)
        attached = okf and true or false
        if not okf then logWarn("[%s] 无法绑定点击回调：%s", tostring(menuId), tostring(errf)) end
    end

    if not attached then
        logWarn("[%s] 菜单项已创建但未能绑定点击回调", tostring(menuId))
    end
end

local function initModern()
    local api = _G.Menu
    if type(api) ~= "table" or type(api.ModifyMenu) ~= "function" then
        logError("Menu.ModifyMenu 不可用，无法注入右键菜单")
        return false
    end

    M.Stats.mode = "modern"

    local okCount = 0
    for i = 1, #MODERN_IDS do
        local menuId = MODERN_IDS[i]
        local handler = function(owner, rootDescription, contextData)
            local ok, err = pcall(buildModernEntry, menuId, owner, rootDescription, contextData)
            if not ok then
                M.Stats.buildErrors = M.Stats.buildErrors + 1
                logError("[%s] 构建菜单项出错：%s", tostring(menuId), tostring(err))
            end
        end

        local ok, err = pcall(api.ModifyMenu, menuId, handler)
        M.Stats.registered[menuId] = ok and true or false
        if ok then
            okCount = okCount + 1
            logDebug("已注册菜单：%s", menuId)
        else
            logWarn("注册菜单失败：%s（%s）", tostring(menuId), tostring(err))
        end
    end

    logInfo("右键菜单注入：成功注册 %d / %d（是否真正生效以展开次数为准）",
        okCount, #MODERN_IDS)
    if okCount == 0 then
        logError("没有任何菜单注册成功，右键菜单里不会出现「%s」", MENU_LABEL)
    end

    scheduleVerify()
    return okCount > 0
end

----------------------------------------------------------------------
-- legacy：UnitPopupMenus（仅 Classic Era）
----------------------------------------------------------------------

local function legacyInfo(unit, name)
    if type(unit) == "string" and unit ~= "" and unitExists(unit) then
        local ok, info = pcall(BE.Identity.Unit, unit)
        if ok and type(info) == "table" and info.key then
            return info, "unit:" .. unit
        end
        logWarn("经典右键：读取 %s 身份失败，改用菜单里的名字", tostring(unit))
    end

    if type(name) == "string" and name ~= "" then
        local e = BE.Identity.FromChat(name)
        if e then
            e.unit = unit
            return e, "name:" .. name
        end
    end

    return nil, "none"
end

local function legacyHandle(via)
    local unit, name = legacyUnit, legacyName

    -- 缓存缺失时退回打开中的菜单对象
    if type(unit) ~= "string" or unit == "" then
        local f = _G.UIDROPDOWNMENU_OPEN_MENU
        if type(f) == "table" then
            if type(f.unit) == "string" then unit = f.unit end
            if name == nil then name = f.name end
        end
    end

    if type(unit) == "string" and unit ~= "" and unitIsSelf(unit) then
        logInfo("经典右键：目标是自己，忽略（which=%s）", tostring(legacyWhich))
        return "self"
    end

    -- 注意：必须显式比较 false。UnitIsPlayer 返回 false 时用 and/or 会被误当成 nil
    if type(unit) == "string" and unit ~= "" and unitIsPlayer(unit) == false then
        logWarn("经典右键：%s 不是玩家，忽略", tostring(unit))
        return "notplayer"
    end

    local info, src = legacyInfo(unit, name)
    if not info then
        logError("经典右键：拿不到目标身份（unit=%s name=%s）",
            tostring(unit), tostring(name))
        if BE.Log then BE.Log.Info("Menu", "可用命令添加：/be add <名字> <备注>") end
        return "noinfo"
    end

    -- 同目标 1.5 秒内只处理一次（防双击）
    local now = BE.Util.Now()
    if lastFireKey == info.key and lastFireAt and (now - lastFireAt) < 1.5 then
        logInfo("经典右键：重复点击 %s，忽略", tostring(info.full or info.name))
        return "dup"
    end
    lastFireKey, lastFireAt = info.key, now

    logInfo("经典右键：%s（来源=%s，触发=%s）",
        tostring(info.full or info.name), tostring(src), tostring(via))
    M.OpenTarget(info)
    return "ok"
end

local function legacyButtonFunc()
    local ok, err = pcall(legacyHandle, "button.func")
    if not ok then logError("经典右键处理出错（func）：%s", tostring(err)) end
    return false
end

local function onShowMenu(dropdownFrame, which, unit, name)
    legacyUnit, legacyName, legacyWhich = unit, name, which

    local ours = false
    for i = 1, #LEGACY_KEYS do
        if LEGACY_KEYS[i] == which then ours = true break end
    end
    if not ours then return end

    -- ShowMenu 钩子被调用 = 菜单确实展开过，作为 legacy 的注入观测依据
    local st = M.Stats
    st.expanded = st.expanded + 1
    st.injected = true
    st.perMenu[which] = (st.perMenu[which] or 0) + 1
    st.lastMenuId = which

    local info = legacyInfo(unit, name)
    if info then
        st.lastTarget = info.full or info.name
        st.lastAt = wallTime()
    end
end

local function onUnitPopupOnClick(self)
    if type(self) ~= "table" then return end
    if self.value ~= LEGACY_VALUE then return end
    local ok, err = pcall(legacyHandle, "UnitPopup_OnClick")
    if not ok then logError("经典右键处理出错（OnClick）：%s", tostring(err)) end
end

local function installLegacy()
    local btns = _G.UnitPopupButtons
    local menus = _G.UnitPopupMenus
    if type(btns) ~= "table" or type(menus) ~= "table" then
        logError("缺少 UnitPopupButtons / UnitPopupMenus，经典右键不可用")
        return false
    end

    local def = btns[LEGACY_VALUE]
    if type(def) ~= "table" then
        def = {}
        btns[LEGACY_VALUE] = def
    end
    def.text = MENU_LABEL
    def.dist = tonumber(def.dist) or 0
    def.func = legacyButtonFunc

    local inserted = 0
    for i = 1, #LEGACY_KEYS do
        local key = LEGACY_KEYS[i]
        if type(menus[key]) ~= "table" then
            menus[key] = {}
            logWarn("UnitPopupMenus[%s] 不存在，已新建（可能不生效）", tostring(key))
        end
        local list = menus[key]

        local found = false
        for j = 1, #list do
            if list[j] == LEGACY_VALUE then found = true break end
        end
        if not found then
            table.insert(list, 1, LEGACY_VALUE)
        end
        inserted = inserted + 1
        logDebug("UnitPopupMenus[%s] 已就位", tostring(key))
    end

    -- ShowMenu：记住这次右键的是谁
    if type(_G.UnitPopup_ShowMenu) == "function" and type(hooksecurefunc) == "function" then
        local okh, errh = pcall(hooksecurefunc, "UnitPopup_ShowMenu", onShowMenu)
        M.Stats.hookShowMenu = okh and true or false
        if not okh then logWarn("hook UnitPopup_ShowMenu 失败：%s", tostring(errh)) end
    else
        M.Stats.hookShowMenu = false
        logWarn("没有 UnitPopup_ShowMenu，点击时只能靠 UIDROPDOWNMENU_OPEN_MENU 取目标")
    end

    -- OnClick：func 被覆盖时的兜底
    if type(_G.UnitPopup_OnClick) == "function" and type(hooksecurefunc) == "function" then
        local okc, errc = pcall(hooksecurefunc, "UnitPopup_OnClick", onUnitPopupOnClick)
        M.Stats.hookOnClick = okc and true or false
        if not okc then logWarn("hook UnitPopup_OnClick 失败：%s", tostring(errc)) end
    else
        M.Stats.hookOnClick = false
        logWarn("没有 UnitPopup_OnClick，菜单项只能靠 func 生效")
    end

    logInfo("经典右键已就位：%d 个菜单（%s）", inserted, table.concat(LEGACY_KEYS, ", "))
    M.Stats.legacyMenus = inserted
    return inserted > 0
end

local function initLegacy()
    M.Stats.mode = "legacy"
    local ok, result = pcall(installLegacy)
    if not ok then
        logError("经典右键初始化失败：%s", tostring(result))
        return false
    end
    -- legacy 无法只看注册结果，等 ShowMenu 被调用后才把 injected 置真
    M.Stats.injected = false
    return result and true or false
end

----------------------------------------------------------------------
-- 初始化
----------------------------------------------------------------------

local function start()
    if not BE.Identity or not BE.Blacklist then
        logError("Identity / Blacklist 未就绪，跳过右键菜单")
        return false
    end

    if not BE.Profile or type(BE.Profile.caps) ~= "table" then
        logError("Profile 尚未探测，跳过右键菜单")
        return false
    end

    -- 按能力分叉：modern 客户端永不进 legacy 分支
    if cap("modernMenu") then
        return initModern()
    end
    return initLegacy()
end

function M.Init()
    if started then return true end
    started = true

    logInfo("客户端菜单能力：modernMenu=%s｜UnitPopupMenus=%s",
        tostring(cap("modernMenu")),
        type(_G.UnitPopupMenus))

    local ok, result = pcall(start)
    if not ok then
        logError("右键菜单初始化失败（不影响插件其它功能）：%s", tostring(result))
        return false
    end
    return result and true or false
end

----------------------------------------------------------------------
-- 诊断
----------------------------------------------------------------------

-- 多行字符串，供 /be menu 直接打印
function M.LiveReport()
    local st = M.Stats
    local out = {}
    local function add(fmt, ...)
        out[#out + 1] = string.format(fmt, ...)
    end

    add("右键菜单路径：%s（mode=%s）", modeText(st.mode), tostring(st.mode))

    if st.mode == "modern" then
        local registered = 0
        for i = 1, #MODERN_IDS do
            if st.registered[MODERN_IDS[i]] then registered = registered + 1 end
        end
        add("注册：%d / %d 个菜单 ID", registered, #MODERN_IDS)
        add("生效：%s（以实际展开为准）", st.injected and "已观测到" or "尚未观测到")
        for i = 1, #MODERN_IDS do
            local id = MODERN_IDS[i]
            local n = st.perMenu[id] or 0
            local state
            if not st.registered[id] then
                state = "注册失败"
            elseif n == 0 then
                state = "已注册，还未展开"
            elseif st.skipped[id] then
                state = ("展开 %d 次，最近一次跳过：%s"):format(n, st.skipped[id])
            else
                state = ("展开 %d 次"):format(n)
            end
            add("  %s：%s", id, state)
        end
    elseif st.mode == "legacy" then
        add("UnitPopupMenus：已写入 %d 个菜单；观测到展开=%s",
            st.legacyMenus or 0, st.injected and "是" or "否")
        add("hook：ShowMenu=%s｜OnClick=%s",
            tostring(st.hookShowMenu), tostring(st.hookOnClick))
        for i = 1, #LEGACY_KEYS do
            local key = LEGACY_KEYS[i]
            add("  %s：展开 %d 次", key, st.perMenu[key] or 0)
        end
    else
        add("未启用：这个客户端没有可用的菜单接口")
    end

    add("展开次数：%d", st.expanded)
    add("点击次数：%d", st.clicked)
    add("最近目标：%s", st.lastTarget or "（无）")
    add("最近时间：%s", st.lastAt and tostring(st.lastAt) or "（无）")

    if st.buildErrors > 0 then
        add("构建出错：%d 次", st.buildErrors)
    end

    return table.concat(out, "\n")
end
