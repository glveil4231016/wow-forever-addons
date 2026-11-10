-- BlackEvidence / ManagerUI.lua
-- 管理页面：黑名单 / 快照 / 设置 + 通用文本窗口 + 导入窗口。
-- 不依赖 BackdropTemplate，三种客户端通用。

local ADDON, BE = ...
BE.ManagerUI = BE.ManagerUI or {}
local M = BE.ManagerUI

local W, H = 800, 560
local PAGE = 10

local main, content
local tabButtons = {}
local panels = {}
local currentTab = "blacklist"

local blPage, snapPage = 1, 1
local blSearch, blRows = nil, {}
local snapRows, snapDetail, snapSelectedId = {}, nil, nil

local textWin
local importWin

----------------------------------------------------------------------
-- 基础控件
----------------------------------------------------------------------

local function paint(f, alpha)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    bg:SetColorTexture(0.045, 0.05, 0.07, alpha or 0.96)
    return bg
end

local function border(f, r, g, b)
    local line = f:CreateTexture(nil, "BORDER")
    line:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    line:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    line:SetHeight(2)
    line:SetColorTexture(r or 0.32, g or 0.42, b or 0.94, 0.9)
end

local function fs(parent, text, size, r, g, b)
    local t = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    if size then
        local font = t:GetFont()
        if font then t:SetFont(font, size, "OUTLINE") end
    end
    if r then t:SetTextColor(r, g, b) end
    t:SetText(text or "")
    t:SetJustifyH("LEFT")
    return t
end

local function mkButton(parent, w, text, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w or 90, 22)
    b:SetText(text or "")
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

local function mkCheck(parent, label, getter, setter)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    local t = fs(parent, label, nil, 0.9, 0.92, 1)
    t:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    cb.label = t
    cb:SetScript("OnClick", function(self)
        setter(self:GetChecked() and true or false)
        M.Refresh()
    end)
    cb.getter = getter
    return cb
end

local function mkScrollEdit(parent, w, h)
    local sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    sf:SetSize(w, h)
    local bg = sf:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(sf)
    bg:SetColorTexture(0, 0, 0, 0.45)

    local child = CreateFrame("Frame", nil, sf)
    child:SetWidth(w - 20)
    child:SetHeight(h)
    sf:SetScrollChild(child)

    local eb = CreateFrame("EditBox", nil, child)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(0)
    eb:SetFontObject(ChatFontNormal)
    eb:SetWidth(w - 20)
    eb:SetHeight(h)
    eb:SetPoint("TOPLEFT", child, "TOPLEFT", 2, -2)
    eb:SetTextInsets(2, 2, 2, 2)
    eb:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        local _, lines = text:gsub("\n", "\n")
        child:SetHeight(math.max(h, (lines + 1) * 16 + 10))
    end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return eb, child
end

----------------------------------------------------------------------
-- 黑名单页
----------------------------------------------------------------------

local function buildBlacklist(panel)
    blSearch = CreateFrame("EditBox", nil, panel)
    blSearch:SetSize(220, 22)
    blSearch:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -6)
    blSearch:SetAutoFocus(false)
    blSearch:SetFontObject(ChatFontNormal)
    blSearch:SetTextInsets(4, 4, 0, 0)
    local sbg = blSearch:CreateTexture(nil, "BACKGROUND")
    sbg:SetAllPoints(blSearch)
    sbg:SetColorTexture(0, 0, 0, 0.5)
    blSearch:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    blSearch:SetScript("OnTextChanged", function()
        blPage = 1
        M.Refresh()
    end)

    local ph = fs(panel, "搜索名字 / 备注", 11, 0.55, 0.58, 0.65)
    ph:SetPoint("LEFT", blSearch, "RIGHT", 8, 0)
    ph:SetScript("OnShow", nil)

    local add = mkButton(panel, 96, "新增", function()
        local info = { name = "", surname = nil, realm = nil, full = "手动新增" }
        if BE.NoteDialog then
            BE.NoteDialog.Open(info, {
                mode = "add",
                askName = true,
                onSave = function(note, name)
                    name = BE.Util.Trim(name) or ""
                    if name == "" then
                        print("|cff33ff99[BE]|r 名字不能为空")
                        return
                    end
                    local key = BE.Identity.KeyFromParts(name, nil)
                    if not key then
                        print("|cff33ff99[BE]|r 名字无效")
                        return
                    end
                    BE.Blacklist.Add({
                        name = name, key = key, full = name, guid = nil,
                        surname = nil, realm = nil,
                    }, note, "manual")
                    M.Refresh()
                end,
            })
        end
    end)
    add:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -120, -6)

    local header = fs(panel, "名字", 11, 0.65, 0.68, 0.75)
    header:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -38)
    local h2 = fs(panel, BE.Identity.SecondLabel(), 11, 0.65, 0.68, 0.75)
    h2:SetPoint("LEFT", header, "RIGHT", 120, 0)
    local h3 = fs(panel, "备注", 11, 0.65, 0.68, 0.75)
    h3:SetPoint("LEFT", h2, "RIGHT", 100, 0)
    local h4 = fs(panel, "命中", 11, 0.65, 0.68, 0.75)
    h4:SetPoint("LEFT", h3, "RIGHT", 190, 0)

    for i = 1, PAGE do
        local row = CreateFrame("Frame", nil, panel)
        row:SetSize(760, 26)
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -56 - (i - 1) * 28)
        paint(row, 0.35)
        row.name = fs(row, "", 12, 0.95, 0.96, 1)
        row.name:SetPoint("LEFT", row, "LEFT", 6, 0)
        row.name:SetWidth(112)
        row.second = fs(row, "", 12, 0.8, 0.82, 0.9)
        row.second:SetPoint("LEFT", row, "LEFT", 126, 0)
        row.second:SetWidth(94)
        row.note = fs(row, "", 12, 0.75, 0.78, 0.85)
        row.note:SetPoint("LEFT", row, "LEFT", 226, 0)
        row.note:SetWidth(300)
        row.hits = fs(row, "", 12, 0.7, 0.72, 0.8)
        row.hits:SetPoint("LEFT", row, "LEFT", 534, 0)
        row.hits:SetWidth(60)
        row.edit = mkButton(row, 48, "编辑", function()
            if row.entry and BE.NoteDialog then
                BE.NoteDialog.Open(row.entry, { mode = "edit", note = row.entry.note })
            end
        end)
        row.edit:SetPoint("RIGHT", row, "RIGHT", -120, 0)
        row.del = mkButton(row, 48, "删除", function()
            if not row.entry then return end
            StaticPopupDialogs["BE_CONFIRM_DELETE"] = StaticPopupDialogs["BE_CONFIRM_DELETE"] or {
                text = "确定删除 %s ？",
                button1 = "删除", button2 = "取消",
                OnAccept = function(_, data)
                    if data then BE.Blacklist.Remove(data) end
                    M.Refresh()
                end,
                timeout = 0, whileDead = true, hideOnEscape = true,
            }
            StaticPopup_Show("BE_CONFIRM_DELETE", BE.Identity.Display(row.entry), nil, row.entry.key)
        end)
        row.del:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row:Hide()
        blRows[i] = row
    end

    local prev = mkButton(panel, 60, "上一页", function()
        if blPage > 1 then blPage = blPage - 1; M.Refresh() end
    end)
    prev:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0)

    local nextBtn = mkButton(panel, 60, "下一页", function()
        blPage = blPage + 1; M.Refresh()
    end)
    nextBtn:SetPoint("LEFT", prev, "RIGHT", 8, 0)

    panel.pageLabel = fs(panel, "", 11, 0.7, 0.72, 0.8)
    panel.pageLabel:SetPoint("LEFT", nextBtn, "RIGHT", 10, 0)

    panel.countLabel = fs(panel, "", 11, 0.7, 0.72, 0.8)
    panel.countLabel:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 4)
end

local function refreshBlacklist()
    if not blSearch then return end
    local q = blSearch:GetText() or ""
    local list = BE.Blacklist.Search(q)
    local total = #list
    local pages = math.max(1, math.ceil(total / PAGE))
    if blPage > pages then blPage = pages end
    if blPage < 1 then blPage = 1 end

    for i = 1, PAGE do
        local row = blRows[i]
        local idx = (blPage - 1) * PAGE + i
        local entry = list[idx]
        if entry then
            row.entry = entry
            row.name:SetText(entry.name or "?")
            local second = BE.Profile.Cap("surname") and (entry.surname or "") or (entry.realm or "")
            row.second:SetText(second)
            row.note:SetText(BE.Util.Truncate(entry.note or "", 32))
            row.hits:SetText(tostring(entry.hits or 0))
            row:Show()
        else
            row.entry = nil
            row:Hide()
        end
    end

    local panel = panels.blacklist
    if panel and panel.pageLabel then
        panel.pageLabel:SetText(("第 %d/%d 页"):format(blPage, pages))
    end
    if panel and panel.countLabel then
        panel.countLabel:SetText(("当前版本 %s 共 %d 条"):format(BE.Profile.label or "?", total))
    end
end

----------------------------------------------------------------------
-- 快照页
----------------------------------------------------------------------

local function buildSnapshots(panel)
    for i = 1, 8 do
        local b = mkButton(panel, 320, "", function()
            local rec = snapRows[i] and snapRows[i].rec
            if rec then
                snapSelectedId = rec.id
                M.Refresh()
            end
        end)
        b:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -6 - (i - 1) * 26)
        b:SetHeight(22)
        b:Hide()
        snapRows[i] = b
    end

    local prev = mkButton(panel, 60, "上一页", function()
        if snapPage > 1 then snapPage = snapPage - 1; M.Refresh() end
    end)
    prev:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0)

    local nextBtn = mkButton(panel, 60, "下一页", function()
        snapPage = snapPage + 1; M.Refresh()
    end)
    nextBtn:SetPoint("LEFT", prev, "RIGHT", 8, 0)

    panel.pageLabel = fs(panel, "", 11, 0.7, 0.72, 0.8)
    panel.pageLabel:SetPoint("LEFT", nextBtn, "RIGHT", 10, 0)

    local del = mkButton(panel, 90, "删除本条", function()
        if snapSelectedId then
            BE.Trigger.Remove(snapSelectedId)
            snapSelectedId = nil
            M.Refresh()
        end
    end)
    del:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 30)

    local clear = mkButton(panel, 90, "清空全部", function()
        StaticPopupDialogs["BE_CONFIRM_CLEAR_SNAP"] = StaticPopupDialogs["BE_CONFIRM_CLEAR_SNAP"] or {
            text = "确定清空全部证据记录？",
            button1 = "清空", button2 = "取消",
            OnAccept = function()
                local recs = BE.Trigger.List()
                for i = #recs, 1, -1 do BE.Trigger.Remove(recs[i].id) end
                snapSelectedId = nil
                M.Refresh()
            end,
            timeout = 0, whileDead = true, hideOnEscape = true,
        }
        StaticPopup_Show("BE_CONFIRM_CLEAR_SNAP")
    end)
    clear:SetPoint("LEFT", del, "RIGHT", 8, 0)

    local copy = mkButton(panel, 90, "复制全文", function()
        if snapDetail then
            snapDetail:SetFocus()
            snapDetail:HighlightText()
        end
    end)
    copy:SetPoint("LEFT", clear, "RIGHT", 8, 0)

    local eb, child = mkScrollEdit(panel, 430, 430)
    eb:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -6)
    snapDetail = eb
    panel.detailChild = child
end

local function refreshSnapshots()
    local list = BE.Trigger and BE.Trigger.List() or {}
    local total = #list
    local pages = math.max(1, math.ceil(total / 8))
    if snapPage > pages then snapPage = pages end
    if snapPage < 1 then snapPage = 1 end

    for i = 1, 8 do
        local idx = (snapPage - 1) * 8 + i
        local rec = list[idx]
        local b = snapRows[i]
        if rec then
            b.rec = rec
            b:SetText(("%s  %s"):format(rec.id or "?", rec.reason or ""))
            b:Show()
        else
            b.rec = nil
            b:Hide()
        end
    end

    local panel = panels.snapshots
    if panel and panel.pageLabel then
        panel.pageLabel:SetText(("第 %d/%d 页 · 共 %d 条"):format(snapPage, pages, total))
    end

    if snapDetail then
        local rec = snapSelectedId and BE.Trigger.Get(snapSelectedId) or nil
        if not rec and list[1] then rec = list[1]; snapSelectedId = rec.id end
        local text = ""
        if rec and BE.Export and BE.Export.Pack then
            text = BE.Export.Pack(rec.id) or ""
        end
        snapDetail:SetText(text)
    end
end

----------------------------------------------------------------------
-- 设置页
----------------------------------------------------------------------

local function buildSettings(panel)
    local y = -6
    local function row(label, kind, key, lo, hi, step)
        local holder = CreateFrame("Frame", nil, panel)
        holder:SetSize(740, 26)
        holder:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, y)
        y = y - 28

        if kind == "bool" then
            local cb = mkCheck(holder, label, function() return BE.Config:Get(key) end, function(v)
                BE.Config:Set(key, v)
            end)
            cb:SetPoint("LEFT", holder, "LEFT", 0, 0)
            holder.cb = cb
        else
            local t = fs(holder, label, 12, 0.9, 0.92, 1)
            t:SetPoint("LEFT", holder, "LEFT", 0, 0)
            local minus = mkButton(holder, 24, "-", function()
                local v = tonumber(BE.Config:Get(key)) or lo
                BE.Config:Set(key, math.max(lo, v - step))
                M.Refresh()
            end)
            minus:SetPoint("LEFT", holder, "LEFT", 260, 0)
            local val = fs(holder, "", 12, 0.8, 0.85, 1)
            val:SetPoint("LEFT", minus, "RIGHT", 10, 0)
            val:SetWidth(70)
            local plus = mkButton(holder, 24, "+", function()
                local v = tonumber(BE.Config:Get(key)) or lo
                BE.Config:Set(key, math.min(hi, v + step))
                M.Refresh()
            end)
            plus:SetPoint("LEFT", val, "RIGHT", 10, 0)
            holder.val = val
            holder.key = key
        end
        panel.rows = panel.rows or {}
        panel.rows[#panel.rows + 1] = holder
    end

    row("黑名单玩家进队时预警", "bool", "warnOnPartyJoin")
    row("真的发到队伍频道（会公开提示）", "bool", "sendToPartyChat")
    row("本地大字 + 音效", "bool", "localAlert")
    row("自动开启聊天日志（写 WoWChatLog.txt）", "bool", "autoChatLog")
    row("拉黑时自动截图", "bool", "screenshotOnAdd")
    row("预警冷却（秒）", "num", "warnCooldown", 5, 300, 5)
    row("时间线保留（秒）", "num", "timelineSeconds", 60, 600, 30)
    row("证据保留条数", "num", "snapshotKeep", 5, 50, 5)

    local scope = mkButton(panel, 160, "", function()
        local v = BE.Config:Get("recordScope") == "instance" and "all" or "instance"
        BE.Config:Set("recordScope", v)
        M.Refresh()
    end)
    scope:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, y - 6)
    panel.scopeBtn = scope

    local lvl = mkButton(panel, 160, "", function()
        local order = { "trace", "debug", "info", "warn", "error", "off" }
        local cur = BE.Config:Get("logLevel") or "debug"
        local idx = 1
        for i = 1, #order do if order[i] == cur then idx = i break end end
        idx = idx % #order + 1
        BE.Config:Set("logLevel", order[idx])
        if BE.Log then BE.Log.Level = order[idx] end
        M.Refresh()
    end)
    lvl:SetPoint("TOPLEFT", panel, "TOPLEFT", 200, y - 6)
    panel.levelBtn = lvl
end

----------------------------------------------------------------------
-- 主窗体
----------------------------------------------------------------------

local function showTab(id)
    currentTab = id
    for key, panel in pairs(panels) do
        if key == id then panel:Show() else panel:Hide() end
    end
    for key, btn in pairs(tabButtons) do
        if btn.SetButtonState then
            pcall(btn.SetButtonState, btn, key == id and "PUSHED" or "NORMAL", false)
        end
    end
    M.Refresh()
end

local function build()
    if main then return end

    main = CreateFrame("Frame", "BlackEvidenceManager", UIParent)
    main:SetSize(W, H)
    main:SetPoint("CENTER")
    main:SetFrameStrata("DIALOG")
    main:SetToplevel(true)
    main:SetClampedToScreen(true)
    main:SetMovable(true)
    main:EnableMouse(true)
    main:RegisterForDrag("LeftButton")
    main:SetScript("OnDragStart", main.StartMoving)
    main:SetScript("OnDragStop", main.StopMovingOrSizing)
    main:Hide()
    paint(main)
    border(main)

    local title = fs(main, "BlackEvidence", 16, 1, 1, 1)
    title:SetPoint("TOPLEFT", main, "TOPLEFT", 16, -12)

    main.profileLabel = fs(main, "", 11, 0.6, 0.85, 1)
    main.profileLabel:SetPoint("LEFT", title, "RIGHT", 10, 0)

    local close = CreateFrame("Button", nil, main, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", main, "TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() main:Hide() end)

    local tabDefs = {
        { id = "blacklist", text = "黑名单" },
        { id = "snapshots", text = "快照" },
        { id = "settings",  text = "设置" },
    }
    local x = 16
    for _, def in ipairs(tabDefs) do
        local b = mkButton(main, 90, def.text, function() showTab(def.id) end)
        b:SetPoint("TOPLEFT", main, "TOPLEFT", x, -40)
        x = x + 96
        tabButtons[def.id] = b
    end

    content = CreateFrame("Frame", nil, main)
    content:SetPoint("TOPLEFT", main, "TOPLEFT", 16, -74)
    content:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -16, 16)

    for _, id in ipairs({ "blacklist", "snapshots", "settings" }) do
        local p = CreateFrame("Frame", nil, content)
        p:SetAllPoints(content)
        p:Hide()
        panels[id] = p
    end

    buildBlacklist(panels.blacklist)
    buildSnapshots(panels.snapshots)
    buildSettings(panels.settings)

    showTab("blacklist")
end

function M.Refresh()
    if not main or not main:IsShown() then return end
    if main.profileLabel then
        main.profileLabel:SetText(("%s · %s · %d 条"):format(
            BE.Profile.label or "?", BE.Profile.id or "?",
            BE.Blacklist and BE.Blacklist.Count() or 0))
    end

    if currentTab == "blacklist" then
        refreshBlacklist()
    elseif currentTab == "snapshots" then
        refreshSnapshots()
    elseif currentTab == "settings" then
        local p = panels.settings
        if p and p.rows then
            for _, holder in ipairs(p.rows) do
                if holder.cb then
                    local v = holder.cb.getter()
                    holder.cb:SetChecked(v and true or false)
                elseif holder.val then
                    local key = holder.key
                    holder.val:SetText(tostring(BE.Config:Get(key)))
                end
            end
        end
        if p and p.scopeBtn then
            p.scopeBtn:SetText("记录范围：" .. (BE.Config:Get("recordScope") == "instance" and "仅副本" or "全地图"))
        end
        if p and p.levelBtn then
            p.levelBtn:SetText("日志级别：" .. tostring(BE.Config:Get("logLevel")))
        end
    end
end

function M.Open()
    build()
    main:Show()
    M.Refresh()
end

function M.Close()
    if main then main:Hide() end
end

function M.Toggle()
    if main and main:IsShown() then M.Close() else M.Open() end
end

function M.OpenSnapshot(id)
    build()
    snapSelectedId = id
    main:Show()
    showTab("snapshots")
end

----------------------------------------------------------------------
-- 通用文本窗口 / 导入窗口
----------------------------------------------------------------------

function M.ShowText(title, text)
    if not textWin then
        textWin = CreateFrame("Frame", "BlackEvidenceText", UIParent)
        textWin:SetSize(700, 500)
        textWin:SetPoint("CENTER")
        textWin:SetFrameStrata("DIALOG")
        textWin:SetMovable(true)
        textWin:EnableMouse(true)
        textWin:RegisterForDrag("LeftButton")
        textWin:SetScript("OnDragStart", textWin.StartMoving)
        textWin:SetScript("OnDragStop", textWin.StopMovingOrSizing)
        paint(textWin)
        border(textWin)

        textWin.title = fs(textWin, "", 14, 1, 1, 1)
        textWin.title:SetPoint("TOPLEFT", textWin, "TOPLEFT", 14, -12)

        local close = CreateFrame("Button", nil, textWin, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", textWin, "TOPRIGHT", -4, -4)

        local eb, child = mkScrollEdit(textWin, 660, 420)
        eb:SetPoint("TOPLEFT", textWin, "TOPLEFT", 14, -40)
        textWin.edit = eb

        local copy = mkButton(textWin, 90, "全选复制", function()
            eb:SetFocus()
            eb:HighlightText()
        end)
        copy:SetPoint("BOTTOMLEFT", textWin, "BOTTOMLEFT", 14, 12)
    end
    textWin.title:SetText(title or "")
    textWin.edit:SetText(text or "")
    textWin:Show()
    textWin:Raise()
end

function M.ShowImport()
    if not importWin then
        importWin = CreateFrame("Frame", "BlackEvidenceImport", UIParent)
        importWin:SetSize(700, 500)
        importWin:SetPoint("CENTER")
        importWin:SetFrameStrata("DIALOG")
        importWin:SetMovable(true)
        importWin:EnableMouse(true)
        importWin:RegisterForDrag("LeftButton")
        importWin:SetScript("OnDragStart", importWin.StartMoving)
        importWin:SetScript("OnDragStop", importWin.StopMovingOrSizing)
        paint(importWin)
        border(importWin)

        local t = fs(importWin, "导入黑名单（粘贴后选择范围）", 14, 1, 1, 1)
        t:SetPoint("TOPLEFT", importWin, "TOPLEFT", 14, -12)

        local close = CreateFrame("Button", nil, importWin, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", importWin, "TOPRIGHT", -4, -4)

        local eb = mkScrollEdit(importWin, 660, 390)
        eb:SetPoint("TOPLEFT", importWin, "TOPLEFT", 14, -40)
        importWin.edit = eb

        local function doImport(mode)
            local text = importWin.edit:GetText() or ""
            local res = BE.Export.Import(text, { profile = mode })
            print(("|cff33ff99[BE]|r 导入：解析 %d，新增 %d，更新 %d，失败 %d"):format(
                res.parsed or 0, res.added or 0, res.updated or 0, res.failed or 0))
            M.Refresh()
        end

        local b1 = mkButton(importWin, 140, "导入到当前版本", function() doImport("current") end)
        b1:SetPoint("BOTTOMLEFT", importWin, "BOTTOMLEFT", 14, 12)

        local b2 = mkButton(importWin, 140, "导入到全部版本", function() doImport("all") end)
        b2:SetPoint("LEFT", b1, "RIGHT", 10, 0)
    end
    importWin.edit:SetText("")
    importWin:Show()
    importWin:Raise()
end

function M.Init()
    -- 懒加载，首次 /be 或 Open 时构建
end

-- 统一 UI 入口（Menu 等模块通过 BE.UI 调用）
BE.UI = BE.UI or {}
BE.UI.Open        = M.Open
BE.UI.Close       = M.Close
BE.UI.Toggle      = M.Toggle
BE.UI.Refresh     = M.Refresh
BE.UI.ShowText    = M.ShowText
BE.UI.ShowImport  = M.ShowImport
BE.UI.OpenSnapshot= M.OpenSnapshot
