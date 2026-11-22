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
- 按 **部位 / 护甲 / 来源 / 品质 / 等级 / 排序** 筛选
- 默认视图：**防骑向（板/锁/盾+首饰）、有耐力、有来源**，共 312 件
- 列表右侧来源字分色：掉=红、任=金、售=绿、制=蓝、箱=紫、容=青、世=灰
- 详情显示完整属性、护甲、武器伤害、绑定、来源
- **商人**：中文名 + 区域 + 坐标 + 备注
- **任务**：中文任务名、接取 NPC、区域、坐标、**整条任务链**（每步 NPC/区域）
- **物品触发任务**：起始物品 + 掉落怪物列表
- **地图标记**：打开对应地图，用 TomTom / 暴雪路径点标出位置；多个位置时弹菜单选择
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
| BOSS / 任务 NPC 中文名 | forever.damijing.com（478 个 NPC） |
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
- 部分 Forever 新增配方没有来源记录，会显示“训练师/专业供应商（数据库暂缺）”。
- 商人中文名是译名；PvP 军需官坐标为近似值。
- 数据以 1.60.1.70959 快照为准，客户端更新后可能有细微差异，以游戏内 tooltip 为准。

## 致谢

- [The Forever Era](https://theforeverera.com)
- [WarcraftMaps](https://warcraftmaps.com)
- [forever.damijing.com](https://forever.damijing.com)
- [Bind on Forever](https://bindonforever.com)
- QuestieDB / Questie
- DungeonQuestAtlas、Completao

## License

代码 MIT；游戏数据与名称归 Blizzard Entertainment 及上述数据站点所有。
