"""Readable FDM and resin teaching equipment for the NTUST exhibit.

Invoked by build_exhibit_kit.py; all coordinates use its Godot XYZ helpers.
This is an artistic teaching-equipment model, not a particular machine model.
The base is 1 x .5 m and the gantry remains below 1.05 m.
"""
import math


def build_printer(api):
    box, mesh, rod = api["box"], api["mesh"], api["rod"]
    cylinder = api["cylinder"]

    def tube(name, center, outer, inner, depth, key, n=36):
        """Open annulus with its axle along Z; no opaque disc over the hole."""
        x, y, z = center
        points = [(x + r * math.cos(i * math.tau / n),
                   y + r * math.sin(i * math.tau / n), z + dz)
                  for dz, r in [(-depth / 2, outer), (depth / 2, outer),
                                (-depth / 2, inner), (depth / 2, inner)]
                  for i in range(n)]
        faces = []
        for i in range(n):
            j = (i + 1) % n
            faces += [(i, j, n + j, n + i),
                      (2*n+i, 3*n+i, 3*n+j, 2*n+j),
                      (i, 2*n+i, 2*n+j, j),
                      (n+i, n+j, 3*n+j, 3*n+i)]
        return mesh(name, points, faces, key)

    def cable(name, points, radius=.004, key="crevice"):
        # A continuous six-sided sweep avoids hundreds of overlapping capped
        # cylinders for threads and layer lines; the mesh remains editable.
        vertices, faces, sides = [], [], 6
        for i, point in enumerate(points):
            a, b = points[max(0, i-1)], points[min(len(points)-1, i+1)]
            direction = [b[j]-a[j] for j in range(3)]
            length = math.sqrt(sum(v*v for v in direction))
            direction = [v / max(length, 1e-12) for v in direction]
            axis = [1, 0, 0] if abs(direction[1]) > .9 else [0, 1, 0]
            normal = [direction[1]*axis[2]-direction[2]*axis[1],
                      direction[2]*axis[0]-direction[0]*axis[2],
                      direction[0]*axis[1]-direction[1]*axis[0]]
            magnitude = math.sqrt(sum(v*v for v in normal))
            normal = [v / max(magnitude, 1e-12) for v in normal]
            side = [direction[1]*normal[2]-direction[2]*normal[1],
                    direction[2]*normal[0]-direction[0]*normal[2],
                    direction[0]*normal[1]-direction[1]*normal[0]]
            for j in range(sides):
                angle = j * math.tau/sides
                vertices.append(tuple(point[k] + radius*(normal[k]*math.cos(angle)+side[k]*math.sin(angle)) for k in range(3)))
        for i in range(len(points)-1):
            for j in range(sides):
                faces.append((i*sides+j, i*sides+(j+1)%sides,
                              (i+1)*sides+(j+1)%sides, (i+1)*sides+j))
        faces += [tuple(range(sides-1, -1, -1)), tuple((len(points)-1)*sides+j for j in range(sides))]
        mesh(f"SM_Printer_{name}", vertices, faces, key)

    box("SM_Printer_DisplayPlinth", (0, .012, 0), (1, .024, .5), "stone", .009)
    # The open gantry and visible bed establish the FDM silhouette first.
    box("SM_Printer_FDM_Chassis", (-.17, .062, .005), (.62, .065, .405), "stone_dark", .012)
    for x in [-.414, .074]:
        box("SM_Printer_FDM_GantryColumn", (x, .495, -.06), (.042, .865, .055), "stone_dark", .005)
        box("SM_Printer_FDM_ExtrusionSlot", (x, .51, -.028), (.009, .81, .005), "crevice", .001)
        rod("SM_Printer_FDM_ZGuide", (x + .022, .115, -.01), (x + .022, .88, -.01), .008, "brass", 14)
        box("SM_Printer_FDM_Motor", (x, .115, -.045), (.075, .063, .072), "crevice", .006)
        # The leadscrews have a readable helical crest, not decorative rivets.
        screw_x = x - .025 if x < 0 else x + .025
        rod("SM_Printer_FDM_LeadScrew", (screw_x, .13, -.052), (screw_x, .88, -.052), .005, "brass", 10)
        helix = [(screw_x + .0064 * math.cos(j * math.tau / 8),
                  .14 + .73 * j / 96, -.052 + .0064 * math.sin(j * math.tau / 8))
                 for j in range(97)]
        cable("LeadScrewThread", helix, .0015, "stone")
    box("SM_Printer_FDM_TopCrossbar", (-.17, .925, -.06), (.548, .043, .063), "stone_dark", .005)
    box("SM_Printer_FDM_TopNameplate", (-.17, .925, -.023), (.12, .018, .009), "brass", .002)
    for x in [-.31, -.035]:
        rod("SM_Printer_FDM_BedRail", (x, .119, -.17), (x, .119, .16), .008, "brass", 14)
    box("SM_Printer_FDM_BedCarriage", (-.17, .148, .025), (.25, .037, .20), "crevice", .005)
    box("SM_Printer_FDM_PrintBed", (-.17, .178, .025), (.365, .021, .285), "stone_dark", .004)
    box("SM_Printer_FDM_BuildSurface", (-.17, .192, .025), (.349, .005, .269), "paper", .001)
    for x in [-.31, -.03]:
        cylinder("SM_Printer_FDM_LevelWheel", (x, .149, .14), .023, .014, "brass", 16)
    # Carriage rides on the X beam; the brass nozzle points at the printed part.
    box("SM_Printer_FDM_XBeam", (-.17, .527, -.01), (.48, .049, .037), "stone_dark", .004)
    rod("SM_Printer_FDM_XGuide", (-.389, .546, .017), (.05, .546, .017), .006, "brass", 14)
    box("SM_Printer_FDM_Belt", (-.17, .507, .017), (.44, .008, .01), "crevice", .001)
    box("SM_Printer_FDM_Carriage", (-.15, .524, .03), (.089, .105, .038), "leather_blue", .006)
    box("SM_Printer_FDM_HotEnd", (-.15, .456, .044), (.047, .036, .043), "stone", .003)
    cylinder("SM_Printer_FDM_Nozzle", (-.15, .428, .044), .003, .023, "brass", 16, .015)
    tube("SM_Printer_FDM_FanRing", (-.15, .53, .057), .032, .023, .009, "crevice", 24)
    rod("SM_Printer_FDM_FanAxle", (-.15, .53, .058), (-.15, .53, .066), .007, "brass", 12)
    for i in range(5):
        angle = i * math.tau / 5
        rod("SM_Printer_FDM_FanBlade", (-.15, .53, .062),
            (-.15 + .023 * math.cos(angle), .53 + .023 * math.sin(angle), .062), .004, "stone_dark", 6)
    # Hollow, growing vessel: wall thickness and layered rim communicate printing.
    n = 36
    rings = [(y, radius) for y, radius in [(.196, .051), (.245, .053), (.30, .066), (.38, .055),
                                          (.38, .045), (.30, .056), (.245, .043), (.206, .041)]]
    points = [(-.15 + r * math.cos(i * math.tau/n), y, .044 + r * math.sin(i * math.tau/n))
              for y, r in rings for i in range(n)]
    faces = [(j*n+i, j*n+(i+1)%n, (j+1)*n+(i+1)%n, (j+1)*n+i)
             for j in range(len(rings)-1) for i in range(n)]
    mesh("SM_Printer_FDM_HollowPrintedVessel", points, faces, "clay")
    for y in [.218, .246, .274, .302, .33, .358, .378]:
        radius = .052 + .014 * math.sin((y-.196) / .184 * math.pi)
        cable("PrintLayer", [(-.15+radius*math.cos(i*math.tau/36), y, .044+radius*math.sin(i*math.tau/36))
                             for i in range(37)], .0018, "ochre" if "ochre" in api.get("M", {}) else "brass")
    # The spool is adjacent to the gantry, visibly feeds the extruder from above.
    rod("SM_Printer_FDM_SpoolBracket", (.074, .72, -.055), (.146, .72, -.055), .013, "stone_dark", 12)
    rod("SM_Printer_FDM_SpoolAxle", (.135, .72, -.064), (.135, .72, .067), .012, "brass", 16)
    for z in [-.037, .046]:
        tube("SM_Printer_FDM_SpoolFlange", (.135, .72, z), .073, .025, .009, "stone_dark")
    tube("SM_Printer_FDM_FilamentRoll", (.135, .72, .005), .065, .025, .068, "leather_green")
    cable("FilamentFeed", [(.16, .78, .012), (.105, .853, .014), (-.025, .86, .015),
                           (-.13, .776, .015), (-.15, .584, .03)], .003, "leather_green")
    cable("ExtruderCable", [(-.40, .81, -.06), (-.31, .84, -.015), (-.23, .73, .02), (-.15, .577, .025)], .005)
    # Angled front controls and a smaller resin machine distinguish two processes.
    box("SM_Printer_FDM_ControlPod", (-.38, .113, .188), (.15, .063, .052), "stone_dark", .006)
    box("SM_Printer_FDM_Screen", (-.395, .12, .217), (.075, .038, .005), "leather_blue", .001)
    rod("SM_Printer_FDM_ControlKnob", (-.335, .12, .215), (-.335, .12, .23), .012, "brass", 16)
    box("SM_Printer_Resin_Base", (.347, .098, 0), (.245, .148, .31), "stone_dark", .011)
    box("SM_Printer_Resin_Display", (.347, .11, .158), (.117, .044, .006), "leather_blue", .002)
    box("SM_Printer_Resin_Vat", (.347, .19, .015), (.18, .032, .19), "brass", .004)
    box("SM_Printer_Resin_VatSurface", (.347, .208, .015), (.145, .008, .154), "leather_green", .001)
    rod("SM_Printer_Resin_ZRail", (.347, .19, -.098), (.347, .61, -.098), .012, "brass", 16)
    box("SM_Printer_Resin_LiftArm", (.347, .51, -.047), (.13, .034, .13), "stone", .003)
    box("SM_Printer_Resin_BuildPlate", (.347, .48, .009), (.13, .026, .126), "stone_dark", .003)
    for dx in [-.032, 0, .032]:
        rod("SM_Printer_Resin_Support", (.347+dx, .464, .012), (.347+dx, .371, .012), .003, "paper", 8)
    cylinder("SM_Printer_Resin_Part", (.347, .345, .012), .043, .055, "clay", 24, .025)
    # Transparent enclosure has an explicit rim and handle; internals remain visible.
    box("SM_Printer_Resin_Hood", (.347, .417, -.005), (.223, .438, .279), "glass", .008)
    for x in [.238, .456]:
        rod("SM_Printer_Resin_HoodEdge", (x, .20, .132), (x, .636, .132), .003, "brass", 8)
    box("SM_Printer_Resin_HoodTop", (.347, .637, -.005), (.225, .018, .28), "leather_blue", .004)
    rod("SM_Printer_Resin_LidHandle", (.31, .673, -.005), (.386, .673, -.005), .008, "brass", 12)
    for x in [.31, .386]:
        rod("SM_Printer_Resin_HandleFoot", (x, .645, -.005), (x, .673, -.005), .006, "brass", 10)
