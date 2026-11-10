# wow-forever-addons

《魔兽世界：无限》（WoW Forever / 1.60.1 / Interface 16001）自用插件集合。

## 插件

| 目录 | 名称 | 作用 | 状态 |
|---|---|---|---|
| `BlackEvidence/` | **BlackEvidence** | 黑名单、进队预警、拉黑瞬间证据快照（时间线 + 截图） | 可用 |
| `ProfitBoard/` | **ProfitBoard** | 全量扫拍卖行、按「规则集 × 阵营」建价格库、全专业配方利润统计 | 待客户端校准 |
| `ProfitProbe/` | **ProfitProbe** | 开发用探针：dump AH / 专业 / 物品 API 能力，不随插件发布 | 开发工具 |

命名约定：插件目录名 = TOC 文件名 = 斜杠命令前缀来源。
`ProfitProbe` 是诊断工具，正式安装只需 `BlackEvidence` 与 `ProfitBoard`。

## 安装

把需要的插件目录整个复制到：

```
<游戏目录>\_forever_\Interface\AddOns\<插件名>
```

确认 `AddOns\<插件名>\<插件名>.toc` 直接存在，重启客户端后在角色选择界面启用。

## 开发

```bash
# ProfitBoard 单测（Python + lupa，无需安装 Lua）
python tests/run_pb.py

# 全部 Lua 文件语法检查
python tests/syntax_check.py

# BlackEvidence 冒烟测试
python tests/run_be.py
```

生成的静态配方表：

```bash
python tools/gen_static_recipes.py recipes.json --out ProfitBoard/StaticRecipes.lua
```

## 文档

- **`docs/DEVELOPMENT.md`** —— 开发文档：架构、模块契约、算法、探针校准手册、调试手册、续作清单（**接手先读这个**）
- `ProfitBoard/README.md` —— 安装、命令、限制
- `BlackEvidence/README.md` —— 插件说明
- `docs/BlackEvidence-实施方案.md` —— 黑名单插件规格
- `docs/superpowers/specs/2026-11-10-profitboard-design.md` —— ProfitBoard 设计
- `docs/superpowers/plans/2026-11-10-profitboard.md` —— ProfitBoard 实施计划

## 说明

- 全部插件为只读/提示类功能，不含自动买卖、自动施法、自动移动等自动化行为。
- 面向 Interface 16001（`## AllowLoadGameType: forever`），不保证在正式服/经典服可用。
