-- BlackEvidence / Blacklist.lua
-- 按 profile 分仓的黑名单数据层。所有身份比较都走 BE.Identity。

local ADDON, BE = ...
BE.Blacklist = BE.Blacklist or {}
local B = BE.Blacklist

local guidIndex = {}     -- guid -> key
local indexedFor = nil   -- 当前索引对应的 profile

local function db()
    return _G.BlackEvidenceDB
end

local function profileId()
    return (BE.Profile and BE.Profile.id) or "retail"
end

function B.Store()
    local d = db()
    if type(d) ~= "table" then
        d = {}
        _G.BlackEvidenceDB = d
    end
    if type(d.profiles) ~= "table" then d.profiles = {} end
    local id = profileId()
    local p = d.profiles[id]
    if type(p) ~= "table" then p = {}; d.profiles[id] = p end
    if type(p.blacklist) ~= "table" then p.blacklist = {} end
    return p.blacklist
end

local function normalizeNote(note)
    if note == nil then return "" end
    note = tostring(note)
    note = note:gsub("\r\n", "\n"):gsub("\r", "\n")
    return BE.Util.Truncate(note, 2000)
end

local function entryFrom(info, note, source)
    return {
        key       = info.key,
        name      = info.name,
        surname   = info.surname,
        realm     = info.realm,
        guid      = info.guid,
        note      = normalizeNote(note),
        source    = source or "manual",
        hits      = 0,
        lastSeen  = 0,
        createdAt = time(),
        updatedAt = time(),
    }
end

local function isValidEntry(v)
    return type(v) == "table"
        and type(v.key) == "string" and v.key ~= ""
        and type(v.name) == "string" and v.name ~= ""
end

-- 重建 GUID 索引，并顺手清洗脏数据 / 按 GUID 去重
function B.RebuildIndex()
    local store = B.Store()
    local seenByGuid = {}

    for key, v in pairs(store) do
        if not isValidEntry(v) or v.key ~= key then
            store[key] = nil
        else
            v.note = normalizeNote(v.note)
            v.hits = tonumber(v.hits) or 0
            v.createdAt = tonumber(v.createdAt) or time()
            v.updatedAt = tonumber(v.updatedAt) or v.createdAt
            if v.guid and v.guid ~= "" then
                local prev = seenByGuid[v.guid]
                if prev then
                    -- 同一 GUID：保留更早的创建时间、更晚的备注
                    prev.createdAt = math.min(prev.createdAt, v.createdAt)
                    prev.hits = math.max(prev.hits or 0, v.hits or 0)
                    if (v.updatedAt or 0) > (prev.updatedAt or 0) then
                        prev.note = v.note
                        prev.updatedAt = v.updatedAt
                    end
                    if type(v.name) == "string" and v.name ~= "" then prev.name = v.name end
                    if v.surname then prev.surname = v.surname end
                    if v.realm then prev.realm = v.realm end
                    store[key] = nil
                else
                    seenByGuid[v.guid] = v
                end
            end
        end
    end

    for k in pairs(guidIndex) do guidIndex[k] = nil end
    for key, v in pairs(store) do
        if v.guid and v.guid ~= "" then guidIndex[v.guid] = key end
    end
    indexedFor = profileId()
end

local function ensureIndex()
    if indexedFor ~= profileId() then
        B.RebuildIndex()
    end
end

function B.Get(key)
    if not key then return nil end
    ensureIndex()
    return B.Store()[key]
end

function B.FindByGUID(guid)
    if not guid or guid == "" then return nil end
    ensureIndex()
    local key = guidIndex[guid]
    return key and B.Store()[key] or nil
end

-- 优先 key，其次 GUID，最后（只有在当前客户端拿不到服务器/姓时）用名字兜底
function B.Find(info)
    if type(info) ~= "table" then return nil end
    ensureIndex()
    local store = B.Store()

    local e = info.key and store[info.key] or nil
    if e then return e end

    if info.guid then
        local k = guidIndex[info.guid]
        if k and store[k] then return store[k] end
    end

    if not BE.Profile.Cap("surname") and not info.realm and info.name then
        local target = BE.Util.AsciiLower(info.name)
        for _, v in pairs(store) do
            if type(v.name) == "string" and BE.Util.AsciiLower(v.name) == target then
                -- 只在不产生歧义时返回
                if v.realm == nil or v.realm == "" then
                    BE.Log.Debug("Blacklist", "按名字兜底命中：%s（无服务器信息）", tostring(v.name))
                    return v
                end
            end
        end
    end

    return nil
end

function B.Add(info, note, source)
    if type(info) ~= "table" or type(info.key) ~= "string" or info.key == "" then
        return nil, false
    end
    ensureIndex()
    local store = B.Store()

    local entry = store[info.key]
    if not entry and info.guid then
        local byGuid = B.FindByGUID(info.guid)
        if byGuid then entry = byGuid end
    end

    if entry then
        entry.note = normalizeNote(note)
        entry.updatedAt = time()
        entry.name = info.name or entry.name
        entry.surname = info.surname or entry.surname
        entry.realm = info.realm or entry.realm
        if info.guid and info.guid ~= "" then
            entry.guid = info.guid
            guidIndex[info.guid] = entry.key
        end
        if source then entry.source = source end
        BE.Log.Info("Blacklist", "更新备注：%s", BE.Identity.Display(entry))
        return entry, false
    end

    entry = entryFrom(info, note, source)
    store[entry.key] = entry
    if entry.guid and entry.guid ~= "" then guidIndex[entry.guid] = entry.key end
    BE.Log.Info("Blacklist", "新增：%s（备注 %d 字）", BE.Identity.Display(entry), #(entry.note or ""))
    return entry, true
end

function B.Update(key, note)
    ensureIndex()
    local entry = B.Store()[key]
    if not entry then return false end
    entry.note = normalizeNote(note)
    entry.updatedAt = time()
    return true
end

function B.Remove(key)
    if not key then return false end
    ensureIndex()
    local store = B.Store()
    local entry = store[key]
    if not entry then return false end
    if entry.guid and guidIndex[entry.guid] == key then
        guidIndex[entry.guid] = nil
    end
    store[key] = nil
    BE.Log.Info("Blacklist", "删除：%s", BE.Identity.Display(entry))
    return true
end

function B.Hit(key)
    ensureIndex()
    local entry = B.Store()[key]
    if not entry then return end
    entry.hits = (tonumber(entry.hits) or 0) + 1
    entry.lastSeen = time()
end

function B.Count()
    ensureIndex()
    local n = 0
    for _ in pairs(B.Store()) do n = n + 1 end
    return n
end

local function sortKeyOf(v)
    return (tonumber(v.lastSeen) or 0) * 1000000000
        + (tonumber(v.createdAt) or 0)
end

function B.Iterate()
    ensureIndex()
    local out = {}
    for _, v in pairs(B.Store()) do out[#out + 1] = v end
    table.sort(out, function(a, b) return sortKeyOf(a) > sortKeyOf(b) end)
    return out
end

function B.Search(q)
    ensureIndex()
    local needle = BE.Util.Trim(q)
    if not needle or needle == "" then return B.Iterate() end
    needle = BE.Util.AsciiLower(needle)

    local out = {}
    for _, v in pairs(B.Store()) do
        local hay = table.concat({
            tostring(v.name or ""), tostring(v.surname or ""),
            tostring(v.realm or ""), tostring(v.note or ""),
        }, "\n")
        if BE.Util.AsciiLower(hay):find(needle, 1, true) then
            out[#out + 1] = v
        end
    end
    table.sort(out, function(a, b) return sortKeyOf(a) > sortKeyOf(b) end)
    return out
end

function B.Cleanup()
    B.RebuildIndex()
    return B.Count()
end

function B.Init()
    B.RebuildIndex()
    BE.Log.Info("Blacklist", "已加载：profile=%s，条目 %d", profileId(), B.Count())
end

