#!/usr/bin/env python3
"""Offline SVG exploration based on the logo-generator comparison workflow."""
from pathlib import Path
import re

root = Path(__file__).resolve().parent.parent
output = root / 'Design' / 'Brand'
output.mkdir(parents=True, exist_ok=True)
side = 'M18 68C16 55 20 44 31 40C23 22 27 10 34 13C42 17 44 30 43 39L48 38C43 20 47 8 54 12C62 17 63 32 59 44C68 48 72 56 88 65C92 68 90 74 84 75L65 77C59 86 43 88 29 83C22 80 18 75 18 68Z M64.6 60a3.6 3.6 0 1 0-7.2 0a3.6 3.6 0 1 0 7.2 0Z'
designs = [
    ('01-side', '侧影', '已采用', '长耳与细鼻构成完整轮廓。单一剪影在 18pt 下仍然清楚，眼睛以留空表现。', f'<path fill="currentColor" fill-rule="evenodd" d="{side}"/>'),
    ('02-ears', '双耳', '几何', '正面的两只长耳朵，更接近一个亲切的小伙伴；对称结构适合头像和应用图标。', '<path fill="currentColor" fill-rule="evenodd" d="M30 48C16 31 17 11 25 10C34 9 40 30 43 43H57C60 30 66 9 75 10C83 11 84 31 70 48C81 59 78 77 64 86Q50 97 36 86C22 77 19 59 30 48Z M39 63a4 4 0 1 0 0 8a4 4 0 1 0 0-8Z M61 63a4 4 0 1 0 0 8a4 4 0 1 0 0-8Z"/>'),
    ('03-curled', '蜷起', '线条', '身体和尾巴收成一圈，呼应把不常用图标收起来。轮廓更柔和，细节少于写实画法。', '<g fill="none" stroke="currentColor" stroke-width="7.5" stroke-linecap="round" stroke-linejoin="round"><path d="M76 70C85 55 78 44 65 41L65 16Q55 8 53 40L47 41Q38 12 31 17L35 47C15 55 17 81 42 85C63 89 80 79 73 67C65 55 46 61 49 73"/></g><circle cx="66" cy="54" r="3.5" fill="currentColor"/>'),
    ('04-peek', '探头', '几何与留白', '从状态栏边缘探出耳朵和眼睛，直接关联产品用途。横向基线使菜单栏图标更稳。', '<path d="M18 74H82M26 65C25 52 32 44 41 43L32 17Q39 8 48 43H54L59 13Q68 8 66 45C76 49 79 56 78 65" fill="none" stroke="currentColor" stroke-width="8" stroke-linecap="round" stroke-linejoin="round"/><g fill="currentColor"><circle cx="42" cy="59" r="3.5"/><circle cx="64" cy="59" r="3.5"/></g>'),
    ('05-monogram', '字母 B', '字母与轮廓', '把 Bilby 的首字母和长耳朵结合，更接近品牌标记。实心面积大，缩小时有分量。', '<path fill="currentColor" fill-rule="evenodd" d="M25 84V37L19 17Q26 8 39 34L45 11Q55 7 56 35C78 35 87 53 71 62C90 73 77 89 57 89H31Q25 89 25 84Z M40 47V58H56C69 58 69 47 56 47Z M40 70V80H58C71 80 71 70 58 70Z"/>'),
    ('06-dots', '耳语', '点与线', '用两只耳朵、两只眼睛和一笔面部轮廓组成表情。更轻盈，保留大量留白。', '<g fill="currentColor"><rect x="29" y="10" width="12" height="32" rx="6" transform="rotate(-13 35 26)"/><rect x="60" y="8" width="12" height="34" rx="6" transform="rotate(13 66 25)"/><circle cx="39" cy="62" r="4"/><circle cx="63" cy="62" r="4"/></g><path d="M25 48C12 62 25 84 49 88C68 85 85 68 77 52M46 76H53" fill="none" stroke="currentColor" stroke-width="7" stroke-linecap="round"/>'),
]

cards = []
for slug, title, kind, reason, body in designs:
    if slug == '04-peek' and (output / 'Bilby.svg').exists():
        artwork = (output / 'Bilby.svg').read_text()
        body = re.search(r'<svg[^>]*>(.*?)</svg>', artwork, flags=re.S).group(1)
        reason = '按最新参考图采用饱满的不对称双耳、较大的耳内留白与圆眼睛，取消底部横线。点击状态栏图标时耳朵轻摆一次，图形本体为 17.5pt。'
    svg = f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" role="img" aria-label="Bilby {title}">{body}</svg>'
    (output / f'{slug}.svg').write_text(svg + '\n')
    if slug == '04-peek':
        (output / 'Bilby.svg').write_text(svg + '\n')
    if slug == '01-side':
        kind = '剪影'
    elif slug == '04-peek':
        kind = '已采用'
    cards.append(f'<button class="card {"selected" if slug == "04-peek" else ""}" data-slug="{slug}" aria-pressed="{"true" if slug == "04-peek" else "false"}"><div class="canvas">{svg}</div><div class="title"><b>{title}</b><span>{kind}</span></div><p>{reason}</p><div class="sizes"><span>18pt</span><i class="small">{svg}</i><span>32pt</span><i class="medium">{svg}</i></div></button>')

page = r'''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Bilby · 图标探索</title>
<style>
:root{color-scheme:light;--bg:#f4f1eb;--card:#fcfaf6;--ink:#242c30;--muted:#71736f;--line:#dad8d0;--accent:#a46b3a}*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:14px/1.65 -apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif}body.dark{color-scheme:dark;--bg:#181d20;--card:#23292d;--ink:#eee9df;--muted:#a4aaa9;--line:#42494c;--accent:#e5b983}main{max-width:1160px;margin:auto;padding:38px 28px 54px}header{display:flex;justify-content:space-between;align-items:center;gap:20px;margin-bottom:24px}h1{font-size:34px;letter-spacing:-1px;margin:0}header p{margin:2px 0 0;color:var(--muted)}button{font:inherit;cursor:pointer}.theme{border:1px solid var(--line);background:var(--card);color:var(--ink);border-radius:20px;padding:7px 14px}.preview{border:1px solid var(--line);border-radius:18px;overflow:hidden;background:var(--card);margin-bottom:25px}.menu{display:flex;align-items:center;gap:15px;padding:14px 20px;font-weight:600}.menu.light{background:#f7f5f0;color:#202526}.menu.dark{background:#202426;color:#f6f1e9}.menu .space{flex:1}.menu svg{display:block;width:18px;height:18px}.menu .system{font-size:17px;line-height:18px}.menu time{font-size:12px;font-weight:500}.caption{padding:12px 20px;border-top:1px solid var(--line);color:var(--muted)}.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:18px}.card{padding:22px;text-align:left;color:var(--ink);background:var(--card);border:1px solid var(--line);border-radius:16px;transition:transform .2s,border-color .2s}.card:hover{transform:translateY(-3px)}.card.selected{border:2px solid var(--accent);padding:21px}.canvas{height:135px;display:grid;place-items:center}.canvas svg{width:108px;height:108px}.title{display:flex;align-items:center;justify-content:space-between;margin-top:14px}.title b{font-size:18px}.title span{font-size:11px;color:var(--muted)}p{color:var(--muted);min-height:68px;font-size:12px}.sizes{display:flex;align-items:center;gap:12px;margin-top:15px;padding-top:14px;border-top:1px solid var(--line);color:var(--muted);font-size:10px}.sizes i{display:block;color:var(--ink)}.small svg{display:block;width:18px;height:18px}.medium svg{display:block;width:32px;height:32px}footer{margin-top:25px;display:flex;gap:20px;align-items:center;flex-wrap:wrap;color:var(--muted);font-size:12px}a{color:var(--ink)}@media(max-width:800px){.grid{grid-template-columns:repeat(2,1fr)}}@media(max-width:520px){.grid{grid-template-columns:1fr}.menu .appmenu{display:none}}@media(prefers-reduced-motion:reduce){*{transition:none!important}}
</style><main><header><div><h1>Bilby</h1><p>兔耳袋狸 · 原生状态栏工具</p></div><button class="theme" onclick="document.body.classList.toggle('dark')">切换深浅色</button></header><div class="preview"><div class="menu light"><span>●</span><span>Finder</span><span class="appmenu">文件　编辑　显示</span><span class="space"></span><span class="chosen"></span><span class="system">◔</span><time>09:41</time></div><div class="menu dark"><span>●</span><span>Finder</span><span class="appmenu">文件　编辑　显示</span><span class="space"></span><span class="chosen"></span><span class="system">◔</span><time>09:41</time></div><div class="caption">图标按实际 18pt 显示。点击方案可同时检查深浅色菜单栏；当前应用采用「侧影」。</div></div><section class="grid">CARDS</section><footer><span>六个独立方向 · 单色 SVG · 无外部字体或脚本</span><a id="download" href="01-side.svg" download>下载选中的 SVG</a></footer></main><script>
const cards=[...document.querySelectorAll('.card')];function select(card){cards.forEach(x=>{x.classList.toggle('selected',x===card);x.setAttribute('aria-pressed',String(x===card))});document.querySelectorAll('.chosen').forEach(x=>x.innerHTML=card.querySelector('.canvas').innerHTML);document.querySelector('#download').href=card.dataset.slug+'.svg'}cards.forEach(x=>x.addEventListener('click',()=>select(x)));select(cards[0]);
</script></html>'''.replace('CARDS', '\n'.join(cards))
page = page.replace('当前应用采用「侧影」', '当前应用采用「探头」').replace('select(cards[0])', 'select(cards[3])').replace('href="01-side.svg"', 'href="04-peek.svg"')
page = page.replace('图标按实际 18pt 显示。', '状态栏使用 20pt 画布，图形本体按 17.5pt 显示。').replace('.menu svg{display:block;width:18px;height:18px}', '.menu svg{display:block;width:20px;height:20px}')
page = page.replace("document.querySelectorAll('.chosen').forEach(x=>x.innerHTML=card.querySelector('.canvas').innerHTML)", "document.querySelectorAll('.chosen').forEach(x=>{x.innerHTML=card.querySelector('.canvas').innerHTML;const svg=x.querySelector('svg');const b=svg.getBBox();const side=Math.max(b.width,b.height)*20/17.5;svg.setAttribute('viewBox',`${b.x+b.width/2-side/2} ${b.y+b.height/2-side/2} ${side} ${side}`)})")
for previous, current in {'#f4f1eb': '#f4f4f5', '#fcfaf6': '#ffffff', '#242c30': '#222326', '#dad8d0': '#dedfe1', '#a46b3a': '#27282b', '#eee9df': '#f1f2f3', '#e5b983': '#eeeeee', '#f7f5f0': '#f7f7f7', '#f6f1e9': '#f6f6f6'}.items():
    page = page.replace(previous, current)
(output / 'index.html').write_text(page)
print(output / 'index.html')
