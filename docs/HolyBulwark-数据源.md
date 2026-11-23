# HolyBulwark 数据源笔记

> 2026-11-23 实测。**先读这一页再改 `Data.lua` 或抓取脚本**，否则很容易把「客户端基础表里没有」误当成「物品不存在」，一次删掉上千件活物品。

## 1. 结论速查

| 问题 | 答案 |
|---|---|
| 客户端基础 `ItemSparse` 里有 = 游戏里存在？ | **否**。只是「客户端自带」的那部分（19,400 行） |
| 基础表没有的物品一定是 Classic 残留？ | **否**。Forever 用**服务端 hotfix** 推送大量物品（例：14624 死亡骨胸甲） |
| 外部站能给出 Forever 的掉落表？ | **基本不能**。旧副本一律退回 Classic 数据并自行标注 |
| Forever 的属性值哪里来？ | wow-forever.gg / warcraftmaps 的物品页（Forever 列） |

## 2. 客户端数据（wago.tools）

产品 ID 是 **`wowf`**（不是 `wow_classic_era`）。当前：`1.60.1.71037`。

```
# 基础表：只有 19,400 行
https://wago.tools/db2/ItemSparse/csv?build=1.60.1.71037&locale=zhCN
https://wago.tools/db2/Item/csv?build=1.60.1.71037&locale=zhCN      # 32,009 行

# 服务端 hotfix（真正的增减量）：行内 table_name=ItemSparse，record_id=物品 ID
https://wago.tools/hotfixes?build=1.60.1.71037&search=<英文名或关键词>
```

- `Item.db2` 32,009 行 ≫ `ItemSparse` 19,400 行，差的那 12,609 件就是被 hotfix 覆盖/新增的物品（名字、物品等级、需求等级都在 hotfix 行里，字段布局与基础表不同：69 列 vs 99 列）。
- hotfix 行里属性是**法术 ID**（字段 16，例如 `[4571, 4857, 3142, ...]`），不是数值；要还原属性还得查 Spell/SpellEffect。
- 于游戏内，这些物品的名字由服务器下发，`C_Item.DoesItemExist()` / `GetItemInfoInstant()` 可能仍返回 false —— **不能用它们判断物品是否存在**。

## 3. The Forever Era（TFE，当前 `fetch_data.ps1` 的来源）

- `meta.json` 自述：`build 1.60.1.70959`、`eraBuild 1.15.9.69722`、`total 19298`、`fallback 4688`。
- 它是**Classic Era 数据 + Forever 覆盖层**；`search.json` 的 `fb` 字段标记 fallback 行（`fb=0` 才有真正的 Forever 行）。
- 后果：fallback 行的**属性与来源都是 Era 的**。Forever 改过属性的物品（如 940 洞察法袍：25 智力/15 精神 → 24 智力/无精神）在 TFE 里仍是旧值。
- TFE 对 19,400 条客户端基础物品的覆盖是完整的（只缺 57 件 `Deprecated` / `Test` 装备）。

## 4. wow-forever.gg（社区库，推荐用于「Forever 属性」）

- 物品页：`https://wow-forever.gg/db/items/<id>/`（会 301 到带 slug 的地址，需 `-L`）。
- 页面有 `Classic Era | Forever` 两列对照，Forever 值即游戏内值；有 `Forever Changed from Classic` 分组页。
- **掉落表是 Classic 的**：旧副本页面/NPC 页面都带 `Classic data` 标记，列出的物品大量在 `Item.db2` 里存在但客户端无显示行。
- 新物品的来源多为 `Coming soon` / `World drop where: Coming soon`，少数有 `Vendor + /way 坐标`。
- 拍卖行面板能证伪「物品是否存在」：`940`、`2309` 有逐日最低价与挂单数；`18882`(TEST)、`1444`(Deprecated)、任务物品则完全没有价格。

## 5. warcraftmaps.com

- 物品页：`https://warcraftmaps.com/item/<id>/<slug>`，页脚标 `Patch 1.60.1 · Game build 1.60.1.70938 · Source: Game client`。
- 有 Forever 物品页（含新 ID），来源常写 `No verified source in this dataset yet` 或 `This comes from game data, which names no NPC, quest or drop rate yet`。
- 本项目已用它抓配方来源（`tools/holybulwark/fetch_recipe_sources.ps1`）。

## 6. 没有的东西

**没有任何公开的 Forever 掉落表。** 掉落（creature_loot_template）在服务端，客户端 DB2 里不存在；旧副本只能拿到 Era 表，新副本（Alcaz Prison、Krol'dok、达拉然城等）连物品列表都没有。

要得到真实的 Forever 掉落，只有两条路：

1. 游戏内观察：写一个掉落记录器（`LOOT_OPENED` / `CHAT_MSG_LOOT` / `ENCOUNTER_END` → 导出 itemID + NPC + 区域），用玩家的实际数据补 `sources`。
2. 逐物品抓 wow-forever.gg 的 Forever 来源块（覆盖有限，缺的仍然缺）。

## 7. 改数据的规矩

- 过滤「客户端不存在」时，判据必须是 **基础表 ∪ hotfix 行**，不能只用 `ItemSparse`。
- 属性以 wow-forever.gg 的 Forever 值为准；TFE 只用在 `fb=0` 的行上。
- 删物品之前先抽查 2-3 件到 wow-forever.gg 看有没有拍卖记录 —— 有挂单就是活物品。
