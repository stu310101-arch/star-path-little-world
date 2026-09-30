"""Inspect authored ecology without loading the world or rendering any models."""
import json
import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RADIUS = 48.0


def add(a, b):
    return tuple(x + y for x, y in zip(a, b))


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def mul(a, s):
    return tuple(x * s for x in a)


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def length(a):
    return math.sqrt(dot(a, a))


def distance(a, b):
    return length(sub(a, b))


def nearest(p, a, b):
    axis = sub(b, a)
    t = max(0.0, min(1.0, dot(sub(p, a), axis) / dot(axis, axis)))
    return add(a, mul(axis, t))


def surface(p):
    q = (p[0], RADIUS, p[1])
    return mul(q, RADIUS / length(q))


def route_distance(p, path):
    # A tangent straight segment maps to the same great-circle arc as Godot.
    # Half-metre samples bound the chord approximation error below 1 mm.
    point = surface(p)
    result = math.inf
    for a, b in zip(path, path[1:]):
        steps = max(1, math.ceil(distance(a, b) / 0.5))
        prev = surface(a)
        for i in range(1, steps + 1):
            following = surface(add(a, mul(sub(b, a), i / steps)))
            result = min(result, distance(point, nearest(point, prev, following)))
            prev = following
    return result


def water_distance(p, data):
    result = math.inf
    for water in data['water']:
        if water['kind'] == 'lake':
            local = tuple((a - b) / s for a, b, s in zip(p, water['center'], water['size']))
            angle = math.atan2(local[1], local[0])
            edge = 1 + 0.10 * math.sin(angle * 3) + 0.055 * math.cos(angle * 5)
            result = min(result, (length(local) - edge) * min(water['size']))
        else:
            for a, b in zip(water['points'], water['points'][1:]):
                result = min(result, distance(p, nearest(p, a, b)) - water['width'] / 2)
    return result


def edge_distance(p, data, index):
    local = tuple(a / s for a, s in zip(p, data['extent']))
    angle = math.atan2(local[1], local[0])
    edge = 1 + .045 * math.sin(angle * 3 + index) + .035 * math.cos(angle * 5 - index)
    return (edge - length(local)) * min(data['extent'])


def asset_radius(kind):
    raw = (ROOT / 'game/assets/ecology' / (kind + '.glb')).read_bytes()
    json_size = struct.unpack_from('<I', raw, 12)[0]
    scene = json.loads(raw[20:20 + json_size])
    binary = raw[28 + json_size:]
    result = 0.0
    for mesh in scene['meshes']:
        for primitive in mesh['primitives']:
            accessor = scene['accessors'][primitive['attributes']['POSITION']]
            view = scene['bufferViews'][accessor['bufferView']]
            offset = view.get('byteOffset', 0) + accessor.get('byteOffset', 0)
            stride = view.get('byteStride', 12)
            for i in range(accessor['count']):
                x, _, z = struct.unpack_from('<fff', binary, offset + i * stride)
                result = max(result, math.hypot(x, z))
    return result


def inspect():
    districts = json.loads((ROOT / 'game/data/districts.json').read_text(encoding='utf8'))
    plan = json.loads((ROOT / 'game/data/ecology_planting.json').read_text(encoding='utf8'))
    radii = {k: asset_radius(k) for k in ['alder', 'birch', 'willow', 'pine', 'fern', 'cattail', 'bank_stones']}
    print('Actual model crown/footprint radii:', {k: round(v, 3) for k, v in radii.items()})
    failures = []
    total_trees = total_understory = 0
    minimum_path_clearance = math.inf
    for index, data in enumerate(districts):
        authored = plan['districts'][data['station']]
        paths = data['paths'] + [[[0, -32.073], [0, 32.073]], [[-32.073, 0], [32.073, 0]]]
        roads = data['roads'] + [data['loop'] + [data['loop'][0]]]
        counts = [0, 0]
        # The reserve plan must respect the 18 authored bench/lamp specimen
        # trees that are preserved by the generator, not just other new trees.
        trees = [(p[0] + 2.0, p[1]) for p in data['gardens']]
        for group in authored['groups']:
            for category in ['trees', 'understory']:
                for row in group[category]:
                    kind, x, y, scale, yaw = row
                    p = (x, y)
                    solid = category == 'trees'
                    footprint = radii[kind] * scale
                    dry = min(edge_distance(p, data, index), water_distance(p, data))
                    path_gap = min(route_distance(p, path) - 1.1 for path in paths)
                    road_gap = min(route_distance(p, path) - 3.15 for path in roads)
                    issues = []
                    if dry < (1.0 if solid else .12):
                        issues.append(f'dry {dry:.2f}')
                    if path_gap < footprint + .12:
                        issues.append(f'path edge {path_gap:.2f} < footprint {footprint:.2f}')
                    # Street canopy may overhang above pedestrians; trunks/low
                    # planting remain completely outside the sidewalk surface.
                    if road_gap < (.55 if solid else footprint + .10):
                        issues.append(f'sidewalk edge {road_gap:.2f}')
                    for window in authored['view_windows']:
                        gap = route_distance(p, [window['from'], window['to']]) - window['half_width']
                        if gap < footprint:
                            issues.append(f'view {window["name"]}: {gap:.2f} < {footprint:.2f}')
                    if data['station'] == 'admissions':
                        deck_gap = route_distance(p, [[31.5, 6], [41, 6]]) - 2.7
                        boat_gap = distance(surface(p), surface((37, 11.1))) - 2.8
                        if min(deck_gap, boat_gap) < (3.0 if solid else .8):
                            issues.append(f'marina {min(deck_gap, boat_gap):.2f}')
                    for building in data['urban_buildings']:
                        # Authored sizes are tangent-plane maxima, so this is
                        # conservative for these radial placements at the edge.
                        bx, by = building['offset']
                        dx = max(0, abs(x - bx) - building.get('max_width', 4) / 2)
                        dy = max(0, abs(y - by) - building.get('max_depth', 4) / 2)
                        if math.hypot(dx, dy) < footprint + (.1 if solid else 0.0):
                            issues.append('building and foliage footprint overlap')
                    if solid:
                        for q in trees:
                            if distance(surface(p), surface(q)) < 2.25:
                                issues.append(f'tree spacing {q}')
                        trees.append(p)
                    minimum_path_clearance = min(minimum_path_clearance, path_gap - footprint)
                    if issues:
                        failures.append({'district': data['station'], 'group': group['name'], 'position': p, 'kind': kind, 'issues': issues})
                    counts[0 if solid else 1] += 1
        total_trees += counts[0]
        total_understory += counts[1]
        print(data['station'], {'reserve_trees': counts[0], 'pocket_specimens_preserved': len(data['gardens']), 'understory': counts[1], 'groups': len(authored['groups'])})
    for failure in failures:
        print(json.dumps(failure, ensure_ascii=False))
    report = {'reserve_trees': total_trees, 'pocket_specimens_preserved': sum(len(d['gardens']) for d in districts), 'understory': total_understory, 'minimum_path_foliage_gap': minimum_path_clearance, 'failures': failures}
    output = ROOT / 'deliverables/authored-garden/planting-data-checks.json'
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf8')
    print('PLANTING_DATA_CHECKS', len(failures), 'failures; reserve trees', total_trees, '; understory', total_understory)
    return bool(failures)


if __name__ == '__main__':
    raise SystemExit(inspect())
