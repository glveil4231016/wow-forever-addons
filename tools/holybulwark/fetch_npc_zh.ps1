$ErrorActionPreference = 'Continue'
$data = 'D:\opencode_workspace\wow-forever-addons\data'
$ProgressPreference = 'SilentlyContinue'
$lua = [System.IO.File]::ReadAllText('D:\opencode_workspace\wow-forever-addons\HolyBulwark\Data.lua', [System.Text.Encoding]::UTF8)
$ids = [regex]::Matches($lua, '\{"drop","(?:[^"\\]|\\.)*","(?:[^"\\]|\\.)*",[^,]*,"(?:[^"\\]|\\.)*",nil,nil,nil,nil,nil,nil,nil,nil,(\d+)\}') |
    ForEach-Object { [int]$_.Groups[1].Value } | Sort-Object -Unique
"drop npc ids: $($ids.Count)"

$result = @{}
$ok = 0
foreach ($id in $ids) {
    try {
        $h = (Invoke-WebRequest "https://forever.damijing.com/npc/$id" -UseBasicParsing -TimeoutSec 30).Content
        $title = [regex]::Match($h, '<title>(.*?)</title>').Groups[1].Value
        $name = ($title -replace 'NPC-.*$', '').Trim()
        if ($name -and $name -notmatch 'NPC不存在|404|错误|未知' -and $name -notmatch '^\s*$') {
            $result[[string]$id] = $name
            $ok++
        }
    } catch {
    }
}
[System.IO.File]::WriteAllText((Join-Path $data 'npc_zh.json'), ($result | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false)))
"fetched names: $ok / $($ids.Count)"
$result.GetEnumerator() | Select-Object -First 5 | ForEach-Object { "$($_.Key) => $($_.Value)" }
