"""Package actual native bench/access captures alongside the playable build."""
from pathlib import Path
import html
import shutil

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "deliverables/bench-rest"
WEB = ROOT / "build/web"
DEST = WEB / "bench-images"
DEST.mkdir(exist_ok=True)
views = [
    ("05-east-entrance", "櫻花庭園・東側入口", "步道直通長椅正面，外緣保留護欄。", 0),
    ("06-west-entrance", "櫻花庭園・西側入口", "兩側都留出完整的進出空間。", 1),
    ("01-east-seated-close", "坐下，看看櫻花", "靠近椅子按 E 或點畫面按鈕，再按 E 起身。", 0),
    ("02-west-seated-close", "樹影下休息", "坐姿、膝蓋與衣襬隨坐下動作調整。", 1),
    ("03-marina-seated-close", "碼頭長椅", "座椅朝向中央甲板，正前方可正常進出。", 2),
    ("04-civic-seated-close", "各區街角長椅", "全世界 34 張同類長椅都能坐下休息。", 0),
]
cards = []
for filename, title, description, index in views:
    file = filename + ".jpg"
    assert (OUT / file).is_file(), file
    shutil.copy2(OUT / file, DEST / file)
    cards.append(f'<article><img src="bench-images/{file}" alt="{html.escape(title)}實際遊戲畫面"><div><h2>{html.escape(title)}</h2><p>{html.escape(description)}</p></div></article>')
page = '''<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>星途｜坐下休息</title><style>
*{box-sizing:border-box}body{margin:0;background:#102e33;color:#f1eee1;font:16px/1.8 system-ui,"Microsoft JhengHei",sans-serif}main{max-width:1160px;margin:auto;padding:40px 24px}header{max-width:800px;margin-bottom:32px}small{letter-spacing:.14em;color:#adc6b9}h1{font-size:38px;line-height:1.3;margin:12px 0}p{color:#cad8cc}section{display:grid;grid-template-columns:1fr 1fr;gap:24px}article{background:#1b3c40;border:1px solid #48645b;border-radius:16px;overflow:hidden}img{display:block;width:100%;height:auto}article div{padding:16px 22px}h2{font-size:22px;margin:4px 0}p{margin:8px 0 16px}a{display:inline-block;color:#173c40;background:#efd7a5;padding:10px 18px;border-radius:10px;text-decoration:none;font-weight:600}footer{margin-top:28px;color:#b5c8bd;font-size:14px}@media(max-width:720px){main{padding:26px 16px}section{grid-template-columns:1fr}h1{font-size:30px}}
</style><main><header><small>星途 · LITTLE WORLD</small><h1>在櫻花下，坐一會兒</h1><p>兩處庭園長椅已轉向步道，欄杆留下寬敞入口。靠近任何長椅，按 E 或點「坐下休息」；再按 E 起身，回到椅子前方繼續走。</p><a href="index.html?v=20260926-bench#review-bench-0">前往櫻花庭園 ↗</a></header><section>''' + ''.join(cards) + '''</section><footer>以上為實際原生遊戲畫面。遊戲操作：WASD 移動 · E 坐下／起身 · 按住左／右鍵拖曳視角。<br>網頁遊戲首次載入需下載完整世界。</footer></main></html>'''
(WEB / "bench-review.html").write_text(page, encoding="utf-8")
(OUT / "bench-review.html").write_text(page.replace("bench-images/", "").replace('href="index.html', 'href="http://127.0.0.1:8765/index.html'), encoding="utf-8")
print("BENCH_REVIEW_PACKAGED")
