"""把 LootLedger 的 SavedVariables 转成 observed_loot.json。

输入是游戏写出的 `LootLedgerDB` 表（默认 `data/LootLedger.lua`）。用 lupa 在沙箱里
直接执行这段 Lua，再读回全局表 —— 不写正则解析 Lua，免得被引号/转义坑到。

用法：
    python tools/holybulwark/convert_observed_loot.py [输入.lua] [--out PATH]

输出：
    {"build": "1.60.1.71037", "generatedAt": "2026-11-23",
     "items": {"2589": [{"npc": "...", "zone": "...", "npcID": 15339,
                          "count": 3, "first": "2026-11-23", "last": "2026-11-24",
                          "ctx": "boss"}]}}

退出码：输入不可读/结构不对 → 1；否则 0。
"""

import argparse
import datetime
import json
import os
import sys
from collections import Counter

from lupa import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEFAULT_IN = os.path.join(ROOT, "data", "LootLedger.lua")
DEFAULT_OUT = os.path.join(ROOT, "data", "observed_loot.json")
UNKNOWN = "未知"


def lua_to_py(value):
    """递归把 lupa 的 table 转成 dict / list。空表一律当 dict。"""
    if value is None or isinstance(value, (bool, int, float, str)):
        return value
    try:
        items = list(value.items())
    except Exception:  # noqa: BLE001 - 非表就原样返回
        return value
    if not items:
        return {}
    keys = [k for k, _ in items]
    if all(isinstance(k, int) for k in keys):
        if keys == list(range(1, len(keys) + 1)):
            return [lua_to_py(v) for _, v in sorted(items)]
    return {str(k): lua_to_py(v) for k, v in items}


def load_db(path):
    with open(path, "r", encoding="utf-8") as fh:
        src = fh.read()

    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(src)
    db = lua.globals().LootLedgerDB
    if db is None:
        # 容忍「文件里只有一张表字面量」的变体
        lua.execute("return " + src)
        db = lua.globals().LootLedgerDB
    data = lua_to_py(db)
    if not isinstance(data, dict):
        raise ValueError("LootLedgerDB 不是一张表")
    return data


def day_string(stamp):
    """YYYYMMDD 整数 → ISO 日期；认不出来就返回空串，不猜。"""
    try:
        value = int(stamp)
    except (TypeError, ValueError):
        return ""
    if value < 19000101 or value > 99991231:
        return ""
    try:
        return datetime.date(value // 10000, (value // 100) % 100, value % 100).isoformat()
    except ValueError:
        return ""


def load_npc_index():
    """HolyBulwark/NpcZh.lua 里 478 个中文 NPC 名 → npcID。

    记录器在 boss 归属时拿不到 npcID（ENCOUNTER_END 只给名字），这里按名字反查，
    这样掉落来源也能点地图。同名多个 ID 时保守放弃，不猜。
    """
    path = os.path.join(ROOT, "HolyBulwark", "NpcZh.lua")
    if not os.path.isfile(path):
        return {}
    try:
        lua = LuaRuntime(unpack_returned_tuples=True)
        table = lua.eval(
            "function(src) local f=assert((loadstring or load)(src)); local ns={}; f({}, ns); return ns.npcZh end"
        )(open(path, encoding="utf-8").read())
        by_name = {}
        for npc_id, name in table.items():
            by_name.setdefault(str(name), []).append(int(npc_id))
        return {name: ids[0] for name, ids in by_name.items() if len(ids) == 1}
    except Exception:  # noqa: BLE001 - 反查失败不影响主流程
        return {}


def build_rows(items, npc_index=None):
    """把 sources 的 `名字|区域|npcID` 键展开成行。"""
    npc_index = npc_index or {}
    resolved = 0
    rows = {}
    for item_id, item in items.items():
        if not isinstance(item, dict):
            continue
        sources = item.get("sources") or {}
        if not isinstance(sources, dict):
            continue
        out = []
        for key, src in sources.items():
            if not isinstance(src, dict):
                continue
            npc, zone, npc_id = str(key), UNKNOWN, 0
            parts = str(key).split("|")
            if len(parts) >= 3:
                npc, zone = parts[0], parts[1]
                try:
                    npc_id = int(parts[2])
                except ValueError:
                    npc_id = 0
            elif len(parts) == 2:
                npc, zone = parts[0], parts[1]
            if npc_id == 0 and npc in npc_index:
                npc_id = npc_index[npc]
                resolved += 1
            out.append(
                {
                    "npc": npc or UNKNOWN,
                    "zone": zone or UNKNOWN,
                    "npcID": npc_id,
                    "count": int(src.get("n") or 0),
                    "first": day_string(src.get("first")),
                    "last": day_string(src.get("last")),
                    "ctx": str(src.get("ctx") or "unknown"),
                }
            )
        out.sort(key=lambda r: (-r["count"], r["npc"], r["zone"], r["npcID"]))
        try:
            key = str(int(item_id))
        except (TypeError, ValueError):
            key = str(item_id)
        rows[key] = out
    return rows, resolved


def main(argv=None):
    parser = argparse.ArgumentParser(description="LootLedger SavedVariables → observed_loot.json")
    parser.add_argument("input", nargs="?", default=DEFAULT_IN, help="SavedVariables 路径")
    parser.add_argument("--out", default=DEFAULT_OUT, help="输出 JSON 路径")
    args = parser.parse_args(argv)

    if not os.path.isfile(args.input):
        print("读取失败：找不到 %s（先在游戏里 /reload 导出 SavedVariables）" % args.input)
        return 1

    try:
        db = load_db(args.input)
    except Exception as exc:  # noqa: BLE001 - 任何解析/执行错误都算输入不可读
        print("读取失败：%s → %s" % (args.input, exc))
        return 1

    items = db.get("items") or {}
    if not isinstance(items, dict):
        print("读取失败：LootLedgerDB.items 不是一张表")
        return 1

    rows, resolved = build_rows(items, load_npc_index())
    payload = {
        "build": str(db.get("build") or "unknown"),
        "generatedAt": datetime.date.today().isoformat(),
        "items": rows,
    }

    out_dir = os.path.dirname(os.path.abspath(args.out))
    os.makedirs(out_dir, exist_ok=True)
    with open(args.out, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(payload, fh, ensure_ascii=False, indent=2, sort_keys=True)
        fh.write("\n")

    flat = [row for item_rows in rows.values() for row in item_rows]
    zones = Counter(row["zone"] for row in flat).most_common(5)
    unknown_rows = sum(1 for row in flat if row["npc"] == UNKNOWN)

    print("build=%s" % payload["build"])
    print("items=%d rows=%d" % (len(rows), len(flat)))
    print("zones: " + ("、".join("%s×%d" % (z, c) for z, c in zones) if zones else "无"))
    print("npc=未知 的行：%d" % unknown_rows)
    print("按 NpcZh 反查出 npcID 的行：%d" % resolved)
    print("→ %s" % args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
