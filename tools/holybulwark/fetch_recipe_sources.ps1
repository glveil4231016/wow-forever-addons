$ErrorActionPreference = 'Continue'
$data = 'D:\opencode_workspace\wow-forever-addons\data'
$ProgressPreference = 'SilentlyContinue'

$lua = [System.IO.File]::ReadAllText('D:\opencode_workspace\wow-forever-addons\HolyBulwark\Data.lua', [System.Text.Encoding]::UTF8)
$ids = [regex]::Matches($lua, '"craft","[^"]*","[^"]*",[^,]*,"[^"]*",nil,nil,nil,nil,nil,"[^"]*",(\d+)') |
    ForEach-Object { [int]$_.Groups[1].Value } | Sort-Object -Unique | Where-Object { $_ -lt 100000 }

$en = Import-Csv (Join-Path $data 'ItemSparse_enUS.csv') -Encoding UTF8
$nameById = @{}
foreach ($r in $en) { $nameById[[int]$r.ID] = $r.Display_lang }

function Slug([string]$s) {
    $x = $s.ToLowerInvariant() -replace "'", '' -replace '[^a-z0-9]+', '-' -replace '^-|-$', ''
    return $x
}

$result = @{}
$found = 0
foreach ($id in $ids) {
    $name = $nameById[$id]
    if (-not $name) { continue }
    $url = 'https://warcraftmaps.com/item/{0}/{1}' -f $id, (Slug $name)
    try {
        $h = (Invoke-WebRequest $url -UseBasicParsing -TimeoutSec 30).Content
        $i = $h.IndexOf('Sources &amp; evidence')
        if ($i -lt 0) { continue }
        $seg = $h.Substring($i, [Math]::Min(4000, $h.Length - $i))
        $text = ($seg -replace '<[^>]+>', ' ' -replace '\s+', ' ')
        $method = '暂缺'
        if ($text -match 'No verified source') { $method = '暂缺' }
        elseif ($text -match 'Sold by') { $method = '商人出售' }
        elseif ($text -match 'Dropped by' -and $text -match 'Contained in') { $method = '世界掉落/宝箱' }
        elseif ($text -match 'Dropped by') { $method = '怪物掉落' }
        elseif ($text -match 'Contained in') { $method = '宝箱' }
        elseif ($text -match 'Taught by') { $method = '训练师' }
        elseif ($text -match 'Quest') { $method = '任务' }
        $result[[string]$id] = $method
        $found++
    } catch {
        $result[[string]$id] = '暂缺'
    }
}
[System.IO.File]::WriteAllText((Join-Path $data 'recipe_sources.json'), ($result | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false)))
"recipe ids=$($ids.Count) fetched=$found sources=$(@($result.Values | Where-Object { $_ -ne '暂缺' }).Count)"
$result.GetEnumerator() | Group-Object Value | ForEach-Object { "$($_.Name): $($_.Count)" }
