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
    html = html.replace('<script src="index.platform.js"></script>\n', '')
    html = html.replace('<script src="index.touch.js"></script>\n', '')
    html = html.replace('<script src="index.js"></script>', '<script src="index.platform.js"></script>\n<script src="index.touch.js"></script>\n<script src="index.js"></script>')
    anchor = 'const engine = new Engine(GODOT_CONFIG);'
    assert html.count(anchor) == 1
    start, end = '// LITTLE_WORLD_PLATFORM_BEGIN', '// LITTLE_WORLD_PLATFORM_END'
    html = re.sub(re.escape(start) + r'.*?' + re.escape(end) + r'\n?', '', html, flags=re.S)
    html = html.replace(anchor, anchor + '\n' + start + '''
const littleWorldStart = engine.startGame.bind(engine);
engine.startGame = options => window.LittleWorldRedirecting ? new Promise(() => {}) : window.LittleWorldCacheReady.then(() => littleWorldStart(options));
''' + end)
    html_path.write_text(html, encoding='utf-8', newline='\n')
    (folder / 'index.platform.js').write_bytes((ROOT / 'tools/web_platform.js').read_bytes())
    (folder / 'index.touch.js').write_bytes((ROOT / 'tools/web_touch.js').read_bytes())

def worker(folder):
    stamp_path = folder / 'index.release.json'
    stamp = json.loads(stamp_path.read_text(encoding='utf-8'))
    files = stamp['files']
    shells = [name for name in files if name.endswith(('.html','.js','.json')) and not name.startswith('games/') and '/games/' not in name and not name.endswith('service-worker.js')]
    # Large engine/packs are cached only as the player actually requests them.
    config = {'build_id':stamp['build_id'], 'files':files, 'shell':shells}
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
