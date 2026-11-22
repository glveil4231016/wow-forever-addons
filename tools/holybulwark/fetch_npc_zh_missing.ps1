$ErrorActionPreference = 'Continue'
$data = 'D:\opencode_workspace\wow-forever-addons\data'
$ProgressPreference = 'SilentlyContinue'
$lua = [System.IO.File]::ReadAllText('D:\opencode_workspace\wow-forever-addons\HolyBulwark\Data.lua', [System.Text.Encoding]::UTF8)
$ids = [regex]::Matches($lua, '\{"drop","(?:[^"\\]|\\.)*","(?:[^"\\]|\\.)*",[^,]*,"(?:[^"\\]|\\.)*",nil,nil,nil,nil,nil,nil,nil,nil,(\d+)\}') |
    ForEach-Object { [int]$_.Groups[1].Value } | Sort-Object -Unique
$path = Join-Path $data 'npc_zh.json'
$result = @{}
if (Test-Path $path) {
    $old = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    foreach ($p in $old.PSObject.Properties) { $result[$p.Name] = [string]$p.Value }
}
$missing = @($ids | Where-Object { -not $result.ContainsKey([string]$_) })
"missing before: $($missing.Count)"
$ok = 0
foreach ($id in $missing) {
    $name = ''
    for ($try = 0; $try -lt 3 -and -not $name; $try++) {
        try {
            $h = (Invoke-WebRequest "https://forever.damijing.com/npc/$id" -UseBasicParsing -TimeoutSec 30).Content
            $title = [regex]::Match($h, '<title>(.*?)</title>').Groups[1].Value
            $n = ($title -replace 'NPC-.*$', '').Trim()
            if ($n -and $n -notmatch 'NPC不存在|404|错误|未知|^$') { $name = $n }
        } catch {
        }
    }
    if ($name) {
        $result[[string]$id] = $name
        $ok++
    }
}
[System.IO.File]::WriteAllText($path, ($result | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false)))
"added: $ok total: $($result.Count) / $($ids.Count)"
