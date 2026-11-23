"""Fetch Forever item values from wow-forever.gg and cache them as JSON.

    python tools/holybulwark/fetch_forever_items.py --from-tfe        # 只抓 TFE fallback 行（嫌疑物品）
    python tools/holybulwark/fetch_forever_items.py --all             # 全部 Data.lua 物品
    python tools/holybulwark/fetch_forever_items.py --ids 940,14624   # 指定 ID

为什么需要它：`HolyBulwark/Data.lua` 的属性来自 The Forever Era，而 TFE 是
「Classic Era 数据 + Forever 覆盖层」，凡是没有 Forever 行的物品，属性都是 Era 的。
wow-forever.gg 的物品页 tooltip 是 Forever 版本的真值（含 `Classic Era | Forever`
对照），所以用它覆写 ilvl / req / quality / armor / stats。

输出 `data/forever_items.json`，由 tools/holybulwark/build_data.ps1 读取。
页面缓存到 `data/wfg/<id>.html`，可断点续跑（`--refresh` 强制重抓）。

只在明确需要时联网；单个物品失败不中断，统计写在 `--report` 文件里。
"""

import argparse
import gzip
import html as htmllib
import io
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA = os.path.join(ROOT, 'data')
CACHE = os.path.join(DATA, 'wfg')
OUT = os.path.join(ROOT, 'tools', 'holybulwark', 'data', 'forever_items.json')
REPORT = os.path.join(DATA, 'forever_items_report.txt')
DATA_LUA = os.path.join(ROOT, 'HolyBulwark', 'Data.lua')
TFE_SEARCH = os.path.join(DATA, 'tfe_search.json')

ITEM_URL = 'https://wow-forever.gg/db/items/%d/'

# 页面上的英文词条 -> Data.lua 的 stats key（与 build_data.ps1 的 $statKeys 对应）
STAT_MAP = [
    ('intellect', 'int'),
    ('stamina', 'sta'),
    ('spirit', 'spi'),
    ('strength', 'str'),
    ('agility', 'agi'),
    ('spell power', 'sp'),
    ('spell damage', 'sp'),
    ('healing', 'heal'),
    ('bonus healing', 'heal'),
    ('mana per 5', 'mp5'),
    ('health per 5', 'hp5'),
    ('defense rating', 'def'),
    ('dodge rating', 'dodge'),
    ('parry rating', 'parry'),
    ('block rating', 'block'),
    ('block value', 'bv'),
    ('bonus armor', 'bv'),
    ('spell critical strike rating', 'spellcrit'),
    ('spell crit rating', 'spellcrit'),
    ('spell hit rating', 'spellhit'),
    ('spell penetration', 'spen'),
    ('armor penetration', 'arpen'),
    ('critical strike rating', 'crit'),
    ('melee hit rating', 'hit'),
    ('hit rating', 'hit'),
    ('haste rating', 'haste'),
    ('expertise rating', 'exp'),
    ('fire resistance', 'fr'),
    ('nature resistance', 'nr'),
    ('frost resistance', 'frr'),
    ('shadow resistance', 'sr'),
    ('arcane resistance', 'ar'),
    ('all resistances', 'allres'),
]

QUALITY_BY_CLASS = {'q0': 0, 'q1': 1, 'q2': 2, 'q3': 3, 'q4': 4, 'q5': 5, 'q6': 6}

TOOLTIP_RE = re.compile(r'<div class="game-tooltip"[^>]*>(.*?)</div>\s*</div>', re.S)
ITEM_ID_RE = re.compile(r'^\s*\{(\d+),')
NUM = r'([0-9]+(?:\.[0-9]+)?)'


def fetch(url, proxy, timeout=60):
    handler = urllib.request.ProxyHandler({'https': proxy, 'http': proxy} if proxy else {})
    opener = urllib.request.build_opener(handler)
    req = urllib.request.Request(url, headers={
        'User-Agent': 'Mozilla/5.0 (compatible; holybulwark-data/1.0)',
        'Accept': 'text/html',
        'Accept-Encoding': 'identity',
    })
    with opener.open(req, timeout=timeout) as res:
        raw = res.read()
        if res.headers.get('Content-Encoding') == 'gzip':
            raw = gzip.decompress(raw)
        return raw.decode('utf-8', 'replace')


def strip_tooltip(fragment):
    text = re.sub(r'<br\s*/?>', '\n', fragment)
    text = re.sub(r'</(td|tr|table)>', '\n', text)
    text = re.sub(r'<[^>]+>', '|', text)
    text = htmllib.unescape(text)
    text = re.sub(r'\|+', '|', text)
    lines = []
    for line in text.split('\n'):
        line = line.replace('|', ' ').strip()
        line = re.sub(r'\s+', ' ', line)
        if line:
            lines.append(line)
    return lines


def match_stat(name):
    low = name.lower().strip()
    low = re.sub(r'\b(your|the|all|of)\b', ' ', low)
    low = re.sub(r'\s+', ' ', low).strip()
    for needle, key in STAT_MAP:
        if needle in low:
            return key
    return None


def parse_tooltip(page):
    m = TOOLTIP_RE.search(page)
    if not m:
        return {'error': 'no tooltip'}
    fragment = m.group(1)
    lines = strip_tooltip(fragment)
    out = {'stats': {}, 'unmapped': [], 'equip': [], 'lines': lines}

    qm = re.search(r'<b class="(q[0-6])"', fragment)
    if qm:
        out['q'] = QUALITY_BY_CLASS[qm.group(1)]

    for line in lines:
        mm = re.search(r'Item Level %s' % NUM, line)
        if mm:
            out['ilvl'] = int(float(mm.group(1)))
            continue
        mm = re.search(r'Requires Level %s' % NUM, line)
        if mm:
            out['req'] = int(float(mm.group(1)))
            continue
        if line.startswith('Binds when'):
            out['bind'] = line
            continue
        mm = re.search(r'%s Armor$' % NUM, line)
        if mm and 'armor' not in out:
            out['armor'] = float(mm.group(1))
            continue
        mm = re.search(r'^(?:Equip|Use|Set|Chance on hit):\s*(.+)$', line)
        if mm:
            body = mm.group(1).strip()
            if body.lower().startswith('+'):
                pass
            else:
                out['equip'].append(body)
            line_body = body
        else:
            line_body = line

        # +N Stat
        for sm in re.finditer(r'\+%s\s+([A-Za-z][A-Za-z \']*)' % NUM, line_body):
            key = match_stat(sm.group(2))
            if key:
                out['stats'][key] = out['stats'].get(key, 0) + float(sm.group(1))
            else:
                out['unmapped'].append('+%s %s' % (sm.group(1), sm.group(2).strip()))
        # Increases/Improves ... by N
        for sm in re.finditer(r'(?:Increases|Improves)\s+(?:your\s+)?(.+?)\s+by\s+%s' % NUM, line_body, re.I):
            key = match_stat(sm.group(1))
            if key:
                out['stats'][key] = out['stats'].get(key, 0) + float(sm.group(2))
            else:
                out['unmapped'].append('%s by %s' % (sm.group(1).strip(), sm.group(2)))

    for k, v in list(out['stats'].items()):
        out['stats'][k] = int(v) if float(v).is_integer() else round(v, 2)
    if isinstance(out.get('armor'), float) and out['armor'].is_integer():
        out['armor'] = int(out['armor'])
    return out


def load_data_lua_ids(path):
    ids = []
    with io.open(path, encoding='utf-8') as fh:
        for line in fh:
            m = ITEM_ID_RE.match(line)
            if m:
                ids.append(int(m.group(1)))
    return ids


def tfe_fallback_ids(data_ids):
    if not os.path.exists(TFE_SEARCH):
        raise SystemExit('缺少 %s —— 先跑 tools/holybulwark/fetch_data.ps1，或用 --all' % TFE_SEARCH)
    raw = json.load(io.open(TFE_SEARCH, encoding='utf-8'))
    ix = {c: i for i, c in enumerate(raw['cols'])}
    fb = {}
    for row in raw['rows']:
        fb[int(row[ix['id']])] = row[ix['fb']]
    picked = [i for i in data_ids if fb.get(i, 0) != 0]
    return picked, len([i for i in data_ids if fb.get(i, 0) == 0])


def main(argv):
    ap = argparse.ArgumentParser(description='抓 wow-forever.gg 的 Forever 物品值')
    ap.add_argument('--all', action='store_true', help='抓 Data.lua 的全部物品')
    ap.add_argument('--from-tfe', action='store_true', help='只抓 TFE 标记为 fallback 的物品（默认）')
    ap.add_argument('--ids', help='逗号分隔的物品 ID')
    ap.add_argument('--delay', type=float, default=1.4, help='每次请求间隔秒数')
    ap.add_argument('--limit', type=int, default=0)
    ap.add_argument('--proxy', default=os.environ.get('HTTPS_PROXY') or 'http://127.0.0.1:10809')
    ap.add_argument('--refresh', action='store_true', help='忽略缓存重新抓')
    ap.add_argument('--out', default=OUT)
    ap.add_argument('--report', default=REPORT)
    args = ap.parse_args(argv)

    data_ids = load_data_lua_ids(DATA_LUA)
    if args.ids:
        ids = [int(x) for x in args.ids.replace(' ', '').split(',') if x]
    elif args.all:
        ids = data_ids
    else:
        ids, clean = tfe_fallback_ids(data_ids)
        print('Data.lua %d 件，其中 TFE 有 Forever 行（跳过）%d 件，待抓 %d 件' % (len(data_ids), clean, len(ids)))
    if args.limit:
        ids = ids[:args.limit]
    if not ids:
        print('没有需要抓取的 ID')
        return 0

    os.makedirs(CACHE, exist_ok=True)
    result = {}
    stats_names = {}
    missing, failed = [], []
    fetched = 0
    for n, item_id in enumerate(ids, 1):
        path = os.path.join(CACHE, '%d.html' % item_id)
        page = None
        if os.path.exists(path) and not args.refresh:
            page = io.open(path, encoding='utf-8', errors='replace').read()
        else:
            try:
                page = fetch(ITEM_URL % item_id, args.proxy)
                io.open(path, 'w', encoding='utf-8', newline='\n').write(page)
                fetched += 1
                time.sleep(args.delay)
            except urllib.error.HTTPError as exc:
                if exc.code == 404:
                    missing.append(item_id)
                    io.open(path, 'w', encoding='utf-8').write('')
                    continue
                failed.append((item_id, 'http %s' % exc.code))
                continue
            except Exception as exc:  # noqa: BLE001 - 单个失败不中断
                failed.append((item_id, str(exc)[:80]))
                continue
        parsed = parse_tooltip(page) if page else {'error': 'empty'}
        if 'error' in parsed:
            missing.append(item_id)
            continue
        parsed.pop('lines', None)
        result[str(item_id)] = parsed
        for key in parsed['stats']:
            stats_names[key] = stats_names.get(key, 0) + 1
        if n % 50 == 0:
            print('  %d/%d … 已解析 %d，缺页 %d，失败 %d' % (n, len(ids), len(result), len(missing), len(failed)))

    payload = {
        'source': 'wow-forever.gg',
        'clientBuild': '1.60.1.71037',
        'fetchedAt': time.strftime('%Y-%m-%d'),
        'items': result,
    }
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with io.open(args.out, 'w', encoding='utf-8', newline='\n') as fh:
        json.dump(payload, fh, ensure_ascii=False, sort_keys=True, indent=1)

    unmapped = {}
    for item in result.values():
        for u in item.get('unmapped', []):
            unmapped[u] = unmapped.get(u, 0) + 1
    lines = [
        'ids requested: %d' % len(ids),
        'pages fetched: %d (cached %d)' % (fetched, len(ids) - fetched - len(missing) - len(failed)),
        'parsed: %d' % len(result),
        'missing page/tooltip: %d %s' % (len(missing), missing[:20]),
        'failed: %d %s' % (len(failed), failed[:10]),
        'stats seen: %s' % json.dumps(stats_names, ensure_ascii=False, sort_keys=True),
        'unmapped stat strings (top 20):',
    ]
    for text, count in sorted(unmapped.items(), key=lambda kv: -kv[1])[:20]:
        lines.append('  %3d  %s' % (count, text))
    with io.open(args.report, 'w', encoding='utf-8', newline='\n') as fh:
        fh.write('\n'.join(lines) + '\n')
    print('\n'.join(lines[:6]))
    print('-> %s' % args.out)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
