"""Read-only structure validation of the complete academic library asset kit."""
from pathlib import Path
import json, struct

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / 'game/assets/university_hall'
EXPECTED = ['atrium', 'gallery', 'booth'] + ['theme_' + key for key in ['urban', 'woodland', 'hills', 'coast', 'arts', 'workshop']] + ['feature_' + key for key in ['palm', 'dairy', 'book', 'tea']]
report = {'revision': '2026-10-11-r3.1-library', 'assets': {}, 'failures': []}

def check(ok, description):
    if not ok:
        report['failures'].append(description)

for key in EXPECTED:
    path = ASSETS / (key + '.glb')
    raw = path.read_bytes()
    check(raw[:4] == b'glTF', key + ': GLB magic')
    size, kind = struct.unpack_from('<II', raw, 12)
    doc = json.loads(raw[20:20+size])
    primitives = [p for mesh in doc['meshes'] for p in mesh['primitives']]
    tri_count = sum(doc['accessors'][p['indices']]['count'] // 3 for p in primitives)
    families = [m.get('name', '') for m in doc['materials']]
    check(all(m.startswith('MAT_University_Library_') for m in families), key + ': stale palette material')
    check(all('TEXCOORD_0' in p['attributes'] for p in primitives), key + ': missing UV')
    check(all('COLOR_0' not in p['attributes'] for p in primitives), key + ': vertex palette unexpected')
    check(all('POSITION' in p['attributes'] and 'NORMAL' in p['attributes'] for p in primitives), key + ': missing geometry attributes')
    check(not doc.get('animations') and not doc.get('skins'), key + ': unexpected animation dependency')
    if key in ['atrium', 'gallery']:
        floors = [node for node in doc['nodes'] if node.get('name', '').endswith('_Floor')]
        check(len(floors) == 1, key + ': expected one separate floor mesh')
        if floors:
            floor_primitives = doc['meshes'][floors[0]['mesh']]['primitives']
            check(sum(doc['accessors'][p['indices']]['count'] for p in floor_primitives) == 6, key + ': floor should have exactly two triangles')
    report['assets'][key] = {'triangles': tri_count, 'bytes': len(raw), 'materials': families, 'embedded_images': len(doc.get('images', [])), 'surfaces': len(primitives)}

layout = json.loads((ASSETS / 'layout.json').read_text(encoding='utf-8'))
check(layout['style'] == 'classical_academic_library', 'layout style')
check(len(layout['atrium']['lights']) == 4, 'atrium practical light budget')
check(len(layout['gallery']['lights']) == 2, 'gallery practical light budget')
check(layout['booth']['display_collision_center'] == [0,1.43,-.20], 'glass collision center')
check(layout['booth']['display_collision_size'] == [4.96,1.08,1.84], 'glass collision size')
for room in ['atrium', 'gallery']:
    for collider in layout[room]['obstacles']:
        check('planter' not in collider['name'], room + ': ghost planter collider')
        check(all(v > 0 for v in collider['size']), room + ': collider has invalid size')
imports = list((ASSETS / 'textures').glob('*.png.import'))
check(len(imports) == 30, 'expected eight common and two floor texture families with three maps each')
for imported in imports:
    check('mipmaps/generate=true' in imported.read_text(encoding='utf-8'), imported.name + ': mipmaps disabled')
report['texture_count'] = len(imports)
report['raw_glb_bytes'] = sum(a['bytes'] for a in report['assets'].values())
report['canonical_png_bytes'] = sum(p.stat().st_size for p in (ASSETS / 'textures').glob('*.png'))
report['all_asset_triangles'] = sum(a['triangles'] for a in report['assets'].values())
report['note'] = 'Raw GLBs are self-contained. Imported Godot resources must reference canonical PNGs; inspect_godot_material.gd verifies this separately.'
destination = Path(__file__).with_name('glb_structure_checks.json')
destination.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps({'assets': len(report['assets']), 'raw_glb_bytes': report['raw_glb_bytes'], 'texture_count': len(imports), 'failures': report['failures']}))
raise SystemExit(bool(report['failures']))
