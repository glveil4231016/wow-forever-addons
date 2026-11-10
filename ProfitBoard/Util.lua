local ADDON, PB = ...
local U = {}
PB.Util = U

function U.Has(tbl, key)
  return type(tbl) == "table" and type(tbl[key]) == "function"
end

function U.SafeCall(fn, ...)
  if type(fn) ~= "function" then return false, "not a function" end
  return pcall(fn, ...)
end

function U.Clamp(v, lo, hi)
  v = tonumber(v) or lo
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

function U.Round(v)
  if not v then return nil end
  return math.floor(v + 0.5)
end

function U.FormatMoney(copper)
  local c = math.floor(tonumber(copper) or 0)
  local neg = c < 0
  if neg then c = -c end
  local g = math.floor(c / 10000)
  local s = math.floor((c % 10000) / 100)
  local o = c % 100
  local parts = {}
  if g > 0 then parts[#parts + 1] = g .. "金" end
  if s > 0 or g > 0 then parts[#parts + 1] = s .. "银" end
  parts[#parts + 1] = o .. "铜"
  return (neg and "-" or "") .. table.concat(parts, " ")
end

function U.ParseMoney(text)
  if type(text) ~= "string" then return nil end
  text = text:gsub("%s+", "")
  if text == "" then return nil end
  local plain = tonumber(text)
  if plain then return math.floor(plain) end
  local g = tonumber(text:match("(%d+)金")) or 0
  local s = tonumber(text:match("(%d+)银")) or 0
  local c = tonumber(text:match("(%d+)铜")) or 0
  if g == 0 and s == 0 and c == 0 then return nil end
  return g * 10000 + s * 100 + c
end

function U.Today()
  return tonumber(date("%Y%m%d")) or 0
end

function U.Median(list)
  local n = #list
  if n == 0 then return nil end
  local copy = {}
  for i = 1, n do copy[i] = list[i] end
  table.sort(copy)
  if n % 2 == 1 then return copy[(n + 1) / 2] end
  return (copy[n / 2] + copy[n / 2 + 1]) / 2
end

function U.Copy(t)
  local out = {}
  for k, v in pairs(t or {}) do out[k] = v end
  return out
end
