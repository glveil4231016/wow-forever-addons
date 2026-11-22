$ErrorActionPreference = 'Continue'
$data = 'D:\opencode_workspace\wow-forever-addons\data'
$ProgressPreference = 'SilentlyContinue'
$out = Join-Path $data 'quest_info.json'

$lua = [System.IO.File]::ReadAllText('D:\opencode_workspace\wow-forever-addons\HolyBulwark\Data.lua', [System.Text.Encoding]::UTF8)
$pairs = [regex]::Matches($lua, '\{"quest","((?:[^"\\]|\\.)*)","(?:[^"\\]|\\.)*",[^,]*,"(\d+)"')
$names = @{}
foreach ($m in $pairs) {
    $id = [int]$m.Groups[2].Value
    if (-not $names.ContainsKey($id)) { $names[$id] = $m.Groups[1].Value }
}
"quests: $($names.Count)"

function Slug([string]$s) {
    $x = $s.ToLowerInvariant() -replace "'", '' -replace '[^a-z0-9]+', '-' -replace '^-|-$', ''
    return $x
}

$result = @{}
foreach ($id in $names.Keys) {
    $url = 'https://warcraftmaps.com/quest/{0}/{1}' -f $id, (Slug $names[$id])
    $h = $null
    for ($try = 0; $try -lt 3 -and -not $h; $try++) {
        try { $h = (Invoke-WebRequest $url -UseBasicParsing -TimeoutSec 30).Content } catch { $h = $null }
    }
    if (-not $h) {
        try {
            $j = (Invoke-WebRequest ("https://warcraftmaps.com/api/search?q={0}&limit=5" -f $id) -UseBasicParsing -TimeoutSec 30).Content | ConvertFrom-Json
            $url = $null
            foreach ($g in $j.groups) { foreach ($hit in $g.hits) { if ($hit.type -eq 'quest' -and $hit.gameId -eq [string]$id) { $url = 'https://warcraftmaps.com' + $hit.url } } }
            if ($url) { $h = (Invoke-WebRequest $url -UseBasicParsing -TimeoutSec 30).Content }
        } catch {}
    }
    if (-not $h) { continue }

    $d = [regex]::Match($h, 'name="description" content="([^"]*)"').Groups[1].Value
    $level = [regex]::Match($d, 'level (\d+)').Groups[1].Value

    $chain = @()
    $ci = $h.IndexOf('Quest chain')
    if ($ci -gt 0) {
        $seg = $h.Substring($ci, [Math]::Min(12000, $h.Length - $ci))
        foreach ($m in [regex]::Matches($seg, '/quest/(\d+)')) {
            $v = [int]$m.Groups[1].Value
            if ($chain -notcontains $v) { $chain += $v }
        }
    }
    if ($chain -notcontains $id) { $chain += $id }

    $giver = ''
    $coordX = $null
    $coordY = $null
    if ($h -match '(?s)Start.{0,3000}?/npc/(\d+)') {
        $giver = [int]$Matches[1]
        $pos = $h.IndexOf("/npc/$giver")
        if ($pos -gt 0) {
            $seg2 = $h.Substring([Math]::Max(0, $pos - 200), [Math]::Min(800, $h.Length - [Math]::Max(0, $pos - 200)))
            $cm = [regex]::Match($seg2, '(\d{1,2}\.\d)\s*,\s*(\d{1,2}\.\d)')
            if ($cm.Success) { $coordX = [double]$cm.Groups[1].Value; $coordY = [double]$cm.Groups[2].Value }
        }
    }
    $itemID = ''
    if (-not $giver -and $h -match '(?s)Start.{0,3000}?/item/(\d+)') { $itemID = [int]$Matches[1] }

    $result[[string]$id] = @{
        level = [int]$level
        giver = if ($giver) { [int]$giver } else { $null }
        item = if ($itemID) { [int]$itemID } else { $null }
        x = $coordX
        y = $coordY
        chain = $chain
    }
}
[System.IO.File]::WriteAllText($out, ($result | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))
"parsed: $($result.Count) / $($names.Count)"
