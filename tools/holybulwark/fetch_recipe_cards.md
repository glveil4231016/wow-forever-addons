# 抓取配方来源（wow-forever.gg）

`RecipeVendor.lua` 的数据来自 wow-forever.gg 的物品页。页面结构大致为：

```html
<a class="wtf-go" href="/db/npcs/256730-stondry-darkhammer/">
  <span class="wtf-word">Vendor</span>
  <span class="wtf-name">Stondry Darkhammer</span>
  <span class="wtf-where">Redridge Mountains</span>
</a>
...
<code class="cp-text">/way Redridge Mountains 10.1 72.8 Stondry Darkhammer</code>
```

## 1. 准备配方 ID

从 `HolyBulwark/Data.lua` 里提取制造来源的配方物品 ID：

```powershell
$lua = [System.IO.File]::ReadAllText('...\HolyBulwark\Data.lua', [System.Text.Encoding]::UTF8)
$ids = [regex]::Matches($lua, '"craft","[^"]*","[^"]*",[^,]*,"[^"]*",nil,nil,nil,nil,nil,"[^"]*",(\d+)') |
    ForEach-Object { [int]$_.Groups[1].Value } | Sort-Object -Unique
($ids -join ',') | Set-Content "$env:TEMP\recipe_ids.txt" -Encoding ascii
```

## 2. 在 wow-forever.gg 页面里收集

打开任意 `https://wow-forever.gg/db/items/` 页面，在 DevTools Console 里粘贴：

```js
window.__ids = [/* 把 recipe_ids.txt 的内容粘贴到这里 */];
window.__cards = {};
window.__cardRun = true; window.__cardsDone = false;
(async () => {
  const dec = s => s.split('&#39;').join("'").split('&amp;').join('&')
    .split('&quot;').join('"').split('&lt;').join('<').split('&gt;').join('>').trim();
  const grab = (s, key) => {
    const m = '<span class="' + key + '">';
    const i = s.indexOf(m); if (i < 0) return null;
    const a = i + m.length, b = s.indexOf('<', a);
    return b < 0 ? null : dec(s.slice(a, b));
  };
  for (const id of window.__ids) {
    if (window.__cards[id]) continue;
    let res = null;
    for (let a = 0; a < 6; a++) {
      try { res = await fetch('/db/items/' + id + '/'); if (res.status === 200) break; } catch (e) {}
      await new Promise(r => setTimeout(r, 3000));
    }
    if (!res || res.status !== 200) { window.__cards[id] = { error: res && res.status }; continue; }
    const h = await res.text();
    const parts = h.split('<a class="wtf-go"').slice(1);
    const cards = [];
    for (const chunk of parts) {
      let npc = null;
      const ni = chunk.indexOf('href="/db/npcs/');
      if (ni >= 0) {
        const d = chunk.slice(ni + 15).split('-')[0];
        if (d && !isNaN(+d)) npc = +d;
      }
      let x = null, y = null;
      const wi = chunk.indexOf('/way ');
      if (wi >= 0) {
        const line = chunk.slice(wi + 5, chunk.indexOf('<', wi)).trim();
        const tk = line.split(/\s+/);
        for (let k = 0; k < tk.length - 1; k++) {
          if (tk[k] && !/[^0-9.]/.test(tk[k]) && tk[k].indexOf('.') > 0) {
            x = +tk[k]; y = +tk[k + 1]; break;
          }
        }
      }
      cards.push({ npc, kind: grab(chunk, 'wtf-word'), name: grab(chunk, 'wtf-name'),
                   zone: grab(chunk, 'wtf-where'), x, y });
      if (cards.length >= 12) break;
    }
    window.__cards[id] = cards;
    await new Promise(r => setTimeout(r, 1400));
  }
  window.__cardRun = false; window.__cardsDone = true;
})();
```

等 `window.__cardsDone === true` 后，导出：

```js
(() => {
  const out = {};
  for (const id of window.__ids) {
    const c = window.__cards[id];
    if (Array.isArray(c)) {
      const v = c.filter(x => x && x.npc);
      if (v.length) out[id] = v;
    }
  }
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob([JSON.stringify(out)], { type: 'application/json' }));
  a.download = 'recipe_cards.json';
  a.click();
})();
```

把下载的 `recipe_cards.json` 放到 `spellpower-db/data/`。

## 3. 中文 NPC 名

wow-forever 只有英文名。用 damijing 的 NPC 页补中文：

```powershell
$ProgressPreference = 'SilentlyContinue'
$ids = <RecipeVendor 里出现的 NPC ID>
$out = @{}
foreach ($id in $ids) {
  Start-Sleep -Milliseconds 900
  try {
    $r = Invoke-WebRequest "https://forever.damijing.com/npc/$id" -UseBasicParsing -TimeoutSec 40
    $h = [System.Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray())
    $name = ([regex]::Match($h, '<title>(.*?)</title>').Groups[1].Value -replace 'NPC-.*$', '').Trim()
    if ($name) { $out[[string]$id] = $name }
  } catch {}
}
$out | ConvertTo-Json | Set-Content 'spellpower-db\data\recipe_vendor_zh.json' -Encoding UTF8
```

damijing 对 Forever 新 NPC 也可能只给英文名，脚本里的 `$manual` 表用于补充音译。

## 4. 生成 Lua

```powershell
powershell -File tools\holybulwark\make_recipe_vendor.ps1
```

输出 `HolyBulwark/RecipeVendor.lua`，并把 `RecipeVendor.lua` 加入 `.toc`。
