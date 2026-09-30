"""Derive the world's Walk/Run/JumpDown + frozen Idle GLB without changing the art master.

Retain every target used by locomotion, entry jumping and the first Idle pose.
All kept geometry, bone tracks and material values remain unchanged.
"""
import copy
import hashlib
import json
import pathlib
import struct

ROOT = pathlib.Path(__file__).resolve().parents[1]
source = ROOT / 'art/Graduate/Godot/assets/graduate.glb'
target = ROOT / 'game/assets/character/graduate.glb'
raw = source.read_bytes()
json_len = struct.unpack_from('<I', raw, 12)[0]
doc = json.loads(raw[20:20 + json_len])
binary = bytearray(raw[28 + json_len:])
assert not doc.get('extensionsRequired'), 'Review required extensions before optimizing'

def floats(index):
    accessor = doc['accessors'][index]
    assert accessor['componentType'] == 5126
    view = doc['bufferViews'][accessor['bufferView']]
    components = {'SCALAR': 1, 'VEC3': 3, 'VEC4': 4}[accessor['type']]
    count = accessor['count'] * components
    assert view.get('byteStride', 4 * components) == 4 * components
    offset = view.get('byteOffset', 0) + accessor.get('byteOffset', 0)
    return list(struct.unpack_from('<' + 'f' * count, binary, offset))

def append(values, kind):
    while len(binary) % 4:
        binary.append(0)
    data = struct.pack('<' + 'f' * len(values), *values)
    vi = len(doc['bufferViews'])
    doc['bufferViews'].append({'buffer': 0, 'byteOffset': len(binary), 'byteLength': len(data)})
    binary.extend(data)
    components = {'SCALAR': 1, 'VEC3': 3, 'VEC4': 4}[kind]
    accessor = {'bufferView': vi, 'componentType': 5126, 'count': len(values) // components, 'type': kind}
    if kind == 'SCALAR':
        accessor.update(min=[min(values)], max=[max(values)])
    doc['accessors'].append(accessor)
    return len(doc['accessors']) - 1

clips = [a for a in doc['animations'] if a['name'] in ('Walk', 'Run', 'JumpDown', 'Idle')]
used = {i: set() for i in range(len(doc['meshes']))}
for ni, node in enumerate(doc['nodes']):
    if 'mesh' not in node:
        continue
    mi = node['mesh']
    defaults = node.get('weights', doc['meshes'][mi].get('weights', []))
    used[mi].update(i for i, value in enumerate(defaults) if value != 0)
for clip in clips:
    for channel in clip['channels']:
        if channel['target']['path'] != 'weights':
            continue
        mi = doc['nodes'][channel['target']['node']]['mesh']
        count = len(doc['meshes'][mi]['primitives'][0]['targets'])
        sampler = clip['samplers'][channel['sampler']]
        assert sampler.get('interpolation', 'LINEAR') == 'LINEAR'
        values = floats(sampler['output'])
        if clip['name'] == 'Idle':
            values = values[:count]
        used[mi].update(i % count for i, value in enumerate(values) if value != 0)

original_counts = {i: len(m['primitives'][0].get('targets', [])) for i, m in enumerate(doc['meshes'])}
keep = {i: sorted(values) for i, values in used.items()}
for clip in clips:
    new_channels, new_samplers = [], []
    for channel in clip['channels']:
        sampler = copy.deepcopy(clip['samplers'][channel['sampler']])
        new_channel = copy.deepcopy(channel)
        kind = doc['accessors'][sampler['output']]['type']
        if channel['target']['path'] == 'weights':
            mi = doc['nodes'][channel['target']['node']]['mesh']
            if not keep[mi]:
                continue
            count = original_counts[mi]
            values = floats(sampler['output'])
            frames = len(values) // count
            if clip['name'] == 'Idle':
                values = [values[i] for i in keep[mi]] * 2
            else:
                # Every removed target has zero weight at every source key.
                assert all(values[f * count + i] == 0 for f in range(frames) for i in range(count) if i not in used[mi])
                values = [values[f * count + i] for f in range(frames) for i in keep[mi]]
            sampler['output'] = append(values, 'SCALAR')
        elif clip['name'] == 'Idle':
            components = {'SCALAR': 1, 'VEC3': 3, 'VEC4': 4}[kind]
            sampler['output'] = append(floats(sampler['output'])[:components] * 2, kind)
        if clip['name'] == 'Idle':
            sampler['input'] = append([0.0, 1.0], 'SCALAR')
        new_channel['sampler'] = len(new_samplers)
        new_channels.append(new_channel)
        new_samplers.append(sampler)
    clip['channels'], clip['samplers'] = new_channels, new_samplers
doc['animations'] = clips
for mi, mesh in enumerate(doc['meshes']):
    for primitive in mesh['primitives']:
        if primitive.get('targets'):
            primitive['targets'] = [primitive['targets'][i] for i in keep[mi]]
            if not primitive['targets']:
                del primitive['targets']
    if 'weights' in mesh:
        mesh['weights'] = [mesh['weights'][i] for i in keep[mi]]
    if 'targetNames' in mesh.get('extras', {}):
        mesh['extras']['targetNames'] = [mesh['extras']['targetNames'][i] for i in keep[mi]]
for node in doc['nodes']:
    if 'weights' in node:
        node['weights'] = [node['weights'][i] for i in keep[node['mesh']]]

# Collect and remap only reachable accessors, then their buffer views.
references = []
def reference(mapping, key):
    references.append((mapping, key))
for mesh in doc['meshes']:
    for primitive in mesh['primitives']:
        for key in primitive['attributes']:
            reference(primitive['attributes'], key)
        if 'indices' in primitive:
            reference(primitive, 'indices')
        for morph in primitive.get('targets', []):
            for key in morph:
                reference(morph, key)
for skin in doc.get('skins', []):
    if 'inverseBindMatrices' in skin:
        reference(skin, 'inverseBindMatrices')
for clip in clips:
    for sampler in clip['samplers']:
        reference(sampler, 'input')
        reference(sampler, 'output')
indices = sorted({mapping[key] for mapping, key in references})
remap = {old: new for new, old in enumerate(indices)}
accessors = [doc['accessors'][old] for old in indices]
for mapping, key in references:
    mapping[key] = remap[mapping[key]]
doc['accessors'] = accessors
view_refs = []
for accessor in accessors:
    if 'bufferView' in accessor:
        view_refs.append(accessor)
    if 'sparse' in accessor:
        view_refs.append(accessor['sparse']['indices'])
        view_refs.append(accessor['sparse']['values'])
view_refs += [image for image in doc.get('images', []) if 'bufferView' in image]
view_indices = sorted({a['bufferView'] for a in view_refs})
new_binary, new_views = bytearray(), []
for old in view_indices:
    view = copy.deepcopy(doc['bufferViews'][old])
    while len(new_binary) % 4:
        new_binary.append(0)
    start = view.get('byteOffset', 0)
    data = binary[start:start + view['byteLength']]
    view['byteOffset'] = len(new_binary)
    view['buffer'] = 0
    new_binary.extend(data)
    new_views.append(view)
remap = {old: new for new, old in enumerate(view_indices)}
for mapping in view_refs:
    mapping['bufferView'] = remap[mapping['bufferView']]
doc['bufferViews'] = new_views
doc['buffers'] = [{'byteLength': len(new_binary)}]
encoded = json.dumps(doc, separators=(',', ':')).encode()
encoded += b' ' * ((-len(encoded)) % 4)
new_binary.extend(b'\0' * ((-len(new_binary)) % 4))
result = struct.pack('<III', 0x46546C67, 2, 28 + len(encoded) + len(new_binary))
result += struct.pack('<II', len(encoded), 0x4E4F534A) + encoded
result += struct.pack('<II', len(new_binary), 0x004E4942) + new_binary
target.write_bytes(result)
report = {'source': str(source.relative_to(ROOT)), 'source_sha256': hashlib.sha256(raw).hexdigest(), 'source_bytes': len(raw), 'world_bytes': len(result), 'kept_clips': ['Walk', 'Run', 'JumpDown', 'Idle (frozen first pose)'], 'removed_weights_all_zero': True, 'targets_before': sum(original_counts.values()), 'targets_after': sum(map(len, keep.values()))}
(ROOT / 'game/assets/character/derivation.json').write_text(json.dumps(report, indent=2), encoding='utf8')
print(json.dumps(report, indent=2))
