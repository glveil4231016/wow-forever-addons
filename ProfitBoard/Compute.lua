local ADDON, PB = ...
local C = {}
PB.Compute = C

C.results = {}
C.computedAt = 0

function C.MakeCtx(market, settings)
  return {
    ahCut = ((settings and settings.ahCutPercent) or 5) / 100,
    maxRecursion = (settings and settings.maxRecursion) or 3,
    priceOf = function(id) return market:PriceOf(id) end,
    recipesFor = function(id) return PB.RecipeSource.RecipesFor(id) end,
  }
end

function C.ComputeAll(market, settings)
  local recipes = PB.RecipeSource.All()
  local ctx = C.MakeCtx(market, settings)
  local out = {}
  for i = 1, #recipes do
    local r = PB.Cost.CraftProfit(recipes[i], ctx)
    r.recipe = recipes[i]
    out[#out + 1] = r
  end
  table.sort(out, function(a, b)
    if (a.missing and true or false) ~= (b.missing and true or false) then
      return not a.missing
    end
    return (a.profit or 0) > (b.profit or 0)
  end)
  return out
end

function C.Run(market, settings, onDone)
  local list = C.ComputeAll(market, settings or {})
  C.results = list
  C.computedAt = time()
  if onDone then onDone(list) end
  if PB.UI and PB.UI.Refresh then PB.UI.Refresh() end
  return list
end

function C.Filter(results, settings, market)
  settings = settings or {}
  local out = {}
  for i = 1, #results do
    local r = results[i]
    local keep = true
    if settings.hideMissingPrices and r.missing then keep = false end
    if keep and settings.onlyLearned and not r.recipe.learned then keep = false end
    if keep and (r.profit or 0) < (settings.minProfit or 0) then keep = false end
    if keep and (r.margin or 0) < (settings.minMarginPercent or 0) then keep = false end
    if keep and market and (settings.maxListings or 0) > 0 then
      local p = market:PriceOf(r.recipe.result.itemID)
      if (p.num or 0) > settings.maxListings then keep = false end
    end
    if keep then out[#out + 1] = r end
  end
  return out
end
