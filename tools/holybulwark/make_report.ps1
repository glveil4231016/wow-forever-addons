$ErrorActionPreference = 'Stop'
$csv = 'D:\opencode_workspace\wow-forever-addons\data\spellpower_gear_report.csv'
$out = 'D:\opencode_workspace\wow-forever-addons\docs\HolyBulwark-装备清单.md'
$rows = Import-Csv $csv -Encoding UTF8

$slotOrder = @('head','neck','shoulder','back','chest','wrist','hands','waist','legs','feet','finger','trinket','shield','weapon')
$slotNames = @{ head='头部'; neck='颈部'; shoulder='肩部'; back='背部'; chest='胸部'; wrist='手腕'; hands='手部'; waist='腰部'; legs='腿部'; feet='脚部'; finger='戒指'; trinket='饰品'; shield='盾牌'; weapon='武器' }
$typeNames = @{ Cloth='布甲'; Leather='皮甲'; Mail='锁甲'; Plate='板甲'; Shield='盾牌'; 'One-Hand Sword'='单手剑'; 'One-Hand Mace'='单手锤'; 'One-Hand Axe'='单手斧'; 'Two-Hand Sword'='双手剑'; 'Two-Hand Mace'='双手锤'; 'Two-Hand Axe'='双手斧'; Polearm='长柄武器' }
$qualityNames = @{ 0='粗糙'; 1='普通'; 2='优秀'; 3='精良'; 4='史诗'; 5='传说'; 6='神器' }
$statDefs = @(
    @('sp', '法强', $false), @('holy', '神圣法伤', $false), @('heal', '治疗', $false),
    @('sta', '耐力', $false), @('int', '智力', $false), @('str', '力量', $false),
    @('agi', '敏捷', $false), @('spi', '精神', $false), @('crit', '暴击', $true),
    @('hit', '命中', $true), @('def', '防御', $false), @('dodge', '闪避', $true),
    @('parry', '招架', $true), @('block', '格挡', $true), @('bv', '格挡值', $false),
    @('mp5', '五回', $false)
)

function StatText($row) {
    $parts = @()
    foreach ($d in $statDefs) {
        $v = [double]$row.($d[0])
        if ($v -ne 0) {
            $num = if ($v -eq [math]::Floor($v)) { ([int]$v).ToString() } else { $v.ToString('0.#') }
            if ($d[2]) { $parts += ('{0}+{1}%' -f $d[1], $num) }
            else { $parts += ('{0}+{1}' -f $d[1], $num) }
        }
    }
    return ($parts -join ' ')
}

$filtered = @($rows | Where-Object {
    $_.known -eq '1' -and [double]$_.sta -gt 0 -and (
        $_.type -in @('Plate', 'Mail', 'Shield') -or $_.slot -in @('neck', 'finger', 'trinket', 'back')
    )
})

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('# WoW Forever：10-60 级法伤防骑装备清单')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('> 数据构建：客户端 1.60.1.71037 / 数据库快照 1.60.1.70959（2026-11-18）。')
[void]$sb.AppendLine('> 属性与来源来自 [The Forever Era](https://theforeverera.com) 的物品数据，名称来自 WoW Forever 中文客户端。')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## 收录口径')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('- 防护骑士可装备：板甲、锁甲、皮甲、布甲、盾牌、项链、戒指、饰品、披风，以及骑士可用的单手/双手斧锤剑、长柄武器。')
[void]$sb.AppendLine('- 带法术强度（通用法强或神圣法伤）。纯治疗、纯暗影/火焰等其它系法伤不计入。')
[void]$sb.AppendLine('- 需求等级 10-60；等级 0 的装备按 60 级内容处理。')
[void]$sb.AppendLine('- **本清单只列出有明确来源、且有耐力、且属于板/锁/盾或首饰披风的坦克向装备**；')
[void]$sb.AppendLine('  完整数据库（含布甲/皮甲、纯输出向、来源暂缺）在插件里切换筛选即可看到。')
[void]$sb.AppendLine('')
[void]$sb.AppendLine(('本清单共 **{0}** 件。插件完整库共 2047 件，其中有明确来源 1054 件。' -f $filtered.Count))
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## 按部位统计')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('| 部位 | 数量 |')
[void]$sb.AppendLine('| --- | ---: |')
foreach ($s in $slotOrder) {
    $n = @($filtered | Where-Object { $_.slot -eq $s }).Count
    if ($n -gt 0) { [void]$sb.AppendLine(('| {0} | {1} |' -f $slotNames[$s], $n)) }
}
[void]$sb.AppendLine('')

foreach ($s in $slotOrder) {
    $list = @($filtered | Where-Object { $_.slot -eq $s })
    if ($list.Count -eq 0) { continue }
    $list = $list | Sort-Object @{ Expression = { if ([int]$_.rl -eq 0) { 61 } else { [int]$_.rl } } }, @{ Expression = { [int]$_.il }; Descending = $true }
    [void]$sb.AppendLine(('## {0}（{1} 件）' -f $slotNames[$s], $list.Count))
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| 装备 | 需求等级 | 物品等级 | 品质 | 类型 | 护甲 | 属性 | 来源 |')
    [void]$sb.AppendLine('| --- | ---: | ---: | --- | --- | ---: | --- | --- |')
    foreach ($r in $list) {
        $name = $r.name -replace '\|', '\|'
        $lvl = if ([int]$r.rl -eq 0) { '—' } else { $r.rl }
        $armor = ''
        if ($r.armor -match '^\d+(\.\d+)?$' -and [double]$r.armor -gt 0) { $armor = ([int][double]$r.armor).ToString() }
        $type = $typeNames[$r.type]
        if (-not $type) { $type = $r.type }
        $q = $qualityNames[[int]$r.q]
        $src = $r.srcText -replace '\|', '\|'
        [void]$sb.AppendLine(('| {0} (#{1}) | {2} | {3} | {4} | {5} | {6} | {7} | {8} |' -f $name, $r.id, $lvl, $r.il, $q, $type, $armor, (StatText $r), $src))
    }
    [void]$sb.AppendLine('')
}

[void]$sb.AppendLine('---')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## 说明')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('- 装备名称使用中文客户端名称；来源里的首领、NPC、任务名保留数据库英文原名（客户端没有可离线查询的中文名）。')
[void]$sb.AppendLine('- 掉落率来自数据库统计，低于 0.01% 显示为 `<0.01%`。')
[void]$sb.AppendLine('- 标注“来源暂缺”的新装备没有进入本清单，但仍收录在插件中，取消“只看有来源”即可查看。')
[void]$sb.AppendLine('- 世界掉落只写“世界掉落”，不列具体怪物。')
[void]$sb.AppendLine('')

[System.IO.File]::WriteAllText($out, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
"rows: $($filtered.Count) -> $out ($((Get-Item $out).Length) bytes)"
