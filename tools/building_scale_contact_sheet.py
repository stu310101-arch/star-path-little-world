"""CPU-only geometry contact sheet for measured existing assets; no world boot."""
import json, math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
data = json.loads((ROOT / 'deliverables/building-scale-source-probe.json').read_text(encoding='utf8'))
selected = [entry for entry in data if ('commercial/' in entry['asset'] and 'skyscraper' not in entry['asset']) or any(name in entry['asset'] for name in ['building-type-k.', 'building-type-l.', 'building-type-r.', 'building-type-o.', 'house-'])]
W, H = 310, 320
sheet = Image.new('RGB', (W * 6, H * math.ceil(len(selected) / 6)), '#d7ddd6')
font = ImageFont.truetype('C:/Windows/Fonts/consola.ttf', 16)
for ordinal, entry in enumerate(selected):
    tile = Image.new('RGB', (W, H), '#d7ddd6')
    draw = ImageDraw.Draw(tile)
    sx, sy, sz = entry['size']
    cx = entry['min'][0] + sx / 2
    cy = entry['min'][1]
    cz = entry['min'][2] + sz / 2
    # Commercial fronts are -Z before build_world rotates them; housing +Z.
    facing = -1 if entry['asset'].startswith('commercial/') else 1
    factor = min(3.5/sx, 4.3/sz)
    scale = min(64, 240 / max(sy * factor, 3.7))
    faces = []
    for part in entry['parts']:
        vertices, colors = part['vertices'], part['colors']
        ids = part['indices'] or list(range(len(vertices)))
        for i in range(0, len(ids), 3):
            points = [[(vertices[j][0]-cx)*factor, (vertices[j][1]-cy)*factor, (vertices[j][2]-cz)*factor*facing] for j in ids[i:i+3]]
            coords = [(W*.46+(x-z*.26)*scale, H-43-(y+z*.16)*scale) for x,y,z in points]
            depths = [z+y*.05-x*.03 for x,y,z in points]
            rgb = [sum(colors[j][axis] for j in ids[i:i+3])/3 for axis in range(3)]
            edges = [[points[1][axis]-points[0][axis] for axis in range(3)], [points[2][axis]-points[0][axis] for axis in range(3)]]
            a,b = edges
            normal = [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
            norm = math.sqrt(sum(x*x for x in normal)) or 1
            light = .66 + .26*abs(sum(normal[i]*[-.2,.7,.5][i] for i in range(3))/norm)
            fill = tuple(max(0,min(255,round(v*light*255))) for v in rgb)
            faces.append((sum(depths)/3,coords,fill))
    for _,coords,fill in sorted(faces):
        draw.polygon(coords,fill=fill)
    # 1.6 m capsule-height reference.
    draw.line((W-28,H-43,W-28,H-43-1.6*scale),fill='#a83b36',width=4)
    draw.text((7,8),Path(entry['asset']).stem,font=font,fill='#172e36')
    draw.text((7,28),f'W {sx*factor:.2f}  H {sy*factor:.2f}  D {sz*factor:.2f}',font=font,fill='#172e36')
    draw.text((7,H-24),'same 3.5m frontage limit',font=font,fill='#344a50')
    sheet.paste(tile,((ordinal%6)*W,(ordinal//6)*H))
sheet.save(ROOT/'deliverables/building-scale-candidates.png')
