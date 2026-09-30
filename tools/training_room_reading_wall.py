"""Authored shallow oak reading wall for the game's east entrance wall.

All coordinates are Blender metres.  This is furniture / room wayfinding,
not a second training device.  Keep the six character display sockets empty.
"""
import math
import bpy


def build_reading_wall(collection, materials, font):
    M = materials
    groups = {"Reading_Bookcase": [], "Reading_Bench": [],
              "Reading_Bench_Back": [], "Reading_Bench_Canopy": [],
              "Reading_Painting": []}

    def mesh(name, vertices, faces, mat, smooth=False):
        data = bpy.data.meshes.new(name)
        data.from_pydata(vertices, [], faces)
        data.update()
        obj = bpy.data.objects.new("READING | " + name, data)
        collection.objects.link(obj)
        data.materials.append(M[mat])
        for polygon in data.polygons:
            polygon.use_smooth = smooth
        return obj

    def box(name, loc, size, mat, bevel=.015, group=None):
        x, y, z = [v * .5 for v in size]
        vs = [(-x,-y,-z),(x,-y,-z),(x,y,-z),(-x,y,-z),
              (-x,-y,z),(x,-y,z),(x,y,z),(-x,y,z)]
        fs = [(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]
        obj = mesh(name,vs,fs,mat)
        obj.location = loc
        if bevel:
            mod = obj.modifiers.new("Soft joined oak edge", "BEVEL")
            mod.width = bevel
            mod.segments = 3
            obj.modifiers.new("Weighted corner normals", "WEIGHTED_NORMAL")
        if group:
            groups[group].append(obj)
        return obj

    def line(name, points, mat, radius=.006, cyclic=False):
        data = bpy.data.curves.new(name, "CURVE")
        data.dimensions = "3D"
        data.bevel_depth = radius
        data.bevel_resolution = 1
        data.resolution_u = 1
        spline = data.splines.new("POLY")
        spline.points.add(len(points)-1)
        for point, co in zip(spline.points, points):
            point.co = (*co, 1)
        spline.use_cyclic_u = cyclic
        obj = bpy.data.objects.new("READING | " + name, data)
        collection.objects.link(obj)
        data.materials.append(M[mat])
        return obj

    def label(name, body, y, z, size, mat="cream", x=9.28):
        data = bpy.data.curves.new(name, "FONT")
        data.body = body
        data.font = font
        data.size = size
        data.align_x = "CENTER"
        data.align_y = "CENTER"
        data.resolution_u = 3
        data.extrude = .0007
        data.materials.append(M[mat])
        obj = bpy.data.objects.new("READING | " + name, data)
        collection.objects.link(obj)
        obj.location = (x, y, z)
        obj.rotation_euler = (math.pi/2, 0, -math.pi/2)
        return obj

    def signed_power(value, exponent):
        return math.copysign(abs(value)**exponent, value)

    def cushion(name, center, size, mat, group):
        # Closed tailored surface with rounded gusset and a lightly compressed
        # crown, rather than a beveled rectangular furniture placeholder.
        a,b,c = [v*.5 for v in size]
        vs = [(center[0],center[1],center[2]-c)]
        rings = []
        segments = 40
        for row in range(1,16):
            lat = -math.pi/2 + math.pi*row/16
            rings.append([])
            for i in range(segments):
                angle = math.tau*i/segments
                breadth = abs(math.cos(lat))**.42
                x = a*breadth*signed_power(math.cos(angle),.32)
                y = b*breadth*signed_power(math.sin(angle),.32)
                z = c*signed_power(math.sin(lat),.48)
                # Shallow relaxed depression in the upper seating surface.
                if z > 0:
                    z -= .012*max(0,1-(x/a)**2)*max(0,1-(y/b)**2)
                rings[-1].append(len(vs))
                vs.append((center[0]+x,center[1]+y,center[2]+z))
        top = len(vs)
        vs.append((center[0],center[1],center[2]+c-.012))
        fs = []
        for i in range(segments):
            nxt = (i+1)%segments
            fs.append((0,rings[0][nxt],rings[0][i]))
            for low,high in zip(rings,rings[1:]):
                fs.append((low[i],low[nxt],high[nxt],high[i]))
            fs.append((rings[-1][i],rings[-1][nxt],top))
        obj = mesh(name,vs,fs,mat,True)
        obj["tailored_bench_cushion"] = True
        groups[group].append(obj)
        seam=[]
        for i in range(80):
            t=math.tau*i/80
            seam.append((center[0]+a*signed_power(math.cos(t),.32),
                         center[1]+b*signed_power(math.sin(t),.32),center[2]))
        line(name+" welt",seam,"dark_teal",.0045,True)
        return obj

    # Asymmetric bookcase beside the long upholstered reading seat.  The oak
    # frames have actual thickness and recessed backing, not painted wall marks.
    group = "Reading_Bookcase"
    box("bookcase recessed backing",(9.86,-1.95,1.41),(.10,1.55,2.57),"dark_teal",.022,group)
    for y in [-2.77,-1.13]:
        box("bookcase upright",(9.57,y,1.42),(.66,.09,2.68),"wood",.023,group)
    for z in [.13,.72,1.30,1.88,2.73]:
        box("bookcase oak shelf",(9.53,-1.95,z),(.72,1.73,.075),"wood",.018,group)
        if z>.8:
            box("bookcase warm shelf inset",(9.22,-1.95,z-.040),(.026,1.50,.009),"white_light",.003)
    box("bookcase inset toe",(9.61,-1.95,.09),(.48,1.48,.10),"dark_teal",.015,group)

    def book(index, y, base, height, width, color):
        # Spine faces the room. Page block is recessed within separate covers.
        before=set(collection.objects)
        x=9.46
        box("volume %02d pages"%index,(x,y,base+height/2),(.35,width-.018,height-.025),"cream",.004)
        for side in [-1,1]:
            box("volume %02d cover"%index,(x,y+side*(width/2-.004),base+height/2),(.38,.008,height),color,.004)
        box("volume %02d curved spine"%index,(x-.185,y,base+height/2),(.022,width,height),color,.009)
        for z in [base+.055,base+height-.055]:
            line("volume %02d spine band"%index,[(x-.199,y-width*.33,z),(x-.199,y+width*.33,z)],"gold",.003)
        for obj in set(collection.objects)-before:
            obj['interactive_root']='BOOK_%02d'%index
            obj['interactive_pivot']=[x,y,base+height/2]
            obj['book_index']=index
            obj['book_cover_color']={'sage':'#708474','teal':'#345c58','wood_dark':'#846747','gold':'#d4cd84'}[color]

    # Deliberately arranged clusters; leave breathing room in each shelf bay.
    for index,(y,z,h,w,color) in enumerate([
        (-2.55,.764,.36,.13,"sage"),(-2.40,.764,.42,.13,"teal"),
        (-2.24,.764,.38,.15,"wood_dark"),(-2.07,.764,.33,.15,"gold"),
        (-1.86,.764,.41,.15,"teal"),(-1.69,.764,.36,.13,"sage"),
        (-1.37,1.344,.36,.14,"sage"),(-1.54,1.344,.40,.15,"wood_dark"),
        (-1.73,1.344,.43,.16,"teal"),(-1.92,1.344,.37,.15,"gold"),
        (-2.45,1.924,.43,.18,"teal"),(-2.23,1.924,.38,.17,"sage"),
        (-2.02,1.924,.47,.17,"wood_dark")],1):
        book(index,y,z,h,w,color)
    for y in [-2.34,-1.56]:
        box("linen storage basket",(9.48,y,.41),(.45,.64,.44),"rug",.032)
        box("basket recessed handle",(9.247,y,.45),(.014,.18,.045),"wood_dark",.018)
        for h in [.22,.29,.36,.43,.50,.57]:
            line("basket woven edge",[(9.245,y-.28,h),(9.245,y+.28,h)],"sage",.0025)
    label("bookcase header","閱 讀",-1.50,2.39,.13,"gold",9.795)

    group="Reading_Bench"
    box("bench oak wall panel",(9.83,-4.50,1.39),(.19,3.18,2.54),"wood",.045,"Reading_Bench_Back")
    box("bench teal acoustic inset",(9.712,-4.50,1.66),(.065,2.91,1.63),"dark_teal",.070,"Reading_Bench_Back")
    for y in [-5.985,-3.015]:
        box("bench joinery end post",(9.69,y,1.42),(.25,.07,2.46),"wood_dark",.017)
    box("bench recessed plinth",(9.29,-4.50,.14),(.68,2.96,.20),"dark_teal",.026,group)
    box("bench oak storage carcass",(9.27,-4.50,.265),(.99,3.16,.22),"wood",.035,group)
    box("bench shaped oak seat rim",(9.25,-4.50,.385),(1.08,3.22,.065),"wood_dark",.035,group)
    for y in [-5.26,-3.74]:
        box("bench drawer front",(8.764,y,.28),(.035,1.43,.16),"wood",.015)
        line("bench recessed drawer pull",[(8.737,y-.12,.32),(8.737,y+.12,.32)],"dark_teal",.013)
        cushion("bench tailored seat",(9.24,y,.465),(.99,1.47,.22),"sage",group)
        cushion("bench tailored back",(9.60,y,.95),(.20,1.40,.68),"teal","Reading_Bench_Back")
    label("reading alcove title","休憩 · 閱讀",-4.50,2.11,.255,"cream",9.668)
    label("reading alcove subline","TAKE A MOMENT",-4.50,1.76,.074,"gold",9.667)
    box("alcove warm downlight housing",(9.55,-4.50,2.64),(.63,3.23,.105),"wood",.030,"Reading_Bench_Canopy")
    box("alcove warm downlight diffuser",(9.48,-4.50,2.581),(.32,2.94,.012),"white_light",.008)

    # Actual public-domain artwork, framed at its original landscape aspect.
    # The canvas has authored 0-1 UVs which the exporter preserves per loop.
    group="Reading_Painting"
    painting_objects=set(collection.objects)
    center_y, center_z = -7.15,1.90
    width=1.83
    height=width * M['starry_night'].get('image_aspect_height',.793)
    box("Starry Night oak frame",(9.862,center_y,center_z),(.18,width+.16,height+.16),"wood",.028,group)
    box("Starry Night linen mount",(9.760,center_y,center_z),(.034,width+.075,height+.075),"cream",.006)
    vs=[(9.738,center_y+width/2,center_z-height/2),(9.738,center_y-width/2,center_z-height/2),
        (9.738,center_y-width/2,center_z+height/2),(9.738,center_y+width/2,center_z+height/2)]
    canvas=mesh("Starry Night canvas",vs,[(0,3,2,1)],'starry_night')
    uv=canvas.data.uv_layers.new(name='UVMap')
    coords={0:(0,0),1:(1,0),2:(1,1),3:(0,1)}
    for polygon in canvas.data.polygons:
        for li in polygon.loop_indices:uv.data[li].uv=coords[canvas.data.loops[li].vertex_index]
    canvas['preserve_authored_uv']=True
    label("Starry Night caption","星空 · Vincent van Gogh · 1889",center_y,center_z-height/2-.19,.075,"dark_teal",9.755)
    for obj in set(collection.objects)-painting_objects:
        obj['interactive_root']='PAINTING_StarryNight'
        obj['interactive_pivot']=[9.80,center_y,center_z]

    return groups
