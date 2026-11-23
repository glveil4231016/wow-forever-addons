"""LootLedger 开发工具的检查：Lua 编译 + 转换脚本输出形状。

`tests/syntax_check.py` 只扫仓库顶层插件目录，`tools/recorder/LootLedger` 不在其内，
所以这里单独编译一次，保证 recorder 的 Lua 不会带着语法错误进游戏。
"""

import json
import os
import subprocess
import sys
import tempfile

from lupa import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = os.path.join(ROOT, "tools", "recorder", "LootLedger", "LootLedger.lua")
CONVERTER = os.path.join(ROOT, "tools", "holybulwark", "convert_observed_loot.py")
FIXTURE = os.path.join(ROOT, "tests", "fixtures", "LootLedger_sample.lua")

fails = []


def check(cond, msg):
    if not cond:
        fails.append(msg)


def lua_compile():
    lua = LuaRuntime(unpack_returned_tuples=True)
    compile_lua = lua.eval(
        "function(src, name) local f, err = (loadstring or load)(src, name); "
        "if not f then error(err) end; return true end"
    )
    with open(ADDON, "r", encoding="utf-8") as fh:
        compile_lua(fh.read(), os.path.basename(ADDON))


def run_converter(out_path):
    proc = subprocess.run(
        [sys.executable, CONVERTER, FIXTURE, "--out", out_path],
        cwd=ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    return proc


def main():
    if not os.path.isfile(ADDON):
        print("FAIL 缺少 %s" % os.path.relpath(ADDON, ROOT))
        return 1

    try:
        lua_compile()
    except Exception as exc:  # noqa: BLE001
        print("SYNTAX FAIL LootLedger.lua -> %s" % exc)
        return 1

    with tempfile.TemporaryDirectory() as tmp:
        out_path = os.path.join(tmp, "observed_loot.json")
        proc = run_converter(out_path)
        if proc.returncode != 0:
            print("FAIL 转换脚本退出码 %d" % proc.returncode)
            print(proc.stdout.strip())
            print(proc.stderr.strip())
            return 1
        if not os.path.isfile(out_path):
            print("FAIL 转换脚本没有写出 JSON")
            return 1
        with open(out_path, "r", encoding="utf-8") as fh:
            data = json.load(fh)

    check(data.get("build") == "1.60.1.71037", "build 应为 1.60.1.71037")
    check(bool(data.get("generatedAt")), "缺少 generatedAt")

    items = data.get("items") or {}
    check(isinstance(items, dict), "items 应为对象")
    check(len(items) == 3, "应有 3 个物品，实际 %d" % len(items))

    rows = [row for item_rows in items.values() for row in item_rows]
    check(len(rows) == 4, "应有 4 条来源，实际 %d" % len(rows))

    first = items.get("2589") or []
    check(len(first) == 1, "2589 应有 1 条来源")
    if first:
        row = first[0]
        check(row.get("npc") == "无疤者奥斯里安", "2589 的 npc 名字不对")
        check(row.get("zone") == "安其拉废墟", "2589 的 zone 不对")
        check(row.get("npcID") == 15339, "2589 的 npcID 应为 15339")
        check(row.get("count") == 3, "2589 的 count 应为 3")
        check(row.get("first") == "2026-11-23", "2589 的 first 应为 2026-11-23")
        check(row.get("last") == "2026-11-24", "2589 的 last 应为 2026-11-24")
        check(row.get("ctx") == "boss", "2589 的 ctx 应为 boss")

    unknown = [r for r in rows if r.get("npcID") == 0]
    check(len(unknown) == 1, "应恰好有 1 条 npcID = 0，实际 %d" % len(unknown))
    check(all(r.get("npc") == "未知" for r in unknown), "npcID = 0 的行 npc 应为 未知")

    chat = [r for r in rows if r.get("ctx") == "chat"]
    check(len(chat) == 1, "应恰好有 1 条 ctx = chat，实际 %d" % len(chat))

    # 缺文件必须报错退出（下游脚本靠退出码判断）
    missing = subprocess.run(
        [sys.executable, CONVERTER, os.path.join(ROOT, "tests", "fixtures", "不存在.lua"),
         "--out", os.path.join(ROOT, "tests", "__never_written.json")],
        cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace",
    )
    check(missing.returncode == 1, "输入缺失时退出码应为 1，实际 %d" % missing.returncode)

    if fails:
        for msg in fails:
            print("FAIL " + msg)
        return 1

    print("LootLedger ok: %d items / %d rows" % (len(items), len(rows)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
