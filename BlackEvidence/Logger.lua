-- BlackEvidence / Logger.lua
-- 分级日志 + 环形缓冲 + 会话号 + 锚点 + 诊断抓取。
-- SavedVariables: BlackEvidenceLog = { session, seq, sessionFrom, entries, marks, diag }
-- 约定：任何值都可能为 secret，日志本身绝不能因此报错或泄露内容。

local ADDON, BE = ...
BE.Log = BE.Log or {}
local L = BE.Log

-- 级别：trace < debug < info < warn < error
local LEVELS = { trace = 1, debug = 2, info = 3, warn = 4, error = 5 }

local DEFAULT_RING = 1000
local MIN_RING     = 100
local MAX_RING     = 2000   -- 硬上限：内存与落盘块都不超过这个数
local MARKS_MAX    = 100
local DIAG_MAX     = 3000
local CAPTURE_MAX  = 2000

local PREFIX = "|cff7c6cffBE|r"
local LEVEL_COLOR = {
  trace = "|cff9aa0b5",
  debug = "|cff9aa0b5",
  info  = "|cff5cc8ff",
  warn  = "|cffffb020",
  error = "|cffff5c5c",
}

-- 公开字段（Slash 可直接赋值 BE.Log.Level 改变级别）
L.Session = tonumber(L.Session) or 0
L.Level   = (type(L.Level) == "string" and L.Level) or "debug"

local store             -- BlackEvidenceLog
local entries           -- store.entries（环形缓冲本体）
local ringSize          = DEFAULT_RING
local head              = 0   -- 最新一条所在槽位
local count             = 0   -- 有效条数
local seqCount          = 0   -- 累计写入条数（单调递增）
local sessionNo         = L.Session
local sessionStarted    = false
local bound             = false
local capture           = nil
local installedHandler  = false
local prevHandler       = nil
local mirrorLevel       = "warn"   -- 聊天窗镜像阈值（内部，默认只镜像 warn 以上）

----------------------------------------------------------------------
-- 基础工具
----------------------------------------------------------------------

local function timeFn()
  if type(time) == "function" then
    local ok, t = pcall(time)
    if ok and type(t) == "number" then return t end
  end
  return 0
end

local function dateFn(pattern, t)
  if type(date) == "function" then
    local ok, s = pcall(date, pattern, t)
    if ok and type(s) == "string" then return s end
  end
  return tostring(t)
end

-- Secret 判定：必须早于任何 tostring / string.format 处理。
local function isSecret(v)
  if v == nil then return false end
  if type(_G.issecretvalue) ~= "function" then return false end
  local ok, r = pcall(_G.issecretvalue, v)
  return ok and r and true or false
end

-- 安全字符串化：secret、function、table、userdata 都走固定占位，不碰内容。
local function safeToString(v)
  if isSecret(v) then return "<secret>" end
  local t = type(v)
  if t == "string" then return v end
  if t == "number" or t == "boolean" then return tostring(v) end
  if v == nil then return "nil" end
  if t == "function" then return "<function>" end
  if t == "table" then
    local n = 0
    for _ in pairs(v) do
      n = n + 1
      if n > 500 then break end
    end
    return "<table:" .. n .. ">"
  end
  if t == "userdata" then return "<userdata>" end
  local ok, s = pcall(tostring, v)
  if ok and type(s) == "string" then return s end
  return "<" .. t .. ">"
end

local function stampOf(t, pattern)
  return dateFn(pattern, tonumber(t) or 0)
end

local function printToChat(text)
  local cf = _G.DEFAULT_CHAT_FRAME
  if cf and type(cf.AddMessage) == "function" then
    cf:AddMessage(text)
    return true
  end
  if type(print) == "function" then
    print(text)
    return true
  end
  return false
end

local function chatPrefix()
  local C = BE.Config
  if type(C) == "table" then
    local p = C.prefix or C.PREFIX
    if type(p) == "string" and p ~= "" then return p end
  end
  return PREFIX
end

----------------------------------------------------------------------
-- 诊断抓取（把聊天窗镜像内容暂存，CaptureStop 时落到 store.diag）
----------------------------------------------------------------------

local function captureLine(text)
  if capture and #capture < CAPTURE_MAX then
    capture[#capture + 1] = text
  end
end

----------------------------------------------------------------------
-- 配置 / 表工具
----------------------------------------------------------------------

local function setting(key, default)
  local db = _G.BlackEvidenceDB
  if type(db) == "table" and type(db.settings) == "table" then
    local v = db.settings[key]
    if v ~= nil then return v end
  end
  return default
end

local function clampRing(n)
  n = tonumber(n) or DEFAULT_RING
  n = math.floor(n)
  if n < MIN_RING then n = MIN_RING end
  if n > MAX_RING then n = MAX_RING end
  return n
end

-- 去掉表里的全部数字键（用于重建环形缓冲）
local function wipeNumeric(t)
  local keys = {}
  for k in pairs(t) do
    if type(k) == "number" then keys[#keys + 1] = k end
  end
  for i = 1, #keys do t[keys[i]] = nil end
end

-- 只保留数组最后 max 项，避免 table.remove(t,1) 的 O(n^2)
local function trimArray(t, max)
  local n = #t
  if n <= max then return end
  local drop = n - max
  for i = 1, max do t[i] = t[i + drop] end
  for i = max + 1, n do t[i] = nil end
end

local function marksTable()
  if type(store) ~= "table" then return {} end
  if type(store.marks) ~= "table" then store.marks = {} end
  local marks = store.marks
  trimArray(marks, MARKS_MAX)
  return marks
end

local function diagTable()
  if type(store) ~= "table" then return {} end
  if type(store.diag) ~= "table" then store.diag = {} end
  return store.diag
end

----------------------------------------------------------------------
-- 环形缓冲
----------------------------------------------------------------------

local function entryAt(k)
  if count <= 0 or k < 1 or k > count then return nil end
  local idx = head - count + k
  while idx < 1 do idx = idx + ringSize end
  while idx > ringSize do idx = idx - ringSize end
  local e = entries[idx]
  if type(e) ~= "table" then return nil end
  return e
end

local function push(entry)
  if type(entries) ~= "table" or ringSize <= 0 then return end

  head = head + 1
  if head > ringSize then head = 1 end
  entries[head] = entry

  if count < ringSize then count = count + 1 end
  seqCount = seqCount + 1

  entries.__head  = head
  entries.__count = count
  entries.__seq   = seqCount
  entries.__cap   = ringSize
  if type(store) == "table" then store.seq = seqCount end
end

-- 把上一次落盘的缓冲区还原成当前 ringSize（超出部分只保留最新）
local function restoreEntries(saved)
  local oldCap   = tonumber(saved.__cap) or 0
  local oldHead  = tonumber(saved.__head)
  local oldCount = tonumber(saved.__count)
  local savedSeq = tonumber(saved.__seq) or 0

  if not oldHead or not oldCount then
    -- 兼容只有连续数字键的旧格式
    local n = 0
    while type(saved[n + 1]) == "table" do n = n + 1 end
    oldHead, oldCount, oldCap = n, n, math.max(n, 1)
  end

  oldCount = math.max(0, math.floor(oldCount))
  oldHead  = math.floor(oldHead)
  oldCap   = math.floor(oldCap)
  if oldCap < 1 then oldCap = math.max(oldHead, oldCount, 1) end
  if oldHead < 1 or oldHead > oldCap then
    oldHead = oldCount
    oldCap  = math.max(oldCap, oldHead, 1)
  end
  if oldCount > oldCap then oldCount = oldCap end

  local keep = math.min(oldCount, ringSize)
  local list = {}
  for k = oldCount - keep + 1, oldCount do
    local idx = oldHead - oldCount + k
    while idx < 1 do idx = idx + oldCap end
    while idx > oldCap do idx = idx - oldCap end
    local e = saved[idx]
    if type(e) == "table" and type(e.msg) == "string" then
      -- 旧存档可能残留 secret，落回之前先抹掉
      if isSecret(e.msg) then e.msg = "<secret>" end
      if isSecret(e.tag) then e.tag = "<secret>" end
      list[#list + 1] = e
    end
  end

  wipeNumeric(saved)
  for i = 1, #list do saved[i] = list[i] end

  head, count = #list, #list
  seqCount = math.max(savedSeq, tonumber(store.seq) or 0, count)
  local last = list[#list]
  if last and (tonumber(last.seq) or 0) > seqCount then
    seqCount = tonumber(last.seq)
  end

  entries = saved
  entries.__cap   = ringSize
  entries.__head  = head
  entries.__count = count
  entries.__seq   = seqCount
  store.entries   = entries
end

local function bind()
  if bound then return end

  local saved = _G.BlackEvidenceLog
  if type(saved) ~= "table" then
    saved = {}
    _G.BlackEvidenceLog = saved
  end
  store = saved

  ringSize = clampRing(setting("logRingSize", DEFAULT_RING))

  if type(saved.entries) == "table" then
    restoreEntries(saved.entries)
  else
    entries = {}
    head, count = 0, 0
    seqCount = tonumber(saved.seq) or 0
    entries.__cap   = ringSize
    entries.__head  = 0
    entries.__count = 0
    entries.__seq   = seqCount
    saved.entries   = entries
  end

  if type(saved.marks) ~= "table" then saved.marks = {} end
  if type(saved.diag)  ~= "table" then saved.diag  = {} end
  trimArray(saved.marks, MARKS_MAX)
  trimArray(saved.diag, DIAG_MAX)

  sessionNo = tonumber(saved.session) or 0
  L.Session = sessionNo
  saved.seq = seqCount

  local lvl = setting("logLevel", nil)
  if type(lvl) == "string" and LEVELS[lvl:lower()] then
    L.Level = lvl:lower()
  end
  local mirror = setting("chatMirrorLevel", nil)
  if type(mirror) == "string" and LEVELS[mirror:lower()] then
    mirrorLevel = mirror:lower()
  end

  bound = true
end

local function ensure()
  if not bound then
    bind()
    return
  end
  -- SavedVariables 在文件执行完之后才注入：若中途已经用过临时表，这里切回真实存档
  local saved = _G.BlackEvidenceLog
  if type(saved) == "table" and saved ~= store then
    bound = false
    bind()
  end
end

----------------------------------------------------------------------
-- 格式化与输出
----------------------------------------------------------------------

local function levelValue(name)
  if type(name) == "number" then return name end
  if type(name) == "string" then
    local v = LEVELS[name:lower()]
    if v then return v end
  end
  return LEVELS.debug
end

local function buildMessage(fmt, ...)
  local argc = select("#", ...)
  if argc == 0 then
    return safeToString(fmt)
  end

  -- 格式串本身是 secret：整条消息都不展开
  if isSecret(fmt) then return "<secret>" end

  local vals = {}
  for i = 1, argc do
    local v = select(i, ...)
    if isSecret(v) then
      vals[i] = "<secret>"
    else
      vals[i] = v
    end
  end

  if type(fmt) == "string" then
    -- Lua 5.1：用全局 unpack，不用 table.unpack
    local ok, s = pcall(string.format, fmt, unpack(vals, 1, argc))
    if ok and type(s) == "string" then return s end
  end

  local parts = { safeToString(fmt) }
  for i = 1, argc do
    parts[#parts + 1] = safeToString(vals[i])
  end
  return table.concat(parts, " ")
end

local function mirrorLine(level, tag, text)
  local line = string.format("%s %s[%s]|r %s: %s",
    chatPrefix(),
    LEVEL_COLOR[level] or "",
    stampOf(timeFn(), "%H:%M:%S"),
    tag,
    text)
  printToChat(line)
  captureLine(line)
end

local function renderEntry(e, withDate)
  return string.format("%s [%s] %s: %s",
    stampOf(e.t, withDate and "%Y-%m-%d %H:%M:%S" or "%H:%M:%S"),
    string.upper(safeToString(e.lvl)),
    safeToString(e.tag),
    safeToString(e.msg))
end

function L.Raw(level, tag, msg, ...)
  ensure()

  if not LEVELS[level] then level = "info" end
  local lv = LEVELS[level]

  local text = buildMessage(msg, ...)
  local tagText = safeToString(tag)
  if tagText == "" then tagText = "?" end

  if lv >= levelValue(L.Level) then
    push({
      seq  = seqCount + 1,
      sess = sessionNo,
      t    = timeFn(),
      lvl  = level,
      tag  = tagText,
      msg  = text,
    })
  end

  -- 聊天窗镜像：只有级别达到镜像阈值（且没被当前日志级别挡住）才输出
  if lv >= levelValue(mirrorLevel) and lv >= levelValue(L.Level) then
    mirrorLine(level, tagText, text)
  end

  return text
end

function L.Debug(tag, fmt, ...) return L.Raw("debug", tag, fmt, ...) end
function L.Info(tag, fmt, ...)  return L.Raw("info",  tag, fmt, ...) end
function L.Warn(tag, fmt, ...)  return L.Raw("warn",  tag, fmt, ...) end

function L.Error(tag, fmt, ...)
  local msg = L.Raw("error", tag, fmt, ...)
  -- 仅 trace 级别才追加调用栈，避免默认级别下刷屏
  if type(debugstack) == "function" and levelValue(L.Level) <= LEVELS.trace then
    local ok, stack = pcall(debugstack, 2, 12, 12)
    if ok and stack then
      L.Raw("trace", tag, "stack: %s", stack)
    end
  end
  return msg
end

----------------------------------------------------------------------
-- 会话
----------------------------------------------------------------------

local function startSession()
  ensure()
  if sessionStarted then return sessionNo end
  sessionStarted = true

  sessionNo = (tonumber(store.session) or 0) + 1
  store.session = sessionNo
  -- 关键修复：必须是“下一条日志的 seq”，不是缓冲条数
  store.sessionFrom = seqCount + 1
  store.sessionAt   = timeFn()
  store.seq         = seqCount
  L.Session         = sessionNo

  L.Raw("info", "Logger", "会话 #%d 开始（缓冲 %d/%d，累计 %d）",
    sessionNo, count, ringSize, seqCount)
  return sessionNo
end

----------------------------------------------------------------------
-- 锚点
----------------------------------------------------------------------

function L.Mark(label)
  ensure()

  local text = safeToString(label)
  if text == "" then text = "标记" end
  local msg = "===== " .. text .. " ====="
  local seq = seqCount + 1

  -- 锚点必须有自己的 seq，所以不受 logLevel 过滤
  push({
    seq  = seq,
    sess = sessionNo,
    t    = timeFn(),
    lvl  = "warn",
    tag  = "MARK",
    msg  = msg,
  })

  local marks = marksTable()
  marks[#marks + 1] = {
    label = text,
    text  = text,   -- 兼容旧写法
    at    = seq,
    t     = timeFn(),
    sess  = sessionNo,
  }
  trimArray(marks, MARKS_MAX)

  if levelValue("warn") >= levelValue(mirrorLevel)
      and levelValue("warn") >= levelValue(L.Level) then
    mirrorLine("warn", "MARK", msg)
  end
  return seq
end

----------------------------------------------------------------------
-- 导出
----------------------------------------------------------------------

function L.Dump(n)
  ensure()

  n = tonumber(n)
  if not n then n = 200 end
  n = math.floor(n)
  if n <= 0 then n = count end
  if n > count then n = count end

  local lines = {}
  local start = count - n + 1
  if start < 1 then start = 1 end
  for k = start, count do
    local e = entryAt(k)
    if e then lines[#lines + 1] = renderEntry(e, true) end
  end
  return table.concat(lines, "\n")
end

function L.DumpSince(anchor)
  ensure()

  local marks = marksTable()
  local mark, since

  if type(anchor) == "number" then
    since = anchor
  elseif anchor == nil or anchor == "" then
    mark = marks[#marks]
    if mark then since = tonumber(mark.at) end
  else
    local asNumber = tonumber(anchor)
    if asNumber then
      since = asNumber
    else
      local needle = safeToString(anchor)
      for i = #marks, 1, -1 do
        local label = safeToString(marks[i].label or marks[i].text)
        if label ~= "" and label:find(needle, 1, true) then
          mark = marks[i]
          break
        end
      end
      if not mark then
        return nil, "没有找到锚点「" .. needle .. "」（先用 /be mark 打一个）"
      end
      since = tonumber(mark.at)
    end
  end

  if not since then
    return nil, "还没有锚点（先用 /be mark 打一个）"
  end

  local lines = {}
  for k = 1, count do
    local e = entryAt(k)
    if e and (tonumber(e.seq) or 0) > since then
      lines[#lines + 1] = renderEntry(e, true)
    end
  end
  return table.concat(lines, "\n"), nil, mark
end

function L.DumpSession()
  ensure()

  local from = tonumber(store.sessionFrom) or 1
  local lines = {}
  for k = 1, count do
    local e = entryAt(k)
    if e and ((tonumber(e.sess) or 0) == sessionNo
          or (tonumber(e.seq) or 0) >= from) then
      lines[#lines + 1] = renderEntry(e, true)
    end
  end
  return table.concat(lines, "\n")
end

----------------------------------------------------------------------
-- 错误处理器（链式，保留上一任）
----------------------------------------------------------------------

local function currentErrorHandler()
  if type(_G.geterrorhandler) == "function" then
    local ok, h = pcall(_G.geterrorhandler)
    if ok and type(h) == "function" then return h end
  end
  return nil
end

function L.InstallErrorHandler()
  if installedHandler then return true end
  if type(_G.seterrorhandler) ~= "function" then return false end

  -- 拿不到上一任就不安装：宁可不记录，也不能改变默认报错行为
  local prev = currentErrorHandler()
  if type(prev) ~= "function" then return false end
  prevHandler = prev

  local function handler(err)
    pcall(function()
      ensure()
      L.Raw("error", "Lua", "%s", err)
    end)
    -- 原样交给上一任，行为保持不变
    prevHandler(err)
  end

  local ok = pcall(_G.seterrorhandler, handler)
  if not ok then return false end
  installedHandler = true
  return true
end

----------------------------------------------------------------------
-- 诊断抓取
----------------------------------------------------------------------

function L.CaptureStart()
  capture = {}
  return capture
end

function L.CaptureStop()
  local lines = capture
  capture = nil

  if type(lines) == "table" and #lines > 0 then
    ensure()
    local diag = diagTable()
    diag[#diag + 1] = string.format("--- capture %s 会话 %d（%d 行）---",
      stampOf(timeFn(), "%Y-%m-%d %H:%M:%S"), sessionNo, #lines)
    for i = 1, #lines do
      diag[#diag + 1] = lines[i]
    end
    trimArray(diag, DIAG_MAX)
  end

  return lines or {}
end

----------------------------------------------------------------------
-- 事件：ADDON_LOADED 绑定存档；PLAYER_LOGIN 递增会话号
----------------------------------------------------------------------

local events
if type(_G.CreateFrame) == "function" then
  local ok, frame = pcall(_G.CreateFrame, "Frame")
  if ok then events = frame end
end

if events then
  events:RegisterEvent("ADDON_LOADED")
  events:RegisterEvent("PLAYER_LOGIN")
  events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
      if arg1 == ADDON then ensure() end
    elseif event == "PLAYER_LOGIN" then
      startSession()
    end
  end)
end
