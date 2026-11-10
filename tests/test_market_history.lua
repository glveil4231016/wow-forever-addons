local ADDON, PB = ...
local KEY = "normal|alliance"

PB.Test.it("history append caps length", function()
  local db = { markets = { [KEY] = { items = {} } } }
  local M = PB.Market.New(db, KEY)
  M.market.items[1] = { min = 1 }
  for i = 1, 40 do M:AppendHistory(1, 20260100 + i, 100 + i) end
  PB.Test.eq(#M.market.items[1].h, 60)
end)

PB.Test.it("median uses window", function()
  local db = { markets = { [KEY] = { items = {} } } }
  local M = PB.Market.New(db, KEY)
  M.market.items[2] = { min = 1 }
  local today = PB.Util.Today()
  M:AppendHistory(2, today - 2, 10)
  M:AppendHistory(2, today - 1, 20)
  M:AppendHistory(2, today, 30)
  PB.Test.near(M:MedianPrice(2, 7), 20)
end)

PB.Test.it("median insufficient nil", function()
  local db = { markets = { [KEY] = { items = {} } } }
  local M = PB.Market.New(db, KEY)
  PB.Test.eq(M:MedianPrice(3, 7), nil)
end)

PB.Test.it("snapshot round trip", function()
  local db = { markets = { [KEY] = { items = { [2589] = { min = 10, depth = 12, num = 3, qty = 50 } } } } }
  local M = PB.Market.New(db, KEY)
  local text = M:SnapshotText()
  local db2 = { markets = {} }
  local M2 = PB.Market.New(db2, KEY)
  M2:RestoreFromText(text)
  local it = db2.markets[KEY].items[2589]
  PB.Test.eq(it.min, 10)
  PB.Test.eq(it.depth, 12)
  PB.Test.eq(it.qty, 50)
end)
