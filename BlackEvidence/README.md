# BlackEvidence

黑名单 + 进队预警 + 证据快照。同一份代码支持 **正式服 / 经典时光服 / 无限服（Forever）**，按客户端能力自动切换。

> 当前版本 0.1.0。Forever 尚未上线，先在正式服与时光服实测；无限服相关分支已按 Interface 16001 的 API 写好，等开服后验证。

## 1. 安装

把整个 `BlackEvidence` 文件夹放到对应客户端的 AddOns 目录：

| 客户端 | 目录 | 加载的 TOC |
|---|---|---|
| 正式服（12.x） | `_retail_\Interface\AddOns\` | `BlackEvidence_Mainline.toc`（120000） |
| 经典旧世（1.15.x） | `_classic_era_\Interface\AddOns\` | `BlackEvidence_Vanilla.toc`（11507） |
| 燃烧的远征 | `_classic_\Interface\AddOns\` | `BlackEvidence_TBC.toc`（20504） |
| 巫妖王之怒 | `_classic_\Interface\AddOns\` | `BlackEvidence_Wrath.toc`（30403） |
| 大灾变 | `_classic_\Interface\AddOns\` | `BlackEvidence_Cata.toc`（40402） |
| 熊猫人之谜 | `_classic_\Interface\AddOns\` | `BlackEvidence_Mists.toc`（50500） |
| 无限服（1.60.1） | `_classic_beta_\Interface\AddOns\` | `BlackEvidence_Camelot.toc`（16001） |

TOC 里的 `## Interface:` 如果和当前客户端不一致，插件列表会显示"已过期"——勾选"加载过期插件"仍可使用；也可以把数字改成 `/dump select(4, GetBuildInfo())` 的第 4 个返回值。

## 2. 第一次自检（三分钟）

```
/be status      -- 看客户端识别、每个关键 API 是否存在、模块是否加载
/be test        -- 非破坏性自检
/be menu        -- 右键菜单走的是哪条路、注入/展开/点击计数
```

正常应看到：`profile=retail/classic/forever`、`menu=modern/legacy`、`name=realm/surname`。

然后：右键任意玩家 → 「加入黑名单」→ 写备注 → 保存 → 检查：
- 屏幕上是否出现一条本地提示；
- `/be evidence` 是否出现一条记录（ID 形如 `BE-20261026-213045-0-1`）；
- `Screenshots` 目录里是否多了一张截图；
- `/reload` 后 `/be` 里黑名单是否还在。

## 3. 命令

| 命令 | 作用 |
|---|---|
| `/be` | 打开管理页（黑名单 / 快照 / 设置） |
| `/be add <名字> [备注]` | 手动加入（支持 `"Asha Brightvale"` 这种带空格的全名） |
| `/be del <名字>` / `/be note <名字> <备注>` | 删除 / 改备注 |
| `/be list` / `/be search <关键字>` | 列表 / 搜索 |
| `/be export` / `/be import` | 导出到可复制窗口 / 粘贴导入 |
| `/be pack [id]` | 生成证据包文本 |
| `/be scan` / `/be warn <名字> [send]` / `/be queue` / `/be flush` | 队伍扫描 / 模拟预警 / 查看队列 / 补发 |
| `/be status` / `/be test` / `/be diag` / `/be menu` | 状态 / 自检 / 诊断包 / 菜单实况 |
| `/be time [n]` / `/be evidence [n|id]` | 时间线 / 证据 |
| `/be ignore <名字>` / `/be unignore <名字>` | 本场豁免（只对当前会话生效） |
| `/be mark <说明>` | 日志锚点 |
| `/be log <级别>` / `log dump` / `log since <锚点>` / `log session` / `log trace on` | 日志 |
| `/be screenshot` | 立刻截一张图（验证截图链路） |

## 4. 多版本数据隔离

黑名单按 profile 分仓存放：

```
BlackEvidenceDB.profiles.retail.blacklist
BlackEvidenceDB.profiles.classic.blacklist
BlackEvidenceDB.profiles.forever.blacklist
```

正式服的条目不会在时光服触发（反之亦然）。跨版本搬运用 `/be export` → `/be import`，导入窗口里可选"只进当前版本"或"合并到全部版本"。

身份键规则：
- 正式服 / 经典：`名字-服务器`（取不到服务器时只用名字）；
- 无限服：`名字 + 引擎分隔符 + 姓`（`Constants.CharacterNameSeparatorConsts`）；
- GUID 只作辅助索引（`UnitGUID` 在 secret 状态下可能为 nil）。

## 5. 录像助手（可选）

没有录像助手时插件也完整可用：截图 + 时间线 + 证据包照常。

有录像助手时（`recorder/`）：

1. 装 `ffmpeg`（PATH 里，或在 `config.ini` 写全路径）；
2. 编辑 `recorder/config.ini`，**必须**填 `paths.wow_root`（正式服填到 `World of Warcraft` 根目录，程序会自己找 `_retail_` / `_classic_era_` / `_classic_beta_`）；
3. 双击 `启动录像助手.bat`，窗口最小化即可。

一次触发产出：`capture.*`、`replay.mp4`（默认最近 150 秒）、`chatlog_tail.txt`、`loot_and_rolls.txt`、`note.txt`、`meta.json`，索引写入 `index.jsonl`。

需要的设置：
- 游戏内 `/chatlog` 开着（插件默认登录时自动开）；
- `video_seconds` 默认 150，可改回 300。

## 6. 已知限制

- **副本战斗锁定期**：聊天文本是 secret value，时间线里只记 `[受限内容]`；掉落/ROLL 的可靠来源是 `C_LootHistory`。
- **CLEU 不可用**：12.x 注册 `COMBAT_LOG_EVENT_UNFILTERED` 会触发 `ADDON_ACTION_FORBIDDEN`，本插件不注册。
- **SavedVariables 只在 `/reload` 或退出时落盘**：崩溃会丢最后一次修改。
- **录像只能靠外部程序**：插件不能录屏、不能写文件、不能启动外部进程。
- **备注不会发到频道**：频道消息永远不包含备注内容。

## 7. 文件结构

```
BlackEvidence/
├─ BlackEvidence.toc / _Mainline / _Vanilla / _TBC / _Wrath / _Cata / _Mists / _Camelot
├─ Core.lua        初始化、事件总线、DB 备份
├─ Profile.lua     三客户端能力探测
├─ Config.lua      默认配置与迁移
├─ Logger.lua      分级日志、锚点、报错捕获
├─ Util.lua        UTF-8 / 物品链接 / 安全调用
├─ Identity.lua    名字与身份键（realm / surname 两种模型）
├─ Blacklist.lua   按 profile 分仓的增删改查
├─ Timeline.lua    180 秒聊天/掉落/ROLL 环形缓冲
├─ Trigger.lua     证据快照 + 截图调度
├─ Comms.lua       进队扫描、预警、lockdown 队列
├─ Export.lua      导出/导入/证据包
├─ NoteDialog.lua  多行备注框
├─ ManagerUI.lua   管理页（黑名单/快照/设置）
├─ Menu.lua        右键菜单（modern + legacy 双路径）
├─ Slash.lua       /be 命令
├─ CONTRACT.md     模块契约
└─ recorder/       外部录像助手（Python + ffmpeg）
```

## 8. 测试清单（正式服 / 时光服）

1. `/be status`：profile、menu、name 三项与实际客户端一致。
2. 右键队友/目标 → 加入黑名单 → 备注能保存 → 管理页能看到。
3. `/reload` 后仍在；完全退出重登后仍在。
4. 同名不同人：两个角色分别加，互不覆盖（正式服看服务器，无限服看姓）。
5. 换一个小号进队（需要第二个账号）→ 只告警一次；离队再进 → 再次告警。
6. 设置里打开"发到队伍频道" → 队友能看到中性提示，且不含备注。
7. `/be export` → 复制 → `/be import` 粘贴 → 数量对得上。
8. `/be evidence` 有记录，`/be pack` 文本包含 ID/时间/目标/时间线。
9. 有录像助手时：拉黑后 `recorder/evidence/<时间戳>_<截图名>/` 下出现 6 个文件。

出问题请发：`/be diag` 的输出 + `recorder/evidence/_diagnostics/` 下的文件。
