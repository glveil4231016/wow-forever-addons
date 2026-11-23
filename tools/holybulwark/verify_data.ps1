# Verify HolyBulwark/Data.lua ships nothing the Forever client cannot resolve.
# Run after build_data.ps1. Exits 1 when a listed item ID is absent from
# data\ItemSparse_zhCN.csv (that is exactly how Classic Era rows used to leak in).
param(
    [string]$DataDir = (Join-Path $PSScriptRoot '..\..\data'),
    [string]$DataLua = (Join-Path $PSScriptRoot '..\..\HolyBulwark\Data.lua')
)
$ErrorActionPreference = 'Stop'

$sparsePath = Join-Path $DataDir 'ItemSparse_zhCN.csv'
if (-not (Test-Path $sparsePath)) { throw "missing client table: $sparsePath" }
if (-not (Test-Path $DataLua)) { throw "missing data file: $DataLua" }

$clientIds = @{}
foreach ($r in Import-Csv $sparsePath -Encoding UTF8) {
    if ($r.ID) { $clientIds[[int]$r.ID] = $true }
}
if ($clientIds.Count -eq 0) { throw 'ItemSparse_zhCN.csv 没有读到任何 ID' }

$bad = New-Object System.Collections.Generic.List[int]
$total = 0
foreach ($line in [System.IO.File]::ReadLines($DataLua, [System.Text.Encoding]::UTF8)) {
    if ($line -match '^\s*\{(\d+),') {
        $id = [int]$Matches[1]
        $total++
        if (-not $clientIds.ContainsKey($id)) { $bad.Add($id) }
    }
}

"data.lua items: $total"
"not in Forever client: $($bad.Count)"
if ($bad.Count -gt 0) {
    $preview = ($bad | Select-Object -First 20) -join ', '
    "first ids: $preview"
    exit 1
}
'source of truth: data\ItemSparse_zhCN.csv'
