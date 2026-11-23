"""对比 Data.lua 现有属性与 wow-forever.gg 抓到的 Forever 值，先看差异再决定重建。

    python tools/holybulwark/report_forever_diff.py

读 `tools/holybulwark/data/forever_items.json`（fetch_forever_items.py 的产物）和
`HolyBulwark/Data.lua`，输出：属性变化的件数、会被过滤逻辑丢弃的件数、
以及属性解析失败（unmapped）的清单。不写任何文件。
"""

import io
import json
import os
import sys

from lupa import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA_LUA = os.path.join(ROOT, 'HolyBulwark', 'Data.lua')
FOREVER = os.path.join(ROOT, 'tools', 'holybulwark', 'data', 'forever_items.json')

INTERESTING = ('sp', 'holy', 'heal', 'sta', 'int', 'spi')


def load_items():
    lua = LuaRuntime(unpack_returned_tuples=True)
    loader = lua.eval(
        'function(src) local f=assert((loadstring or load)(src)); local ns={}; f({}, ns); return ns.data.items end'
    )
    with io.open(DATA_LUA, encoding='utf-8') as fh:
        items = loader(fh.read())
    return [list(row.values()) for row in items.values()]


def stats_of(table):
    return {str(k): float(v) for k, v in table.items()} if table is not None else {}


def main():
    if not os.path.exists(FOREVER):
        print('缺少 %s —— 先跑 fetch_forever_items.py' % FOREVER)
        return 1
    forever = json.load(io.open(FOREVER, encoding='utf-8'))['items']
    items = load_items()

    changed = []
    lost_sp = []
    unmapped = []
    missing_page = 0
    for it in items:
        item_id, name, ilvl, req, stats = str(it[1]), it[2], it[3], it[4], it[9]
        fv = forever.get(item_id)
        if not fv:
            missing_page += 1
            continue
        if fv.get('unmapped'):
            unmapped.append((item_id, name, fv['unmapped']))
            continue
        old = stats_of(stats)
        new = {k: float(v) for k, v in (fv.get('stats') or {}).items()}
        diffs = []
        for key in INTERESTING:
            a, b = old.get(key, 0), new.get(key, 0)
            if abs(a - b) > 0.001:
                diffs.append('%s %g→%g' % (key, a, b))
        if abs(float(ilvl) - float(fv.get('ilvl') or ilvl)) > 0.001:
            diffs.append('ilvl %s→%s' % (ilvl, fv.get('ilvl')))
        if abs(float(req) - float(fv.get('req') or req)) > 0.001:
            diffs.append('req %s→%s' % (req, fv.get('req')))
        if diffs:
            changed.append((item_id, name, diffs))
        if (old.get('sp', 0) + old.get('holy', 0)) > 0 and (new.get('sp', 0) + new.get('holy', 0)) <= 0:
            lost_sp.append((item_id, name, diffs))

    print('Data.lua 物品: %d' % len(items))
    print('有 Forever 数据: %d' % (len(items) - missing_page))
    print('没有页面/未抓到: %d' % missing_page)
    print('属性会变化: %d' % len(changed))
    print('会失去 sp/holy（可能被过滤掉）: %d' % len(lost_sp))
    print('解析器有未识别词条（属性保留 TFE）: %d' % len(unmapped))
    if changed:
        print('\n变化最大的 15 件：')
        for item_id, name, diffs in changed[:15]:
            print('  %s %s  %s' % (item_id, name, '; '.join(diffs)))
    if lost_sp:
        print('\n失去 sp/holy 的 15 件：')
        for item_id, name, diffs in lost_sp[:15]:
            print('  %s %s  %s' % (item_id, name, '; '.join(diffs)))
    if unmapped:
        print('\n未识别词条：')
        for item_id, name, texts in unmapped[:10]:
            print('  %s %s  %s' % (item_id, name, texts[:3]))
    return 0


if __name__ == '__main__':
    sys.exit(main())
