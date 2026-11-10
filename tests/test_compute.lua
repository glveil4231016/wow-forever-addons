local ADDON, PB = ...
local C = PB.Compute

local function fakeMarket(prices)
  return { PriceOf = function(_, id) return prices[id] or {} end }
end

PB.Test.it("sorts by profit desc", function()
  PB.RecipeSource.SetSources({ static = {
    { id = 1, profession = "A", result = { itemID = 200, count = 1 }, reagents = { { itemID = 10, count = 1 } } },
    { id = 2, profession = "A", result = { itemID = 300, count = 1 }, reagents = { { itemID = 10, count = 1 } } },
  }, game = {} })
  local res = C.ComputeAll(
    fakeMarket({ [10] = { ah = 100 }, [200] = { ah = 1000 }, [300] = { ah = 400 } }),
    { ahCutPercent = 5, maxRecursion = 3 })
  PB.Test.eq(#res, 2)
  PB.Test.eq(res[1].recipe.id, 1)
end)

PB.Test.it("missing sorted last", function()
  PB.RecipeSource.SetSources({ static = {
    { id = 1, profession = "A", result = { itemID = 200, count = 1 }, reagents = { { itemID = 404, count = 1 } } },
    { id = 2, profession = "A", result = { itemID = 300, count = 1 }, reagents = { { itemID = 10, count = 1 } } },
  }, game = {} })
  local res = C.ComputeAll(
    fakeMarket({ [10] = { ah = 100 }, [300] = { ah = 400 } }),
    { ahCutPercent = 5, maxRecursion = 3 })
  PB.Test.eq(res[1].recipe.id, 2)
  PB.Test.truthy(res[2].missing)
end)

PB.Test.it("filter by profit", function()
  PB.RecipeSource.SetSources({ static = {
    { id = 1, profession = "A", result = { itemID = 200, count = 1 }, reagents = { { itemID = 10, count = 1 } } },
  }, game = {} })
  local res = C.ComputeAll(
    fakeMarket({ [10] = { ah = 100 }, [200] = { ah = 1000 } }),
    { ahCutPercent = 5, maxRecursion = 3 })
  PB.Test.eq(#C.Filter(res, { hideMissingPrices = true, minProfit = 1000 }), 0)
  PB.Test.eq(#C.Filter(res, { hideMissingPrices = true, minProfit = 100 }), 1)
end)

PB.Test.it("filter by max listings", function()
  PB.RecipeSource.SetSources({ static = {
    { id = 1, profession = "A", result = { itemID = 200, count = 1 }, reagents = { { itemID = 10, count = 1 } } },
  }, game = {} })
  local res = C.ComputeAll(fakeMarket({ [10] = { ah = 100 }, [200] = { ah = 1000 } }),
    { ahCutPercent = 5, maxRecursion = 3 })
  local market = { PriceOf = function(_, id) if id == 200 then return { num = 3 } end return {} end }
  PB.Test.eq(#C.Filter(res, { hideMissingPrices = true, maxListings = 2 }, market), 0)
  PB.Test.eq(#C.Filter(res, { hideMissingPrices = true, maxListings = 5 }, market), 1)
end)
