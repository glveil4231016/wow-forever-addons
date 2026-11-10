local ADDON, PB = ...
local C = {}
PB.Config = C

C.Defaults = {
  ahCutPercent = 5, depthPercent = 20, depthMaxUnits = 1000,
  historyDays = 30, medianWindowDays = 7, maxRecursion = 3,
  frameBudgetMs = 5, scanCooldownSec = 900,
  minProfit = 0, minMarginPercent = 0, maxListings = 0,
  hideMissingPrices = true, onlyLearned = false,
  autoPromptOnAH = true, logLevel = "info",
}

local CLAMP = {
  ahCutPercent = { 0, 50 }, depthPercent = { 1, 100 }, depthMaxUnits = { 1, 100000 },
  historyDays = { 1, 365 }, medianWindowDays = { 1, 60 }, maxRecursion = { 1, 5 },
  frameBudgetMs = { 1, 16 }, scanCooldownSec = { 60, 3600 },
  minProfit = { 0, 100000000 }, minMarginPercent = { 0, 100 }, maxListings = { 0, 100000 },
}

local function clamp(key, value)
  local r = CLAMP[key]
  if not r then return value end
  return PB.Util.Clamp(value, r[1], r[2])
end

function C.New(db)
  db = db or {}
  local self = { db = db }
  setmetatable(self, { __index = C })
  C.Load(self, db)
  return self
end

function C:Load(db)
  db = db or self.db or {}
  db.settings = db.settings or {}
  for k, v in pairs(C.Defaults) do
    if db.settings[k] == nil then db.settings[k] = v end
  end
  for k in pairs(CLAMP) do
    db.settings[k] = clamp(k, db.settings[k])
  end
  self.db = db
end

function C:Get(key)
  local v = self.db and self.db.settings and self.db.settings[key]
  if v == nil then return C.Defaults[key] end
  return v
end

function C:Set(key, value)
  if CLAMP[key] then value = clamp(key, value) end
  self.db.settings = self.db.settings or {}
  self.db.settings[key] = value
end
