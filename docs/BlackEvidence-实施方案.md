# BlackEvidence 规格与实施方案

> 目标客户端：**《魔兽世界：无限》= World of Warcraft: Forever**
> 客户端 1.60.1 · Interface **16001** · flavor `_Camelot` · zhCN · **realmless（无服务器）**
> 本文档自包含：照做即可实现，不需要再查别的资料。所有"未验证"项在第 13 节有探针脚本，先在游戏里跑一遍。

---

## 0. 一句话结论

- 需求 1–4（右键添加、备注、进队告警、管理页）：**可做**。
- 需求 5 拆成三块：
  - 自动截图：**可做**（`Screenshot()`）。
  - 最近 3 分钟事件快照：**部分可做**（野外完整；副本战斗锁定期聊天是 secret value，只能落占位符；Roll 明细改用 `C_LootHistory` 事后补）。
  - 5 分钟视频：**插件做不到**，只能由 OBS Replay Buffer 保存；插件负责显示可识别的触发层 + 提示。
- 所有"做不到"的原因都是客户端沙盒，不是实现问题。

---

## 1. 环境事实（已核实，不要再按 3.3.5a / WLK 写）

| 项 | 值 | 说明 |
|---|---|---|
| 版本 | 1.60.1，构建 70xxx | `GetBuildInfo()` 第 4 个返回值 = 16001 |
| Interface | **16001** | TOC 必须写这个 |
| 安装路径 | `World of Warcraft\_classic_beta_\Interface\AddOns\BlackEvidence\` | 正式上线后可能改目录名，认 `_Camelot` flavor |
| TOC 文件名 | `BlackEvidence.toc`；flavor 专用可再加 `BlackEvidence_Camelot.toc` / `BlackEvidence_Forever.toc` | 70408+ 两种后缀都认 |
| 姓名 | `UnitName(unit)` 返回 **两个值：`name, surname`** | 第二段是**姓**，不是服务器名 |
| 服务器 | **无**（realmless） | `UnitFullName` 的第二个返回值同样是姓；没有 realm 可拼 |
| 聊天发送 | `C_ChatInfo.SendChatMessage(msg, chatType)` | `SendChatMessage` 自 11.2 起 deprecated |
| PARTY/RAID 发送 | **不需要硬件事件** | SAY/YELL/CHANNEL 在野外需要硬件事件，不要用 |
| 战斗日志 | **不可用** | 注册 `COMBAT_LOG_EVENT_UNFILTERED` 直接 `ADDON_ACTION_FORBIDDEN` |
| 副本内聊天 | 战斗/大秘境/PvP 锁定期为 **secret value** | 能显示、能拼接，不能比较/匹配/当 table key/转数字。**例外：`CHAT_MSG_LOOT` / `CHAT_MSG_MONEY` 在 16001 官方文档里没有这个守卫** |
| 截图 | `Screenshot()` 全局函数可用 | 无参数、无返回；默认存 jpg 到 `_classic_beta_\Screenshots` |

---

## 2. 硬边界（写代码前先接受，别浪费时间）

1. 插件**不能**启动/控制 OBS 或任何本机程序，不能发 HTTP/WS，不能读屏幕像素，不能录屏。
2. 插件**不能**写任意文件；唯一持久化是 SavedVariables，**只在 `/reload`、退出游戏、断线时落盘**。崩溃会丢最后一次修改。
3. 插件**只能记录加载之后**收到的事件；装插件/登录/重载之前的 3 分钟拿不回来。
4. 副本内战斗锁定期，聊天/掉落/Roll 的**正文不可解析**，快照里写 `[受限内容]`；不要试图写原文进 SavedVariables。
5. `UnitGUID` 对部分 secret unit token 会返回 `nil`，**不能当唯一主键**。
6. 官方客户端，禁止改客户端、读内存、自动操作游戏。本方案不涉及。

---

## 3. 目录与 TOC

```
BlackEvidence/
├─ BlackEvidence.toc
├─ Core.lua          DB 初始化/迁移、事件分发、工具函数、斜杠命令
├─ Identity.lua      ★ 两段姓名解析与主键生成（整个插件的地基）
├─ Blacklist.lua     黑名单 CRUD
├─ ContextMenu.lua   ★ 唯一放"版本相关 API"的地方：右键菜单注入
├─ PartyWatch.lua    队伍扫描 + 会话去重
├─ EventLog.lua      180s 环形日志 + 冻结快照
├─ UI.lua            备注弹窗 / 管理页 / 设置 / 触发层
└─ Export.lua        快照渲染为可复制文本
```

`BlackEvidence.toc`：

```toc
## Interface: 16001
## Title: BlackEvidence
## Notes: 黑名单与证据记录（WoW Forever）
## Author: you
## Version: 1.0.0
## SavedVariables: BlackEvidenceDB
## AllowLoadGameType: forever
## ExcludeLoadGameType: standard, classic
## X-Category: Interface Enhancements

Core.lua
Identity.lua
Blacklist.lua
ContextMenu.lua
PartyWatch.lua
EventLog.lua
Export.lua
UI.lua
```

要点：
- `AllowLoadGameType: forever` + `ExcludeLoadGameType: standard, classic` 保证只在 Forever 加载。
- `UI.lua` 放最后，它依赖前面所有模块。
- 不要用 `## LoadOnDemand`。

---

## 4. 数据模型

```lua
BlackEvidenceDB = {
    version = 1,

    -- 主键 = BE:NormKey(全名)（名 + SEP + 姓，再 strlower），见第 5 节
    blacklist = {
        [key] = {
            key        = key,            -- 必须是 NormKey（小写），不是显示名
            name       = "Asha",            -- 名
            surname    = "Brightvale",      -- 姓，可能 nil
            note       = "抢装备后退队",
            guid       = "Player-0000-0000A1B2C3D4",  -- 辅助字段，可能 nil
            createdAt  = 1760000000,        -- time()
            updatedAt  = 1760000000,
        },
    },

    settings = {
        enablePartyWarning = true,   -- 进队检测总开关
        sendToPartyChat    = false,  -- 是否真的发到队伍频道（默认关）
        warningChannel     = "auto", -- auto | PARTY | RAID | INSTANCE_CHAT
        eventRetention     = 180,    -- 秒
        maxEvents          = 1000,
        showTriggerOverlay = true,
        overlayDuration    = 8,      -- 秒
        snapshotLimit      = 20,
        replaySeconds      = 150,    -- 只用于提示文案，OBS 里自己设
        -- 记录范围：instance = 只在副本/团本内记录（默认，符合"只要副本数据"）
        recordScope        = "instance",   -- instance | all
        -- 长期存档（默认开，2 万条 ≈ 2–4 MB）
        persistArchive     = true,
        archiveMaxLines    = 20000,
        -- 登录时自动开启客户端聊天日志（写 Logs/WoWChatLog.txt）
        autoChatLog        = true,
    },

    -- 冻结快照，数组，最多 20 份（FIFO）
    snapshots = {
        {
            id       = "BE-20261023-201536-001",
            trigger  = "BLACKLIST_ADDED",  -- BLACKLIST_ADDED | BLACKLIST_JOINED | MANUAL
            at       = 1760000000,
            atText   = "2026-10-23 20:15:36",
            selfName = "Asha Brightvale",
            target   = { key = ..., name = ..., surname = ..., note = ... },
            party    = { { name="...", surname="...", class="WARRIOR", role="TANK" }, ... },
            events   = { { t=123.4, wall="20:13:22", type="CHAT_MSG_LOOT",
                           text="...", restricted=false, itemLink="|Hitem:...", roll=87 }, ... },
            screenshot = { predicted = "WoWScrnShot_102326_201536.jpg", ok = true },
            lootHistory = { ... },   -- 可选，见 7.7
        },
    },
}
```

- **环形日志不进 SavedVariables**，只放内存 `BE.state.ring`。
- 每份快照的事件最多保留 **300 条**，超出丢弃最旧的，避免存档膨胀。
- `version` 用于以后迁移。

---

## 5. 身份主键（最重要，别写错）

### 5.1 取名

```lua
-- Identity.lua
local SEP = (Constants
    and Constants.CharacterNameSeparatorConsts
    and Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR) or " "

local function rawName(unit)
    -- UnitNameUnmodified 与 UnitName 是同一个 C 函数，两个返回值
    local n, s = UnitNameUnmodified(unit)
    if not n or n == "" then return nil end
    return n, s
end

function BE:UnitKey(unit)
    local n, s = rawName(unit)
    if not n then return nil end
    if s and s ~= "" then return n .. SEP .. s, n, s end
    return n, n, nil
end

-- 所有写入 DB / 查找 / 去重表一律经过这一层
function BE:NormKey(key)
    return key and strlower(key) or nil
end
```

### 5.2 必须遵守的规则

| 规则 | 原因 |
|---|---|
| 用 `UnitNameUnmodified` 的**两个返回值** | 只取第一个 = 只认到"名"，就是"只识别到主 ID"的根因 |
| 用 `Constants...CHARACTERNAME_SURNAME_SEPARATOR` 拼接 | 引擎自定分隔符，**不是空格、不是连字符**，且版本间改过一次 |
| **不要** `strsplit(" ")` / `strmatch("^([^-]+)-")` | 姓可能含空格；按 `-` 切是 3.3.5 的老逻辑 |
| **不要**拼 realm | Forever 无服务器 |
| 匹配键 = `strlower(全名)` | 只影响 ASCII；中文无大小写，安全。显示时用原串 |
| **不要**用 `strsub`/`strlen` 截断 | UTF-8 按字节切会切坏中文/`·` |
| 不拿 `UnitGUID` 当主键 | secret token 下是 nil；只作辅助字段 |

### 5.3 解析已有全名字符串（聊天发送者等）

```lua
function BE:SplitFullName(full)
    if NameUtil and NameUtil.SplitPlayerNameIntoParts then
        local a, b = NameUtil.SplitPlayerNameIntoParts(full)
        if a then return a, b end
    end
    if SEP ~= "" then
        local a, b = strsplit(SEP, full, 2)
        if b then return a, b end
    end
    return full, nil
end
```

> 聊天事件里的发送者名（`arg2`）通常是完整"名 姓"，直接当 key 用前先过一遍 `BE:SplitFullName` 再重新拼；若解析失败就原样用，**不要丢字符**。

### 5.4 自检

- 目标叫 `Asha Brightvale` → 列表显示完整两段，key 正确。
- 同时存在 `Asha Brightvale` 和 `Asha Nightfall` → 两条独立记录，不串号。
- 中文名（如 `张三` + 姓 `李`）→ 正常显示、正常匹配。

---

## 6. 功能规格

### F1 右键菜单注入（ContextMenu.lua）

**Forever 的机制**：`UnitPopupMenus` 已经是"菜单对象注册表"（例如 `UnitPopupMenus["PLAYER"] = UnitPopupMenuPlayer`），**不是**按钮 key 的数组。老写法会破坏菜单。

```lua
local function InjectEntry(which)
    local mgr = UnitPopupManager
    if not mgr then return false end
    local menu = mgr:GetMenu(which)
    if not menu or menu.__beInjected then return false end

    local btn = CreateFromMixins(UnitPopupButtonMixin)  -- 见"待实测"
    function btn:GetText(ctx) return "加入黑名单" end
    function btn:CanShow(ctx)
        return ctx and ctx.unit
            and UnitIsPlayer(ctx.unit)
            and not UnitIsUnit(ctx.unit, "player")
    end
    function btn:OnClick(ctx)
        BE:PromptAddNote(ctx.unit, ctx.name, ctx.surname)
    end

    local orig = menu.GetEntries
    menu.GetEntries = function(self, ...)
        local entries = orig(self, ...)
        if entries then table.insert(entries, btn) end
        return entries
    end
    menu.__beInjected = true
    return true
end

local MENUS = { "PLAYER", "PARTY", "RAID_PLAYER", "TARGET", "FOCUS" }
```

加载时机：
1. `PLAYER_LOGIN` 先 `pcall(C_AddOns.LoadAddOn, "Blizzard_UnitPopupShared")`（若存在），再对 5 个菜单 `InjectEntry`。
2. 若注入失败（manager 还没建），退化为包一次 `UnitPopup_OpenMenu`，在真正打开前再注入。
3. **只在加载时注入，不要每帧/战斗中改。**

要点：
- 点击回调里只做非受保护的事（开自己窗口、读名字、写 DB、发频道）。**禁止** `TargetUnit`/`InviteUnit` 等受保护调用。
- 取被点击的人：`contextData.unit`（不是 `UIDROPDOWNMENU_INIT_MENU`，那个在单位菜单里已失效）。
- `contextData.name` / `contextData.surname` 已经拆好，优先用；没有就回退 `BE:UnitKey(ctx.unit)`。

### F2 备注弹窗（UI.lua）

- 自定义 Frame（`StaticPopup` 不支持多行）：宽 420，高 260，`SetFrameStrata("DIALOG")`。
- 标题：`加入黑名单`；副标题显示目标全名（只读）。
- 备注：多行 `EditBox`，`SetMultiLine(true)`、`SetMaxLetters(500)`、外包 `UIPanelScrollFrameTemplate`。
- 按钮：`保存` / `取消`；ESC 关闭；打开时 `EditBox:SetFocus()`。
- 保存逻辑：
  ```lua
  local key = BE:NormKey(BE:UnitKey(unit) or (name .. (surname and (SEP..surname) or "")))
  local rec = db.blacklist[key]
  if rec then rec.note = note; rec.updatedAt = time()
  else db.blacklist[key] = { key=key, name=name, surname=surname, note=note,
                             guid=UnitGUID(unit), createdAt=time(), updatedAt=time() } end
  ```
- 保存后依次执行：`BE:TakeScreenshot()` → `BE:FreezeSnapshot("BLACKLIST_ADDED", rec)` → `BE:ShowTrigger("BLACKLIST_ADDED", rec)`。

### F3 进队告警（PartyWatch.lua）

监听：`GROUP_ROSTER_UPDATE`、`PLAYER_ENTERING_WORLD`、`GROUP_LEFT`（若有）、`GROUP_FORMED`（若有）。旧事件名 `PARTY_MEMBERS_CHANGED` / `RAID_ROSTER_UPDATE` 一并注册，内部去抖。

扫描：
```lua
local function Scan()
    if not db.settings.enablePartyWarning then return end
    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do units[#units+1] = "raid"..i end
    elseif IsInGroup() then
        units[#units+1] = "player"
        for i = 1, 4 do if UnitExists("party"..i) then units[#units+1] = "party"..i end end
    else
        BE.state.warned = {}   -- 不在队伍：清会话去重表
        return
    end
    for _, u in ipairs(units) do
        local key = BE:NormKey(BE:UnitKey(u))
        if key and not BE.state.warned[key] then
            local rec = db.blacklist[key]
            if rec then
                BE.state.warned[key] = true
                BE:OnBlacklistedJoin(u, rec)
            end
        end
    end
end
-- 事件里：C_Timer.After(0.4, Scan)  -- 名单刷新有延迟
```

去重规则：
- `BE.state.warned` **只在内存**，不持久化。
- 离开队伍（不在任何 group）→ 清空；这样"离队再进队"会再次触发。
- 队伍名单刷新（换人但仍在队）→ **不清空**，已警告的不重复。

命中动作：
1. `BE:FreezeSnapshot("BLACKLIST_JOINED", rec)`
2. 本地警告：屏幕上方的红色条 + `PlaySound(SOUNDKIT.ALARM_CLOCK_WARNING_1)` + 聊天框黄字
3. 若 `settings.sendToPartyChat` 为真 → 发一次中性提示（见下）
4. `BE:ShowTrigger("BLACKLIST_JOINED", rec)`（至少 8 秒）

频道选择：
```lua
local function Channel()
    if db.settings.warningChannel ~= "auto" then return db.settings.warningChannel end
    if IsInRaid() then return "RAID" end
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInGroup() then return "PARTY" end
end
C_ChatInfo.SendChatMessage(msg, Channel())
```

约束：
- 文案**绝不能包含备注**：
  `警告：队伍中有我在 BlackEvidence 中标记过的玩家：<全名>。请自行留意。`
- 全局限流：两次发送间隔 ≥ 10 秒；同一次组队只发一次。
- 默认关闭；用户开启时先弹一次确认框（"会向队友公开提示，可能引起争执/被举报刷屏"）。

### F4 管理页（UI.lua）

- `/be`、`/blackevidence` 打开；小地图按钮可选。
- 尺寸 760×540，可拖动，`SetFrameStrata("DIALOG")`，`ESC` 关闭。
- 三个 Tab：

**黑名单**
- 顶部：搜索框（按名/姓/备注过滤，`strfind(..., true)` 或大小写不敏感）、`新增`、`刷新`。
- 列表列：名 / 姓 / 备注（截断） / 更新时间 / 操作（编辑、删除）。
- 用 `UIPanelScrollFrameTemplate` + 自建行（每行一个 Button），**不要**用 FauxScrollFrame（现代客户端推荐 ScrollBox；先用 ScrollFrame + 行池即可）。
- 新增：弹出和 F2 一样的弹窗，但多一个"名"输入框 + "姓"输入框（姓可空）。
- 删除：`StaticPopupDialogs["BE_CONFIRM_DELETE"]`，二次确认，显示目标全名。
- 编辑：直接复用备注弹窗。

**快照**
- 列出最近 20 份：ID / 触发原因 / 时间 / 目标。
- 选中后右侧多行只读 EditBox 显示完整文本（`SetFocus()` + `HighlightText()` 便于 Ctrl+A/Ctrl+C）。
- 按钮：`复制`（`HighlightText`）、`删除这份`、`清空全部`（二次确认）。

**设置**
- 进队检测开关、是否发队伍频道（带警告文案）、频道选择、事件保留秒数（60–600）、快照上限（5–50）、触发层开关与时长（5–20 秒）。
- 全部改动即时写 DB。

### F5 自动截图

```lua
function BE:TakeScreenshot()
    local ok = pcall(Screenshot)         -- 无参数、无返回
    local predicted = date("WoWScrnShot_%m%d%y_%H%M%S.jpg")
    return ok, predicted
end
```

- 客户端不会返回文件名，**用 `date()` 预测**，存进快照 `screenshot.predicted`，并标 `predicted=true`。
- 默认 jpg；若要 png，`SetCVar("screenshotFormat", "png")` 后再预测扩展名（设置里提供选项）。
- 截图和快照 ID 必须同一秒生成，方便对账。

### F6 环形事件日志（EventLog.lua）

监听事件（★ = 受 `SecretInChatMessagingLockdown` 守卫，副本锁定期文本不可读）：

```
★ CHAT_MSG_SAY / YELL / PARTY / PARTY_LEADER / RAID / RAID_LEADER
★ CHAT_MSG_INSTANCE_CHAT / INSTANCE_CHAT_LEADER / WHISPER / SYSTEM
★ CHAT_MSG_MONSTER_SAY/YELL/EMOTE/PARTY/WHISPER / RAID_BOSS_EMOTE
  CHAT_MSG_LOOT / CHAT_MSG_MONEY          -- 16001 官方文档：无守卫
  ENCOUNTER_LOOT_RECEIVED                 -- encounterID, itemID, itemLink, quantity, itemName, fileName（无玩家字段）
  START_LOOT_ROLL                         -- rollID, rollTime, lootHandle（无点数、无赢家）
  CANCEL_LOOT_ROLL                        -- rollID
  CONFIRM_LOOT_ROLL                       -- rollID, rollType, confirmReason
  LOOT_ROLLS_COMPLETE                     -- lootHandle
  LOOT_ITEM_ROLL_WON                      -- itemLink, rollQuantity, rollType, roll, upgraded（自己赢时有点数）
  LOOT_OPENED                             -- autoLoot, isFromItem
  LOOT_CLOSED
  LOOT_READY                              -- autoloot（可选）
  GROUP_ROSTER_UPDATE / PLAYER_ENTERING_WORLD
  LOOT_HISTORY_UPDATE_ENCOUNTER / UPDATE_DROP / ONE_HUNDRED_ROLL
```

### F6.1 数据可获取性矩阵（决定"能不能存完整"）

| 数据 | 野外/主城 | 副本战斗锁定期 | 可靠来源 |
|---|---|---|---|
| 队伍/团队/小队/密语/系统聊天 | ✅ 完整文本 | ❌ 插件读不到；✅ **客户端 `WoWChatLog.txt` 可保存原文** | `CHAT_MSG_*` / `LoggingChat`（见 7.9） |
| 装备掉落 / 分钱 | ✅ | ✅（16001 无守卫，仍需实测） | `CHAT_MSG_LOOT` / `CHAT_MSG_MONEY` |
| Roll 类型 / 点数 / 赢家 | ⚠️ 只能解析文本 | ❌ 文本读不到 | **`C_LootHistory`** |
| 谁拾取了什么 | ✅ | ✅ | `CHAT_MSG_LOOT` + `C_LootHistory.winner` |
| 自己获得的物品 | ✅ | ✅ | `ENCOUNTER_LOOT_RECEIVED`（**无玩家字段**） |
| 回读聊天框历史 | ⚠️ 仅 128 行左右、无时间戳 | ⚠️ 同上且可能 secret | `GetMessageInfo`（不可靠，不用） |

**结论**：想"完整存档"，只有 `C_LootHistory` 能补上副本内的 Roll/归属；聊天正文在副本锁定期必须靠截图/视频（像素不受 secret 限制）。

每条记录：

```lua
{ t = GetTime(), wall = date("%H:%M:%S"), type = "CHAT_MSG_LOOT",
  text = <原文或占位>, restricted = false,
  actor = nil, itemLink = nil, roll = nil }
```

规则：
1. 追加后，删除 `t < GetTime() - 180` 的条目；总数上限 1000。
2. **secret 处理**（关键）：
   ```lua
   local function IsSecret(v)
       if type(issecretvalue) ~= "function" then return false end
       local ok, res = pcall(issecretvalue, v)
       return ok and res == true
   end
   ```
   若 `IsSecret(text)` → `text = "[受限内容]"`, `restricted = true`，**跳过一切解析**，也**不写进 SavedVariables**（快照里保留占位）。
3. 解析只在 `restricted == false` 时做，且**失败不丢原文**：
   - 物品链接：`text:match("(|c%x+|Hitem:[^|]+|h%[[^%]]+%]|h|r)")`
   - 数字：仅在需要时 `tonumber`
   - 角色名：`BE:SplitFullName` 后再拼 key
   - 发送者：`CHAT_MSG_*` 共 18 个参数，**第 2 个是完整两段名，第 12 个是 guid**（`select(12, ...)`）→ guid 可作辅助键
4. 环形日志留内存，**不持久化**。
5. `CHAT_MSG_SAY/YELL` 只记录、不解析，避免噪音。

### F7 冻结快照

触发点：`BLACKLIST_ADDED`、`BLACKLIST_JOINED`、管理页手动。

流程：
1. 生成 ID：`("BE-%s-%03d"):format(date("%Y%m%d-%H%M%S"), seq)`，`seq` 每秒从 1 递增，保证同秒唯一。
2. 拷贝当前环形日志**最近 180 秒、最多 300 条**（深拷贝，之后环形继续滚动不影响快照）。
3. 拷贝当前队伍成员（名/姓/职业/职责）。
4. `TakeScreenshot()` → 记录预测文件名。
5. 可选：抓 `C_LootHistory`（见 7.7）。
6. 写入 `db.snapshots`，超过 `snapshotLimit` 时 `table.remove(db.snapshots, 1)`。
7. 提示"快照已生成（ID: …）；如需长期保存，请 `/reload` 让存档落盘"。

### F8 触发层（Overlay）

- Frame：`SetFrameStrata("TOOLTIP")`，`EnableMouse(false)`，锚 `TOP`，`y = -120`，宽 560。
- 视觉：纯黑 85% 背景 + 2px 亮黄边框；标题 32px 黄色；正文 16px 白色；等宽字体优先。
- 内容（ASCII 标记必须逐字符固定，供后续 OCR/模板匹配）：

```
BE_TRIGGER
ID: BE-20261023-201536-001
REASON: BLACKLIST_ADDED
TARGET: Asha Brightvale
TIME: 2026-10-23 20:15:36
请按 OBS 热键保存回放（150 秒）
```

- 显示 `settings.overlayDuration` 秒（默认 8），带淡出；出现时 `PlaySound(SOUNDKIT.ALARM_CLOCK_WARNING_1)`。
- 不拦截鼠标、不抢焦点、不显示备注。
- 提供 `/be trigger` 测试命令（手动弹一次），用于调 OBS 和 Python。

### F9 OBS 手动流程

按你确认的 **150 秒**：

| 项 | 值 |
|---|---|
| 输出分辨率 | 1920×1080 |
| FPS | 15 |
| 即时回放长度 | **150 秒** |
| 容器 | MKV（防崩溃丢文件） |
| 编码优先级 | AV1 → HEVC/H.265 → NVENC H.264 |
| 码率 | AV1/HEVC ≈ 3 Mbps；H.264 ≈ 4 Mbps |
| 预估体积 | ≈ 56 MB（3 Mbps）/ ≈ 75 MB（4 Mbps） |

验收方法：先录 10–20 秒样本，在 100% 尺寸暂停，确认聊天文字可读。不清楚就先调大游戏聊天字号/UI 缩放，再把码率提到 3.5–4 Mbps；**不要靠 60 FPS 解决**。

热键：OBS 设置 → 热键 → "保存即时回放"，绑一个和游戏不冲突的键（如 F9），并在插件设置里记住这个键名，方便提示文案一致。

### F10 Python 桌面助手（P4，可选）

独立程序，**不得由 Lua 启动**，不得注入游戏进程。

```
插件固定区域显示 BE_TRIGGER
   ↓ 每 0.5–1 秒截取该区域（约 560×160，位置固定）
模板匹配 "BE_TRIGGER"（首选）/ OCR（备用）
   ↓ 识别出 ID
ID 与上次不同 且 距上次 ≥ 30 秒
   ↓
obs-websocket 5.x：ws://127.0.0.1:4455 → SaveReplayBuffer
   ↓ 记录日志（时间 / ID / 成功或失败）
```

硬性要求：
1. 只截固定小区域，**禁止全屏分析**。
2. 1–2 次/秒足够。
3. 证据 ID 去重 + 30 秒冷却。
4. 只允许连 `127.0.0.1:4455`；密码从本地配置文件读，不硬编码、不上传。
5. OBS 未运行 / 未开即时回放 / 连接失败 → **必须明确报错**，禁止显示"已保存成功"。
6. 保留手动热键兜底。

参考依赖：`obs-websocket-py`、`mss`、`opencv-python`、`pytesseract`（或模板匹配免 OCR）。

---

## 7. 关键实现细节与陷阱

### 7.1 secret value 判定必须 pcall

`issecretvalue` 在不同构建上可能不存在或抛错，一律包 `pcall`，失败按"可读"处理。

更可靠的运行时开关：`C_ChatInfo.InChatMessagingLockdown()`（Forever 的 API 索引里存在）。返回 true 时，所有带守卫的聊天事件一律不要解析，直接落 `[受限内容]`。

### 7.2 不要用 `SendChatMessage`

11.2 起 deprecated。统一用 `C_ChatInfo.SendChatMessage`，并做 10 秒限流。

### 7.3 SavedVariables 的 beta 坑

- beta 曾出现"退出写了、重登不恢复"（69913 报告，约 70009 修复）。
- 必须实测：加一条黑名单 → `/reload` → 还在；→ 完全退出游戏 → 重登 → 还在。
- 若重登丢失：在 `PLAYER_LOGIN` 后延迟 1 秒把关键设置镜像到一个 CVar（`C_CVar.SetSavedValue`），DB 仍以 SavedVariables 为准，只做兜底。
- 不要在 `PLAYER_LOGOUT` 里做耗时操作。

### 7.4 中文字符串

- 所有匹配用 `strfind(s, pattern, 1, true)`（纯文本）避免模式字符问题。
- 需要大小写不敏感时先 `strlower`（只影响 ASCII）。
- 不要 `strsub` 截断中文；UI 截断用 FontString `SetWidth` + `SetWordWrap(false)`。

### 7.5 时间

- 环形日志用 `GetTime()`（浮点，单调）算窗口。
- 快照用 `date("%Y-%m-%d %H:%M:%S")` 存可读时间。
- 两者都存，别只存一个。

### 7.6 队伍/团队单位 token

- 团队：`raid1..raid40`，数量用 `GetNumGroupMembers()`。
- 小队：`player` + `party1..party4`。
- 副本小队：`IsInGroup(LE_PARTY_CATEGORY_INSTANCE)` 为真。
- 宠物/召唤物不在名单里，别扫。

### 7.7 C_LootHistory（Roll 明细的唯一可靠来源）

官方文档签名（12.1.5 / Forever 生成文档，`Environment = "All"`，**无 secret 谓词**）：

```lua
C_LootHistory.GetAllEncounterInfos()                      -> EncounterLootInfo[]
C_LootHistory.GetInfoForEncounter(encounterID)            -> EncounterLootInfo?
C_LootHistory.GetLootHistoryTime()                        -> number
C_LootHistory.GetSortedDropsForEncounter(encounterID)     -> EncounterLootDropInfo[]?
C_LootHistory.GetSortedInfoForDrop(encounterID, lootListKey) -> EncounterLootDropInfo?
```

返回结构：

| 结构 | 字段 |
|---|---|
| `EncounterLootInfo` | `encounterName`, `encounterID`, `startTime`, `duration` |
| `EncounterLootDropInfo` | `lootListKey`, **`itemHyperlink`**, `playerRollState`, `currentLeader`, `isTied`, **`winner`**, `allPassed`, `rollInfos[]`, `startTime`, `duration` |
| `rollInfos[]` | `playerName`, `playerGUID`, `playerClass`, `isSelf`, `state`, **`isWinner`**, **`roll`**（可空） |
| `Enum.EncounterLootDropRollState` | `NeedMainSpec`, `NeedOffSpec`, `Transmog`, `Greed`, `NoRoll`, `Pass` |

```lua
local function GrabLootHistory()
    if type(C_LootHistory) ~= "table" then return nil end
    local ok, encs = pcall(C_LootHistory.GetAllEncounterInfos)
    if not ok or type(encs) ~= "table" then return nil end
    local out = {}
    for _, enc in ipairs(encs) do
        local e = { name = enc.encounterName, id = enc.encounterID,
                    startTime = enc.startTime, duration = enc.duration, drops = {} }
        local ok2, drops = pcall(C_LootHistory.GetSortedDropsForEncounter, enc.encounterID)
        if ok2 and type(drops) == "table" then
            for _, d in ipairs(drops) do
                local drop = { item = d.itemHyperlink, winner = d.winner,
                               rolls = {} }
                for _, r in ipairs(d.rollInfos or {}) do
                    drop.rolls[#drop.rolls+1] = {
                        name = r.playerName, class = r.playerClass,
                        state = r.state, roll = r.roll, winner = r.isWinner,
                    }
                end
                e.drops[#e.drops+1] = drop
            end
        end
        out[#out+1] = e
    end
    return out
end
```

坑（务必记牢）：
- **物品只有 `itemHyperlink`，没有 itemID** → 需要 ID 就自己从链接里 `match("item:(%d+)")`。
- **没有逐条 Roll 时间戳**，只有 drop 的 `startTime` / `duration`。
- **跨登出是否保留未验证** → 必须在 `LOOT_HISTORY_*` 事件里**增量复制进 SavedVariables**，不要等到拉黑时才读。
- **`GetLootRollItemInfo` / `GetLootRollItemLink` 在 Forever 里不存在**（已移除，别写）。看正在 roll 的物品用 `C_TooltipInfo.GetLootRollItem(rollID)`，看剩余时间用 `C_Loot.GetLootRollDuration(rollID)`。
- 三个取数函数都标了 `secretArguments: AllowedWhenUntainted` → **不要在 taint 上下文**（hook 过的安全按钮回调、受污染的事件处理）里调用。
- 拿不到就跳过，不要让快照失败。

### 7.8 性能

- 事件回调里不做字符串拼接大活；先原始入队，快照时再渲染。
- 队列超过上限直接丢最旧，不要动态扩容。
- UI 列表刷屏时用 `C_Timer.After(0.1, Refresh)` 合并。

---

### 7.9 客户端聊天日志（副本内聊天原文的唯一出路）

插件读不到副本内聊天，但**客户端自己在写日志**。12.x 仍然保留：

```lua
LoggingChat(true)                  -- 开启（等价于 /chatlog）
LoggingChat(false)                 -- 关闭
C_ChatInfo.IsLoggingChat()         -- 查询状态
```

- 文件：`_classic_beta_\Logs\WoWChatLog.txt`（**追加写，不覆盖**）。
- 行格式近似：`10/23 21:33:45.123  [Party] Asha Brightvale: 内容`。
- **关键**：写文件发生在 C++ 层、在消息交给 Lua 之前，所以 `SecretInChatMessagingLockdown` 理论上管不到它 → 副本内聊天原文**有可能完整落盘**。
- 开关**不持久**（每次启动复位），所以插件要在 `PLAYER_LOGIN` 里调 `LoggingChat(true)` 重新打开。
- 插件**读不了这个文件**（无 io），只能靠自己记录的时间戳/快照 ID 去和文件对账。

限制（必须写进用户提示）：
1. 日志在**退出游戏或 `/reload` 时**才完整落盘，崩溃可能丢最后一段。
2. 文件**无自动轮转/大小上限**，长期使用会很大，需要定期手动归档。
3. Roll 的"谁掷了多少点"**大概率不在**聊天日志里（那是 LOOT 窗口/系统串，不属于"聊天流"）→ 仍用 `C_LootHistory`。
4. 副本内是否真的写出 party/raid 行 —— **必须实测**（见第 13 节探针 11）。

实现建议：
- 设置项 `autoChatLog = true`，登录时 `pcall(LoggingChat, true)`，并在管理页设置里给出开关 + 提示"副本内聊天原文记录在 `Logs\WoWChatLog.txt`"。
- 快照里记录 `chatLogEnabled = C_ChatInfo.IsLoggingChat()`，方便事后判断这份证据有没有原文可对。

## 8. 证据快照文本格式（Export.lua）

```
=== BlackEvidence Snapshot ===
ID: BE-20261023-201536-001
Trigger: BLACKLIST_ADDED
Time: 2026-10-23 20:15:36
Player: Asha Brightvale
Target: Asha Brightvale
Note: 抢装备后退队
Screenshot: WoWScrnShot_102326_201536.jpg (predicted)

--- Party Members ---
1. Asha Brightvale (WARRIOR/TANK)
2. ...

--- Recent Events (180s) ---
[20:13:11] [LOOT] 某玩家获得了：[物品]
[20:13:22] [ROLL] [受限内容]
[20:13:25] [CHAT_PARTY] 某玩家：……

--- Loot History (C_LootHistory) ---
Encounter: ...
  - [物品] Need: 87 (Winner: A) / Greed: 45 ...
```

规则：
- `Note` **只本地展示**，任何自动发送的频道消息都不带备注。
- 原始系统文字尽量保留；`[受限内容]` 是唯一的替代写法。
- 渲染在管理页的多行 EditBox 里，可全选复制。

---

## 9. 验收清单

| # | 验收项 | 判定 |
|---|---|---|
| 1 | 右键玩家（目标/队友/焦点）出现"加入黑名单" | 手动 |
| 2 | 点击弹出多行备注框，中文输入正常 | 手动 |
| 3 | 重复添加同一角色 → 更新备注，不新增 | 手动 |
| 4 | **两段名**：`Asha Brightvale` 显示完整且 key 正确 | 手动 |
| 5 | **同名不同姓**：`Asha Brightvale` / `Asha Nightfall` 互不干扰 | 手动 |
| 6 | 中文名 + 姓 正常 | 手动 |
| 7 | `/reload` 后黑名单/备注/快照仍在 | 手动 |
| 8 | 完全退出重登后仍在（SavedVariables） | 手动 |
| 9 | 管理页：搜索、新增、改备注、删除（二次确认） | 手动 |
| 10 | 黑名单玩家进队 → 只告警一次；离队再进 → 再告警 | 手动 |
| 11 | 队伍频道消息不含备注；默认不开 | 手动 |
| 12 | 拉黑瞬间自动截图，`Screenshots` 里能找到文件 | 手动 |
| 13 | 快照含 ID/时间/触发原因/目标/队员/事件窗口 | 自动断言 |
| 14 | 副本战斗中快照出现 `[受限内容]` 且**不报错** | 手动 |
| 15 | 触发层含 `BE_TRIGGER` + ID，显示 ≥ 8 秒，有声 | 手动 |
| 16 | OBS 150 秒回放能保存，视频里聊天字清晰、`BE_TRIGGER` 可读 | 手动 |
| 17 | 战斗日志未被注册（无 `ADDON_ACTION_FORBIDDEN`） | 看报错 |
| 18 | 战斗中打开右键菜单不报错、不破坏系统菜单项 | 手动 |
| 19 | 若实现 Python 助手：同 ID 只保存一次；OBS 不可用时报错 | 手动 |
| 20 | 副本内 `CHAT_MSG_LOOT` 文本**可读**（`issecretvalue` 为 false），掉落/分钱能入快照 | 实测 |
| 21 | `C_LootHistory` 能取到 `rollInfos[].roll` 与 `winner`（副本 boss 掉落） | 实测 |
| 22 | 长期存档开启后，2 万行 ≈ 2–4 MB，`/reload` 不卡 | 手动 |
| 23 | 副本锁定期聊天正文只有视频/截图能保留（快照为 `[受限内容]`） | 人工核对 |
| 24 | `LoggingChat(true)` 生效，`Logs\WoWChatLog.txt` 有内容且追加写 | 实测 |
| 25 | **副本内**队伍/团队聊天能在 `WoWChatLog.txt` 里看到原文（决定证据链上限） | 实测（关键） |
| 26 | `recordScope=instance` 时野外不记录，存档体积可控 | 手动 |

---

## 10. 执行方案（逐步，按顺序做，可打勾）

> 总计约 10–14 小时（不含 Python 助手）。每个阶段结束做一次"`/reload` → 重登 → 检查存档"。

### 阶段 A：落地前验证（约 30 分钟）

- [ ] **S01 建目录**：`_classic_beta_\Interface\AddOns\BlackEvidence\`，按第 3 节建 8 个 `.lua` + `.toc`（内容照抄第 3 节）。
  - 验收：游戏插件列表出现 BlackEvidence，无 Lua 报错。
- [ ] **S02 跑探针**：第 13 节 11 条 `/run` 逐条执行，输出记到本节末尾的"实测记录"。
  - 验收：至少拿到 `UnitName` 两个返回、`SEP`、`UnitPopupManager`、`C_LootHistory`、`LoggingChat` 五项。
- [ ] **S03 确认两段名**：对任意有姓的角色 `/run local n,s=UnitName("target"); print(n,s)`。
  - 验收：第二段是姓，不是 nil，不是服务器名。

### 阶段 B：数据库与身份（1–2 小时）

- [ ] **S04 Core.lua**：`ADDON_LOADED` 初始化 `BlackEvidenceDB`（缺字段补默认值）；注册 `/be`；封装 `BE:RegisterEvent`。
- [ ] **S05 Identity.lua**：`BE:UnitKey` / `BE:NormKey` / `BE:SplitFullName` / `BE:DisplayName`（照第 5 节）。
  - 验收：`/be who` 打印的 key == `name + SEP + surname`（小写）。
- [ ] **S06 版本迁移**：启动时按 `version` 补字段；`/be reset` 清空（二次确认）。

### 阶段 C：黑名单 + 右键 + 备注 + 管理页（3–4 小时）

- [ ] **S07 Blacklist.lua**：Add / Update / Remove / Get / Iterate + 备注搜索。
  - 验收：`/be add 名 姓 备注` 写入成功；重复添加只更新备注。
- [ ] **S08 ContextMenu.lua**：注入 `PLAYER / PARTY / RAID_PLAYER / TARGET / FOCUS` 五个菜单；`CanShow` 排除自己和 NPC（照 F1）。
  - 验收：右键队友出现"加入黑名单"；战斗中打开不报错；系统原菜单项完整。
- [ ] **S09 备注弹窗**：自定义 Frame + 多行 EditBox（照 F2），保存后串联截图/快照/触发层。
- [ ] **S10 管理页骨架**：760×540、三 Tab、可拖动、ESC 关闭。
- [ ] **S11 黑名单 Tab**：滚动列表 + 搜索 + 新增 + 编辑 + 删除（二次确认）。
  - 验收：第 9 节 1–11 项。

### 阶段 D：队伍告警（1–2 小时）

- [ ] **S12 PartyWatch**：订阅事件 → `C_Timer.After(0.4)` 扫描 → 小队/团队遍历 → `warned` 去重（照 F3）。
- [ ] **S13 本地告警**：屏幕上方红色条 + `PlaySound` + 聊天框黄字。
- [ ] **S14 频道发送**：`C_ChatInfo.SendChatMessage`，默认关；开启时二次确认；10 秒限流；文案不带备注。
  - 验收：第 9 节 10–11 项。

### 阶段 E：事件日志 + 快照 + 截图（2–3 小时）

- [ ] **S15 环形日志**：注册 F6 事件表；`issecretvalue` 判定（pcall）；180 秒 / 1000 条裁剪；`recordScope=instance` 时野外不入队。
- [ ] **S16 chatlog 自动开启**：`PLAYER_LOGIN` 调 `LoggingChat(true)`；设置项 `autoChatLog`。
  - 验收（关键）：进副本 → 队友说话 → `/reload` → `Logs\WoWChatLog.txt` 里有原文。
- [ ] **S17 快照**：ID 生成（秒内递增）、事件深拷贝（≤300 条）、队员快照、`TakeScreenshot()`、写入 DB、FIFO 20 份。
- [ ] **S18 C_LootHistory 增量同步**：在 `LOOT_HISTORY_*` 事件里复制到内存（照 7.7），快照时附带。
  - 验收：打完一个 boss 后，快照里能看到 物品 + 每人 state + roll + winner。

### 阶段 F：触发层与 OBS（1–2 小时）

- [ ] **S19 Overlay**：`TOOLTIP` 层、固定位置、`BE_TRIGGER` + ID + REASON + TARGET + TIME、8 秒、音效、不挡鼠标（照 F8）。
- [ ] **S20 `/be trigger`**：手动弹一次，用于调 OBS / Python。
- [ ] **S21 OBS 配置**：按 F9 配 150 秒回放，绑定"保存即时回放"热键。
- [ ] **S22 端到端**：进副本 → `/be trigger` → 按热键 → 检查视频里 `BE_TRIGGER` 与聊天字清晰。
  - 验收：第 9 节 12–18 项。

### 阶段 G：管理页收尾（1 小时）

- [ ] **S23 快照 Tab**：列表 + 只读多行 EditBox + 复制 + 删除单条/全部。
- [ ] **S24 设置 Tab**：全部 settings 项 + chatlog 状态提示 + OBS 参数提示。
- [ ] **S25 Export.lua**：按第 8 节格式渲染；secret 一律写 `[受限内容]`。
  - 验收：第 9 节 19–26 项。

### 阶段 H：可选 Python 助手（2–4 小时，不影响主功能）

- [ ] **S26 截区域**：固定 `560×160`，0.5–1 秒一次，只截这一块。
- [ ] **S27 识别**：模板匹配 `BE_TRIGGER`（首选），OCR 备用；读取同屏 ID。
- [ ] **S28 调 OBS**：obs-websocket 5.x `SaveReplayBuffer`；ID 去重 + 30 秒冷却；失败必须报错。
  - 验收：第 9 节 19 项 + 同一 ID 只保存一次。

### 交付前

- [ ] 完整跑第 9 节 26 条验收
- [ ] 检查 `BlackEvidenceDB` 体积（建议 < 10 MB）
- [ ] 打包整个 `BlackEvidence` 文件夹 + README（安装路径、`/be` 命令、OBS 设置、chatlog 说明）

### 实测记录（S02 填这里）

```
GetBuildInfo()            =
UnitName("player")        = name / surname
SEP                       =
UnitPopupManager          =
UnitPopupButtonMixin      =
C_LootHistory             = 有无 / 签名是否一致
LoggingChat               = 可用 / 副本内是否写原文
Screenshot                = 文件名格式
```

---

## 11. 已知风险与对策

| 风险 | 影响 | 对策 |
|---|---|---|
| `UnitPopupButtonMixin` 名字/接口和你客户端不一致 | 菜单注入失败 | 第 13 节探针确认；退化为包装 `UnitPopup_OpenMenu` |
| `menu.GetEntries` 返回结构不是数组 | 菜单崩 | 注入前 `type(entries)=="table"` 判断；失败就回滚 |
| `C_LootHistory` 签名不同 | Roll 明细拿不到 | 只用 `pcall`，失败跳过；不影响主流程 |
| 分隔符常量读取不到 | 名字拼错 | 兜底：用 `NameUtil.FormatUnitNameForDisplay` 或 `GetUnitName` 显示；匹配时退化为原始两个返回值的拼接 |
| SavedVariables 重登丢失 | 数据丢 | 第 7.3 节 CVar 镜像兜底 |
| 发频道被举报/刷屏 | 账号风险 | 默认关闭 + 10 秒限流 + 一次组队只发一次 |
| secret value 写进存档 | 存档异常 | 统一 `[受限内容]`，不写原文 |
| 截图文件名预测错 | 对不上文件 | 标 `predicted=true`，同时记录精确时间 |

---

## 12. 与原始需求文档的差异（重要）

原始文档里这几处**不能照抄**：

1. `NormalizePlayerKey(name, realm)` 和 `"名字-服务器"` → Forever 无服务器，必须改成两段姓名 + `SEP`。
2. `"取不到服务器名退化为名字"` → 会串号，禁止。
3. `LOOT_HISTORY_ROLL_CHANGED` 等事件名 → 按第 13 节实测结果再定，别写死。
4. `UIDropDownMenu_AddButton` / `UnitPopupMenus` 数组注入 → 会破坏菜单。
5. `SendChatMessage` → 改 `C_ChatInfo.SendChatMessage`。
6. 回放 150 秒（已确认），非 300 秒。
7. 文档漏了自动截图 → 本方案补上（F5）。

---

## 13. 上机探针（写代码前先跑，5 分钟）

在游戏聊天框逐条粘贴执行，把输出记下来：

```lua
-- 1) 版本
/run print(GetBuildInfo())

-- 2) 两段姓名
/run local n,s=UnitName("player"); print("name=["..tostring(n).."] surname=["..tostring(s).."]")
/run local n,s=UnitNameUnmodified("player"); print("raw name=["..tostring(n).."] surname=["..tostring(s).."]")

-- 3) 分隔符
/run local c=Constants and Constants.CharacterNameSeparatorConsts; print("SEP=["..tostring(c and c.CHARACTERNAME_SURNAME_SEPARATOR).."]")

-- 4) NameUtil
/run print("NameUtil", type(NameUtil), NameUtil and type(NameUtil.SplitPlayerNameIntoParts))

-- 5) 单位菜单
/run print("UnitPopupManager", type(UnitPopupManager)); local m=UnitPopupManager and UnitPopupManager:GetMenu("PLAYER"); print("menu", type(m), m and type(m.GetEntries))
/run print("UnitPopupButtonMixin", type(UnitPopupButtonMixin))

-- 6) secret 判定
/run print("issecretvalue", type(issecretvalue))

-- 7) 截图（执行后去 Screenshots 目录看文件名）
/run Screenshot()

-- 8) 掉落历史
/run print("C_LootHistory", type(C_LootHistory)); print("enc", C_LootHistory and type(C_LootHistory.GetAllEncounterInfos))

-- 9) 频道 API
/run print("C_ChatInfo.SendChatMessage", type(C_ChatInfo and C_ChatInfo.SendChatMessage))

-- 10) 队伍
/run print("inGroup", IsInGroup(), "inRaid", IsInRaid(), "n", GetNumGroupMembers())

-- 11) 客户端聊天日志（关键：决定副本内聊天原文能不能存）
/run print("LoggingChat", type(LoggingChat), "IsLoggingChat", type(C_ChatInfo and C_ChatInfo.IsLoggingChat))
/run LoggingChat(true); print("chatlog ->", C_ChatInfo and C_ChatInfo.IsLoggingChat())
-- 然后进副本，让队友说一句话，/reload，去 _classic_beta_\Logs\WoWChatLog.txt 里找这行

-- 12) 聊天锁定状态 + 已移除的老函数（Forever 里应当不存在）
/run print("InChatMessagingLockdown", C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown())
/run print("GetLootRollItemInfo", type(GetLootRollItemInfo), "C_TooltipInfo.GetLootRollItem", type(C_TooltipInfo and C_TooltipInfo.GetLootRollItem))
```

把结果填回本文档"待实测"处，然后开始 P0。

---

## 14. 参考（实现时可查）

- `API:UnitName` / `API:UnitFullName` — 两段姓名、realmless
- `API:C_NameUtil.ReplaceSurnameSeparatorWithLinkSeparator` — 聊天链接分隔符与显示分隔符不同
- `Blizzard_UnitPopupShared/UnitPopupShared.lua` — 菜单对象与 `GetEntries`
- `API:Screenshot` — 无参数、无返回
- `C_ChatInfo.SendChatMessage` — 替代 deprecated 的 `SendChatMessage`
- `C_LootHistory` — 副本掉落/roll 结构化账本
- `API:issecretvalue` — 12.x secret value 判定
- LibGuildRoster / VersionCheck（CurseForge, Forever）— 两段姓名主键的现成参考实现

---

## 15. 离线核对工具：hated-wow-mcp（可选但推荐）

`RdyGaming/hated-wow-mcp`（MIT）是唯一**明确支持 Forever / Camelot** 的 MCP 服务器：内置四套离线 API 索引（`mainline` / `classic` / `vanilla` / **`forever`**），不装游戏、不连客户端也能核对签名、事件 payload、FrameXML 源码。

### 安装

```powershell
npx -y hated-wow-mcp --list                      # 应列出 20 个工具
npx -y hated-wow-mcp sync ui-source -- forever    # 约 46 MB，只有要读 FrameXML 时才需要
npx -y hated-wow-mcp sync game-data -- forever    # 图集 / FileDataID，可选
```

要求 Node 20+，无需 API key。数据缓存在 `%LOCALAPPDATA%\hated-wow-mcp\Cache`。

### OpenCode 配置（Windows 必须用 cmd 包一层）

```json
{
  "mcp": {
    "wow": {
      "type": "local",
      "command": ["cmd", "/c", "npx", "-y", "hated-wow-mcp"],
      "environment": { "WOW_DEFAULT_FLAVOR": "forever" },
      "enabled": true
    }
  }
}
```

### 对应本方案的用途

| 要确认的事 | 工具 |
|---|---|
| `UnitName` 到底几个返回值 | `wow_api_search` |
| `C_LootHistory.*` 签名 / 结构字段 | `wow_api_search` / `wow_api_type_search` |
| 事件 payload | `wow_api_event_search` |
| Forever 与 Retail 的差异 | `wow_api_diff` |
| 读 `UnitPopupShared.lua` / `ChatInfoDocumentation.lua` | `wow_ui_grep` / `wow_ui_read_file` |
| TOC 校验（16001 / `_Camelot` / 文件列表） | `wow_toc_validate` |
| 废弃 API / taint 检查 | `wow_lua_lint --flavor forever` |

### 本文档已用它核对过的结论（2026-10-23，`api-forever.json`，生成于 2026-09-18）

- `UnitName(unit)` → **两个返回值** `unitName, unitServer`（Forever 里第二段是姓）✅
- `Screenshot()` → 存在，无参数无返回 ✅
- `C_ChatInfo.SendChatMessage` → 存在；裸 `SendChatMessage` 已不在索引里 ✅
- `C_ChatInfo.IsLoggingChat` / **`C_ChatInfo.InChatMessagingLockdown`** → 存在 ✅
- `C_LootHistory.GetSortedInfoForDrop(encounterID, **lootListKey**)`，字段名是 `lootListKey` 不是 `lootListID` ✅（已按此修正正文）
- **`GetLootRollItemInfo` / `GetLootRollItemLink` 在 Forever 不存在**（已移除）✅
- `LOOT_ITEM_ROLL_WON` 事件存在，payload 含 `roll`（自己赢时有点数）✅
- `ENCOUNTER_LOOT_RECEIVED` 无玩家字段 ✅
- `CHAT_MSG_*` 共 18 个参数，第 2 个是完整名、第 12 个是 guid ✅

### 已知限制（README 明示）

Forever 缺三个上游列表（globals / eventNames / cvars），因此：
- `wow_lua_lint` 的"未知函数"检查在 forever 上**关闭**；
- `wow_api_diff` 里裸名字显示 "not documented" 而非 "not available"；
- `wow_cvar_search` 只有 Blizzard UI 用到的 CVar，没有默认值/描述/保护标记；
- `LoggingChat` 不在 API 索引里（是 FrameXML 全局），仍要用第 13 节探针 11 在游戏里确认。

---

## 16. 借鉴清单：BlackBook 项目评审结论

评审对象：`D:\文档\Trae-CN\temp_20261026_01`（BlackBook 1.0.0，13 个 Lua 文件 + Python 录像助手 + 339 条离线断言）。

**结论：不要 fork，cherry-pick。** 它的日志/导出/证据/录像助手是工程亮点；身份模型、聊天发送、掉落 API 全是为"有服务器、非 12.x"的客户端写的，在 Forever 上会**静默失败**。

### 16.1 值得移植（按价值排序）

| # | 来源 | 做什么 | 移植时必须改 |
|---|---|---|---|
| 1 | `recorder/blackbook_recorder.py` | ffmpeg 分段环形缓冲 + **监听 Screenshots 新文件**当触发 → 拼接最近 N 秒 → 证据包（capture / replay.mp4 / chatlog_tail / loot_and_rolls / note / meta.json / index.jsonl） | `APP_NAME`；SavedVariables 文件名与表名改 `BlackEvidence`；默认 300s → **150s**；`wow_root` 显式指向 `_classic_beta_`；截图扩展名已支持 jpg |
| 2 | `Logger.lua` + `Core.lua` 的 `seterrorhandler` 链式接管 | 会话号、锚点、`log since`、事件追踪、error 自动附环境快照 | `sessionFrom = seqCount + 1`；`SafeToString` 里加 `issecretvalue`；硬上限 |
| 3 | `Export.lua`（EncodeList / ParseList / ApplyList） | 多行备注**不转义**，`---` 终止；导入时只更新备注 | 导出 `name` **和** `surname`（或 GUID），**不要** `-`；备注行恰好是 `---` 时拒绝 |
| 4 | `Trigger.lua`（Fire / BuildContext / ScheduleScreenshot） | 触发瞬间冻结上下文 + 时间线 + 截图 | `Timeline.Mark` 必须在 `Snapshot` **之前**；ID 用 GUID+时间，不用 `seq % 100` |
| 5 | `Menu.lua`（ResolveUnit / Stats / LiveReport + `Menu.ModifyMenu` 注册形状） | 多菜单 ID 注入 + "哪条路生效/展开几次/点过几次"实况报告 | 只保留 `MENU_UNIT_PLAYER/TARGET/PARTY/RAID_PLAYER`；注入成功要靠"首次构建菜单时观测"，不能只看 `pcall` |
| 6 | `Util.lua` 的 UTF-8 工具 | `utf8SafeStart/End/Tail`、`Truncate`、`StripColors`、`ParseItemLink` | 只拿这几个；`FullName/UnitName2/NormalizeName/CharTag` **全部重写** |
| 7 | `Slash.lua` 的 SelfTest / LiveTest + `Logger.Capture*` | `/be test` 一键自检、产出可粘贴诊断 | 必须做成非破坏性、且感知 lockdown |

### 16.2 禁止照抄（Forever 上会静默失败）

| 问题 | 位置 | 后果 |
|---|---|---|
| 身份键 | `Util.FullName`（`name.."-"..realm`）、`UnitName2`（把第二个返回值叫 realm）、`MakeKey(name)` 只取第一个返回值 | 同名不同姓串号/漏判；姓被当服务器名 |
| 掉落/ROLL | `Timeline.rollInfo` 探测已移除的 `GetLootRollItemInfo/Link`；`CollectLootHistory` 用 `encInfo.items/item.players` | 全部变"未知物品"；账本返回空 |
| secret 文本 | 没有 `issecretvalue` / `InChatMessagingLockdown` | 副本锁定期 concat/gsub 抛错，时间线全空 |
| 发频道 | 全局 `SendChatMessage`；按"战斗中"排队 | 已废弃；真正的限制是 messaging lockdown |
| TOC | 无 `_Camelot.toc` / `AllowLoadGameType: forever` | 可能落到 Vanilla 11507 被禁用 |
| legacy 菜单 | `UnitPopupMenus[key]` 当字符串数组（`#list`、`table.insert`） | Forever 上会破坏系统菜单，必须整段删除 |

### 16.3 移植时要顺手修的 bug

- 删除确认空操作：`StaticPopup_Show(which, name, note, nil, entry.key)` → 第 4 参是 `data`，永远拿到 nil。
- `/bl log session` 用 `entry.seq` 比 `sessionFrom = count + 1` → reload 后返回旧会话。
- 证据先 Snapshot 后 Mark → 触发标记不在自己的证据里。
- `scanSeedOnly = scanSeedOnly or seedOnly` → 登录 seed 扫描期间的真实名单变化被降级，漏警告。
- 一个模块 init 抛错会跳过 `Slash.Init` → 用户连命令都没有。
- 存档膨胀：300 条 × 6000 字符 ≈ 180 万字符（`Validate` 甚至允许 30M），登出卡顿。
- `Timeline.Prune` 每次 push 都 `table.remove(buffer,1)` → O(n²)。

### 16.4 录像助手移植清单

- 已在支持的目录表里包含 `_classic_beta_`，但自动选目录可能选到别的客户端 → **配置里显式写 `wow_root`**。
- 录制是 `gdigrab` 抓**整个桌面**（不是游戏窗口）→ 切出去会把桌面录进去；用 `region` 限区域。
- 触发后是**同步归档**（停止录制 → 拼接 → 写文件），期间有 10–120 秒空档，连续两次触发会重叠/丢图 → 建议改成"归档线程 + 队列"。
- 段号每个进程从 0 重排，可能覆盖上一次的段 → 加会话前缀。
- `-c copy` 拼接没有 ffprobe 校验、没有重编码兜底 → 分辨率/区域变化会产出坏 mp4。
- 聊天时间戳写死 `M/D HH:MM:SS.mmm`；`chat_after_seconds` 实际抓不到尾巴（读取发生在拼接后）。
- 手写 Lua 解析器只支持双引号字段 → SavedVariables 结构一改就静默读空。
- 无单实例锁、无磁盘空间检查、ffmpeg 崩溃后每轮无退避重启。

---

## 17. 多版本移植结果（已实现）

需求变更为"正式服 + 时光服 + 无限服三端可用"后，架构从 Forever-only 调整为 **profile 能力探测**：同一份代码按客户端能力分叉，而不是按版本号散落 if。

### 17.1 产物

| 位置 | 内容 | 体量 |
|---|---|---|
| `BlackEvidence/` | 15 个 Lua 文件 | 7,555 行 |
| `BlackEvidence/*.toc` | 8 个（Mainline/Vanilla/TBC/Wrath/Cata/Mists/Camelot/兜底） | — |
| `BlackEvidence/recorder/` | `blackevidence_recorder.py` + `config.ini` + 启动脚本 | 2,565 行 Python |
| `BlackEvidence/CONTRACT.md` | 模块契约（profile/API/数据模型） | — |
| `BlackEvidence/README.md` | 安装、命令、测试清单 | — |
| `wow-addon/tests/` | `stub_be.lua` + `run_be.py` 离线冒烟 | — |

### 17.2 三个 profile

| 能力 | retail | classic | forever |
|---|---|---|---|
| 右键菜单 | `Menu.ModifyMenu` | `UnitPopupMenus`（legacy） | `Menu.ModifyMenu` |
| 姓名第二段 | 服务器 | 服务器 | **姓** |
| 发送频道 | `C_ChatInfo.SendChatMessage` | 全局 `SendChatMessage` | `C_ChatInfo.SendChatMessage` |
| C_LootHistory | 有 | 无 | 有 |
| secret / lockdown | 有 | 无 | 有 |

身份键：`Identity.lua` 统一生成，其它模块禁止自己拼名字。数据按 profile 分仓（`profiles.retail/classic/forever`），导出/导入负责跨版本搬运。

### 17.3 已验证

- `luaparser` 解析 15 个 Lua 文件：**0 错误**。
- 离线装载（lupa + WoW stub）：15 个文件按 TOC 顺序加载 → `InitManual()` → **17 项断言 0 失败**，覆盖 profile 识别（forever/16001/surname）、身份键、黑名单增删、导出文本、证据触发、时间线、日志、Comms/Menu 状态、UI 入口、Slash 注册。
- 录像助手：`py_compile` 通过；`--selftest`、`--dry-run --fake-screenshot --exit-after-trigger`、SavedVariables 解析、锁竞争、ffprobe 校验/重编码回退均由移植 lane 实测通过。
- **未验证**：真机（正式服/时光服）的 `Menu.ModifyMenu` 实际行为、`C_LootHistory` 返回结构、secret 文本处理、UI 模板差异、SavedVariables 落盘。这些必须靠 `/be status`、`/be menu`、`/be test` 在客户端确认。

### 17.4 与 BlackBook 的差异（继承的修复）

- 会话过滤 `sessionFrom = seqCount + 1`；secret 安全的日志字符串化。
- 删除确认的 `StaticPopup_Show` 第 4 参传 `data`（不再空操作）。
- `Timeline` 用 head 索引环形（去掉 O(n²)）；`Trigger` 先 Mark 再 Snapshot；证据上限 50 条 × 300 行。
- 扫描竞态修复（seed / 真实名单变化分离）。
- 每个模块 `Init` 独立 pcall；一个失败不影响其它模块与 `/be` 命令。
- 发频道改为按 `InChatMessagingLockdown` 排队，并校验发送结果。
- 归档/段号/ffprobe 校验/单实例锁/磁盘检查全部在录像助手里补齐。

### 17.5 下一步（真机测试顺序）

1. 正式服：`/be status` → 右键菜单 → 加黑名单 → `/reload` → 管理页三 Tab。
2. 时光服：同上，重点看 `menu=legacy` 与 `name=realm`。
3. 双账号：小号进队 → 只告警一次 → 离队再进 → 再告警。
4. 打开"发到队伍频道" → 确认文案不含备注。
5. 装录像助手 → 拉黑 → 检查 `evidence/<时间戳>_<截图名>/` 六个文件。
6. 无限服开服后：`/be status` 确认 `profile=forever`、`name=surname`、`menu=modern`，再跑一遍 1–5。
