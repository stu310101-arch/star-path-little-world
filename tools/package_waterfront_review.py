"""Package the six actual in-game screenshots with links to playable shore views."""
from pathlib import Path
import json
import html
import shutil

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "deliverables/water-ecology"
WEB = ROOT / "build/web"
plan = json.loads((ROOT / "game/data/water_ecology.json").read_text(encoding="utf-8"))
districts = json.loads((ROOT / "game/data/districts.json").read_text(encoding="utf-8"))
(WEB / "waterfront-images").mkdir(exist_ok=True)
cards = []
for i, (area, district) in enumerate(zip(plan["districts"], districts)):
    filename = f'{i:02}-{area["station"]}.jpg'
    assert (OUT / filename).is_file(), filename
    shutil.copy2(OUT / filename, WEB / "waterfront-images" / filename)
    title = html.escape(district["theme"])
    description = html.escape(area["description"])
    cards.append(f'<article><a href="index.html?v=20260926-water-v2#review-water-{i}"><img src="waterfront-images/{filename}" alt="{title}實際遊戲畫面"><div><span>0{i+1} / 水岸漫遊</span><h2>{title}</h2><p>{description}</p><b>到這裡走走 ↗</b></div></a></article>')
page = '''<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>星途｜六區水岸巡覽</title><style>
*{box-sizing:border-box}body{margin:0;background:#102e33;color:#f1eee1;font:16px/1.8 system-ui,"Microsoft JhengHei",sans-serif}main{max-width:1160px;margin:auto;padding:48px 24px}header{max-width:760px;margin-bottom:36px}small,span{letter-spacing:.14em;color:#adc6b9}h1{font-size:40px;line-height:1.3;margin:12px 0}header p{color:#cad8cc}section{display:grid;grid-template-columns:1fr 1fr;gap:24px}article{background:#1b3c40;border:1px solid #48645b;border-radius:16px;overflow:hidden}a{color:inherit;text-decoration:none}img{display:block;width:100%;height:auto}article div{padding:22px}h2{font-size:23px;margin:6px 0}p{margin:8px 0 18px}article span{font-size:12px}b{color:#ead395}footer{margin-top:36px;color:#b5c8bd;font-size:14px}@media(max-width:720px){main{padding:28px 16px}section{grid-template-columns:1fr}h1{font-size:30px}}
</style><main><header><small>星途 · LITTLE WORLD</small><h1>沿著水岸，看看這個小世界</h1><p>睡蓮湖、河口蘆葦、石岸溪流與濕地。六張圖都來自實際遊戲；點選場景即可站到岸邊，繼續自由漫遊。</p></header><section>'''+"".join(cards)+'''</section><footer>WASD 移動 · Shift 跑步 · 空白鍵空翻 · 按住左／右鍵拖曳視角<br>首次載入需下載完整遊戲。音樂可在遊戲右上角切換。</footer></main></html>'''
(WEB / "waterfront-review.html").write_text(page, encoding="utf-8")
(OUT / "waterfront-review.html").write_text(page.replace("waterfront-images/", "").replace('href="index.html', 'href="http://127.0.0.1:8765/index.html'), encoding="utf-8")
print("SIX_WATERFRONT_VIEWS_PACKAGED")
