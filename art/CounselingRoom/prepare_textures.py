"""Fetch licensed source maps and derive the room's 2K oak and 1K woven-fabric runtime palette."""
from pathlib import Path
import urllib.request, zipfile, json, hashlib
from PIL import Image, ImageEnhance, ImageOps

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / 'art/CounselingRoom'
SRC = ART / 'sources'
TEX = ROOT / 'game/assets/counseling_room/textures'
SRC.mkdir(parents=True, exist_ok=True)
TEX.mkdir(parents=True, exist_ok=True)
records = []

def fetch(url, path):
    if not path.exists():
        request = urllib.request.Request(url, headers={'User-Agent': 'StarPath-LittleWorld/1.0 (asset preparation)'})
        path.write_bytes(urllib.request.urlopen(request, timeout=60).read())

for channel in ['diff', 'rough', 'nor_gl']:
    url = f'https://dl.polyhaven.org/file/ph-assets/Textures/jpg/2k/wood_floor/wood_floor_{channel}_2k.jpg'
    path = SRC / f'wood_floor_{channel}_2k.jpg'
    fetch(url, path)
    records.append(dict(asset='Poly Haven Wood Floor', url=url, file=path.name,
                        sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                        license='CC0-1.0', author='Dimitrios Savva'))
url = 'https://acg-download.struffelproductions.com/file/ambientCG-Web/download/Fabric060_v6pQ2xeI/Fabric060_1K-JPG.zip'
archive = SRC / 'Fabric060_1K-JPG.zip'
fetch(url, archive)
records.append(dict(asset='ambientCG Fabric 060', url=url, file=archive.name,
                    sha256=hashlib.sha256(archive.read_bytes()).hexdigest(),
                    license='CC0-1.0', author='ambientCG'))
with zipfile.ZipFile(archive) as package:
    for name in package.namelist():
        if name.endswith(('_Color.jpg', '_Roughness.jpg', '_NormalGL.jpg')):
            (SRC / Path(name).name).write_bytes(package.read(name))
for suffix, channel in [('base', 'diff'), ('rough', 'rough'), ('normal', 'nor_gl')]:
    image = Image.open(SRC / f'wood_floor_{channel}_2k.jpg').convert('RGB')
    if suffix == 'base':
        image = ImageEnhance.Color(image).enhance(.60)
        image = ImageEnhance.Contrast(image).enhance(.62)
        image = Image.blend(image, Image.new('RGB', image.size, (221, 195, 153)), .39)
    image.save(TEX / f'oak_{suffix}.png')
api_path = SRC / 'wood_table_001-files.json'
fetch('https://api.polyhaven.com/files/wood_table_001', api_path)
joinery_api = json.loads(api_path.read_text(encoding='utf-8'))
for suffix, channel in [('base', 'diff'), ('rough', 'rough'), ('normal', 'nor_gl')]:
    source = joinery_api[{'diff':'Diffuse','rough':'Rough','nor_gl':'nor_gl'}[channel]]['2k']['jpg']
    path = SRC / f'wood_table_001_{channel}_2k.jpg'
    fetch(source['url'], path)
    raw = path.read_bytes()
    assert len(raw) == source['size'] and hashlib.md5(raw).hexdigest() == source['md5']
    image = Image.open(path).convert('RGB')
    assert image.size == (2048, 2048)
    if suffix == 'base':
        image = ImageOps.colorize(ImageOps.grayscale(image), (76, 56, 37), (215, 182, 136))
    image.save(TEX / f'joinery_{suffix}.png')
    records.append(dict(asset='Poly Haven Wood Table 001', url=source['url'], file=path.name,
        sha256=hashlib.sha256(raw).hexdigest(), md5_verified=source['md5'], bytes=len(raw),
        license='CC0-1.0', author='Dimitrios Savva (photography), Rico Cilliers (processing)'))
for key, color in [('sage', (151, 178, 148)), ('apricot', (226, 164, 128)), ('linen', (192, 177, 150))]:
    image = Image.open(next(SRC.glob('Fabric060*_Color.jpg'))).convert('L')
    image = ImageEnhance.Contrast(image).enhance(.38)
    image = ImageOps.colorize(image, tuple(int(c*.70) for c in color), tuple(min(255, int(c*1.08)) for c in color))
    image.save(TEX / f'{key}_base.png')
for dest, pattern in [('fabric_rough.png', 'Fabric060*_Roughness.jpg'), ('fabric_normal.png', 'Fabric060*_NormalGL.jpg')]:
    Image.open(next(SRC.glob(pattern))).convert('RGB').save(TEX / dest)
(ART / 'sources.json').write_text(json.dumps({'downloaded': '2026-10-24', 'assets': records,
    'modifications': 'Runtime floor wood lightened and contrast reduced. Separate Wood Table 001 furniture wood is recolored warm honey while preserving source grain, normal and roughness. Fabric colorized sage, apricot, linen; original source maps preserved. Both wood map sets 2048x2048 from native 2K sources; fabric maps 1024x1024. No image upscaling.'}, indent=2), encoding='utf-8')
print(json.dumps({'downloaded': [(r['file'], (SRC/r['file']).stat().st_size) for r in records], 'textures': len(list(TEX.glob('*.png')))}, indent=2))
