local ADDON, PB = ...
local M = PB.Market

local function listing(id, qty, unit)
  return { itemID = id, qty = qty, unit = unit }
end

PB.Test.it("aggregate min num qty", function()
  local items = M.Aggregate({
    listing(2589, 20, 100), listing(2589, 5, 80), listing(2589, 10, 120),
  }, { [2589] = true })
  PB.Test.eq(items[2589].min, 80)
  PB.Test.eq(items[2589].num, 3)
  PB.Test.eq(items[2589].qty, 35)
end)

PB.Test.it("depth uses cheapest 20 percent", function()
  local items = M.Aggregate({
    listing(100, 10, 10), listing(100, 10, 20), listing(100, 80, 100),
  }, { [100] = true }, { capUnits = 20 })
  PB.Test.near(items[100].depth, 15)
end)

PB.Test.it("depth default is 20 percent of qty", function()
  local items = M.Aggregate({
    listing(104, 50, 10), listing(104, 50, 100),
  }, { [104] = true })
  PB.Test.near(items[104].depth, 10)
end)

PB.Test.it("depth ignores zero price", function()
  local items = M.Aggregate({ listing(101, 5, 0), listing(101, 5, 50) }, { [101] = true })
  PB.Test.eq(items[101].min, 50)
  PB.Test.near(items[101].depth, 50)
end)

PB.Test.it("non interesting falls back to min", function()
  local items = M.Aggregate({ listing(102, 5, 70), listing(102, 5, 90) }, {})
  PB.Test.eq(items[102].depth, 70)
end)

PB.Test.it("ladder truncation flagged", function()
  local list = {}
  for i = 1, 10 do list[i] = listing(103, 1, i) end
  local items = M.Aggregate(list, { [103] = true }, { maxLadder = 3 })
  PB.Test.eq(items[103].truncated, true)
end)

PB.Test.it("parse item link id", function()
  PB.Test.eq(M.ParseItemLinkID("|cff9d9d9d|Hitem:2589::::::::::|h[亚麻布]|h|r"), 2589)
  PB.Test.eq(M.ParseItemLinkID(nil), nil)
end)

PB.Test.it("resolve fields from record", function()
  local vals = { n = 13 }
  vals[10] = 500
  vals[11] = 40
  vals[12] = 2589
  local ok, fields = M.ResolveFields(vals, 2589)
  PB.Test.truthy(ok)
  PB.Test.eq(fields.id, 12)
  PB.Test.eq(fields.qty, 11)
  PB.Test.eq(fields.price, 10)
end)

PB.Test.it("resolve fields fails on mismatch", function()
  PB.Test.eq(M.ResolveFields({ n = 3, 1, 2, 3 }, 999), false)
end)
