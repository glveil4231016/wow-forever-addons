# BlackEvidence 模块契约（v0.1）

> 任何模块改动前先读本文件。所有路径相对 `BlackEvidence/`。
> 目标：同一份代码在 **正式服 / 经典时光服 / 无限服（Forever）** 三个 profile 下都能跑。

## 0. 基本约定

- 插件名 `BlackEvidence`，斜杠命令 `/be`、`/blackevidence`。
- SavedVariables：`BlackEvidenceDB`（配置+黑名单+备份）、`BlackEvidenceLog`（日志/锚点/诊断）、`BlackEvidenceSnapshots`（证据）。
- 每个文件头：`local ADDON, BE = ...`，**不得**创建其它全局变量（除 ADDON 本身）。
- 所有可选 API 一律 `pcall` + 存在性判断，缺失就降级并写日志，**绝不报错**。
- 不注册 `COMBAT_LOG_EVENT_UNFILTERED`（12.x 会 `ADDON_ACTION_FORBIDDEN`）。
- 不把 secret value 写进 SavedVariables。
- 中文/UTF-8 一律用 `BE.Util` 的 UTF-8 安全函数，禁止 `strsub` 截断。

## 1. Profile（能力探测）

`profile = "retail" | "classic" | "forever"`，由 `Profile.lua` 在 `ADDON_LOADED` 时确定。

| 能力键 | 说明 | retail | classic | forever |
|---|---|---|---|---|
| `modernMenu` | `type(Menu.ModifyMenu)=="function"` | ✅ | ❌ | ✅ |
| `surname` | 姓名第二段是姓（`RegionalUniqueNamesEnabled()` / `Constants.CharacterNameSeparatorConsts`） | ❌ | ❌ | ✅ |
| `sendChat` | `"nameless"`=C_ChatInfo.SendChatMessage / `"global"`=SendChatMessage | C_ChatInfo | global | C_ChatInfo |
| `lootHistory` | `type(C_LootHistory)=="table"` | ✅ | ❌ | ✅ |
| `rollItemAPI` | `C_TooltipInfo.GetLootRollItem` 存在 | ✅ | ❌ | ✅ |
| `secret` | `issecretvalue` 存在 | ✅ | ❌ | ✅ |
| `lockdown` | `C_ChatInfo.InChatMessagingLockdown` 存在 | ✅ | ❌ | ✅ |
| `loggingChat` | `LoggingChat` 可调用 | ✅ | ✅ | ✅（待实测） |

```lua
BE.Profile = {
  id = "retail",            -- 当前
  caps = { ... },           -- 上表
  interface = 120000,       -- GetBuildInfo 第 4 位
  label = "正式服",          -- 显示名
  Detect = function() end,  -- 内部
}
```

**规则**：任何"按版本分叉"的代码只能读 `BE.Profile.caps`，**禁止**散落 `if WOW_PROJECT_ID == ...`。

## 2. 加载顺序（TOC 必须与此一致）

```
Core → Profile → Config → Logger → Util → Identity → Blacklist
→ Timeline → Trigger → Comms → Export → NoteDialog → ManagerUI → Menu → Slash
```

## 3. 模块 API

### Core
```lua
BE:Init()                       -- 各模块 Init 单独 pcall，失败不影响其它模块
BE:On(event, fn)                -- 事件总线（同名事件多监听）
BE:Fire(event, ...)             -- 内部
BE:RegisterEvent(event)         -- 幂等
BE:Debug(...)                   -- 等价 BE.Log.Debug("Core", ...)
```

### Profile
```lua
BE.Profile.Detect()             -- 仅 Core 调用一次
BE.Profile.Is("forever")        -- 布尔
BE.Profile.Cap(name)            -- 布尔/字符串
BE.Profile.StatusLine()         -- "/be status" 用的一行摘要
```

### Config
```lua
BE.Config.Defaults              -- 表
BE.Config:Load()                -- 补默认值 + 版本迁移 + clamp
BE.Config:Get(key) / :Set(key, v)
BE.Config:Reset()
```

### Logger
```lua
BE.Log.Debug(tag, fmt, ...) / Info / Warn / Error
BE.Log.Raw(level, tag, msg)     -- 已格式化
BE.Log.Mark(label)              -- 锚点，返回 seq
BE.Log.Dump(n) / DumpSince(anchor) / DumpSession()
BE.Log.CaptureStart() / CaptureStop()   -- 捕获某段日志用于诊断包
BE.Log.InstallErrorHandler()    -- 链式接管 seterrorhandler
BE.Log.Session                  -- 会话号（每次登录/reload +1）
```
- 环形缓冲默认 1000 条，`seq` 单调递增，**跨会话不清空**。
- `sessionFrom` 必须取 `seqCount + 1`（BlackBook 的 bug，别抄）。

### Util
```lua
BE.Util.SafeCall(fn, ...)                -- 返回 ok, ...
BE.Util.IsPlain(v)                       -- 非 secret 字符串
BE.Util.IsSecret(v)                      -- issecretvalue 的 pcall 包装
BE.Util.Utf8SafeEnd(s, n) / Utf8SafeStart(s, n) / Tail(s, n) / Truncate(s, n)
BE.Util.StripColors(s)
BE.Util.ParseItemLink(s)                 -- 返回 itemID, itemLink, itemName
BE.Util.ClientFlavorLabel()              -- 人读的客户端名
BE.Util.ApiLine(name)                    -- "✔ API" / "✘ 不存在"
```

### Identity（唯一身份入口）
```lua
BE.Identity.Unit(unit)   -- { name, surname, realm, full, key, guid } 或 nil
BE.Identity.Key(unit)    -- 归一化 key（小写）
BE.Identity.KeyFromParts(name, second)  -- second = realm(retail/classic) 或 surname(forever)
BE.Identity.Display(entry)              -- "Asha Brightvale" / "李四-测试服"
BE.Identity.Normalize(s)                -- trim + lower（仅 ASCII）
```
- `forever`：`key = name .. SEP .. surname`，`SEP = Constants...CHARACTERNAME_SURNAME_SEPARATOR`
- 其它：`key = name .. "-" .. realm`（realm 空则只用 name）
- 全部小写；`guid` 只作辅助索引，`UnitGUID` 为 nil 时不参与匹配。
- **禁止**在其它模块里自己拼名字。

### Blacklist（按 profile 分仓）
```lua
BE.Blacklist.Store()                     -- 当前 profile 的表
BE.Blacklist.Add(info, note)             -- 已存在则更新备注；返回 entry, isNew
BE.Blacklist.Update(key, note)
BE.Blacklist.Remove(key)                 -- 返回 bool
BE.Blacklist.Get(key) / FindByGUID(guid)
BE.Blacklist.Iterate()                   -- 稳定排序（createdAt desc）
BE.Blacklist.Search(q)                   -- 名字/姓/备注
BE.Blacklist.Hit(key)                    -- hits+1, lastSeen=now
BE.Blacklist.Count()
```

### Timeline（180s 环形 + secret 安全）
```lua
BE.Timeline.Start()
BE.Timeline.Push(t)        -- { kind, text, actor, guid, itemLink, roll, secret }
BE.Timeline.Mark(label)    -- 写入一条 kind="MARK"
BE.Timeline.Snapshot()     -- 返回当前窗口的深拷贝（数组）
BE.Timeline.Count()
```
- 用 **head 索引环形**，禁止 `table.remove(t,1)`。
- `BE.Util.IsSecret(text)` 为真 → `text="[受限内容]"`, `secret=true`，不解析、不入存档。
- 副本内 `C_ChatInfo.InChatMessagingLockdown()` 为真时，所有 CHAT_MSG 统一按 secret 处理。

### Trigger（证据）
```lua
BE.Trigger.Fire(reason, info, note)  -- 返回 record；内部顺序：Mark → Snapshot → Screenshot
BE.Trigger.List() / Get(id) / Remove(id) / Keep(n)
BE.Trigger.ScheduleScreenshot(delay)
```
- record.id = `BE-YYYYMMDD-HHMMSS-session-seq`，**不得**用 `seq % 100`。
- 每条最多 300 行时间线；最多保留 50 条（不是 300）。

### Comms（进队预警）
```lua
BE.Comms.Init()            -- 注册 GROUP_ROSTER_UPDATE / PLAYER_ENTERING_WORLD
BE.Comms.Scan(reason)      -- 0.4s 去抖；登录首扫 seed
BE.Comms.Warn(info)
BE.Comms.Queue / Flush()   -- 按 lockdown 排队，退锁补发
BE.Comms.Channel()         -- RAID / INSTANCE_CHAT / PARTY / 自定义
```
- 发送用 `caps.sendChat` 选择 `C_ChatInfo.SendChatMessage` 或全局 `SendChatMessage`。
- 排队条件：`caps.lockdown and C_ChatInfo.InChatMessagingLockdown()` 为真，**不是** combat。
- 发送必须校验返回（`pcall` 成功 ≠ 已发送），失败进队列。
- 频道文案不得包含备注。

### Menu（双路径）
```lua
BE.Menu.Init()             -- modern: Menu.ModifyMenu ×4；legacy: UnitPopupMenus
BE.Menu.ResolveUnit(menuId, ctx)  -- 统一拿到 unit/name/surname/realm
BE.Menu.Stats              -- { injected, expanded, clicked, lastTarget, mode }
BE.Menu.LiveReport()       -- "/be menu" 输出
```
- modern 路径：`MENU_UNIT_PLAYER / MENU_UNIT_TARGET / MENU_UNIT_PARTY / MENU_UNIT_RAID_PLAYER`。
- legacy 路径：只在 `not caps.modernMenu` 时执行；**forever/retail 永不进入**。
- 注入成功与否以"首次菜单构建被观测到"为准，不能只看 `pcall`。
- 点击回调里只做非受保护操作。

### UI
```lua
BE.UI.Open() / Close() / Toggle()
BE.UI.OpenNote(info, opts)     -- opts.onSave(note)
BE.UI.OpenSnapshot(id)
BE.UI.Refresh()
```
- 管理页三 Tab：黑名单 / 快照 / 设置；顶部显示当前 profile 与计数。
- 删除必须真正删除（`StaticPopup_Show` 的 `data` 参数别传错）。

### Export
```lua
BE.Export.List(profile)        -- 生成文本
BE.Export.Pack(id)             -- 证据包文本
BE.Export.Import(text, opts)   -- opts.profile = "current" | "all"
BE.Export.ShowList() / ShowImport()
```
- 格式 `#BE-LIST v2`，每条 `profile= / name= / surname= / realm= / guid= / note= ... ---`。
- 备注**不转义**，`note=` 到 `---` 全算原文；备注行恰好为 `---` 时拒绝导入。
- 导入：已存在只更新备注，保留 createdAt / hits。

### Slash
```
/be | /be help | /be add | /be del | /be note | /be list | /be search
/be export | /be import | /be pack <id>
/be scan | /be warn <名字> [send] | /be queue | /be flush
/be status | /be selftest | /be test | /be diag | /be menu | /be time [n]
/be evidence [n|id] | /be profile [retail|classic|forever]
/be log <级别> | /be log dump [n] | /be log since [锚点] | /be log session | /be log trace on|off | /be mark <说明>
```

## 4. 数据模型

```lua
BlackEvidenceDB = {
  version = 2,
  activeProfile = "retail",
  profiles = {
    retail  = { blacklist = {} },
    classic = { blacklist = {} },
    forever = { blacklist = {} },
  },
  settings = {
    enabled = true,
    warnOnPartyJoin = true,
    sendToPartyChat = false,     -- 默认关
    warnChannel = "auto",
    warnCooldown = 20,
    localAlert = true,
    localAlertSeconds = 8,
    autoChatLog = true,
    screenshotOnAdd = true,
    screenshotOnJoinWarn = false,
    screenshotDelay = 0.15,
    noteDialogDelay = 0.45,
    timelineSeconds = 180,
    timelineEntries = 800,
    timelineChars = 6000,
    snapshotKeep = 50,
    snapshotTimelineLines = 300,
    recordScope = "instance",   -- instance | all
    logLevel = "debug",
    logRingSize = 1000,
    verboseEvents = false,
  },
  backup = { at = 0, payload = "" },   -- 上一次启动的序列化快照（截断 200KB）
}
```

条目：
```lua
{ key, name, surname, realm, guid, note, source, hits, lastSeen, createdAt, updatedAt }
```

## 5. 从 BlackBook 移植映射

| 目标文件 | 来源 | 必须改 |
|---|---|---|
| `Logger.lua` | `BlackBook/Logger.lua` | 改名；`sessionFrom=seqCount+1`；`SafeToString` 判 secret；硬上限 |
| `Slash.lua` | `BlackBook/Slash.lua` | 改名 `/be`；`/be diag` 新增；各模块 pcall 独立 |
| `Export.lua` | `BlackBook/Export.lua` | 改名；加 `profile` 头；surname；导入可选 profile |
| `ManagerUI.lua` | `BlackBook/ManagerUI.lua` | 改名；加 profile 切换/计数；修删除确认；快照 Tab |
| `NoteDialog.lua` | `BlackBook/NoteDialog.lua` | 改名；目标名用 `BE.Identity.Display` |
| `Menu.lua` | `BlackBook/Menu.lua` | 保留双路径但按 caps 门控；legacy 只在 non-modern |
| `Comms.lua` | `BlackBook/Comms.lua` | lockdown 队列；`caps.sendChat`；校验发送 |
| `Timeline.lua` | `BlackBook/Timeline.lua` | secret 处理；head 环形；roll 用新 API |
| `Trigger.lua` | `BlackBook/Trigger.lua` | Mark 在 Snapshot 前；ID 新格式；上限 50/300 |
| `Util.lua` | `BlackBook/Util.lua` | 只保留 UTF-8/颜色/物品链接；身份函数全部重写 |
| `Config.lua` | `BlackBook/Config.lua` | 加 profile 字段、snapshotKeep 等 |
| `Core.lua` | `BlackBook/Core.lua` | 各模块 init 独立 pcall；先装错误处理器 |
| `Profile.lua` | 新写 | 能力探测 |
| `Identity.lua` | 新写 | 三 profile 身份 |
| `Blacklist.lua` | `BlackBook/Blacklist.lua` | 按 profile 分仓；GUID 索引；修 matchRealm 逻辑 |
| 录像助手 | `recorder/blackbook_recorder.py` | 见实施方案 §16.4 |

## 6. 禁止事项

1. 不注册 CLEU。
2. 不用全局 `SendChatMessage`（除 `caps.sendChat=="global"`）。
3. 不用 `GetLootRollItemInfo` / `GetLootRollItemLink`。
4. 不在 retail/forever 执行 legacy `UnitPopupMenus` 注入。
5. 不把 secret 文本写入 DB。
6. 不用 `table.remove(t,1)` 做环形。
7. 不把备注发到频道。
8. 不引入第三方库。
