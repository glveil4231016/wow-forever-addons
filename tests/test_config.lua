local ADDON, PB = ...

PB.Test.it("defaults exist", function()
  PB.Test.eq(PB.Config.Defaults.ahCutPercent, 5)
  PB.Test.eq(PB.Config.Defaults.maxRecursion, 3)
  PB.Test.eq(PB.Config.Defaults.scanCooldownSec, 900)
end)

PB.Test.it("load fills and clamps", function()
  local db = { settings = { ahCutPercent = 999, maxRecursion = -2 } }
  local cfg = PB.Config.New(db)
  PB.Test.eq(cfg:Get("ahCutPercent"), 50)
  PB.Test.eq(cfg:Get("maxRecursion"), 1)
  PB.Test.eq(cfg:Get("depthPercent"), 20)
end)

PB.Test.it("set clamps", function()
  local cfg = PB.Config.New({})
  cfg:Set("minMarginPercent", 250)
  PB.Test.eq(cfg:Get("minMarginPercent"), 100)
end)

PB.Test.it("market key has separator", function()
  PB.Profile.Detect()
  local key = PB.Profile.MarketKey()
  PB.Test.truthy(type(key) == "string" and key:find("|") ~= nil, "market key must contain |")
end)
