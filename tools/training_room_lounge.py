"""Authored low-poly lounge furniture for the training room.

Called by the scene builder; does not reset, save or change scene settings.
"""
import math
import bpy


def build_lounge(collection, materials):
    """Build the front-left L sectional, rug and two tables in metres."""
    created = []
    cube_cache = {}
    cushion_cache = {}

    def obj_mesh(name, mesh, mat, loc=(0, 0, 0)):
        obj = bpy.data.objects.new('LOUNGE_' + name, mesh)
        collection.objects.link(obj)
        obj.location = loc
        if len(mesh.materials) == 0:
            mesh.materials.append(materials[mat])
        created.append(obj)
        return obj

    def box(name, loc, size, mat, bevel=0.025):
        key = tuple(size) + (mat,)
        mesh = cube_cache.get(key)
        if mesh is None:
            x, y, z = [d * .5 for d in size]
            vertices = [(-x,-y,-z),(x,-y,-z),(x,y,-z),(-x,y,-z),
                        (-x,-y,z),(x,-y,z),(x,y,z),(-x,y,z)]
            faces = [(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),
                     (2,3,7,6),(3,0,4,7)]
            mesh = bpy.data.meshes.new('LOUNGE_mesh_' + name)
            mesh.from_pydata(vertices, [], faces)
            mesh.update()
            cube_cache[key] = mesh
        obj = obj_mesh(name, mesh, mat, loc)
        if bevel:
            mod = obj.modifiers.new('Soft manufactured edges', 'BEVEL')
            mod.width = bevel
            mod.segments = 3
            mod = obj.modifiers.new('Weighted corner normals', 'WEIGHTED_NORMAL')
            mod.keep_sharp = True
        return obj

    def line(name, points, mat='metal', radius=.004, cyclic=False):
        curve = bpy.data.curves.new('LOUNGE_curve_' + name, 'CURVE')
        curve.dimensions = '3D'
        curve.resolution_u = 1
        curve.bevel_depth = radius
        curve.bevel_resolution = 1
        spline = curve.splines.new('POLY')
        spline.points.add(len(points) - 1)
        for p, xyz in zip(spline.points, points):
            p.co = (*xyz, 1)
        spline.use_cyclic_u = cyclic
        return obj_mesh(name, curve, mat)

    def rounded_outline(cx, cy, z, sx, sy, rounding=.06):
        points = []
        for dx, dy, begin in [(1,1,0),(-1,1,90),(-1,-1,180),(1,-1,270)]:
            center = (cx+dx*(sx/2-rounding), cy+dy*(sy/2-rounding))
            for step in range(5):
                a = math.radians(begin + 90 * step/4)
                points.append((center[0]+rounding*math.cos(a),
                               center[1]+rounding*math.sin(a),z))
        return points

    def cylinder(name, loc, radius, depth, mat, count=32):
        vertices=[]
        for z in (-depth/2,depth/2):
            for i in range(count):
                a=2*math.pi*i/count
                vertices.append((radius*math.cos(a),radius*math.sin(a),z))
        faces=[tuple(reversed(range(count))),tuple(range(count,2*count))]
        faces += [(i,(i+1)%count,(i+1)%count+count,i+count) for i in range(count)]
        mesh=bpy.data.meshes.new('LOUNGE_mesh_'+name)
        mesh.from_pydata(vertices,[],faces)
        mesh.update()
        for p in list(mesh.polygons)[2:]:
            p.use_smooth=True
        ob=obj_mesh(name,mesh,mat,loc)
        mod=ob.modifiers.new('Machined rim','BEVEL')
        mod.width=.009
        mod.segments=3
        return ob

    def cushion(name, loc, size, rotation=(0,0,0)):
        # Squared superellipsoid keeps large upholstery faces softly inflated.
        key=tuple(size)
        mesh=cushion_cache.get(key)
        if mesh is None:
            def power(v, e):
                return math.copysign(abs(v)**e,v)
            verts=[]
            longitude=24
            latitude=12
            sx,sy,sz=[v/2 for v in size]
            verts.append((0,0,-sz))
            for j in range(1,latitude):
                theta=-math.pi/2+math.pi*j/latitude
                ct=power(math.cos(theta),.34)
                st=power(math.sin(theta),.50)
                for i in range(longitude):
                    phi=2*math.pi*i/longitude
                    verts.append((sx*ct*power(math.cos(phi),.35),
                                  sy*ct*power(math.sin(phi),.35),sz*st))
            top=len(verts)
            verts.append((0,0,sz))
            faces=[]
            for i in range(longitude):
                faces.append((0,1+(i+1)%longitude,1+i))
            for j in range(latitude-2):
                row=1+j*longitude
                nex=row+longitude
                for i in range(longitude):
                    k=(i+1)%longitude
                    faces.append((row+i,row+k,nex+k,nex+i))
            final=1+(latitude-2)*longitude
            for i in range(longitude):
                faces.append((final+i,final+(i+1)%longitude,top))
            mesh=bpy.data.meshes.new('LOUNGE_mesh_'+name)
            mesh.from_pydata(verts,[],faces)
            mesh.update()
            for poly in mesh.polygons:
                poly.use_smooth=True
            cushion_cache[key]=mesh
        ob=obj_mesh(name,mesh,'leather',loc)
        ob.rotation_euler=rotation
        return ob

    # The rug sits entirely on the floor and is bound around all four edges.
    box('Rug',(-4.30,-3.20,.017),(4.65,3.90,.028),'rug',.018)
    line('Rug_bound_edge',rounded_outline(-4.30,-3.20,.036,4.57,3.82,.08),
         'black',.011,True)
    # Low-relief staggered weave marks read as fabric without heavy geometry.
    for row in range(14):
        yy=-4.99+row*.275
        for start,end in [(-6.47,-5.33),(-4.96,-3.83),(-3.46,-2.14)]:
            offset=.045 if row%2 else -.045
            line('Rug_weave_%02d_%s'%(row,str(start)),
                 [(start,yy,.035),(end,yy+offset,.035)],'black',.004)

    # Connected sectional: left arm, corner, and front return.
    box('Left_frame',(-5.68,-2.67,.20),(1.18,3.73,.25),'black',.065)
    box('Return_frame',(-4.13,-4.68,.20),(4.27,1.12,.25),'black',.065)
    box('Left_back_shell',(-6.20,-2.74,.62),(.25,3.94,.66),'leather',.09)
    box('Return_back_shell',(-4.16,-5.15,.62),(4.19,.24,.66),'leather',.085)
    box('Left_end_arm',(-5.66,-.94,.48),(1.22,.22,.58),'leather',.08)
    box('Return_end_arm',(-2.08,-4.68,.48),(.22,1.18,.58),'leather',.08)

    # Blue light remains a fine undercut beneath otherwise black furniture.
    box('Left_recessed_glow',(-5.05,-2.75,.157),(.016,3.65,.012),'blue',.004)
    box('Return_recessed_glow',(-3.62,-4.08,.157),(3.12,.016,.012),'blue',.004)
    for xx,ys in [(-6.13,[-1.08,-2.7,-4.78]),(-5.19,[-1.08,-2.7,-4.78]),
                  (-2.26,[-4.31,-5.02]),(-3.72,[-4.31,-5.02])]:
        for yy in ys:
            box('Chrome_foot_%s_%s'%(xx,yy),(xx,yy,.083),(.085,.085,.14),'chrome',.008)

    for n,yy in enumerate([-1.47,-2.38,-3.29]):
        cushion('Left_seat_%02d'%n,(-5.64,yy,.366),(.91,.865,.205))
        line('Left_seat_piping_%02d'%n,
             rounded_outline(-5.64,yy,.391,.876,.830,.09),'metal',.0032,True)
        back=cushion('Left_back_cushion_%02d'%n,(-6.016,yy,.723),(.24,.86,.535))
        back.rotation_euler.y=math.radians(-7)
    cushion('Corner_seat',(-5.62,-4.24,.366),(.93,.98,.205))
    line('Corner_piping',rounded_outline(-5.62,-4.24,.391,.89,.94,.1),'metal',.0032,True)
    for n,xx in enumerate([-4.70,-3.72,-2.74]):
        cushion('Return_seat_%02d'%n,(xx,-4.62,.366),(.94,.87,.205))
        line('Return_seat_piping_%02d'%n,
             rounded_outline(xx,-4.62,.391,.907,.837,.09),'metal',.0032,True)
        back=cushion('Return_back_cushion_%02d'%n,(xx,-4.975,.724),(.94,.24,.535))
        back.rotation_euler.x=math.radians(7)
    cushion('Corner_back',(-5.64,-4.975,.724),(.91,.24,.535),
            (math.radians(7),0,0))
    cushion('Loose_pillow_A',(-5.72,-1.21,.665),(.22,.48,.44),
            (math.radians(-14),math.radians(-15),math.radians(12)))
    cushion('Loose_pillow_B',(-2.43,-4.80,.668),(.44,.20,.44),
            (math.radians(16),math.radians(12),math.radians(-10)))

    # Broad low marble coffee table; trim and feet are recessed from its edge.
    tx,ty=-3.65,-2.75
    box('Coffee_table_plinth',(tx,ty,.185),(1.54,1.24,.25),'black',.037)
    box('Coffee_table_shadow_gap',(tx,ty,.331),(1.68,1.38,.037),'metal',.016)
    box('Coffee_table_marble',(tx,ty,.379),(1.75,1.45,.067),'marble',.035)
    line('Coffee_table_light',rounded_outline(tx,ty,.342,1.70,1.40,.045),
         'blue',.009,True)
    for dx in [-.61,.61]:
        for dy in [-.46,.46]:
            box('Coffee_table_foot_%s_%s'%(dx,dy),(tx+dx,ty+dy,.067),
                (.115,.115,.10),'chrome',.01)

    cylinder('Side_table_base',(-6.0,-.60,.045),.265,.045,'black')
    cylinder('Side_table_stem',(-6.0,-.60,.276),.033,.435,'chrome',20)
    cylinder('Side_table_top',(-6.0,-.60,.53),.35,.043,'marble')
    line('Side_table_fine_rim',
         [(-6.0+.337*math.cos(2*math.pi*i/48),-.60+.337*math.sin(2*math.pi*i/48),.528)
          for i in range(48)],'chrome',.006,True)

    for obj in created:
        obj['training_room_zone']='lounge'
    return created
