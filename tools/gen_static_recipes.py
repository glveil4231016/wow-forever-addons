"""Generate ProfitBoard/StaticRecipes.lua from a recipe export.

Input formats (auto-detected by extension):

1) JSON
   {
     "version": "1.60.1-20261110",
     "recipes": [
       {"id": 1234, "profession": "Alchemy", "name": "治疗药水",
        "result": {"itemID": 929, "count": 1},
        "reagents": [{"itemID": 2455, "count": 1}, {"itemID": 2454, "count": 1}],
        "level": 60}
     ]
   }

2) CSV (one row per reagent, repeated recipe columns)
   recipeID,profession,name,resultID,resultCount,reagentID,reagentCount,level

Usage:
    python tools/gen_static_recipes.py <input.json|input.csv> [--out PATH]

Output keeps itemIDs even when names are missing; names are optional.
"""

import argparse
import csv
import json
import os
import sys


def lua_string(value):
    if value is None:
        return '""'
    text = str(value)
    text = text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ")
    return '"' + text + '"'


def normalize(recipe, dropped):
    try:
        rid = int(recipe.get("id"))
    except (TypeError, ValueError):
        dropped["no recipe id"] += 1
        return None

    result = recipe.get("result") or {}
    try:
        result_id = int(result.get("itemID"))
    except (TypeError, ValueError):
        dropped["no result itemID"] += 1
        return None
    try:
        result_count = int(result.get("count") or 1)
    except (TypeError, ValueError):
        result_count = 1
    if result_count <= 0:
        result_count = 1

    reagents = []
    for re in recipe.get("reagents") or []:
        try:
            item_id = int(re.get("itemID"))
        except (TypeError, ValueError):
            dropped["invalid reagent id"] += 1
            continue
        try:
            count = int(re.get("count") or 1)
        except (TypeError, ValueError):
            count = 1
        if count <= 0:
            continue
        reagents.append({"itemID": item_id, "count": count})

    if not reagents:
        dropped["no reagents"] += 1
        return None

    out = {
        "id": rid,
        "profession": recipe.get("profession") or "",
        "name": recipe.get("name") or "",
        "result": {"itemID": result_id, "count": result_count},
        "reagents": reagents,
    }
    level = recipe.get("level")
    if level is not None:
        try:
            out["level"] = int(level)
        except (TypeError, ValueError):
            pass
    return out


def read_json(path):
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
    recipes = data.get("recipes") if isinstance(data, dict) else data
    return (data.get("version") if isinstance(data, dict) else None), recipes or []


def read_csv(path):
    recipes = {}
    with open(path, "r", encoding="utf-8-sig", newline="") as fh:
        for row in csv.DictReader(fh):
            rid = (row.get("recipeID") or "").strip()
            if not rid:
                continue
            entry = recipes.get(rid)
            if entry is None:
                entry = {
                    "id": int(rid),
                    "profession": (row.get("profession") or "").strip(),
                    "name": (row.get("name") or "").strip(),
                    "result": {
                        "itemID": int((row.get("resultID") or "0").strip() or 0),
                        "count": int((row.get("resultCount") or "1").strip() or 1),
                    },
                    "reagents": [],
                }
                if row.get("level"):
                    entry["level"] = row["level"].strip()
                recipes[rid] = entry
            reagent_id = (row.get("reagentID") or "").strip()
            if reagent_id:
                entry["reagents"].append({
                    "itemID": int(reagent_id),
                    "count": int((row.get("reagentCount") or "1").strip() or 1),
                })
    return None, list(recipes.values())


def render(version, recipes):
    lines = [
        "local ADDON, PB = ...",
        "PB.StaticRecipes = {",
        "  version = %s," % lua_string(version),
        "  recipes = {",
    ]
    for r in recipes:
        parts = [
            "id = %d" % r["id"],
            "profession = %s" % lua_string(r["profession"]),
            "name = %s" % lua_string(r["name"]),
            "result = { itemID = %d, count = %d }" % (r["result"]["itemID"], r["result"]["count"]),
        ]
        if "level" in r:
            parts.append("level = %d" % r["level"])
        reagent_parts = []
        for re in r["reagents"]:
            reagent_parts.append("{ itemID = %d, count = %d }" % (re["itemID"], re["count"]))
        parts.append("reagents = { %s }" % ", ".join(reagent_parts))
        lines.append("    { " + ", ".join(parts) + " },")
    lines.extend(["  },", "}", ""])
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("source", help="input .json or .csv")
    parser.add_argument("--out", default=os.path.join("ProfitBoard", "StaticRecipes.lua"))
    parser.add_argument("--version", default=None)
    args = parser.parse_args()

    if not os.path.exists(args.source):
        print("input not found: %s" % args.source, file=sys.stderr)
        return 2

    with open(args.source, "rb") as fh:
        head = fh.read(4096).lstrip()
    is_json = head.startswith(b"{") or args.source.lower().endswith(".json")

    version, raw = read_json(args.source) if is_json else read_csv(args.source)
    version = args.version or version or "unversioned"

    dropped = {
        "no recipe id": 0,
        "no result itemID": 0,
        "no reagents": 0,
        "invalid reagent id": 0,
    }
    cleaned = []
    for recipe in raw:
        item = normalize(recipe, dropped)
        if item:
            cleaned.append(item)

    text = render(version, cleaned)
    with open(args.out, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)

    print("wrote %s" % args.out)
    print("version=%s recipes=%d" % (version, len(cleaned)))
    for key, value in dropped.items():
        if value:
            print("dropped %s: %d" % (key, value))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
