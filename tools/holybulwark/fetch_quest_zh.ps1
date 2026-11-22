$ErrorActionPreference = 'Continue'
$data = 'D:\opencode_workspace\wow-forever-addons\data'
$ProgressPreference = 'SilentlyContinue'
$lua = [System.IO.File]::ReadAllText('D:\opencode_workspace\wow-forever-addons\HolyBulwark\Data.lua', [System.Text.Encoding]::UTF8)
$ids = [regex]::Matches($lua, '\{"quest","(?:[^"\\]|\\.)*","(?:[^"\\]|\\.)*",[^,]*,"(\d+)"') |
    ForEach-Object { [int]$_.Groups[1].Value } | Sort-Object -Unique
"quests: $($ids.Count)"

$result = @{}
foreach ($id in $ids) {
    for ($try = 0; $try -lt 3; $try++) {
        try {
            $h = (Invoke-WebRequest "https://forever.damijing.com/quest/$id" -UseBasicParsing -TimeoutSec 30).Content
            $title = [regex]::Match($h, '<title>(.*?)</title>').Groups[1].Value
            $name = ($title -replace '任务详情-.*$', '').Trim()
            if ($name -and $name -notmatch '任务不存在|404|错误|^$') {
                $result[[string]$id] = $name
                break
            }
        } catch {
        }
    }
}
[System.IO.File]::WriteAllText((Join-Path $data 'quest_zh.json'), ($result | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false)))
"names: $($result.Count) / $($ids.Count)"
