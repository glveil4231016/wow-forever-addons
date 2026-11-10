-- BlackEvidence / NoteDialog.lua
-- 多行备注对话框。三种客户端通用，不依赖 BackdropTemplate。

local ADDON, BE = ...
BE.NoteDialog = BE.NoteDialog or {}
local N = BE.NoteDialog

local frame, editBox, scrollChild, titleText, subText
local nameLabel, nameBox, scrollFrame
local currentInfo, currentOpts

local W, H = 460, 300

local function makeBackground(f)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    bg:SetColorTexture(0.045, 0.05, 0.07, 0.96)
    local line = f:CreateTexture(nil, "BORDER")
    line:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    line:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    line:SetHeight(2)
    line:SetColorTexture(0.32, 0.42, 0.94, 0.9)
    return bg
end

local function close()
    if frame then frame:Hide() end
    currentInfo, currentOpts = nil, nil
end

local function save()
    if not currentInfo then close() return end
    local note = editBox and editBox:GetText() or ""
    note = note or ""
    note = note:gsub("\r\n", "\n"):gsub("\r", "\n")

    local opts = currentOpts or {}
    local name
    if opts.askName and nameBox then
        name = nameBox:GetText() or ""
        name = (BE.Util and BE.Util.Trim(name)) or name
        if name == "" then
            print("|cff33ff99[BE]|r 名字不能为空")
            if nameBox.SetFocus then nameBox:SetFocus() end
            return
        end
        currentInfo.name = name
        if BE.Identity then
            currentInfo.full = BE.Identity.Display({
                name = name,
                surname = currentInfo.surname,
                realm = currentInfo.realm,
            })
        end
    end

    if type(opts.onSave) == "function" then
        local ok, err = pcall(opts.onSave, note, name)
        if not ok and BE.Log then BE.Log.Error("NoteDialog", "onSave 失败：%s", tostring(err)) end
    elseif BE.Blacklist then
        if opts.mode == "edit" and currentInfo.key then
            BE.Blacklist.Update(currentInfo.key, note)
        else
            if not currentInfo.key and BE.Identity then
                currentInfo.key = BE.Identity.KeyFromParts(
                    currentInfo.name,
                    (BE.Profile and BE.Profile.Cap("surname")) and currentInfo.surname or currentInfo.realm)
            end
            local entry, isNew = BE.Blacklist.Add(currentInfo, note, "menu")
            if isNew and BE.Trigger and BE.Config and BE.Config:Get("screenshotOnAdd") then
                pcall(BE.Trigger.Fire, "BLACKLIST_ADD", currentInfo, note)
            end
        end
    end

    if BE.ManagerUI and BE.ManagerUI.Refresh then
        pcall(BE.ManagerUI.Refresh)
    end
    close()
end

local function build()
    if frame then return end

    frame = CreateFrame("Frame", "BlackEvidenceNoteDialog", UIParent)
    frame:SetSize(W, H)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    makeBackground(frame)

    titleText = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    titleText:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -14)
    titleText:SetText("加入黑名单")

    subText = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -6)
    subText:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
    subText:SetJustifyH("LEFT")
    subText:SetText("")

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", close)

    -- 手动新增时的名字输入（默认隐藏）
    nameLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    nameLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -72)
    nameLabel:SetText("名字")
    nameLabel:Hide()

    nameBox = CreateFrame("EditBox", nil, frame)
    nameBox:SetSize(220, 20)
    nameBox:SetPoint("LEFT", nameLabel, "RIGHT", 8, 0)
    nameBox:SetAutoFocus(false)
    nameBox:SetFontObject(ChatFontNormal)
    nameBox:SetTextInsets(4, 4, 0, 0)
    local nbg = nameBox:CreateTexture(nil, "BACKGROUND")
    nbg:SetAllPoints(nameBox)
    nbg:SetColorTexture(0, 0, 0, 0.5)
    nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    nameBox:Hide()

    -- 滚动区 + 多行 EditBox
    local sf = CreateFrame("ScrollFrame", "BlackEvidenceNoteScroll", frame, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -72)
    sf:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -36, 52)
    scrollFrame = sf

    local bg = sf:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(sf)
    bg:SetColorTexture(0, 0, 0, 0.45)

    scrollChild = CreateFrame("Frame", nil, sf)
    scrollChild:SetWidth(W - 60)
    scrollChild:SetHeight(1)
    sf:SetScrollChild(scrollChild)

    editBox = CreateFrame("EditBox", "BlackEvidenceNoteEdit", scrollChild)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetMaxLetters(2000)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(W - 60)
    editBox:SetHeight(200)
    editBox:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 4, -2)
    editBox:SetTextInsets(2, 2, 2, 2)

    editBox:SetScript("OnEscapePressed", close)
    editBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        local _, lines = text:gsub("\n", "\n")
        local h = math.max(200, (lines + 1) * 16 + 8)
        scrollChild:SetHeight(h)
    end)
    editBox:SetScript("OnKeyDown", function(self, key)
        if key == "ENTER" and IsControlKeyDown and IsControlKeyDown() then
            if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
            save()
        elseif IsShiftKeyDown and IsShiftKeyDown() and key == "ENTER" then
            -- Shift+Enter 换行
        end
    end)

    local hint = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 34)
    hint:SetText("Ctrl+Enter 保存 · Esc 取消")

    local okBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    okBtn:SetSize(96, 24)
    okBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 12)
    okBtn:SetText("保存")
    okBtn:SetScript("OnClick", save)

    local cancelBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    cancelBtn:SetSize(96, 24)
    cancelBtn:SetPoint("RIGHT", okBtn, "LEFT", -8, 0)
    cancelBtn:SetText("取消")
    cancelBtn:SetScript("OnClick", close)
end

function N.Open(info, opts)
    build()
    currentInfo = info
    currentOpts = opts or {}

    local mode = currentOpts.mode or "add"
    titleText:SetText(mode == "edit" and "修改备注" or "加入黑名单")
    subText:SetText(BE.Identity and BE.Identity.Display(info) or (info and info.full) or "?")

    local askName = currentOpts.askName and true or false
    if nameLabel and nameBox and scrollFrame then
        if askName then
            nameLabel:Show()
            nameBox:Show()
            nameBox:SetText((info and info.name) or "")
            scrollFrame:ClearAllPoints()
            scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -100)
            scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -36, 52)
        else
            nameLabel:Hide()
            nameBox:Hide()
            scrollFrame:ClearAllPoints()
            scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -72)
            scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -36, 52)
        end
    end

    local note = currentOpts.note
    if note == nil then
        local entry = BE.Blacklist and info and info.key and BE.Blacklist.Get(info.key) or nil
        note = entry and entry.note or ""
    end
    editBox:SetText(note or "")
    editBox:SetCursorPosition(0)
    scrollChild:SetHeight(math.max(200, 208))

    frame:Show()
    if askName and nameBox then
        nameBox:SetFocus()
    else
        editBox:SetFocus()
        editBox:HighlightText()
    end
end

function N.Close()
    close()
end

function N.IsOpen()
    return frame and frame:IsShown() or false
end

function N.Init()
    -- 懒加载：第一次 Open 时才建 UI
end

-- 兼容层：Menu.lua 通过 BE.UI.OpenNote 打开备注框
BE.UI = BE.UI or {}
BE.UI.OpenNote = N.Open
BE.UI.CloseNote = N.Close
