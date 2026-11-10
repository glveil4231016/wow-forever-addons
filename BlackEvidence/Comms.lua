-- BlackEvidence / Comms.lua
-- 进队预警：黑名单玩家进入队伍时弹本地大字提示，可选在队伍频道播报。
-- 频道发言在 12.x 受聊天封锁限制，统一走「发送 -> 失败/封锁则入队 -> 解锁补发」。

local ADDON, BE = ...
BE.Comms = BE.Comms or {}
local M = BE.Comms

local SCAN_DEBOUNCE = 0.4
local QUEUE_MAX     = 20

local knownMembers = {}   -- 上一次扫描时在队伍里的 key（用于识别"新加入"）
local lastWarnAt   = {}   -- key -> GetTime，冷却
local queue        = {}   -- { key, text, channel, at }

local scanPending  = false
local scanSeedOnly = false
local scanReason   = nil
local seededOnce   = false

local started      = false
local alertFrame   = nil
local alertToken   = 0

----------------------------------------------------------------------
-- 小工具
----------------------------------------------------------------------

local function logDebug(fmt, ...)
    if BE.Log then BE.Log.Debug("Comms", fmt, ...) end
end

local function logInfo(fmt, ...)
    if BE.Log then BE.Log.Info("Comms", fmt, ...) end
end

local function logWarn(fmt, ...)
    if BE.Log then BE.Log.Warn("Comms", fmt, ...) end
end

local function logError(fmt, ...)
    if BE.Log then BE.Log.Error("Comms", fmt, ...) end
end

local function setting(key)
    if BE.Config and type(BE.Config.Get) == "function" then
        local ok, v = pcall(BE.Config.Get, BE.Config, key)
        if ok then return v end
    end
    return nil
end

local function cap(name)
    if BE.Profile and type(BE.Profile.Cap) == "function" then
        local ok, v = pcall(BE.Profile.Cap, name)
        if ok then return v end
    end
    return nil
end

-- 保证 state 的两个去重表可用（Core 已建，这里只兜底）
local function state()
    BE.state = BE.state or {}
    local s = BE.state
    if type(s.warned) ~= "table" then s.warned = {} end
    if type(s.ignoreSession) ~= "table" then s.ignoreSession = {} end
    return s
end

local function count(t)
    local n = 0
    if type(t) == "table" then
        for _ in pairs(t) do n = n + 1 end
    end
    return n
end

local function wallTime()
    if type(time) == "function" then
        local ok, v = pcall(time)
        if ok then return tonumber(v) or 0 end
    end
    return 0
end

local function inRaid()
    if type(IsInRaid) ~= "function" then return false end
    local ok, v = pcall(IsInRaid)
    return ok and v and true or false
end

local function inGroup()
    if type(IsInGroup) ~= "function" then return false end
    local ok, v = pcall(IsInGroup)
    return ok and v and true or false
end

local function clearWarned()
    local s = state()
    for k in pairs(s.warned) do s.warned[k] = nil end
end

local function sendMode()
    return cap("sendChat") or "none"
end

-- 只在 caps.lockdown 为真时查询，避免在不存在的接口上做无谓 pcall
local function inLockdown()
    if not cap("lockdown") then return false end
    local info = _G.C_ChatInfo
    if type(info) ~= "table" or type(info.InChatMessagingLockdown) ~= "function" then
        return false
    end
    local ok, v = pcall(info.InChatMessagingLockdown)
    return ok and v and true or false
end

----------------------------------------------------------------------
-- 本地大字提示（不受聊天封锁 / 战斗限制）
----------------------------------------------------------------------

local function playAlertSound()
    if type(PlaySound) ~= "function" then return end
    local id = 8959
    local sk = _G.SOUNDKIT
    if type(sk) == "table" and tonumber(sk.RAID_WARNING) then
        id = tonumber(sk.RAID_WARNING)
    end
    pcall(PlaySound, id, "Master")
end

local function buildAlertFrame()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetSize(720, 110)
    f:SetPoint("TOP", UIParent, "TOP", 0, -170)
    f:EnableMouse(false)
    f:Hide()

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    if type(bg.SetColorTexture) == "function" then
        bg:SetColorTexture(0.55, 0.03, 0.03, 0.86)
    else
        bg:SetTexture(0.55, 0.03, 0.03, 0.86)
    end

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOP", f, "TOP", 0, -12)
    title:SetText("黑名单玩家进入队伍")
    title:SetTextColor(1, 0.28, 0.28)

    local body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    body:SetPoint("TOP", title, "BOTTOM", 0, -10)
    body:SetPoint("LEFT", f, "LEFT", 18, 0)
    body:SetPoint("RIGHT", f, "RIGHT", -18, 0)
    body:SetJustifyH("CENTER")
    body:SetTextColor(1, 0.86, 0.42)

    f.title, f.body = title, body
    return f
end

local function ensureAlertFrame()
    if alertFrame then return alertFrame end
    if type(CreateFrame) ~= "function" or type(UIParent) ~= "table" then return nil end
    local ok, f = pcall(buildAlertFrame)
    if not ok or type(f) ~= "table" then
        logWarn("本地大字提示框创建失败：%s", tostring(f))
        return nil
    end
    alertFrame = f
    return f
end

local function showAlert(text, seconds)
    if setting("localAlert") == false then return end

    local f = ensureAlertFrame()
    if not f then
        logWarn("本地提示不可用，仅记录：%s", tostring(text))
        return
    end

    alertToken = alertToken + 1
    local token = alertToken

    pcall(f.body.SetText, f.body, text)
    pcall(f.Show, f)
    playAlertSound()

    if type(UIErrorsFrame) == "table" and type(UIErrorsFrame.AddMessage) == "function" then
        local clean = BE.Util.Truncate(BE.Util.StripColors(text), 150)
        pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, clean, 1, 0.25, 0.25, 1)
    end

    local sec = tonumber(seconds) or tonumber(setting("localAlertSeconds")) or 8
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        pcall(C_Timer.After, sec, function()
            if alertToken == token and alertFrame then
                pcall(alertFrame.Hide, alertFrame)
            end
        end)
    end

    logInfo("本地提示：%s", BE.Util.Truncate(text, 120))
end

----------------------------------------------------------------------
-- 频道 / 发送 / 排队
----------------------------------------------------------------------

function M.Channel()
    local pref = setting("warnChannel")
    if type(pref) == "string" and pref ~= "" and pref ~= "auto" then
        return pref
    end

    if inRaid() then return "RAID" end

    if type(IsInGroup) == "function" and _G.LE_PARTY_CATEGORY_INSTANCE ~= nil then
        local ok, v = pcall(IsInGroup, _G.LE_PARTY_CATEGORY_INSTANCE)
        if ok and v then return "INSTANCE_CHAT" end
    end

    return "PARTY"
end

-- 只发一次；返回是否"确认发出"。pcall 成功不等于已发出，所以再看返回值。
local function sendRaw(text, channel)
    if type(text) ~= "string" or text == "" then return false, "空消息" end
    if type(channel) ~= "string" or channel == "" then return false, "无频道" end

    local mode = sendMode()

    if mode == "nameless" then
        local info = _G.C_ChatInfo
        if type(info) ~= "table" or type(info.SendChatMessage) ~= "function" then
            return false, "缺少 C_ChatInfo.SendChatMessage"
        end
        local ok, ret = pcall(info.SendChatMessage, text, channel)
        if not ok then return false, tostring(ret) end
        if ret == false then return false, "接口拒绝发送" end
        return true
    end

    if mode == "global" then
        if type(_G.SendChatMessage) ~= "function" then
            return false, "缺少 SendChatMessage"
        end
        local ok, ret = pcall(_G.SendChatMessage, text, channel, nil)
        if not ok then return false, tostring(ret) end
        if ret == false then return false, "接口拒绝发送" end
        return true
    end

    return false, "无可用发送通道（caps.sendChat=" .. tostring(mode) .. "）"
end

local function enqueue(key, text, channel)
    if #queue >= QUEUE_MAX then
        table.remove(queue, 1)
        logWarn("预警队列已满（%d 条），丢弃最早一条", QUEUE_MAX)
    end
    queue[#queue + 1] = {
        key     = key,
        text    = text,
        channel = channel,
        at      = wallTime(),
    }
    logDebug("预警已入队（当前 %d 条）", #queue)
end

-- 中性文案：不含备注、不含指控性措辞
local function channelText(entry)
    local name = BE.Identity.Display(entry)
    local text = ("[BlackEvidence] 提示：队伍成员「%s」在你的黑名单记录中，请注意甄别与自我保护。"):format(name)
    return BE.Util.Truncate(text, 240)
end

local function sendOrQueue(text, key)
    if not inGroup() then
        logDebug("当前不在队伍中，跳过频道提示")
        return false
    end

    local channel = M.Channel()

    if inLockdown() then
        enqueue(key, text, channel)
        logWarn("聊天封锁中，频道提示已排队（%d 条），解锁后补发", #queue)
        return false
    end

    local ok, err = sendRaw(text, channel)
    if not ok then
        enqueue(key, text, channel)
        logWarn("发送失败（%s），已转入队列（%d 条）", tostring(err), #queue)
        return false
    end

    logInfo("已发送频道提示（%s）：%s", channel, BE.Util.Truncate(text, 120))
    return true
end

----------------------------------------------------------------------
-- 预警
----------------------------------------------------------------------

-- 触发一次预警。顺序：Hit -> 本地大字 -> 可选频道 -> 证据 -> 冷却标记。
function M.Warn(info)
    if type(info) ~= "table" or type(info.key) ~= "string" then return false end
    if setting("enabled") == false then return false end

    local s = state()

    local entry = BE.Blacklist.Find(info)
    if not entry then
        logDebug("目标不在黑名单里：%s", tostring(info.full or info.name))
        return false
    end

    local key = entry.key or info.key
    if s.ignoreSession[key] then
        logDebug("本场已豁免：%s", tostring(BE.Identity.Display(entry)))
        return false
    end
    if s.warned[key] then
        logDebug("本次组队已预警过：%s", tostring(BE.Identity.Display(entry)))
        return false
    end

    local now = BE.Util.Now()
    local cooldown = tonumber(setting("warnCooldown")) or 20
    if lastWarnAt[key] and (now - lastWarnAt[key]) < cooldown then
        logDebug("预警冷却中，跳过 %s（%.1f / %d 秒）",
            tostring(BE.Identity.Display(entry)), now - lastWarnAt[key], cooldown)
        return false
    end

    s.warned[key] = true
    lastWarnAt[key] = now

    -- 1) 命中计数
    BE.Blacklist.Hit(key)

    -- 2) 本地大字（立刻可见）
    showAlert(("黑名单玩家进入队伍：%s"):format(tostring(BE.Identity.Display(entry))))

    -- 3) 可选频道播报（默认关；文案不含备注）
    if setting("sendToPartyChat") then
        sendOrQueue(channelText(entry), key)
    end

    -- 4) 证据记录（Trigger 可能尚未加载）
    if BE.Trigger and type(BE.Trigger.Fire) == "function" then
        local ok, err = pcall(BE.Trigger.Fire, "JOIN_WARN", info, entry.note)
        if not ok then logWarn("证据记录失败：%s", tostring(err)) end
    end

    -- 5) 冷却已在上面标记
    logInfo("预警完成：%s（频道播报=%s）",
        tostring(BE.Identity.Display(entry)),
        setting("sendToPartyChat") and "开" or "关")
    return true
end

----------------------------------------------------------------------
-- 队伍扫描
----------------------------------------------------------------------

local function groupUnits()
    local units = {}

    if inRaid() then
        local n = 0
        if type(GetNumGroupMembers) == "function" then
            local ok, v = pcall(GetNumGroupMembers)
            if ok then n = tonumber(v) or 0 end
        end
        for i = 1, n do units[#units + 1] = "raid" .. i end
        if #units == 0 then units[1] = "player" end
        return units, n
    end

    units[1] = "player"
    for i = 1, 4 do
        local unit = "party" .. i
        local exists = true
        if type(UnitExists) == "function" then
            local ok, v = pcall(UnitExists, unit)
            exists = ok and v and true or false
        end
        if exists then units[#units + 1] = unit end
    end
    return units, #units
end

-- 真正干活的一次扫描。seedOnly=true 时只重建"已知成员"，不预警。
local function scanNow(reason, seedOnly)
    local s = state()

    if not inGroup() then
        if next(knownMembers) then
            knownMembers = {}
            logInfo("已不在队伍中，清空成员缓存")
        end
        clearWarned()
        return 0
    end

    local myInfo = BE.Identity.Unit("player")
    local myKey = myInfo and myInfo.key or nil

    local units = groupUnits()
    local current, newcomers = {}, {}
    local unreadable = 0

    for i = 1, #units do
        local unit = units[i]
        if unit ~= "player" then
            local ok, info = pcall(BE.Identity.Unit, unit)
            if not ok or type(info) ~= "table" then
                unreadable = unreadable + 1
                logDebug("成员 %s 身份不可读", tostring(unit))
            elseif info.key and info.key ~= myKey then
                current[info.key] = true
                if not knownMembers[info.key]
                    and not s.ignoreSession[info.key]
                    and not s.warned[info.key] then
                    newcomers[#newcomers + 1] = info
                end
            end
        end
    end

    local groupSize = count(current)
    knownMembers = current

    if seedOnly then
        -- 登录瞬间队伍信息可能还读不到：这种"空种子"不算完成首扫，
        -- 让 PLAYER_ENTERING_WORLD 再补一次，避免把现有队友误判为新人
        if groupSize > 0 then seededOnce = true end
        logDebug("种子扫描(%s)：%d 人，信息不可读 %d 个（不预警）",
            tostring(reason), groupSize, unreadable)
        return 0
    end

    if setting("enabled") == false or setting("warnOnPartyJoin") == false then
        logDebug("进队预警已关闭，只更新成员缓存")
        return 0
    end

    logDebug("队伍扫描(%s)：%d 人，新加入 %d 人，信息不可读 %d 个",
        tostring(reason), groupSize, #newcomers, unreadable)

    local warned = 0
    for i = 1, #newcomers do
        local info = newcomers[i]
        if BE.Blacklist.Find(info) then
            if M.Warn(info) then warned = warned + 1 end
        else
            logDebug("新成员 %s 不在黑名单里", tostring(info.full or info.name))
        end
    end

    if warned == 0 and #newcomers > 0 then
        logDebug("%d 名新成员都不是黑名单玩家", #newcomers)
    end
    return warned
end

-- 去抖调度。seedOnly 与 pending 分开记：
-- 真实名单更新永远把 seedOnly 拉回 false，不会被迟到的种子扫描降级。
local function schedule(reason, seedOnly)
    if seedOnly then
        if not scanPending then scanSeedOnly = true end
    else
        scanSeedOnly = false
        scanReason = reason
    end
    if not scanReason then scanReason = reason end

    if scanPending then return true end
    scanPending = true

    local function run()
        scanPending = false
        local seed = scanSeedOnly
        local why = scanReason or reason or "timer"
        scanSeedOnly, scanReason = false, nil
        local ok, err = pcall(scanNow, why, seed)
        if not ok then logError("队伍扫描失败：%s", tostring(err)) end
    end

    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        local ok = pcall(C_Timer.After, SCAN_DEBOUNCE, run)
        if ok then return true end
        logWarn("C_Timer.After 不可用，改为立即扫描")
    end
    run()
    return true
end

----------------------------------------------------------------------
-- 公共 API
----------------------------------------------------------------------

-- 去抖扫描（真实事件用；永远不会被当成种子扫描）
function M.Scan(reason)
    return schedule(reason or "manual", false)
end

-- 立即扫描（/be scan 用）
function M.ScanNow(reason)
    return scanNow(reason or "manual", false)
end

-- 供 /be queue 使用：返回队列的浅拷贝（不暴露内部表）
function M.Queue()
    local out = {}
    for i = 1, #queue do
        local q = queue[i]
        out[i] = { key = q.key, text = q.text, channel = q.channel, at = q.at }
    end
    return out
end

function M.QueueCount()
    return #queue
end

function M.ClearQueue()
    local n = #queue
    queue = {}
    if n > 0 then logInfo("已清空 %d 条排队预警", n) end
    return n
end

-- 解锁 / 进世界后补发；只在不处于封锁且仍在队伍里时发
function M.Flush()
    local n = #queue
    if n == 0 then return 0 end

    -- 配置关闭时绝不发频道：直接丢弃排队项
    if setting("sendToPartyChat") == false then
        queue = {}
        logInfo("频道播报已关闭，丢弃 %d 条排队预警", n)
        return 0
    end

    if inLockdown() then
        logDebug("仍处于聊天封锁，暂不补发 %d 条", n)
        return 0
    end

    if not inGroup() then
        queue = {}
        logWarn("已不在队伍中，丢弃 %d 条排队预警", n)
        return 0
    end

    local sending = queue
    queue = {}

    local sent = 0
    for i = 1, #sending do
        local item = sending[i]
        local channel = item.channel or M.Channel()
        local ok, err = sendRaw(item.text, channel)
        if ok then
            sent = sent + 1
        else
            logError("补发失败（%s），重新入队：%s", tostring(err), tostring(item.text))
            enqueue(item.key, item.text, channel)
        end
    end

    logInfo("补发完成：成功 %d / %d 条", sent, #sending)
    return sent
end

-- /be queue 与 /be status 用的多行摘要
function M.Status()
    local s = state()
    local lines = {
        ("进队预警：%s｜频道播报：%s"):format(
            setting("warnOnPartyJoin") == false and "关" or "开",
            setting("sendToPartyChat") and "开" or "关（仅本地提示）"),
        ("频道：配置=%s｜实际=%s"):format(
            tostring(setting("warnChannel") or "auto"),
            inGroup() and M.Channel() or "（不在队伍）"),
        ("本地大字：%s｜冷却：%d 秒"):format(
            setting("localAlert") == false and "关" or "开",
            tonumber(setting("warnCooldown")) or 20),
        ("本次组队已预警：%d 人｜本场豁免：%d 人"):format(
            count(s.warned), count(s.ignoreSession)),
        ("排队：%d / %d 条｜聊天封锁：%s"):format(
            #queue, QUEUE_MAX, inLockdown() and "是" or "否"),
        ("发送通道：%s"):format(tostring(sendMode())),
    }
    return table.concat(lines, "\n")
end

----------------------------------------------------------------------
-- 初始化
----------------------------------------------------------------------

function M.Init()
    if started then return true end

    if not (BE.Config and BE.Blacklist and BE.Identity) then
        logError("基础模块未就绪，队伍预警没有启动")
        return false
    end

    state()

    local events = {
        "GROUP_ROSTER_UPDATE",
        "PLAYER_ENTERING_WORLD",
        "GROUP_LEFT",
        "GROUP_FORMED",
        "PLAYER_REGEN_ENABLED",   -- 解锁 / 退出战斗后补发
    }
    local okCount, failed = 0, {}
    for i = 1, #events do
        local ev = events[i]
        local ok = BE:RegisterEvent(ev)
        if ok then
            okCount = okCount + 1
        else
            failed[#failed + 1] = ev
        end
    end

    BE:On("GROUP_ROSTER_UPDATE", function()
        M.Scan("roster")
    end)

    BE:On("GROUP_FORMED", function()
        M.Scan("group_formed")
    end)

    BE:On("GROUP_LEFT", function()
        if not inGroup() then
            knownMembers = {}
            clearWarned()
            logInfo("已离开队伍，清空成员缓存与预警去重")
        end
        M.Scan("group_left")
    end)

    BE:On("PLAYER_ENTERING_WORLD", function()
        -- 首次进世界做种子扫描（/reload 不重复预警）；之后按普通扫描
        schedule("enter_world", not seededOnce)
        M.Flush()
    end)

    BE:On("PLAYER_REGEN_ENABLED", function()
        M.Flush()
    end)

    started = true
    logInfo("队伍预警已启动：事件 %d/%d｜频道=%s｜播报=%s｜冷却=%d 秒",
        okCount, #events,
        tostring(setting("warnChannel") or "auto"),
        setting("sendToPartyChat") and "开" or "关",
        tonumber(setting("warnCooldown")) or 20)
    if #failed > 0 then
        logWarn("部分事件注册失败：%s", table.concat(failed, ", "))
    end

    -- 登录首扫种子：把已在队伍里的成员记为"已知"
    schedule("init", true)
    return true
end
