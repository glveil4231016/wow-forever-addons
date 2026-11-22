$dir = 'D:\opencode_workspace\wow-forever-addons\HolyBulwark'
$files = @('Data.lua', 'MapIds.lua', 'NpcZh.lua', 'NpcLoc.lua', 'QuestZh.lua', 'QuestInfo.lua', 'QuestFull.lua', 'RecipeVendor.lua', 'RecipeDrop.lua', 'Core.lua', 'Tooltip.lua', 'UI.lua')
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('<!doctype html><html><head><meta charset="utf-8"><title>Lua syntax check</title></head><body><pre id="out">running...</pre>')
[void]$sb.AppendLine('<script src="fengari.js"></script>')
foreach ($f in $files) {
    $t = [System.IO.File]::ReadAllText((Join-Path $dir $f), [System.Text.Encoding]::UTF8)
    [void]$sb.AppendLine('<script type="text/plain" id="lua-' + $f + '">')
    [void]$sb.AppendLine($t)
    [void]$sb.AppendLine('</script>')
}
$js = @'
<script>
window.__results = [];
document.querySelectorAll('script[type="text/plain"]').forEach(function(el){
  try {
    var L = fengari.lauxlib.luaL_newstate();
    var status = fengari.lauxlib.luaL_loadstring(L, fengari.to_luastring(el.textContent));
    var err = status === 0 ? '' : fengari.lua.lua_tojsstring(L, -1);
    window.__results.push({id: el.id, status: status, err: err});
  } catch(e) { window.__results.push({id: el.id, status: -1, err: String(e)}); }
});
document.getElementById('out').textContent = JSON.stringify(window.__results, null, 2);
</script>
'@
[void]$sb.AppendLine($js)
[void]$sb.AppendLine('</body></html>')
[System.IO.File]::WriteAllText('D:\opencode_workspace\wow-forever-addons\tools\holybulwark\syntax-check.html', $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
"written $((Get-Item 'D:\opencode_workspace\wow-forever-addons\tools\holybulwark\syntax-check.html').Length)"
