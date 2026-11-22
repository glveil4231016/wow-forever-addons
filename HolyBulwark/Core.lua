local addonName, ns = ...

-- Data layout (see Data.lua)
ns.F = {
    ID = 1, NAME = 2, QUALITY = 3, ILVL = 4, REQ = 5, SLOT = 6, TYPE = 7,
    ARMOR = 8, STATS = 9, SOURCES = 10, KNOWN = 11, BIND = 12, DMG = 13, ENAME = 14, ICON = 15,
}
ns.VERSION = "1.8.0"

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
    if name and name ~= "" then return name end
    return "NPC #" .. tostring(npcID)
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

    local dqaMap, dqaX, dqaY, dqaName = self:GetDQABossPoint(npcID)
    if dqaMap then
        if not name or name == ("NPC #" .. tostring(npcID)) then name = dqaName end
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
        return rvMap, rvX, rvY, name, rvZone, sub
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
                        if not zoneName then zoneName = z end
                        if v[7] or v[2] then name = v[7] or v[2] end
                        break
                    end
                end
            end
            if mapID then break end
        end
    end
    return mapID, x, y, name, zoneName, sub
end

function ns:GetQuestChain(questID)
    local dqa = _G.DungeonQuestAtlas
    if dqa and dqa.Quests and dqa.Quests[questID] and dqa.Quests[questID].chain then
        local chain = dqa.Quests[questID].chain
        if type(chain) == "table" and #chain > 1 then return chain end
    end
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
    return own and own.chain
end

function ns:GetQuestInfo(questID)
    if not questID then return nil end
    local db = _G.QuestDB
    local localQ = self.questInfo and self.questInfo[questID]
    if not (localQ or (db and db.Get)) then return nil end
    self.questInfoCache = self.questInfoCache or {}
    local cached = self.questInfoCache[questID]
    if cached ~= nil then return cached end

    local info = {}
    if localQ then
        if localQ.level then info.level = localQ.level end
        local chain = self:GetQuestChain(questID) or localQ.chain
        if type(chain) == "table" then info.chain = chain end
    end
    if self.questZh and self.questZh[questID] then info.name = self.questZh[questID] end

    local started
    if db and db.Get then
        if not info.name then
            local ok, name = pcall(db.Get, db, questID, "name")
            if ok and type(name) == "string" then info.name = name end
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
            local idb = _G.ItemDB
            if idb and idb.Get then
                local okI, iname = pcall(idb.Get, idb, itemID, "name")
                if okI and type(iname) == "string" then info.itemName = iname end
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
    if info.enderID then
        local em, ex, ey, en, ez = self:GetNpcPoint(info.enderID)
        info.enderName = en or self:GetNpcName(info.enderID)
        if em then info.enderMapID = em; info.enderX = ex; info.enderY = ey; info.enderZone = ez end
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

function ns:FormatSource(src)
    local kind, name, zone, chance, extra = src[1], src[2], src[3], src[4], src[5]
    local zhName, mapID, x, y, note, recipeName = src[6], src[7], src[8], src[9], src[10], src[11]
    local info = self.SOURCE_KINDS[kind]
    local label = info and info.label or kind or "来源"
    if kind == "drop" and src[14] then
        local cn = NpcField(src[14], "name")
        if cn and cn ~= "" then name = cn end
    end
    if kind == "quest" then
        local qid = tonumber(extra)
        local info = self:GetQuestInfo(qid)
        local qname = (info and info.name) or self:GetQuestTitle(qid, name)
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
            local zone = v[3]
            if zone then zone = zone:match("^(.-)%s*·") or zone end
            local mapID = v[6] or (self.zoneToMap and self.zoneToMap[zone])
            local x, y = v[4], v[5]
            if (not mapID or not x or not y) and v[1] then
                local m2, x2, y2, n2, z2 = self:GetNpcPoint(v[1])
                if m2 then
                    if not mapID then mapID = m2 end
                    if x2 and y2 then x, y = x2, y2 end
                    if not zone then zone = z2 end
                end
            end
            local resolved = v[7]
            if not resolved then
                local n = self:GetNpcName(v[1])
                if n and n ~= ("NPC #" .. tostring(v[1])) then resolved = n end
            end
            local kind = v[8] or "Vendor"
            if kind == "Vendor" then hasVendor = true end
            seenNpc[v[1]] = true
            out[#out + 1] = {
                npcID = v[1],
                name = resolved or v[2] or ("NPC #" .. tostring(v[1])),
                enName = v[2],
                zone = zone,
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
                            name = name or ("NPC #" .. npcID),
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
        return src[7], src[8], src[9], (src[6] or src[2] or "商人")
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
            return info.mapID, info.x, info.y, (info.npcName or info.name or "任务")
        end
    elseif kind == "drop" and src[14] then
        local mapID, x, y, name = self:GetNpcPoint(src[14])
        if not mapID and src[3] and self.zoneToMap then
            mapID = self.zoneToMap[src[3]]
        end
        if mapID then
            return mapID, x, y, name
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
        local mapID, x, y, title = self:GetSourceMap(s)
        if mapID then add(mapID, x, y, title, s[3]) end
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
            if info and info.enderID and info.enderMapID then
                add(info.enderMapID, info.enderX, info.enderY,
                    (info.enderName or "交付 NPC") .. "（交付）", info.enderZone)
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

function ns:PinPoint(point)
    if not point then
        self:Print("没有可标记的位置。")
        return
    end
    local mapID, x, y = point.mapID, point.x, point.y
    local mapInfo = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    if not mapInfo then
        self:Print("地图 ID 无效：" .. tostring(mapID))
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
    if C_Map and C_Map.OpenMap then
        pcall(C_Map.OpenMap, mapID)
    elseif ToggleWorldMap then
        pcall(ToggleWorldMap)
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
        self:Print("没有这个 NPC 的位置记录。")
        return
    end
    self:PinPoint({ mapID = mapID, x = x, y = y, title = name or ("NPC #" .. tostring(npcID)), zone = zone })
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
