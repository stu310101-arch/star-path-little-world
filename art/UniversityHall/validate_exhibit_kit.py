"""Read-only export audit; no Blender or Godot process is started."""
from pathlib import Path
import json, math, struct

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / 'art/UniversityHall'
OUT = ROOT / 'game/assets/university_hall'
blob = (OUT / 'exhibit_kit.glb').read_bytes()
assert blob[:4] == b'glTF'
json_size = struct.unpack_from('<I', blob, 12)[0]
doc = json.loads(blob[20:20 + json_size])
binary = memoryview(blob)[28 + json_size:]
manifest = json.loads((OUT / 'kit_manifest.json').read_text(encoding='utf-8'))
errors = []

def check(value, message):
    if not value:
        errors.append(message)

def floats(index):
    accessor = doc['accessors'][index]
    view = doc['bufferViews'][accessor['bufferView']]
    count = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[accessor['type']]
    assert accessor['componentType'] == 5126
    start = view.get('byteOffset', 0) + accessor.get('byteOffset', 0)
    stride = view.get('byteStride', count * 4)
    return [struct.unpack_from('<' + 'f' * count, binary, start + i * stride)
            for i in range(accessor['count'])]

roots = doc['scenes'][doc.get('scene', 0)]['nodes']
names = [doc['nodes'][i].get('name') for i in roots]
check(len(roots) == 44, 'Expected 8 displays and 36 components')
check(set(names) == set(manifest['module_keys']), 'Root names differ from manifest')
check(len(names) == len(set(names)), 'Duplicate root name')
for index in roots:
    node = doc['nodes'][index]
    check('mesh' in node and not node.get('children'), 'Root is not one packed mesh: ' + node['name'])
    check(not any(k in node for k in ['matrix', 'translation', 'rotation', 'scale']),
          'Non-identity exported transform: ' + node['name'])
    for primitive in doc['meshes'][node['mesh']]['primitives']:
        attr = primitive['attributes']
        check('TEXCOORD_0' in attr and 'NORMAL' in attr, 'UV or normals missing: ' + node['name'])
        for p in floats(attr['POSITION']):
            check(all(math.isfinite(v) for v in p), 'Nonfinite vertex: ' + node['name'])
        for normal in floats(attr['NORMAL']):
            length = sum(v*v for v in normal)
            check(.95 < length < 1.05, 'Invalid normal: ' + node['name'])
for material in doc['materials']:
    check(material['name'].startswith('MAT_University_Library_'), 'Unmapped material prefix')
check(len(doc.get('images', [])) == 24, 'Unexpected additional embedded images')
check('palette_import.gd' in (OUT/'exhibit_kit.glb.import').read_text(encoding='utf-8'),
      'Missing canonical texture import hook')
for key, info in manifest['modules'].items():
    if key.startswith('component_'):
        check(abs(info['bounds_min'][1]) < .0001, 'Component is not floor rooted: ' + key)
        check(info['bounds_max'][1] <= 1.0501, 'Component exceeds height contract: ' + key)
report = {'asset': 'exhibit_kit.glb', 'revision': manifest['revision'],
          'root_children': len(roots), 'triangles': manifest['triangles_total'],
          'bytes': len(blob), 'material_count': len(doc['materials']),
          'embedded_images': len(doc.get('images', [])),
          'errors': sorted(set(errors)), 'passed': not errors,
          'scope': 'Raw GLB names, transforms, UVs, normals, finite vertices, floor-rooted bounds, canonical import hook. Actual Godot screenshots remain the visual acceptance evidence.'}
(ART / 'kit_validation_report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(report, ensure_ascii=False))
raise SystemExit(1 if errors else 0)
