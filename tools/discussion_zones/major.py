"""Red-brick makers' lane. Executed inside the garden builder's zone frame/group."""

ZONE_CONTROL = (0, .06, 10.2)
ZONE_SIGN = (0, 1.7, 10.0)
ZONE_SLOTS = [
    {"position": [-3.15, .02, z], "rotation_y": math.pi / 2}
    for z in [-8.4, -3.1, 2.2, 7.5]
] + [
    {"position": [3.15, .02, z], "rotation_y": -math.pi / 2}
    for z in [-8.4, -3.1, 2.2, 7.5]
]


def major_brick_panel(name, p, width, height, depth=.24):
    """The baked 512px bond supplies mortar without thousands of tiny boxes."""
    with frame(p):
        box(name, (0, height / 2, 0), (width, height, depth), "brick", .009)


def major_workbench(name, p, width=2.25):
    with frame(p):
        box(name + "_Top", (0, .88, 0), (width, .105, .88), "oak", .025)
        box(name + "_Apron", (0, .73, 0), (width - .08, .13, .79), "steel", .007)
        box(name + "_LowerShelf", (0, .22, 0), (width - .12, .055, .73), "oak", .01)
        for x in [-width / 2 + .12, width / 2 - .12]:
            for z in [-.32, .32]:
                box(name + "_Leg", (x, .43, z), (.06, .86, .06), "steel", .005)
                cylinder(name + "_Leveller", (x, .025, z), .055, .04, "steel", segments=12)
        collision(name, (0, .47, 0), (width + .05, .94, .94))


def major_gear(name, p, radius=.3, teeth=14):
    profile = []
    for i in range(teeth * 4):
        angle = i * math.tau / (teeth * 4)
        r = radius * (1 if i % 4 in [1, 2] else .82)
        profile.append((math.cos(angle) * r, math.sin(angle) * r))
    points = [(x, y, z) for y in [-.065, .065] for x, z in profile]
    n = len(profile)
    ob = mesh(name, points, [tuple(range(n - 1, -1, -1)), tuple(range(n, n * 2))] +
              [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)], "brass")
    ob.matrix_world = FRAME @ Matrix.Translation(gv(p))
    bevel(ob, .003, 1)


def major_workshop(side, row, z):
    name = "Maker_%s_%s" % ("West" if side < 0 else "East", row)
    # Local front is +Z, directed toward the walking lane.
    with frame((side * 8.35, 0, z), yaw=-side * math.pi / 2):
        box(name + "_WorkshopFloor", (0, -.007, 0), (6.15, .05, 7.55), "concrete", 0)
        major_brick_panel(name + "_RearWall", (0, 0, -3.66), 6.15, 3.5)
        collision(name + "_RearWall", (0, 1.75, -3.66), (6.15, 3.5, .25))
        # Open bays use substantial brick piers with stone plinths and steel lintels.
        for x in [-2.98, 2.98]:
            for zz in [-3.45, 3.35]:
                major_brick_panel(name + "_Pier", (x, 0, zz), .42, 3.55, .44)
                box(name + "_PierFoot", (x, .13, zz), (.53, .26, .55), "stone", .015)
                box(name + "_PierCapital", (x, 3.52, zz), (.52, .16, .56), "concrete", .008)
                collision(name + "_Pier", (x, 1.8, zz), (.53, 3.6, .55))
        for zz in [-3.45, 3.35]:
            box(name + "_Lintel", (0, 3.60, zz), (6.30, .22, .18), "steel", .008)
        for x in [-2.98, 2.98]:
            box(name + "_SideBeam", (x, 3.58, -.05), (.18, .22, 7.05), "steel", .008)
        # Asymmetric tooth roof: broad low roof and tall glazed northlight face.
        roof_points = [(-3.18, 3.75, -3.90), (3.18, 3.75, -3.90), (3.18, 5.02, 1.85), (-3.18, 5.02, 1.85),
                       (-3.18, 3.80, 3.62), (3.18, 3.80, 3.62)]
        roof = mesh(name + "_SawtoothRoof", roof_points[:4], [(0, 1, 2, 3)], "roof")
        solid = roof.modifiers.new("Standing-seam roof thickness", "SOLIDIFY"); solid.thickness = .075
        for x in [-3.18, -2.38, -1.58, -.78, .02, .82, 1.62, 2.42, 3.18]:
            rod(name + "_RoofSeam", (x, 3.79, -3.88), (x, 5.06, 1.84), .017, "steel", 8)
            rod(name + "_RoofReturnSeam", (x, 5.06, 1.86), (x, 3.84, 3.62), .017, "steel", 8)
        for x in [-3.0, 3.0]:
            rod(name + "_TrussChord", (x, 3.60, -3.45), (x, 3.60, 3.35), .045, "steel", 8)
            rod(name + "_TrussRafter", (x, 3.66, -3.45), (x, 4.92, 1.8), .045, "steel", 8)
            for zz in [-2.8, -1.4, 0, 1.4]:
                yy = 3.75 + (zz + 3.9) / 5.75 * 1.27
                rod(name + "_TrussDiagonal", (x, 3.64, zz - .35), (x, yy - .08, zz + .8), .024, "steel", 8)
        # Clerestory end glass is framed as individual structural bays.
        for x in [-2.4, -1.2, 0, 1.2, 2.4]:
            with frame((x, 4.41, 2.735), tilt=math.radians(-55.42)):
                box(name + "_Northlight", (0, 0, 0), (1.10, 2.10, .025), "glass", 0)
                for edge_x in [-.57, .57]: box(name + "_NorthlightMullion", (edge_x, 0, .025), (.045, 2.15, .055), "steel", .004)
                for edge_y in [-1.055, 1.055]: box(name + "_NorthlightCrossbar", (0, edge_y, .025), (1.18, .055, .055), "steel", .004)
        # Warm oak soffit strips and suspended enamel task lamps.
        for x in [-2.6, -1.3, 0, 1.3, 2.6]:
            rod(name + "_SoffitRail", (x, 3.68, -3.45), (x, 4.55, .65), .035, "oak", 8)
        for x in [-1.6, 1.6]:
            rod(name + "_LampCable", (x, 3.70, 1.8), (x, 2.94, 1.8), .012, "steel", 8)
            cylinder(name + "_EnamelLamp", (x, 2.91, 1.8), .24, .19, "steel", top=.07, segments=20)
            cylinder(name + "_LampDiffuser", (x, 2.815, 1.8), .205, .018, "paper", segments=20)
        # Rear storage, joinery and books make every open interior inhabitable.
        for x in [-1.8, 1.8]:
            for height in [.55, 1.25, 1.95, 2.65]:
                box(name + "_StorageShelf", (x, height, -3.30), (1.8, .06, .51), "oak", .008)
                for book in range(5):
                    material_key = ["teal", "sand", "paper", "clay", "slate"][(book + row) % 5]
                    box(name + "_MaterialSample", (x - .66 + book * .26, height + .20, -3.30), (.13, .34 + .035 * (book % 3), .25), material_key, .005)
            for xx in [x - .87, x + .87]: box(name + "_ShelfUpright", (xx, 1.46, -3.34), (.055, 2.9, .52), "steel", .004)
        major_workbench(name + "_DisplayBench", (0, 0, 1.35), 2.45)
        if (row + (side > 0)) % 3 == 0:
            # Small articulated manufacturing arm with distinct shoulder/elbow/wrist joints.
            cylinder(name + "_RobotBase", (-.35, 1.00, 1.35), .25, .16, "steel", segments=20)
            rod(name + "_RobotUpper", (-.35, 1.12, 1.35), (-.2, 1.68, 1.32), .12, "clay", 16)
            rod(name + "_RobotForearm", (-.2, 1.68, 1.32), (.30, 1.78, 1.32), .09, "clay", 16)
            rod(name + "_RobotWrist", (.30, 1.78, 1.32), (.48, 1.47, 1.32), .064, "steel", 12)
            for point in [(-.35, 1.10, 1.35), (-.2, 1.68, 1.32), (.30, 1.78, 1.32)]:
                with frame(point, tilt=math.pi / 2): cylinder(name + "_RobotJoint", (0, 0, 0), .14, .22, "brass", segments=16)
            for xx in [.41, .55]: box(name + "_RobotGripper", (xx, 1.40, 1.32), (.035, .19, .10), "steel", .004)
            box(name + "_Workpiece", (.48, .99, 1.36), (.3, .1, .3), "paper", .012)
        elif (row + (side > 0)) % 3 == 1:
            # Visible mechanics: meshing gear exhibit and a compact machinist's vice.
            for x, y, r in [(-.44, 1.28, .32), (.05, 1.43, .24), (.42, 1.28, .22)]:
                with frame((x, y, 1.29), tilt=math.pi / 2): major_gear(name + "_Gear", (0, 0, 0), r)
                rod(name + "_GearAxle", (x, y, 1.0), (x, y, 1.50), .04, "steel", 12)
            box(name + "_MechanismBack", (0, 1.30, .98), (1.50, .7, .06), "steel", .01)
            box(name + "_Vice", (.85, 1.01, 1.38), (.30, .20, .24), "teal", .015)
            rod(name + "_ViceScrew", (.7, 1.03, 1.4), (1.10, 1.03, 1.4), .022, "brass", 12)
        else:
            # Sculpture studio: curved branching sculpture, clay maquettes and timber easel.
            cylinder(name + "_SculptureFoot", (-.30, .99, 1.35), .32, .10, "stone", segments=24)
            points = [(-.30, 1.03, 1.35), (-.59, 1.35, 1.35), (-.38, 1.69, 1.35), (.00, 1.84, 1.35), (.17, 1.55, 1.35), (-.10, 1.39, 1.35)]
            for a, b in zip(points, points[1:]): rod(name + "_SculptureArc", a, b, .075, "paper", 16)
            for x, h in [(.55, .28), (.86, .18)]:
                cylinder(name + "_ClayVessel", (x, .94 + h / 2, 1.35), .12, h, "clay", top=.07, segments=20)
            with frame((-2.05, 0, .55), yaw=.12):
                for x in [-.4, .4]: rod(name + "_EaselSide", (x, .02, .3), (x * .35, 2.1, 0), .038, "oak", 8)
                rod(name + "_EaselRearLeg", (0, .03, -.5), (0, 1.85, 0), .035, "oak", 8)
                box(name + "_Canvas", (0, 1.35, .10), (.76, 1.02, .06), "paper", .009)
                box(name + "_CanvasLower", (0, .94, .145), (.64, .20, .012), "sage", 0)
                box(name + "_CanvasUpper", (-.12, 1.45, .145), (.30, .42, .012), "clay", 0)
                collision(name + "_Easel", (0, 1.05, 0), (1, 2.10, 1))


district_floor("MakerLane_Ground", (0, -.055, 0), (28, .11, 24), "concrete",3)
collision("MakerLane_Ground", (0, -.15, 0), (28, .30, 24))
box("MakerLane_CentralPaving", (0, .004, 0), (5.9, .008, 24), "stone", 0)
for side in [-1,1]:
    box("MakerLane_WorkshopApron",(side*4.2,.003,0),(2.0,.008,24),"paving_dark",0)
for x in [-2.91, 2.91]: box("MakerLane_BrassPavingLine", (x, .010, 0), (.028, .006, 24), "brass", 0)
for z in range(-11, 12, 2): box("MakerLane_PavingJoint", (0, .011, z), (5.82, .003, .013), "slate", 0)
for side in [-1, 1]:
    for row, z in enumerate([-6.7, 0, 6.7]): major_workshop(side, row, z)
    # Planting keeps workshop doors readable; message lecterns sit between entrances.
    for z in [-10.5, -3.35, 3.35, 10.5]:
        planter("MakerLane_BrickPlanter", (side * 4.25, 0, z), (.85, .55, 1.6), "brick")
        broadleaf("MakerLane_PlanterFoliage", (side * 4.25, .58, z), .8)
        flowers("MakerLane_PlanterFlowers", (side * 4.20, .62, z + .32), .65)
    for z in [-10.65, 10.65]:
        asset("birch", (side * 11.45, 0, z), scale=.84, yaw=side * .7)
        asset("fern", (side * 10.1, 0, z), scale=.7, yaw=.8)
    bench("MakerLane_SideSeat", (side * 5.0, 0, -10.75), yaw=-side * math.pi / 2)
# Loft-height cross-lane braces terminate in workshop piers, keeping the ground entirely open.
for z in [-9.65, 3.35]:
    rod("MakerLane_CrossBeam", (-4.94, 4.18, z), (4.94, 4.18, z), .065, "steel", 8)
    rod("MakerLane_CrossBeamUpper", (-4.94, 4.85, z), (4.94, 4.85, z), .048, "steel", 8)
    for x in [-4.8, -3.2, -1.6, 0, 1.6, 3.2]:
        rod("MakerLane_CrossTruss", (x, 4.18, z), (x + 1.6, 4.85, z), .027, "steel", 8)
    # The old braces sat above the masonry with no structural connection.
    # Anchor the second pair to the actual pier at z=2.98, not the bay gap.
    base_z=-9.68 if z<0 else 2.98
    for side in [-1,1]:
        rod("MakerLane_TrussPierBracket",(side*5.0,3.52,base_z),(side*4.94,4.85,z),.065,"steel",8)

