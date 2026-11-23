param(
    [string]$Build = '1.60.1.71037'
)
$ErrorActionPreference = 'Stop'
$data = 'D:\opencode_workspace\wow-forever-addons\data'
$chunks = Join-Path $data 'chunks'
New-Item -ItemType Directory -Force $data, $chunks | Out-Null
$ProgressPreference = 'SilentlyContinue'

function Get-File([string]$url, [string]$path) {
    if (Test-Path $path) { Remove-Item $path -Force }
    Write-Host "GET $url"
    Invoke-WebRequest $url -OutFile $path -UseBasicParsing -TimeoutSec 180
}

# The Forever Era item database
Get-File 'https://theforeverera.com/data/items/search.json' (Join-Path $data 'tfe_search.json')
Get-File 'https://theforeverera.com/data/items/meta.json' (Join-Path $data 'tfe_meta.json')
Get-File 'https://theforeverera.com/zh-cn/search-items.json' (Join-Path $data 'tfe_zh_names.json')

$meta = [System.IO.File]::ReadAllText((Join-Path $data 'tfe_meta.json'), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
foreach ($k in $meta.chunks) {
    $p = Join-Path $chunks ("chunk-$k.json")
    if (Test-Path $p) { continue }
    Get-File "https://theforeverera.com/data/items/chunk-$k.json" $p
}

# WoW Forever client tables (Chinese names / zones)
Get-File "https://wago.tools/db2/ItemSparse/csv?build=$Build&locale=zhCN" (Join-Path $data 'ItemSparse_zhCN.csv')
Get-File "https://wago.tools/db2/ItemSparse/csv?build=$Build&locale=enUS" (Join-Path $data 'ItemSparse_enUS.csv')
Get-File "https://wago.tools/db2/Item/csv?build=$Build&locale=zhCN" (Join-Path $data 'Item_zhCN.csv')
Get-File "https://wago.tools/db2/AreaTable/csv?build=$Build&locale=zhCN" (Join-Path $data 'AreaTable_zhCN.csv')
Get-File "https://wago.tools/db2/AreaTable/csv?build=$Build&locale=enUS" (Join-Path $data 'AreaTable_enUS.csv')

Write-Host "done: $((Get-ChildItem $chunks -Filter '*.json').Count) chunks"
