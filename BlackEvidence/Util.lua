-- BlackEvidence / Util.lua
-- 纯工具：安全调用、secret 判定、UTF-8 安全截断、颜色/物品链接、客户端标签。
-- 身份相关（名字/服务器/姓）不在这里，全部见 Identity.lua。

local ADDON, BE = ...
BE.Util = BE.Util or {}
local U = BE.Util

----------------------------------------------------------------------
-- 基础
----------------------------------------------------------------------

-- 统一安全调用：返回 ok, 第一个返回值, ...
function U.SafeCall(fn, ...)
  if type(fn) ~= "function" then return false, nil end
  return pcall(fn, ...)
end

-- Secret 判定：优先信任 Profile 的探测结果；Profile 尚未探测时按 API 存在性兜底
function U.IsSecret(v)
  local P = BE.Profile
  local caps = (type(P) == "table") and P.caps or nil

  local enabled
  if caps then
    enabled = caps.secret and true or false
  else
    enabled = type(_G.issecretvalue) == "function"
  end
  if not enabled or type(_G.issecretvalue) ~= "function" then
    return false
  end

  local ok, r = pcall(_G.issecretvalue, v)
  return ok and r and true or false
end

-- 可安全当普通字符串处理（string 且非 secret）
function U.IsPlain(v)
  return type(v) == "string" and not U.IsSecret(v)
end

local function isText(s)
  return type(s) == "string" and not U.IsSecret(s)
end

----------------------------------------------------------------------
-- UTF-8 安全截断（Lua 5.1，不依赖 utf8 库）
----------------------------------------------------------------------

-- 返回 <= n 的字节位置，保证 s:sub(1, 结果) 是合法 UTF-8
function U.Utf8SafeEnd(s, n)
  if not isText(s) then return 0 end
  n = tonumber(n) or 0
  if n <= 0 then return 0 end
  if n >= #s then return #s end

  local p = math.floor(n)
  local guard = 0
  -- 回退到所在字符的起始字节（10xxxxxx 是续字节）
  while p > 0 and guard < 4 do
    local b = s:byte(p)
    if not b or b < 0x80 or b >= 0xC0 then break end
    p = p - 1
    guard = guard + 1
  end
  if p <= 0 then return 0 end

  local b = s:byte(p)
  local len = 1
  if b >= 0xF0 then len = 4
  elseif b >= 0xE0 then len = 3
  elseif b >= 0xC0 then len = 2 end

  if p + len - 1 <= n then return p + len - 1 end
  return p - 1   -- 这个字符被切了一半，整个丢掉
end

-- 返回 >= pos 的第一个字符起始字节位置；空串/越界返回 #s + 1
function U.Utf8SafeStart(s, pos)
  if not isText(s) then return 1 end
  pos = tonumber(pos) or 1
  if pos < 1 then pos = 1 end
  if pos > #s then return #s + 1 end

  local p = math.floor(pos)
  while p <= #s do
    local b = s:byte(p)
    if not b or b < 0x80 or b >= 0xC0 then return p end
    p = p + 1
  end
  return #s + 1
end

-- 取文本最后 n 个字节（从完整字符开始），过长时加截断提示
function U.Tail(s, n)
  if not isText(s) then return "" end
  n = tonumber(n) or 6000
  if n <= 0 then return "" end
  if #s <= n then return s end

  local start = #s - math.floor(n) + 1
  if start < 1 then start = 1 end
  start = U.Utf8SafeStart(s, start)
  if start > #s then return "" end

  local tail = s:sub(start)
  local nl = tail:find("\n", 1, true)
  if nl and nl < 300 then tail = tail:sub(nl + 1) end
  return "…（更早内容已截断）\n" .. tail
end

-- 截断到 n 个字节以内，自动回退到字符边界
function U.Truncate(s, n, suffix)
  if not isText(s) then return "" end
  n = tonumber(n) or 40
  suffix = suffix or "…"
  if n <= 0 then return suffix end
  if #s <= n then return s end

  local cut = U.Utf8SafeEnd(s, n)
  if cut <= 0 then return suffix end
  return s:sub(1, cut) .. suffix
end

----------------------------------------------------------------------
-- 文本处理
----------------------------------------------------------------------

-- 去掉颜色、链接、图标代码
function U.StripColors(s)
  if not isText(s) then return "" end
  local out = s
  out = out:gsub("|c%x%x%x%x%x%x%x%x", "")
  out = out:gsub("|c%x%x%x%x%x%x", "")
  out = out:gsub("|r", "")
  out = out:gsub("|H.-|h", "")
  out = out:gsub("|h", "")
  out = out:gsub("|T.-|t", "")
  out = out:gsub("|A.-|a", "")
  out = out:gsub("\r", "")
  return out
end

-- 物品链接 -> itemID, itemLink, itemName
function U.ParseItemLink(s)
  if not isText(s) then return nil end
  local itemID = tonumber(s:match("item:(%d+)"))
  if not itemID then return nil end
  local itemName = s:match("%[(.-)%]")
  return itemID, s, itemName
end

-- 客户端显示名：正式服 / 经典时光服（巫妖王之怒） / 无限服
function U.ClientFlavorLabel()
  local P = BE.Profile
  if type(P) ~= "table" then return "未知客户端" end

  local label = P.label
  if type(label) ~= "string" or label == "" then label = "未知客户端" end

  local sub = P.subLabel
  if type(sub) == "string" and sub ~= "" and sub ~= label then
    return label .. "（" .. sub .. "）"
  end
  return label
end

-- 全局 API 检查行："OK  name" / "MISS name"（支持 A.B.C 路径）
local function resolvePath(path)
  if type(path) ~= "string" or path == "" then return nil end
  local node = _G
  for part in path:gmatch("[^%.]+") do
    if type(node) ~= "table" then return nil end
    node = node[part]
    if node == nil then return nil end
  end
  return node
end

function U.ApiLine(name)
  if type(name) ~= "string" or name == "" then return "MISS ?" end
  if U.IsSecret(name) then return "MISS <secret>" end
  if resolvePath(name) ~= nil then return "OK  " .. name end
  return "MISS " .. name
end

----------------------------------------------------------------------
-- 小工具
----------------------------------------------------------------------

-- 去掉首尾空白
function U.Trim(s)
  if not isText(s) then return "" end
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- 只小写 ASCII A-Z，避免动到 UTF-8 多字节
function U.AsciiLower(s)
  if not isText(s) then return "" end
  return (s:gsub("[A-Z]", function(ch)
    return string.char(ch:byte() + 32)
  end))
end

-- GetTime 包装：进游戏后的秒数，失败返回 0
function U.Now()
  if type(_G.GetTime) == "function" then
    local ok, t = pcall(_G.GetTime)
    if ok and type(t) == "number" then return t end
  end
  return 0
end

function U.TableCount(t)
  if type(t) ~= "table" then return 0 end
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

local function keyLess(a, b)
  local ta, tb = type(a), type(b)
  if ta ~= tb then return ta < tb end
  if ta == "number" or ta == "string" then return a < b end
  return tostring(a) < tostring(b)
end

function U.SortedKeys(t)
  local keys = {}
  if type(t) ~= "table" then return keys end
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys, keyLess)
  return keys
end

-- 四舍五入到 digits 位小数（默认整数）
function U.Round(v, digits)
  v = tonumber(v)
  if not v then return 0 end
  digits = tonumber(digits) or 0
  local m = 10 ^ digits
  if v < 0 then return -math.floor(-v * m + 0.5) / m end
  return math.floor(v * m + 0.5) / m
end
