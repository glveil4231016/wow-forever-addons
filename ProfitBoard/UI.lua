local ADDON, PB = ...
local UI = {}
PB.UI = UI

local COLS = {
  { key = "name", label = "配方", width = 210, type = "string" },
  { key = "prof", label = "专业", width = 80, type = "string" },
  { key = "result", label = "产物×数量", width = 140, type = "string" },
  { key = "cost", label = "材料成本", width = 105, type = "number" },
  { key = "value", label = "成品价", width = 105, type = "number" },
  { key = "profit", label = "利润", width = 105, type = "number" },
  { key = "margin", label = "利润率", width = 65, type = "number" },
  { key = "listings", label = "挂单", width = 55, type = "number" },
  { key = "fresh", label = "数据", width = 85, type = "string" },
}

local ROW_H, VISIBLE = 21, 24
local frame, rows, statusText, searchBox, scrollBar, listingsBox
local sortKey, sortAsc = "profit", false
local offset = 0

local function ensure()
  if frame then return end
  frame = CreateFrame("Frame", "ProfitBoardFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(980, 600)
  frame:SetPoint("CENTER")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetScript("OnMouseWheel", function(_, delta)
    offset = math.max(0, offset - delta * 3)
    UI.Refresh()
  end)

  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.title:SetPoint("TOPLEFT", 14, -6)
  frame.title:SetText("ProfitBoard · 全配方利润")

  searchBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  searchBox:SetSize(170, 20)
  searchBox:SetPoint("TOPLEFT", 14, -34)
  searchBox:SetAutoFocus(false)
  searchBox:SetScript("OnEscapePressed", function() searchBox:ClearFocus() end)
  searchBox:SetScript("OnTextChanged", function()
    offset = 0
    UI.Refresh()
  end)

  local listingLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  listingLabel:SetPoint("TOPRIGHT", -92, -34)
  listingLabel:SetText("挂单≤")
  listingLabel:SetJustifyH("RIGHT")

  listingsBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  listingsBox:SetSize(60, 20)
  listingsBox:SetPoint("TOPRIGHT", -24, -34)
  listingsBox:SetAutoFocus(false)
  listingsBox:SetNumeric(false)
  listingsBox:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
  end)
  listingsBox:SetScript("OnEnterPressed", function(self)
    local cfg = PB.ConfigInstance
    if cfg then cfg:Set("maxListings", tonumber(self:GetText()) or 0) end
    self:ClearFocus()
    offset = 0
    UI.Refresh()
  end)

  local header = CreateFrame("Frame", nil, frame)
  header:SetPoint("TOPLEFT", 14, -60)
  header:SetSize(930, 18)
  local x = 0
  for i = 1, #COLS do
    local col = COLS[i]
    local btn = CreateFrame("Button", nil, header)
    btn:SetPoint("TOPLEFT", x, 0)
    btn:SetSize(col.width, 18)
    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("LEFT", 0, 0)
    fs:SetText(col.label)
    btn:SetScript("OnClick", function()
      if sortKey == col.key then
        sortAsc = not sortAsc
      else
        sortKey, sortAsc = col.key, false
      end
      UI.Refresh()
    end)
    x = x + col.width
  end

  rows = {}
  for i = 1, VISIBLE do
    local row = CreateFrame("Button", nil, frame)
    row:SetPoint("TOPLEFT", 14, -80 - (i - 1) * ROW_H)
    row:SetSize(930, ROW_H)
    row.cells = {}
    local cx = 0
    for j = 1, #COLS do
      local col = COLS[j]
      local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      fs:SetPoint("LEFT", cx, 0)
      fs:SetWidth(col.width - 4)
      fs:SetJustifyH("LEFT")
      row.cells[col.key] = fs
      cx = cx + col.width
    end
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.05)
    row:SetScript("OnClick", function(self)
      local r = self.recipe
      if not r then return end
      print("|cff516cefProfitBoard|r " .. tostring(r.recipe.name or r.recipe.id))
      if r.details then
        for k = 1, #r.details do
          local d = r.details[k]
          print(string.format("   材料 %d × %d @ %s（%s）", d.itemID, d.count,
            PB.Util.FormatMoney(PB.Util.Round(d.unit or 0)), tostring(d.from)))
        end
      end
    end)
    rows[i] = row
  end

  scrollBar = CreateFrame("Slider", "ProfitBoardScroll", frame, "UIPanelScrollBarTemplate")
  scrollBar:SetPoint("TOPRIGHT", -4, -80)
  scrollBar:SetPoint("BOTTOMRIGHT", -4, 34)
  scrollBar:SetMinMaxValues(0, 1000)
  scrollBar:SetValueStep(1)
  scrollBar:SetValue(0)
  scrollBar:SetScript("OnValueChanged", function(_, value)
    offset = math.floor(value)
    UI.Refresh()
  end)

  statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  statusText:SetPoint("BOTTOMLEFT", 14, 10)
  frame:Hide()
end

local function cellText(r, key, market)
  if key == "name" then return r.recipe.name or ("配方#" .. tostring(r.recipe.id)) end
  if key == "prof" then return r.recipe.profession or "?" end
  if key == "result" then
    return string.format("%d×%d", r.recipe.result.itemID, r.recipe.result.count or 1)
  end
  if key == "cost" then return r.missing and "缺价" or PB.Util.FormatMoney(r.cost) end
  if key == "value" then return r.missing and "-" or PB.Util.FormatMoney(r.value) end
  if key == "profit" then return r.missing and "-" or PB.Util.FormatMoney(r.profit) end
  if key == "margin" then return r.missing and "-" or string.format("%.0f%%", r.margin or 0) end
  if key == "listings" then
    local p = market and market:PriceOf(r.recipe.result.itemID) or {}
    return tostring(p.num or 0)
  end
  if key == "fresh" then
    local p = market and market:PriceOf(r.recipe.result.itemID) or {}
    if not p.updatedAt or p.updatedAt == 0 then return "无" end
    local mins = (time() - p.updatedAt) / 60
    if mins < 60 then return string.format("%d 分钟前", mins) end
    return string.format("%d 小时前", mins / 60)
  end
  return ""
end

local function sortValue(r, key, market)
  if key == "name" then return r.recipe.name or "" end
  if key == "prof" then return r.recipe.profession or "" end
  if key == "listings" then
    local p = market and market:PriceOf(r.recipe.result.itemID) or {}
    return p.num or 0
  end
  return r[key] or 0
end

function UI.Refresh()
  ensure()
  local market = PB.MarketInstance
  local settings = (PB.ConfigInstance and PB.ConfigInstance.db.settings) or {}
  local data = PB.Compute.Filter(PB.Compute.results or {}, settings, market)

  local q = searchBox and searchBox:GetText()
  if q and q ~= "" then
    q = q:lower()
    local keep = {}
    for i = 1, #data do
      local name = (data[i].recipe.name or ""):lower()
      if name:find(q, 1, true) then keep[#keep + 1] = data[i] end
    end
    data = keep
  end

  local numeric = sortKey ~= "name" and sortKey ~= "prof"
  table.sort(data, function(a, b)
    local va, vb = sortValue(a, sortKey, market), sortValue(b, sortKey, market)
    if numeric then
      if sortAsc then return (va or 0) < (vb or 0) end
      return (va or 0) > (vb or 0)
    end
    if sortAsc then return tostring(va) < tostring(vb) end
    return tostring(va) > tostring(vb)
  end)

  local maxOffset = math.max(0, #data - VISIBLE)
  if offset > maxOffset then offset = maxOffset end
  if scrollBar then scrollBar:SetMinMaxValues(0, math.max(1, maxOffset)) end

  for i = 1, VISIBLE do
    local row = rows[i]
    local r = data[offset + i]
    if r then
      row.recipe = r
      for j = 1, #COLS do
        local key = COLS[j].key
        row.cells[key]:SetText(cellText(r, key, market))
      end
      if r.missing then
        row.cells.profit:SetTextColor(0.6, 0.6, 0.6)
      elseif (r.profit or 0) >= 0 then
        row.cells.profit:SetTextColor(0.25, 0.9, 0.45)
      else
        row.cells.profit:SetTextColor(1, 0.35, 0.35)
      end
      row:Show()
    else
      row.recipe = nil
      row:Hide()
    end
  end

  statusText:SetText(string.format("共 %d 条 · %d–%d · 排序 %s %s", #data,
    math.min(offset + 1, #data), math.min(offset + VISIBLE, #data),
    sortKey, sortAsc and "↑" or "↓"))
end

function UI.Open()
  ensure()
  if listingsBox and PB.ConfigInstance then
    listingsBox:SetText(tostring(PB.ConfigInstance:Get("maxListings") or 0))
  end
  frame:Show()
  UI.Refresh()
end

function UI.Close()
  if frame then frame:Hide() end
end

function UI.Toggle()
  ensure()
  if frame:IsShown() then UI.Close() else UI.Open() end
end
