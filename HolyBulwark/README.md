# 圣光壁垒 · HolyBulwark

给 **WoW Forever（魔兽世界：永久，`_forever_` 客户端，Interface 16001）** 用的防护骑士法伤装备库。

它回答四个问题：

1. 10-60 级有哪些**骑士能穿、带法术强度**的装备？
2. 每件装备的**完整属性**是什么？
3. 它**从哪来**（掉落 / 任务 / 商人 / 制造 / 宝箱 / 世界掉落）？
4. 任务怎么接、整条任务链是什么、NPC 在哪、怎么在地图上标出来？

## 安装

把 `HolyBulwark` 整个文件夹放到：

```
D:\game\World of Warcraft\_forever_\Interface\AddOns\HolyBulwark
```

重启游戏或 `/reload`。

## 使用

| 命令 / 入口 | 作用 |
| --- | --- |
| 小地图图标 | 左键打开/关闭，拖动调整位置 |
| `/hb`、`/spg`、`/法伤骑`、`/fsq` | 打开/关闭窗口 |
| `/spg 21610` | 在聊天框打印物品属性与来源 |
| `/spg 虫鳞` | 打开窗口并搜索 |
| `/spg diag` | 数据库/筛选诊断 |

功能：

- 搜索名称、物品 ID、英文名、来源名
- 列表列：名称、需要等级、物品等级、属性、来源；来源用彩色标签，多来源显示 `+N`
- 按 **部位 / 护甲 / 来源 / 品质 / 等级 / 排序** 筛选；多选菜单使用标准勾选框
- 等级范围修改后点“查询”或按回车才应用，避免输入过程中列表闪空
- 默认视图：**防骑向（板/锁/盾+首饰）、有耐力、有来源**，当前版本可获取 303 件（另有 9 件纳克萨玛斯装备默认隐藏）
- 列表右侧来源标签分色：掉=红、任=金、售=绿、制=蓝、箱=紫、容=青、世=灰
- 详情显示完整属性、护甲、武器伤害、绑定、来源
- **商人**：中文名 + 区域 + 坐标 + 备注
- **制造**：配方物品 + 贩卖图纸的 NPC 中文名、区域、坐标 + “标出”快捷链接
- **来源阅读**：任务装备按“任务 / 接取 / 交付 / 任务链”分段；制造装备按“制造 / 配方 / 图纸商人”分段
- **任务**：中文任务名、接取/交付 NPC、区域、坐标、**整条任务链**
- **任务链状态**：每一步标记 `[完成] / [当前] / [下一步] / 未接`，并标出本物品任务
- **任务详情**：任务描述/目标、任务品、击杀目标、任务对象、任务品位置与掉落人物
- **任务链可点击**：点任务名查看详情；点 NPC、任务品位置、任务对象、掉落人物直接在地图标点
- **物品触发任务**：起始物品 + 掉落人物列表（可点击标图）
- **地图标记**：打开对应地图并显示醒目的地图钉；世界地图始终在插件窗口上方
- **全中文**：物品英文名、英文区域名不再显示；NPC/物品/任务名优先使用客户端中文数据
- **Ctrl+左键**列表物品打开试穿；**Shift+左键**插入可点击物品链接到聊天框
- 物品没有物品等级时，显示**任务等级**
- 鼠标悬停任意物品（含聊天链接）自动追加来源

## 数据来源

| 内容 | 来源 |
| --- | --- |
| 物品属性、护甲、掉率、来源、任务 ID | [The Forever Era](https://theforeverera.com)（1.60.1.70959） |
| 中文物品名 | WoW Forever 中文客户端 `ItemSparse` |
| 区域中文名 / 地图 ID | 客户端 `AreaTable`、QuestieDB Forever 映射 |
| 任务中文名 | [forever.damijing.com](https://forever.damijing.com)（410 个任务） |
| 任务链、接取 NPC、坐标 | [WarcraftMaps](https://warcraftmaps.com) |
| 完整任务链、任务品位置、掉落怪物 | Completao（本地安装的 Forever 任务库） |
| BOSS / 任务 NPC / 商人中文名 | forever.damijing.com（478 个 NPC） |
| 图纸贩卖 NPC、区域、坐标 | [WoW Forever](https://wow-forever.gg) 物品页 |
| 首领刷新点 | QuestieDB Forever 元数据 |
| BOSS 副本内位置 | 运行时可读取 DungeonQuestAtlas（本地已安装） 的 `Maps.pins` |
| 交叉核对 | [Bind on Forever](https://bindonforever.com)、Completao（本地已安装） |

数据构建日期：2026-11-22。

## 本地数据库

插件不依赖在线接口，运行时只用本地 Lua 数据：

| 文件 | 内容 |
| --- | --- |
| `Data.lua` | 2047 件装备（中文名、属性、来源、任务等级） |
| `MapIds.lua` | AreaID→UiMapID、区域中文名→UiMapID |
| `NpcZh.lua` | 478 个 BOSS/任务 NPC 中文名 |
| `NpcLoc.lua` | 世界首领刷新坐标 |
| `QuestZh.lua` | 410 个任务中文名 |
| `QuestInfo.lua` | 任务等级、接取 NPC、坐标、任务链 |
| `QuestFull.lua` | 从 Completao 提取的 556 个任务：接取/交付地点、任务品步骤、掉落怪物、前置关系 |
| `RecipeVendor.lua` | 图纸/配方贩卖 NPC、区域、坐标 |

QuestieDB 是可选增强：装了可以补全更多 NPC/任务中文名与位置；没装也能用本地库。

## 重新生成

所有脚本在 `tools/`，默认数据目录 `data/`（不提交到 Git）：

```powershell
# 1. 下载客户端表 + TFE 物品数据
powershell -File tools\fetch_data.ps1

# 2. 生成 Data.lua + CSV
powershell -File tools\build_data.ps1

# 3. 中文名 / 位置 / 任务库
powershell -File tools\build_npc_index.ps1
powershell -File tools\fetch_npc_zh.ps1
powershell -File tools\fetch_npc_zh_missing.ps1
powershell -File tools\fetch_npc_zh_givers.ps1
powershell -File tools\make_npc_zh.ps1
powershell -File tools\build_npc_loc.ps1
powershell -File tools\fetch_quest_zh.ps1
powershell -File tools\fetch_quest_zh_chain.ps1
powershell -File tools\make_quest_zh.ps1
powershell -File tools\fetch_quest_info.ps1
powershell -File tools\fetch_quest_info_chain.ps1
powershell -File tools\make_quest_info.ps1
powershell -File tools\make_map_ids.ps1

# 4. 人类可读清单
powershell -File tools\make_report.ps1
```

脚本里的绝对路径按当前工作区写死，换机器时改一下开头的 `$dataDir` / `$outDir`。

## 目录

```
holy-bulwark/
├─ HolyBulwark/            # 插件本体
│  ├─ HolyBulwark.toc
│  ├─ Data.lua
│  ├─ MapIds.lua
│  ├─ NpcZh.lua
│  ├─ NpcLoc.lua
│  ├─ QuestZh.lua
│  ├─ QuestInfo.lua
│  ├─ QuestFull.lua
│  ├─ RecipeVendor.lua
│  ├─ Core.lua
│  ├─ Tooltip.lua
│  └─ UI.lua
├─ tools/                  # 抓取与生成脚本
├─ docs/
│  └─ 装备清单.md           # 312 件坦克向清单
├─ LICENSE
└─ README.md
```

## 已知限制

- 副本 BOSS 如果没有世界刷新坐标，会打开副本地图但不放精确点；装了 DungeonQuestAtlas 时会读取它的 `Maps.pins` 精确标记。
- 少数配方在公开数据库里完全没有来源记录，会显示“暂无可靠数据”；经典配方会自动读取 QuestieDB 的商人列表兜底。
- Forever 新增 NPC 的官方中文名通常不存在，插件使用 damijing 译名或音译名；坐标以 Wow Forever 数据为准。
- 商人中文名是译名；PvP 军需官坐标为近似值。
- 数据以 1.60.1.70959 快照为准，客户端更新后可能有细微差异，以游戏内 tooltip 为准。

## 致谢

- [The Forever Era](https://theforeverera.com)
- [WoW Forever](https://wow-forever.gg)
- [WarcraftMaps](https://warcraftmaps.com)
- [forever.damijing.com](https://forever.damijing.com)
- [Bind on Forever](https://bindonforever.com)
- QuestieDB / Questie
- DungeonQuestAtlas、Completao

## License

代码 MIT；游戏数据与名称归 Blizzard Entertainment 及上述数据站点所有。
