local ADDON, PB = ...
local E = {}
PB.Export = E

local frame, editBox

local function ensureFrame()
  if frame then return end
  frame = CreateFrame("Frame", "ProfitBoardExportFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(560, 420)
  frame:SetPoint("CENTER")
  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.title:SetPoint("TOPLEFT", 12, -6)
  frame.title:SetText("ProfitBoard 导出")

  local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 12, -30)
  scroll:SetPoint("BOTTOMRIGHT", -32, 40)

  editBox = CreateFrame("EditBox", nil, scroll)
  editBox:SetMultiLine(true)
  editBox:SetAutoFocus(false)
  editBox:SetFontObject(ChatFontNormal)
  editBox:SetWidth(500)
  editBox:SetScript("OnEscapePressed", function() frame:Hide() end)
  scroll:SetScrollChild(editBox)
  frame:Hide()
end

function E.CSV()
  ensureFrame()
  local lines = { "配方ID,配方名,专业,产物ID,产物名,产物数量,材料成本,成品价,利润,利润率,渠道,缺价" }
  local results = PB.Compute.results or {}
  for i = 1, #results do
    local r = results[i]
    local rp = r.recipe
    lines[#lines + 1] = table.concat({
      tostring(rp.id),
      (rp.name or ""):gsub(",", "，"),
      rp.profession or "",
      tostring(rp.result.itemID),
      (PB.Util.ItemName(rp.result.itemID) or ""):gsub(",", "，"),
      tostring(rp.result.count or 1),
      tostring(PB.Util.Round(r.cost or 0)),
      tostring(PB.Util.Round(r.value or 0)),
      tostring(PB.Util.Round(r.profit or 0)),
      string.format("%.1f", r.margin or 0),
      r.channel or "",
      r.missing and "1" or "0",
    }, ",")
  end
  editBox:SetText(table.concat(lines, "\n"))
  editBox:SetCursorPosition(0)
  editBox:HighlightText()
  frame:Show()
  print("|cff516cefProfitBoard|r CSV 已生成（" .. tostring(#results) .. " 行），Ctrl+C 复制")
end

function E.Import(text)
  if not text or text == "" then
    print("|cff516cefProfitBoard|r 用法：/pb import <快照文本>")
    return
  end
  local market = PB.MarketInstance
  if not market then return end
  local n = market:RestoreFromText(text)
  print("|cff516cefProfitBoard|r 已恢复 " .. tostring(n) .. " 个物品价格")
end
