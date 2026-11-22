# Generate HolyBulwark/QuestFull.lua from Completao's generated Forever quest data.
#
# Completao path:
#   D:\game\World of Warcraft\_forever_\Interface\AddOns\Completao
# The caller first exports Data/**/*.lua to data/completao_quests.json with a small
# Lua harness (see the comment block at the bottom of this file).
#
# Only quests reachable from the gear database's quest rewards are kept, together
# with all prerequisite and follow-up quests.

$ErrorActionPreference = 'Stop'
$dataDir = 'D:\opencode_workspace\spellpower-db\data'
$outFile = 'D:\opencode_workspace\wow-forever-addons\HolyBulwark\QuestFull.lua'

$quests = Get-Content (Join-Path $dataDir 'completao_quests.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$byId = @{}
foreach ($q in $quests) { $byId[[int]$q.id] = $q }

$rev = @{}
foreach ($q in $quests) {
    if ($q.requires) {
        foreach ($r in $q.requires) {
            $ri = [int]$r
            if (-not $rev.ContainsKey($ri)) { $rev[$ri] = New-Object System.Collections.ArrayList }
            [void]$rev[$ri].Add([int]$q.id)
        }
    }
}

$lua = [System.IO.File]::ReadAllText('D:\opencode_workspace\wow-forever-addons\HolyBulwark\Data.lua', [System.Text.Encoding]::UTF8)
$tracked = [regex]::Matches($lua, '\{"quest","(?:[^"\\]|\\.)*","(?:[^"\\]|\\.)*",[^,]*,"(\d+)"') |
    ForEach-Object { [int]$_.Groups[1].Value } | Sort-Object -Unique

$closure = New-Object 'System.Collections.Generic.HashSet[int]'
foreach ($id in $tracked) {
    $stack = New-Object 'System.Collections.Generic.Stack[int]'
    $stack.Push($id)
    while ($stack.Count -gt 0) {
        $x = $stack.Pop()
        if (-not $closure.Add($x)) { continue }
        $q = $byId[$x]
        if ($q -and $q.requires) {
            foreach ($r in $q.requires) {
                $ri = [int]$r
                if (-not $closure.Contains($ri)) { $stack.Push($ri) }
            }
        }
        if ($rev.ContainsKey($x)) {
            foreach ($r in $rev[$x]) {
                $ri = [int]$r
                if (-not $closure.Contains($ri)) { $stack.Push($ri) }
            }
        }
    }
}

function Esc([string]$s) {
    if ($null -eq $s) { return '' }
    return $s.Replace('\', '\\').Replace('"', '\"').Replace("`r", '').Replace("`n", ' ')
}
function LuaStr([string]$s) {
    if ($null -eq $s -or $s -eq '') { return 'nil' }
    return '"' + (Esc $s) + '"'
}
function Loc($o) {
    if ($null -eq $o) { return 'nil' }
    $parts = @()
    if ($o.npc) { $parts += 'n=' + (LuaStr ([string]$o.npc)) }
    if ($null -ne $o.area) { $parts += 'a=' + [int]$o.area }
    if ($null -ne $o.x) { $parts += 'x=' + ([double]$o.x).ToString('0.###', [System.Globalization.CultureInfo]::InvariantCulture) }
    if ($null -ne $o.y) { $parts += 'y=' + ([double]$o.y).ToString('0.###', [System.Globalization.CultureInfo]::InvariantCulture) }
    if ($parts.Count -eq 0) { return 'nil' }
    return '{' + ($parts -join ',') + '}'
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('-- Generated from Completao Data (Forever). Do not edit by hand.')
$lines.Add('-- Only quests reachable from the gear database chains are included.')
$lines.Add('-- Keys: l=level ml=minLevel f=faction cl=classMask d=dungeon s=start e=finish')
$lines.Add('-- st=steps (n=name a=area x y m=mobs) r=requires o=English objective fallback')
$lines.Add('local _, ns = ...')
$lines.Add('ns.questFull = {')

foreach ($id in ($closure | Sort-Object)) {
    $q = $byId[$id]
    if (-not $q) { continue }
    $parts = @()
    if ($q.level) { $parts += 'l=' + [int]$q.level }
    if ($q.minLevel) { $parts += 'ml=' + [int]$q.minLevel }
    if ($q.faction) { $parts += 'f=' + (LuaStr ([string]$q.faction)) }
    if ($q.classes) { $parts += 'cl=' + [int]$q.classes }
    if ($q.dungeon) { $parts += 'd=' + (LuaStr ([string]$q.dungeon)) }
    $s = Loc $q.start; if ($s -ne 'nil') { $parts += 's=' + $s }
    $e = Loc $q.finish; if ($e -ne 'nil') { $parts += 'e=' + $e }
    if ($q.requires) { $parts += 'r={' + (($q.requires | ForEach-Object { [int]$_ }) -join ',') + '}' }
    if ($q.objective) { $parts += 'o=' + (LuaStr ([string]$q.objective)) }
    if ($q.steps) {
        $sts = @()
        foreach ($st in $q.steps) {
            $sp = @()
            if ($st.name) { $sp += 'n=' + (LuaStr ([string]$st.name)) }
            if ($null -ne $st.area) { $sp += 'a=' + [int]$st.area }
            if ($null -ne $st.x) { $sp += 'x=' + ([double]$st.x).ToString('0.###', [System.Globalization.CultureInfo]::InvariantCulture) }
            if ($null -ne $st.y) { $sp += 'y=' + ([double]$st.y).ToString('0.###', [System.Globalization.CultureInfo]::InvariantCulture) }
            if ($st.mobs) { $sp += 'm={' + (($st.mobs | ForEach-Object { LuaStr ([string]$_) }) -join ',') + '}' }
            if ($sp.Count -gt 0) { $sts += '{' + ($sp -join ',') + '}' }
        }
        if ($sts.Count -gt 0) { $parts += 'st={' + ($sts -join ',') + '}' }
    }
    $lines.Add('    [' + $id + '] = {' + ($parts -join ',') + '},')
}

$lines.Add('}')
[System.IO.File]::WriteAllText($outFile, ($lines -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
"quests=$($closure.Count) bytes=$((Get-Item $outFile).Length)"

# Export input (run with a standalone Lua 5.1 interpreter):
#
# local base = "D:/game/World of Warcraft/_forever_/Interface/AddOns/Completao/"
# local files = { "Data/Forever/Dungeons.lua", ... all files from Load_Data_Forever.xml ... }
# local quests, patches = {}, {}
# local ns = { REWARDS = {} }
# ns.RegisterEntry = function() end
# ns.SetEntrance = function() end
# ns.AddQuests = function(entry, list) for _, q in ipairs(list) do if not quests[q.id] then quests[q.id] = q end end end
# ns.PatchQuest = function(id, fields) patches[id] = patches[id] or {}; for k, v in pairs(fields) do patches[id][k] = v end end
# for _, f in ipairs(files) do assert(loadfile(base .. f))("Completao", ns) end
# ... serialize quests to completao_quests.json ...
