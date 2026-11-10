# ProfitBoard

《魔兽世界：无限》（WoW Forever，Interface 16001）的全配方利润统计插件。
扫拍卖行 → 本地价格库 → 全专业配方逐条算「材料成本 vs 成品价」→ 中文可排序表格。

只做统计，不自动买卖、不上架、不发送聊天消息。

## 安装

把 `ProfitBoard` 整个文件夹放进：

```
<游戏目录>\_forever_\Interface\AddOns\ProfitBoard
```

确认 `AddOns\ProfitBoard\ProfitBoard.toc` 直接存在（不要再套一层 `ProfitBoard\ProfitBoard`）。
重启客户端，在角色选择界面确认插件已启用。

## 首次使用

1. 打开拍卖行，输入 `/pb scan`，等「扫描完成」。
2. `/pb` 打开表格。
3. 看「利润」列，点表头可换排序，点行可在聊天框看材料明细。

## 命令

```
/pb                       打开/关闭窗口
/pb scan                  全量扫描拍卖行（15 分钟一次）
/pb top [n]               控制台打印利润前 n 条
/pb price <物品ID>        查单个物品价格与 7 日中位
/pb filter profit 10000   利润 ≥ 1 金
/pb filter margin 30      利润率 ≥ 30%
/pb filter listings 10    成品挂单 ≤ 10
/pb filter learned 1      只看已学配方
/pb filter missing 0      隐藏缺价配方
/pb export                导出 CSV（可复制）
/pb import <文本>         从快照文本恢复价格库
/pb status                客户端能力、市场、价格库与配方规模
/pb reset market|config|all
```

## 数据来源与限制

- 价格只来自**你自己的**全量扫描，没有云端共享。全扫受服务端限制约 15 分钟一次。
- 市场按「规则集 × 阵营」隔离（普通 / PvP / RP / 专家 × 联盟 / 部落），跨规则集不能套用。
- 配方优先从客户端枚举（含未学配方，取决于客户端 API）；不可用时读 `StaticRecipes.lua`。
- **利润 ≠ 卖得掉**：游戏不提供成交速度，挂单数只是竞争度参考。
- 利润只扣 5% 拍卖行抽成，不含上架保管费（该规则未在无限服验证）。
- 任一材料缺价时该配方标「缺价」，不参与排名，不做估算。

## 静态配方库（可选）

若 `/pb status` 显示配方条数为 0，说明客户端无法枚举配方，需要生成静态表：

```bash
python tools/gen_static_recipes.py recipes.json --out ProfitBoard/StaticRecipes.lua
```

输入格式见 `tools/gen_static_recipes.py` 顶部注释（JSON 或 CSV）。
生成后重启客户端，`/pb status` 应显示配方条数与静态表版本。

## 开发与测试

```bash
python tests/run_pb.py       # 单测（lupa，无需安装 Lua）
python tests/syntax_check.py # 全部 Lua 文件语法检查
```

设计文档：`docs/superpowers/specs/2026-11-10-profitboard-design.md`
实施计划：`docs/superpowers/plans/2026-11-10-profitboard.md`

## 已知未完成

- 探针（`ProfitProbe`）尚未在真实无限客户端跑过，`Market.REPLICATE_FIELDS` 与 `Profile.SELL_PRICE_INDEX` 仍是零售默认值，需要按探针报告校准。
- 静态配方表尚未生成。
