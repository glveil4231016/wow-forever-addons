$src = 'D:\game\World of Warcraft\_forever_\Interface\AddOns\QuestieDB\support\Forever\Zones\areaIdToUiMapId.lua'
$out = 'D:\opencode_workspace\wow-forever-addons\HolyBulwark\MapIds.lua'

$lines = Get-Content $src
$base = @{}
$over = @{}
$section = ''
foreach ($line in $lines) {
    if ($line -match 'areaIdToUiMapIdOverride\s*=') { $section = 'over'; continue }
    if ($line -match 'areaIdToUiMapId\s*=') { $section = 'base'; continue }
    if ($line -match '^\s*\[(\d+)\]\s*=\s*(\d+),') {
        $a = [int]$Matches[1]; $m = [int]$Matches[2]
        if ($section -eq 'over') { $over[$a] = $m } else { $base[$a] = $m }
    }
}
foreach ($k in $over.Keys) { $base[$k] = $over[$k] }

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('-- AreaTable AreaID -> UiMapID, generated from QuestieDB Forever support data.')
[void]$sb.AppendLine('-- Used for quest-giver map pins.')
[void]$sb.AppendLine('local _, ns = ...')
[void]$sb.AppendLine('ns.areaToMap = {')
foreach ($k in ($base.Keys | Sort-Object { [int]$_ })) {
    [void]$sb.AppendLine(('    [{0}] = {1},' -f $k, $base[$k]))
}
[void]$sb.AppendLine('}')

$area = Import-Csv 'D:\opencode_workspace\wow-forever-addons\data\AreaTable_zhCN.csv' -Encoding UTF8
$zoneToMap = @{}
foreach ($r in $area) {
    $id = [int]$r.ID
    if ($base.ContainsKey($id) -and $r.AreaName_lang) {
        $zoneToMap[$r.AreaName_lang] = $base[$id]
    }
}
[void]$sb.AppendLine('ns.zoneToMap = {')
foreach ($k in ($zoneToMap.Keys | Sort-Object)) {
    [void]$sb.AppendLine(('    ["{0}"] = {1},' -f ($k -replace '"', '\"'), $zoneToMap[$k]))
}
[void]$sb.AppendLine('}')
[System.IO.File]::WriteAllText($out, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
"entries: $($base.Count) -> $out ($((Get-Item $out).Length) bytes)"
