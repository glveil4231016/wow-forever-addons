local ADDON, PB = ...
local Cost = PB.Cost

local function ctx(prices, recipes, ahCut)
  return {
    ahCut = ahCut or 0.05,
    maxRecursion = 3,
    priceOf = function(id) return prices[id] or {} end,
    recipesFor = function(id) return recipes[id] or {} end,
  }
end

local function recipe(id, resultID, count, reagents)
  return { id = id, result = { itemID = resultID, count = count or 1 }, reagents = reagents or {} }
end

PB.Test.it("simple profit after cut", function()
  local c = ctx({ [100] = { ah = 100 }, [200] = { ah = 1000 } },
    { [200] = { recipe(1, 200, 1, { { itemID = 100, count = 2 } }) } })
  local r = Cost.CraftProfit(recipe(1, 200, 1, { { itemID = 100, count = 2 } }), c)
  PB.Test.eq(r.cost, 200)
  PB.Test.eq(r.value, 950)
  PB.Test.eq(r.profit, 750)
  PB.Test.near(r.margin, 375)
end)

PB.Test.it("missing reagent price", function()
  local c = ctx({ [200] = { ah = 1000 } }, {})
  local r = Cost.CraftProfit(recipe(1, 200, 1, { { itemID = 999, count = 1 } }), c)
  PB.Test.truthy(r.missing)
  PB.Test.eq(r.missingCount, 1)
end)

PB.Test.it("craft intermediate cheaper", function()
  local c = ctx(
    { [10] = { ah = 30 }, [100] = { ah = 100 }, [200] = { ah = 1000 } },
    { [100] = { recipe(2, 100, 1, { { itemID = 10, count = 2 } }) } })
  local r = Cost.CraftProfit(recipe(1, 200, 1, { { itemID = 100, count = 1 } }), c)
  PB.Test.eq(r.cost, 60)
end)

PB.Test.it("multi output divides cost", function()
  local c = ctx({ [10] = { ah = 100 }, [200] = { ah = 1000 } }, {})
  local r = Cost.CraftProfit(recipe(1, 200, 2, { { itemID = 10, count = 2 } }), c)
  PB.Test.eq(r.cost, 200)
  PB.Test.eq(r.value, 1900)
  PB.Test.eq(r.profit, 1700)
end)

PB.Test.it("cycle terminates", function()
  local c = ctx({}, {
    [1] = { recipe(1, 1, 1, { { itemID = 2, count = 1 } }) },
    [2] = { recipe(2, 2, 1, { { itemID = 1, count = 1 } }) },
  })
  local r = Cost.CraftProfit(recipe(1, 1, 1, { { itemID = 2, count = 1 } }), c)
  PB.Test.truthy(r.missing)
end)

PB.Test.it("vendor beats ah", function()
  local c = ctx({ [10] = { ah = 100 }, [200] = { ah = 100, vendor = 500 } }, {})
  local r = Cost.CraftProfit(recipe(1, 200, 1, { { itemID = 10, count = 1 } }), c)
  PB.Test.eq(r.value, 500)
  PB.Test.eq(r.channel, "vendor")
end)

PB.Test.it("optional reagent ignored", function()
  local c = ctx({ [10] = { ah = 100 }, [200] = { ah = 1000 } }, {})
  local r = Cost.CraftProfit(
    recipe(1, 200, 1, { { itemID = 10, count = 1 }, { itemID = 999, count = 5, optional = true } }), c)
  PB.Test.eq(r.cost, 100)
  PB.Test.truthy(not r.missing)
end)
