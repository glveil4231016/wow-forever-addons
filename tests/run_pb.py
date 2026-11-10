import os
import sys

from lupa import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = os.path.join(ROOT, "ProfitBoard")
TESTS = os.path.join(ROOT, "tests")

FILES = [
    "Core.lua", "Profile.lua", "Config.lua", "Util.lua", "Market.lua",
    "StaticRecipes.lua", "RecipeSource.lua", "Cost.lua", "Compute.lua",
    "UI.lua", "Export.lua", "Slash.lua",
]

lua = LuaRuntime(unpack_returned_tuples=True)
loader = lua.eval(
    "function(src, name, ns) local f = assert((loadstring or load)(src, name)); f(name, ns) end"
)
ns = lua.table()


def load_file(path):
    with open(path, "r", encoding="utf-8") as fh:
        loader(fh.read(), os.path.basename(path), ns)


load_file(os.path.join(TESTS, "stub_pb.lua"))
for name in FILES:
    path = os.path.join(ADDON, name)
    if os.path.exists(path):
        load_file(path)

test_files = sorted(
    f for f in os.listdir(TESTS) if f.startswith("test_") and f.endswith(".lua")
)
for name in test_files:
    load_file(os.path.join(TESTS, name))

fails = ns.Test.report()
print("test files: %d" % len(test_files))
sys.exit(1 if fails else 0)
