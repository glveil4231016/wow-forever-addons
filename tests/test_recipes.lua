local ADDON, PB = ...
local RS = PB.RecipeSource

local function r(id, resultID, count, reagents, extra)
  local out = {
    id = id, profession = "Alchemy",
    result = { itemID = resultID, count = count },
    reagents = reagents, source = "static",
  }
  for k, v in pairs(extra or {}) do out[k] = v end
  return out
end

PB.Test.it("merge static only", function()
  RS.SetSources({ static = { r(1, 200, 1, { { itemID = 10, count = 2 } }) }, game = {} })
  PB.Test.eq(#RS.All(), 1)
end)

PB.Test.it("game overrides same id", function()
  RS.SetSources({
    static = { r(1, 200, 1, { { itemID = 10, count = 2 } }, { name = "静态名" }) },
    game = { r(1, 200, 1, { { itemID = 10, count = 3 } }, { name = "游戏名" }) },
  })
  local all = RS.All()
  PB.Test.eq(#all, 1)
  PB.Test.eq(all[1].reagents[1].count, 3)
  PB.Test.eq(all[1].source, "game")
  PB.Test.eq(all[1].name, "游戏名")
end)

PB.Test.it("reverse index by product", function()
  RS.SetSources({
    static = {
      r(1, 200, 1, { { itemID = 10, count = 1 } }),
      r(2, 200, 1, { { itemID = 11, count = 1 } }),
      r(3, 300, 1, { { itemID = 12, count = 1 } }),
    },
    game = {},
  })
  PB.Test.eq(#RS.RecipesFor(200), 2)
end)

PB.Test.it("interesting set has products and reagents", function()
  RS.SetSources({ static = { r(1, 200, 1, { { itemID = 10, count = 2 } }) }, game = {} })
  local set = RS.InterestingSet()
  PB.Test.eq(set[200], true)
  PB.Test.eq(set[10], true)
end)

PB.Test.it("drops invalid", function()
  RS.SetSources({
    static = {
      { id = 9, result = nil, reagents = {} },
      r(10, 400, 1, { { itemID = 1, count = 1 } }),
    },
    game = {},
  })
  PB.Test.eq(#RS.All(), 1)
end)

PB.Test.it("autodetect none without api", function()
  PB.Test.eq(RS.AutoDetect(), "none")
end)
