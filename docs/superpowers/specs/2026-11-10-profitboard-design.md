# ProfitBoard 设计文档（v1，定稿）

- 日期：2026-11-10
- 目标客户端：《魔兽世界：无限》WoW Forever，1.60.1，Interface **16001**，flavor `_Camelot` / 安装目录 `_forever_`
- 代码目录：`F:\opencode_workspace\wow-addon\ProfitBoard`
- 斜杠命令：`/pb`
- 状态：设计已获用户批准，待实施

---

## 1. 背景与目标

用户要在无限服靠「材料 → 成品」赚金币。现成插件（CraftProfit / Blackthornes Tradeskills / Profiteer 等）已能扫拍卖行并给配方利润排序，但都只覆盖**已学配方**（CraftProfit 明确写 known recipes only），且市场分库、语言、筛选门槛不可控。

本插件的差别只有三点，其余一律跟现成插件对齐，不重复造：

1. **全专业全配方**：包括角色没学过的配方，用于回答「哪条配方最赚」「练哪个专业回本最快」。
2. **自建价格库**：自己全量扫 AH，按「规则集 × 阵营」隔离，保留 30 天历史与 7 天中位价。
3. **可筛选的中文利润表**：自定义利润/利润率/挂单数门槛，缺价显式标注，不猜。

### 非目标（明确不做）

- 不自动购买、不自动上架、不自动制作、不发聊天消息（规避无限服自动化红线）。
- 不做跨玩家物价共享（无网络 API；HS 云端数据不在本项目范围）。
- 不模拟零售的 multicraft / resourcefulness / concentration（无限的专业是 Classic 1–300，没有这些机制）。
- 不做 TSM 式分组/操作/补货体系。

---

## 2. 已确认的客户端事实（决定实现方式）

| 事实 | 状态 | 影响 |
|---|---|---|
| 安装目录 `_forever_`，TOC flavor `_Camelot`，Interface 16001 | 已确认 | TOC 与部署路径 |
| 全量快照入口是 `C_AuctionHouse.ReplicateItems()`，服务端 15 分钟节流 | 已确认（wiki + 多个插件实现） | 扫描器的核心约束 |
| AH 为现代化 AH（commodities 按单价买、合并堆叠） | 已确认（auxForever 说明） | depth 价必须按「单价 × 数量」算 |
| 旧 AH API（`QueryAuctionItems` / `CanSendAuctionQuery` / `GetAuctionItemInfo`）已被移除 | 已确认 | 禁止写 3.3.5a 风格代码 |
| `GetItemInfo` / `GetItemIcon` / `GetItemQualityColor` 在 Forever 被移除 | 已确认（Auctioneer Forever 移植日志） | 必须走 `C_Item.*`，并全部做存在性判断 |
| 市场按「规则集 × 阵营」隔离，约 6–8 个市场 | 已确认 | 价格库 key 不能用 `GetRealmName()` |
| 专业为 Classic 1–300，无品质/专精 | 已确认 | 配方模型简单：产物 + 材料 + 数量 |
| Blizzard 是否发布 Forever AH 数据 | **各方说法冲突** | 不依赖，全部本地扫描 |
| `C_TradeSkillUI.GetAllRecipeIDs` 能否返回未学配方 | **未验证** | P0 探针首要问题 |
| 全量快照的 `GetReplicateItemInfo` 字段顺序 | **未验证** | 探针 dump 后写死映射 + 自检 |
| SavedVariables 是否稳定回读 | **未验证（Forever 有已知问题）** | 需要文本快照兜底 |

---

## 3. 文件布局与加载顺序

```
ProfitBoard/
  ProfitBoard.toc
  ProfitBoard_Camelot.toc      -- 内容同主 TOC，flavor 专用
  Core.lua
  Profile.lua
  Config.lua
  Util.lua
  Market.lua
  RecipeSource.lua
  StaticRecipes.lua            -- 生成物，可整文件替换
  Cost.lua
  Compute.lua
  UI.lua
  Export.lua
  Slash.lua
```

加载顺序即上表顺序，`StaticRecipes.lua` 必须在 `RecipeSource.lua` 之前。

TOC 关键行：

```
## Interface: 16001
## Title: ProfitBoard
## Notes-zhCN: 全专业配方利润统计（无限服）
## SavedVariables: ProfitBoardDB
## SavedVariables: ProfitBoardCache
## AllowLoadGameType: forever
## ExcludeLoadGameType: standard, classic
```

### 全局污染约束

每个文件头 `local ADDON, PB = ...`；除 `ProfitBoardDB` / `ProfitBoardCache` 两个 SavedVariables 外不创建任何全局变量。

---

## 4. Profile（能力探测）

`PB.Profile.Detect()` 在 `ADDON_LOADED` 时执行一次，结果写入 `PB.Profile.caps`。所有版本分叉只读 caps。

```lua
PB.Profile = {
  interface = 16001,
  build = "1.60.1",
  caps = {
    ahReplicate   = type(C_AuctionHouse) == "table" and type(C_AuctionHouse.ReplicateItems) == "function",
    ahReplicateFields = { itemID = nil, quantity = nil, buyout = nil }, -- 探针确定后填
    itemInfo      = C_Item and type(C_Item.GetItemInfo) == "function" and "C_Item"
                    or (type(GetItemInfo) == "function" and "global" or nil),
    itemSellPrice = nil,   -- 探针确定取第几个返回值
    recipeAll     = false, -- C_TradeSkillUI.GetAllRecipeIDs 能否枚举未学配方
    tradeSkill    = type(C_TradeSkillUI) == "table",
    gameRules     = type(C_GameRules) == "table",
    rulesetID     = nil,
    faction       = nil,
  },
}
```

`PB.Profile.MarketKey()` 返回 `"<rulesetID>|<faction>"`。若拿不到规则集，退化为 `"unknown|<faction>"` 并在 UI 顶部红字警告。

---

## 5. 数据模型

```lua
ProfitBoardDB = {
  version = 1,
  settings = {
    ahCutPercent      = 5,      -- 拍卖行抽成
    depthPercent      = 20,     -- depth 取最便宜 N% 挂单
    depthMaxUnits     = 1000,   -- depth 最多累计多少单位
    historyDays       = 30,
    medianWindowDays  = 7,
    maxRecursion      = 3,      -- 材料自造递归深度
    frameBudgetMs     = 5,      -- 分帧预算
    scanCooldownSec   = 900,    -- 15 分钟
    minProfit         = 0,      -- 铜
    minMarginPercent  = 0,
    maxListings       = 0,      -- 0 = 不限
    hideMissingPrices = true,
    onlyLearned       = false,
    autoPromptOnAH    = true,
    logLevel          = "info",
  },
  -- 每个市场独立
  markets = {
    ["<rulesetID>|<faction>"] = {
      updatedAt = 0,
      partial   = false,
      scanCount = 0,
      items = {
        -- 精简档：所有出现过的物品
        [itemID] = { min = 0, depth = 0, num = 0, qty = 0, t = 0,
                     h = { d1, v1, d2, v2, ... } },   -- 历史：日序号 + depth，最多 30 对
      },
      ladders = {
        -- 仅"关心物品"（配方产物 ∪ 配方材料）保留挂单价梯，用于重算 depth
        [itemID] = { { p = 单价, q = 数量 }, ... },  -- 最多 200 条，升序
      },
    },
  },
  snapshotText = "",  -- 最近一次导出的可恢复文本（截断 400KB）
}

ProfitBoardCache = {
  version = 1,
  recipeVersion = "",     -- 与 PB.StaticRecipes.version / Game 枚举指纹比对，变化则重建
  recipes = { ... },      -- 配方源缓存（含 source 字段）
  learned = { [recipeID] = true },
  computedAt = 0,
}
```

### 容量控制

- `items`：全服可交易物品量级 1–3 万，每条 6 个数字 + 至多 60 个历史数字，实测控制在 ~10MB 以内。
- `ladders`：只对「配方产物 ∪ 配方材料」建梯子（预计 2000–4000 个物品），每个最多 200 条。
- 超出上限时按「最久未更新」淘汰历史，不淘汰当前价。

---

## 6. 价格库（Market.lua）

### 6.1 扫描流程

```
Scan():
  1. 校验 caps.ahReplicate 与节流（now - lastScanAt < 900 → 提示剩余秒数，返回）
  2. 校验 AH 是否打开（探针确认判定方式）
  3. C_AuctionHouse.ReplicateItems()
  4. 等 REPLICATE_ITEM_LIST_UPDATE（同时注册超时 120s，超时标 partial）
  5. total = C_AuctionHouse.GetNumReplicateItems()
  6. 分帧循环 i = 1..total：
       itemID, qty, unitPrice = 解析 GetReplicateItemInfo(i)   -- 字段映射见下
       若 itemID 为空 → 计入 skipped，跳过（不报错）
       聚合到 temp[itemID]
       每帧预算 frameBudgetMs，超预算 yield
  7. 收尾：写 markets[key]，更新 updatedAt / scanCount，追加历史
  8. 触发 PB:Fire("MARKET_UPDATED")
```

**字段映射自检**：第一次拿到记录时，取 `GetReplicateItemLink(i)` 解析 itemID，与候选字段比对；不一致则把整张记录 dump 到 `/pb status`，停止扫描并提示「字段映射需更新」。宁可停，不要算错。

### 6.2 聚合规则

扫描时对每个 itemID 累积：

- `min` = 最小单价（忽略 buyout=0 的异常）
- `num` = 挂单条数
- `qty` = 总数量
- 关心物品额外累积 `prices[] = {p, q}`

扫描结束后对关心物品：

```
按 p 升序排序
cap = min(totalQty * depthPercent/100, depthMaxUnits)
acc = 0, cost = 0
for each {p,q} while acc < cap:
   take = min(q, cap - acc); cost += take * p; acc += take
depth = acc > 0 and cost / acc or min
```

### 6.3 历史与中位价

- 每天（本地日期）每个物品只记一条：`d` = `YYYYMMDD` 数字，`v` = 当天最后一次 depth。
- 中位价 = 最近 `medianWindowDays` 天内所有 `v` 的 median；不足 3 天 → 视为「历史不足」，UI 显示 min 并标注。
- 保留 `historyDays` 天后裁掉最旧。
- `depth` 依赖 `ladders`（最多 200 条）。若某物品挂单超过 200 条被截断，标 `truncated=true`，UI 显示 `≈` 前缀。
- P1 阶段尚无配方源 → 无法确定「关心物品」→ depth 一律等于 `min`，UI 标「单挂单价」。P2 起改为 depth。

### 6.4 节流与并发

- 全局单实例：`PB.Market.scanning` 为真时任何再次触发都只提示。
- `lastScanAt` 落库，跨会话有效。
- 关闭 AH 或登录中断 → `partial = true`，已聚合的部分仍然写入（并标记「不完整扫描」）。

---

## 7. 配方源（RecipeSource.lua）

### 7.1 统一结构

```lua
recipe = {
  id       = 12345,
  name     = "厚丝质绷带",
  profession = "FirstAid",     -- 内部英文 key
  result   = { itemID = 4306, count = 1 },
  reagents = { { itemID = 4305, count = 2, optional = false }, ... },
  level    = 180,              -- 配方等级（可选）
  learned  = false,
  source   = "game" | "static",
}
```

### 7.2 Game 源

配方可能出现的专业（固定常量 `PB.RecipeSource.PROFESSIONS`，运行期按 `GetProfessions()` 标注已学）：

```
Alchemy, Blacksmithing, Enchanting, Engineering, Leatherworking, Tailoring,
Cooking, FirstAid, Mining(熔炼), Fishing(无制造配方，跳过)
```

```
for each skillLine in PROFESSION_SKILL_LINES:
   ids = C_TradeSkillUI.GetAllRecipeIDs(skillLine)      -- [待探针确认]
   for each id: GetRecipeInfo / GetRecipeSchematic → 产物、材料、数量
```

无法枚举时返回空数组，由 Static 兜底。是否要求「该专业已学」也由探针结论决定；若必须已学，则 Game 源只覆盖本角色已学专业。

### 7.3 Static 源

`StaticRecipes.lua` 结构：

```lua
PB.StaticRecipes = {
  version = "1.60.1-20261110",
  recipes = {
    { id=..., profession="Alchemy", result={itemID=...,count=...},
      reagents={{itemID=...,count=...}}, level=... },
  },
}
```

由 `tools/gen_static_recipes.py` 生成（见 §14）。

### 7.4 合并

- 同 `id`：Game 覆盖 Static（字段级合并，Game 缺的字段用 Static 补）。
- `learned` 来自 `C_TradeSkillUI.IsRecipeLearned`（若存在），否则按「该专业是否已学 + 配方是否在 Game 枚举结果中」推断。
- 合并结果缓存在 `ProfitBoardCache.recipes`，配方库版本号变化时失效。
- 合并后同时构建**反向索引** `byProduct[itemID] = { recipe, ... }`，供 `ctx.recipesFor()` 使用（成本引擎的自造判定依赖它）。
- 反向索引与配方集同生命周期，配方版本变化时一起重建。

---

## 8. 成本/收益引擎（Cost.lua，纯函数）

### 8.1 输入抽象

引擎不直接读 WoW API，只接受一个 `ctx`：

```lua
ctx = {
  priceOf = function(itemID) return { ah = depth or nil, vendor = copper or nil, min = ..., num = ... } end,
  recipesFor = function(itemID) return array_of_recipes end,
}
```

这样单测可以注入假数据。

### 8.2 算法

```
Cost(itemID, depth, visiting):
  if depth > maxRecursion: return nil
  if visiting[itemID]: return nil            -- 环形，放弃自造
  visiting[itemID] = true
  market = ctx.priceOf(itemID)
  best = min(market.ah, market.vendor)        -- 直购/卖店购买
  bestFrom = best == market.ah and "ah" or "vendor"
  for each r in ctx.recipesFor(itemID):
     c = CraftCost(r, depth, visiting)       -- 见下
     if c and c.unit < best: best, bestFrom = c.unit, "craft:"..r.id
  visiting[itemID] = nil
  return best, bestFrom

CraftCost(recipe, depth, visiting):
  total = 0
  for each re in recipe.reagents:
     if re.optional then skip
     c = Cost(re.itemID, depth+1, visiting)
     if c == nil: return nil                -- 缺价，整条配方不可算
     total += c * re.count
  if total == 0: return nil
  unit = total / recipe.result.count
  return { unit = unit, total = total }
```

### 8.3 收益与指标

```
ProductValue(recipe):
  ahNet = result.count * depthPrice(result)                 -- 无 AH 价则 nil
  if ahNet ~= nil then
     ahNet = ahNet * (100 - ahCutPercent) / 100
     ahNet = ahNet - deposit                               -- 默认 0，见下
  end
  vendor = result.count * vendorPrice(result)               -- 无卖店价则 nil
  if ahNet == nil and vendor == nil then return nil always end
  if ahNet == nil then return vendor, "vendor" end
  if vendor == nil then return ahNet, "ah" end
  return (ahNet >= vendor) and ahNet or vendor, (ahNet >= vendor) and "ah" or "vendor"

CraftProfit(recipe):
  mat = CraftCost(recipe, 0, {})
  if mat == nil: return { missing = true, missingCount = <未取到价的材料数> }
  value, channel = ProductValue(recipe)
  if value == nil: return { missing = true }
  profit = value - mat.total
  margin = mat.total > 0 and profit / mat.total * 100 or 0
  return { cost = mat.total, value = value, profit = profit, margin = margin, channel = channel }
```

### 8.4 明确规则

- **缺价不猜**：任一行材料既无 AH 价也无卖店价 → 该配方 `missing=true`，不参与排名，UI 显示「缺价 x/y」。
- **分解价不进主排名**：Forever 分解表未验证，先作为可选列并标 beta。
- **多产出**：统一按 `result.count` 摊到单位成本。
- **可选材料**：不计入基准成本，在材料明细里单列。
- **不含上架保管费**：利润只扣 `ahCutPercent`（默认 5%）成交抽成，不扣挂单保管费（`deposit` 默认 0）。无限服保管费规则未验证，UI 不展示「含保管费」的假精度。
- **缓存**：`Cost` 结果按 `itemID|depth` 缓存，一次计算会话内复用；`items` 价格变化或配方版本变化时清空。

---

## 9. 计算与缓存（Compute.lua）

```
ComputeAll():
  results = {}
  for each recipe in RecipeSource.All():
     r = Cost.CraftProfit(recipe)
     r.recipe = recipe
     results[] = r
  sort by profit desc
  PB.Compute.results = results
  PB.Compute.computedAt = time()
  PB:Fire("RESULTS_UPDATED")
```

- 全量计算必须分帧（同样用 `frameBudgetMs`），进度显示 `已算 n/N`。
- 增量：若配方集与价格库未变，直接复用上次结果。
- 预估规模：全配方约 2500–4000 条，每条材料 2–8 个，递归 3 层且有缓存，应在 1–3 秒内完成。

---

## 10. UI（UI.lua）

单窗口，宽约 900px，高约 560px。顶部筛选栏，中部虚拟滚动表格，底部状态栏。

### 列

`配方 | 专业 | 产物×数量 | 材料成本 | 成品价 | 利润 | 利润率 | 挂单 | 数据`

- 点表头排序（升/降）。
- 利润正绿负红；挂单 > maxListings 的行标灰。
- `数据` 列：`3天前` / `历史不足` / `缺价`。

### 筛选栏

- 利润 ≥ `[输入]` 金；利润率 ≥ `[输入]` %；挂单 ≤ `[输入]`；`[x] 隐藏缺价`；`[ ] 只看已学`；搜索框。
- 「只看已学」默认关闭（因为核心价值是全配方）。

### 行展开

点行 → 展开材料明细，每条：`材料名 | 数量 | 单价 | 来源(AH/自造/商店) | 小计`。

### 虚拟滚动

固定池 30 行 frame，滚动时重绑数据，不随结果数量创建 frame。

### 中文

所有文案中文；金额统一 `1金 23银 45铜`（0 的部分省略）。物品名优先 `C_Item.GetItemNameByID`，失败用缓存名，再失败显示 `物品#12345`。

---

## 11. 命令

```
/pb                  打开窗口
/pb scan             扫描拍卖行（需在 AH 打开状态）
/pb top [n]          控制台打印利润前 n 条（默认 20）
/pb price <链接|名称> 查单个物品价格与历史
/pb filter <key> <value>   设置筛选（profit/margin/listings/learned/missing）
/pb export           导出 CSV（弹出可复制文本框）
/pb import           从文本恢复价格库
/pb status           profile、市场 key、价格库规模、配方数、缺失能力
/pb reset market|config|all
```

---

## 12. 错误处理与持久化

1. **API 缺失**：全部走 `PB.Util.Has()` + `pcall`；缺失项记入 `PB.Profile.missing`，`/pb status` 显示；功能降级而非报错。
2. **SavedVariables 回读失败**（Forever 已知问题）：
   - 每次扫描结束写 `snapshotText`（简化文本：`market|itemID|min|depth|num|qty|d,v;...`）。
   - 启动时若 `markets` 为空但 `snapshotText` 非空 → 自动恢复并提示，不静默丢数据。
3. **扫描中断**：`partial=true`，保留已聚合数据，UI 标注「上次扫描不完整」。
4. **字段映射不符**：停止扫描 + 输出 dump，不产出错误结果。
5. **模块 init 失败**：`Core` 用 `pcall` 逐个 init，任一失败只禁用该模块并在 `/pb status` 标红。
6. **计算 OOM / 卡顿**：分帧 + 结果上限（最多保留 5000 条，超出截断并提示）。

---

## 13. 测试计划

### 13.1 纯函数单测（不依赖 WoW 客户端）

- `Cost.lua`：中间件递归、环形配方、多产出、缺价、自造更贵时回退直购、递归深度上限。
- `Market` 聚合：depth 计算、忽略零价、数量不足 20% 边界、历史去重。
- `Util.lua`：金/银/铜格式化与解析（含负数、0、极大值）。
- 运行方式：本机已装 **Python 3.12 + lupa 2.8**，沿用 `tests/run_be.py` 的模式写 `tests/run_pb.py`（用 lupa 加载 Lua 源码 + `tests/stub_pb.lua` 桩件），`python tests/run_pb.py` 一键跑全部用例；不依赖系统 Lua 解释器。

### 13.2 客户端集成验收

- P0：`/pb probe` 输出一段文本回传，核对 API 能力。
- P1：扫一次后 `/pb price 亚麻布`，与 AH 手查最低价一致；`/reload` 后价格仍在。
- P2：`/pb top 20` 列出的第一名的材料成本可手工复算一致（误差 ≤ 1 铜）。
- P3：三个筛选条件组合后结果数正确；滚动不卡顿。

---

## 14. 静态配方导出脚本（P2）

`tools/gen_static_recipes.py`，两种输入源，输出 `StaticRecipes.lua`：

1. **客户端 DB2 导出**（主）：用户在自己机器上用 DBC/DB2 工具导出 `SkillLineAbility` / `CraftingReagent` / `SpellName` 等为 CSV/JSON，脚本转成 Lua 表。
2. **wago.tools / wow.tools API**（备）：脚本直接拉取对应 build 的 DB2 页面并解析（若 Forever build 可用）。

校验要求：

- 每条配方必须有 `result.itemID` 与至少 1 个 `reagents`，否则丢弃并计数。
- 产物或材料缺物品名的，保留 itemID，名字留空（插件运行时按 ID 查）。
- 输出带 `version` 与配方总数，便于比对。

若 P0 证明 Game 源能枚举全部配方，此脚本降级为「可选增强」，不阻塞主线。

---

## 15. 分阶段与验收

| 阶段 | 交付 | 验收标准 |
|---|---|---|
| **P0 探针** | 独立 `ProfitProbe` 插件（不落在 ProfitBoard 内，避免污染） | `/probe` 输出：build、AH API 存在性、首条 Replicate 记录字段、total 数量、全扫耗时、专业 API 存在性与结果样例、物品 API 与卖店价取法、规则集/阵营标识 |
| **P1 价格库** | Market + Config + Util + Core + Slash(`price`/`scan`/`status`) | 扫描成功、`/pb price` 正确、reload 后数据在、15 分钟节流生效 |
| **P2 引擎** | RecipeSource + StaticRecipes + Cost + Compute + `/pb top` | 全配方计算完成、缺价标注正确、手工复算误差 ≤ 1 铜 |
| **P3 UI** | UI + 排序/筛选/展开 | 日常决策可完全不看聊天框 |
| **P4 增强** | 导出 CSV、多角色合并、采购清单 | 可选，按实际需要排期 |

P0 是硬门槛：在拿到探针结果前，P1 的 AH 字段映射与 P2 的配方枚举方式都按「待定」处理。

---

## 16. 风险与未知（按影响排序）

1. **`C_TradeSkillUI` 在 16001 的真实行为未知** —— 若无法枚举未学配方，全配方目标必须依赖静态库；静态库又依赖客户端 DB2 数据可用性。
2. **`GetReplicateItemInfo` 字段顺序未知** —— 已设计「首次记录自检 + 不符即停」。
3. **SavedVariables 回读不稳** —— 已有文本快照兜底，但仍需实测。
4. **全量快照性能** —— 5–6 万条分帧解析，若单帧预算控制不好会卡；已设计 4–6ms 预算与进度条。
5. **价格是快照，无成交速度** —— 利润高 ≠ 卖得掉；UI 用挂单数做竞争度参考，并在文档与界面注明。
6. **静态库数据准确性** —— Forever 改动过配方数值，静态表必须带版本号，且以 Game 源为准。

---

## 17. 不引入的东西

- 不引入任何第三方 Lua 库（无 Ace3）。
- 不做多语言（先中文）。
- 不做云端同步、不做账号间自动同步（超出插件能力）。
