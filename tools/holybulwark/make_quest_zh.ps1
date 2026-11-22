$json = 'D:\opencode_workspace\wow-forever-addons\data\quest_zh.json'
$out = 'D:\opencode_workspace\wow-forever-addons\HolyBulwark\QuestZh.lua'
$j = [System.IO.File]::ReadAllText($json, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
$map = @{}
foreach ($p in $j.PSObject.Properties) { $map[[int]$p.Name] = [string]$p.Value }

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('-- Chinese quest names scraped from forever.damijing.com.')
[void]$sb.AppendLine('local _, ns = ...')
[void]$sb.AppendLine('ns.questZh = {')
foreach ($k in ($map.Keys | Sort-Object { [int]$_ })) {
    [void]$sb.AppendLine(('    [{0}] = "{1}",' -f $k, ($map[$k] -replace '"', '\"')))
}
[void]$sb.AppendLine('}')
[System.IO.File]::WriteAllText($out, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
"entries: $($map.Count) -> $out"
