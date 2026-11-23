"""Dump the Forever client's ItemSparse ids into tests/data/forever_item_ids.txt.

    python tools/holybulwark/dump_item_ids.py data/ItemSparse_zhCN.csv

Run this in the same commit as a rebuilt Data.lua when the client build changes.
"""

import csv
import io
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "tests", "data", "forever_item_ids.txt")


def main():
    if len(sys.argv) < 2:
        print(__doc__.strip())
        return 2
    ids = []
    with io.open(sys.argv[1], encoding="utf-8-sig", newline="") as fh:
        for row in csv.DictReader(fh):
            if row.get("ID"):
                ids.append(int(row["ID"]))
    ids = sorted(set(ids))
    if not ids:
        print("no ids in %s" % sys.argv[1])
        return 1
    lines = [
        "# Forever client ItemSparse ids -- build 1.60.1.71037 (locale zhCN, wago.tools)",
        "# Regenerate together with Data.lua when the client build changes.",
        "# count: %d" % len(ids),
    ]
    lines += [str(i) for i in ids]
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with io.open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")
    print("wrote %d ids to %s" % (len(ids), OUT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
