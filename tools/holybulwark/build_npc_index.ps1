$toc = 'D:\game\World of Warcraft\_forever_\Interface\AddOns\QuestieDB\QuestieDB_Forever.toc'
$out = 'D:\opencode_workspace\wow-forever-addons\data\npc_index.json'
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

$nameToId = @{}
$dupes = 0
$count = 0
foreach ($line in [System.IO.File]::ReadLines($toc)) {
    if ($line -notmatch '^## X-Npc-(\d+)-S:\s*(\S+)') { continue }
    $id = [int]$Matches[1]
    $b64 = $Matches[2]
    try {
        $bytes = [Convert]::FromBase64String($b64)
        $script:pos = 0
        $map = Read-Value $bytes
        if ($id -eq 14221) {
            "DEBUG type=$($map.GetType().FullName) keys=$($map.Keys -join ',') v1type=$($map['1'].GetType().FullName) v1=$($map['1'])"
        }
        if ($map -and $map.ContainsKey('1')) {
            $name = [string]$map['1']
            if ($name) {
                if ($nameToId.ContainsKey($name)) { $dupes++ }
                else { $nameToId[$name] = $id }
                $count++
            }
        }
    } catch {
        if ($script:errCount -lt 3) {
            $script:errCount = 1 + [int]$script:errCount
            "ERR npc $id : $($_.Exception.Message)"
        }
    }
}
$nameToId | ConvertTo-Json -Depth 3 | Set-Content -Path $out -Encoding UTF8
"npc entries=$count unique names=$($nameToId.Count) dupes=$dupes"
foreach ($n in @('Ouro', 'Archmage Arugal', 'High Inquisitor Whitemane', 'Commander Althea Ebonlocke', 'Lord Sinslayer')) {
    "$n => $($nameToId[$n])"
}
