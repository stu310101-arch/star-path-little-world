"""Fetch exact CC0 source maps; retain hashes and licensing beside game assets."""
from pathlib import Path
import concurrent.futures, hashlib, json, urllib.request

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'game/assets/world_materials'
ASSETS = ['forest_ground_04', 'rocky_terrain_02', 'wooden_planks', 'cobblestone_floor_03', 'leafy_grass']

def read(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'}), timeout=90).read()

def fetch(asset):
    catalog = json.loads(read('https://api.polyhaven.com/files/' + asset))
    records = []
    for channel in ['Diffuse', 'nor_gl', 'Rough']:
        spec = catalog[channel]['1k']['jpg']
        path = OUT / (asset + '_' + channel.lower() + '.jpg')
        if not path.exists() or hashlib.md5(path.read_bytes()).hexdigest() != spec['md5']:
            content = read(spec['url'])
            assert hashlib.md5(content).hexdigest() == spec['md5'], spec['url']
            path.write_bytes(content)
        records.append({'file': path.name, 'source': spec['url'], 'md5': spec['md5'], 'bytes': path.stat().st_size})
    print(asset, 'verified', flush=True)
    return {'id': asset, 'source': 'https://polyhaven.com/a/' + asset, 'license': 'CC0-1.0', 'maps': records}

if __name__ == '__main__':
    OUT.mkdir(parents=True, exist_ok=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        assets = list(pool.map(fetch, ASSETS))
    (OUT / 'manifest.json').write_text(json.dumps({'license_source': 'https://polyhaven.com/license', 'resolution': '1024', 'assets': assets}, indent=2), encoding='utf-8')
    (OUT / 'LICENSE.txt').write_text('Poly Haven assets: CC0 1.0 Universal. https://polyhaven.com/license\nForest Ground 04 / Cobblestone Floor 03: Rob Tuytel (Forest Ground adjustment: Rico Cilliers).\nRocky Terrain 02: Amal Kumar. Wooden Planks: Charlotte Baglioni and Dario Barresi. Leafy Grass: Charlotte Baglioni.\nSource maps are unmodified. Runtime shader controls color, texture scale and roughness.\n', encoding='utf-8')
