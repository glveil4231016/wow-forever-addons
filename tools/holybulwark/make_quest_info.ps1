$json = 'D:\opencode_workspace\wow-forever-addons\data\quest_info.json'
$out = 'D:\opencode_workspace\wow-forever-addons\HolyBulwark\QuestInfo.lua'
$j = [System.IO.File]::ReadAllText($json, [System.Text.Encoding]::UTF8) | ConvertFrom-Json

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('-- Quest level / giver / chain, scraped from WarcraftMaps (Forever snapshot).')
[void]$sb.AppendLine('local _, ns = ...')
[void]$sb.AppendLine('ns.questInfo = {')
foreach ($p in ($j.PSObject.Properties | Sort-Object { [int]$_.Name })) {
    $v = $p.Value
    $parts = @()
    $parts += ('level = ' + [int]$v.level)
    if ($null -ne $v.giver -and $v.giver) { $parts += ('giver = ' + [int]$v.giver) }
    if ($null -ne $v.item -and $v.item) { $parts += ('item = ' + [int]$v.item) }
    if ($null -ne $v.x -and $v.x) {
        $inv = [System.Globalization.CultureInfo]::InvariantCulture
        $parts += ('x = ' + ([double]$v.x).ToString($inv))
        $parts += ('y = ' + ([double]$v.y).ToString($inv))
    }
    if ($v.chain -and @($v.chain).Count -gt 0) {
        $parts += ('chain = {' + ((@($v.chain) | ForEach-Object { [int]$_ }) -join ',') + '}')
    }
    [void]$sb.AppendLine(('    [{0}] = {{ {1} }},' -f [int]$p.Name, ($parts -join ', ')))
}
[void]$sb.AppendLine('}')
[System.IO.File]::WriteAllText($out, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
"entries: $($j.PSObject.Properties.Count) -> $out"
