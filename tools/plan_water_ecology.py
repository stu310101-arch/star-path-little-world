"""Author and validate the six freshwater habitats without changing the world layout.

Coordinates use the same tangent-plane metres as districts.json.  Road and
plant clearances are measured after projection onto the 48 m globe: tangent
coordinates alone exaggerate available space toward the island perimeter.
Run with --check to validate the saved plan without rewriting it.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "game/data/water_ecology.json"
RADIUS = 48.0
FOOTPRINTS = {"water_lily": .52, "cattail": .95, "bank_stones": 1.15, "fern": .85}
HEIGHTS = {"water_lily": .075, "cattail": -.12, "bank_stones": .035, "fern": .16}


def add(a, b):
    return tuple(x + y for x, y in zip(a, b))


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def mul(a, factor):
    return tuple(x * factor for x in a)


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def length(a):
    return math.sqrt(dot(a, a))


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def unit(a):
    return mul(a, 1 / length(a))


def nearest(point, a, b):
    direction = sub(b, a)
    factor = max(0., min(1., dot(sub(point, a), direction) / max(1e-12, dot(direction, direction))))
    return add(a, mul(direction, factor))


def surface(point):
    vector = (point[0], RADIUS, point[1])
    return mul(vector, RADIUS / length(vector))


def water_distance(point, district):
    water = district["water"][0]
    if water["kind"] == "lake":
        local = tuple((point[i] - water["center"][i]) / water["size"][i] for i in (0, 1))
        angle = math.atan2(local[1], local[0])
        contour = 1 + .10 * math.sin(angle * 3) + .055 * math.cos(angle * 5)
        return (length(local) - contour) * min(water["size"])
    return min(length(sub(point, nearest(point, a, b))) - water["width"] * .5
               for a, b in zip(water["points"], water["points"][1:]))


def island_distance(point, district, index):
    local = tuple(point[i] / district["extent"][i] for i in (0, 1))
    angle = math.atan2(local[1], local[0])
    edge = 1 + .045 * math.sin(angle * 3 + index) + .035 * math.cos(angle * 5 - index)
    return (edge - length(local)) * min(district["extent"])


def routes(district):
    result = [(path, 1.1) for path in district["paths"]]
    # Match WorldRoutes' shared bends, including the continuous wetland deck.
    if district["station"] == "wordking":
        result[0] = (district["paths"][0] + district["paths"][1][1:], 1.1)
        result.pop(1)
    elif district["station"] == "life":
        result[1] = (district["paths"][1] + list(reversed(district["paths"][2]))[1:], 1.1)
        result.pop(2)
    starts = [15., 15., 15., 15.]
    station = district["station"]
    overrides = {"counseling": {3: 22}, "admissions": {1: 30},
                 "recommendations": {0: 17, 3: 13}, "universities": {2: 26, 3: 29},
                 "life": {1: 19, 2: 17}}
    for axis, value in overrides.get(station, {}).items():
        starts[axis] = value
    end = RADIUS * math.tan(.375 * math.pi * .5)
    for axis, start in zip([(-1, 0), (1, 0), (0, -1), (0, 1)], starts):
        result.append(([mul(axis, start), mul(axis, end)], 1.1))
    result.append((district["loop"] + district["loop"][:1], 3.15))
    result.extend((road, 3.15) for road in district["roads"])
    return result


def route_segments(district):
    segments = []
    for path, half_width in routes(district):
        for a, b in zip(path, path[1:]):
            start, finish = mul(surface(a), 1 / RADIUS), mul(surface(b), 1 / RADIUS)
            cosine = max(-1., min(1., dot(start, finish)))
            angle = math.acos(cosine)
            tangent = mul(sub(finish, mul(start, cosine)), 1 / math.sin(angle))
            # A tangent-plane line projects to an exact great-circle arc.
            segments.append((start, tangent, angle, half_width))
    return segments


def road_clearance(point, segments, station):
    p = surface(point)
    unit = mul(p, 1 / RADIUS)
    distance = float("inf")
    for start, tangent, angle, width in segments:
        x, y = dot(unit, start), dot(unit, tangent)
        theta = max(0., min(angle, math.atan2(y, x)))
        nearest_dot = x * math.cos(theta) + y * math.sin(theta)
        gap = RADIUS * math.acos(max(-1., min(1., nearest_dot))) - width
        distance = min(distance, gap)
    if station == "admissions":
        a, b = surface((31.5, 6)), surface((41, 6))
        distance = min(distance, length(sub(p, nearest(p, a, b))) - 2.7,
                       length(sub(p, surface((37, 11.1)))) - 2.8)
    return distance


def tangent_footprint(point, radius):
    # Largest singular value of the inverse gnomonic projection; use this
    # conservative radius to keep a complete leaf cluster inside its habitat.
    return radius * (1 + dot(point, point) / RADIUS ** 2)


def route_boundaries(district):
    """Sample the actual mitered strip sides, matching Geo.path_sides."""
    boundaries = []
    for path, width in routes(district):
        closed = path[0] == path[-1]
        points = path[:-1] if closed else path
        normals = [unit(surface(p)) for p in points]
        sides = []
        for i, normal in enumerate(normals):
            incoming = unit(cross(normals[(i - 1) % len(normals)], normal))
            outgoing = unit(cross(normal, normals[(i + 1) % len(normals)]))
            if not closed and i == 0:
                incoming = outgoing
            if not closed and i == len(normals) - 1:
                outgoing = incoming
            bisector = unit(add(incoming, outgoing))
            sides.append(mul(bisector, 1 / max(.25, dot(bisector, outgoing))))
        left, right = [], []
        indices = list(range(len(points))) + ([0] if closed else [])
        for i, j in zip(indices, indices[1:]):
            steps = max(1, math.ceil(length(sub(points[j], points[i])) / .25))
            for k in range(steps):
                t = k / steps
                normal = unit(surface(add(points[i], mul(sub(points[j], points[i]), t))))
                side = add(sides[i], mul(sub(sides[j], sides[i]), t))
                left.append(mul(unit(add(mul(normal, RADIUS), mul(side, width))), RADIUS))
                right.append(mul(unit(add(mul(normal, RADIUS), mul(side, -width))), RADIUS))
        if not closed:
            left.append(mul(unit(add(mul(normals[-1], RADIUS), mul(sides[-1], width))), RADIUS))
            right.append(mul(unit(add(mul(normals[-1], RADIUS), mul(sides[-1], -width))), RADIUS))
        polygon = left + right[::-1]
        tangent_polygon = [(v[0] * RADIUS / v[1], v[2] * RADIUS / v[1]) for v in polygon]
        boundaries.append((polygon, tangent_polygon))
    return boundaries


def point_in_polygon(point, polygon):
    x, y = point
    inside = False
    for (a, b), (c, d) in zip(polygon, polygon[1:] + polygon[:1]):
        if (b > y) != (d > y) and x < (c - a) * (y - b) / (d - b) + a:
            inside = not inside
    return inside


def miter_clearance(point, boundaries):
    p = surface(point)
    result = float("inf")
    for polygon, tangent_polygon in boundaries:
        gap = min(length(sub(p, nearest(p, a, b))) for a, b in zip(polygon, polygon[1:] + polygon[:1]))
        if point_in_polygon(point, tangent_polygon):
            gap = -gap
        result = min(result, gap)
    return result


def valid_plant(kind, point, scale, district, index, segments, occupied):
    footprint = FOOTPRINTS[kind] * scale
    expanded = tangent_footprint(point, footprint)
    if road_clearance(point, segments, district["station"]) < footprint + .18:
        return False
    if island_distance(point, district, index) < expanded + .25:
        return False
    wet = water_distance(point, district)
    if kind == "water_lily" and wet > -expanded - .14:
        return False
    reed_depth = -4.5 if district["station"] == "wordking" else -.65
    if kind == "cattail" and not reed_depth <= wet <= .65:
        return False
    if kind == "bank_stones" and not -.85 <= wet <= .65:
        return False
    if kind == "fern" and not expanded * .65 <= wet <= 2.5:
        return False
    for other in occupied:
        separation = length(sub(surface(point), surface(other["point"])))
        minimum = .64 * (footprint + FOOTPRINTS[other["kind"]] * other["scale"])
        if separation < minimum:
            return False
    return True


def authored_plant(kind, desired, scale, yaw, district, index, segments, occupied):
    # Tiny, deterministic adjustments respect the contour and full road width.
    # The artist's anchor remains the preference; this is not random scatter.
    candidates = [(0., 0.)]
    for ring in range(1, 10):
        for i in range(32):
            angle = i * math.tau / 32
            candidates.append((math.cos(angle) * ring * .22, math.sin(angle) * ring * .22))
    for offset in candidates:
        point = tuple(round(value, 3) for value in add(desired, offset))
        if valid_plant(kind, point, scale, district, index, segments, occupied):
            row = {"kind": kind, "point": list(point), "scale": scale,
                   "yaw": round(math.radians(yaw), 5), "height": HEIGHTS[kind]}
            occupied.append(row)
            return
    raise ValueError(f"No safe authored placement: {district['station']} {kind} {desired}")


def fish(center, major, minor, size=.62, phase=0., speed=.25):
    return {"center": list(center), "axes": [list(major), list(minor)],
            "size": size, "depth": .19, "speed": speed, "phase": phase}


PLANS = [
    {"station": "counseling", "description": "市政湖的睡蓮與觀魚淺灘；開闊中央水面保留橋景，兩側香蒲和卵石勾出水岸。",
     "review": {"point": [-20.8, 8.5], "target": [-27, 6], "pitch": .45},
     "groups": [
         ("water_lily", [(-25, 9), (-27.5, 10.1), (-28.2, 7.8), (-25.1, 4.9), (-27.7, 2.2), (-28.5, 4.6), (-25.4, 1.8)], .94),
         ("cattail", [(-30.7, 7), (-30.7, 3), (-29.8, 10.5), (-24.7, 12.1)], .78),
         ("bank_stones", [(-23, 6), (-25.5, 12.5), (-29.7, 10.9)], .64),
         ("fern", [(-24.5, -2), (-29.3, -1.7)], .73)],
     "fish_paths": [fish((-26.3, 6.5), (1.1, .1), (0, 2), .66), fish((-27.3, 4), (.9, .2), (-.2, 1.25), .57, 2.1)]},
    {"station": "admissions", "description": "商務碼頭旁的河口蘆葦帶；河灣卵石、岸蕨與沿水道巡游的魚群，保留碼頭出入和河面視線。",
     "review": {"point": [23.1, 9.2], "target": [25.7, 9.5], "pitch": .45},
     "groups": [
         ("cattail", [(27.4, 8.4), (26.8, 12.7), (24.8, 16.2), (22.6, 19.8), (28.1, -4.6), (25.1, -12.4)], .72),
         ("bank_stones", [(24.6, 7.5), (23.1, 15.9), (25, -4)], .54),
         ("fern", [(28.3, 11.3), (23.9, 19.5), (29.1, -7.3)], .7)],
     "fish_paths": [fish((25.5, 8), (-.19, 1.9), (.29, .03), .57), fish((23.1, 16.5), (-1.0, 1.85), (.28, .15), .56, 2.1), fish((26.55, -3.1), (-.15, 1.5), (.3, .03), .53, 4)]},
    {"station": "recommendations", "description": "文化院落東側的靜水花池；淡色睡蓮與蕨類石岸形成閱讀散步時的觀景焦點。",
     "review": {"point": [19.4, 10.4], "target": [25, 12], "pitch": .45},
     "groups": [
         ("water_lily", [(23.2, 9), (24.8, 8.4), (26.8, 10), (27, 13), (24.7, 14.8), (22.8, 13.3), (24.3, 11.5)], .88),
         ("bank_stones", [(21.1, 9), (21.2, 14.5), (26.4, 17.6)], .63),
         ("fern", [(20.1, 12.2), (23.1, 18.1), (29.8, 11.8)], .79),
         ("cattail", [(28.5, 15), (29.2, 10.3), (26.8, 7.0)], .68)],
     "fish_paths": [fish((24.8, 11.6), (1.55, .1), (0, 1.45), .62), fish((24.2, 13.3), (.9, .2), (-.2, 1.05), .54, 2.4)]},
    {"station": "universities", "description": "大學校園的清淺溪谷；低矮蕨叢和成組溪石沿水流排列，小魚在跨溪步道兩側游動。",
     "review": {"point": [6.2, 26.8], "target": [6.1, 23.55], "pitch": .45},
     "groups": [
         ("bank_stones", [(4.2, 25), (8.6, 22.6), (13.3, 25), (-7.1, 23), (-15.5, 24.8), (17.7, 21.4)], .53),
         ("fern", [(4.3, 26.4), (10.4, 20.9), (-7.3, 21.7), (-17, 25.8)], .7),
         ("cattail", [(10.4, 25.5), (16.1, 23.9), (-10.1, 26.4), (-20.5, 20.9)], .65)],
     "fish_paths": [fish((6.1, 23.555), (1.8, .164), (-.027, .3), .57), fish((-5.5, 24.1), (1.65, -.33), (.058, .29), .53, 2.1), fish((15.5, 23.182), (1.65, -.3), (.055, .3), .57, 4.2)]},
    {"station": "life", "description": "住宅區的小型睡蓮池；近岸花葉與低矮溪石親切可近，香蒲集中在對岸，保留環湖散步空間。",
     "review": {"point": [-16.1, 20.2], "target": [-22, 18], "pitch": .45},
     "groups": [
         ("water_lily", [(-20.1, 18.2), (-22.2, 19.6), (-24.1, 18.7), (-23.8, 16.5), (-21.7, 16.1), (-20.5, 20.3)], .78),
         ("bank_stones", [(-18.7, 17), (-22.1, 13.9)], .58),
         ("cattail", [(-21.3, 13.8), (-19.1, 15.6)], .67),
         ("fern", [(-18.5, 14.1)], .66)],
     "fish_paths": [fish((-21.2, 18.3), (1.05, .15), (-.15, .95), .59), fish((-23.1, 17.7), (.65, .1), (-.1, .8), .51, 2.6)]},
    {"station": "wordking", "description": "濕地工坊的香蒲保育池；密疏交錯的挺水植物、浮葉和淺水魚群，木棧道穿過濕地仍保持完整通行寬度。",
     "review": {"point": [14.3, 20.2], "target": [20.2, 19.8], "pitch": .45},
     "groups": [
         ("cattail", [(17, 18.2), (16.4, 20), (17.4, 22.7), (25.7, 12.6), (28.5, 13.5), (28.3, 16), (28.3, 19), (27.2, 21.9)], .76),
         ("water_lily", [(19, 18), (19.9, 20), (19.1, 21.7), (21.3, 22.3), (26.4, 15.8), (28.3, 17.5), (28.7, 20.4), (27, 22.5)], .86),
         ("bank_stones", [(17.1, 21.2), (29, 14.5)], .65),
         ("fern", [(14.8, 18.3), (27.7, 12.3)], .7)],
     "fish_paths": [fish((19.7, 19.8), (.8, .1), (-.1, 1.45), .59), fish((27.4, 18.7), (1.2, .25), (-.2, 1.6), .62, 2.2), fish((24, 23.2), (1.1, .2), (-.2, .6), .52, 4.1)]},
]


def validate(plan, districts):
    assert [p["station"] for p in plan["districts"]] == [d["station"] for d in districts]
    report = []
    for index, (habitat, district) in enumerate(zip(plan["districts"], districts)):
        segments = route_segments(district)
        boundaries = route_boundaries(district)
        minimum_route_gap = float("inf")
        minimum_miter_gap = float("inf")
        for plant in habitat["plants"]:
            p, kind, scale = plant["point"], plant["kind"], plant["scale"]
            assert valid_plant(kind, p, scale, district, index, segments, []), (district["station"], plant)
            gap = road_clearance(p, segments, district["station"]) - FOOTPRINTS[kind] * scale
            minimum_route_gap = min(minimum_route_gap, gap)
            miter_gap = miter_clearance(p, boundaries) - FOOTPRINTS[kind] * scale
            assert miter_gap > .08, (district["station"], "plant intersects mitered route", plant, miter_gap)
            minimum_miter_gap = min(minimum_miter_gap, miter_gap)
        maximum_fish_water_distance = -float("inf")
        for path in habitat["fish_paths"]:
            assert .5 <= path["size"] <= .8 and .15 <= path["depth"] <= .25
            for sample in range(720):
                t = math.tau * sample / 720
                p = add(path["center"], add(mul(path["axes"][0], math.cos(t)), mul(path["axes"][1], math.sin(t))))
                wet = water_distance(p, district)
                assert wet < -.5, (district["station"], "fish path leaves water", path, p, wet)
                assert island_distance(p, district, index) > .5, (district["station"], "fish outside island", p)
                maximum_fish_water_distance = max(maximum_fish_water_distance, wet)
        review = habitat["review"]["point"]
        assert water_distance(review, district) > .45, (district["station"], "review in water", review)
        assert island_distance(review, district, index) > 1., (district["station"], "review outside island", review)
        for plant in habitat["plants"]:
            assert length(sub(surface(review), surface(plant["point"]))) > FOOTPRINTS[plant["kind"]] * plant["scale"] + .4, (district["station"], "review blocked by plant")
        report.append({"station": district["station"], "plant_clusters": len(habitat["plants"]),
                       "fish_loops": len(habitat["fish_paths"]), "minimum_route_gap_m": round(minimum_route_gap, 3),
                       "minimum_miter_gap_m": round(minimum_miter_gap, 3),
                       "closest_fish_to_bank_m": round(-maximum_fish_water_distance, 3),
                       "review_dry_margin": round(water_distance(review, district), 3)})
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Validate the existing JSON without rewriting it")
    args = parser.parse_args()
    districts = json.loads((ROOT / "game/data/districts.json").read_text(encoding="utf-8"))
    if args.check:
        plan = json.loads(OUTPUT.read_text(encoding="utf-8"))
    else:
        habitats = []
        for index, (authored, district) in enumerate(zip(PLANS, districts)):
            assert authored["station"] == district["station"]
            segments = route_segments(district)
            plants = []
            for kind, anchors, scale in authored["groups"]:
                for sequence, point in enumerate(anchors):
                    authored_plant(kind, point, scale, (sequence * 137 + index * 37) % 360,
                                   district, index, segments, plants)
            habitats.append({"station": authored["station"], "description": authored["description"],
                             "review": authored["review"], "plants": plants, "fish_paths": authored["fish_paths"]})
        plan = {"schema": 1, "radius": RADIUS, "water_height": .055,
                "intent": "六區各有能在人物視角看見的淡水生態，保留開闊水面、完整道路及棧道；新增植物均為裝飾，不增加行走障礙。",
                "footprints": FOOTPRINTS, "districts": habitats}
    report = validate(plan, districts)
    if not args.check:
        OUTPUT.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"ok": True, "districts": report}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
