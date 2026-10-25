"""Two oak reading cabins in a generous fern garden; all routes stay at ground level."""

ZONE_CONTROL = (0, .06, 10.2)
ZONE_SIGN = (0, 1.7, 10.0)
ZONE_SLOTS = [
    {"position": [-2.75, .02, 8.0], "rotation_y": math.pi / 2},
    {"position": [3.15, .02, 6.0], "rotation_y": -math.pi / 2},
    {"position": [-3.1, .02, 2.8], "rotation_y": math.pi / 2},
    {"position": [3.0, .02, .6], "rotation_y": -math.pi / 2},
    {"position": [-3.1, .02, -3.0], "rotation_y": math.pi / 2},
    {"position": [3.2, .02, -4.8], "rotation_y": -math.pi / 2},
    {"position": [-2.9, .02, -7.5], "rotation_y": math.pi / 2},
    {"position": [3.25, .02, -9.0], "rotation_y": -math.pi / 2},
]


def school_bookcase(name, p, width=2.35, height=2.25):
    with frame(p):
        box(name + "_Back", (0, height / 2, 0), (width, height, .055), "walnut", .006)
        for x in [-width / 2, width / 2]: box(name + "_Stile", (x, height / 2, .19), (.065, height, .44), "oak", .009)
        for index in range(5):
            y = .13 + index * .50
            box(name + "_Shelf", (0, y, .20), (width, .055, .45), "oak", .009)
            if index == 4: continue
            for book in range(11):
                bx = -width / 2 + .16 + book * (width - .32) / 10
                height_book = .25 + .035 * ((book * 3 + index) % 5)
                mat = ["teal", "slate", "sand", "clay", "sage", "paper"][(book + index) % 6]
                with frame((bx, y + .027 + height_book / 2, .21), tilt=0):
                    box(name + "_BookCover", (0, 0, 0), (.115, height_book, .26), mat, 0)
                    box(name + "_SpineBand", (0, height_book * .31, .131), (.085, .012, .002), "linen", 0)
        box(name + "_Crown", (0, height + .045, .17), (width + .14, .11, .49), "oak", .012)
        collision(name, (0, height / 2, .18), (width + .12, height + .12, .49))


def school_armchair(name, p, yaw=0):
    with frame(p, yaw=yaw):
        for x in [-.34, .34]:
            for z in [-.31, .31]: box(name + "_Leg", (x, .23, z), (.065, .46, .065), "oak", .01)
            box(name + "_Arm", (x, .68, 0), (.10, .08, .75), "oak", .025)
            box(name + "_SideRail", (x, .42, 0), (.055, .13, .74), "oak", .01)
            rod(name + "_RearPost", (x, .34, -.31), (x, 1.04, -.39), .038, "oak", 10)
        round_box(name + "_SeatCushion", (0, .49, 0), (.70, .14, .67), .08, "teal")
        with frame((0, .82, -.32), tilt=-.12):
            box(name + "_BackCushion", (0, 0, 0), (.68, .47, .16), "teal", .065)
            for x in [-.18, .18]:
                with frame((x, 0, .091), tilt=math.pi / 2): cylinder(name + "_UpholsteryButton", (0, 0, 0), .014, .006, "brass", segments=12)
        collision(name, (0, .54, 0), (.83, 1.08, .88))


def school_cabin(name, p, yaw):
    with frame(p, yaw=yaw):
        # Porch deck is flush with the route, avoiding steps at the entry.
        box(name + "_Foundation", (0, -.12, 0), (7.4, .24, 6.75), "stone", .015)
        for i in range(30): box(name + "_Floorboard", (-3.5 + i * .24, .012, 0), (.229, .024, 6.50), "oak", .002)
        # Rear and side wall boards, with deeper frame members and window recesses.
        box(name + "_RearWall", (0, 1.50, -3.20), (7.25, 3.0, .16), "walnut", .01)
        collision(name + "_RearWall", (0, 1.50, -3.20), (7.25, 3.0, .22))
        for y in [.20 + i * .19 for i in range(15)]:
            box(name + "_RearCladding", (0, y, -3.09), (7.15, .16, .055), "oak", .006)
        for x in [-3.58, 3.58]:
            # Solid lower sill, open middle glazing, and upper wall band.
            box(name + "_SideLower", (x, .48, -.65), (.18, .96, 5.08), "oak", .01)
            box(name + "_SideUpper", (x, 2.69, -.65), (.18, .62, 5.08), "oak", .01)
            box(name + "_SideGlass", (x, 1.69, -.65), (.028, 1.40, 4.95), "glass", 0)
            for zz in [-3.15, -1.48, .19, 1.86]:
                box(name + "_WindowMullion", (x, 1.70, zz), (.22, 1.5, .08), "oak", .008)
            box(name + "_WindowSill", (x, 1.00, -.65), (.32, .10, 5.18), "oak", .012)
            collision(name + "_SideWall", (x, 1.50, -.65), (.24, 3, 5.15))
        # Full-height front posts and exposed mortise-and-tenon braces.
        for x in [-3.48, 3.48]:
            for z in [-3.10, 2.90]:
                box(name + "_OakPost", (x, 1.60, z), (.22, 3.20, .22), "oak", .018)
                box(name + "_PostShoe", (x, .12, z), (.29, .24, .29), "steel", .008)
                collision(name + "_Post", (x, 1.63, z), (.30, 3.26, .30))
                rod(name + "_KneeBrace", (x, 2.46, z), (x - math.copysign(.70, x), 3.10, z), .075, "oak", 8)
        # Steep roof with visible rafters, ridge cap, standing seams and gable fascia.
        roof_points = [(-3.98, 3.13, -3.70), (3.98, 3.13, -3.70), (0, 5.05, -3.70),
                       (-3.98, 3.13, 3.55), (3.98, 3.13, 3.55), (0, 5.05, 3.55)]
        roof = mesh(name + "_PitchedRoof", roof_points, [(0, 3, 5, 2), (2, 5, 4, 1)], "roof")
        solid = roof.modifiers.new("Editable roof board thickness", "SOLIDIFY"); solid.thickness = .09
        for z in [-3.68 + i * .48 for i in range(16)]:
            for side in [-1, 1]:
                rod(name + "_RoofSeam", (side * 3.98, 3.19, z), (0, 5.11, z), .018, "steel", 8)
        for z in [-3.5, -1.4, .6, 3.40]:
            rod(name + "_RafterLeft", (-3.92, 3.08, z), (0, 4.99, z), .08, "oak", 8)
            rod(name + "_RafterRight", (0, 4.99, z), (3.92, 3.08, z), .08, "oak", 8)
            box(name + "_TieBeam", (0, 3.11, z), (7.72, .20, .16), "oak", .012)
            rod(name + "_KingPost", (0, 3.15, z), (0, 4.95, z), .07, "oak", 8)
            for side in [-1, 1]: rod(name + "_TrussStrut", (side * 1.7, 3.2, z), (0, 4.2, z), .052, "oak", 8)
        rod(name + "_RidgeCap", (0, 5.12, -3.77), (0, 5.12, 3.65), .065, "steel", 12)
        for x in [-3.95, 3.95]: rod(name + "_RainGutter", (x, 3.14, -3.72), (x, 3.14, 3.60), .06, "steel", 12)
        school_bookcase(name + "_BookcaseLeft", (-1.85, 0, -2.98), 2.65)
        school_bookcase(name + "_BookcaseRight", (1.35, 0, -2.98), 2.65)
        # Reading groups sit off-centre so a visitor can walk between porch and shelves.
        school_armchair(name + "_ReadingChairA", (-2.40, 0, .96), yaw=.18)
        school_armchair(name + "_ReadingChairB", (-.92, 0, .64), yaw=-.18)
        round_box(name + "_ReadingTable", (-1.68, .56, 1.64), (1.10, .07, .66), .14, "oak")
        for x in [-2.08, -1.28]:
            for z in [1.43, 1.85]: box(name + "_TableLeg", (x, .26, z), (.045, .52, .045), "oak", .006)
        collision(name + "_ReadingTable", (-1.68, .30, 1.64), (1.15, .60, .71))
        box(name + "_OpenBookLeft", (-1.86, .617, 1.64), (.27, .015, .30), "paper", .002)
        box(name + "_OpenBookRight", (-1.57, .617, 1.64), (.27, .015, .30), "paper", .002)
        box(name + "_BookBinding", (-1.715, .621, 1.64), (.012, .01, .30), "brass", 0)
        cylinder(name + "_TeaCup", (-1.35, .66, 1.62), .055, .085, "paper", top=.058, segments=20)
        # Oak writing counter on the opposite wall, supplied with books and a desk lamp.
        box(name + "_WritingDesk", (2.33, .78, -.1), (1.70, .085, .82), "oak", .018)
        for x in [1.66, 3.00]:
            for z in [-.42, .22]: box(name + "_DeskLeg", (x, .37, z), (.055, .74, .055), "oak", .005)
        collision(name + "_WritingDesk", (2.33, .42, -.1), (1.80, .84, .90))
        cylinder(name + "_DeskLampBase", (2.82, .85, -.15), .12, .035, "brass", segments=20)
        rod(name + "_DeskLampStem", (2.82, .85, -.15), (2.82, 1.15, -.22), .016, "brass", 12)
        cylinder(name + "_DeskLampShade", (2.82, 1.17, -.22), .16, .14, "teal", top=.055, segments=20)
        for i in range(3): box(name + "_DeskBook", (1.95, .84 + i * .045, -.1), (.42, .035, .31), ["clay", "paper", "sage"][i], .004)
        rod(name + "_PendantWire", (.5, 4.1, 1.6), (.5, 2.83, 1.6), .012, "steel", 8)
        cylinder(name + "_PendantShade", (.5, 2.85, 1.6), .26, .22, "brass", top=.06, segments=24)
        cylinder(name + "_PendantDiffuser", (.5, 2.735, 1.6), .22, .02, "paper", segments=20)
        planter(name + "_PorchPot", (2.55, 0, 2.35), (.72, .53, .72), "clay")
        broadleaf(name + "_PorchPlant", (2.55, .56, 2.35), .75)


district_floor("LearningGrove_Ground", (0, -.055, -2), (28, .11, 28), "forest_floor",3)
collision("LearningGrove_Ground", (0, -.15, 0), (28, .30, 24))
# A gently winding, 3.8 m wide path is visually curved while maintaining a level collision floor.
path_points = [(0, 12), (-.35, 9), (.40, 6), (.35, 3), (-.45, 0), (-.40, -3), (.40, -6), (.35, -9), (0, -12)]
for index, ((x1, z1), (x2, z2)) in enumerate(zip(path_points, path_points[1:])):
    mesh("LearningGrove_Path_%02d" % index, [(x1 - 1.95, .009, z1), (x1 + 1.95, .009, z1),
          (x2 + 1.95, .009, z2), (x2 - 1.95, .009, z2)], [(0, 1, 2, 3)], "sand")
    for side in [-1, 1]:
        rod("LearningGrove_PathEdging", (x1 + side * 1.97, .025, z1), (x2 + side * 1.97, .025, z2), .045, "stone", 8)
school_cabin("LearningGrove_WestCabin", (-8.3, 0, 1.8), math.pi / 2 - .12)
school_cabin("LearningGrove_EastCabin", (8.3, 0, -5.0), -math.pi / 2 + .12)
# Flat porch approach aprons broaden the clearing without introducing steps.
for p, size in [((-4.55, .009, 1.8), (5.3, .012, 5.4)), ((4.55, .010, -5.0), (5.3, .012, 5.4))]:
    round_box("LearningGrove_PorchApproach", p, size, .75, "sand")
bench("LearningGrove_WelcomeBench", (-6.2, 0, 8.2), yaw=.28)
bench("LearningGrove_GardenBench", (6.7, 0, 5.9), yaw=-.32)
bench("LearningGrove_BackBench", (-6.6, 0, -8.3), yaw=.12)
for kind, p, scale, yaw in [
    ("alder", (-10.9, 0, 9.1), 1.0, .2), ("birch", (9.7, 0, 8.8), 1.05, 1.2),
    ("birch", (-10.5, 0, -8.9), .95, .8), ("alder", (11.0, 0, -10.0), .92, -.8),
    ("birch", (-6.0, 0, -10.1), .82, -.2), ("birch", (12.2, 0, 1.2), .9, .6),
]:
    asset(kind, p, scale=scale, yaw=yaw)
# Overlapping mature crowns close the forest horizon behind the reading
# clearing. All trunks stand behind the cabins or beyond the message route.
for index,(x,z) in enumerate([(-11,-12.8),(-5.5,-13.0),(0,-14.5),(5.5,-13.0),(11,-12.8),(-13,1),(13,6)]):
    asset("birch" if index%2 else "alder",(x,0,z),1.02+(index%3)*.08,index*.47)
    collision("LearningGrove_BackdropTrunk",(x,1,z),(.55,2,.55))
    for offset in [-.9,.9]:
        asset("fern",(x+offset,0,z+.5),.82,index+offset)
# Layered mass planting: full ferns at the tree line, broad leaves and flower drifts closer to the path.
for index, (x, z) in enumerate([(-4.8, 10), (-7.9, 10), (4.6, 9.2), (7.1, 8.4), (10.9, 5.3),
                              (-12.8, 6.5), (-12.8, -3.0), (-7.0, -6.2), (-4.8, -9.9),
                              (5.5, -10.6), (9.0, -11.1), (12.8, -7.5)]):
    asset("fern", (x, 0, z), scale=.70 + .12 * (index % 3), yaw=index * 1.73)
    broadleaf("LearningGrove_Understory", (x + .48, .02, z + .32), .55 + .09 * (index % 2))
    flowers("LearningGrove_FlowerDrift", (x - .48, .02, z + .58), .72)
for side in [-1, 1]:
    for index, z in enumerate([-10.5, -6.0, -.9, 4.6, 9.7]):
        x = side * (4.0 + .35 * (index % 2))
        flowers("LearningGrove_PathFlowers", (x, .02, z), .65)
        broadleaf("LearningGrove_LowGarden", (x + side * .55, .02, z + .48), .55)

