# Generate HolyBulwark/RecipeVendor.lua from wow-forever.gg recipe pages.
#
# Input:
#   data/recipe_cards.json      - { [recipeID] = { { npc, kind, name, zone, x, y } } }
#   data/recipe_vendor_zh.json  - { [npcID] = "中文名" } (optional, from damijing)
#
# The browser collector is tools/holybulwark/fetch_recipe_cards.md.
# x/y in the JSON are percentages (0-100); the Lua table stores 0-1 fractions.

$ErrorActionPreference = 'Stop'
$data = 'D:\opencode_workspace\spellpower-db\data'
$outFile = 'D:\opencode_workspace\wow-forever-addons\HolyBulwark\RecipeVendor.lua'

$cards = Get-Content (Join-Path $data 'recipe_cards.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$zh = @{}
$zhFile = Join-Path $data 'recipe_vendor_zh.json'
if (Test-Path $zhFile) {
    $j = Get-Content $zhFile -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($p in $j.PSObject.Properties) { $zh[[int]$p.Name] = [string]$p.Value }
}

# Forever-only NPCs whose names damijing keeps in English.
$manual = @{
    256730 = '斯通德里·暗锤'
    256734 = '丹尼尔·缝歌'
    256735 = '米文·影织'
}
foreach ($k in $manual.Keys) { $zh[[int]$k] = $manual[$k] }

function Esc([string]$s) {
    if ($null -eq $s) { return '' }
    return $s.Replace('\', '\\').Replace('"', '\"')
}

$okKinds = @{ 'Vendor' = $true; 'Drop' = $true; 'Quest' = $true; 'Chest' = $true }
$rows = New-Object System.Collections.Generic.List[string]
$count = 0

foreach ($p in ($cards.PSObject.Properties | Sort-Object { [int]$_.Name })) {
    $id = [int]$p.Name
    $c = @($p.Value)[0]
    if (-not $c -or -not $c.npc) { continue }
    if (-not $okKinds.ContainsKey([string]$c.kind)) { continue }

    $zone = [string]$c.zone
    if ($zone -match ' · ') { $zone = ($zone -split ' · ')[0] }
    $en = [string]$c.name
    $cn = $zh[[int]$c.npc]
    $cnLua = if ($cn) { '"' + (Esc $cn) + '"' } else { 'nil' }
    $zoneLua = if ($zone) { '"' + (Esc $zone) + '"' } else { 'nil' }

    $xLua = 'nil'; $yLua = 'nil'
    if ($null -ne $c.x -and $null -ne $c.y) {
        $xLua = ([double]$c.x / 100.0).ToString('0.####', [System.Globalization.CultureInfo]::InvariantCulture)
        $yLua = ([double]$c.y / 100.0).ToString('0.####', [System.Globalization.CultureInfo]::InvariantCulture)
    }

    $row = '        {{ {0}, "{1}", {2}, {3}, {4}, nil, {5}, "{6}" }},' -f `
        [int]$c.npc, (Esc $en), $zoneLua, $xLua, $yLua, $cnLua, [string]$c.kind
    $rows.Add('    [' + $id + '] = {')
    $rows.Add($row)
    $rows.Add('    },')
    $count++
}

$header = @(
    '-- Generated from wow-forever.gg item pages (Forever 1.60.1.70959 snapshot).',
    '-- Tuple: { npcID, EnglishName, Zone, x, y, mapID, ChineseName, kind }',
    '-- x/y are normalized 0-1 map coordinates; nil means resolve from QuestieDB at runtime.',
    '-- kind: Vendor / Drop / Quest / Chest. Regenerate with tools/holybulwark/make_recipe_vendor.ps1.',
    'local _, ns = ...',
    'ns.recipeVendor = {'
)
$footer = @('}', '')
$text = ($header + $rows + $footer) -join "`r`n"
[System.IO.File]::WriteAllText($outFile, $text, (New-Object System.Text.UTF8Encoding($false)))
"recipes=$count bytes=$((Get-Item $outFile).Length)"
