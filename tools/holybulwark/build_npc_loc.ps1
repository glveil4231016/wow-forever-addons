$ErrorActionPreference = 'Continue'
$toc = 'D:\game\World of Warcraft\_forever_\Interface\AddOns\QuestieDB\QuestieDB_Forever.toc'
$data = 'D:\opencode_workspace\wow-forever-addons\data'
$out = 'D:\opencode_workspace\wow-forever-addons\HolyBulwark\NpcLoc.lua'
$script:pos = 0

function Read-Len([byte[]]$b, [int]$add) {
    if ($add -lt 24) { return [long]$add }
    if ($add -eq 24) { $v = $b[$script:pos]; $script:pos++; return [long]$v }
    if ($add -eq 25) { $v = ([long]$b[$script:pos] -shl 8) -bor $b[$script:pos + 1]; $script:pos += 2; return $v }
    if ($add -eq 26) { $v = ([long]$b[$script:pos] -shl 24) -bor ([long]$b[$script:pos + 1] -shl 16) -bor ([long]$b[$script:pos + 2] -shl 8) -bor $b[$script:pos + 3]; $script:pos += 4; return $v }
    return 0
}

function Read-Value([byte[]]$b) {
    $initial = $b[$script:pos]; $script:pos++
    $major = $initial -shr 5
    $add = $initial -band 0x1F
    switch ($major) {
        0 { return (Read-Len $b $add) }
        1 { return -1 - (Read-Len $b $add) }
        2 {
            $n = Read-Len $b $add
            $s = [System.Text.Encoding]::UTF8.GetString($b, $script:pos, [int]$n)
            $script:pos += $n
            return $s
        }
        3 {
            $n = Read-Len $b $add
            $s = [System.Text.Encoding]::UTF8.GetString($b, $script:pos, [int]$n)
            $script:pos += $n
            return $s
        }
        4 {
            $n = Read-Len $b $add
            $arr = @()
            for ($i = 0; $i -lt $n; $i++) { $arr += ,(Read-Value $b) }
            return ,$arr
        }
        5 {
            $n = Read-Len $b $add
            $map = @{}
            for ($i = 0; $i -lt $n; $i++) {
                $k = Read-Value $b
                $v = Read-Value $b
                if ($null -ne $k) { $map[[string]$k] = $v }
            }
            return $map
        }
        6 { $null = Read-Len $b $add; return (Read-Value $b) }
        7 {
            if ($add -eq 20 -or $add -eq 21) { return $null }
            if ($add -eq 26) { $script:pos += 4; return 0 }
            if ($add -eq 27) { $script:pos += 8; return 0 }
            if ($add -eq 25) { $script:pos += 2; return 0 }
            return $null
        }
    }
    return $null
}

function Read-Float([byte[]]$b) {
    if ($b[$script:pos] -eq 0xFB) {
        $tmp = New-Object byte[] 8
        [Array]::Copy($b, $script:pos + 1, $tmp, 0, 8)
        [Array]::Reverse($tmp)
        $script:pos += 9
        return [BitConverter]::ToDouble($tmp, 0)
    }
    if ($b[$script:pos] -eq 0xFA) {
        $tmp = New-Object byte[] 4
        [Array]::Copy($b, $script:pos + 1, $tmp, 0, 4)
        [Array]::Reverse($tmp)
        $script:pos += 5
        return [BitConverter]::ToSingle($tmp, 0)
    }
    return 0
}

$linesById = @{}
foreach ($line in [System.IO.File]::ReadLines($toc)) {
    if ($line -match '^## X-Npc-(\d+)-([S7]):\s*(\S+)') {
        $id = [int]$Matches[1]
        if (-not $linesById.ContainsKey($id)) { $linesById[$id] = @{} }
        $linesById[$id][$Matches[2]] = $Matches[3]
    }
}

$ids = @{}
$zh = [System.IO.File]::ReadAllText((Join-Path $data 'npc_zh.json'), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
foreach ($p in $zh.PSObject.Properties) { $ids[[int]$p.Name] = $true }

$result = @{}
foreach ($id in $ids.Keys) {
    if (-not $linesById.ContainsKey($id)) { continue }
    $zone = 0
    $spots = @()
    if ($linesById[$id].ContainsKey('S')) {
        try {
            $bytes = [Convert]::FromBase64String($linesById[$id]['S'])
            $script:pos = 0
            $m = Read-Value $bytes
            if ($m -and $m.ContainsKey('9')) { $zone = [int]$m['9'] }
        } catch {}
    }
    if ($linesById[$id].ContainsKey('7')) {
        try {
            $b = [Convert]::FromBase64String($linesById[$id]['7'])
            $script:pos = 0
            if ($b[0] -eq 0xA1) {
                $script:pos = 1
                $add = $b[$script:pos] -band 0x1F
                $script:pos++
                if ($add -eq 24) { $zoneFrom7 = [int]$b[$script:pos]; $script:pos++ }
                elseif ($add -eq 25) { $zoneFrom7 = ([int]$b[$script:pos] -shl 8) -bor $b[$script:pos + 1]; $script:pos += 2 }
                else { $zoneFrom7 = [int]$add }
                if (-not $zone) { $zone = $zoneFrom7 }
                $arrHead = $b[$script:pos]; $script:pos++
                $count = $arrHead -band 0x1F
                for ($i = 0; $i -lt $count; $i++) {
                    $spotHead = $b[$script:pos]; $script:pos++
                    $n = $spotHead -band 0x1F
                    $coord = @()
                    for ($j = 0; $j -lt $n; $j++) { $coord += Read-Float $b }
                    if ($coord.Count -ge 2 -and [double]$coord[0] -gt 0 -and [double]$coord[1] -gt 0) { $spots += ,@([double]$coord[0], [double]$coord[1]) }
                    if ($spots.Count -ge 3) { break }
                }
            }
        } catch {}
    }
    if ($spots.Count -gt 0) {
        $result[[string]$id] = @{ zone = $zone; spots = $spots }
    }
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('-- NPC spawn coordinates from QuestieDB Forever metadata (first 3 spawns, 0-100 scale).')
[void]$sb.AppendLine('local _, ns = ...')
[void]$sb.AppendLine('ns.npcLoc = {')
foreach ($k in ($result.Keys | Sort-Object { [int]$_ })) {
    $e = $result[$k]
    $parts = @()
    foreach ($sp in $e.spots) {
        $x = ([double]$sp[0]).ToString('0.##', [System.Globalization.CultureInfo]::InvariantCulture)
        $y = ([double]$sp[1]).ToString('0.##', [System.Globalization.CultureInfo]::InvariantCulture)
        $parts += ('{' + $x + ',' + $y + '}')
    }
    [void]$sb.AppendLine(('    [{0}] = {{ zone = {1}, spots = {{{2}}} }},' -f $k, $e.zone, ($parts -join ',')))
}
[void]$sb.AppendLine('}')
[System.IO.File]::WriteAllText($out, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
"npc loc entries: $($result.Count) -> $out"
