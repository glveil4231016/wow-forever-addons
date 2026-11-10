import os

from lupa import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

lua = LuaRuntime(unpack_returned_tuples=True)
compile_lua = lua.eval(
    "function(src, name) local f, err = (loadstring or load)(src, name); "
    "if not f then error(err) end; return true end"
)

files = []
for folder in ("ProfitBoard", "ProfitProbe"):
    path = os.path.join(ROOT, folder)
    for name in sorted(os.listdir(path)):
        if name.endswith(".lua"):
            files.append(os.path.join(path, name))

for path in files:
    with open(path, "r", encoding="utf-8") as fh:
        compile_lua(fh.read(), os.path.basename(path))

print("syntax ok: %d files" % len(files))
