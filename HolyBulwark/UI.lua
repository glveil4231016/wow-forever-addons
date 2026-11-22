local addonName, ns = ...

local F = ns.F
local ROWS = 18
local ROW_H = 25

local frame, rows, listFrame, countLabel, pageLabel
local searchBox, minBox, maxBox, tankyCB, knownCB, noteLabel
local detail, detailIcon, detailName, detailEn, detailSub1, detailSub2, detailBody, detailScroll, detailContent
local detailLink, detailMap
local HandleSpgLink
local ShowQuestDetail
local questFrame, questScroll, questContent, questBody

local function NpcLink(id, name)
    return "|cff9cd6ff|Hspg:npc:" .. tostring(id) .. "|h[" .. tostring(name or id) .. "]|h|r"
end

local function QuestLink(id, name)
    return "|cffffd200|Hspg:quest:" .. tostring(id) .. "|h[" .. tostring(name or id) .. "]|h|r"
end

local function ObjectLink(id, name)
    return "|cff9cd6ff|Hspg:object:" .. tostring(id) .. "|h[" .. tostring(name or ("对象 #" .. tostring(id))) .. "]|h|r"
end

local function PinLink(kind, id, label)
    return "|cff33ff99|Hspg:" .. kind .. ":" .. tostring(id) .. "|h[" .. tostring(label or "标出") .. "]|h|r"
end

local function QLocLink(id, which, label)
    return "|cff9cd6ff|Hspg:qloc:" .. tostring(id) .. ":" .. tostring(which) .. "|h[" .. tostring(label) .. "]|h|r"
end

local function StepLink(id, index, label)
    return "|cff9cd6ff|Hspg:step:" .. tostring(id) .. ":" .. tostring(index) .. "|h[" .. tostring(label) .. "]|h|r"
end

local function ItemName(id)
    local idb = _G.ItemDB
    if idb and idb.Get then
        local ok, name = pcall(idb.Get, idb, tonumber(id) or id, "name")
        if ok and type(name) == "string" and name ~= "" then
            local loc = GetLocale and GetLocale() or ""
            if loc:sub(1, 2) == "zh" and not name:find("[\128-\255]") then
                return "物品 #" .. tostring(id)
            end
            return name
        end
    end
    return "物品 #" .. tostring(id)
end

local function ChineseItemFromEnglish(name)
    if not name then return nil end
    local id = ns:FindItemIdByName(name)
    if id then return ItemName(id), id end
end

local function MobLinks(names, limit)
    local out = {}
    for i = 1, math.min(#names, limit or 8) do
        local id = ns:FindNpcIdByName(names[i])
        if id then out[#out + 1] = NpcLink(id, ns:GetNpcName(id)) end
    end
    return out
end
local filtered = {}
local selectedItem

ns.page = 1

-- ------------------------------------------------------------------ helpers
local function Round255(v)
    return math.floor(v * 255 + 0.5)
end

local function QualityRGB(q)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then return Round255(c.r), Round255(c.g), Round255(c.b) end
    return 255, 255, 255
end

local function SetItemButtonIcon(tex, item)
    tex:SetTexture(ns:GetIcon(item))
end

local function ShowItemTooltip(owner, item)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, ns:GetRawLink(item))
    if not ok then
        GameTooltip:AddLine(ns:ColorName(item))
        GameTooltip:AddLine("物品等级 " .. item[F.ILVL] .. " · 需要等级 " .. (item[F.REQ] == 0 and "—" or item[F.REQ]), 0.8, 0.8, 0.8)
        GameTooltip:AddLine(ns:RowStats(item, 6), 1, 1, 1, true)
        local src = ns:GetSourceText(item, 2)
        if src then GameTooltip:AddLine("来源：" .. src, 0.8, 0.8, 0.8, true) end
    end
    GameTooltip:Show()
end

-- ------------------------------------------------------------------ dropdown
local menu, menuOverlay

local function HideMenu()
    if menu then menu:Hide() end
    if menuOverlay then menuOverlay:Hide() end
end

local function EnsureMenu()
    if menu then return end
    menuOverlay = CreateFrame("Frame", nil, UIParent)
    menuOverlay:SetAllPoints(UIParent)
    menuOverlay:EnableMouse(true)
    menuOverlay:SetFrameStrata("FULLSCREEN_DIALOG")
    menuOverlay:Hide()
    menuOverlay:SetScript("OnMouseDown", HideMenu)

    menu = CreateFrame("Frame", "HolyBulwarkMenu", UIParent, "BackdropTemplate")
    menu:SetFrameStrata("TOOLTIP")
    menu:SetClampedToScreen(true)
    menu:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 12,
    })
    menu:SetBackdropColor(0.03, 0.03, 0.03, 0.98)
    menu:SetBackdropBorderColor(0.55, 0.55, 0.55, 1)
    menu.buttons = {}
end

local function ShowMenu(anchor, options, currentValue, onSelect)
    EnsureMenu()
    HideMenu()
    local width = math.max(anchor:GetWidth(), 170)
    menu:SetWidth(width)
    local height = 8
    for i, opt in ipairs(options) do
        local b = menu.buttons[i]
        if not b then
            b = CreateFrame("Button", nil, menu)
            b:SetHeight(22)
            b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            b.text:SetPoint("LEFT", 8, 0)
            b.text:SetPoint("RIGHT", -8, 0)
            b.text:SetJustifyH("LEFT")
            b.bg = b:CreateTexture(nil, "BACKGROUND")
            b.bg:SetAllPoints()
            b.bg:SetColorTexture(1, 1, 1, 0)
            b:SetScript("OnEnter", function(self) self.bg:SetColorTexture(1, 1, 1, 0.12) end)
            b:SetScript("OnLeave", function(self) self.bg:SetColorTexture(1, 1, 1, 0) end)
            menu.buttons[i] = b
        end
        local btn = b
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", 6, -4 - (i - 1) * 22)
        btn:SetPoint("TOPRIGHT", -6, -4 - (i - 1) * 22)
        local mark = (opt.value == currentValue) and "|cff33ff99*|r " or "  "
        btn.text:SetText(mark .. opt.label)
        btn:SetScript("OnClick", function()
            HideMenu()
            onSelect(opt.value, opt.label)
        end)
        btn:Show()
        height = height + 22
    end
    for i = #options + 1, #menu.buttons do menu.buttons[i]:Hide() end
    menu:SetHeight(height)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    menu:Show()
    menuOverlay:Show()
    menu:Raise()
end

local function FindLabel(options, value)
    for _, opt in ipairs(options) do
        if opt.value == value then return opt.label end
    end
    return options[1] and options[1].label or ""
end

local function CreateDropdown(parent, x, y, width, prefix, options, onSelect)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 24)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    b:SetText("")
    b.prefix = prefix
    b.options = options
    b.current = options[1].value
    b.valueText = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.valueText:SetPoint("LEFT", 10, 0)
    b.valueText:SetPoint("RIGHT", -10, 0)
    b.valueText:SetJustifyH("LEFT")
    b.valueText:SetWordWrap(false)
    b.valueText:SetFontObject(GameFontNormalSmall)
    b.valueText:SetText(prefix .. "：" .. options[1].label)
    b:SetScript("OnClick", function(self)
        ShowMenu(self, self.options, self.current, function(value, label)
            self.current = value
            self.valueText:SetText(self.prefix .. "：" .. label)
            onSelect(value)
        end)
    end)
    return b
end

local function SetDropdownValue(btn, value)
    btn.current = value
    btn.valueText:SetText(btn.prefix .. "：" .. FindLabel(btn.options, value))
end

local function ListHas(list, value)
    if type(list) ~= "table" then return false end
    for i = 1, #list do
        if list[i] == value then return true end
    end
    return false
end

local function MultiLabel(prefix, options, list)
    if #list == 0 then return prefix .. "：全部" end
    if #list == 1 then return prefix .. "：" .. FindLabel(options, list[1]) end
    return prefix .. "：" .. #list .. "项"
end

local function ShowMultiMenu(anchor, options, selected, onChange)
    EnsureMenu()
    local width = math.max(anchor:GetWidth(), 190)
    menu:SetWidth(width)
    local height = 8
    local RefreshAll
    for i, opt in ipairs(options) do
        local b = menu.buttons[i]
        if not b then
            b = CreateFrame("Button", nil, menu)
            b:SetHeight(22)
            b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            b.text:SetPoint("LEFT", 8, 0)
            b.text:SetPoint("RIGHT", -8, 0)
            b.text:SetJustifyH("LEFT")
            b.bg = b:CreateTexture(nil, "BACKGROUND")
            b.bg:SetAllPoints()
            b.bg:SetColorTexture(1, 1, 1, 0)
            b:SetScript("OnEnter", function(self) self.bg:SetColorTexture(1, 1, 1, 0.12) end)
            b:SetScript("OnLeave", function(self) self.bg:SetColorTexture(1, 1, 1, 0) end)
            menu.buttons[i] = b
        end
        local btn = b
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", 6, -4 - (i - 1) * 22)
        btn:SetPoint("TOPRIGHT", -6, -4 - (i - 1) * 22)
        btn:SetScript("OnClick", function()
            if opt.value == "all" then
                for j = #selected, 1, -1 do table.remove(selected, j) end
            elseif ListHas(selected, opt.value) then
                for j = #selected, 1, -1 do
                    if selected[j] == opt.value then table.remove(selected, j) end
                end
            else
                selected[#selected + 1] = opt.value
            end
            RefreshAll()
            onChange()
        end)
        btn:Show()
        height = height + 22
    end
    for i = #options + 1, #menu.buttons do menu.buttons[i]:Hide() end
    RefreshAll = function()
        for i, opt in ipairs(options) do
            local btn = menu.buttons[i]
            local checked
            if opt.value == "all" then
                checked = (#selected == 0)
            else
                checked = ListHas(selected, opt.value)
            end
            btn.text:SetText((checked and "|cff33ff99[x]|r " or "[ ] ") .. opt.label)
        end
    end
    RefreshAll()
    menu:SetHeight(height)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    menu:Show()
    menuOverlay:Show()
    menu:Raise()
end

local function CreateMultiDropdown(parent, x, y, width, prefix, options, getList, onChange)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 24)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    b:SetText("")
    b.prefix = prefix
    b.options = options
    b.valueText = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.valueText:SetPoint("LEFT", 10, 0)
    b.valueText:SetPoint("RIGHT", -10, 0)
    b.valueText:SetJustifyH("LEFT")
    b.valueText:SetWordWrap(false)
    b.valueText:SetFontObject(GameFontNormalSmall)
    b.valueText:SetText(MultiLabel(prefix, options, getList()))
    b:SetScript("OnClick", function(self)
        ShowMultiMenu(self, options, getList(), function()
            self.valueText:SetText(MultiLabel(prefix, options, getList()))
            onChange()
        end)
    end)
    b.refresh = function()
        b.valueText:SetText(MultiLabel(prefix, options, getList()))
    end
    return b
end

-- ------------------------------------------------------------------ refresh
local function BuildDetailBody(item)
    local lines = {}
    lines[#lines + 1] = "|cffffd200属性|r"
    local stats = item[F.STATS]
    for _, key in ipairs(ns.DETAIL_STATS) do
        local v = stats[key]
        if v and v ~= 0 then
            lines[#lines + 1] = ns:StatLine(key, v)
        end
    end
    local dmg = item[F.DMG]
    if dmg then
        lines[#lines + 1] = ""
        lines[#lines + 1] = string.format("|cffffd200武器|r  %s-%s  速度 %s  秒伤 %s",
            ns.Num(dmg[1] or 0), ns.Num(dmg[2] or 0), ns.Num(dmg[3] or 0), ns.Num(dmg[4] or 0))
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "|cffffd200来源|r"
    local srcs = item[F.SOURCES]
    if not srcs or #srcs == 0 then
        lines[#lines + 1] = "|cff888888数据库暂缺（可能尚未开放或尚未记录）|r"
    else
        for i = 1, #srcs do
            lines[#lines + 1] = ns:FormatSource(srcs[i])
            if srcs[i][1] == "quest" then
                local info = ns:GetQuestInfo(tonumber(srcs[i][5]))
                if info and info.npcID then
                    local tail = ""
                    if info.zoneName then tail = tail .. " · " .. info.zoneName end
                    if info.x and info.y then tail = tail .. string.format(" · %.1f, %.1f", info.x * 100, info.y * 100) end
                    lines[#lines + 1] = "|cff999999  接取 NPC：|r" .. NpcLink(info.npcID, info.npcName) .. tail
                elseif info and info.extra and info.extra.s then
                    lines[#lines + 1] = "|cff999999  接取地点：|r" .. QLocLink(tonumber(srcs[i][5]), "s", "地图标点")
                end
                if info and info.enderID then
                    local tail = ""
                    if info.enderZone then tail = tail .. " · " .. info.enderZone end
                    lines[#lines + 1] = "|cff999999  交付 NPC：|r" .. NpcLink(info.enderID, info.enderName) .. tail
                elseif info and info.extra and info.extra.e then
                    lines[#lines + 1] = "|cff999999  交付地点：|r" .. QLocLink(tonumber(srcs[i][5]), "e", "地图标点")
                end
                if info and info.itemID then
                    lines[#lines + 1] = "|cff999999  起始物品：" .. (info.itemName or ("#" .. info.itemID)) .. "|r"
                    if info.monsters and #info.monsters > 0 then
                        local names = {}
                        for m = 1, math.min(#info.monsters, 12) do
                            local mon = info.monsters[m]
                            names[#names + 1] = NpcLink(mon.id, mon.name)
                        end
                        lines[#lines + 1] = "|cff999999  掉落怪物：" .. table.concat(names, "、") .. "|r"
                    end
                end
                local chain = info and info.chain
                if type(chain) == "table" and #chain > 1 then
                    lines[#lines + 1] = ""
                    lines[#lines + 1] = "|cffffd200任务链（" .. #chain .. " 步）|r"
                    local flags, anyCompleted = {}, false
                    for idx, cid in ipairs(chain) do
                        local c, l = ns:GetQuestStatus(cid)
                        flags[idx] = { c = c, l = l }
                        if c then anyCompleted = true end
                    end
                    local nextMarked = false
                    for idx, cid in ipairs(chain) do
                        local ci = ns:GetQuestInfo(cid)
                        local cname = (ci and ci.name) or ("任务 #" .. cid)
                        local st = flags[idx]
                        local mark
                        if st.c then
                            mark = "|cff33ff99[已完成]|r"
                        elseif st.l then
                            mark = "|cffffd200[当前（已接）]|r"
                        elseif anyCompleted and not nextMarked then
                            mark = "|cffffd200[下一步]|r"
                            nextMarked = true
                        else
                            mark = "|cff777777[未完成]|r"
                        end
                        local line = string.format("%s %d. %s", mark, idx, QuestLink(cid, cname))
                        local extra = {}
                        if ci and ci.npcID then extra[#extra + 1] = NpcLink(ci.npcID, ci.npcName or ("人物 #" .. ci.npcID)) end
                        if ci and ci.zoneName then extra[#extra + 1] = ci.zoneName end
                        if #extra > 0 then line = line .. " · " .. table.concat(extra, " · ") end
                        if cid == tonumber(srcs[i][5]) then line = line .. "  |cff33ff99· 本物品任务|r" end
                        lines[#lines + 1] = line
                    end
                    lines[#lines + 1] = "|cff777777点击任务名查看描述、目标、接取/交付 NPC 与任务品位置；点击 NPC 名可直接标图。|r"
                end
            end
            if srcs[i][1] == "craft" then
                local rname, rid, rsrc = srcs[i][11], srcs[i][12], srcs[i][13]
                if rname then
                    lines[#lines + 1] = "|cff999999  配方物品：" .. rname .. (rid and (" #" .. rid) or "") .. "|r"
                else
                    lines[#lines + 1] = "|cff999999  配方来源：训练师学习（未找到配方物品）|r"
                end
                local vendors = rid and ns:GetRecipeVendors(rid) or {}
                local vendorCount = 0
                for _, v in ipairs(vendors) do
                    if v.kind == "Vendor" then
                        if vendorCount == 0 then lines[#lines + 1] = "|cff999999  图纸商人：|r" end
                        vendorCount = vendorCount + 1
                        local tail = {}
                        if v.zone then tail[#tail + 1] = v.zone end
                        if v.x and v.y then tail[#tail + 1] = string.format("%.1f, %.1f", v.x * 100, v.y * 100) end
                        local line = "    " .. NpcLink(v.npcID, v.name) .. " " .. PinLink("npc", v.npcID, "标出")
                        if #tail > 0 then line = line .. " · " .. table.concat(tail, " · ") end
                        lines[#lines + 1] = line
                    end
                end
                if vendorCount == 0 then
                    local shown = 0
                    for _, v in ipairs(vendors) do
                        if shown >= 4 then break end
                        local label = (v.kind == "Chest") and "图纸宝箱" or "图纸掉落"
                        if shown == 0 then
                            lines[#lines + 1] = "|cff999999  " .. (rsrc or "图纸来源") .. "：|r"
                        end
                        shown = shown + 1
                        local tail = {}
                        if v.zone then tail[#tail + 1] = v.zone end
                        if v.x and v.y then tail[#tail + 1] = string.format("%.1f, %.1f", v.x * 100, v.y * 100) end
                        local line = "    " .. label .. " " .. NpcLink(v.npcID, v.name)
                        if #tail > 0 then line = line .. " · " .. table.concat(tail, " · ") end
                        lines[#lines + 1] = line
                    end
                    if shown == 0 then
                        if rsrc then
                            lines[#lines + 1] = "|cff999999  图纸来源：" .. rsrc .. "|r"
                        else
                            lines[#lines + 1] = "|cff888888  图纸商人：暂无可靠数据（点击“地图标记”可查看已记录位置）|r"
                        end
                    end
                end
            end
        end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format("|cff777777物品编号 %d · 数据来自永远纪元数据库|r", item[F.ID])
    return table.concat(lines, "\n")
end

local function ShowDetail(item)
    if not detail then return end
    selectedItem = item
    if not item then
        detailIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        detailName:SetText("")
        detailEn:SetText("")
        detailSub1:SetText("")
        detailSub2:SetText("")
        detailBody:SetText("")
        detailContent:SetHeight(1)
        if detailMap then detailMap:SetEnabled(false) end
        return
    end
    detailIcon:SetTexture(ns:GetIcon(item))
    detailName:SetText(ns:ColorName(item))
    detailEn:SetText("")
    local rl = item[F.REQ]
    local qlv = ns:GetItemQuestLevel(item)
    local ilvlText
    if qlv then
        ilvlText = "任务等级 " .. qlv
    elseif item[F.ILVL] and item[F.ILVL] > 0 then
        ilvlText = "物品等级 " .. item[F.ILVL]
    else
        ilvlText = "物品等级 —"
    end
    detailSub1:SetText(string.format("%s · %s", ilvlText, rl == 0 and "无等级要求" or ("需要等级 " .. rl)))
    local parts = {}
    parts[#parts + 1] = ns.TYPE_NAMES[item[F.TYPE]] or item[F.TYPE]
    if item[F.ARMOR] then parts[#parts + 1] = "护甲 " .. ns.Num(item[F.ARMOR]) end
    local bind = item[F.BIND]
    if bind and bind > 0 and ns.BIND_NAMES[bind] then parts[#parts + 1] = ns.BIND_NAMES[bind] end
    detailSub2:SetText(table.concat(parts, " · "))
    detailBody:SetText(BuildDetailBody(item))
    detailContent:SetHeight(math.max(1, detailBody:GetStringHeight() + 10))
    detailScroll:SetVerticalScroll(0)
    if detailMap then detailMap:SetEnabled(ns:FindMapSource(item) and true or false) end
end

local function UpdateRows()
    ns.lastRowError = nil
    local startIdx = (ns.page - 1) * ROWS
    for i = 1, ROWS do
        local row = rows[i]
        local item = filtered[startIdx + i]
        row.item = item
        if item then
            ns.lastRowId = item[F.ID]
            local rowOk, rowErr = pcall(function()
                SetItemButtonIcon(row.icon, item)
                row.name:SetText(ns:ColorName(item))
                row.level:SetText(item[F.REQ] == 0 and "—" or tostring(item[F.REQ]))
                row.stats:SetText(ns:RowStats(item, 3))
                local srcs = item[F.SOURCES] or {}
                for t = 1, 3 do row.tags[t]:SetText("") end
                if #srcs == 0 then
                    row.tags[1]:SetText("?")
                    row.tags[1]:SetTextColor(0.5, 0.5, 0.5)
                else
                    for t = 1, math.min(#srcs, 3) do
                        local info = ns.SOURCE_KINDS[srcs[t][1]]
                        row.tags[t]:SetText(info and info.short or "?")
                        row.tags[t]:SetTextColor((info and info.r or 0.8), (info and info.g or 0.8), (info and info.b or 0.8))
                    end
                end
                if selectedItem == item then row.sel:Show() else row.sel:Hide() end
                row:Show()
            end)
            if not rowOk then
                ns.lastRowError = ("item %s: %s"):format(tostring(item[F.ID]), tostring(rowErr))
                row:Hide()
            end
        else
            row:Hide()
        end
    end
    local maxPage = math.max(1, math.ceil(#filtered / ROWS))
    if ns.page > maxPage then ns.page = maxPage end
    if pageLabel then pageLabel:SetText(string.format("第 %d / %d 页", ns.page, maxPage)) end
    if countLabel then
        local known = 0
        for i = 1, #filtered do
            if filtered[i][F.KNOWN] == 1 then known = known + 1 end
        end
        countLabel:SetText(string.format("共 %d 件 · 有来源 %d 件 · 库 %d 件", #filtered, known, #ns.data.items))
    end
end

function ns:Refresh()
    if not frame then return end
    self.page = self.page or 1
    local ok, res = pcall(self.GetFiltered, self)
    if not ok then
        self.lastError = tostring(res)
        filtered = {}
        UpdateRows()
        if countLabel then countLabel:SetText("|cffff5555筛选出错，见 /spg diag|r") end
        return
    end
    self.lastError = nil
    filtered = res
    local shown, showErr = pcall(UpdateRows)
    if not shown then
        self.lastError = tostring(showErr)
        if countLabel then countLabel:SetText("|cffff5555显示错误：" .. tostring(showErr):sub(1, 90)) end
        self:Print("|cffff5555显示错误：" .. tostring(showErr))
        return
    end
    if countLabel and #self.data.items == 0 then
        countLabel:SetText("|cffff5555数据库未加载|r")
    end
end

local function ResetPageAndRefresh()
    ns.page = 1
    ns:Refresh()
end

-- ------------------------------------------------------------------ controls
local function SyncControls()
    if not searchBox then return end
    local f = ns.db.filters
    searchBox:SetText(f.search or "")
    minBox:SetText(tostring(f.minLevel or 10))
    maxBox:SetText(tostring(f.maxLevel or 60))
    tankyCB:SetChecked(f.tanky and true or false)
    knownCB:SetChecked(f.knownOnly and true or false)
    for _, b in ipairs(ns.dropdowns or {}) do SetDropdownValue(b.btn, f[b.key]) end
    for _, d in ipairs(ns.multiDropdowns or {}) do
        if d.btn.refresh then d.btn.refresh() end
    end
end

local function CreateControls(parent)
    -- search
    searchBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    searchBox:SetSize(190, 24)
    searchBox:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, -44)
    searchBox:SetAutoFocus(false)
    searchBox:SetFontObject(GameFontHighlightSmall)
    searchBox:SetTextInsets(8, 8, 0, 0)
    searchBox:SetMaxLetters(60)
    local ph = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ph:SetPoint("LEFT", 10, 0)
    ph:SetText("搜索名称 / 物品ID / 来源")
    searchBox.placeholder = ph
    searchBox:SetScript("OnTextChanged", function(self, userInput)
        ph:SetShown((self:GetText() or "") == "")
        if not userInput then return end
        ns.db.filters.search = self:GetText() or ""
        ResetPageAndRefresh()
    end)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    -- level boxes
    local ApplyLevels
    local function MakeLevelBox(x)
        local b = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
        b:SetSize(38, 24)
        b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -44)
        b:SetAutoFocus(false)
        b:SetFontObject(GameFontHighlightSmall)
        b:SetTextInsets(6, 6, 0, 0)
        b:SetMaxLetters(2)
        b:SetNumeric(true)
        b:SetScript("OnEnterPressed", function(self) self:ClearFocus(); ApplyLevels() end)
        b:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        return b
    end
    minBox = MakeLevelBox(742)
    maxBox = MakeLevelBox(798)
    ApplyLevels = function()
        local mn = tonumber(minBox:GetText()) or 10
        local mx = tonumber(maxBox:GetText()) or 60
        mn = math.max(1, math.min(60, math.floor(mn)))
        mx = math.max(1, math.min(60, math.floor(mx)))
        if mn > mx then mn, mx = mx, mn end
        minBox:SetText(tostring(mn))
        maxBox:SetText(tostring(mx))
        ns.db.filters.minLevel = mn
        ns.db.filters.maxLevel = mx
        ResetPageAndRefresh()
    end
    local lvlLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lvlLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 706, -50)
    lvlLabel:SetText("等级")
    local dash = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dash:SetPoint("TOPLEFT", parent, "TOPLEFT", 783, -50)
    dash:SetText("—")

    local queryBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    queryBtn:SetSize(54, 24)
    queryBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", 842, -44)
    queryBtn:SetText("查询")
    queryBtn:SetScript("OnClick", function() ApplyLevels() end)

    -- checkboxes
    local function MakeCheck(x, label, key)
        local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        cb:SetSize(22, 22)
        cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -74)
        local t = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        t:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        t:SetText(label)
        cb:SetScript("OnClick", function(self)
            ns.db.filters[key] = self:GetChecked() and true or false
            ResetPageAndRefresh()
        end)
        return cb
    end
    tankyCB = MakeCheck(140, "只看有耐力", "tanky")
    knownCB = MakeCheck(260, "只看有来源", "knownOnly")

    countLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countLabel:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -28, -80)
    countLabel:SetJustifyH("RIGHT")
    countLabel:SetText("共 0 件")

    -- dropdowns
    ns.dropdowns = {}
    local slotOptions = { { value = "all", label = "全部" } }
    for _, key in ipairs(ns.SLOT_ORDER) do
        slotOptions[#slotOptions + 1] = { value = key, label = ns.SLOT_NAMES[key] }
    end
    local armorOptions = {
        { value = "tank", label = "防骑向" },
        { value = "all", label = "全部" },
        { value = "Plate", label = "板甲" },
        { value = "Mail", label = "锁甲" },
        { value = "Leather", label = "皮甲" },
        { value = "Cloth", label = "布甲" },
        { value = "Shield", label = "盾牌" },
        { value = "jewel", label = "首饰" },
        { value = "weapon", label = "武器" },
    }
    local sourceOptions = {
        { value = "all", label = "全部" },
        { value = "drop", label = "掉落" },
        { value = "quest", label = "任务" },
        { value = "vendor", label = "出售" },
        { value = "craft", label = "制造" },
        { value = "object", label = "宝箱" },
        { value = "world", label = "世界" },
        { value = "unknown", label = "未知" },
    }
    local qualityOptions = {
        { value = "all", label = "全部" },
        { value = "2", label = "优秀" },
        { value = "3", label = "精良" },
        { value = "4", label = "史诗" },
        { value = "5", label = "传说" },
    }
    local sortOptions = {
        { value = "level", label = "等级" },
        { value = "ilvl", label = "物品等级" },
        { value = "sp", label = "法强" },
        { value = "name", label = "名称" },
    }
    local slotBtn = CreateMultiDropdown(parent, 216, -44, 110, "部位", slotOptions,
        function() return ns.db.filters.slot end, ResetPageAndRefresh)
    local armorBtn = CreateMultiDropdown(parent, 332, -44, 134, "护甲", armorOptions,
        function() return ns.db.filters.armor end, ResetPageAndRefresh)
    local sourceBtn = CreateMultiDropdown(parent, 472, -44, 112, "来源", sourceOptions,
        function() return ns.db.filters.source end, function()
            if ListHas(ns.db.filters.source, "unknown") then
                ns.db.filters.knownOnly = false
                if knownCB then knownCB:SetChecked(false) end
            end
            ResetPageAndRefresh()
        end)
    local qualityBtn = CreateMultiDropdown(parent, 590, -44, 110, "品质", qualityOptions,
        function() return ns.db.filters.quality end, ResetPageAndRefresh)
    local sortBtn = CreateDropdown(parent, 20, -74, 110, "排序", sortOptions, function(v)
        ns.db.filters.sort = v; ResetPageAndRefresh()
    end)
    ns.dropdowns = { { key = "sort", btn = sortBtn } }
    ns.multiDropdowns = {
        { key = "slot", btn = slotBtn }, { key = "armor", btn = armorBtn },
        { key = "source", btn = sourceBtn }, { key = "quality", btn = qualityBtn },
    }
end

-- ------------------------------------------------------------------ window
local function CreateRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H - 1)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -4 - (index - 1) * ROW_H)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -4, -4 - (index - 1) * ROW_H)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(1, 1, 1, 0.025)

    row.sel = row:CreateTexture(nil, "BACKGROUND")
    row.sel:SetAllPoints()
    row.sel:SetColorTexture(0.15, 0.45, 0.85, 0.30)
    row.sel:Hide()

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", 3, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", 28, 0)
    row.name:SetWidth(205)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.level = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.level:SetPoint("LEFT", 238, 0)
    row.level:SetWidth(36)
    row.level:SetJustifyH("RIGHT")

    row.stats = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.stats:SetPoint("LEFT", 284, 0)
    row.stats:SetWidth(238)
    row.stats:SetJustifyH("LEFT")
    row.stats:SetWordWrap(false)

    row.tags = {}
    for i = 1, 3 do
        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("RIGHT", -6 - (3 - i) * 20, 0)
        fs:SetWidth(20)
        fs:SetJustifyH("CENTER")
        fs:SetWordWrap(false)
        row.tags[i] = fs
    end

    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", function(_, delta)
        local maxPage = math.max(1, math.ceil(#filtered / ROWS))
        if delta > 0 then ns.page = math.max(1, ns.page - 1)
        elseif delta < 0 then ns.page = math.min(maxPage, ns.page + 1) end
        UpdateRows()
    end)
    row:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(1, 1, 1, 0.09)
        if self.item then ShowItemTooltip(self, self.item) end
    end)
    row:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(1, 1, 1, 0.025)
        GameTooltip:Hide()
    end)
    row:SetScript("OnClick", function(self)
        if not self.item then return end
        if IsControlKeyDown and IsControlKeyDown() then
            DressUpItemLink(ns:GetLink(self.item))
            return
        end
        if IsShiftKeyDown and IsShiftKeyDown() then
            ns:InsertLink(self.item)
            return
        end
        ShowDetail(self.item)
        UpdateRows()
    end)
    return row
end

local function CreateWindow()
    frame = CreateFrame("Frame", "HolyBulwarkFrame", UIParent, "BasicFrameTemplate")
    frame:SetSize(960, 600)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        ns.db.position = { point = point, relPoint = relPoint, x = x, y = y }
    end)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetToplevel(true)
    tinsert(UISpecialFrames, "HolyBulwarkFrame")

    local title = frame.TitleText or _G[frame:GetName() .. "TitleText"]
    if not title then
        title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", frame, "TOP", 0, -6)
    end
    title:SetText("圣光壁垒")

    if ns.db and ns.db.position then
        local p = ns.db.position
        frame:ClearAllPoints()
        frame:SetPoint(p.point or "CENTER", UIParent, p.relPoint or p.point or "CENTER", p.x or 0, p.y or 0)
    end

    CreateControls(frame)

    -- list
    listFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    listFrame:SetPoint("TOPLEFT", 16, -104)
    listFrame:SetSize(600, ROWS * ROW_H + 8)
    listFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 12,
    })
    listFrame:SetBackdropColor(0, 0, 0, 0.35)
    listFrame:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
    listFrame:EnableMouseWheel(true)
    listFrame:SetScript("OnMouseWheel", function(_, delta)
        local maxPage = math.max(1, math.ceil(#filtered / ROWS))
        if delta > 0 then ns.page = math.max(1, ns.page - 1)
        elseif delta < 0 then ns.page = math.min(maxPage, ns.page + 1) end
        UpdateRows()
    end)

    rows = {}
    for i = 1, ROWS do rows[i] = CreateRow(listFrame, i) end

    -- detail
    detail = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    detail:SetPoint("TOPLEFT", 628, -104)
    detail:SetSize(316, ROWS * ROW_H + 8)
    detail:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 12,
    })
    detail:SetBackdropColor(0, 0, 0, 0.35)
    detail:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)

    detailIcon = detail:CreateTexture(nil, "ARTWORK")
    detailIcon:SetSize(38, 38)
    detailIcon:SetPoint("TOPLEFT", 10, -10)
    detailIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    detailName = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    detailName:SetPoint("TOPLEFT", 56, -10)
    detailName:SetWidth(248)
    detailName:SetJustifyH("LEFT")
    detailName:SetWordWrap(false)

    detailEn = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detailEn:SetPoint("TOPLEFT", 56, -28)
    detailEn:SetWidth(248)
    detailEn:SetJustifyH("LEFT")
    detailEn:SetWordWrap(false)

    detailSub1 = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    detailSub1:SetPoint("TOPLEFT", 10, -52)
    detailSub1:SetWidth(294)
    detailSub1:SetJustifyH("LEFT")

    detailSub2 = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    detailSub2:SetPoint("TOPLEFT", 10, -68)
    detailSub2:SetWidth(294)
    detailSub2:SetJustifyH("LEFT")
    detailSub2:SetTextColor(0.75, 0.75, 0.75)

    detailScroll = CreateFrame("ScrollFrame", "HolyBulwarkDetailScroll", detail, "UIPanelScrollFrameTemplate")
    detailScroll:SetPoint("TOPLEFT", 10, -88)
    detailScroll:SetPoint("BOTTOMRIGHT", -32, 40)
    detailContent = CreateFrame("Frame", nil, detailScroll)
    detailContent:SetWidth(272)
    if detailContent.SetHyperlinksEnabled then
        detailContent:SetHyperlinksEnabled(true)
        detailContent:SetScript("OnHyperlinkClick", function(_, link)
            if HandleSpgLink then HandleSpgLink(link) end
        end)
    end
    detailScroll:SetScrollChild(detailContent)
    detailBody = detailContent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    detailBody:SetPoint("TOPLEFT", 0, 0)
    detailBody:SetWidth(272)
    detailBody:SetJustifyH("LEFT")
    detailBody:SetSpacing(3)

    detailLink = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
    detailLink:SetSize(92, 22)
    detailLink:SetPoint("BOTTOMLEFT", 10, 10)
    detailLink:SetText("插入链接")
    detailLink:SetScript("OnClick", function()
        if selectedItem then ns:InsertLink(selectedItem) end
    end)

    detailMap = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
    detailMap:SetSize(92, 22)
    detailMap:SetPoint("BOTTOMLEFT", detailLink, "BOTTOMLEFT", 100, 0)
    detailMap:SetText("地图标记")
    detailMap:SetScript("OnClick", function(self)
        if not selectedItem then return end
        local points = ns:GetMapPoints(selectedItem)
        if #points == 0 then
            ns:Print("这件装备没有可标记的位置。")
        elseif #points == 1 then
            ns:PinPoint(points[1])
        else
            local options = {}
            for i, p in ipairs(points) do
                options[i] = { value = i, label = p.title .. (p.zone and (" · " .. p.zone) or "") }
            end
            ShowMenu(self, options, nil, function(v) ns:PinPoint(points[v]) end)
        end
    end)
    detailMap:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self:IsEnabled() then
            GameTooltip:AddLine("在地图上标出商人 / 图纸商人 / 任务 NPC 的位置")
        else
            GameTooltip:AddLine("没有可用的商人、图纸或任务位置")
        end
        GameTooltip:Show()
    end)
    detailMap:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- quest detail popup
    questFrame = CreateFrame("Frame", "HolyBulwarkQuestFrame", UIParent, "BasicFrameTemplate")
    questFrame:SetSize(392, 348)
    questFrame:SetPoint("CENTER")
    questFrame:SetFrameStrata("MEDIUM")
    questFrame:SetToplevel(true)
    questFrame.TitleText:SetText("任务详情")
    if UISpecialFrames then
        local found = false
        for _, name in ipairs(UISpecialFrames) do
            if name == "HolyBulwarkQuestFrame" then found = true; break end
        end
        if not found then table.insert(UISpecialFrames, "HolyBulwarkQuestFrame") end
    end

    questScroll = CreateFrame("ScrollFrame", "HolyBulwarkQuestScroll", questFrame, "UIPanelScrollFrameTemplate")
    questScroll:SetPoint("TOPLEFT", 14, -34)
    questScroll:SetPoint("BOTTOMRIGHT", -32, 14)
    questContent = CreateFrame("Frame", nil, questScroll)
    questContent:SetWidth(322)
    if questContent.SetHyperlinksEnabled then
        questContent:SetHyperlinksEnabled(true)
        questContent:SetScript("OnHyperlinkClick", function(_, link)
            if HandleSpgLink then HandleSpgLink(link) end
        end)
    end
    questScroll:SetScrollChild(questContent)
    questBody = questContent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    questBody:SetPoint("TOPLEFT", 0, 0)
    questBody:SetWidth(322)
    questBody:SetJustifyH("LEFT")
    questBody:SetSpacing(3)
    questFrame:Hide()

    ShowQuestDetail = function(questID)
        questID = tonumber(questID)
        if not questID then return end
        local ci = ns:GetQuestInfo(questID)
        local L = {}
        local level = ci and ci.level
        L[#L + 1] = "|cffffd200" .. tostring((ci and ci.name) or ("任务 #" .. questID)) .. "|r"
            .. (level and ("  |cff888888等级 " .. tostring(level) .. "|r") or "")
        L[#L + 1] = ""

        if ci and ci.npcID then
            local tail = ""
            if ci.zoneName then tail = tail .. " · " .. ci.zoneName end
            if ci.x and ci.y then tail = tail .. string.format(" · %.1f, %.1f", ci.x * 100, ci.y * 100) end
            L[#L + 1] = "|cffffd200接取 NPC|r  " .. NpcLink(ci.npcID, ci.npcName) .. tail
        elseif ci and ci.extra and ci.extra.s then
            local mapID, x, y, zoneName = ns:PointFromArea(ci.extra.s.a, ci.extra.s.x, ci.extra.s.y)
            local tail = zoneName and (" · " .. zoneName) or ""
            if x and y then tail = tail .. string.format(" · %.1f, %.1f", x * 100, y * 100) end
            L[#L + 1] = "|cffffd200接取地点|r  " .. QLocLink(questID, "s", "地图标点") .. tail
        elseif ci and ci.itemID then
            L[#L + 1] = "|cffffd200起始物品|r  " .. tostring(ci.itemName or ("#" .. ci.itemID))
        elseif ci and ci.objectID then
            L[#L + 1] = "|cffffd200任务对象|r  #" .. tostring(ci.objectID)
        end

        if ci and ci.enderID then
            local tail = ""
            if ci.enderZone then tail = tail .. " · " .. ci.enderZone end
            if ci.enderX and ci.enderY then tail = tail .. string.format(" · %.1f, %.1f", ci.enderX * 100, ci.enderY * 100) end
            L[#L + 1] = "|cffffd200交付 NPC|r  " .. NpcLink(ci.enderID, ci.enderName) .. tail
        elseif ci and ci.extra and ci.extra.e then
            local mapID, x, y, zoneName = ns:PointFromArea(ci.extra.e.a, ci.extra.e.x, ci.extra.e.y)
            local tail = zoneName and (" · " .. zoneName) or ""
            if x and y then tail = tail .. string.format(" · %.1f, %.1f", x * 100, y * 100) end
            L[#L + 1] = "|cffffd200交付地点|r  " .. QLocLink(questID, "e", "地图标点") .. tail
        end

        L[#L + 1] = ""
        L[#L + 1] = "|cffffd200任务描述 / 目标|r"
        local objHasZh = false
        if ci and ci.objectives then
            for _, s in ipairs(ci.objectives) do
                if tostring(s):find("[\128-\255]") then objHasZh = true; break end
            end
        end
        if ci and ci.objectives and #ci.objectives > 0 and (objHasZh or (GetLocale and GetLocale():sub(1, 2) == "en")) then
            for _, s in ipairs(ci.objectives) do
                L[#L + 1] = "· " .. tostring(s)
            end
        elseif ci and ci.objectiveEn and GetLocale and GetLocale():sub(1, 2) == "en" then
            L[#L + 1] = "· " .. tostring(ci.objectiveEn)
        else
            L[#L + 1] = "|cff888888暂无中文任务目标文本（需要 QuestieDB）|r"
        end

        local raw = ci and ci.objectivesRaw
        if raw then
            local items = raw[3] or {}
            if next(items) then
                L[#L + 1] = ""
                L[#L + 1] = "|cffffd200任务品|r"
                for _, o in pairs(items) do
                    local iid = type(o) == "table" and tonumber(o[1]) or nil
                    if iid then
                        L[#L + 1] = "· " .. ItemName(iid)
                        local idb = _G.ItemDB
                        if idb and idb.Get then
                            local okN, drops = pcall(idb.Get, idb, iid, "npcDrops")
                            if okN and type(drops) == "table" and #drops > 0 then
                                local links = {}
                                for i = 1, math.min(#drops, 10) do
                                    local mid = tonumber(drops[i])
                                    if mid then links[#links + 1] = NpcLink(mid, ns:GetNpcName(mid)) end
                                end
                                if #links > 0 then L[#L + 1] = "  |cff999999掉落：|r" .. table.concat(links, "、") end
                            end
                            local okO, odrops = pcall(idb.Get, idb, iid, "objectDrops")
                            if okO and type(odrops) == "table" and #odrops > 0 then
                                local links = {}
                                for i = 1, math.min(#odrops, 6) do
                                    local oid = tonumber(odrops[i])
                                    if oid then links[#links + 1] = ObjectLink(oid, ns:GetObjectName(oid)) end
                                end
                                if #links > 0 then L[#L + 1] = "  |cff999999容器：|r" .. table.concat(links, "、") end
                            end
                        end
                    end
                end
            end

            local creatures = raw[1] or {}
            if next(creatures) then
                L[#L + 1] = ""
                L[#L + 1] = "|cffffd200击杀目标|r"
                local links = {}
                for _, o in pairs(creatures) do
                    local id = type(o) == "table" and tonumber(o[1]) or nil
                    if id then links[#links + 1] = NpcLink(id, ns:GetNpcName(id)) end
                end
                if #links > 0 then L[#L + 1] = table.concat(links, "、") end
            end

            local objects = raw[2] or {}
            if next(objects) then
                L[#L + 1] = ""
                L[#L + 1] = "|cffffd200任务对象|r"
                local links = {}
                for _, o in pairs(objects) do
                    local id = type(o) == "table" and tonumber(o[1]) or nil
                    if id then links[#links + 1] = ObjectLink(id, ns:GetObjectName(id)) end
                end
                if #links > 0 then L[#L + 1] = table.concat(links, "、") end
            end
        end

        if ci and ci.steps and #ci.steps > 0 then
            L[#L + 1] = ""
            L[#L + 1] = "|cffffd200任务品位置|r"
            for i, st in ipairs(ci.steps) do
                local mapID, sx, sy, zoneName = ns:PointFromArea(st.a, st.x, st.y)
                local label = ChineseItemFromEnglish(st.n) or ("任务品位置 " .. i)
                local tail = {}
                if zoneName then tail[#tail + 1] = zoneName end
                if sx and sy then tail[#tail + 1] = string.format("%.1f, %.1f", sx * 100, sy * 100) end
                local line = "· " .. StepLink(questID, i, label)
                if #tail > 0 then line = line .. " · " .. table.concat(tail, " · ") end
                L[#L + 1] = line
                if st.m and #st.m > 0 then
                    local links = MobLinks(st.m, 8)
                    if #links > 0 then L[#L + 1] = "  |cff999999掉落：|r" .. table.concat(links, "、") end
                end
            end
        end

        if ci and ci.need and #ci.need > 0 and not (raw and raw[3] and next(raw[3])) then
            L[#L + 1] = ""
            L[#L + 1] = "|cffffd200所需物品|r"
            for _, n in ipairs(ci.need) do
                local cnt = tonumber(n[2])
                L[#L + 1] = "· " .. ItemName(n[1]) .. (cnt and cnt > 1 and (" ×" .. cnt) or "")
            end
        end

        L[#L + 1] = ""
        L[#L + 1] = "|cff777777点击蓝色名称打开地图并标点；点击任务名继续查看下一段任务；按 Esc 关闭。|r"

        questBody:SetText(table.concat(L, "\n"))
        local h = questBody:GetStringHeight() or 0
        questContent:SetHeight(math.max(h + 8, 10))
        questScroll:SetVerticalScroll(0)
        questFrame:Show()
        questFrame:Raise()
    end

    HandleSpgLink = function(link)
        if not link then return end
        local kind, id = tostring(link):match("^spg:(%w+):(.+)$")
        if not kind then return end
        if kind == "npc" then
            ns:PinNpc(tonumber(id))
        elseif kind == "quest" then
            ShowQuestDetail(tonumber(id))
        elseif kind == "object" then
            ns:PinObject(tonumber(id))
        elseif kind == "qloc" then
            local qid, which = id:match("^(%d+):(%a+)$")
            if qid then ns:PinQuestLoc(tonumber(qid), which) end
        elseif kind == "step" then
            local qid, index = id:match("^(%d+):(%d+)$")
            if qid then ns:PinQuestStep(tonumber(qid), tonumber(index)) end
        end
    end

    ns.lowerForMap = function()
        if frame then frame:SetFrameStrata("BACKGROUND") end
        if questFrame then questFrame:SetFrameStrata("BACKGROUND") end
    end
    ns.restoreForMap = function()
        if frame then frame:SetFrameStrata("MEDIUM") end
        if questFrame then questFrame:SetFrameStrata("MEDIUM") end
    end

    local function HookWorldMap()
        local wm = WorldMapFrame
        if not wm or wm.hbHooked then return end
        wm.hbHooked = true
        wm:HookScript("OnShow", function() ns.lowerForMap() end)
        wm:HookScript("OnHide", function() ns.restoreForMap() end)
    end
    HookWorldMap()
    if C_Timer and C_Timer.After then
        C_Timer.After(2, HookWorldMap)
        C_Timer.After(5, function()
            if ns.BuildRawNameIndex and _G.NpcDB then ns:BuildRawNameIndex(_G.NpcDB, "rawNpcNameIndex") end
        end)
        C_Timer.After(8, function()
            if ns.BuildRawNameIndex and _G.ItemDB then ns:BuildRawNameIndex(_G.ItemDB, "rawItemNameIndex") end
        end)
        C_Timer.After(11, function()
            if ns.BuildRawNameIndex and _G.ObjectDB then ns:BuildRawNameIndex(_G.ObjectDB, "rawObjectNameIndex") end
        end)
    end
    local hookFrame = CreateFrame("Frame")
    hookFrame:RegisterEvent("ADDON_LOADED")
    hookFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    hookFrame:SetScript("OnEvent", function(_, event, name)
        if event == "ADDON_LOADED" then
            if name == "Blizzard_WorldMap" then HookWorldMap() end
            if name == "QuestieDB" or name == "Questie" then
                ns.questInfoCache = nil
                ns.rawNpcNameIndex = nil
                ns.rawItemNameIndex = nil
                ns.rawObjectNameIndex = nil
            end
        elseif event == "PLAYER_ENTERING_WORLD" then
            ns.questInfoCache = nil
        end
    end)

    -- footer
    local prev = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    prev:SetSize(34, 22)
    prev:SetPoint("BOTTOMLEFT", 18, 14)
    prev:SetText("<<")
    prev:SetScript("OnClick", function()
        if ns.page > 1 then ns.page = ns.page - 1; UpdateRows() end
    end)

    pageLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pageLabel:SetPoint("LEFT", prev, "RIGHT", 6, 0)
    pageLabel:SetWidth(110)
    pageLabel:SetJustifyH("LEFT")

    local nextBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    nextBtn:SetSize(34, 22)
    nextBtn:SetPoint("LEFT", pageLabel, "RIGHT", 4, 0)
    nextBtn:SetText(">>")
    nextBtn:SetScript("OnClick", function()
        local maxPage = math.max(1, math.ceil(#filtered / ROWS))
        if ns.page < maxPage then ns.page = ns.page + 1; UpdateRows() end
    end)

    local reset = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    reset:SetSize(70, 22)
    reset:SetPoint("BOTTOMLEFT", 240, 14)
    reset:SetText("重置筛选")
    reset:SetScript("OnClick", function()
        for k, v in pairs(ns.defaults) do
            if type(v) == "table" then
                local t = {}
                for i = 1, #v do t[i] = v[i] end
                ns.db.filters[k] = t
            else
                ns.db.filters[k] = v
            end
        end
        SyncControls()
        ResetPageAndRefresh()
    end)

    noteLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    noteLabel:SetPoint("BOTTOMRIGHT", -22, 18)
    noteLabel:SetJustifyH("RIGHT")
    noteLabel:SetText("数据：The Forever Era · 1.60.1.70959 · 客户端 1.60.1")

    frame:SetScript("OnShow", function()
        local ok, err = pcall(function()
            SyncControls()
            ns:Refresh()
            if ns.dataError then
                ShowDetail(nil)
                detailBody:SetText("|cffff5555" .. ns.dataError .. "|r\n\n请确认 Data.lua 在插件目录中，或在聊天框运行 /spg diag 查看状态。")
                detailContent:SetHeight(math.max(1, detailBody:GetStringHeight() + 10))
            elseif not selectedItem and filtered[1] then
                ShowDetail(filtered[1])
            elseif not filtered[1] then
                ShowDetail(nil)
                detailBody:SetText("|cffaaaaaa当前筛选没有结果，点左下角“重置筛选”。|r")
                detailContent:SetHeight(math.max(1, detailBody:GetStringHeight() + 10))
            end
        end)
        if not ok then
            ns:Print("|cffff5555窗口初始化错误：" .. tostring(err))
            if countLabel then countLabel:SetText("|cffff5555" .. tostring(err):sub(1, 90)) end
        elseif #filtered == 0 then
            ns:Diag()
        end
    end)
    frame:SetScript("OnHide", HideMenu)
end

-- ------------------------------------------------------------------ minimap icon
local minimapButton
local ICON = "Interface\\Icons\\Spell_Holy_DevotionAura"

local function UpdateMinimapButtonPosition()
    if not minimapButton then return end
    local angle = math.rad(ns.db.minimapAngle or 220)
    local width = Minimap:GetWidth() or 140
    if width <= 0 then width = 140 end
    local radius = width / 2 + 4
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function CreateMinimapButton()
    if minimapButton or not Minimap then return end
    ns.db.minimapAngle = ns.db.minimapAngle or 220

    local b = CreateFrame("Button", "HolyBulwarkMinimapButton", Minimap)
    b:SetSize(32, 32)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:SetMovable(true)
    b:EnableMouse(true)
    b:RegisterForDrag("LeftButton")

    b.border = b:CreateTexture(nil, "OVERLAY")
    b.border:SetSize(54, 54)
    b.border:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    b.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetSize(20, 20)
    b.bg:SetPoint("CENTER")
    b.bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(18, 18)
    b.icon:SetPoint("CENTER")
    b.icon:SetTexture(ICON)
    b.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)

    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("圣光壁垒")
        GameTooltip:AddLine("左键：打开 / 关闭窗口", 1, 1, 1)
        GameTooltip:AddLine("拖动：调整小地图上的位置", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    b:SetScript("OnDragStart", function(self)
        self.moved = true
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local scale = Minimap:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            if not (mx and my and scale and cx and cy) then return end
            cx, cy = cx / scale, cy / scale
            ns.db.minimapAngle = math.deg(math.atan2(cy - my, cx - mx))
            UpdateMinimapButtonPosition()
        end)
    end)
    b:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        UpdateMinimapButtonPosition()
    end)

    b:SetScript("OnClick", function(self, button)
        if self.moved then
            self.moved = nil
            return
        end
        if button == "LeftButton" then
            ns:Toggle()
        end
    end)

    minimapButton = b
    UpdateMinimapButtonPosition()
    Minimap:HookScript("OnSizeChanged", function() UpdateMinimapButtonPosition() end)
end

local function RegisterCompartment()
    if not AddonCompartmentFrame or not AddonCompartmentFrame.RegisterAddon then return end
    if ns.compartmentRegistered then return end
    ns.compartmentRegistered = true
    local ok = pcall(function()
        AddonCompartmentFrame:RegisterAddon({
            text = "圣光壁垒",
            icon = ICON,
            notCheckable = true,
            func = function() ns:Toggle() end,
            funcOnEnter = function(button)
                GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
                GameTooltip:AddLine("圣光壁垒")
                GameTooltip:AddLine("点击打开 / 关闭窗口", 1, 1, 1)
                GameTooltip:Show()
            end,
            funcOnLeave = function() GameTooltip:Hide() end,
        })
    end)
    if not ok then ns.compartmentRegistered = nil end
end

-- ------------------------------------------------------------------ commands
function ns:Toggle()
    if not self.byId then return end
    local now = GetTime and GetTime() or 0
    if self.lastToggle and now - self.lastToggle < 0.2 then return end
    self.lastToggle = now

    local created = false
    if not frame then
        CreateWindow()
        frame:Hide()
        selectedItem = nil
        ShowDetail(nil)
        created = true
    end

    if created or not frame:IsShown() then
        frame:Show()
        if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPEN then pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPEN) end
    else
        frame:Hide()
        if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_CLOSE then pcall(PlaySound, SOUNDKIT.IG_MAINMENU_CLOSE) end
    end
end

SLASH_SPELLPOWERGEAR1 = "/spg"
SLASH_SPELLPOWERGEAR2 = "/法伤骑"
SLASH_SPELLPOWERGEAR3 = "/fsq"
SLASH_SPELLPOWERGEAR4 = "/hb"
SlashCmdList["SPELLPOWERGEAR"] = function(msg)
    if not ns.byId then return end
    msg = (msg or ""):match("^%s*(.-)%s*$")
    if msg == "diag" then
        ns:Diag()
        return
    end
    if msg ~= "" then
        local id = tonumber(msg)
        if id and ns.byId[id] then
            ns:PrintItem(ns.byId[id])
            return
        end
        ns.db.filters.search = msg
        if frame then SyncControls() end
    end
    ns:Toggle()
    if msg ~= "" and frame then ResetPageAndRefresh() end
end

-- ------------------------------------------------------------------ bootstrap
local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name ~= addonName then return end
        ns:Init()
        if ns.dataError then ns:Print("|cffff5555" .. ns.dataError .. "|r") end
        CreateMinimapButton()
        RegisterCompartment()
    elseif event == "PLAYER_LOGIN" then
        if ns.db then
            CreateMinimapButton()
            RegisterCompartment()
        end
    end
end)
