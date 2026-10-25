"""Add mobile selection and a bounded, versioned offline asset cache."""
from pathlib import Path
import argparse
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[1]

def inject(folder):
    html_path = folder / 'index.html'
    html = html_path.read_text(encoding='utf-8')
    html = html.replace('<html lang="en">', '<html lang="zh-Hant">')
    html = re.sub(r'<meta name="viewport"[^>]*>', '<meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no, viewport-fit=cover">', html)
    # Home Screen launch removes browser chrome on iOS, where the ordinary
    # Fullscreen API is not available on every supported device/browser.
    mobile_start, mobile_end = '<!-- LITTLE_WORLD_MOBILE_BEGIN -->', '<!-- LITTLE_WORLD_MOBILE_END -->'
    html = re.sub(re.escape(mobile_start) + r'.*?' + re.escape(mobile_end) + r'\n?', '', html, flags=re.S)
    html = html.replace('</head>', mobile_start + '''
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="apple-mobile-web-app-title" content="星途">
<meta name="theme-color" content="#17343c">
<link rel="manifest" href="index.webmanifest">
<link rel="apple-touch-icon" sizes="180x180" href="index.icon-180.png">
<style>
html, body { width: 100%; height: 100%; overscroll-behavior: none; }
html:fullscreen, html:-webkit-full-screen { width: 100%; height: 100%; }
</style>
''' + mobile_end + '\n</head>')
    root = '../' if folder.name == 'mobile' else './'
    manifest = {'id': root, 'name': '星途 · Little World', 'short_name': '星途',
                'lang': 'zh-Hant', 'start_url': root, 'scope': root,
                'display': 'standalone', 'background_color': '#17343c', 'theme_color': '#17343c',
                'icons': [{'src': f'index.icon-{size}.png', 'sizes':f'{size}x{size}', 'type': 'image/png', 'purpose': 'any maskable'} for size in (192,512)]}
    from PIL import Image, ImageDraw
    for size in (180,192,512):
        image = Image.new('RGB', (size,size), '#173b3d')
        draw = ImageDraw.Draw(image)
        unit = size / 512
        draw.ellipse(tuple(round(v*unit) for v in (112,112,400,400)),fill='#96b8aa')
        draw.arc(tuple(round(v*unit) for v in (62,186,450,330)),15,205,fill='#e7b579',width=max(2,round(18*unit)))
        draw.ellipse(tuple(round(v*unit) for v in (320,124,366,170)),fill='#f7f3e7')
        image.save(folder / f'index.icon-{size}.png')
    (folder / 'index.webmanifest').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    html = html.replace('<script src="index.platform.js"></script>\n', '')
    html = html.replace('<script src="index.touch.js"></script>\n', '')
    html = html.replace('<script src="index.resources.js"></script>\n', '')
    html = html.replace('<script src="index.js"></script>', '<script src="index.platform.js"></script>\n<script src="index.resources.js"></script>\n<script src="index.touch.js"></script>\n<script src="index.js"></script>')
    anchor = 'const engine = new Engine(GODOT_CONFIG);'
    assert html.count(anchor) == 1
    start, end = '// LITTLE_WORLD_PLATFORM_BEGIN', '// LITTLE_WORLD_PLATFORM_END'
    html = re.sub(re.escape(start) + r'.*?' + re.escape(end) + r'\n?', '', html, flags=re.S)
    html = html.replace(anchor, anchor + '\n' + start + '''
const littleWorldStart = engine.startGame.bind(engine);
engine.startGame = options => window.LittleWorldRedirecting ? new Promise(() => {}) : Promise.all([window.LittleWorldResourceReady, window.LittleWorldCacheReady]).then(() => littleWorldStart(options));
''' + end)
    html_path.write_text(html, encoding='utf-8', newline='\n')
    (folder / 'index.platform.js').write_bytes((ROOT / 'tools/web_platform.js').read_bytes())
    (folder / 'index.touch.js').write_bytes((ROOT / 'tools/web_touch.js').read_bytes())
    (folder / 'index.resources.js').write_bytes((ROOT / 'tools/web_resource_profile.js').read_bytes())

def resource_cache_groups(folder, virtual_files=None):
    """Map installation and optional closures to real gzip/fallback/chunk URLs."""
    virtual_files = virtual_files or {}
    profiles = {}
    on_demand = {}
    for renderer, prefix in (('desktop',''),('mobile','mobile/')):
        base = folder / prefix
        manifest = json.loads((base / 'index.packs.json').read_text(encoding='utf-8'))
        delivery = json.loads((base / 'index.delivery.json').read_text(encoding='utf-8')).get('packs', {})
        def paths(keys, fallback=False):
            result = set()
            for key in keys:
                raw = manifest['packs'][key]['url']
                names = {delivery.get(key, {}).get('url', raw)}
                if fallback:
                    names.add(raw)
                for name in names:
                    path = prefix + name
                    virtual = virtual_files.get(path)
                    result.update(part['url'] for part in virtual['parts']) if virtual else result.add(path)
            return sorted(result)
        profiles[renderer] = {
            profile:paths(keys)
            for profile,keys in manifest.get('profiles', {}).items()
        }
        # Include raw fallback too: it can be requested if compressed delivery fails.
        on_demand[renderer] = paths(manifest.get('shared_on_demand', []), fallback=True)
    return {'profiles':profiles, 'shared_on_demand':on_demand}

def worker(folder):
    stamp_path = folder / 'index.release.json'
    stamp = json.loads(stamp_path.read_text(encoding='utf-8'))
    files = stamp['files']
    shells = [name for name in files if name.endswith(('.html','.js','.json','.webmanifest')) and not name.startswith('games/') and '/games/' not in name and not name.endswith('service-worker.js')]
    # Large engine/packs are cached only as the player actually requests them.
    config = {'build_id':stamp['build_id'], 'files':files, 'shell':shells, **resource_cache_groups(folder)}
    payload = ('const RELEASE = ' + json.dumps(config, separators=(',',':')) + ';\n').encode() + (ROOT / 'tools/web_service_worker.js').read_bytes()
    (folder / 'index.service-worker.js').write_bytes(payload)
    files['index.service-worker.js'] = {'bytes':len(payload), 'sha256':hashlib.sha256(payload).hexdigest()}
    stamp_path.write_text(json.dumps(stamp, indent=2) + '\n', encoding='utf-8')

if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('mode',choices=['inject','worker'])
    p.add_argument('--web-dir',type=Path,required=True)
    a=p.parse_args()
    (inject if a.mode == 'inject' else worker)(a.web_dir)
