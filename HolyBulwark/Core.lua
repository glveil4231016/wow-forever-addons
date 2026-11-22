local addonName, ns = ...

-- Data layout (see Data.lua)
ns.F = {
    ID = 1, NAME = 2, QUALITY = 3, ILVL = 4, REQ = 5, SLOT = 6, TYPE = 7,
    ARMOR = 8, STATS = 9, SOURCES = 10, KNOWN = 11, BIND = 12, DMG = 13, ENAME = 14, ICON = 15,
}
ns.VERSION = "1.9.5"

local F = ns.F

ns.SLOT_ORDER = { "head", "neck", "shoulder", "back", "chest", "wrist", "hands", "waist", "legs", "feet", "finger", "trinket", "shield", "weapon" }
ns.SLOT_NAMES = {
    head = "头部", neck = "颈部", shoulder = "肩部", back = "背部", chest = "胸部",
    wrist = "手腕", hands = "手部", waist = "腰部", legs = "腿部", feet = "脚部",
    finger = "戒指", trinket = "饰品", shield = "盾牌", weapon = "武器", other = "其他",
}
ns.TYPE_NAMES = {
    Cloth = "布甲", Leather = "皮甲", Mail = "锁甲", Plate = "板甲", Shield = "盾牌",
    Miscellaneous = "其他",
    ["One-Hand Sword"] = "单手剑", ["One-Hand Mace"] = "单手锤", ["One-Hand Axe"] = "单手斧",
    ["Two-Hand Sword"] = "双手剑", ["Two-Hand Mace"] = "双手锤", ["Two-Hand Axe"] = "双手斧",
    Polearm = "长柄武器", Staff = "法杖", Dagger = "匕首", ["Fist Weapon"] = "拳套",
    Wand = "魔杖", Bow = "弓", Gun = "枪", Crossbow = "弩", Thrown = "投掷武器",
}
ns.QUALITY_NAMES = { [0] = "粗糙", [1] = "普通", [2] = "优秀", [3] = "精良", [4] = "史诗", [5] = "传说", [6] = "神器" }
ns.QUALITY_HEX = { [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd", [4] = "a335ee", [5] = "ff8000", [6] = "e6cc80" }
ns.BIND_NAMES = { [0] = "", [1] = "拾取绑定", [2] = "装备绑定", [3] = "使用绑定", [4] = "任务物品" }

ns.STAT_FULL = {
    sp = "法术强度", holy = "神圣法术强度", heal = "治疗强度",
    sta = "耐力", int = "智力", str = "力量", agi = "敏捷", spi = "精神",
    crit = "暴击", hit = "命中", spellcrit = "法术暴击", spellhit = "法术命中",
    def = "防御", dodge = "闪避", parry = "招架", block = "格挡", bv = "格挡值",
    mp5 = "每5秒法力", hp5 = "每5秒生命", haste = "急速", exp = "精准",
    ap = "攻击强度", rap = "远程攻击强度", fap = "野性攻击强度",
    spen = "法术穿透", arpen = "护甲穿透", firepen = "火焰穿透", frostpen = "冰霜穿透",
    fr = "火焰抗性", nr = "自然抗性", frr = "冰霜抗性", sr = "暗影抗性",
    ar = "奥术抗性", hr = "神圣抗性", allres = "所有抗性",
    shadow = "暗影法术强度", fire = "火焰法术强度", frost = "冰霜法术强度",
    nature = "自然法术强度", arcane = "奥术法术强度",
    spdemon = "对恶魔法术强度", spundead = "对亡灵法术强度",
    apdemon = "对恶魔攻击强度", apundead = "对亡灵攻击强度", apbeast = "对野兽攻击强度",
    mana = "法力值", hp = "生命值", wdmg = "武器伤害",
}
ns.STAT_SHORT = {
    sp = "法强", holy = "神圣法伤", heal = "治疗",
    sta = "耐", int = "智", str = "力", agi = "敏", spi = "精",
    crit = "暴击", hit = "命中", spellcrit = "法暴", spellhit = "法命",
    def = "防御", dodge = "闪避", parry = "招架", block = "格挡", bv = "格挡值",
    mp5 = "五回", hp5 = "五回血", haste = "急速", exp = "精准",
    ap = "攻强", rap = "远程攻强", fap = "野性攻强",
    spen = "法穿", arpen = "破甲", firepen = "火穿", frostpen = "冰穿",
    fr = "火抗", nr = "自然抗", frr = "冰抗", sr = "暗抗", ar = "奥抗", hr = "神圣抗", allres = "全抗",
    shadow = "暗伤", fire = "火伤", frost = "冰伤", nature = "自然伤", arcane = "奥伤",
    spdemon = "对恶魔法伤", spundead = "对亡灵法伤",
    apdemon = "对恶魔攻强", apundead = "对亡灵攻强", apbeast = "对野兽攻强",
    mana = "法力", hp = "生命", wdmg = "武器伤害",
}
-- Row summary priority: tank / spell damage first.
ns.ROW_STATS = { "sp", "holy", "sta", "int", "str", "agi", "spi", "heal", "crit", "hit",
    "def", "dodge", "parry", "block", "bv", "mp5", "haste", "exp", "spen", "ap",
    "fr", "nr", "frr", "sr", "ar", "hr", "allres", "shadow", "fire", "frost", "nature", "arcane" }
ns.DETAIL_STATS = { "sp", "holy", "heal", "sta", "int", "str", "agi", "spi",
    "crit", "hit", "spellcrit", "spellhit", "def", "dodge", "parry", "block", "bv",
    "mp5", "hp5", "haste", "exp", "spen", "arpen", "firepen", "frostpen",
    "ap", "rap", "fap", "spdemon", "spundead", "apdemon", "apundead", "apbeast",
    "fr", "nr", "frr", "sr", "ar", "hr", "allres", "shadow", "fire", "frost", "nature", "arcane",
    "mana", "hp", "wdmg" }
ns.PCT_STATS = { crit = true, hit = true, spellcrit = true, spellhit = true,
    dodge = true, parry = true, block = true, haste = true }

ns.SOURCE_KINDS = {
    drop   = { label = "掉落", short = "掉", r = 1.00, g = 0.40, b = 0.40 },
    quest  = { label = "任务", short = "任", r = 1.00, g = 0.82, b = 0.20 },
    vendor = { label = "出售", short = "售", r = 0.35, g = 1.00, b = 0.55 },
    craft  = { label = "制造", short = "制", r = 0.40, g = 0.75, b = 1.00 },
    object = { label = "宝箱", short = "箱", r = 0.80, g = 0.55, b = 1.00 },
    item   = { label = "容器", short = "容", r = 0.55, g = 0.85, b = 0.85 },
    world  = { label = "世界掉落", short = "世", r = 0.70, g = 0.70, b = 0.70 },
}

ns.defaults = {
    search = "", slot = {}, armor = { "tank" }, sort = "level",
    minLevel = 10, maxLevel = 60, tanky = true, knownOnly = true,
    source = {}, quality = {},
}

local function Num(v)
    if v == math.floor(v) then return string.format("%d", v) end
    return string.format("%.1f", v)
end
ns.Num = Num

function ns:FormatChance(c)
    if not c or c < 0 then return nil end
    if c > 0 and c < 0.01 then return "<0.01%" end
    if c == math.floor(c) then return string.format("%d%%", c) end
    if c < 1 then return string.format("%.2f%%", c) end
    return string.format("%.1f%%", c)
end

function ns:StatText(key, v)
    local label = self.STAT_SHORT[key] or key
    local val
    if self.PCT_STATS[key] then
        val = "+" .. Num(v) .. "%"
    else
        val = "+" .. Num(v)
    end
    return val .. label
end

function ns:StatLine(key, v)
    local label = self.STAT_FULL[key] or key
    if self.PCT_STATS[key] then
        return label .. " +" .. Num(v) .. "%"
    end
    return label .. " +" .. Num(v)
end

function ns:RowStats(item, maxParts)
    local stats = item[F.STATS]
    local out = {}
    for _, key in ipairs(self.ROW_STATS) do
        local v = stats[key]
        if v and v ~= 0 then
            out[#out + 1] = self:StatText(key, v)
            if #out >= (maxParts or 4) then break end
        end
    end
    return table.concat(out, "  ")
end

function ns:GetName(item)
    return item[F.NAME]
end

function ns:GetRawLink(item)
    local ok, _, link = pcall(GetItemInfo, item[F.ID])
    if ok and link then
        local raw = link:match("|H(item:[^|]+)|h")
        return raw or link
    end
    return "item:" .. item[F.ID] .. ":::::::::"
end

function ns:GetLink(item)
    local ok, _, link = pcall(GetItemInfo, item[F.ID])
    if ok and link and link:sub(1, 2) == "|H" then return link end
    return "|H" .. self:GetRawLink(item) .. "|h[" .. self:GetName(item) .. "]|h"
end

function ns:InsertLink(item)
    local link = self:GetLink(item)
    local edit = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
    if not edit and ChatFrame_OpenChat then
        ChatFrame_OpenChat("")
        edit = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
    end
    if edit and ChatEdit_InsertLink then
        ChatEdit_InsertLink(link)
    elseif HandleModifiedItemClick then
        HandleModifiedItemClick(link)
    end
end

function ns:GetIcon(item)
    local icon = item[F.ICON]
    if icon and icon ~= "" then
        if icon:find("^Interface") then return icon end
        return "Interface\\Icons\\" .. icon
    end
    local id = item[F.ID]
    local ok, _, _, _, _, _, _, _, _, _, texture = pcall(GetItemInfo, id)
    if not ok then texture = nil end
    if not texture and C_Item and C_Item.GetItemIconByID then
        local ok2, liveIcon = pcall(C_Item.GetItemIconByID, id)
        if ok2 then texture = liveIcon end
    end
    return texture or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function NpcField(npcID, key)
    local db = _G.NpcDB
    if db and db.Get and npcID then
        local ok, value = pcall(db.Get, db, npcID, key)
        if ok then return value end
    end
    return nil
end

function ns:GetNpcName(npcID)
    local zh = self.npcZh and self.npcZh[npcID]
    if zh and zh ~= "" then return zh end
    local name = NpcField(npcID, "name")
    if name and name ~= "" then
        local loc = GetLocale and GetLocale() or ""
        if loc:sub(1, 2) == "zh" and not name:find("[\128-\255]") then
            return "人物 #" .. tostring(npcID)
        end
        return name
    end
    return "人物 #" .. tostring(npcID)
end

function ns:ZhZone(zone)
    if not zone or zone == "" then return zone end
    local raw = zone:match("^(.-)%s*·") or zone
    return (self.zoneZh and self.zoneZh[raw]) or raw
end

function ns:GetDQABossPoint(npcID)
    local dqa = _G.DungeonQuestAtlas
    if not (dqa and dqa.Bosses and dqa.Maps) then return nil end
    for key, bosses in pairs(dqa.Bosses) do
        for idx, boss in ipairs(bosses) do
            if tonumber(boss.npcID) == npcID then
                for _, floor in ipairs(dqa.Maps[key] or {}) do
                    for _, pin in ipairs(floor.pins or {}) do
                        if pin[1] == idx and floor.id then
                            return floor.id, pin[2], pin[3], boss.name
                        end
                    end
                end
            end
        end
    end
end

function ns:FindRecipeVendorPoint(npcID)
    npcID = tonumber(npcID)
    if not npcID or not self.recipeVendor then return nil end
    self.recipeVendorNpcCache = self.recipeVendorNpcCache or {}
    local cached = self.recipeVendorNpcCache[npcID]
    if cached ~= nil then
        if cached == false then return nil end
        return cached[1], cached[2], cached[3], cached[4], cached[5]
    end
    for _, list in pairs(self.recipeVendor) do
        for i = 1, #list do
            local v = list[i]
            if v[1] == npcID then
                local zone = v[3]
                if zone then zone = zone:match("^(.-)%s*·") or zone end
                local mapID = zone and self.zoneToMap and self.zoneToMap[zone]
                if mapID and v[4] and v[5] then
                    local hit = { mapID, v[4], v[5], v[7] or v[2], zone }
                    self.recipeVendorNpcCache[npcID] = hit
                    return hit[1], hit[2], hit[3], hit[4], hit[5]
                end
            end
        end
    end
    self.recipeVendorNpcCache[npcID] = false
    return nil
end

function ns:GetNpcPoint(npcID)
    if not npcID then return nil end
    local name = self:GetNpcName(npcID)
    local sub = NpcField(npcID, "subName")

    local qp = self.questNpcPointCache and self.questNpcPointCache[npcID]
    if qp and qp[2] and qp[3] then
        return qp[1], qp[2], qp[3], qp[4] or name, qp[5], sub
    end

    local dqaMap, dqaX, dqaY, dqaName = self:GetDQABossPoint(npcID)
    if dqaMap then
        if not name or name == ("人物 #" .. tostring(npcID)) then name = dqaName end
        return dqaMap, dqaX, dqaY, name, nil, sub
    end

    local loc = self.npcLoc and self.npcLoc[npcID]
    if loc and loc.spots and loc.spots[1] then
        local mapID = self.areaToMap and self.areaToMap[loc.zone]
        local zoneName
        if mapID and C_Map and C_Map.GetMapInfo then
            local mi = C_Map.GetMapInfo(mapID)
            if mi and mi.name then zoneName = mi.name end
        end
        return mapID, loc.spots[1][1] / 100, loc.spots[1][2] / 100, name, zoneName, sub
    end

    local rvMap, rvX, rvY, rvName, rvZone = self:FindRecipeVendorPoint(npcID)
    if rvMap then
        if rvName and rvName ~= "" then name = rvName end
        return rvMap, rvX, rvY, name, self:ZhZone(rvZone), sub
    end

    local zoneID = tonumber(NpcField(npcID, "zoneID"))
    local spawns = NpcField(npcID, "spawns")
    local list, listZoneID
    if type(spawns) == "table" then
        if zoneID then
            list = spawns[zoneID] or spawns[tostring(zoneID)]
            listZoneID = zoneID
        end
        if not list then
            for k, v in pairs(spawns) do
                if type(v) == "table" and v[1] then
                    list = v
                    listZoneID = tonumber(k) or zoneID
                    break
                end
            end
        end
    end
    if not zoneID then zoneID = listZoneID end
    local mapID = zoneID and self.areaToMap and self.areaToMap[zoneID]
    local zoneName
    if mapID and C_Map and C_Map.GetMapInfo then
        local mi = C_Map.GetMapInfo(mapID)
        if mi and mi.name then zoneName = mi.name end
    end
    local x, y
    if list and list[1] then
        x, y = list[1][1], list[1][2]
        if x and y then
            if x > 1 or y > 1 then x, y = x / 100, y / 100 end
        end
    end
    if not mapID then
        for _, rlist in pairs(self.recipeVendor or {}) do
            for i = 1, #rlist do
                local v = rlist[i]
                if v[1] == npcID then
                    local z = v[3]
                    if z then z = z:match("^(.-)%s*·") or z end
                    local m = z and self.zoneToMap and self.zoneToMap[z]
                    if m then
                        mapID = m
                        if not zoneName then zoneName = self:ZhZone(z) end
                        if v[7] or v[2] then name = v[7] or v[2] end
                        break
                    end
                end
            end
            if mapID then break end
        end
    end
    if not mapID and qp then
        mapID = qp[1]
        if not zoneName then zoneName = qp[5] end
        if qp[4] then name = qp[4] end
    end
    return mapID, x, y, name, zoneName, sub
end

function ns:GetQuestChain(questID)
    local dqa = _G.DungeonQuestAtlas
    if dqa and dqa.Quests and dqa.Quests[questID] and dqa.Quests[questID].chain then
        local chain = dqa.Quests[questID].chain
        if type(chain) == "table" and #chain > 1 then return chain end
    end
    local full = self:BuildChainFromFull(questID)
    if type(full) == "table" and #full > 1 then return full end
    local best
    if self.questInfo then
        for _, q in pairs(self.questInfo) do
            local chain = q.chain
            if type(chain) == "table" and #chain > 1 then
                for _, cid in ipairs(chain) do
                    if cid == questID then
                        if not best or #chain > #best then best = chain end
                        break
                    end
                end
            end
        end
    end
    if best then return best end
    local own = self.questInfo and self.questInfo[questID]
    if own and type(own.chain) == "table" and #own.chain > 1 then return own.chain end
    return self:BuildChainFromFull(questID)
end

function ns:PointFromArea(area, x, y)
    area = tonumber(area)
    if not area then return nil end
    local mapID = self.areaToMap and self.areaToMap[area]
    local zoneName
    if C_Map and C_Map.GetAreaInfo then
        local ok, name = pcall(C_Map.GetAreaInfo, area)
        if ok and name and name ~= "" then zoneName = name end
    end
    if not zoneName and mapID and C_Map and C_Map.GetMapInfo then
        local mi = C_Map.GetMapInfo(mapID)
        if mi and mi.name then zoneName = mi.name end
    end
    local fx, fy
    if tonumber(x) and tonumber(y) then
        fx, fy = tonumber(x) / 100, tonumber(y) / 100
    end
    return mapID, fx, fy, zoneName
end

function ns:GetObjectName(objectID)
    local db = _G.ObjectDB
    if db and db.Get and objectID then
        local ok, name = pcall(db.Get, db, objectID, "name")
        if ok and type(name) == "string" and name ~= "" then
            local loc = GetLocale and GetLocale() or ""
            if loc:sub(1, 2) == "zh" and not name:find("[\128-\255]") then
                return "任务对象 #" .. tostring(objectID)
            end
            return name
        end
    end
    return "任务对象 #" .. tostring(objectID)
end

function ns:GetObjectPoint(objectID)
    local db = _G.ObjectDB
    if not (db and db.Get) then return nil end
    local name = self:GetObjectName(objectID)
    local okS, spawns = pcall(db.Get, db, objectID, "spawns")
    local zoneID = nil
    local okZ, z = pcall(db.Get, db, objectID, "zoneID")
    if okZ then zoneID = tonumber(z) end
    local list
    if okS and type(spawns) == "table" then
        if zoneID then list = spawns[zoneID] or spawns[tostring(zoneID)] end
        if not list then
            for k, v in pairs(spawns) do
                if type(v) == "table" and v[1] then
                    list = v
                    zoneID = tonumber(k) or zoneID
                    break
                end
            end
        end
    end
    local mapID = zoneID and self.areaToMap and self.areaToMap[zoneID]
    local zoneName
    if mapID and C_Map and C_Map.GetMapInfo then
        local mi = C_Map.GetMapInfo(mapID)
        if mi and mi.name then zoneName = mi.name end
    end
    local x, y
    if list and list[1] then
        x, y = list[1][1], list[1][2]
        if x and y and (x > 1 or y > 1) then x, y = x / 100, y / 100 end
    end
    return mapID, x, y, name, zoneName
end

function ns:PinObject(objectID)
    local mapID, x, y, name, zone = self:GetObjectPoint(tonumber(objectID))
    if not mapID then
        self:Print("没有这个任务对象的位置记录。")
        return
    end
    self:PinPoint({ mapID = mapID, x = x, y = y, title = name or ("任务对象 #" .. tostring(objectID)), zone = zone })
end

function ns:GetQuestStatus(questID)
    local completed, inLog = false, false
    if C_QuestLog then
        if C_QuestLog.IsQuestFlaggedCompleted then
            local ok, res = pcall(C_QuestLog.IsQuestFlaggedCompleted, questID)
            if ok then completed = res and true or false end
        end
        if C_QuestLog.GetLogIndexForQuestID then
            local ok, res = pcall(C_QuestLog.GetLogIndexForQuestID, questID)
            if ok and res then inLog = true end
        end
    end
    if not completed and _G.IsQuestFlaggedCompleted then
        local ok, res = pcall(_G.IsQuestFlaggedCompleted, questID)
        if ok then completed = res and true or false end
    end
    if not inLog and C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        local n = C_QuestLog.GetNumQuestLogEntries()
        for i = 1, n do
            local info = C_QuestLog.GetInfo(i)
            if info and info.questID == questID then inLog = true; break end
        end
    end
    return completed, inLog
end

function ns:BuildRawNameIndex(db, cacheKey)
    if self[cacheKey] then return self[cacheKey] end
    if not (db and db.GetAllIds and db.GetRaw) then return {} end
    local ok, ids = pcall(db.GetAllIds, db)
    if not (ok and type(ids) == "table" and #ids > 0) then return {} end
    local index = {}
    for i = 1, #ids do
        local okN, name = pcall(db.GetRaw, db, ids[i], "name")
        if okN and type(name) == "string" and name ~= "" and not index[name] then
            index[name] = ids[i]
        end
    end
    self[cacheKey] = index
    return index
end

function ns:FindNpcIdByName(name)
    if not name then return nil end
    local db = _G.NpcDB
    if db and db.IdsByName then
        local ok, ids = pcall(db.IdsByName, db, name)
        if ok and type(ids) == "table" and ids[1] then return ids[1] end
    end
    if not db then return nil end
    return self:BuildRawNameIndex(db, "rawNpcNameIndex")[name]
end

function ns:FindItemIdByName(name)
    if not name then return nil end
    local db = _G.ItemDB
    if db and db.IdsByName then
        local ok, ids = pcall(db.IdsByName, db, name)
        if ok and type(ids) == "table" and ids[1] then return ids[1] end
    end
    if not db then return nil end
    return self:BuildRawNameIndex(db, "rawItemNameIndex")[name]
end

function ns:PinQuestStep(questID, index)
    local info = self:GetQuestInfo(tonumber(questID))
    local st = info and info.steps and info.steps[tonumber(index)]
    if not st then
        self:Print("没有这个任务品的位置记录。")
        return
    end
    local mapID, x, y, zoneName = self:PointFromArea(st.a, st.x, st.y)
    if not mapID then
        self:Print("任务品没有可用地图。")
        return
    end
    local title = "任务品位置"
    if st.n then
        local loc = GetLocale and GetLocale() or ""
        if loc:sub(1, 2) == "en" or st.n:find("[\128-\255]") then title = st.n end
    end
    local itemID = self:FindItemIdByName(st.n)
    if itemID then
        local iname = self:GetItemNameSafe(itemID)
        if iname then title = iname end
    end
    self:PinPoint({ mapID = mapID, x = x, y = y, title = title, zone = zoneName })
end

function ns:PinQuestLoc(questID, which)
    local info = self:GetQuestInfo(tonumber(questID))
    local ex = info and info.extra
    local loc = ex and ((which == "e") and ex.e or ex.s)
    if not loc then
        if info and info.mapID then
            self:PinPoint({ mapID = info.mapID, x = info.x, y = info.y,
                title = (which == "e" and "交付地点" or "接取地点"), zone = info.zoneName })
        else
            self:Print("没有这个任务人物 的位置记录。")
        end
        return
    end
    local mapID, x, y, zoneName = self:PointFromArea(loc.a, loc.x, loc.y)
    if not mapID then
        self:Print("任务人物 没有可用地图。")
        return
    end
    self:PinPoint({ mapID = mapID, x = x, y = y, title = (which == "e" and "交付地点" or "接取地点"), zone = zoneName })
end

function ns:BuildChainFromFull(questID)
    local all = self.questFull
    if not all or not all[questID] then return nil end
    if not self.questFullRev then
        local rev = {}
        for id, q in pairs(all) do
            if q.r then
                for i = 1, #q.r do
                    local r = q.r[i]
                    rev[r] = rev[r] or {}
                    rev[r][#rev[r] + 1] = id
                end
            end
        end
        self.questFullRev = rev
    end
    local rev = self.questFullRev
    local set = { [questID] = true }
    local stack = { questID }
    while #stack > 0 do
        local x = table.remove(stack)
        local q = all[x]
        if q and q.r then
            for i = 1, #q.r do
                local r = q.r[i]
                if not set[r] then set[r] = true; stack[#stack + 1] = r end
            end
        end
        local kids = rev[x]
        if kids then
            for i = 1, #kids do
                local k = kids[i]
                if not set[k] then set[k] = true; stack[#stack + 1] = k end
            end
        end
    end

    local faction = UnitFactionGroup and UnitFactionGroup("player")
    local filtered = {}
    for id in pairs(set) do
        local q = all[id]
        local ok = true
        if q then
            if q.f and faction and q.f ~= faction then ok = false end
            if ok and q.cl and math.floor(q.cl / 2) % 2 == 0 then ok = false end
        end
        if ok or id == questID then filtered[id] = true end
    end

    local depth = {}
    for id in pairs(filtered) do depth[id] = 1 end
    for _ = 1, 40 do
        local changed = false
        for id in pairs(filtered) do
            local q = all[id]
            if q and q.r then
                for i = 1, #q.r do
                    local r = q.r[i]
                    if filtered[r] and depth[r] + 1 > depth[id] then
                        depth[id] = depth[r] + 1
                        changed = true
                    end
                end
            end
        end
        if not changed then break end
    end

    local list = {}
    for id in pairs(filtered) do list[#list + 1] = id end
    table.sort(list, function(a, b)
        if depth[a] ~= depth[b] then return depth[a] < depth[b] end
        local qa, qb = all[a], all[b]
        local la = (qa and qa.l) or 0
        local lb = (qb and qb.l) or 0
        if la ~= lb then return la < lb end
        return a < b
    end)
    return list
end

function ns:GetQuestInfo(questID)
    if not questID then return nil end
    local db = _G.QuestDB
    local localQ = self.questInfo and self.questInfo[questID]
    local ex = self.questFull and self.questFull[questID]
    if not (localQ or ex or (db and db.Get)) then return nil end
    self.questInfoCache = self.questInfoCache or {}
    local cached = self.questInfoCache[questID]
    if cached ~= nil then return cached end

    local info = {}
    if localQ and localQ.level then info.level = localQ.level end
    local chain = self:GetQuestChain(questID)
    if type(chain) == "table" and #chain > 1 then info.chain = chain end
    if self.questZh and self.questZh[questID] then info.name = self.questZh[questID] end

    local started
    if db and db.Get then
        if not info.name then
            local ok, name = pcall(db.Get, db, questID, "name")
            if ok and type(name) == "string" and name ~= "" then
                local loc = GetLocale and GetLocale() or ""
                if loc:sub(1, 2) ~= "zh" or name:find("[\128-\255]") then
                    info.name = name
                end
            end
        end
        if not info.level then
            local okL, lvl = pcall(db.Get, db, questID, "questLevel")
            if okL then info.level = tonumber(lvl) end
        end
        local ok2, sb = pcall(db.Get, db, questID, "startedBy")
        if ok2 and type(sb) == "table" then started = sb end
        local okF, fin = pcall(db.Get, db, questID, "finishedBy")
        if okF and type(fin) == "table" and fin.npcIds and fin.npcIds[1] then info.enderID = fin.npcIds[1] end
        local okO, obj = pcall(db.Get, db, questID, "objectivesText")
        if okO and type(obj) == "table" then info.objectives = obj end
        local okRaw, raw = pcall(db.Get, db, questID, "objectives")
        if okRaw and type(raw) == "table" then info.objectivesRaw = raw end
    end

    if ex then
        info.extra = ex
        if not info.level and ex.l then info.level = ex.l end
        info.steps = ex.st
        info.objectiveEn = ex.o
        info.requires = ex.r
    end
    local npcID = started and started.npcIds and started.npcIds[1]
    if not npcID and localQ and localQ.giver then npcID = localQ.giver end

    local dqa = _G.DungeonQuestAtlas
    local dq = dqa and dqa.Quests and dqa.Quests[questID]
    if dq then
        if not info.level then info.level = dq.level end
        if dq.need then info.need = dq.need end
        if not npcID and type(dq.starts) == "table" then
            for _, s in ipairs(dq.starts) do
                local id = tostring(s):match("^npc:(%d+)")
                if id then npcID = tonumber(id); break end
            end
        end
        if not info.enderID and type(dq.ends) == "table" then
            for _, s in ipairs(dq.ends) do
                local id = tostring(s):match("^npc:(%d+)")
                if id then info.enderID = tonumber(id); break end
            end
        end
    end

    if npcID then
        local mapID, x, y, name, zoneName, sub = self:GetNpcPoint(npcID)
        info.npcID = npcID
        info.npcName = name
        if sub and sub ~= "" then info.subName = sub end
        if mapID then info.mapID = mapID; info.zoneName = zoneName end
        if (not x or not y) and localQ and localQ.x and localQ.y then
            x, y = localQ.x / 100, localQ.y / 100
        end
        if x and y then info.x, info.y = x, y end
    else
        local itemID = started and started.itemIds and started.itemIds[1]
        if not itemID and localQ then itemID = localQ.item end
        if not itemID and db and db.Get then
            local okS, sid = pcall(db.Get, db, questID, "sourceItemId")
            if okS and tonumber(sid) and tonumber(sid) > 0 then itemID = tonumber(sid) end
        end
        if itemID then
            info.itemID = itemID
            info.itemName = self:GetItemNameSafe(itemID) or ("物品 #" .. tostring(itemID))
            local idb = _G.ItemDB
            if idb and idb.Get then
                local okD, drops = pcall(idb.Get, idb, itemID, "npcDrops")
                if okD and type(drops) == "table" then
                    info.monsters = {}
                    for _, mid in ipairs(drops) do
                        if #info.monsters >= 12 then break end
                        info.monsters[#info.monsters + 1] = { id = mid, name = self:GetNpcName(mid) }
                    end
                end
            end
        elseif started and started.objectIds and started.objectIds[1] then
            info.objectID = started.objectIds[1]
        end
    end
    if ex and ex.s then
        if not info.mapID or not info.x or not info.y then
            local m, px, py, zname = self:PointFromArea(ex.s.a, ex.s.x, ex.s.y)
            if not info.mapID and m then info.mapID = m end
            if not info.zoneName and zname then info.zoneName = zname end
            if (not info.x or not info.y) and px and py then info.x, info.y = px, py end
        end
    end
    if info.enderID then
        local em, exx, eyy, en, ez = self:GetNpcPoint(info.enderID)
        info.enderName = en or self:GetNpcName(info.enderID)
        if em then info.enderMapID = em; info.enderX = exx; info.enderY = eyy; info.enderZone = ez end
    end
    if ex and ex.e then
        if not info.enderMapID or not info.enderX or not info.enderY then
            local m, px, py, zname = self:PointFromArea(ex.e.a, ex.e.x, ex.e.y)
            if not info.enderMapID and m then info.enderMapID = m end
            if not info.enderZone and zname then info.enderZone = zname end
            if (not info.enderX or not info.enderY) and px and py then info.enderX, info.enderY = px, py end
        end
    end
    self.questNpcPointCache = self.questNpcPointCache or {}
    if info.npcID and info.mapID then
        self.questNpcPointCache[info.npcID] = { info.mapID, info.x, info.y, info.npcName, info.zoneName }
    end
    if info.enderID and info.enderMapID then
        self.questNpcPointCache[info.enderID] = { info.enderMapID, info.enderX, info.enderY, info.enderName, info.enderZone }
    end
    self.questInfoCache[questID] = info
    return info
end

function ns:GetItemQuestLevel(item)
    if item[F.ILVL] and item[F.ILVL] > 0 then return nil end
    local srcs = item[F.SOURCES] or {}
    for i = 1, #srcs do
        local s = srcs[i]
        if s[1] == "quest" then
            local info = self:GetQuestInfo(tonumber(s[5]))
            if info and info.level and info.level > 0 then return info.level end
            if s[15] then return tonumber(s[15]) end
        end
    end
end

function ns:GetQuestTitle(qid, fallback)
    if not qid then return fallback end
    local info = self:GetQuestInfo(qid)
    if info and info.name then return info.name end
    local cached = self.questCache[qid]
    if cached ~= nil then
        if cached == false then return fallback end
        return cached
    end
    local title
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local ok, res = pcall(C_QuestLog.GetTitleForQuestID, qid)
        if ok and type(res) == "string" and res ~= "" then title = res end
    end
    self.questCache[qid] = title or false
    return title or fallback
end

function ns:GetItemNameSafe(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil end
    local idb = _G.ItemDB
    if idb and idb.Get then
        local ok, name = pcall(idb.Get, idb, itemID, "name")
        if ok and type(name) == "string" and name ~= "" then
            local loc = GetLocale and GetLocale() or ""
            if loc:sub(1, 2) == "zh" and not name:find("[\128-\255]") then
                return "物品 #" .. itemID
            end
            return name
        end
    end
    return "物品 #" .. itemID
end

function ns:FindObjectIdByName(name)
    if not name then return nil end
    local db = _G.ObjectDB
    if db and db.IdsByName then
        local ok, ids = pcall(db.IdsByName, db, name)
        if ok and type(ids) == "table" and ids[1] then return ids[1] end
    end
    if not db then return nil end
    return self:BuildRawNameIndex(db, "rawObjectNameIndex")[name]
end

function ns:FormatSource(src)
    local kind, name, zone, chance, extra = src[1], src[2], src[3], src[4], src[5]
    local zhName, mapID, x, y, note, recipeName = src[6], src[7], src[8], src[9], src[10], src[11]
    local info = self.SOURCE_KINDS[kind]
    local label = info and info.label or kind or "来源"
    if kind == "drop" and src[14] then
        local cn = self:GetNpcName(src[14])
        if cn and cn ~= "" then name = cn end
    elseif kind == "item" then
        local iid = tonumber(extra)
        local cn = self:GetItemNameSafe(iid)
        if cn then name = cn end
    elseif kind == "object" then
        local oid = self:FindObjectIdByName(name)
        if oid then
            name = self:GetObjectName(oid)
        else
            local loc = GetLocale and GetLocale() or ""
            if loc:sub(1, 2) == "zh" and name and not name:find("[\128-\255]") then
                name = "任务对象"
            end
        end
    end
    if kind == "drop" and not src[14] then
        local loc = GetLocale and GetLocale() or ""
        if loc:sub(1, 2) == "zh" and name and not name:find("[\128-\255]") then
            name = "小怪"
        end
    end
    if kind == "quest" then
        local qid = tonumber(extra)
        local info = self:GetQuestInfo(qid)
        local qname = (info and info.name) or self:GetQuestTitle(qid, name)
        local loc = GetLocale and GetLocale() or ""
        if qname and loc:sub(1, 2) == "zh" and not qname:find("[\128-\255]") then
            qname = "任务 #" .. tostring(qid)
        end
        local out = "任务 · " .. tostring(qname)
        if info and info.npcName then
            out = out .. " · 接取：" .. info.npcName
            if info.subName then out = out .. "（" .. info.subName .. "）" end
            if info.zoneName then out = out .. " · " .. info.zoneName end
            if info.x and info.y then out = out .. string.format(" · %.1f, %.1f", info.x * 100, info.y * 100) end
        elseif info and info.itemID then
            out = out .. " · 起始物品：" .. (info.itemName or ("#" .. info.itemID))
            if info.monsters and #info.monsters > 0 then
                local names = {}
                for i = 1, math.min(#info.monsters, 4) do
                    names[#names + 1] = info.monsters[i].name
                end
                out = out .. " · 掉落：" .. table.concat(names, "、")
                if #info.monsters > 4 then out = out .. string.format(" 等%d只", #info.monsters) end
            end
        elseif info and info.objectID then
            out = out .. " · 任务对象 #" .. info.objectID
        elseif zone and zone ~= "" then
            out = out .. " · " .. zone
        end
        return out
    elseif kind == "vendor" then
        if zhName and zhName ~= "" then name = zhName end
        if extra and extra ~= "" then
            name = (name ~= "" and (name .. "（" .. extra .. "）")) or extra
        end
        local loc = GetLocale and GetLocale() or ""
        if loc:sub(1, 2) == "zh" and name and not name:find("[\128-\255]") then
            name = "商人"
        end
    end
    local out = label
    if kind ~= "world" and name and name ~= "" then
        out = out .. " · " .. name
    end
    if kind == "craft" and recipeName and recipeName ~= "" then
        out = out .. " · 配方：" .. recipeName
    end
    if zone and zone ~= "" then
        out = out .. " · " .. zone
    end
    if kind == "vendor" and x and y then
        out = out .. string.format(" · %.1f, %.1f", x * 100, y * 100)
    end
    local c = self:FormatChance(chance)
    if c and kind ~= "world" then out = out .. " · " .. c end
    if kind == "vendor" and note and note ~= "" then out = out .. " · " .. note end
    return out
end

function ns:GetRecipeVendors(recipeID)
    recipeID = tonumber(recipeID)
    if not recipeID then return {} end
    self.recipeVendorCache = self.recipeVendorCache or {}
    local cached = self.recipeVendorCache[recipeID]
    if cached then return cached end

    local out = {}
    local seenNpc = {}
    local hasVendor = false
    local list = self.recipeVendor and self.recipeVendor[recipeID]
    if list then
        for i = 1, #list do
            local v = list[i]
            local zoneRaw = v[3]
            if zoneRaw then zoneRaw = zoneRaw:match("^(.-)%s*·") or zoneRaw end
            local mapID = v[6] or (self.zoneToMap and self.zoneToMap[zoneRaw])
            local x, y = v[4], v[5]
            local zoneName = zoneRaw and self:ZhZone(zoneRaw) or nil
            if (not mapID or not x or not y) and v[1] then
                local m2, x2, y2, n2, z2 = self:GetNpcPoint(v[1])
                if m2 then
                    if not mapID then mapID = m2 end
                    if x2 and y2 then x, y = x2, y2 end
                    if not zoneName and z2 then zoneName = z2 end
                end
            end
            local resolved = v[7]
            if not resolved then
                local n = self:GetNpcName(v[1])
                if n and n ~= ("人物 #" .. tostring(v[1])) then resolved = n end
            end
            local kind = v[8] or "Vendor"
            if kind == "Vendor" then hasVendor = true end
            seenNpc[v[1]] = true
            out[#out + 1] = {
                npcID = v[1],
                name = resolved or v[2] or ("人物 #" .. tostring(v[1])),
                enName = v[2],
                zone = zoneName,
                x = x,
                y = y,
                mapID = mapID,
                kind = kind,
            }
        end
    end

    if not hasVendor then
        local idb = _G.ItemDB
        if idb and idb.Get then
            local ok, npcs = pcall(idb.Get, idb, recipeID, "vendors")
            if ok and type(npcs) == "table" then
                for i = 1, #npcs do
                    local npcID = tonumber(npcs[i])
                    if npcID and not seenNpc[npcID] then
                        seenNpc[npcID] = true
                        local mapID, x, y, name, zone = self:GetNpcPoint(npcID)
                        out[#out + 1] = {
                            npcID = npcID,
                            name = name or ("人物 #" .. npcID),
                            zone = zone,
                            x = x,
                            y = y,
                            mapID = mapID,
                            kind = "Vendor",
                        }
                    end
                end
            end
        end
    end

    self.recipeVendorCache[recipeID] = out
    return out
end

function ns:GetSourceMap(src)
    local kind = src[1]
    if kind == "vendor" and src[7] and src[8] and src[9] then
        return src[7], src[8], src[9], (src[6] or src[2] or "商人"), src[3]
    elseif kind == "craft" and src[12] then
        local vendors = self:GetRecipeVendors(src[12])
        local v
        for _, c in ipairs(vendors) do
            if c.kind == "Vendor" then v = c; break end
        end
        v = v or vendors[1]
        if v and v.mapID then
            local prefix = (v.kind == "Vendor") and "图纸商人 " or "图纸来源 "
            return v.mapID, v.x, v.y, (prefix .. tostring(v.name)), v.zone
        end
    elseif kind == "quest" then
        local info = self:GetQuestInfo(tonumber(src[5]))
        if info and info.mapID then
            return info.mapID, info.x, info.y, (info.npcName or info.name or "任务"), info.zoneName
        end
    elseif kind == "drop" and src[14] then
        local mapID, x, y, name, zone = self:GetNpcPoint(src[14])
        if not mapID and src[3] and self.zoneToMap then
            mapID = self.zoneToMap[src[3]]
        end
        if mapID then
            return mapID, x, y, name, zone or src[3]
        end
    end
end

function ns:GetMapPoints(item)
    local points = {}
    local seen = {}
    local function add(mapID, x, y, title, zone)
        if not mapID then return end
        local key = table.concat({ mapID, x and math.floor(x * 1000) or -1, y and math.floor(y * 1000) or -1 }, ":")
        if seen[key] then return end
        seen[key] = true
        points[#points + 1] = { mapID = mapID, x = x, y = y, title = title or "位置", zone = zone }
    end

    local srcs = item[F.SOURCES] or {}
    for i = 1, #srcs do
        local s = srcs[i]
        local mapID, x, y, title, zone = self:GetSourceMap(s)
        if mapID then add(mapID, x, y, title, zone or s[3]) end
        if s[1] == "quest" then
            local info = self:GetQuestInfo(tonumber(s[5]))
            if info and type(info.chain) == "table" then
                for idx, cid in ipairs(info.chain) do
                    local ci = self:GetQuestInfo(cid)
                    if ci and ci.mapID then
                        add(ci.mapID, ci.x, ci.y, string.format("第%d步 %s", idx, ci.npcName or ci.name or ("任务 #" .. cid)), ci.zoneName)
                    end
                end
            end
            if info and info.monsters then
                for _, m in ipairs(info.monsters) do
                    local mID, mx, my, mname, mzone = self:GetNpcPoint(m.id)
                    if mID then
                        add(mID, mx, my, (mname or m.name or "怪物") .. "（怪物）", mzone)
                    end
                end
            end
            if info and info.objectivesRaw then
                local raw = info.objectivesRaw
                for _, o in pairs(raw[1] or {}) do
                    local id = type(o) == "table" and tonumber(o[1]) or nil
                    if id then
                        local mID, mx, my, mname, mzone = self:GetNpcPoint(id)
                        if mID then add(mID, mx, my, (mname or ("人物 #" .. id)) .. "（击杀）", mzone) end
                    end
                end
                for _, o in pairs(raw[2] or {}) do
                    local id = type(o) == "table" and tonumber(o[1]) or nil
                    if id then
                        local mID, mx, my, mname, mzone = self:GetObjectPoint(id)
                        if mID then add(mID, mx, my, (mname or ("对象 #" .. id)) .. "（任务对象）", mzone) end
                    end
                end
                for _, o in pairs(raw[3] or {}) do
                    local iid = type(o) == "table" and tonumber(o[1]) or nil
                    local idb = _G.ItemDB
                    if iid and idb and idb.Get then
                        local okN, drops = pcall(idb.Get, idb, iid, "npcDrops")
                        if okN and type(drops) == "table" then
                            for _, mid in ipairs(drops) do
                                local mID, mx, my, mname, mzone = self:GetNpcPoint(tonumber(mid))
                                if mID then add(mID, mx, my, (mname or "怪物") .. "（任务品掉落）", mzone) end
                            end
                        end
                        local okO, odrops = pcall(idb.Get, idb, iid, "objectDrops")
                        if okO and type(odrops) == "table" then
                            for _, oid in ipairs(odrops) do
                                local mID, mx, my, mname, mzone = self:GetObjectPoint(tonumber(oid))
                                if mID then add(mID, mx, my, (mname or "任务对象") .. "（任务品）", mzone) end
                            end
                        end
                    end
                end
            end
            if info and info.steps then
                for i, st in ipairs(info.steps) do
                    local mapID, sx, sy, zname = self:PointFromArea(st.a, st.x, st.y)
                    if mapID then
                        local title = "任务品位置 " .. i
                        local iid = st.n and self:FindItemIdByName(st.n)
                        local iname = iid and self:GetItemNameSafe(iid)
                        if iname then title = iname end
                        add(mapID, sx, sy, title, zname)
                    end
                end
            end
            if info and info.enderID and info.enderMapID then
                add(info.enderMapID, info.enderX, info.enderY,
                    (info.enderName or "交付人物") .. "（交付）", info.enderZone)
            end
        elseif s[1] == "craft" and s[12] then
            local vendors = self:GetRecipeVendors(s[12])
            for _, v in ipairs(vendors) do
                if v.mapID then
                    local prefix = (v.kind == "Vendor") and "图纸商人" or (v.kind == "Chest" and "图纸宝箱" or "图纸掉落")
                    add(v.mapID, v.x, v.y,
                        string.format("%s %s（%s）", prefix, tostring(v.name), s[11] or ("配方 #" .. tostring(s[12]))),
                        v.zone)
                end
            end
        end
    end
    return points
end

function ns:FindMapSource(item)
    return self:GetMapPoints(item)[1]
end

function ns:OpenMapAt(mapID)
    mapID = tonumber(mapID)
    if not mapID then return false end
    local wm = _G.WorldMapFrame
    local opened = false

    if C_Map and C_Map.OpenWorldMap then
        opened = pcall(C_Map.OpenWorldMap, mapID) or opened
    elseif _G.OpenWorldMap then
        opened = pcall(_G.OpenWorldMap, mapID) or opened
    end

    if wm then
        if not wm:IsShown() then
            if ShowUIPanel then pcall(ShowUIPanel, wm) end
        end
        if wm.SetMapID then pcall(wm.SetMapID, wm, mapID) end
    end

    if wm and wm.GetMapID then
        local cur = wm:GetMapID()
        if cur ~= mapID then
            if C_Map and C_Map.OpenMap then pcall(C_Map.OpenMap, mapID) end
            if wm.SetMapID then pcall(wm.SetMapID, wm, mapID) end
        end
    end

    if not (wm and wm:IsShown()) then
        if C_Map and C_Map.OpenMap then
            pcall(C_Map.OpenMap, mapID)
        elseif ToggleWorldMap then
            pcall(ToggleWorldMap)
        end
    end
    return (wm and wm:IsShown()) or opened
end

function ns:PinPoint(point)
    if not point then
        self:Print("没有可标记的位置。")
        return
    end
    local mapID, x, y = point.mapID, point.x, point.y
    if not mapID then
        self:Print("没有可标记的地图。")
        return
    end
    local title = tostring(point.title or "位置")
    if point.zone and point.zone ~= "" then title = title .. " · " .. point.zone end

    if x and y then
        if TomTom and TomTom.AddWaypoint then
            pcall(TomTom.AddWaypoint, TomTom, mapID, x, y, { title = title, persistent = false })
        end
        if C_Map and C_Map.SetUserWaypoint then
            pcall(C_Map.SetUserWaypoint, { uiMapID = mapID, position = { x = x, y = y } })
        end
    end

    local opened = self:OpenMapAt(mapID)
    if opened and self.lowerForMap then
        self.lowerForMap()
        if C_Timer and C_Timer.After then
            C_Timer.After(0.8, function()
                local wm = _G.WorldMapFrame
                if not (wm and wm:IsShown()) and self.restoreForMap then self:restoreForMap() end
            end)
        end
    end
    if x and y and self.ShowMapPin then self:ShowMapPin(mapID, x, y) end
    if not opened then
        if self.restoreForMap then self:restoreForMap() end
        self:Print("无法打开地图：" .. tostring(mapID) .. "（" .. title .. "）")
        return
    end
    if x and y then
        self:Print(string.format("已标记：%s（%.1f, %.1f）", title, x * 100, y * 100))
    else
        self:Print("已打开地图：" .. title .. "（数据库没有精确坐标）")
    end
end

function ns:SetMapPin(item)
    self:PinPoint(self:GetMapPoints(item)[1])
end

function ns:PinNpc(npcID)
    local mapID, x, y, name, zone = self:GetNpcPoint(tonumber(npcID))
    if not mapID then
        self:Print("没有这个人物或怪物的位置记录。")
        return
    end
    self:PinPoint({ mapID = mapID, x = x, y = y, title = name or ("人物 #" .. tostring(npcID)), zone = zone })
end

function ns:GetSourceText(item, limit)
    local srcs = item[F.SOURCES]
    if not srcs or #srcs == 0 then return nil end
    limit = limit or 2
    local out = {}
    for i = 1, math.min(#srcs, limit) do
        out[#out + 1] = self:FormatSource(srcs[i])
    end
    if #srcs > limit then out[#out + 1] = string.format("等%d处", #srcs) end
    return table.concat(out, "；")
end

local function IsJewel(item)
    local s = item[F.SLOT]
    return s == "neck" or s == "finger" or s == "trinket" or s == "back"
end

local function ListHas(list, value)
    if type(list) ~= "table" then return false end
    for i = 1, #list do
        if list[i] == value then return true end
    end
    return false
end

function ns:Matches(item, f)
    local wantsUnknown = ListHas(f.source, "unknown")
    if f.knownOnly and not wantsUnknown and item[F.KNOWN] == 0 then return false end
    if #f.slot > 0 and not ListHas(f.slot, item[F.SLOT]) then return false end

    if #f.quality > 0 and not ListHas(f.quality, tostring(item[F.QUALITY])) then return false end

    if #f.source > 0 then
        local found = false
        for i = 1, #f.source do
            local want = f.source[i]
            if want == "unknown" then
                if item[F.KNOWN] == 0 then found = true; break end
            else
                local srcs = item[F.SOURCES] or {}
                for j = 1, #srcs do
                    if srcs[j][1] == want then found = true; break end
                end
                if found then break end
            end
        end
        if not found then return false end
    end

    local t = item[F.TYPE]
    if #f.armor > 0 then
        local matched = false
        for i = 1, #f.armor do
            local a = f.armor[i]
            if a == "tank" then
                if t == "Plate" or t == "Mail" or t == "Shield" or IsJewel(item) then matched = true; break end
            elseif a == "jewel" then
                if IsJewel(item) then matched = true; break end
            elseif a == "weapon" then
                if item[F.SLOT] == "weapon" then matched = true; break end
            elseif t == a then
                matched = true; break
            end
        end
        if not matched then return false end
    end

    local rl = item[F.REQ]
    local lvl = (rl == 0) and 60 or rl
    if lvl < f.minLevel or lvl > f.maxLevel then return false end

    if f.tanky then
        local sta = item[F.STATS].sta or 0
        if sta <= 0 then return false end
    end

    if f.search and f.search ~= "" then
        local q = string.lower(f.search)
        local hay = item[F.NAME] .. " " .. (item[F.ENAME] or "") .. " " .. item[F.ID] .. " " .. (self.TYPE_NAMES[t] or t)
        local srcs = item[F.SOURCES] or {}
        for i = 1, #srcs do
            hay = hay .. " " .. tostring(srcs[i][2] or "") .. " " .. tostring(srcs[i][3] or "")
        end
        if not string.find(string.lower(hay), q, 1, true) then return false end
    end
    return true
end

local function SortValue(a, b, mode)
    if mode == "ilvl" then
        if a[F.ILVL] ~= b[F.ILVL] then return a[F.ILVL] > b[F.ILVL] end
    elseif mode == "sp" then
        local as = a[F.STATS].sp or 0
        local bs = b[F.STATS].sp or 0
        if as ~= bs then return as > bs end
    elseif mode == "name" then
        return a[F.NAME] < b[F.NAME]
    end
    local al = a[F.REQ] == 0 and 61 or a[F.REQ]
    local bl = b[F.REQ] == 0 and 61 or b[F.REQ]
    if al ~= bl then return al < bl end
    if a[F.ILVL] ~= b[F.ILVL] then return a[F.ILVL] > b[F.ILVL] end
    if a[F.QUALITY] ~= b[F.QUALITY] then return a[F.QUALITY] > b[F.QUALITY] end
    return a[F.NAME] < b[F.NAME]
end

function ns:GetFiltered()
    local f = self.db.filters
    local out = {}
    for i = 1, #self.data.items do
        local item = self.data.items[i]
        if self:Matches(item, f) then out[#out + 1] = item end
    end
    table.sort(out, function(a, b) return SortValue(a, b, f.sort) end)
    return out
end

ns.DB_VERSION = 4

function ns:Init()
    self.questCache = {}
    self.questInfoCache = {}
    self.byId = {}
    self.dataError = nil

    HolyBulwarkDB = HolyBulwarkDB or {}
    self.db = HolyBulwarkDB
    if self.db.version ~= self.DB_VERSION then
        self.db.version = self.DB_VERSION
        self.db.filters = {}
    end
    self.db.filters = self.db.filters or {}
    local function CopyList(t)
        local out = {}
        for i = 1, #t do out[i] = t[i] end
        return out
    end
    local function NormalizeList(v)
        if type(v) == "table" then
            local out = {}
            for i = 1, #v do out[#out + 1] = tostring(v[i]) end
            return out
        end
        if v == nil or v == "all" then return {} end
        return { tostring(v) }
    end

    for k, v in pairs(self.defaults) do
        if self.db.filters[k] == nil then
            if type(v) == "table" then self.db.filters[k] = CopyList(v) else self.db.filters[k] = v end
        end
    end
    local f = self.db.filters
    f.minLevel = tonumber(f.minLevel) or 10
    f.maxLevel = tonumber(f.maxLevel) or 60
    f.minLevel = math.max(1, math.min(60, math.floor(f.minLevel)))
    f.maxLevel = math.max(1, math.min(60, math.floor(f.maxLevel)))
    if f.minLevel > f.maxLevel then f.minLevel, f.maxLevel = f.maxLevel, f.minLevel end
    f.tanky = f.tanky and true or false
    f.knownOnly = f.knownOnly and true or false
    f.search = tostring(f.search or "")
    if type(f.sort) ~= "string" then f.sort = "level" end
    f.slot = NormalizeList(f.slot)
    f.armor = NormalizeList(f.armor)
    f.source = NormalizeList(f.source)
    f.quality = NormalizeList(f.quality)

    if type(self.data) ~= "table" or type(self.data.items) ~= "table" or #self.data.items == 0 then
        self.dataError = "数据库没有加载：Data.lua 缺失或为空"
        self.data = { items = {} }
        return
    end
    for i = 1, #self.data.items do
        local item = self.data.items[i]
        self.byId[item[F.ID]] = item
    end
end

function ns:Diag()
    local d = self.data
    local f = (self.db and self.db.filters) or {}
    local byIdCount = 0
    if self.byId then
        for _ in pairs(self.byId) do byIdCount = byIdCount + 1 end
    end
    local ok, res = pcall(self.GetFiltered, self)
    local n = ok and #res or -1
    self:Print(string.format("数据=%s items=%s count=%s loaded=%s byId=%s",
        type(d), tostring(d and d.items and #d.items), tostring(d and d.count),
        tostring(d and d.loaded), tostring(byIdCount)))
    self:Print(string.format("筛选 slot=%s armor=%s sort=%s level=%s-%s tanky=%s known=%s search=%q",
        tostring(f.slot), tostring(f.armor), tostring(f.sort), tostring(f.minLevel),
        tostring(f.maxLevel), tostring(f.tanky), tostring(f.knownOnly), tostring(f.search or "")))
    self:Print("筛选结果=" .. n .. (ok and "" or ("  错误=" .. tostring(res))))
    if self.lastError then self:Print("最近错误：" .. self.lastError) end
    if self.lastRowError then self:Print("行渲染错误：" .. self.lastRowError) end
end

function ns:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99圣光壁垒|r " .. tostring(msg))
end

function ns:ColorName(item)
    return "|cff" .. (self.QUALITY_HEX[item[F.QUALITY]] or "ffffff") .. self:GetName(item) .. "|r"
end

function ns:PrintItem(item)
    local link = self:GetLink(item)
    if link:sub(1, 4) ~= "|H" then
        link = "|H" .. link .. "|h[" .. self:GetName(item) .. "]|h"
    end
    self:Print(string.format("%s  物品等级 %d · 需要等级 %s", link, item[F.ILVL],
        item[F.REQ] == 0 and "—" or tostring(item[F.REQ])))
    self:Print(self:RowStats(item, 10))
    local src = self:GetSourceText(item, 5)
    if src then self:Print("来源：" .. src) end
end
