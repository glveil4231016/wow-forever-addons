"""Guard: HolyBulwark/Data.lua may only ship items the Forever client defines.

The item database is built from The Forever Era, whose dataset also carries
Classic Era fallback rows for items this client never defines. Those rows used
to leak into Data.lua (1261 of 2047 entries) and showed up in game as classic
gear. tests/data/forever_item_ids.txt is the client's own ItemSparse id set
(build 1.60.1.71037, wago.tools).

Regenerate the id list together with Data.lua whenever the client build changes:

    python tools/holybulwark/dump_item_ids.py <ItemSparse_zhCN.csv>
"""

import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_LUA = os.path.join(ROOT, "HolyBulwark", "Data.lua")
ID_LIST = os.path.join(ROOT, "tests", "data", "forever_item_ids.txt")
ITEM_LINE = re.compile(r"^\s{8}\{(\d+),")


def load_client_ids(path):
    ids = set()
    with io.open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            ids.add(int(line))
    return ids


def load_shipped_ids(path):
    ids = []
    with io.open(path, encoding="utf-8") as fh:
        for line in fh:
            m = ITEM_LINE.match(line)
            if m:
                ids.append(int(m.group(1)))
    return ids


def main():
    client = load_client_ids(ID_LIST)
    shipped = load_shipped_ids(DATA_LUA)
    if not client:
        print("FAIL: %s is empty" % ID_LIST)
        return 1
    if not shipped:
        print("FAIL: no item rows found in %s" % DATA_LUA)
        return 1

    bad = [i for i in shipped if i not in client]
    dupes = len(shipped) - len(set(shipped))
    print("data.lua items: %d" % len(shipped))
    print("client ids: %d" % len(client))
    print("not in client: %d" % len(bad))
    if dupes:
        print("duplicate ids: %d" % dupes)
    if bad:
        print("first offenders: %s" % ", ".join(str(i) for i in bad[:20]))
        return 1
    if dupes:
        return 1
    print("ok: every shipped item exists in the Forever client")
    return 0


if __name__ == "__main__":
    sys.exit(main())
