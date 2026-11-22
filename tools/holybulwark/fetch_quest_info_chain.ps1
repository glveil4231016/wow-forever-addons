$ErrorActionPreference = 'Continue'
$data = 'D:\opencode_workspace\wow-forever-addons\data'
$ProgressPreference = 'SilentlyContinue'
$path = Join-Path $data 'quest_info.json'
$info = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
$map = @{}
foreach ($p in $info.PSObject.Properties) { $map[[int]$p.Name] = $p.Value }

$ids = @{}
foreach ($p in $info.PSObject.Properties) { foreach ($c in @($p.Value.chain)) { $ids[[int]$c] = $true } }
$missing = @($ids.Keys | Where-Object { -not $map.ContainsKey($_) })
"missing chain quests: $($missing.Count)"

foreach ($id in $missing) {
    $url = $null
    try {
        $j = (Invoke-WebRequest ("https://warcraftmaps.com/api/search?q={0}&limit=5" -f $id) -UseBasicParsing -TimeoutSec 30).Content | ConvertFrom-Json
        foreach ($g in $j.groups) { foreach ($hit in $g.hits) { if ($hit.type -eq 'quest' -and $hit.gameId -eq [string]$id) { $url = 'https://warcraftmaps.com' + $hit.url } } }
    } catch {}
    if (-not $url) { continue }
    $h = $null
    for ($try = 0; $try -lt 3 -and -not $h; $try++) {
        try { $h = (Invoke-WebRequest $url -UseBasicParsing -TimeoutSec 30).Content } catch { $h = $null }
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

    $giver = $null; $x = $null; $y = $null
    if ($h -match '(?s)Start.{0,3000}?/npc/(\d+)') {
        $giver = [int]$Matches[1]
        $pos = $h.IndexOf("/npc/$giver")
        if ($pos -gt 0) {
            $seg2 = $h.Substring([Math]::Max(0, $pos - 200), [Math]::Min(800, $h.Length - [Math]::Max(0, $pos - 200)))
            $cm = [regex]::Match($seg2, '(\d{1,2}\.\d)\s*,\s*(\d{1,2}\.\d)')
            if ($cm.Success) { $x = [double]$cm.Groups[1].Value; $y = [double]$cm.Groups[2].Value }
        }
    }
    $item = $null
    if (-not $giver -and $h -match '(?s)Start.{0,3000}?/item/(\d+)') { $item = [int]$Matches[1] }

    $map[[string]$id] = @{
        level = [int]$level; giver = $giver; item = $item; x = $x; y = $y; chain = $chain
    }
}
$out = @{}
foreach ($k in $map.Keys) { $out[[string]$k] = $map[$k] }
[System.IO.File]::WriteAllText($path, ($out | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))
"total quest info: $($out.Count)"
