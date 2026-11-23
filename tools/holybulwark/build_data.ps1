# Build SpellPowerGear/Data.lua from The Forever Era item chunks + WoW Forever client tables.
# Requires: data\chunks\chunk-*.json, data\ItemSparse_zhCN.csv, data\tfe_zh_names.json,
#           data\AreaTable_enUS.csv, data\AreaTable_zhCN.csv
$ErrorActionPreference = 'Stop'

$dataDir = 'D:\opencode_workspace\wow-forever-addons\data'
$outDir  = 'D:\opencode_workspace\wow-forever-addons\HolyBulwark'
$outLua  = Join-Path $outDir 'Data.lua'
$outCsv  = 'D:\opencode_workspace\wow-forever-addons\data\spellpower_gear_report.csv'

$inv = [System.Globalization.CultureInfo]::InvariantCulture

function Read-JsonUtf8([string]$path) {
    return [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
}
function Num([double]$v) {
    if ($v -eq [Math]::Floor($v)) { return ([int64]$v).ToString($inv) }
    return ([Math]::Round($v, 2)).ToString($inv)
}
function Esc([string]$s) {
    if ($null -eq $s) { return '' }
    return ($s -replace '\\', '\\\\' -replace '"', '\"' -replace "`r", ' ' -replace "`n", ' ')
}

# ---------------------------------------------------------------- client names
$sparse = Import-Csv (Join-Path $dataDir 'ItemSparse_zhCN.csv') -Encoding UTF8
$nameZh = @{}
foreach ($r in $sparse) {
    if ($r.Display_lang) { $nameZh[[int]$r.ID] = $r.Display_lang }
}

$tfeZh = Read-JsonUtf8 (Join-Path $dataDir 'tfe_zh_names.json')
$tfeName = @{}
$acc = 0
foreach ($r in $tfeZh.rows) { $acc += [int]$r[0]; if ($r[3]) { $tfeName[$acc] = [string]$r[3] } }

# English item names (for finding recipe items such as "Plans: ...").
$enSparse = Import-Csv (Join-Path $dataDir 'ItemSparse_enUS.csv') -Encoding UTF8
$enNameToId = @{}
foreach ($r in $enSparse) {
    if ($r.Display_lang -and -not $enNameToId.ContainsKey($r.Display_lang)) {
        $enNameToId[$r.Display_lang] = [int]$r.ID
    }
}
$recipePrefix = @{
    'Blacksmithing' = 'Plans: '
    'Leatherworking' = 'Pattern: '
    'Tailoring' = 'Pattern: '
    'Engineering' = 'Schematic: '
    'Alchemy' = 'Recipe: '
    'Enchanting' = 'Formula: '
    'Cooking' = 'Recipe: '
    'First Aid' = 'Manual: '
}

# Vendor localization + location (manual, 12 vendors cover every vendor source in the DB).
$npcIndex = @{}
$npcIndexPath = Join-Path $dataDir 'npc_index.json'
if (Test-Path $npcIndexPath) {
    $ni = Read-JsonUtf8 $npcIndexPath
    foreach ($p in $ni.PSObject.Properties) { $npcIndex[$p.Name] = [int]$p.Value }
}

$recipeSourceMap = @{}
$recipeSourcePath = Join-Path $dataDir 'recipe_sources.json'
if (Test-Path $recipeSourcePath) {
    $rj = Read-JsonUtf8 $recipeSourcePath
    foreach ($p in $rj.PSObject.Properties) { $recipeSourceMap[$p.Name] = [string]$p.Value }
}

$vendorSubZh = @{
    'Armor Quartermaster' = '护甲军需官'
    'Weapons Quartermaster' = '武器军需官'
    'Stormpike Supply Officer' = '雷矛补给官'
    'Frostwolf Supply Officer' = '霜狼补给官'
    'Silverwing Supply Officer' = '银翼补给官'
    'Warsong Supply Officer' = '战歌补给官'
    'Defilers Supply Officer' = '污染者补给官'
    'League of Arathor Supply Officer' = '阿拉索联军补给官'
}

$vendorInfo = @{
    'Captain Dirgehammer'      = @{ zh = '迪格哈默队长';  zone = '暴风城';       map = 1453;  x = 0.745; y = 0.665; note = '旧城区（坐标近似）' }
    'Captain O''Neal'          = @{ zh = '奥尼尔队长';    zone = '暴风城';       map = 1453;  x = 0.745; y = 0.665; note = '旧城区（坐标近似）' }
    'Lady Palanseer'           = @{ zh = '帕兰希尔女士';  zone = '奥格瑞玛';     map = 1454;  x = 0.775; y = 0.380; note = '荣誉谷（坐标近似）' }
    'Sergeant Thunderhorn'     = @{ zh = '雷角中士';      zone = '奥格瑞玛';     map = 1454;  x = 0.775; y = 0.380; note = '荣誉谷（坐标近似）' }
    'Gaelden Hammersmith'      = @{ zh = '盖尔登·锤锻';   zone = '奥特兰克山脉'; map = 1416;  x = 0.394; y = 0.816; note = '奥特兰克山谷入口' }
    'Thanthaldis Snowgleam'    = @{ zh = '桑塔迪斯·雪光'; zone = '奥特兰克山脉'; map = 1416;  x = 0.394; y = 0.816; note = '奥特兰克山谷入口' }
    'Grunnda Wolfheart'        = @{ zh = '格伦达·狼心';   zone = '奥特兰克山脉'; map = 1416;  x = 0.628; y = 0.592; note = '奥特兰克山谷入口' }
    'Jekyll Flandring'         = @{ zh = '杰基尔·弗兰德林'; zone = '奥特兰克山脉'; map = 1416; x = 0.628; y = 0.592; note = '奥特兰克山谷入口' }
    'Illiyana Moonblaze'       = @{ zh = '伊莉安娜·月辉'; zone = '灰谷';         map = 1440;  x = 0.615; y = 0.838; note = '银翼补给官' }
    'Kelm Hargunth'            = @{ zh = '凯尔姆·哈古斯'; zone = '贫瘠之地';     map = 1413; x = 0.466; y = 0.084; note = '战歌补给官' }
    'Rutherford Twing'         = @{ zh = '卢瑟福·特温';   zone = '阿拉希高地';   map = 1417;  x = 0.734; y = 0.297; note = '污染者补给官' }
    'Samuel Hawke'             = @{ zh = '塞缪尔·霍克';   zone = '阿拉希高地';   map = 1417;  x = 0.460; y = 0.452; note = '阿拉索联军补给官' }
}

# ---------------------------------------------------------------- zone names
$areaEn = Import-Csv (Join-Path $dataDir 'AreaTable_enUS.csv') -Encoding UTF8
$areaZh = Import-Csv (Join-Path $dataDir 'AreaTable_zhCN.csv') -Encoding UTF8
$zhById = @{}
foreach ($r in $areaZh) { $zhById[$r.ID] = $r.AreaName_lang }
$zoneZh = @{}
foreach ($r in $areaEn) {
    $z = $zhById[$r.ID]
    if (-not $z) { continue }
    if ($r.AreaName_lang -and -not $zoneZh.ContainsKey($r.AreaName_lang)) { $zoneZh[$r.AreaName_lang] = $z }
    if ($r.ZoneName     -and -not $zoneZh.ContainsKey($r.ZoneName))     { $zoneZh[$r.ZoneName] = $z }
}
# Names the client table does not use for these instances / custom zones.
$manualZone = @{
    "Ahn'Qiraj Temple" = '安其拉神殿'
    'Deadmines'        = '死亡矿井'
    'Nightmare Grove'  = '梦魇林地'
}
$profZh = @{
    'Tailoring'      = '裁缝'
    'Leatherworking' = '制皮'
    'Blacksmithing'  = '锻造'
    'Alchemy'        = '炼金术'
    'Engineering'    = '工程学'
    'Enchanting'     = '附魔'
    'Cooking'        = '烹饪'
    'First Aid'      = '急救'
    'Fishing'        = '钓鱼'
}

$sourceLabels = @{ drop = '掉落'; quest = '任务'; vendor = '出售'; craft = '制造'; object = '宝箱'; item = '容器'; world = '世界掉落' }
function SourceText([string]$kind, [string]$name, [string]$zone, [double]$chance) {
    $label = $sourceLabels[$kind]
    if (-not $label) { $label = $kind }
    $parts = @($label)
    if ($kind -ne 'world' -and $name) { $parts += $name }
    if ($zone) { $parts += $zone }
    if ($chance -ge 0 -and $kind -ne 'world') {
        if ($chance -gt 0 -and $chance -lt 0.01) { $parts += '<0.01%' }
        elseif ($chance -eq [math]::Floor($chance)) { $parts += ('{0}%' -f [int]$chance) }
        else { $parts += (([math]::Round($chance, 2)).ToString($inv) + '%') }
    }
    return ($parts -join ' · ')
}

$statKeys = @('str','agi','sta','int','spi','ap','rap','sp','heal','crit','hit','spellcrit','spellhit',
    'def','dodge','parry','block','bv','mp5','hp5','fr','nr','frr','sr','ar','hr','allres','haste','exp',
    'arpen','spen','firepen','frostpen','wdmg','holy','fire','nature','frost','shadow','arcane',
    'apdemon','apundead','apbeast','spdemon','spundead','mana','hp','fap')
$statSet = @{}
foreach ($k in $statKeys) { $statSet[$k] = $true }

# ---------------------------------------------------------------- merge chunks
$all = @{}
Get-ChildItem (Join-Path $dataDir 'chunks') -Filter '*.json' | ForEach-Object {
    $o = Read-JsonUtf8 $_.FullName
    foreach ($p in $o.PSObject.Properties) { $all[[int]$p.Name] = $p.Value }
}

$armorSc = @(1, 2, 3, 4, 6)      # cloth / leather / mail / plate / shield
$jewelSlots = @(2, 11, 12, 16)   # neck / finger / trinket / back
$weapSc = @(0, 1, 4, 5, 6, 7, 8) # 1H axe, 2H axe, 1H mace, 2H mace, polearm, 1H sword, 2H sword

$records = New-Object System.Collections.Generic.List[object]
$zoneMiss = @{}

foreach ($it in $all.Values) {
    $st = $it.stats
    if (-not $st) { continue }

    # Spell damage: generic spell power or holy spell power. Pure shadow/fire/... caster gear is out.
    $sp = 0; $holy = 0
    if ($st.sp)   { $sp = [double]$st.sp }
    if ($st.holy) { $holy = [double]$st.holy }
    if ($sp -le 0 -and $holy -le 0) { continue }

    $rl = [int]$it.rl
    $il = [int]$it.il
    if ($rl -lt 10 -or $rl -gt 60) {
        if (-not ($rl -eq 0 -and $il -le 63)) { continue }
    }

    $c = [int]$it.c; $sc = [int]$it.sc; $slot = [int]$it.s
    $ok = $false
    if ($c -eq 4) {
        if ($armorSc -contains $sc) { $ok = $true }
        elseif ($sc -eq 0 -and ($jewelSlots -contains $slot)) { $ok = $true }
    } elseif ($c -eq 2) {
        if ($weapSc -contains $sc) { $ok = $true }
    }
    if (-not $ok) { continue }

    $cl = $it.cl
    if ($null -ne $cl -and [int]$cl -ne -1 -and [int]$cl -ne 32767 -and (([int]$cl -band 2) -eq 0)) { continue }

    $nameEn = [string]$it.n.en
    if (-not $nameEn -or $nameEn -match '^(OLD|UNUSED|unused|Test)') { continue }

    $id = [int]$it.id
    $name = $nameZh[$id]
    if (-not $name) { $name = $tfeName[$id] }
    if (-not $name) { $name = $nameEn }

    # slot key
    $slotEn = [string]$it.slot.en
    $typeEn = [string]$it.sub.en
    if ($c -eq 2) { $slotKey = 'weapon' }
    elseif ($sc -eq 6) { $slotKey = 'shield' }
    else {
        switch -regex ($slotEn) {
            '^Head'      { $slotKey = 'head';     break }
            '^Neck'      { $slotKey = 'neck';     break }
            '^Shoulder'  { $slotKey = 'shoulder'; break }
            '^Back'      { $slotKey = 'back';     break }
            '^Chest'     { $slotKey = 'chest';    break }
            '^Wrist'     { $slotKey = 'wrist';    break }
            '^Hands'     { $slotKey = 'hands';    break }
            '^Waist'     { $slotKey = 'waist';    break }
            '^Legs'      { $slotKey = 'legs';     break }
            '^Feet'      { $slotKey = 'feet';     break }
            '^Finger'    { $slotKey = 'finger';   break }
            '^Trinket'   { $slotKey = 'trinket';  break }
            default      { $slotKey = 'other' }
        }
    }
    if ($slotKey -eq 'other') { continue }

    # stats
    $statParts = New-Object System.Collections.Generic.List[string]
    $statTable = @{}
    foreach ($k in $statKeys) {
        $v = $st.$k
        if ($null -eq $v) { continue }
        $d = [double]$v
        if ($d -eq 0) { continue }
        $statTable[$k] = $d
        $statParts.Add(('{0}={1}' -f $k, (Num $d)))
    }
    if ($statParts.Count -eq 0) { continue }

    # sources
    $srcParts = New-Object System.Collections.Generic.List[string]
    $srcHuman = New-Object System.Collections.Generic.List[string]
    $seenSrc = @{}
    $count = 0
    foreach ($s in @($it.src)) {
        if (-not $s -or -not $s.k) { continue }
        if ($s.more -and (-not $s.n -or -not $s.n.en)) { continue }
        if ($count -ge 8) { break }
        $kind = [string]$s.k
        $sn = ''
        if ($s.n -and $s.n.en) { $sn = [string]$s.n.en }
        $zone = ''
        if ($s.zone -and $s.zone.en) {
            $ze = [string]$s.zone.en
            if ($zoneZh.ContainsKey($ze) -and $zoneZh[$ze]) { $zone = $zoneZh[$ze] }
            elseif ($manualZone.ContainsKey($ze)) { $zone = $manualZone[$ze] }
            else { $zone = $ze; $zoneMiss[$ze] = 1 }
        }
        $extra = ''
        $zhName = ''
        $mapLua = 'nil'
        $xLua = 'nil'
        $yLua = 'nil'
        $note = ''
        $recipeName = ''
        $recipeIdLua = 'nil'
        $recipeSource = ''
        $npcIdLua = 'nil'
        $questLevelLua = 'nil'

        if ($kind -eq 'quest') {
            if ($s.id) { $extra = [string]$s.id }
            if ($s.lvl) { $questLevelLua = [string]$s.lvl }
        } elseif ($kind -eq 'vendor') {
            if ($s.sub -and $s.sub.en) {
                $subEn = [string]$s.sub.en
                if ($vendorSubZh.ContainsKey($subEn)) { $extra = $vendorSubZh[$subEn] }
                else { $extra = $subEn }
            }
            if ($vendorInfo.ContainsKey($sn)) {
                $vi = $vendorInfo[$sn]
                $zhName = $vi.zh
                $note = $vi.note
                if (-not $zone) { $zone = $vi.zone }
                $mapLua = [string]$vi.map
                $xLua = Num ([double]$vi.x)
                $yLua = Num ([double]$vi.y)
            }
        } elseif ($kind -eq 'craft') {
            if ($s.prof -and $s.prof.en) {
                $p = [string]$s.prof.en
                if ($profZh.ContainsKey($p)) { $sn = $profZh[$p] } else { $sn = $p }
                $pre = $recipePrefix[$p]
                if ($pre) {
                    $recipeEn = $pre + [string]$it.n.en
                    if ($enNameToId.ContainsKey($recipeEn)) {
                        $rid = $enNameToId[$recipeEn]
                        $recipeIdLua = [string]$rid
                        if ($nameZh.ContainsKey($rid)) { $recipeName = $nameZh[$rid] }
                        else { $recipeName = $recipeEn }
                        if ($recipeSourceMap.ContainsKey($recipeIdLua)) { $recipeSource = $recipeSourceMap[$recipeIdLua] }
                    }
                }
            }
        } elseif ($kind -eq 'item') {
            if ($s.id) { $extra = [string]$s.id }
        } elseif ($kind -eq 'object') {
            if ($s.id) { $extra = [string]$s.id }
        } elseif ($kind -eq 'world') {
            $sn = '世界掉落'
        }
        if (($kind -eq 'drop' -or $kind -eq 'object') -and $sn -and $npcIndex.ContainsKey($sn)) {
            $npcIdLua = [string]$npcIndex[$sn]
        }
        $chance = -1.0
        if ($null -ne $s.chance) { $chance = [double]$s.chance }
        if (-not $sn -and $kind -eq 'world') { $sn = '世界掉落' }
        $sig = '{0}|{1}|{2}|{3}' -f $kind, $sn, $zone, $extra
        if ($seenSrc.ContainsKey($sig)) { continue }
        $seenSrc[$sig] = $true
        $chanceLua = 'nil'
        if ($chance -ge 0) { $chanceLua = Num $chance }

        $luaKind = '"' + (Esc $kind) + '"'
        $luaName = '"' + (Esc $sn) + '"'
        $luaZone = '"' + (Esc $zone) + '"'
        $luaExtra = '"' + (Esc $extra) + '"'
        $luaZh = if ($zhName) { '"' + (Esc $zhName) + '"' } else { 'nil' }
        $luaNote = if ($note) { '"' + (Esc $note) + '"' } else { 'nil' }
        $luaRecipeName = if ($recipeName) { '"' + (Esc $recipeName) + '"' } else { 'nil' }
        $luaRecipeSource = if ($recipeSource) { '"' + (Esc $recipeSource) + '"' } else { 'nil' }
        $srcParts.Add(('{{{0},{1},{2},{3},{4},{5},{6},{7},{8},{9},{10},{11},{12},{13},{14}}}' -f
            $luaKind, $luaName, $luaZone, $chanceLua, $luaExtra, $luaZh, $mapLua, $xLua, $yLua, $luaNote, $luaRecipeName, $recipeIdLua, $luaRecipeSource, $npcIdLua, $questLevelLua))

        $displayName = if ($zhName) { $zhName } else { $sn }
        $human = SourceText $kind $displayName $zone $chance
        if ($kind -eq 'vendor' -and $note) { $human += ' · ' + $note }
        if ($kind -eq 'craft' -and $recipeName) {
            $human += ' · 配方：' + $recipeName
            if ($recipeSource) { $human += '（' + $recipeSource + '）' }
        }
        $srcHuman.Add($human)
        $count++
    }

    $armorLua = 'nil'
    if ($it.armor) { $armorLua = Num ([double]$it.armor) }

    $dmgLua = 'nil'
    if ($it.dmg -and $it.dmg.min) {
        $dmgLua = '{' + (Num ([double]$it.dmg.min)) + ',' + (Num ([double]$it.dmg.max)) + ',' +
            (Num ([double]$it.dmg.speed)) + ',' + (Num ([double]$it.dmg.dps)) + '}'
    }

    $bind = 0
    if ($null -ne $it.bind) { $bind = [int]$it.bind }
    $known = 0
    if ($srcParts.Count -gt 0) { $known = 1 }

    $statLua = '{' + ($statParts -join ',') + '}'
    $srcLua = '{' + ($srcParts -join ',') + '}'
    $line = '{' + $id + ',"' + (Esc $name) + '",' + [int]$it.q + ',' + $il + ',' + $rl + ',"' + $slotKey +
        '","' + (Esc $typeEn) + '",' + $armorLua + ',' + $statLua + ',' + $srcLua + ',' + $known + ',' + $bind + ',' + $dmgLua + ',"' + (Esc $nameEn) + '","' + (Esc ([string]$it.i)) + '"' + '}'

    $records.Add([pscustomobject]@{
        id = $id; name = $name; nameEn = $nameEn; q = [int]$it.q; il = $il; rl = $rl;
        slot = $slotKey; type = $typeEn; armor = $armorLua; known = $known;
        sp = $sp; holy = $holy; line = $line; stats = $statTable; srcCount = $count;
        srcText = ($srcHuman -join '；'); icon = [string]$it.i
    })
}

# Sort: required level (0 counts as 60), then ilvl desc, quality desc, name
$sorted = $records | Sort-Object @{Expression = { if ([int]$_.rl -eq 0) { 61 } else { [int]$_.rl } }}, `
    @{Expression = { [int]$_.il }; Descending = $true }, `
    @{Expression = { [int]$_.q }; Descending = $true }, `
    @{Expression = { $_.name } }

# ---------------------------------------------------------------- write Lua
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('-- Generated by tools/build_data.ps1 -- do not edit by hand.')
[void]$sb.AppendLine('-- Item stats: The Forever Era (build 1.60.1.70959), client names: WoW Forever zhCN tables.')
[void]$sb.AppendLine('-- Layout: {id, name, quality, ilvl, reqLevel, slotKey, typeEn, armor, stats, sources, knownSource, bind, dmg, nameEn, icon}')
[void]$sb.AppendLine('-- sources: {"kind","name","zoneZh",chance,"extra"}  kind = drop/quest/vendor/craft/object/item/world')
[void]$sb.AppendLine('local _, ns = ...')
[void]$sb.AppendLine('ns.data = {')
[void]$sb.AppendLine('    build = "1.60.1.70959",')
[void]$sb.AppendLine('    generated = "2026-11-22",')
[void]$sb.AppendLine('    items = {')
foreach ($r in $sorted) {
    [void]$sb.Append('        ').Append($r.line).AppendLine(',')
}
[void]$sb.AppendLine('    },')
[void]$sb.AppendLine('    loaded = true,')
[void]$sb.AppendLine('    count = ' + $records.Count + ',')
[void]$sb.AppendLine('}')
$utf8 = New-Object System.Text.UTF8Encoding($false)
$outText = $sb.ToString().Replace('"Trash mobs"', '"小怪"')
[System.IO.File]::WriteAllText($outLua, $outText, $utf8)

# ---------------------------------------------------------------- report
$sorted | Select-Object id, name, nameEn, q, il, rl, slot, type, armor, known,
    @{ n = 'sp'; e = { [double]$_.stats.sp } },
    @{ n = 'holy'; e = { [double]$_.stats.holy } },
    @{ n = 'heal'; e = { [double]$_.stats.heal } },
    @{ n = 'sta'; e = { [double]$_.stats.sta } },
    @{ n = 'int'; e = { [double]$_.stats.int } },
    @{ n = 'str'; e = { [double]$_.stats.str } },
    @{ n = 'agi'; e = { [double]$_.stats.agi } },
    @{ n = 'spi'; e = { [double]$_.stats.spi } },
    @{ n = 'crit'; e = { [double]$_.stats.crit } },
    @{ n = 'hit'; e = { [double]$_.stats.hit } },
    @{ n = 'def'; e = { [double]$_.stats.def } },
    @{ n = 'dodge'; e = { [double]$_.stats.dodge } },
    @{ n = 'parry'; e = { [double]$_.stats.parry } },
    @{ n = 'block'; e = { [double]$_.stats.block } },
    @{ n = 'bv'; e = { [double]$_.stats.bv } },
    @{ n = 'mp5'; e = { [double]$_.stats.mp5 } },
    srcCount, srcText | Export-Csv $outCsv -NoTypeInformation -Encoding UTF8

"items: $($records.Count)"
"known source: $(@($sorted | Where-Object { $_.known -eq 1 }).Count)"
"unknown source: $(@($sorted | Where-Object { $_.known -eq 0 }).Count)"
"zones missing: $(($zoneMiss.Keys | Sort-Object) -join ', ')"
"lua bytes: $((Get-Item $outLua).Length)"
