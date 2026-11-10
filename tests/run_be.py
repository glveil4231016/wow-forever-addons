import os
import sys

PYLIB = r"D:\文档\Trae-CN\temp_20261026_01\_dev_tests\pylib"
ADDON = r"F:\opencode_workspace\wow-addon\BlackEvidence"
STUB = r"F:\opencode_workspace\wow-addon\tests\stub_be.lua"

FILES = [
    "Core.lua", "Profile.lua", "Config.lua", "Logger.lua", "Util.lua",
    "Identity.lua", "Blacklist.lua", "Timeline.lua", "Trigger.lua",
    "Comms.lua", "Export.lua", "NoteDialog.lua", "ManagerUI.lua",
    "Menu.lua", "Slash.lua",
]

CHECKS = [
    ("addonName",        'return tostring(BE.addonName)'),
    ("profile.id",       'return tostring(BE.Profile.id)'),
    ("profile.label",    'return tostring(BE.Profile.label)'),
    ("interface",        'return tostring(BE.Profile.interface)'),
    ("caps.surname",     'return tostring(BE.Profile.Cap("surname"))'),
    ("caps.sendChat",    'return tostring(BE.Profile.Cap("sendChat"))'),
    ("identity.key",     'local i = BE.Identity.Unit("player"); return tostring(i and i.key)'),
    ("blacklist.add",    'local i = BE.Identity.Unit("player"); local e, n = BE.Blacklist.Add(i, "抢装备后退队", "test"); return tostring(n) .. "/" .. tostring(BE.Blacklist.Count())'),
    ("export.list",      'local t = BE.Export.List(BE.Profile.id); return tostring(#t) .. "/" .. tostring(t:find("#BE-LIST v2", 1, true) ~= nil)'),
    ("trigger.fire",     'local i = BE.Identity.Unit("player"); local r = BE.Trigger.Fire("BLACKLIST_ADD", i, "抢装备后退队"); return tostring(r and #r.id)'),
    ("timeline",         'BE.Timeline.Mark("smoke"); return tostring(BE.Timeline.Count())'),
    ("log.dump",         'return tostring(#BE.Log.Dump(3))'),
    ("comms.status",     'return tostring(#tostring(BE.Comms.Status()))'),
    ("menu.report",      'return tostring(#tostring(BE.Menu.LiveReport()))'),
    ("ui.api",           'return tostring(type(BE.UI)) .. "/" .. tostring(type(BE.UI and BE.UI.OpenNote))'),
    ("slash.api",        'return tostring(type(BE.Slash)) .. "/" .. tostring(type(SlashCmdList["BLACKEVIDENCE"]))'),
    ("pack.text",        'local r = BE.Trigger.List()[1]; return tostring(#(BE.Export.Pack(r and r.id) or ""))'),
]

def main():
    sys.path.insert(0, PYLIB)
    import lupa.lua51 as lupa

    L = lupa.LuaRuntime(unpack_returned_tuples=True)
    L.execute(open(STUB, encoding="utf-8").read())
    L.execute("BE = {}")

    for name in FILES:
        path = os.path.join(ADDON, name).replace("\\", "/")
        try:
            L.execute('local chunk = assert(loadfile("%s")); chunk("BlackEvidence", BE)' % path)
        except Exception as e:
            print("LOAD FAIL " + name + ": " + str(e))
            return 1
    print("LOAD OK  all 15 files")

    L.execute("BE:InitManual()")
    print("INIT OK  addonName=%s started=%s" % (
        L.eval("tostring(BE.addonName)"), L.eval("tostring(BE.state and BE.state.started)")))

    failures = 0
    for label, code in CHECKS:
        try:
            L.execute("__chk = function() " + code + " end")
            value = L.eval("__chk()")
            print("CHECK OK   %-14s %s" % (label, value))
        except Exception as e:
            failures += 1
            print("CHECK FAIL %-14s %s" % (label, str(e)[:300]))

    try:
        L.execute('BE.Slash.Handle("status")')
        print("SLASH OK   status")
    except Exception as e:
        failures += 1
        print("SLASH FAIL status: %s" % str(e)[:300])

    print("--- failures:", failures)
    return 0 if failures == 0 else 1

if __name__ == "__main__":
    sys.exit(main())
