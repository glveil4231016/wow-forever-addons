# ProfitBoard 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在《魔兽世界：无限》（1.60.1 / Interface 16001）上做一个只读统计插件：全量扫描拍卖行、自建按「规则集 × 阵营」隔离的价格库，把全专业全配方的「材料 → 成品」利润算成可筛选的中文表。

**Architecture:** 纯 Lua、无第三方库。数据层（Util / Profile / Config / Market / Cost / RecipeSource / Compute）全部是可注入依赖的纯函数，用 Python + lupa 在游戏外跑单测；UI 层只消费数据层导出。价格来自 `C_AuctionHouse.ReplicateItems()` 全量快照并分帧聚合；配方优先游戏内枚举，缺失部分由生成的 `StaticRecipes.lua` 兜底。

**Tech Stack:** WoW Lua 5.1 API、`C_AuctionHouse` / `C_TradeSkillUI` / `C_Item` / `C_GameRules`、Python 3.12 + lupa 2.8。

**Spec:** `docs/superpowers/specs/2026-11-10-profitboard-design.md`

**仓库状态：** `F:\opencode_workspace\wow-addon` 不是 git 仓库，本计划不含 `git commit` 步骤。需要版本管理请先 `git init`。所有命令在 `F:\opencode_workspace\wow-addon` 下执行，测试命令统一为 `python tests/run_pb.py`。

---

## 文件结构

| 路径 | 职责 |
|---|---|
| `ProfitBoard/ProfitBoard.toc` | 主清单（Interface 16001 / forever） |
| `ProfitBoard/ProfitBoard_Camelot.toc` | flavor 专用清单 |
| `ProfitBoard/Core.lua` | 事件总线、模块装配、SavedVariables 初始化 |
| `ProfitBoard/Profile.lua` | 能力探测、市场 key（规则集 × 阵营）、卖店价 |
| `ProfitBoard/Config.lua` | 默认配置、迁移、clamp |
| `ProfitBoard/Util.lua` | 金额格式化/解析、安全调用、日期、中位数 |
| `ProfitBoard/Market.lua` | 扫描、聚合、depth、历史、文本快照 |
| `ProfitBoard/RecipeSource.lua` | 配方源（游戏 / 静态 / 合并 / 反向索引） |
| `ProfitBoard/StaticRecipes.lua` | 生成的静态配方表（可缺席） |
| `ProfitBoard/Cost.lua` | 成本/收益纯函数引擎 |
| `ProfitBoard/Compute.lua` | 全量计算与筛选 |
| `ProfitBoard/UI.lua` | 表格窗口、排序、筛选、行展开 |
| `ProfitBoard/Export.lua` | CSV 导出、快照导入 |
| `ProfitBoard/Slash.lua` | `/pb` 命令 |
| `ProfitProbe/` | P0 探针，独立插件，不进主包 |
| `tests/stub_pb.lua` | WoW 桩 + 断言工具 |
| `tests/run_pb.py` | lupa 测试驱动 |
| `tests/test_*.lua` | 单测 |

加载顺序即上表顺序（`StaticRecipes.lua` 必须在 `RecipeSource.lua` 之前）。

---

## Task 0：工程骨架与测试驱动

**Files:**
- Create: `ProfitBoard/ProfitBoard.toc`
- Create: `ProfitBoard/ProfitBoard_Camelot.toc`
- Create: `tests/stub_pb.lua`
- Create: `tests/run_pb.py`

- [ ] **Step 1: 建目录**

```powershell
New-Item -ItemType Directory -Force -Path 'F:\opencode_workspace\wow-addon\ProfitBoard' | Out-Null
New-Item -ItemType Directory -Force -Path 'F:\opencode_workspace\wow-addon\ProfitProbe' | Out-Null
New-Item -ItemType Directory -Force -Path 'F:\opencode_workspace\wow-addon\tests' | Out-Null
```

- [ ] **Step 2: 写主 TOC**

`ProfitBoard/ProfitBoard.toc`：

```
## Interface: 16001
## Title: ProfitBoard
## Notes: 全专业配方利润统计
## Notes-zhCN: 全专业配方利润统计（无限服）
## Author: you
## Version: 0.1.0
## SavedVariables: ProfitBoardDB
## SavedVariables: ProfitBoardCache
## AllowLoadGameType: forever
## ExcludeLoadGameType: standard, classic
## X-Category: Auction & Economy
Core.lua
Profile.lua
Config.lua
Util.lua
Market.lua
StaticRecipes.lua
RecipeSource.lua
Cost.lua
Compute.lua
UI.lua
Export.lua
Slash.lua
```

`ProfitBoard/ProfitBoard_Camelot.toc`：内容与主 TOC 完全相同。

- [ ] **Step 3: 写测试桩**

`tests/stub_pb.lua`：

```lua
local ADDON, PB = ...
PB.Test = PB.Test or { pass = 0, fails = {} }

function PB.Test.it(name, fn)
  local ok, err = pcall(fn)
  if ok then
    PB.Test.pass = PB.Test.pass + 1
  else
    PB.Test.fails[#PB.Test.fails + 1] = tostring(name) .. " -> " .. tostring(err)
  end
end

function PB.Test.eq(actual, expected, msg)
  if actual ~= expected then
    error((msg or "eq") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

function PB.Test.near(actual, expected, eps, msg)
  eps = eps or 0.001
  if actual == nil or math.abs(actual - expected) > eps then
    error((msg or "near") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

function PB.Test.truthy(v, msg)
  if not v then error((msg or "truthy") .. ": got falsy", 2) end
end

function PB.Test.report()
  print(string.format("PASS %d  FAIL %d", PB.Test.pass, #PB.Test.fails))
  for i = 1, #PB.Test.fails do print("FAIL " .. PB.Test.fails[i]) end
  return #PB.Test.fails
end

function GetBuildInfo() return "1.60.1", "70862", "20261110", 16001 end
function time() return 1762732800 end
function date(fmt, t) return os.date(fmt, t) end
function UnitFactionGroup() return "Alliance", "联盟" end

UIParent = {}
function CreateFrame()
  local f = {}
  f.SetScript = function() end
  f.Hide = function() end
  f.Show = function() end
  f.RegisterEvent = function() end
  f.CreateFontString = function() return { SetText = function() end } end
  return f
end
C_Timer = { After = function(_, fn) fn() end, NewTicker = function() return { Cancel = function() end } end }
```

- [ ] **Step 4: 写测试驱动**

`tests/run_pb.py`：

```python
import os
import sys

from lupa import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = os.path.join(ROOT, "ProfitBoard")
TESTS = os.path.join(ROOT, "tests")

FILES = [
    "Core.lua", "Profile.lua", "Config.lua", "Util.lua", "Market.lua",
    "StaticRecipes.lua", "RecipeSource.lua", "Cost.lua", "Compute.lua",
    "UI.lua", "Export.lua", "Slash.lua",
]

lua = LuaRuntime(unpack_returned_tuples=True)
loader = lua.eval(
    "function(src, name, ns) local f = assert((loadstring or load)(src, name)); f(name, ns) end"
)
ns = lua.table()


def load_file(path):
    with open(path, "r", encoding="utf-8") as fh:
        loader(fh.read(), os.path.basename(path), ns)


load_file(os.path.join(TESTS, "stub_pb.lua"))
for name in FILES:
    path = os.path.join(ADDON, name)
    if os.path.exists(path):
        load_file(path)

test_files = sorted(
    f for f in os.listdir(TESTS) if f.startswith("test_") and f.endswith(".lua")
)
for name in test_files:
    load_file(os.path.join(TESTS, name))

fails = ns.Test.report()
print("test files: %d" % len(test_files))
sys.exit(1 if fails else 0)
```

- [ ] **Step 5: 跑基线**

Run: `python tests/run_pb.py`
Expected: `PASS 0  FAIL 0`，退出码 0。

---

## Task 1：P0 探针（硬门槛）

**Files:**
- Create: `ProfitProbe/ProfitProbe.toc`
- Create: `ProfitProbe/ProfitProbe.lua`

探针只做三件事：列出哪些 API 存在、dump 拍卖行全量快照前 3 条原始字段、测一次全扫总数与耗时。全部 `pcall`，缺什么写「缺失」。

- [ ] **Step 1: 写探针 TOC**

```
## Interface: 16001
## Title: ProfitProbe
## Notes-zhCN: ProfitBoard 探针
## AllowLoadGameType: forever
## ExcludeLoadGameType: standard, classic
ProfitProbe.lua
```

- [ ] **Step 2: 写探针实现**

`ProfitProbe/ProfitProbe.lua`：

```lua
local ADDON = ...
local lines = {}

local function add(fmt, ...)
  lines[#lines + 1] = string.format(fmt, ...)
end

local function api(label, tbl, key)
  add("%s %s", (type(tbl) == "table" and type(tbl[key]) ~= "nil") and "[OK]  " or "[MISS]", label)
end

local function dump(label, ...)
  local n = select("#", ...)
  local parts = {}
  for i = 1, n do
    parts[#parts + 1] = string.format("%d=%s", i, tostring((select(i, ...))))
  end
  add("%s -> %s", label, table.concat(parts, " | "))
end

local function probeStatic()
  local b1, b2, b3, b4 = GetBuildInfo()
  add("build=%s.%s date=%s interface=%s locale=%s",
    tostring(b1), tostring(b2), tostring(b3), tostring(b4), tostring(GetLocale()))
  add("projectID=%s", tostring(WOW_PROJECT_ID))
  add("--- namespaces ---")
  api("C_AuctionHouse.ReplicateItems", C_AuctionHouse, "ReplicateItems")
  api("C_AuctionHouse.GetNumReplicateItems", C_AuctionHouse, "GetNumReplicateItems")
  api("C_AuctionHouse.GetReplicateItemInfo", C_AuctionHouse, "GetReplicateItemInfo")
  api("C_AuctionHouse.GetReplicateItemLink", C_AuctionHouse, "GetReplicateItemLink")
  api("C_TradeSkillUI.GetAllRecipeIDs", C_TradeSkillUI, "GetAllRecipeIDs")
  api("C_TradeSkillUI.GetRecipeInfo", C_TradeSkillUI, "GetRecipeInfo")
  api("C_TradeSkillUI.GetRecipeOutputItems", C_TradeSkillUI, "GetRecipeOutputItems")
  api("C_TradeSkillUI.GetRecipeReagentItems", C_TradeSkillUI, "GetRecipeReagentItems")
  api("C_TradeSkillUI.GetRecipeSchematic", C_TradeSkillUI, "GetRecipeSchematic")
  api("C_TradeSkillUI.IsRecipeLearned", C_TradeSkillUI, "IsRecipeLearned")
  api("C_Item.GetItemInfo", C_Item, "GetItemInfo")
  api("C_Item.GetItemNameByID", C_Item, "GetItemNameByID")
  api("C_GameRules.IsGameRuleActive", C_GameRules, "IsGameRuleActive")
  api("global.GetItemInfo", _G, "GetItemInfo")
  add("--- professions ---")
  local okProf, p1, p2 = pcall(GetProfessions)
  add("GetProfessions ok=%s v1=%s v2=%s", tostring(okProf), tostring(p1), tostring(p2))
  if okProf and p1 then
    local ok2, name, _, skill, maxLevel = pcall(GetProfessionInfo, p1)
    add("prof1 ok=%s name=%s skill=%s/%s", tostring(ok2), tostring(name), tostring(skill), tostring(maxLevel))
  end
  add("--- item api shape (2589) ---")
  if C_Item and C_Item.GetItemInfo then dump("C_Item.GetItemInfo(2589)", C_Item.GetItemInfo(2589)) end
  if type(GetItemInfo) == "function" then dump("GetItemInfo(2589)", GetItemInfo(2589)) end
  add("--- GameRule enum ---")
  if type(Enum) == "table" and type(Enum.GameRule) == "table" then
    for k, v in pairs(Enum.GameRule) do add("GameRule.%s=%s", tostring(k), tostring(v)) end
  end
end

local probeFrame, scanStart, collect

local function finish()
  add("--- auction house snapshot ---")
  add("total=%s elapsed=%.2fs", tostring(collect and collect.total), scanStart and (GetTime() - scanStart) or -1)
  for i = 1, math.min(3, (collect and collect.total) or 0) do
    dump("Replicate[" .. i .. "]", C_AuctionHouse.GetReplicateItemInfo(i))
    local ok, link = pcall(C_AuctionHouse.GetReplicateItemLink, i)
    add("Replicate[%d].link ok=%s %s", i, tostring(ok), tostring(link))
  end
  print("===== ProfitProbe start =====")
  for i = 1, #lines do print(lines[i]) end
  print("===== ProfitProbe end =====")
end

local function onUpdate()
  if not collect then return end
  if GetTime() - scanStart > 120 then
    add("TIMEOUT after 120s, read=%s/%s", tostring(collect.i), tostring(collect.total))
    probeFrame:Hide()
    finish()
    return
  end
  local spent = 0
  local i = collect.i
  while i < collect.total and spent < 0.006 do
    local t0 = GetTime()
    pcall(C_AuctionHouse.GetReplicateItemInfo, i)
    i = i + 1
    spent = spent + (GetTime() - t0)
  end
  collect.i = i
  if i >= collect.total then
    probeFrame:Hide()
    finish()
  end
end

local function startScan()
  if not (C_AuctionHouse and C_AuctionHouse.ReplicateItems) then
    add("AH replicate API missing")
    finish()
    return
  end
  add("ReplicateItems ok=%s", tostring(pcall(C_AuctionHouse.ReplicateItems)))
  scanStart = GetTime()
  collect = { i = 1, total = 0 }
  probeFrame = CreateFrame("Frame")
  probeFrame:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
  probeFrame:SetScript("OnEvent", function()
    collect.total = C_AuctionHouse.GetNumReplicateItems() or 0
    add("REPLICATE_ITEM_LIST_UPDATE total=%s", tostring(collect.total))
    probeFrame:SetScript("OnUpdate", onUpdate)
  end)
  C_Timer.After(15, function()
    if collect and collect.total == 0 then
      add("no REPLICATE_ITEM_LIST_UPDATE within 15s (AH not open?)")
      probeFrame:Hide()
      finish()
    end
  end)
end

SLASH_PROFITPROBE1 = "/probe"
SlashCmdList["PROFITPROBE"] = function()
  lines = {}
  probeStatic()
  startScan()
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, _, name)
  if name == ADDON then
    print("ProfitProbe 已加载。打开拍卖行后输入 /probe，把输出整段贴回。")
  end
end)
```

- [ ] **Step 3: 交给用户运行**

`ProfitProbe` 拷到 `_forever_\Interface\AddOns\`，重启客户端，**打开拍卖行**，输入 `/probe`，等两行 `=====` 之间的输出，整段回传。

- [ ] **Step 4: 用报告校准三处常量**

1. `Market.lua` 的 `REPLICATE_FIELDS = { id=?, qty=?, price=? }`
2. `Profile.lua` 的 `SELL_PRICE_INDEX = ?`
3. `RecipeSource.lua` 的 `GAME_RECIPE_API`（`output` / `schematic` / `none`）

---

## Task 2：Util

**Files:**
- Create: `ProfitBoard/Util.lua`
- Test: `tests/test_util.lua`

- [ ] **Step 1: 写失败测试**

`tests/test_util.lua`：

```lua
local ADDON, PB = ...
local U = PB.Util

PB.Test.it("money format zero", function() PB.Test.eq(U.FormatMoney(0), "0铜") end)
PB.Test.it("money format copper only", function() PB.Test.eq(U.FormatMoney(45), "45铜") end)
PB.Test.it("money format full", function() PB.Test.eq(U.FormatMoney(12345), "1金 23银 45铜") end)
PB.Test.it("money format negative", function() PB.Test.eq(U.FormatMoney(-12345), "-1金 23银 45铜") end)
PB.Test.it("parse plain", function() PB.Test.eq(U.ParseMoney("12345"), 12345) end)
PB.Test.it("parse zh", function() PB.Test.eq(U.ParseMoney("1金23银45铜"), 12345) end)
PB.Test.it("parse partial", function() PB.Test.eq(U.ParseMoney("1金45铜"), 10045) end)
PB.Test.it("parse invalid", function() PB.Test.eq(U.ParseMoney("abc"), nil) end)
PB.Test.it("median odd", function() PB.Test.near(U.Median({ 5, 1, 3 }), 3) end)
PB.Test.it("median even", function() PB.Test.near(U.Median({ 4, 1, 3, 2 }), 2.5) end)
PB.Test.it("median empty", function() PB.Test.eq(U.Median({}), nil) end)
PB.Test.it("today numeric", function() PB.Test.eq(type(U.Today()), "number") end)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `python tests/run_pb.py`
Expected: 12 条全部 FAIL（`Util` 为 nil）。

- [ ] **Step 3: 实现**

`ProfitBoard/Util.lua`：

```lua
local ADDON, PB = ...
local U = {}
PB.Util = U

function U.Has(tbl, key)
  return type(tbl) == "table" and type(tbl[key]) == "function"
end

function U.SafeCall(fn, ...)
  if type(fn) ~= "function" then return false, "not a function" end
  return pcall(fn, ...)
end

function U.Clamp(v, lo, hi)
  v = tonumber(v) or lo
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

function U.Round(v)
  if not v then return nil end
  return math.floor(v + 0.5)
end

function U.FormatMoney(copper)
  local c = math.floor(tonumber(copper) or 0)
  local neg = c < 0
  if neg then c = -c end
  local g = math.floor(c / 10000)
  local s = math.floor((c % 10000) / 100)
  local o = c % 100
  local parts = {}
  if g > 0 then parts[#parts + 1] = g .. "金" end
  if s > 0 or g > 0 then parts[#parts + 1] = s .. "银" end
  parts[#parts + 1] = o .. "铜"
  return (neg and "-" or "") .. table.concat(parts, " ")
end

function U.ParseMoney(text)
  if type(text) ~= "string" then return nil end
  text = text:gsub("%s+", "")
  if text == "" then return nil end
  local plain = tonumber(text)
  if plain then return math.floor(plain) end
  local g = tonumber(text:match("(%d+)金")) or 0
  local s = tonumber(text:match("(%d+)银")) or 0
  local c = tonumber(text:match("(%d+)铜")) or 0
  if g == 0 and s == 0 and c == 0 then return nil end
  return g * 10000 + s * 100 + c
end

function U.Today()
  return tonumber(date("%Y%m%d")) or 0
end

function U.Median(list)
  local n = #list
  if n == 0 then return nil end
  local copy = {}
  for i = 1, n do copy[i] = list[i] end
  table.sort(copy)
  if n % 2 == 1 then return copy[(n + 1) / 2] end
  return (copy[n / 2] + copy[n / 2 + 1]) / 2
end

function U.Copy(t)
  local out = {}
  for k, v in pairs(t or {}) do out[k] = v end
  return out
end
```

- [ ] **Step 4: 跑测试**

Run: `python tests/run_pb.py`
Expected: `PASS 12  FAIL 0`

---

## Task 3：Profile 与 Config

**Files:**
- Create: `ProfitBoard/Profile.lua`
- Create: `ProfitBoard/Config.lua`
- Test: `tests/test_config.lua`

- [ ] **Step 1: 写失败测试**

`tests/test_config.lua`：

```lua
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
```

- [ ] **Step 2: 跑测试确认失败**

Run: `python tests/run_pb.py`
Expected: 4 条 FAIL。

- [ ] **Step 3: 实现 Profile**

`ProfitBoard/Profile.lua`：

```lua
local ADDON, PB = ...
local P = {}
PB.Profile = P

P.SELL_PRICE_INDEX = 11
P.caps = { ahReplicate = false, itemInfo = nil, tradeSkill = false, gameRules = false, recipeAll = false }

local RULESETS = {
  { "PvPRuleset", "pvp" },
  { "RoleplayingRuleset", "rp" },
  { "RoleplayingPvPRuleset", "rppvp" },
  { "HardcoreRuleset", "hc" },
}

function P.Detect()
  local _, _, _, iface = GetBuildInfo()
  P.interface = iface or 0
  P.caps.ahReplicate = type(C_AuctionHouse) == "table" and type(C_AuctionHouse.ReplicateItems) == "function"
  P.caps.tradeSkill = type(C_TradeSkillUI) == "table"
  P.caps.gameRules = type(C_GameRules) == "table"
  P.caps.recipeAll = P.caps.tradeSkill and type(C_TradeSkillUI.GetAllRecipeIDs) == "function"
  if type(C_Item) == "table" and type(C_Item.GetItemInfo) == "function" then
    P.caps.itemInfo = "C_Item"
  elseif type(GetItemInfo) == "function" then
    P.caps.itemInfo = "global"
  end
  P.ruleset = P.Ruleset()
  local faction = UnitFactionGroup("player")
  P.faction = (faction == "Horde") and "horde" or "alliance"
end

function P.Ruleset()
  if type(C_GameRules) ~= "table" or type(C_GameRules.IsGameRuleActive) ~= "function" then return "normal" end
  local enum = type(Enum) == "table" and Enum.GameRule or nil
  if not enum then return "normal" end
  for i = 1, #RULESETS do
    local value = enum[RULESETS[i][1]]
    if value then
      local ok, active = pcall(C_GameRules.IsGameRuleActive, value)
      if ok and active then return RULESETS[i][2] end
    end
  end
  return "normal"
end

function P.MarketKey()
  return tostring(P.ruleset or "unknown") .. "|" .. tostring(P.faction or "unknown")
end

function P.VendorPrice(itemID)
  if not itemID or not P.caps.itemInfo then return nil end
  local ok, v
  if P.caps.itemInfo == "C_Item" then
    ok, v = pcall(function() return select(P.SELL_PRICE_INDEX, C_Item.GetItemInfo(itemID)) end)
  else
    ok, v = pcall(function() return select(P.SELL_PRICE_INDEX, GetItemInfo(itemID)) end)
  end
  if ok and type(v) == "number" and v > 0 then return v end
  return nil
end

function P.StatusLine()
  return string.format("接口 %s · 市场 %s · AH %s · 专业 %s · 配方全量 %s",
    tostring(P.interface), P.MarketKey(),
    P.caps.ahReplicate and "可用" or "缺失",
    P.caps.tradeSkill and "可用" or "缺失",
    P.caps.recipeAll and "可用" or "未知")
end
```

- [ ] **Step 4: 实现 Config**

`ProfitBoard/Config.lua`：

```lua
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
```

- [ ] **Step 5: 跑测试**

Run: `python tests/run_pb.py`
Expected: `PASS 16  FAIL 0`

---

## Task 4：Market 聚合纯函数

**Files:**
- Create: `ProfitBoard/Market.lua`（本任务只写纯函数）
- Test: `tests/test_market.lua`

- [ ] **Step 1: 写失败测试**

`tests/test_market.lua`：

```lua
local ADDON, PB = ...
local M = PB.Market

local function listing(id, qty, unit)
  return { itemID = id, qty = qty, unit = unit }
end

PB.Test.it("aggregate min num qty", function()
  local items = M.Aggregate({
    listing(2589, 20, 100), listing(2589, 5, 80), listing(2589, 10, 120),
  }, { [2589] = true })
  PB.Test.eq(items[2589].min, 80)
  PB.Test.eq(items[2589].num, 3)
  PB.Test.eq(items[2589].qty, 35)
end)

PB.Test.it("depth uses cheapest 20 percent", function()
  local items = M.Aggregate({
    listing(100, 10, 10), listing(100, 10, 20), listing(100, 80, 100),
  }, { [100] = true }, { capUnits = 20 })
  PB.Test.near(items[100].depth, 15)
end)

PB.Test.it("depth default is 20 percent of qty", function()
  local items = M.Aggregate({
    listing(104, 50, 10), listing(104, 50, 100),
  }, { [104] = true })
  -- cap = 100 * 0.2 = 20，全部由 10 价供应 => depth 10
  PB.Test.near(items[104].depth, 10)
end)

PB.Test.it("depth ignores zero price", function()
  local items = M.Aggregate({ listing(101, 5, 0), listing(101, 5, 50) }, { [101] = true })
  PB.Test.eq(items[101].min, 50)
  PB.Test.near(items[101].depth, 50)
end)

PB.Test.it("non interesting falls back to min", function()
  local items = M.Aggregate({ listing(102, 5, 70), listing(102, 5, 90) }, {})
  PB.Test.eq(items[102].depth, 70)
end)

PB.Test.it("ladder truncation flagged", function()
  local list = {}
  for i = 1, 10 do list[i] = listing(103, 1, i) end
  local items = M.Aggregate(list, { [103] = true }, { maxLadder = 3 })
  PB.Test.eq(items[103].truncated, true)
end)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `python tests/run_pb.py`
Expected: 6 条 FAIL（`Market` 为 nil）。

- [ ] **Step 3: 实现聚合**

`ProfitBoard/Market.lua`：

```lua
local ADDON, PB = ...
local M = {}
PB.Market = M

M.REPLICATE_FIELDS = { id = 13, qty = 12, price = 11 }

function M.DepthFromLadder(ladder, capUnits)
  if type(ladder) ~= "table" or #ladder == 0 then return nil end
  table.sort(ladder, function(a, b) return a.p < b.p end)
  local cap = capUnits or math.huge
  local acc, cost = 0, 0
  for i = 1, #ladder do
    local row = ladder[i]
    if row.p > 0 and row.q > 0 and acc < cap then
      local take = math.min(row.q, cap - acc)
      if take > 0 then
        cost = cost + take * row.p
        acc = acc + take
      end
    end
  end
  if acc <= 0 then return nil end
  return cost / acc
end

function M.Aggregate(listings, interesting, opts)
  opts = opts or {}
  local maxLadder = opts.maxLadder or 200
  local pct = opts.depthPercent or 0.2
  local maxUnits = opts.depthMaxUnits or 1000
  local forcedCap = opts.capUnits
  local items, ladders = {}, {}

  for i = 1, #listings do
    local L = listings[i]
    local id, q, p = L.itemID, L.qty or 1, L.unit or 0
    if id and p > 0 then
      local it = items[id]
      if not it then
        it = { min = p, num = 0, qty = 0 }
        items[id] = it
      end
      if p < it.min then it.min = p end
      it.num = it.num + 1
      it.qty = it.qty + q
      if interesting and interesting[id] then
        local lad = ladders[id]
        if not lad then lad = {}; ladders[id] = lad end
        if #lad < maxLadder then lad[#lad + 1] = { p = p, q = q } end
      end
    end
  end

  for id, lad in pairs(ladders) do
    local it = items[id]
    local cap = forcedCap or math.min(it.qty * pct, maxUnits)
    it.depth = M.DepthFromLadder(lad, cap)
    if not it.depth then it.depth = it.min end
    it.truncated = (#lad >= maxLadder)
  end

  for id, it in pairs(items) do
    if not it.depth then it.depth = it.min end
  end

  return items, ladders
end
```

- [ ] **Step 4: 跑测试**

Run: `python tests/run_pb.py`
Expected: `PASS 22  FAIL 0`

---

## Task 5：Market 历史、快照、扫描

**Files:**
- Modify: `ProfitBoard/Market.lua`
- Test: `tests/test_market_history.lua`

- [ ] **Step 1: 写失败测试**

`tests/test_market_history.lua`：

```lua
local ADDON, PB = ...
local KEY = "normal|alliance"

PB.Test.it("history append caps length", function()
  local db = { markets = { [KEY] = { items = {} } } }
  local M = PB.Market.New(db, KEY)
  for i = 1, 40 do M:AppendHistory(1, 20260100 + i, 100 + i) end
  M.market.items[1].h = M.market.items[1].h or {}
  PB.Test.eq(#M.market.items[1].h <= 60, true)
end)

PB.Test.it("median uses window", function()
  local db = { markets = { [KEY] = { items = {} } } }
  local M = PB.Market.New(db, KEY)
  M.market.items[2] = { min = 1 }
  M:AppendHistory(2, PB.Util.Today(), 10)
  M:AppendHistory(2, PB.Util.Today(), 20)
  M:AppendHistory(2, PB.Util.Today(), 30)
  PB.Test.near(M:MedianPrice(2, 7), 20)
end)

PB.Test.it("median insufficient nil", function()
  local db = { markets = { [KEY] = { items = {} } } }
  local M = PB.Market.New(db, KEY)
  PB.Test.eq(M:MedianPrice(3, 7), nil)
end)

PB.Test.it("snapshot round trip", function()
  local db = { markets = { [KEY] = { items = { [2589] = { min = 10, depth = 12, num = 3, qty = 50 } } } } }
  local M = PB.Market.New(db, KEY)
  local text = M:SnapshotText()
  local db2 = { markets = {} }
  local M2 = PB.Market.New(db2, KEY)
  M2:RestoreFromText(text)
  local it = db2.markets[KEY].items[2589]
  PB.Test.eq(it.min, 10)
  PB.Test.eq(it.depth, 12)
  PB.Test.eq(it.qty, 50)
end)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `python tests/run_pb.py`
Expected: 4 条 FAIL（`Market.New` 为 nil）。

- [ ] **Step 3: 追加历史与快照**

在 `ProfitBoard/Market.lua` 末尾追加：

```lua
function M.New(db, marketKey)
  db.markets = db.markets or {}
  db.markets[marketKey] = db.markets[marketKey] or { items = {}, ladders = {} }
  local m = db.markets[marketKey]
  m.items = m.items or {}
  m.ladders = m.ladders or {}
  local self = { db = db, key = marketKey, market = m }
  setmetatable(self, { __index = M })
  return self
end

function M:AppendHistory(itemID, day, value)
  local it = self.market.items[itemID]
  if not it then return end
  it.h = it.h or {}
  local n = #it.h
  if n >= 2 and it.h[n - 1] == day then
    it.h[n] = value
  elseif n == 0 or it.h[n - 1] ~= day then
    it.h[#it.h + 1] = day
    it.h[#it.h + 1] = value
  end
  local maxPairs = (PB.Config and PB.Config.Defaults.historyDays) or 30
  while #it.h > maxPairs * 2 do
    table.remove(it.h, 1)
    table.remove(it.h, 1)
  end
end

function M:MedianPrice(itemID, windowDays)
  local it = self.market.items[itemID]
  if not it or not it.h then return nil end
  local cutoff = PB.Util.Today() - (windowDays or 7)
  local values = {}
  for i = 1, #it.h, 2 do
    if it.h[i] >= cutoff then values[#values + 1] = it.h[i + 1] end
  end
  if #values < 3 then return nil end
  return PB.Util.Median(values)
end

function M:PriceOf(itemID)
  local it = self.market.items[itemID]
  if not it then return {} end
  return {
    ah = it.depth or it.min,
    min = it.min,
    num = it.num,
    qty = it.qty,
    vendor = PB.Profile.VendorPrice(itemID),
    updatedAt = it.t or 0,
    truncated = it.truncated,
  }
end

function M:SnapshotText()
  local out = {}
  for id, it in pairs(self.market.items) do
    out[#out + 1] = string.format("%d:%d:%d:%d:%d", id,
      it.min or 0, PB.Util.Round(it.depth or 0), it.num or 0, it.qty or 0)
  end
  return table.concat(out, ";")
end

function M:RestoreFromText(text)
  if type(text) ~= "string" or text == "" then return 0 end
  local n = 0
  for chunk in text:gmatch("[^;]+") do
    local id, minv, depth, num, qty = chunk:match("^(%d+):(%d+):(%d+):(%d+):(%d+)$")
    if id then
      self.market.items[tonumber(id)] = {
        min = tonumber(minv), depth = tonumber(depth),
        num = tonumber(num), qty = tonumber(qty), t = time(),
      }
      n = n + 1
    end
  end
  return n
end
```

- [ ] **Step 4: 跑测试**

Run: `python tests/run_pb.py`
Expected: `PASS 26  FAIL 0`

- [ ] **Step 5: 追加扫描（WoW 侧）**

继续在 `Market.lua` 末尾追加：

```lua
local scanDriver, scanState

local function yieldFrame(co)
  if scanDriver then return end
  scanDriver = CreateFrame("Frame")
  scanDriver:SetScript("OnUpdate", function(self, elapsed)
    local budget = 0.006
    local spent = 0
    while spent < budget do
      local ok, err = coroutine.resume(co)
      if not ok then
        self:SetScript("OnUpdate", nil)
        self:Hide()
        scanDriver = nil
        print("|cffff5555ProfitBoard|r 扫描异常：" .. tostring(err))
        return
      end
      if coroutine.status(co) == "dead" then
        self:SetScript("OnUpdate", nil)
        self:Hide()
        scanDriver = nil
        return
      end
      spent = spent + elapsed
    end
  end)
end

function M:Scan(callback)
  if scanState then return false, "已有扫描进行中" end
  if not PB.Profile.caps.ahReplicate then return false, "客户端缺少全量快照 API" end

  local cooldown = (PB.ConfigInstance and PB.ConfigInstance:Get("scanCooldownSec")) or 900
  local last = self.market.updatedAt or 0
  if time() - last < cooldown then
    return false, string.format("还需等待 %d 秒（全扫 15 分钟一次）", cooldown - (time() - last))
  end

  local okCall = pcall(C_AuctionHouse.ReplicateItems)
  if not okCall then return false, "ReplicateItems 调用失败" end

  scanState = { total = 0, done = false }
  local co = coroutine.create(function()
    local waited = 0
    while (C_AuctionHouse.GetNumReplicateItems() or 0) == 0 do
      waited = waited + 1
      if waited > 600 then
        scanState = nil
        if callback then callback(false, "等待快照超时") end
        return
      end
      coroutine.yield()
    end

    local total = C_AuctionHouse.GetNumReplicateItems()
    scanState.total = total
    local listings = {}
    local F = M.REPLICATE_FIELDS
    for i = 1, total do
      local ok, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13 = pcall(C_AuctionHouse.GetReplicateItemInfo, i)
      if ok then
        local id, qty, price = a13, a12, a11
        if F.id ~= 13 then id, qty, price = a3, a2, a1 end
        if type(id) == "number" and type(price) == "number" and price > 0 then
          listings[#listings + 1] = { itemID = id, qty = qty or 1, unit = price }
        end
      end
      if i % 200 == 0 then coroutine.yield() end
    end

    local cfg = PB.ConfigInstance
    local interesting = PB.RecipeSource.InterestingSet()
    local items, ladders = M.Aggregate(listings, interesting, {
      depthPercent = (cfg and cfg:Get("depthPercent") or 20) / 100,
      depthMaxUnits = (cfg and cfg:Get("depthMaxUnits")) or 1000,
      maxLadder = 200,
    })

    local day = PB.Util.Today()
    for id, it in pairs(items) do
      it.t = time()
      self.market.items[id] = it
      self:AppendHistory(id, day, PB.Util.Round(it.depth or it.min))
    end
    self.market.ladders = ladders
    self.market.updatedAt = time()
    self.market.scanCount = (self.market.scanCount or 0) + 1
    self.market.partial = false
    self.db.snapshotText = self:SnapshotText()
    scanState = nil
    if callback then callback(true, self.market.scanCount) end
  end)

  yieldFrame(co)
  return true
end

function M:Scanning()
  return scanState ~= nil
end
```

- [ ] **Step 6: 跑测试（仅确认加载无语法错误）**

Run: `python tests/run_pb.py`
Expected: `PASS 26  FAIL 0`

---

## Task 6：Cost 成本/收益引擎

**Files:**
- Create: `ProfitBoard/Cost.lua`
- Test: `tests/test_cost.lua`

- [ ] **Step 1: 写失败测试**

`tests/test_cost.lua`：

```lua
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
```

- [ ] **Step 2: 跑测试确认失败**

Run: `python tests/run_pb.py`
Expected: 7 条 FAIL。

- [ ] **Step 3: 实现引擎**

`ProfitBoard/Cost.lua`：

```lua
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
```

- [ ] **Step 4: 跑测试**

Run: `python tests/run_pb.py`
Expected: `PASS 33  FAIL 0`

---

## Task 7：RecipeSource（静态 + 游戏 + 合并 + 反向索引）

**Files:**
- Create: `ProfitBoard/StaticRecipes.lua`
- Create: `ProfitBoard/RecipeSource.lua`
- Test: `tests/test_recipes.lua`

- [ ] **Step 1: 写失败测试**

`tests/test_recipes.lua`：

```lua
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
  RS.SetSources({ static = { r(1, 200, 1, {}), r(2, 200, 1, {}), r(3, 300, 1, {}) }, game = {} })
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
    static = { { id = 9, result = nil, reagents = {} }, r(10, 400, 1, {}) },
    game = {},
  })
  PB.Test.eq(#RS.All(), 1)
end)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `python tests/run_pb.py`
Expected: 5 条 FAIL。

- [ ] **Step 3: 写静态表占位**

`ProfitBoard/StaticRecipes.lua`：

```lua
local ADDON, PB = ...
PB.StaticRecipes = PB.StaticRecipes or { version = "", recipes = {} }
```

- [ ] **Step 4: 实现 RecipeSource**

`ProfitBoard/RecipeSource.lua`：

```lua
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
    if not bucket then bucket = {}; byProduct[pid] = bucket end
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

function RS.FromGame()
  local out = {}
  if not PB.Profile.caps.recipeAll then return out end
  for i = 1, #RS.SKILL_LINES do
    local line = RS.SKILL_LINES[i]
    local ok, ids = pcall(C_TradeSkillUI.GetAllRecipeIDs, line.id)
    if ok and type(ids) == "table" then
      for j = 1, #ids do
        local rid = ids[j]
        local resultID, count = readOutput(rid)
        local reagents = readReagents(rid)
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
  RS.SetSources({
    static = (PB.StaticRecipes and PB.StaticRecipes.recipes) or {},
    game = RS.FromGame(),
  })
  return RS.Count()
end
```

- [ ] **Step 5: 跑测试**

Run: `python tests/run_pb.py`
Expected: `PASS 38  FAIL 0`

---

## Task 8：Compute 计算与筛选

**Files:**
- Create: `ProfitBoard/Compute.lua`
- Test: `tests/test_compute.lua`

- [ ] **Step 1: 写失败测试**

`tests/test_compute.lua`：

```lua
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

PB.Test.it("filter by profit and missing", function()
  PB.RecipeSource.SetSources({ static = {
    { id = 1, profession = "A", result = { itemID = 200, count = 1 }, reagents = { { itemID = 10, count = 1 } } },
  }, game = {} })
  local res = C.ComputeAll(
    fakeMarket({ [10] = { ah = 100 }, [200] = { ah = 1000 } }),
    { ahCutPercent = 5, maxRecursion = 3 })
  local out = C.Filter(res, { hideMissingPrices = true, minProfit = 1000 })
  PB.Test.eq(#out, 0)
  local out2 = C.Filter(res, { hideMissingPrices = true, minProfit = 100 })
  PB.Test.eq(#out2, 1)
end)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `python tests/run_pb.py`
Expected: 3 条 FAIL。

- [ ] **Step 3: 实现**

`ProfitBoard/Compute.lua`：

```lua
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

function C.Filter(results, settings)
  settings = settings or {}
  local out = {}
  for i = 1, #results do
    local r = results[i]
    local keep = true
    if settings.hideMissingPrices and r.missing then keep = false end
    if keep and settings.onlyLearned and not r.recipe.learned then keep = false end
    if keep and (r.profit or 0) < (settings.minProfit or 0) then keep = false end
    if keep and (r.margin or 0) < (settings.minMarginPercent or 0) then keep = false end
    if keep and out then
      out[#out + 1] = r
    end
  end
  return out
end
```

- [ ] **Step 4: 跑测试**

Run: `python tests/run_pb.py`
Expected: `PASS 41  FAIL 0`

---

## Task 9：Slash 命令

**Files:**
- Create: `ProfitBoard/Slash.lua`

- [ ] **Step 1: 实现**

`ProfitBoard/Slash.lua`：

```lua
local ADDON, PB = ...

local function say(fmt, ...)
  print("|cff516cefProfitBoard|r " .. string.format(fmt, ...))
end

local function fmtResult(r)
  local rp = r.recipe
  local name = rp.name or ("配方#" .. tostring(rp.id))
  if r.missing then
    return string.format("%s |cff999999缺价 %d|r", name, r.missingCount or 0)
  end
  return string.format("%s | 成本 %s | 售价 %s | 利润 %s | 利润率 %.0f%%",
    name, PB.Util.FormatMoney(r.cost), PB.Util.FormatMoney(r.value),
    PB.Util.FormatMoney(r.profit), r.margin or 0)
end

local handlers = {}

function handlers.scan()
  local market = PB.MarketInstance
  if not market then return say("尚未初始化") end
  local ok, err = market:Scan(function(success, detail)
    if success then
      say("扫描完成，第 %d 次", detail or 0)
      PB.Compute.Run(market, PB.ConfigInstance.db.settings)
    else
      say("扫描未完成：%s", tostring(detail or err))
    end
  end)
  if not ok then say("%s", tostring(err)) end
end

function handlers.top(rest)
  local n = tonumber(rest) or 20
  local results = PB.Compute.results or {}
  if #results == 0 then return say("还没有结果：先 /pb scan，再 /pb top") end
  say("利润前 %d 条：", n)
  for i = 1, math.min(n, #results) do
    say("%d. %s", i, fmtResult(results[i]))
  end
end

function handlers.price(rest)
  local itemID = tonumber(rest)
  if not itemID and rest then itemID = tonumber(rest:match("item:(%d+)")) end
  if not itemID then return say("用法：/pb price 2589") end
  local market = PB.MarketInstance
  if not market then return say("尚未初始化") end
  local p = market:PriceOf(itemID)
  if not p.min then return say("物品 %d 没有价格数据", itemID) end
  say("物品 %d：最低 %s · 深度 %s · 挂单 %s · 总量 %s · 卖店 %s", itemID,
    PB.Util.FormatMoney(p.min), PB.Util.FormatMoney(PB.Util.Round(p.ah or 0)),
    tostring(p.num or 0), tostring(p.qty or 0),
    p.vendor and PB.Util.FormatMoney(p.vendor) or "无")
  local med = market:MedianPrice(itemID, 7)
  say("7 日中位：%s", med and PB.Util.FormatMoney(PB.Util.Round(med)) or "历史不足")
end

function handlers.status()
  say("%s", PB.Profile.StatusLine())
  local market = PB.MarketInstance
  if market then
    local n = 0
    for _ in pairs(market.market.items) do n = n + 1 end
    say("价格库：%d 个物品 · 扫描 %d 次 · 上次 %s", n, market.market.scanCount or 0,
      (market.market.updatedAt or 0) > 0 and date("%m-%d %H:%M", market.market.updatedAt) or "从未")
    if market.market.partial then say("|cffffaa00上次扫描不完整|r") end
  end
  say("配方：%d 条（静态表版本：%s）", PB.RecipeSource.Count(),
    (PB.StaticRecipes and PB.StaticRecipes.version ~= "" and PB.StaticRecipes.version) or "无")
  say("结果：%d 条", #(PB.Compute.results or {}))
end

function handlers.filter(rest)
  local key, value = (rest or ""):match("^(%S+)%s+(.+)$")
  if not key then
    return say("用法：/pb filter profit 10000 | /pb filter margin 20 | /pb filter listings 10 | /pb filter learned 1 | /pb filter missing 0")
  end
  local cfg = PB.ConfigInstance
  if not cfg then return say("尚未初始化") end
  if key == "profit" then
    local v = PB.Util.ParseMoney(value)
    if not v then return say("数值无效") end
    cfg:Set("minProfit", v)
  elseif key == "margin" then
    cfg:Set("minMarginPercent", tonumber(value) or 0)
  elseif key == "listings" then
    cfg:Set("maxListings", tonumber(value) or 0)
  elseif key == "learned" then
    cfg:Set("onlyLearned", value == "1" or value == "true")
  elseif key == "missing" then
    cfg:Set("hideMissingPrices", not (value == "1" or value == "true"))
  else
    return say("未知筛选键 %s", key)
  end
  if PB.UI then PB.UI.Refresh() end
  say("已设置 %s = %s", key, value)
end

function handlers.export()
  if PB.Export then PB.Export.CSV() end
end

function handlers.import(rest)
  if PB.Export then PB.Export.Import(rest) end
end

function handlers.reset(rest)
  local which = (rest or ""):match("^(%S+)") or "all"
  local db = ProfitBoardDB
  if which == "market" or which == "all" then db.markets = {} end
  if which == "config" or which == "all" then db.settings = {} end
  PB.ConfigInstance:Load(db)
  PB.MarketInstance = PB.Market.New(db, PB.Profile.MarketKey())
  say("已重置 %s", which)
end

local function dispatch(msg)
  local cmd, rest = (msg or ""):match("^(%S*)%s*(.-)$")
  cmd = (cmd or ""):lower()
  if cmd == "" then
    if PB.UI then PB.UI.Toggle() end
    return
  end
  local fn = handlers[cmd]
  if not fn then
    return say("未知命令 %s。可用：scan / top / price / filter / export / import / status / reset", cmd)
  end
  local ok, err = pcall(fn, rest)
  if not ok then say("命令出错：%s", tostring(err)) end
end

SLASH_PROFITBOARD1 = "/pb"
SLASH_PROFITBOARD2 = "/profitboard"
SlashCmdList["PROFITBOARD"] = dispatch
```

- [ ] **Step 2: 校验加载**

Run: `python tests/run_pb.py`
Expected: `PASS 41  FAIL 0`

---

## Task 10：UI 表格

**Files:**
- Create: `ProfitBoard/UI.lua`

- [ ] **Step 1: 实现**

`ProfitBoard/UI.lua`：

```lua
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
local frame, rows, statusText, searchBox, scrollBar
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
  searchBox:SetScript("OnTextChanged", function() offset = 0; UI.Refresh() end)

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
      if sortKey == col.key then sortAsc = not sortAsc else sortKey, sortAsc = col.key, false end
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
  if key == "name" then return (r.recipe.name or "") end
  if key == "prof" then return (r.recipe.profession or "") end
  if key == "listings" then
    local p = market and market:PriceOf(r.recipe.result.itemID) or {}
    return p.num or 0
  end
  return r[key] or 0
end

function UI.Refresh()
  ensure()
  local market = PB.MarketInstance
  local settings = PB.ConfigInstance and PB.ConfigInstance.db.settings or {}
  local data = PB.Compute.Filter(PB.Compute.results or {}, settings)

  local q = searchBox:GetText()
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
      if sortAsc then return va < vb end
      return va > vb
    end
    if sortAsc then return va < vb end
    return va > vb
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
```

- [ ] **Step 2: 校验加载**

Run: `python tests/run_pb.py`
Expected: `PASS 41  FAIL 0`

---

## Task 11：Export / Import

**Files:**
- Create: `ProfitBoard/Export.lua`

- [ ] **Step 1: 实现**

`ProfitBoard/Export.lua`：

```lua
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
  local lines = { "配方ID,配方名,专业,产物ID,产物数量,材料成本,成品价,利润,利润率,渠道,缺价" }
  local results = PB.Compute.results or {}
  for i = 1, #results do
    local r = results[i]
    local rp = r.recipe
    lines[#lines + 1] = table.concat({
      tostring(rp.id),
      (rp.name or ""):gsub(",", "，"),
      rp.profession or "",
      tostring(rp.result.itemID),
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
```

- [ ] **Step 2: 校验**

Run: `python tests/run_pb.py`
Expected: `PASS 41  FAIL 0`

---

## Task 12：Core 装配与集成验收

**Files:**
- Create: `ProfitBoard/Core.lua`

- [ ] **Step 1: 实现 Core**

`ProfitBoard/Core.lua`：

```lua
local ADDON, PB = ...
PB.addonName = ADDON

local listeners = {}
local started = false

function PB:On(event, fn)
  listeners[event] = listeners[event] or {}
  listeners[event][#listeners[event] + 1] = fn
end

function PB:Fire(event, ...)
  local list = listeners[event]
  if not list then return end
  for i = 1, #list do
    local ok, err = pcall(list[i], ...)
    if not ok then print("|cffff5555ProfitBoard|r 事件 " .. tostring(event) .. " 失败：" .. tostring(err)) end
  end
end

local function initDB()
  if type(ProfitBoardDB) ~= "table" then ProfitBoardDB = {} end
  if type(ProfitBoardCache) ~= "table" then ProfitBoardCache = {} end
  ProfitBoardDB.markets = ProfitBoardDB.markets or {}
end

local function safeInit(label, fn)
  local ok, err = pcall(fn)
  if not ok then
    print(string.format("|cffff5555ProfitBoard|r 模块 %s 初始化失败：%s", label, tostring(err)))
  end
  return ok
end

local function start()
  if started then return end
  started = true
  initDB()

  safeInit("Profile", function() PB.Profile.Detect() end)
  safeInit("Config", function() PB.ConfigInstance = PB.Config.New(ProfitBoardDB) end)
  safeInit("Market", function()
    PB.MarketInstance = PB.Market.New(ProfitBoardDB, PB.Profile.MarketKey())
    if next(PB.MarketInstance.market.items) == nil
      and type(ProfitBoardDB.snapshotText) == "string"
      and ProfitBoardDB.snapshotText ~= "" then
      local n = PB.MarketInstance:RestoreFromText(ProfitBoardDB.snapshotText)
      if n > 0 then
        print("|cff516cefProfitBoard|r 已从文本快照恢复 " .. n .. " 个物品价格")
      end
    end
  end)
  safeInit("Recipes", function()
    local n = PB.RecipeSource.Refresh()
    print("|cff516cefProfitBoard|r 配方载入 " .. tostring(n) .. " 条")
  end)
  safeInit("Compute", function()
    if PB.MarketInstance then
      PB.Compute.Run(PB.MarketInstance, ProfitBoardDB.settings)
    end
  end)
  print(PB.Profile.StatusLine())
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("AUCTION_HOUSE_SHOW")
f:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 == ADDON then start() end
    return
  end
  if event == "PLAYER_LOGIN" then
    start()
    print("|cff516cefProfitBoard|r 打开拍卖行后输入 /pb scan 更新价格")
    return
  end
  if event == "AUCTION_HOUSE_SHOW" then
    local market = PB.MarketInstance
    local cfg = PB.ConfigInstance
    if market and cfg then
      if time() - (market.market.updatedAt or 0) >= cfg:Get("scanCooldownSec") then
        print("|cff516cefProfitBoard|r 价格已过期，输入 /pb scan 全量扫描")
      end
    end
  end
end)
```

- [ ] **Step 2: 跑单测**

Run: `python tests/run_pb.py`
Expected: `PASS 41  FAIL 0`，退出码 0。

- [ ] **Step 3: 打包交付**

```powershell
Compress-Archive -Path 'F:\opencode_workspace\wow-addon\ProfitBoard' -DestinationPath 'F:\opencode_workspace\wow-addon\ProfitBoard.zip' -Force
```

用户解压到 `_forever_\Interface\AddOns\ProfitBoard`（注意不要再套一层目录）。

- [ ] **Step 4: 客户端集成验收（用户侧，逐条打勾）**

1. `[ ]` `/pb status`：接口 16001、市场 key 含 `|`、AH「可用」、配方条数 > 0。
2. `[ ]` 打开拍卖行 → `/pb scan` → 输出「扫描完成，第 1 次」。
3. `[ ]` `/pb price 2589`：最低价与拍卖行手查一致（误差 0）。
4. `[ ]` `/reload` → `/pb price 2589`：价格仍在（SavedVariables 回读正常）。
5. `[ ]` `/pb top 20`：第一名材料成本与手算一致（误差 ≤ 1 铜）。
6. `[ ]` `/pb` 打开窗口：表格有数据、排序可点、搜索可用、滚轮可滚。
7. `[ ]` `/pb filter margin 30` → 窗口只剩利润率 ≥ 30% 的行。
8. `[ ]` `/pb export` → CSV 可复制，行数等于结果数。

任一条失败：把 `/pb status` 输出 + 报错文本回传，不要自行改阈值掩盖问题。

- [ ] **Step 5: 收尾**

把上面 8 条的实测结果写进 `docs/superpowers/specs/2026-11-10-profitboard-design.md` 末尾的「验收记录」小节（新增一节，逐条记录通过/失败与客户端 build 号）。

---

## 计划自查

**1. Spec 覆盖**

| Spec 章节 | 对应任务 |
|---|---|
| §3 文件布局与 TOC | Task 0 |
| §4 Profile 能力探测 | Task 3、Task 1（探针校准） |
| §5 数据模型 | Task 3（settings）、Task 5（markets/history/snapshotText） |
| §6 价格库（扫描/聚合/历史/节流/partial） | Task 4、Task 5 |
| §7 配方源（Game/Static/合并/反向索引） | Task 7 |
| §8 成本引擎（递归/环形/多产出/缺价/税） | Task 6 |
| §9 计算与筛选 | Task 8 |
| §10 UI | Task 10 |
| §11 命令 | Task 9 |
| §12 错误处理与持久化 | Task 0（pcall 桩）、Task 12（safeInit）、Task 5（snapshotText/RestoreFromText） |
| §13 测试 | 全部 Task 的 Step「跑测试」+ Task 12 Step 4 |
| §14 静态配方导出脚本 | **本计划不含**：P0 若证明 Game 源可枚举全配方，则不需要；否则单开一份计划 |
| §15 分阶段 | P0=Task 1，P1=Task 0/2/3/4/5/9，P2=Task 6/7/8，P3=Task 10/11 |
| P4（多角色、采购清单） | 本计划明确不做 |

**2. 占位扫描**：无 TBD / TODO / 「稍后补」。唯一的外部依赖是 Task 1 Step 4 的三个常量，已写明取值来源与校准方式。

**3. 类型与命名一致性**

- `Market:PriceOf` 返回 `{ ah, min, num, qty, vendor, updatedAt, truncated }`，被 Task 6 的 `ctx.priceOf`、Task 8 的 `MakeCtx`、Task 10 的 `cellText` 共用，字段名一致。
- `Cost.CraftProfit` 返回 `{ cost, value, profit, margin, channel, details, missing, missingCount }`，Task 8 排序、Task 9 打印、Task 10 表格、Task 11 CSV 均只读这些字段。
- `RecipeSource` 导出 `SetSources / All / RecipesFor / InterestingSet / Count / Refresh / FromGame`，Task 5 用 `InterestingSet`，Task 6 用 `RecipesFor`，Task 9 用 `Count`。
- `Config` 用 `Config.New(db)` + `cfg:Get/Set`，Task 3 测试、Task 5 扫描、Task 9 命令一致。
- 已补齐：`Compute.Filter(results, settings, market)` 现在实现 `maxListings`（成品挂单上限）筛选，`/pb filter listings N` 生效；UI 的「挂单」列仍只做展示，筛选走命令或配置。
- 仍属后续：多角色合并、采购清单（P4），以及静态配方表的实际数据生成（取决于 P0 探针结果）。

---

## 交付节奏建议

1. Task 0 → Task 1 立刻做，先拿到探针报告（这是唯一阻塞项）。
2. 探针报告回来前，Task 2/3/4/6 可以并行推进（纯函数，不依赖客户端事实）。
3. Task 5/7 依赖探针报告；Task 7 在 Game 源不可用时应直接走静态表路线，不阻塞。
4. Task 9/10/11/12 最后做，一次跑通验收 8 条。

