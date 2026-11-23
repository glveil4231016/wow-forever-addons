"""Fetch Forever item values and cache them as JSON.

    python tools/holybulwark/fetch_forever_items.py --from-tfe        # 只抓 TFE fallback 行（嫌疑物品）
    python tools/holybulwark/fetch_forever_items.py --all             # 全部 Data.lua 物品
    python tools/holybulwark/fetch_forever_items.py --ids 940,14624   # 指定 ID

为什么需要它：`HolyBulwark/Data.lua` 的属性来自 The Forever Era，而 TFE 是
「Classic Era 数据 + Forever 覆盖层」，凡是没有 Forever 行的物品，属性都是 Era 的。
两个社区站给的才是 Forever 值：

* 主源 `wow-forever.gg`：物品页 `<div class="game-tooltip">`，含 `Classic Era | Forever` 对照；
* 备源 `warcraftmaps.com`：主源 404 时用（它的页面同样标 `Patch 1.60.1 · Source: Game client`）。

输出 `tools/holybulwark/data/forever_items.json`，由 build_data.ps1 读取。
页面缓存到 `data/wfg/<id>.html`、`data/wcm/<id>.html`，可断点续跑（`--refresh` 强制重抓）。
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
CACHE_WFG = os.path.join(DATA, 'wfg')
CACHE_WCM = os.path.join(DATA, 'wcm')
OUT = os.path.join(ROOT, 'tools', 'holybulwark', 'data', 'forever_items.json')
REPORT = os.path.join(DATA, 'forever_items_report.txt')
DATA_LUA = os.path.join(ROOT, 'HolyBulwark', 'Data.lua')
TFE_SEARCH = os.path.join(DATA, 'tfe_search.json')

WFG_URL = 'https://wow-forever.gg/db/items/%d/'
WCM_URL = 'https://warcraftmaps.com/item/%d/%s'

# 页面英文词条 -> Data.lua 的 stats key（对应 build_data.ps1 的 $statKeys）。
# 顺序重要：长句（"damage and healing done by magical spells"）必须排在
# 'healing' / 'spell damage' 前面，否则会被短词抢走。
STAT_MAP = [
    ('damage and healing done by magical spells', 'sp'),
    ('damage and healing', 'sp'),
    ('damage done by magical spells', 'sp'),
    ('healing done by magical spells', 'heal'),
    ('spell power', 'sp'),
    ('spell damage', 'sp'),
    ('bonus healing', 'heal'),
    ('increases healing', 'heal'),
    ('healing', 'heal'),
    ('intellect', 'int'),
    ('stamina', 'sta'),
    ('spirit', 'spi'),
    ('strength', 'str'),
    ('agility', 'agi'),
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
QUALITY_BY_WORD = {'poor': 0, 'common': 1, 'uncommon': 2, 'rare': 3, 'epic': 4, 'legendary': 5}

TOOLTIP_RE = re.compile(r'<div class="game-tooltip"[^>]*>(.*?)</div>\s*</div>', re.S)
ITEM_LINE_RE = re.compile(r'^\s*\{(\d+),"((?:[^"\\]|\\.)*)",(\d+),(\d+),(\d+),.*?"((?:[^"\\]|\\.)*)",(?:"((?:[^"\\]|\\.)*)")?\}?,?\s*$')
NUM = r'([0-9]+(?:\.[0-9]+)?)'
STAT_LINE_RE = re.compile(r'^\+%s\s+([A-Za-z][A-Za-z \']*)' % NUM)
BY_RE = re.compile(r'(?:Increases|Improves)\s+(?:your\s+)?(.+?)\s+by\s+(?:up to\s+)?%s' % NUM, re.I)


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


def match_stat(name):
    low = name.lower().strip()
    low = re.sub(r'\b(your|the|all|of)\b', ' ', low)
    low = re.sub(r'\s+', ' ', low).strip()
    for needle, key in STAT_MAP:
        if needle in low:
            return key
    return None


def parse_lines(lines, quality=None):
    """两站共用的行解析：`+N Stat`、`Increases ... by N`、Item Level、Requires Level、Armor。"""
    out = {'stats': {}, 'unmapped': [], 'equip': []}
    if quality is not None:
        out['q'] = quality

    for line in lines:
        mm = re.search(r'Item Level %s' % NUM, line)
        if mm and 'ilvl' not in out:
            out['ilvl'] = int(float(mm.group(1)))
            continue
        mm = re.search(r'Requires Level %s' % NUM, line)
        if mm and 'req' not in out:
            out['req'] = int(float(mm.group(1)))
            continue
        if line.startswith('Binds when') and 'bind' not in out:
            out['bind'] = line
            continue
        mm = re.search(r'(\d+) Armor$', line)
        if mm and 'armor' not in out:
            out['armor'] = int(mm.group(1))
            continue

        body = line
        mm = re.search(r'^(?:Equip|Use|Set|Chance on hit):\s*(.+)$', line)
        if mm:
            body = mm.group(1).strip()
            if not body.startswith('+'):
                out['equip'].append(body)

        for sm in STAT_LINE_RE.finditer(body):
            key = match_stat(sm.group(2))
            if key:
                out['stats'][key] = out['stats'].get(key, 0) + float(sm.group(1))
            else:
                out['unmapped'].append('+%s %s' % (sm.group(1), sm.group(2).strip()))
        for sm in BY_RE.finditer(body):
            key = match_stat(sm.group(1))
            if key:
                out['stats'][key] = out['stats'].get(key, 0) + float(sm.group(2))
            else:
                out['unmapped'].append('%s by %s' % (sm.group(1).strip(), sm.group(2)))
        rm = re.search(r'Restores\s+%s\s+mana per 5' % NUM, body, re.I)
        if rm:
            out['stats']['mp5'] = out['stats'].get('mp5', 0) + float(rm.group(1))

    for k, v in list(out['stats'].items()):
        out['stats'][k] = int(v) if float(v).is_integer() else round(v, 2)
    return out


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


def parse_tooltip(page):
    """wow-forever.gg：只认 game-tooltip 块。"""
    m = TOOLTIP_RE.search(page)
    if not m:
        return {'error': 'no tooltip'}
    fragment = m.group(1)
    quality = None
    qm = re.search(r'<b class="(q[0-6])"', fragment)
    if qm:
        quality = QUALITY_BY_CLASS[qm.group(1)]
    out = parse_lines(strip_tooltip(fragment), quality)
    out['src'] = 'wow-forever'
    return out


def parse_warcraftmaps(page):
    """warcraftmaps.com：无固定容器，按行找 `Item Level` 附近的属性块。"""
    text = re.sub(r'<script.*?</script>|<style.*?</style>', '', page, flags=re.S)
    quality = None
    qm = re.search(r'class="tt-name"[^>]*>\s*<span class="([^"]*)"', page) or re.search(
        r'class="[^"]*\bq-(poor|common|uncommon|rare|epic|legendary)', page)
    if qm:
        token = re.search(r'q-(poor|common|uncommon|rare|epic|legendary)', qm.group(1)) or qm
        if token:
            quality = QUALITY_BY_WORD[token.group(1)]
    text = re.sub(r'<[^>]+>', '\n', text)
    text = htmllib.unescape(text)
    lines = [re.sub(r'\s+', ' ', ln).strip() for ln in text.split('\n')]
    lines = [ln for ln in lines if ln]

    marks = [i for i, ln in enumerate(lines) if re.match(r'^Item Level \d+$', ln)]
    if not marks:
        return {'error': 'no item level'}

    # 两站排版不同：属性有时在 Item Level 之前（审判套），有时在后（洞察法袍）。
    # 每个候选位置都取一次，选属性命中最多、且带护甲的那个窗口。
    best = None
    for idx in marks:
        window = lines[max(0, idx - 35):idx + 1]
        for ln in lines[idx + 1:idx + 30]:
            if (ln.startswith('(') or ln.startswith('Set:') or ln.startswith('Durability')
                    or ln.startswith('Classes:') or ln.startswith('Sell Price')
                    or re.match(r'^\d+/\d+\)?$', ln)):
                break
            window.append(ln)
        window_quality = quality
        if window_quality is None:
            for ln in window:
                if ln.lower() in QUALITY_BY_WORD:
                    window_quality = QUALITY_BY_WORD[ln.lower()]
                    break
        parsed = parse_lines(window, window_quality)
        score = len(parsed['stats']) + (1 if 'armor' in parsed else 0)
        if best is None or score > best[0]:
            best = (score, parsed, window)
    out = best[1]
    out['src'] = 'warcraftmaps'
    if any('not confirmed' in ln.lower() for ln in best[2]):
        out['statsUnconfirmed'] = True
    return out


def slug(name):
    value = name.lower().replace("'", '')
    value = re.sub(r'[^a-z0-9]+', '-', value)
    return value.strip('-')


def load_items(path):
    """Data.lua → {id: {"zh": 中文名, "en": 英文名}}"""
    items = {}
    with io.open(path, encoding='utf-8') as fh:
        for line in fh:
            m = ITEM_LINE_RE.match(line.strip())
            if not m:
                continue
            item_id = int(m.group(1))
            en = m.group(6) or ''
            en = en.replace('\\"', '"').replace('\\\\', '\\')
            items[item_id] = {'zh': m.group(2), 'en': en}
    return items


def tfe_fallback_ids(items):
    if not os.path.exists(TFE_SEARCH):
        raise SystemExit('缺少 %s —— 先跑 tools/holybulwark/fetch_data.ps1，或用 --all' % TFE_SEARCH)
    raw = json.load(io.open(TFE_SEARCH, encoding='utf-8'))
    ix = {c: i for i, c in enumerate(raw['cols'])}
    fb = {int(row[ix['id']]): row[ix['fb']] for row in raw['rows']}
    picked = [i for i in items if fb.get(i, 0) != 0]
    clean = len([i for i in items if fb.get(i, 0) == 0])
    return picked, clean


def read_cache(path):
    """返回 ('ok', text) / ('404', '') / ('none', '')。"""
    if not os.path.exists(path):
        return 'none', ''
    try:
        text = io.open(path, encoding='utf-8', errors='replace').read()
    except OSError:
        return 'none', ''
    return ('ok', text) if text else ('404', '')


def save_cache(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with io.open(path, 'w', encoding='utf-8', newline='\n') as fh:
        fh.write(text)


def get_cached(url, path, proxy, refresh, delay):
    state, text = read_cache(path)
    if state == 'ok' and not refresh:
        return text
    if state == '404' and not refresh:
        return None
    try:
        page = fetch(url, proxy)
        save_cache(path, page)
        if delay:
            time.sleep(delay)
        return page
    except urllib.error.HTTPError as exc:
        if exc.code in (403, 404, 410):
            save_cache(path, '')
            return None
        raise
    except Exception:
        raise


def main(argv):
    ap = argparse.ArgumentParser(description='抓 Forever 物品值（wow-forever.gg，失败退回 warcraftmaps.com）')
    ap.add_argument('--all', action='store_true', help='抓 Data.lua 的全部物品')
    ap.add_argument('--from-tfe', action='store_true', help='只抓 TFE 标记为 fallback 的物品（默认）')
    ap.add_argument('--ids', help='逗号分隔的物品 ID')
    ap.add_argument('--delay', type=float, default=1.2, help='每次请求间隔秒数')
    ap.add_argument('--limit', type=int, default=0)
    ap.add_argument('--proxy', default=os.environ.get('HTTPS_PROXY') or 'http://127.0.0.1:10809')
    ap.add_argument('--refresh', action='store_true', help='忽略缓存重新抓')
    ap.add_argument('--out', default=OUT)
    ap.add_argument('--report', default=REPORT)
    args = ap.parse_args(argv)

    items = load_items(DATA_LUA)
    if args.ids:
        ids = [int(x) for x in args.ids.replace(' ', '').split(',') if x]
    elif args.all:
        ids = sorted(items)
    else:
        ids, clean = tfe_fallback_ids(items)
        print('Data.lua %d 件，其中 TFE 有 Forever 行（跳过）%d 件，待抓 %d 件' % (len(items), clean, len(ids)))
    if args.limit:
        ids = ids[:args.limit]
    if not ids:
        print('没有需要抓取的 ID')
        return 0

    result = {}
    stats_names = {}
    missing, failed = [], []
    by_src = {'wow-forever': 0, 'warcraftmaps': 0}
    fetched = 0

    for n, item_id in enumerate(ids, 1):
        parsed = None
        try:
            page = get_cached(WFG_URL % item_id, os.path.join(CACHE_WFG, '%d.html' % item_id),
                              args.proxy, args.refresh, args.delay)
            if page:
                fetched += 1
                parsed = parse_tooltip(page)
                if 'error' in parsed:
                    parsed = None
        except Exception as exc:  # noqa: BLE001 - 单件失败不中断
            failed.append((item_id, 'wfg %s' % str(exc)[:60]))

        if parsed is None:
            en = items.get(item_id, {}).get('en') or ''
            if not en:
                missing.append(item_id)
                continue
            try:
                url = WCM_URL % (item_id, slug(en))
                page = get_cached(url, os.path.join(CACHE_WCM, '%d.html' % item_id),
                                  args.proxy, args.refresh, args.delay)
                if page:
                    fetched += 1
                    parsed = parse_warcraftmaps(page)
                    if 'error' in parsed:
                        parsed = None
            except Exception as exc:  # noqa: BLE001
                failed.append((item_id, 'wcm %s' % str(exc)[:60]))

        if parsed is None:
            missing.append(item_id)
            continue
        result[str(item_id)] = parsed
        by_src[parsed['src']] += 1
        for key in parsed['stats']:
            stats_names[key] = stats_names.get(key, 0) + 1
        if n % 50 == 0:
            print('  %d/%d … 解析 %d（wfg %d / wcm %d），缺 %d，失败 %d' % (
                n, len(ids), len(result), by_src['wow-forever'], by_src['warcraftmaps'],
                len(missing), len(failed)))

    payload = {
        'source': 'wow-forever.gg + warcraftmaps.com',
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
        'network fetches: %d' % fetched,
        'parsed: %d (wow-forever %d, warcraftmaps %d)' % (
            len(result), by_src['wow-forever'], by_src['warcraftmaps']),
        'missing (no page on either site): %d %s' % (len(missing), missing[:20]),
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
