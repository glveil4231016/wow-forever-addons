local ADDON, PB = ...
PB.Test = PB.Test or { pass = 0, fails = {} }

function PB.Test.it(name, fn)
  local ok, err = pcall(fn)
  if ok then
    PB.Test.pass = PB.Test.pass + 1
  else
    PB.Test.fails[#PB.Test.fails + 1] = tostring(name) .. " -> " .. tostring(err)
  end
end

function PB.Test.eq(actual, expected, msg)
  if actual ~= expected then
    error((msg or "eq") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

function PB.Test.near(actual, expected, eps, msg)
  eps = eps or 0.001
  if actual == nil or math.abs(actual - expected) > eps then
    error((msg or "near") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

function PB.Test.truthy(v, msg)
  if not v then error((msg or "truthy") .. ": got falsy", 2) end
end

function PB.Test.report()
  print(string.format("PASS %d  FAIL %d", PB.Test.pass, #PB.Test.fails))
  for i = 1, #PB.Test.fails do print("FAIL " .. PB.Test.fails[i]) end
  return #PB.Test.fails
end

function GetBuildInfo() return "1.60.1", "70862", "20261110", 16001 end
function time() return 1762732800 end
function date(fmt, t) return os.date(fmt, t) end
function UnitFactionGroup() return "Alliance", "联盟" end

C_Item = {
  GetItemNameByID = function(id) return id == 2589 and "亚麻布" or nil end,
}
UIParent = {}
SlashCmdList = {}
function CreateFrame()
  local f = {}
  f.SetScript = function() end
  f.Hide = function() end
  f.Show = function() end
  f.RegisterEvent = function() end
  f.CreateFontString = function() return { SetText = function() end } end
  return f
end
C_Timer = { After = function(_, fn) fn() end, NewTicker = function() return { Cancel = function() end } end }
