"""Check authored garden spacing without starting the engine.

This supplements Godot character/shape queries; it does not claim runtime QA.
"""
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def local(point, zone):
    x = point[0] - zone['center'][0]
    z = point[2] - zone['center'][2]
    c, s = math.cos(zone['rotation_y']), math.sin(zone['rotation_y'])
    return (c * x - s * z, point[1], s * x + c * z)


def rectangle(collider):
    x, _, z = collider['center']
    w, _, d = collider['size']
    c, s = math.cos(collider['rotation_y']), math.sin(collider['rotation_y'])
    return [(x + c * u + s * v, z - s * u + c * v)
            for u, v in [(-w / 2, -d / 2), (w / 2, -d / 2),
                         (w / 2, d / 2), (-w / 2, d / 2)]]


def overlap(a, b):
    for poly in (a, b):
        for i in range(4):
            p, q = poly[i], poly[(i + 1) % 4]
            axis = (p[1] - q[1], q[0] - p[0])
            ap = [x * axis[0] + z * axis[1] for x, z in a]
            bp = [x * axis[0] + z * axis[1] for x, z in b]
            if min(max(ap), max(bp)) - max(min(ap), min(bp)) <= 1e-6:
                return False
    return True


def distance(point, collider):
    x, z = point[0] - collider['center'][0], point[1] - collider['center'][2]
    c, s = math.cos(collider['rotation_y']), math.sin(collider['rotation_y'])
    u, v = c * x - s * z, s * x + c * z
    return math.hypot(max(0, abs(u) - collider['size'][0] / 2),
                      max(0, abs(v) - collider['size'][2] / 2))


def zone_of(collider):
    name = collider['name'].lower()
    for prefix, zone in [('university', 'university'), ('maker', 'major'),
                         ('major', 'major'), ('career', 'career'),
                         ('learninggrove', 'high_school'), ('high_school', 'high_school'),
                         ('cloister', 'campus'), ('fountain', 'campus'), ('campus', 'campus')]:
        if name.startswith(prefix):
            return zone
    return None


def main():
    layout = json.loads((ROOT / 'game/assets/discussion_garden/layout.json').read_text(encoding='utf-8'))
    old = json.loads((ROOT / 'art/DiscussionGarden/history/pre-overhaul-20261023/layout.json').read_text(encoding='utf-8'))
    old_zones = {z['id']: z for z in old['zones']}
    solids = [c for c in layout['colliders'] if not c.get('camera_only')
              and c['center'][1] + c['size'][1] / 2 > .13
              and c['center'][1] - c['size'][1] / 2 < 1.8]
    intersections = []
    for i, a in enumerate(solids):
        az = zone_of(a)
        if not az:
            continue
        for b in solids[i + 1:]:
            bz = zone_of(b)
            if bz and az != bz and overlap(rectangle(a), rectangle(b)):
                intersections.append([a['name'], b['name']])
    routes, device_errors = {}, []
    max_local_delta = 0
    for zone in layout['zones']:
        baseline = old_zones[zone['id']]
        p, before = zone['controls']['point'], baseline['controls']['point']
        length, old_length = math.hypot(p[0], p[2]), math.hypot(before[0], before[2])
        clearance = min(distance((p[0] * t / 100, p[2] * t / 100), c)
                        for t in range(101) for c in solids)
        routes[zone['id']] = {'oldHubToEntryMetres': round(old_length, 3),
                             'hubToEntryMetres': round(length, 3),
                             'distanceReductionPercent': round((1 - length / old_length) * 100, 2),
                             'minimumCenterlineObstacleClearance': round(clearance, 3)}
        for index, (slot, old_slot) in enumerate(zip(zone['slots'], baseline['slots'])):
            max_local_delta = max(max_local_delta, *(abs(a - b) for a, b in zip(local(slot['position'], zone), local(old_slot['position'], baseline))))
            angle_delta = (slot['rotation_y'] - zone['rotation_y']) - (old_slot['rotation_y'] - baseline['rotation_y'])
            max_local_delta = max(max_local_delta, abs(angle_delta))
            a = slot['rotation_y']; point = (slot['position'][0] + math.sin(a) * 1.3, slot['position'][2] + math.cos(a) * 1.3)
            blocked = [c['name'] for c in solids if distance(point, c) < .38]
            if blocked:
                device_errors.append({'zone': zone['id'], 'slot': index, 'standingPointObstacles': blocked})
    ring_clearance = min(distance((math.sin(math.radians(deg)) * 15.6, math.cos(math.radians(deg)) * 15.6), c)
                         for deg in range(45, 316) for c in solids)
    navigation = layout.get('navigation', {})
    ring_points = navigation.get('ring_points', [])
    segment_lengths = [math.dist(a, b) for a, b in zip(ring_points, ring_points[1:])]
    report = {'revision': layout['revision'], 'zoneCount': len(layout['zones']),
              'independentDeviceCount': sum(len(z['slots']) for z in layout['zones']),
              'maxLocalDeviceTransformDelta': max_local_delta,
              'crossZoneSolidIntersections': intersections, 'deviceStandingPointErrors': device_errors,
              'routes': routes,
              'northRing': {'radius': 15.6, 'width': 3.6, 'degrees': [45, 315],
                            'navigationPointCount': len(ring_points),
                            'maximumSegmentLength': max(segment_lengths, default=0),
                            'minimumEdgeObstacleClearance': round(ring_clearance - 1.8, 3)},
              'engineValidationRequired': True}
    report['passed'] = (report['zoneCount'] == 5 and report['independentDeviceCount'] == 40
                        and max_local_delta < .00003 and not intersections and not device_errors
                        and min(v['minimumCenterlineObstacleClearance'] for v in routes.values()) > .38)
    if navigation:
        report['passed'] = report['passed'] and max(segment_lengths) <= 1.8 and len(navigation['spokes']) == 5
    path = ROOT / 'art/DiscussionGarden/compact-layout-qa.json'
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
