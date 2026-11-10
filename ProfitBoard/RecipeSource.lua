local ADDON, PB = ...
local RS = {}
PB.RecipeSource = RS

RS.GAME_RECIPE_API = "none"

RS.SKILL_LINES = {
  { id = 171, name = "炼金术" }, { id = 164, name = "锻造" },
  { id = 333, name = "附魔" }, { id = 202, name = "工程学" },
  { id = 165, name = "制皮" }, { id = 197, name = "裁缝" },
  { id = 185, name = "烹饪" }, { id = 129, name = "急救" },
  { id = 186, name = "采矿" },
}

local sources = { game = {}, static = {} }
local merged, byProduct, interesting

local function valid(r)
  return type(r) == "table" and type(r.id) == "number"
    and type(r.result) == "table" and type(r.result.itemID) == "number"
    and type(r.reagents) == "table" and #r.reagents > 0
end

local function rebuild()
  merged, byProduct, interesting = {}, {}, {}
  local index, list = {}, {}

  for i = 1, #sources.static do
    local r = sources.static[i]
    if valid(r) then
      r.source = "static"
      index[r.id] = r
      list[#list + 1] = r
    end
  end

  for i = 1, #sources.game do
    local r = sources.game[i]
    if valid(r) then
      local old = index[r.id]
      if old then
        for k, v in pairs(r) do old[k] = v end
        old.source = "game"
        r = old
      else
        r.source = "game"
        index[r.id] = r
        list[#list + 1] = r
      end
    end
  end

  for i = 1, #list do
    local r = list[i]
    merged[#merged + 1] = r
    local pid = r.result.itemID
    local bucket = byProduct[pid]
    if not bucket then
      bucket = {}
      byProduct[pid] = bucket
    end
    bucket[#bucket + 1] = r
    interesting[pid] = true
    for j = 1, #r.reagents do interesting[r.reagents[j].itemID] = true end
  end
end

function RS.SetSources(newSources)
  sources.game = newSources.game or {}
  sources.static = newSources.static or {}
  rebuild()
end

function RS.All()
  if not merged then rebuild() end
  return merged
end

function RS.RecipesFor(itemID)
  if not byProduct then rebuild() end
  return byProduct[itemID] or {}
end

function RS.InterestingSet()
  if not interesting then rebuild() end
  return interesting
end

function RS.Count()
  return #RS.All()
end

local function readOutput(recipeID)
  if RS.GAME_RECIPE_API ~= "output" then return nil end
  if type(C_TradeSkillUI.GetRecipeOutputItems) ~= "function" then return nil end
  local ok, items = pcall(C_TradeSkillUI.GetRecipeOutputItems, recipeID)
  if not ok or type(items) ~= "table" or not items[1] then return nil end
  local first = items[1]
  local id = type(first) == "table" and first.itemID or first
  local count = type(first) == "table" and (first.quantity or first.count) or 1
  if type(id) ~= "number" then return nil end
  return id, count or 1
end

local function readReagents(recipeID)
  local out = {}
  if RS.GAME_RECIPE_API ~= "output" then return out end
  if type(C_TradeSkillUI.GetRecipeReagentItems) ~= "function" then return out end
  local ok, items = pcall(C_TradeSkillUI.GetRecipeReagentItems, recipeID)
  if not ok or type(items) ~= "table" then return out end
  for i = 1, #items do
    local it = items[i]
    local id = type(it) == "table" and (it.itemID or it.id) or it
    local count = type(it) == "table" and (it.quantity or it.count) or 1
    if type(id) == "number" then
      out[#out + 1] = { itemID = id, count = count or 1 }
    end
  end
  return out
end

-- 现代客户端的 GetRecipeSchematic 返回 { outputs = {...}, reagents = {...} }
local function readSchematic(recipeID)
  if RS.GAME_RECIPE_API ~= "schematic" then return nil, {} end
  if type(C_TradeSkillUI.GetRecipeSchematic) ~= "function" then return nil, {} end
  local ok, schema = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
  if not ok or type(schema) ~= "table" then return nil, {} end

  local result, reagents = nil, {}
  local outputs = schema.outputs or schema.Outputs
  if type(outputs) == "table" and outputs[1] then
    local first = outputs[1]
    local id = type(first) == "table" and (first.itemID or first.id) or nil
    local count = type(first) == "table" and (first.quantity or first.count) or 1
    if type(id) == "number" then result = { itemID = id, count = count or 1 } end
  end

  local list = schema.reagents or schema.Reagents
  if type(list) == "table" then
    for i = 1, #list do
      local it = list[i]
      local id = type(it) == "table" and (it.itemID or it.id) or it
      local count = type(it) == "table" and (it.quantity or it.count) or 1
      if type(id) == "number" then
        reagents[#reagents + 1] = { itemID = id, count = count or 1 }
      end
    end
  end
  return result, reagents
end

function RS.AutoDetect()
  if type(C_TradeSkillUI) ~= "table" then
    RS.GAME_RECIPE_API = "none"
  elseif type(C_TradeSkillUI.GetRecipeOutputItems) == "function" then
    RS.GAME_RECIPE_API = "output"
  elseif type(C_TradeSkillUI.GetRecipeSchematic) == "function" then
    RS.GAME_RECIPE_API = "schematic"
  else
    RS.GAME_RECIPE_API = "none"
  end
  return RS.GAME_RECIPE_API
end

function RS.FromGame()
  local out = {}
  if not PB.Profile.caps.recipeAll then return out end
  for i = 1, #RS.SKILL_LINES do
    local line = RS.SKILL_LINES[i]
    local ok, ids = pcall(C_TradeSkillUI.GetAllRecipeIDs, line.id)
    if ok and type(ids) == "table" then
      for j = 1, #ids do
        local rid = ids[j]
        local resultID, count
        local reagents = {}
        if RS.GAME_RECIPE_API == "schematic" then
          local res, res2 = readSchematic(rid)
          if res then
            resultID, count = res.itemID, res.count
          end
          reagents = res2
        else
          resultID, count = readOutput(rid)
          reagents = readReagents(rid)
        end
        if resultID and #reagents > 0 then
          local learned = false
          if type(C_TradeSkillUI.IsRecipeLearned) == "function" then
            local okL, v = pcall(C_TradeSkillUI.IsRecipeLearned, rid)
            learned = okL and v and true or false
          end
          out[#out + 1] = {
            id = rid, profession = line.name,
            result = { itemID = resultID, count = count or 1 },
            reagents = reagents, learned = learned, source = "game",
          }
        end
      end
    end
  end
  return out
end

function RS.Refresh()
  RS.AutoDetect()
  RS.SetSources({
    static = (PB.StaticRecipes and PB.StaticRecipes.recipes) or {},
    game = RS.FromGame(),
  })
  return RS.Count()
end
