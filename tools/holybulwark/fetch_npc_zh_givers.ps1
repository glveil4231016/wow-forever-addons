$ErrorActionPreference = 'Continue'
$data = 'D:\opencode_workspace\wow-forever-addons\data'
$ProgressPreference = 'SilentlyContinue'
$path = Join-Path $data 'npc_zh.json'
$zh = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
$map = @{}
foreach ($p in $zh.PSObject.Properties) { $map[[int]$p.Name] = [string]$p.Value }

$info = [System.IO.File]::ReadAllText((Join-Path $data 'quest_info.json'), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
$ids = @{}
foreach ($p in $info.PSObject.Properties) { if ($p.Value.giver) { $ids[[int]$p.Value.giver] = $true } }
$missing = @($ids.Keys | Where-Object { -not $map.ContainsKey($_) })
"missing quest givers: $($missing.Count)"

foreach ($id in $missing) {
    for ($try = 0; $try -lt 3; $try++) {
        try {
            $h = (Invoke-WebRequest "https://forever.damijing.com/npc/$id" -UseBasicParsing -TimeoutSec 30).Content
            $title = [regex]::Match($h, '<title>(.*?)</title>').Groups[1].Value
            $name = ($title -replace 'NPC-.*$', '').Trim()
            if ($name -and $name -notmatch 'NPC不存在|404|错误|未知|^$') { $map[$id] = $name; break }
        } catch {
        }
    }
}
$out = @{}
foreach ($k in $map.Keys) { $out[[string]$k] = $map[$k] }
[System.IO.File]::WriteAllText($path, ($out | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false)))
"total npc names: $($out.Count)"
