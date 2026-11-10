# wow-forever-addons 开发文档

> 面向：接手继续开发的自己（或任何新的 AI/开发者）。
> 目标：读完这份文档，不用回看聊天记录，就能知道**现在能跑什么、卡在哪、下一步怎么做**。
> 最后更新：2026-11-10

---

## 0. 五分钟上手

```bash
git clone https://github.com/glveil4231016/wow-forever-addons.git
cd wow-forever-addons

python -m pip install lupa      # 唯一依赖，测试用
python tests/run_pb.py          # 期望：PASS 48  FAIL 0
python tests/syntax_check.py    # 期望：syntax ok: 13 files
```

安装到游戏：把 `ProfitBoard/` 整个文件夹复制到
`<游戏目录>\_forever_\Interface\AddOns\ProfitBoard`，重启客户端。

进游戏后：打开拍卖行 → `/pb scan` → `/pb`。

---

## 1. 仓库结构

```
wow-forever-addons/
├─ README.md                      仓库总览
├─ .gitignore                     排除 *.zip / __pycache__ / .svn 等
├─ .github/workflows/tests.yml    CI：跑单测 + 语法检查
├─ BlackEvidence/                 已有插件：黑名单 + 证据快照（与本项目独立）
│  ├─ BlackEvidence.toc … （多 flavor TOC）
│  ├─ Core/Profile/Config/… 共 20 个 .lua
│  ├─ recorder/blackevidence_recorder.py   Python 自动保存助手
│  ├─ CONTRACT.md                 该插件的模块契约（重要）
│  └─ 安装指南.md
├─ ProfitBoard/                   本项目：全配方利润统计
│  ├─ ProfitBoard.toc             主清单（Interface 16001 / forever）
│  ├─ ProfitBoard_Camelot.toc     flavor 专用清单（内容相同）
│  ├─ Core.lua                    事件总线 + 模块装配 + SavedVariables 初始化
│  ├─ Profile.lua                 能力探测 + 市场 key + 卖店价
│  ├─ Config.lua                  默认配置 + clamp + 迁移
│  ├─ Util.lua                    金额格式化/解析、中位数、日期、clamp
│  ├─ Market.lua                  扫描、聚合、depth、历史、文本快照、字段自检
│  ├─ StaticRecipes.lua           静态配方表（当前为空壳，见 §11）
│  ├─ RecipeSource.lua            配方源：Game / Static / 合并 / 反向索引
│  ├─ Cost.lua                    成本/收益纯函数引擎
│  ├─ Compute.lua                 全量计算 + 筛选
│  ├─ UI.lua                      表格窗口（虚拟滚动 24 行、排序、搜索）
│  ├─ Export.lua                  CSV 导出 + 快照导入
│  ├─ Slash.lua                   /pb 命令族
│  └─ README.md                   面向用户的使用说明
├─ ProfitProbe/                   开发用探针（不随插件发布）
│  ├─ ProfitProbe.toc
│  └─ ProfitProbe.lua             /probe 输出客户端 API 能力报告
├─ docs/
│  ├─ BlackEvidence-实施方案.md
│  ├─ DEVELOPMENT.md              ← 本文件
│  └─ superpowers/
│     ├─ specs/2026-11-10-profitboard-design.md   设计文档（决策与算法来源）
│     └─ plans/2026-11-10-profitboard.md          实施计划（12 个任务，含成品代码）
├─ tests/
│  ├─ stub_pb.lua                 WoW API 桩 + 断言工具
│  ├─ run_pb.py                   ProfitBoard 单测驱动（lupa）
│  ├─ run_be.py                   BlackEvidence 冒烟测试（硬编码了本机路径，见 §14）
│  ├─ stub_be.lua
│  ├─ syntax_check.py             全部 .lua 语法检查
│  ├─ test_util.lua               14 例
│  ├─ test_config.lua             4 例
│  ├─ test_market.lua             9 例
│  ├─ test_market_history.lua     5 例
│  ├─ test_cost.lua               7 例
│  ├─ test_recipes.lua            6 例
│  └─ test_compute.lua            4 例
└─ tools/
   └─ gen_static_recipes.py       配方导出 → StaticRecipes.lua
```

---

## 2. 当前状态（2026-11-10）

| 项 | 状态 |
|---|---|
| 代码完整度 | ProfitBoard 13 个模块全部写完，可加载 |
| 单测 | 48 例全绿；13 个 Lua 文件语法检查通过 |
| 包体 | `ProfitBoard.zip` ≈ 19 KB，`ProfitProbe.zip` ≈ 2 KB（本地，未入库） |
| 客户端实测 | **未做**。这台开发机只有正式服客户端，没有无限客户端 |
| 配方条数 | **0 条**（配方源尚未确认，`StaticRecipes.lua` 为空壳） |
| 价格库 | 未扫过真实数据；字段映射有自检保护 |
| 已知阻塞 | 需要一份 `/probe` 输出（见 §10） |

**一句话**：代码写完了，但所有依赖客户端事实的常量都还是「零售默认值 + 运行时自检」，必须用探针结果锁定。

---

## 3. 目标客户端与硬约束

| 事实 | 值 / 结论 | 影响 |
|---|---|---|
| 客户端 | 《魔兽世界：无限》WoW Forever，1.60.1 | — |
| Interface | `16001` | TOC 必须写 16001 |
| 安装目录 | `_forever_\Interface\AddOns\` | 不是 `_retail_` / `_classic_` |
| TOC flavor 后缀 | `_Camelot.toc`，并声明 `## AllowLoadGameType: forever` | 两个 TOC 都要保留 |
| 引擎 | 现代 12.x 引擎 | 用 `C_*` 命名空间，禁止 3.3.5a 写法 |
| 专业模型 | Classic 1–300，无品质/专精/multicraft/resourcefulness | 成本模型简单：产物 + 材料 + 数量 |
| 拍卖行 | 现代 AH（commodities 按单价买、自动合并堆叠） | 旧 `QueryAuctionItems` 系列 API 已删除 |
| 市场划分 | **规则集 × 阵营**，约 6–8 个独立市场（普通/PvP/RP/专家 × 联盟/部落） | 价格库 key 禁止用 `GetRealmName()` |
| 全量快照 | `C_AuctionHouse.ReplicateItems()`，服务端约 15 分钟一次 | 扫描必须节流 |
| 已移除的旧 API | `GetItemInfo` / `GetItemIcon` / `GetItemQualityColor`（Forever 移除） | 必须走 `C_Item.*`，且全部 pcall + 存在性判断 |
| SavedVariables | Forever 有过「写得出、读不回」的 bug | 已做 `snapshotText` 文本快照兜底 |

> 参考：`docs/superpowers/specs/2026-11-10-profitboard-design.md` §2 有逐条来源。

### 3.1 Lua 版本陷阱（很重要）

- **游戏内是 Lua 5.1**；**测试环境经 lupa 跑的是 Lua 5.5**（错误栈里会看到 `lupa.lua55`）。
- 所以：不要用 `//`、`goto`、`table.unpack`（用 `unpack` 会 5.5 报错，两边都不要用）、`integer/float` 差异敏感的代码。
- `string.format("%d", x)` 在 5.3+ 遇到非整数浮点会直接报错。**任何传给 `%d` 的值先过 `PB.Util.Round()`**。

---

## 4. 架构

```
                    ┌──────────────────────────────┐
  拍卖行打开          │  Core.lua                    │
  /pb scan  ────────▶ │  ADDON_LOADED → Detect/Config │
                    │  → Market.New → RecipeSource  │
                    │  → Compute.Run                │
                    └───────────┬──────────────────┘
                                │
        ┌───────────────────────┴────────────────────────┐
        ▼                                                ▼
┌────────────────┐   listings[]                ┌──────────────────┐
│ Market.lua     │ ──────────────▶ Aggregate   │ RecipeSource.lua │
│ ReplicateItems │                items[]      │ Game + Static    │
│ 分帧 6ms/帧     │                ladders{}     │ → All/RecipesFor │
│ 字段自检        │                             │ → InterestingSet │
└───────┬────────┘                             └────────┬─────────┘
        │ markets[key].items                             │
        ▼                                                ▼
┌────────────────┐        ctx{priceOf, recipesFor}  ┌─────────────┐
│ ProfitBoardDB  │ ───────────────────────────────▶ │ Cost.lua    │
│ (SavedVariables)│                                 │ 递归自造判定 │
└───────┬────────┘                                  └──────┬──────┘
        │                                                  │
        │            ┌──────────────┐                      │
        └───────────▶│ Compute.lua  │◀─────────────────────┘
                     │ 排序 + 筛选   │
                     └──────┬───────┘
                            ▼
                  ┌───────────────────┐
                  │ UI / Slash / Export│
                  └───────────────────┘
```

设计原则：**数据层不认识 UI**。`Cost.lua` 只吃 `ctx`（两个函数），所以能在游戏外单测。

---

## 5. 模块契约

> 约定：每个文件头 `local ADDON, PB = ...`；除两个 SavedVariables 外不创建全局变量。

### 5.1 `Util.lua` → `PB.Util`

| 函数 | 返回 | 说明 |
|---|---|---|
| `Has(tbl, key)` | bool | 函数存在性判断 |
| `SafeCall(fn, ...)` | ok, ... | pcall 包装 |
| `Clamp(v, lo, hi)` | number | 非数字按 lo 处理 |
| `Round(v)` | number/nil | `floor(v+0.5)`，传给 `%d` 之前必须过它 |
| `FormatMoney(copper)` | string | `1金 23银 45铜`；0 → `0铜`；负数带前导 `-` |
| `ParseMoney(text)` | number/nil | 支持 `12345`、`1金23银45铜`、`1金45铜` |
| `Today()` | number | `YYYYMMDD` |
| `Median(list)` | number/nil | 不修改入参，内部复制后排序 |
| `Copy(t)` | table | 浅拷贝 |

### 5.2 `Profile.lua` → `PB.Profile`

| 成员 | 说明 |
|---|---|
| `P.SELL_PRICE_INDEX = 11` | **待校准**：`C_Item.GetItemInfo` 多返回值中卖店价的下标 |
| `P.caps.ahReplicate / itemInfo / tradeSkill / gameRules / recipeAll` | 能力探测结果 |
| `P.Detect()` | 登录时调用一次；同时设置 `P.ruleset` / `P.faction` |
| `P.Ruleset()` | `pvp` / `rp` / `rppvp` / `hc` / `normal` |
| `P.MarketKey()` | `"<ruleset>|<faction>"`，价格库分仓键 |
| `P.VendorPrice(itemID)` | 卖店价（铜），失败返回 nil，绝不报错 |
| `P.StatusLine()` | `/pb status` 第一行 |

### 5.3 `Config.lua` → `PB.Config`

`Config.New(db)` 返回带 `Get/Set` 的实例；`Config:Load(db)` 补默认值 + clamp。

默认值：

```
ahCutPercent 5          depthPercent 20         depthMaxUnits 1000
historyDays 30          medianWindowDays 7      maxRecursion 3
frameBudgetMs 5         scanCooldownSec 900
minProfit 0             minMarginPercent 0      maxListings 0
hideMissingPrices true  onlyLearned false       autoPromptOnAH true
```

clamp 区间见 `Config.lua` 的 `CLAMP` 表（例如 `ahCutPercent` 0–50、`maxRecursion` 1–5）。

### 5.4 `Market.lua` → `PB.Market`

| 函数 | 说明 |
|---|---|
| `REPLICATE_FIELDS` | `{ id, qty, price }`。**运行时会被 `ResolveFields` 覆盖** |
| `ParseItemLinkID(link)` | 从 `item:2589:...` 取出 2589 |
| `ResolveFields(values, linkID)` | 用第一条记录反查 itemID 下标，推出 `{id, qty=id-1, price=id-2}`；失败返回 `false, 原因` |
| `DepthFromLadder(ladder, capUnits)` | 按单价升序累计到 capUnits，返回加权均价 |
| `Aggregate(listings, interesting, opts)` | 返回 `items, ladders`；`opts = {depthPercent, depthMaxUnits, maxLadder, capUnits}` |
| `New(db, marketKey)` | 实例，`m.market` 指向该市场表 |
| `m:Scan(callback)` | 协程 + OnUpdate，每帧 6ms；成功 `callback(true, scanCount)`，失败 `callback(false, 原因)` |
| `m:Scanning()` | 是否扫描中 |
| `m:PriceOf(itemID)` | `{ ah=depth, min, num, qty, vendor, updatedAt, truncated }` |
| `m:AppendHistory(itemID, day, value)` | 同日覆盖，跨日追加，最多 `historyDays*2` 个数字 |
| `m:MedianPrice(itemID, windowDays)` | 窗口内 <3 天返回 nil；日期用 `Util.DayNumber` 的连续日序号比较，跨月/跨年正确 |
| `m:SnapshotText()` / `m:RestoreFromText(text)` | `id:min:depth:num:qty;…` 文本快照 |

### 5.5 `RecipeSource.lua` → `PB.RecipeSource`

| 函数 | 说明 |
|---|---|
| `GAME_RECIPE_API` | `"output"` / `"schematic"` / `"none"`，`AutoDetect()` 自动判定 |
| `AutoDetect()` | 有 `GetRecipeOutputItems` → output；有 `GetRecipeSchematic` → schematic；否则 none |
| `SetSources({static=, game=})` | 触发重建；同 id 时 game 覆盖 static 字段 |
| `All()` / `Count()` | 合并后的全部配方 |
| `RecipesFor(itemID)` | 反向索引：产出该物品的配方数组 |
| `InterestingSet()` | 产物 ∪ 材料 的 itemID 集合（决定哪些物品保留价格梯子） |
| `FromGame()` | 遍历 `RS.SKILL_LINES` 调 `GetAllRecipeIDs` |
| `Refresh()` | `AutoDetect()` + 合并静态表与游戏源，返回条数 |

配方结构：

```lua
{ id = 1234, profession = "炼金术", name = "治疗药水",
  result   = { itemID = 929, count = 1 },
  reagents = { { itemID = 2455, count = 1 }, { itemID = 2454, count = 1 } },
  learned  = false, level = 60, source = "game" | "static" }
```

### 5.6 `Cost.lua` → `PB.Cost`

```lua
ctx = {
  ahCut = 0.05, maxRecursion = 3,
  priceOf    = function(itemID) return { ah = 铜/单位 or nil, vendor = 铜 or nil } end,
  recipesFor = function(itemID) return recipe[] end,
}
Cost.CraftProfit(recipe, ctx)
-- → { cost, value, profit, margin, channel, details, missing, missingCount }
```

四条硬规则：

1. **缺价不猜**：任一非可选材料既无 AH 价也无卖店价 → `missing = true`，不参与排名。
2. **自造递归**：材料按 `min(直购, 自造成本)` 取；`visiting` 集合防环；深度上限 `maxRecursion`。
3. **多产出**：材料总额 ÷ `result.count` 得单位成本；成品价值按 `count` 放大。
4. **不含保管费**：只扣 `ahCutPercent`，`deposit` 未建模。

### 5.7 `Compute.lua` → `PB.Compute`

| 函数 | 说明 |
|---|---|
| `MakeCtx(market, settings)` | 组装 Cost 用的 ctx |
| `ComputeAll(market, settings)` | 全量计算并排序：可算的按利润降序，缺价的排最后 |
| `Run(market, settings, onDone)` | 计算 + 缓存到 `C.results` + 刷新 UI |
| `Filter(results, settings, market)` | 应用 `hideMissingPrices / onlyLearned / minProfit / minMarginPercent / maxListings` |

### 5.8 UI / Export / Slash

- `PB.UI`: `Refresh() / Open() / Close() / Toggle()`。虚拟滚动固定 24 行；点行在聊天框打印材料明细。
- `PB.Export`: `CSV()`（弹可复制文本框）/ `Import(text)`。
- `/pb` 命令见 §12。

---

## 6. 数据结构（SavedVariables）

```lua
ProfitBoardDB = {
  version = 1,
  settings = { …见 §5.3… },
  markets = {
    ["normal|alliance"] = {
      updatedAt = 1762732800,   -- 上次成功扫描（节流依据）
      partial   = false,        -- 上次是否不完整
      scanCount = 3,
      items = {
        [2589] = {
          min = 23, depth = 25, num = 40, qty = 16941,
          t = 1762732800,       -- 该物品价格时间
          truncated = false,    -- 梯子是否被 200 条上限截断
          h = { 20261108, 22, 20261109, 24 },   -- 日, 值, 日, 值 … 最多 60 个数字
        },
      },
      ladders = {               -- 仅"关心物品"，最多 200 条
        [2589] = { { p = 23, q = 200 }, { p = 24, q = 500 } },
      },
    },
  },
  snapshotText = "2589:23:25:40:16941;…",   -- 文本兜底，截断 400KB
}

ProfitBoardCache = { version = 1, recipeVersion = "", recipes = {}, learned = {}, computedAt = 0 }
```

> 容量：items 量级 1–3 万，实测预期 10MB 内；超限时按最久未更新淘汰历史，不淘汰当前价。

---

## 7. 关键算法

### 7.1 depth 价（为什么不用最低价）

最低价可能是一条钓鱼挂单（1 个 1 铜）。所以取**最便宜 20% 数量**的加权均价：

```
cap = min(该物品总数量 × depthPercent%, depthMaxUnits)
按单价升序累计，直到累计数量达到 cap
depth = 累计金额 / 累计数量
```

例：50 个 @10 铜 + 50 个 @100 铜，总 100，cap=20 → 20 个都在 10 铜档 → depth=10。

无梯子（非"关心物品"）时 depth 退化为 `min`，UI 标「单挂单价」。

### 7.2 成本递归

```
Cost(item, depth, visiting):
  depth > maxRecursion        → nil
  visiting[item]              → nil（环形）
  best = min(AH depth, 卖店价)
  best = min(best, 每条产出该物品的配方的单位成本)
  return best
```

### 7.3 筛选语义

| 配置 | 语义 |
|---|---|
| `hideMissingPrices` | 有缺价材料时整个配方隐藏（默认 true） |
| `onlyLearned` | 只看本角色已学（默认 false，因为全配方才是本项目卖点） |
| `minProfit` | 利润 ≥ N 铜 |
| `minMarginPercent` | 利润率 ≥ N% |
| `maxListings` | 成品挂单条数 ≤ N（抄底/防踩踏），0 = 不限 |

---

## 8. 一次扫描的完整时序

1. `/pb scan` → `Market:Scan()`
2. 校验 `caps.ahReplicate`、15 分钟节流、`scanState` 并发
3. `C_AuctionHouse.ReplicateItems()`
4. 协程轮询 `GetNumReplicateItems()`，最多 600 帧；仍为 0 则失败
5. **字段自检**：读第 1 条记录 + `GetReplicateItemLink(1)` → `ResolveFields` 反推下标；失败立刻中止并打印提示，**不写任何价格**
6. 逐条 `GetReplicateItemInfo(i)`，按 `{id,qty,price}` 入 `listings`，每 200 条 yield 一次
7. `Aggregate(listings, InterestingSet(), opts)` → `items`（全部物品）+ `ladders`（关心物品）
8. 写 `market.items`、追加历史、更新 `updatedAt` / `scanCount`、写 `snapshotText`
9. `callback(true)` → `Slash` 里接着 `Compute.Run()` 重算并刷新 UI

失败路径全部保留旧数据，只标 `partial`。

---

## 9. 测试体系

```
tests/run_pb.py      加载 stub → 13 个模块 → 7 个 test_*.lua → 打印 PASS/FAIL，失败时退出码 1
tests/syntax_check.py 逐个 load() 全部 .lua（含 ProfitProbe），只查语法
```

- 断言工具：`PB.Test.it/eat/near/truthy`，见 `tests/stub_pb.lua`。
- 桩件只覆盖纯函数需要的最小 API：`GetBuildInfo/time/date/UnitFactionGroup/CreateFrame/SlashCmdList/C_Timer`。
- 新增模块时：先在 `test_*.lua` 写失败用例，再实现。
- **不要**在单测里依赖 `C_AuctionHouse` / `C_TradeSkillUI` 的真实行为，注入假 `ctx` / `market`。

`tests/run_be.py` 是 BlackEvidence 的冒烟测试，硬编码了 `D:\文档\Trae-CN\...` 的 `PYLIB` 路径，**换机器会直接失败**，属于已知技术债。

---

## 10. 探针 → 校准手册（当前唯一的阻塞项）

### 10.1 怎么跑

1. `ProfitProbe/` 复制到 `_forever_\Interface\AddOns\ProfitProbe`
2. 重启客户端，进游戏，**打开拍卖行**
3. `/probe`，等 `===== ProfitProbe end =====`（最长 2 分钟）
4. 保存整段输出

### 10.2 用它确定三件事

**A. `SELL_PRICE_INDEX`**

报告里有 `C_Item.GetItemInfo(2589) -> 1=… | 2=… | …`。对照游戏内亚麻布 tooltip 的「卖店价格」，找到数值相同的下标，写进 `ProfitBoard/Profile.lua`：

```lua
P.SELL_PRICE_INDEX = 11   -- ← 改成实测下标
```

**B. 价格单位（最容易算错的一处）**

在报告里找 `Replicate[N]` 的原始字段，结合拍卖行界面确认：

- 如果 `price` ≈ 界面上的**单价** → 现状正确，不用改。
- 如果 `price` ≈ **整堆总价**（单价 × 数量）→ 商品会算贵几十倍，必须在 `Market.lua` 的聚合处除以数量：

```lua
-- Market.lua 协程内，listings 组装处
local unit = price
if PRICE_IS_STACK_TOTAL and qty and qty > 1 then unit = price / qty end
listings[#listings + 1] = { itemID = id, qty = qty, unit = unit }
```

建议加一个常量 `M.PRICE_IS_STACK_TOTAL = false`，按探针结果改。

**C. 配方能不能枚举未学配方**

报告里看 `C_TradeSkillUI.GetAllRecipeIDs` 是否 `[OK]`，以及当前角色未学专业时是否能取到数量。判定：

- 能拿到「没学过的专业/配方」→ 直接可用，`AutoDetect()` 会选 `output` 或 `schematic`，无需额外工作。
- 只能拿到已学 → 走静态库（§11）。

### 10.3 顺手确认

- `GetReplicateItemLink` 是否存在（不存在则字段自检被跳过，改为信任 `REPLICATE_FIELDS`）
- `GetNumReplicateItems` 返回的真实数量级（决定分帧预算是否够）
- `Enum.GameRule` 里到底有哪些规则集，`Profile.Ruleset()` 的映射是否要补

---

## 11. 配方源两条路线

### 路线 A：游戏内枚举（优先）

`AutoDetect()` 自动选：

- `C_TradeSkillUI.GetRecipeOutputItems` + `GetRecipeReagentItems`（新式）
- 或 `C_TradeSkillUI.GetRecipeSchematic(recipeID, false)` 读 `outputs` / `reagents`（更现代）

前提：`GetAllRecipeIDs(skillLineID)` 能给出配方 ID 列表。专业技能线 ID 已写在 `RS.SKILL_LINES`（171 炼金 / 164 锻造 / 333 附魔 / 202 工程 / 165 制皮 / 197 裁缝 / 185 烹饪 / 129 急救 / 186 采矿）。

### 路线 B：静态配方库

1. 准备数据（JSON 或 CSV）：

```json
{ "version": "1.60.1-20261110",
  "recipes": [
    { "id": 1234, "profession": "炼金术", "name": "治疗药水",
      "result": { "itemID": 929, "count": 1 },
      "reagents": [ { "itemID": 2455, "count": 1 }, { "itemID": 2454, "count": 1 } ],
      "level": 60 } ] }
```

CSV 列：`recipeID,profession,name,resultID,resultCount,reagentID,reagentCount,level`（每个材料一行）。

2. 生成：

```bash
python tools/gen_static_recipes.py recipes.json --out ProfitBoard/StaticRecipes.lua
```

3. 校验：脚本会打印 `version=… recipes=N` 和被丢弃的原因计数；`/pb status` 会显示静态表版本。

数据来源选项：客户端 DB2 导出（`SkillLineAbility` / `CraftingReagent` / 物品名表）、wago.tools / wow.tools 的对应 build 页面。注意 Forever 的物品静态数据有缺项，缺名字不影响计算。

---

## 12. 命令参考

```
/pb                       打开/关闭窗口
/pb scan                  全量扫描（15 分钟节流）
/pb top [n]               控制台打印利润前 n 条（默认 20）
/pb price <物品ID>        价格 + 7 日中位
/pb filter profit 10000   利润 ≥ 1 金
/pb filter margin 30      利润率 ≥ 30%
/pb filter listings 10    成品挂单 ≤ 10
/pb filter learned 1      只看已学
/pb filter missing 0      隐藏缺价
/pb export                CSV（可复制文本框）
/pb import <文本>         恢复价格库
/pb status                能力 / 市场 / 价格库 / 配方规模
/pb reset market|config|all
```

---

## 13. 调试手册

| 症状 | 先查 | 处理 |
|---|---|---|
| `/pb status` 配方 0 条 | `RS.GAME_RECIPE_API` | 探针确认 API；或生成静态表 |
| `/pb scan` 立刻说字段无法识别 | `Market.ResolveFields` 返回原因 | 贴 `/probe` 输出，手工填 `REPLICATE_FIELDS` |
| `/pb scan` 说「还需等待 N 秒」 | `market.updatedAt` | 正常节流，等或 `/pb reset market` |
| 扫描完成但 `/pb price` 无数据 | `market.items` 是否为空 | 看 `partial`；看 `total` 是否为 0（AH 没开） |
| 利润明显离谱（贵几十倍） | 价格单位 | 见 §10.2 B |
| 利润全是负的 | depth 价 vs 卖店价 | 可能把整堆价当单价，或税率设错 |
| `/reload` 后价格没了 | SavedVariables 回读 | 看是否自动从 `snapshotText` 恢复；否则 `/pb import` |
| UI 打开空白 | `PB.Compute.results` | 先 `/pb scan`；或 `/pb reset` 后重进 |
| 点表头报错 | `sortValue` 返回类型 | 字符串/数字混排已处理，注意新增列要登记 `type` |
| 中文乱码 | 文件编码 | 全部 UTF-8 无 BOM；PowerShell 用 `-Encoding UTF8` |

---

## 14. 开发约定

**必须**

- 每个文件 `local ADDON, PB = ...`，不新增全局。
- 所有可选 API：存在性判断 + `pcall`；失败降级，不报错。
- 数字进 `string.format("%d")` 之前先 `PB.Util.Round()`。
- 数据层（Util/Profile/Config/Market/Cost/RecipeSource/Compute）不碰 UI，保持可单测。
- 新增行为先加测试，`python tests/run_pb.py` 必须 0 失败再提交。

**禁止**

- 引入第三方 Lua 库（无 Ace3）。
- 用 `GetRealmName()` 做价格库 key。
- 在数据层直接 `print`（用返回值或 `PB:Fire`）。
- 提交 `*.zip`（`.gitignore` 已排除）。
- 把 secret value 写进 SavedVariables。
- 自动买卖 / 自动施法 / 自动移动（无限服自动化红线）。

**提交信息**：`type(scope): 中文描述`，如 `feat(market): 扫描前用物品链接自检字段映射`。

**推送**：本机直连 GitHub 会被 reset，必须走代理（`git config --global https.proxy` 已设为 `127.0.0.1:10809`，换机器要重设）：

```bash
git -c http.proxy=http://127.0.0.1:10809 -c http.version=HTTP/1.1 push origin main
```

---

## 15. 已知限制与技术债

1. **未在真实无限客户端验证**（最高优先，见 §10）。
2. `SELL_PRICE_INDEX` 仍是零售默认 11。
3. 价格单位（单价 vs 整堆总价）未确认。
4. 配方 0 条，静态库未生成。
5. `ladders` 每物品最多 200 条，超了 depth 是近似值（标 `truncated`）。
6. ~~`MedianPrice` 跨月偏差~~ 已修：改用 `Util.DayNumber` 连续日序号。
7. ~~UI 无挂单筛选~~ 已修：标题栏右侧「挂单≤」输入框，回车生效（等价 `/pb filter listings N`）。
8. `Compute.Filter` 依赖 `market` 实例，不传则跳过 `maxListings`。
9. 多角色合并、采购清单（P4）未做。
10. `tests/run_be.py` 硬编码本机路径，跨机器不可用。
11. CI 已配置（`.github/workflows/tests.yml`），但尚未在 GitHub 实际跑过一次。
12. `ProfitProbe` 的 `/probe` 输出可能很长，聊天框会截断，必要时用 `/dump` 或分次执行。

---

## 16. 回家后的续作清单（按优先级）

| # | 任务 | 验收 |
|---|---|---|
| 1 | 跑 `/probe`，回填 `SELL_PRICE_INDEX` 与价格单位 | `/pb price 2589` 与 AH 手查完全一致 |
| 2 | 确认真实扫描：`/pb scan` → 等完成 | 输出「扫描完成，第 1 次」，无字段错误 |
| 3 | `/pb price 2589`、`/reload` 再查 | 价格仍在（SavedVariables OK） |
| 4 | 配方源落地（Game 或静态库） | `/pb status` 配方数 > 0 |
| 5 | `/pb top 20` 手工复算第一名 | 材料成本误差 ≤ 1 铜 |
| 6 | UI 8 条验收（见实施计划 Task 12 Step 4） | 全通过 |
| 7 | 修已知技术债 5/6/7 | 单测补充 |
| 8 | 确认 CI 通过（已在 `.github/workflows/tests.yml` 配好） | Actions 绿 |
| 9 | P4：多角色合并 / 采购清单 / Release 打包 | 按需 |

**新会话开局提示语**（可直接复制）：

> 读 `docs/DEVELOPMENT.md`（尤其 §5 模块契约、§10 探针校准）。当前卡在探针校准，我的探针输出如下：…… 请据此修改 `SELL_PRICE_INDEX`、价格单位，并继续第 4–6 项。

---

## 17. 参考

- `C_AuctionHouse.ReplicateItems` / `GetReplicateItemInfo` / `GetReplicateItemLink`：warcraft.wiki.gg
- 旧 AH API 移除（8.3）：`Patch_8.3.0/API_changes`
- Forever API 变化：`Patch_1.60.1/API_changes`
- Forever 插件移植踩坑清单：`github.com/NoobyGains/Auctioneer-Forever` 的 README（`GetItemInfo` / `GetMouseFocus` 等被移除）
- 现有同类插件对照：CraftProfit、CraftProfit Forever、Blackthornes Tradeskills、Profiteer - Forever、Auctionator（均支持 Forever flavor）
- 设计决策与取舍：`docs/superpowers/specs/2026-11-10-profitboard-design.md`
- 逐任务实施细节：`docs/superpowers/plans/2026-11-10-profitboard.md`

---

## 18. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-11-10 | ProfitBoard 首个完整实现；48 例单测；字段自检；静态库生成器；本文件 |
