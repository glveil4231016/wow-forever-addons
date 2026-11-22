local addonName, ns = ...

local function AddSourceLines(tt)
    if not ns.byId then return end
    local _, link = tt:GetItem()
    if not link then return end
    local id = tonumber(link:match("item:(%d+)"))
    if not id then return end
    local item = ns.byId[id]
    if not item or tt.spgShownFor == id then return end
    tt.spgShownFor = id

    tt:AddLine(" ")
    tt:AddLine("|cff33ff99圣光壁垒|r")
    local src = ns:GetSourceText(item, 3)
    if src then
        tt:AddLine("来源：" .. src, 0.85, 0.85, 0.85, true)
    else
        tt:AddLine("来源：数据库暂缺（可在插件窗口查看）", 0.6, 0.6, 0.6, true)
    end
    local armor = item[ns.F.ARMOR]
    if armor then
        tt:AddLine("护甲：" .. ns.Num(armor), 0.75, 0.75, 0.75)
    end
    if item[ns.F.KNOWN] == 0 then
        tt:AddLine("该物品的来源在数据库中暂缺", 0.55, 0.55, 0.55)
    end
end

local function HookTooltip(tt)
    if not tt or tt.spgHooked then return end
    tt.spgHooked = true
    tt:HookScript("OnTooltipSetItem", AddSourceLines)
    tt:HookScript("OnTooltipCleared", function(self) self.spgShownFor = nil end)
end

HookTooltip(GameTooltip)
HookTooltip(ItemRefTooltip)

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, _, name)
    if name == addonName then
        if not ItemRefTooltip then
            -- created lazily by the client on first shift-click
            local ticker = CreateFrame("Frame")
            ticker:SetScript("OnUpdate", function(self)
                if ItemRefTooltip then
                    HookTooltip(ItemRefTooltip)
                    self:SetScript("OnUpdate", nil)
                end
            end)
        end
    end
end)
