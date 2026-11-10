import os

from lupa import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

FOLDERS = ("ProfitBoard", "ProfitProbe", "BlackEvidence")

lua = LuaRuntime(unpack_returned_tuples=True)
compile_lua = lua.eval(
    "function(src, name) local f, err = (loadstring or load)(src, name); "
    "if not f then error(err) end; return true end"
)

files = []
skipped = []
for folder in FOLDERS:
    path = os.path.join(ROOT, folder)
    if not os.path.isdir(path):
        skipped.append(folder)
        continue
    for name in sorted(os.listdir(path)):
        if name.endswith(".lua"):
            files.append(os.path.join(path, name))

failures = []
for path in files:
    try:
        with open(path, "r", encoding="utf-8") as fh:
            compile_lua(fh.read(), os.path.basename(path))
    except Exception as exc:  # noqa: BLE001 - report every file, continue
        failures.append("%s -> %s" % (os.path.relpath(path, ROOT), exc))

print("syntax ok: %d files" % (len(files) - len(failures)))
for folder in skipped:
    print("skipped missing folder: %s" % folder)
for item in failures:
    print("SYNTAX FAIL " + item)

raise SystemExit(1 if failures else 0)
