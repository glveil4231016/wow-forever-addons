"""Parser tests for tools/holybulwark/fetch_forever_items.py.

The fixtures under tests/fixtures/wfg/ are trimmed wow-forever.gg item pages
(tooltip block only, captured 2026-11-23). They pin the Forever values so a
markup change on the site shows up as a test failure instead of silently
rewriting Data.lua with garbage.
"""

import io
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools', 'holybulwark'))

import fetch_forever_items as ff  # noqa: E402

FIXTURES = os.path.join(ROOT, 'tests', 'fixtures', 'wfg')

CASES = {
    # item id: (ilvl, req, quality, armor, stats)
    '940': (47, 42, 4, 74, {'int': 24, 'heal': 33, 'sp': 11}),
    '14624': (61, 56, 3, 637, {'sta': 16, 'int': 11, 'def': 17}),
    '252545': (53, 48, 2, 96, {'int': 5, 'spi': 8, 'sp': 8}),
    '274741': (25, 20, 2, 34, {'sta': 7, 'sp': 5}),
}

fails = 0


def check(label, got, want):
    global fails
    if got != want:
        fails += 1
        print('FAIL %s: got %r want %r' % (label, got, want))


for item_id, (ilvl, req, q, armor, stats) in sorted(CASES.items()):
    page = io.open(os.path.join(FIXTURES, item_id + '.html'), encoding='utf-8').read()
    parsed = ff.parse_tooltip(page)
    check(item_id + ' ilvl', parsed.get('ilvl'), ilvl)
    check(item_id + ' req', parsed.get('req'), req)
    check(item_id + ' quality', parsed.get('q'), q)
    check(item_id + ' armor', parsed.get('armor'), armor)
    check(item_id + ' stats', parsed.get('stats'), stats)
    check(item_id + ' unmapped', parsed.get('unmapped'), [])

# 940 的 Use 行必须保留，不能被当成属性
page = io.open(os.path.join(FIXTURES, '940.html'), encoding='utf-8').read()
parsed = ff.parse_tooltip(page)
if not any('Mana cost' in e for e in parsed.get('equip', [])):
    fails += 1
    print('FAIL 940 equip text: %r' % (parsed.get('equip'),))

print('forever parser ok: %d fixtures' % len(CASES) if not fails else 'forever parser FAIL %d' % fails)
raise SystemExit(1 if fails else 0)
