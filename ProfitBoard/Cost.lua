local ADDON, PB = ...
local Cost = {}
PB.Cost = Cost

local function itemCost(itemID, depth, visiting, ctx)
  if depth > ctx.maxRecursion then return nil end
  if visiting[itemID] then return nil end
  visiting[itemID] = true

  local p = ctx.priceOf(itemID) or {}
  local best, from
  if p.ah and p.ah > 0 then best, from = p.ah, "ah" end
  if p.vendor and p.vendor > 0 and (not best or p.vendor < best) then
    best, from = p.vendor, "vendor"
  end

  local recipes = ctx.recipesFor(itemID)
  for i = 1, #recipes do
    local c = Cost.CraftCost(recipes[i], depth, visiting, ctx)
    if c and c.unit and c.unit > 0 and (not best or c.unit < best) then
      best, from = c.unit, "craft"
    end
  end

  visiting[itemID] = nil
  return best, from
end

function Cost.CraftCost(recipe, depth, visiting, ctx)
  local total, missing = 0, 0
  local details = {}
  for i = 1, #recipe.reagents do
    local re = recipe.reagents[i]
    if not re.optional then
      local unit, src = itemCost(re.itemID, depth + 1, visiting, ctx)
      if not unit then
        missing = missing + 1
      else
        total = total + unit * re.count
        details[#details + 1] = {
          itemID = re.itemID, count = re.count, unit = unit,
          from = src, subtotal = unit * re.count,
        }
      end
    end
  end
  if missing > 0 then return nil, missing end
  if total <= 0 then return nil, 0 end
  local count = (recipe.result and recipe.result.count) or 1
  if count <= 0 then count = 1 end
  return { total = total, unit = total / count, details = details }
end

function Cost.CraftProfit(recipe, ctx)
  local mat, missingCount = Cost.CraftCost(recipe, 0, {}, ctx)
  if not mat then return { missing = true, missingCount = missingCount or 1 } end

  local p = ctx.priceOf(recipe.result.itemID) or {}
  local count = recipe.result.count or 1
  local ah = p.ah and p.ah > 0 and (p.ah * count * (1 - (ctx.ahCut or 0))) or nil
  local vendor = p.vendor and p.vendor > 0 and (p.vendor * count) or nil

  local value, channel
  if ah and vendor then
    if ah >= vendor then value, channel = ah, "ah" else value, channel = vendor, "vendor" end
  elseif ah then
    value, channel = ah, "ah"
  elseif vendor then
    value, channel = vendor, "vendor"
  else
    return { missing = true, missingCount = 1 }
  end

  local profit = value - mat.total
  return {
    cost = mat.total, value = value, profit = profit,
    margin = mat.total > 0 and (profit / mat.total * 100) or 0,
    channel = channel, details = mat.details,
  }
end
