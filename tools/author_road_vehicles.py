"""Original production fleet. Blender 5.2 background authoring, GLB and renders.

Units are meters. Blender -Y is forward, exporting as Godot +Z. Wheel pivots
export as wheel-* nodes and rotate about their local X axes. No vendor meshes.
"""
import bpy, bmesh, math, json, os, sys
from mathutils import Vector, Matrix
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'art' / 'Vehicles'
OUT = ROOT / 'game' / 'assets' / 'vehicles'
REVIEW = ROOT / 'deliverables' / 'vehicles'
for folder in (ART, OUT, REVIEW): folder.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
scene.unit_settings.system='METRIC'; scene.unit_settings.scale_length=1
scene.render.engine='CYCLES'; scene.cycles.samples=40
scene.cycles.use_denoising=True; scene.cycles.adaptive_threshold=.08
scene.render.resolution_x=1200; scene.render.resolution_y=840
scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX'
geo=bpy.data.collections.new('COL_Geo'); scene.collection.children.link(geo)
cutters=bpy.data.collections.new('COL_CollisionAndCutters'); scene.collection.children.link(cutters)
studio=bpy.data.collections.new('COL_Studio'); scene.collection.children.link(studio)
blockout=bpy.data.collections.new('COL_Blockout'); scene.collection.children.link(blockout)

def mat(name, color, metal=0, rough=.4, coat=0, emission=None):
    m=bpy.data.materials.new('MAT_'+name); m.diffuse_color=(*color,1); m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF'); p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Metallic'].default_value=metal; p.inputs['Roughness'].default_value=rough
    p.inputs['Coat Weight'].default_value=coat; p.inputs['Coat Roughness'].default_value=.16
    if emission:
        p.inputs['Emission Color'].default_value=(*color,1); p.inputs['Emission Strength'].default_value=emission
    return m

trim=mat('Trim_SatinGraphite',(.025,.030,.035),.18,.32)
glass=mat('Glass_SmokedReflective',(.018,.030,.040),.22,.11,.5)
rubber=mat('Rubber_Tire',(.014,.017,.020),0,.83)
alloy=mat('Alloy_BrushedAluminium',(.42,.46,.49),.95,.25)
lamp=mat('Lamp_WhiteLED',(.84,.91,1.0),.15,.18,.2,.7)
tail=mat('Lamp_RubyLens',(.26,.009,.014),.18,.18,.5,.35)
amber=mat('Lamp_AmberLens',(.72,.20,.015),.12,.23,.3,.2)
plate=mat('Plate_OffWhite',(.60,.63,.62),.05,.43)

def link(obj,col=geo):
    for c in list(obj.users_collection): c.objects.unlink(obj)
    col.objects.link(obj)
    return obj

def mesh(name, verts, faces, material, smooth=True):
    me=bpy.data.meshes.new(name+'_Topology'); me.from_pydata(verts,[],faces); me.update()
    ob=bpy.data.objects.new('SM_'+name,me); geo.objects.link(ob)
    if material: me.materials.append(material)
    for p in me.polygons: p.use_smooth=smooth
    return ob

def bevel(ob, width=.015, segments=3):
    mod=ob.modifiers.new('Bevel_manufactured_edges','BEVEL'); mod.width=width; mod.segments=segments
    mod.limit_method='ANGLE'
    return ob

def cube(name, at, size, material, bevel_width=.015):
    bpy.ops.mesh.primitive_cube_add(size=1, location=at); ob=link(bpy.context.object); ob.name='SM_'+name
    ob.dimensions=size; bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    ob.data.materials.append(material)
    if bevel_width: bevel(ob,bevel_width,3)
    return ob

def sphere(name, at, size, material):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24,ring_count=12,location=at)
    ob=link(bpy.context.object); ob.name='SM_'+name; ob.scale=Vector(size)*.5
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    ob.data.materials.append(material)
    for p in ob.data.polygons: p.use_smooth=True
    return ob

def curve(name, points, thickness, material, closed=False):
    data=bpy.data.curves.new(name,'CURVE'); data.dimensions='3D'; data.resolution_u=1
    data.bevel_depth=thickness; data.bevel_resolution=1
    data.use_fill_caps=True
    sp=data.splines.new('POLY'); sp.points.add(len(points)-1)
    for p,v in zip(sp.points,points): p.co=(*v,1)
    sp.use_cyclic_u=closed
    ob=bpy.data.objects.new('SM_'+name,data); geo.objects.link(ob); data.materials.append(material)
    return ob

def interp(knots, x, index):
    for i in range(len(knots)-1):
        if x<=knots[i+1][0]:
            a,b=knots[i],knots[i+1]; t=max(0,min(1,(x-a[0])/(b[0]-a[0])))
            # Smooth cubic avoids the stepped primitive-car silhouette.
            t=t*t*(3-2*t)
            return a[index]*(1-t)+b[index]*t
    return knots[-1][index]

def loft(name, knots, paint, longitudinal=58, around=24):
    verts=[]; faces=[]
    for i in range(longitudinal+1):
        y=knots[0][0]+(knots[-1][0]-knots[0][0])*i/longitudinal
        w,lo,hi=(interp(knots,y,k) for k in (1,2,3))
        for j in range(around):
            a=math.tau*j/around; c,s=math.cos(a),math.sin(a)
            x=w*math.copysign(abs(c)**.43,c)
            z=(hi+lo)*.5+(hi-lo)*.5*math.copysign(abs(s)**.18,s)
            verts.append((x,y,z))
    for i in range(longitudinal):
        for j in range(around):
            a=i*around+j; b=i*around+(j+1)%around
            faces.append((a,b,b+around,a+around))
    faces.append(tuple(reversed(range(around))))
    faces.append(tuple(longitudinal*around+j for j in range(around)))
    return mesh(name,verts,faces,paint)

def cylinder(name, at, radius, depth, material, segments=48):
    bpy.ops.mesh.primitive_cylinder_add(vertices=segments,radius=radius,depth=depth,location=at,rotation=(0,math.pi/2,0))
    ob=link(bpy.context.object); ob.name='SM_'+name
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    if material: ob.data.materials.append(material)
    for p in ob.data.polygons: p.use_smooth=len(p.vertices)==4
    return ob

def tire(name, center, rad, width):
    # A shaped radial tire, with a flat contact band and round sidewalls.
    profile=[(-width*.5,.73),(-width*.54,.83),(-width*.46,.96),(-width*.30,1),
             (-width*.1,1.004),(width*.1,1.004),(width*.3,1),(width*.46,.96),
             (width*.54,.83),(width*.5,.73)]
    verts=[]; faces=[]; count=48
    for x,r in profile:
        for i in range(count):
            a=math.tau*i/count; verts.append((center[0]+x,center[1]+rad*r*math.sin(a),center[2]+rad*r*math.cos(a)))
    for j in range(len(profile)):
        for i in range(count):
            faces.append((j*count+i,j*count+(i+1)%count,((j+1)%len(profile))*count+(i+1)%count,((j+1)%len(profile))*count+i))
    return mesh(name,verts,faces,rubber)

def ring(name, x,y,z,radius,tube,material,segments=48):
    points=[(x,y+math.sin(i*math.tau/segments)*radius,z+math.cos(i*math.tau/segments)*radius) for i in range(segments)]
    return curve(name,points,tube,material,True)

def cabin(name, rows, paint):
    # Curved continuous roof and sloping pillars, instead of a box on a box.
    verts=[]; faces=[]; along=36; across=16
    for i in range(along+1):
        y=rows[0][0]+(rows[-1][0]-rows[0][0])*i/along
        w,base,top=(interp(rows,y,k) for k in (1,2,3))
        for j in range(across+1):
            t=-1+2*j/across
            x=w*t
            z=base+(top-base)*(1-abs(t)**5.5)
            verts.append((x,y,z))
    for i in range(along):
        for j in range(across):
            a=i*(across+1)+j; faces.append((a,a+1,a+across+2,a+across+1))
    ob=mesh(name,verts,faces,paint)
    solid=ob.modifiers.new('Solidify_roof_skin','SOLIDIFY'); solid.thickness=.024
    return ob

def glass_panel(name, points):
    ob=mesh(name,points,[tuple(range(len(points)))],glass,False)
    solid=ob.modifiers.new('Solidify_laminated_glass','SOLIDIFY'); solid.thickness=.009
    bevel(ob,.012,3)
    curve(name+'_WeatherSeal',points,.012,trim,True)
    return ob

def cleanup_export(objects, root_name, path, lod_ratio=1):
    export_col=bpy.data.collections.new('COL_Export_'+root_name); scene.collection.children.link(export_col)
    root=bpy.data.objects.new(root_name,None); export_col.objects.link(root)
    groups={}
    deps=bpy.context.evaluated_depsgraph_get()
    for original in objects:
        if original.type not in {'MESH','CURVE'}: continue
        group=original.get('wheel_group','body')
        evaluated=original.evaluated_get(deps)
        data=bpy.data.meshes.new_from_object(evaluated,depsgraph=deps)
        ob=bpy.data.objects.new(original.name,data); export_col.objects.link(ob); ob.matrix_world=original.matrix_world.copy()
        groups.setdefault(group,[]).append(ob)
    triangles=0; parts=[]; all_bounds=[]
    for group, obs in groups.items():
        bpy.ops.object.select_all(action='DESELECT')
        for ob in obs: ob.select_set(True)
        bpy.context.view_layer.objects.active=obs[0]; bpy.ops.object.join(); ob=obs[0]
        ob.name='SM_'+root_name+'_'+group.replace('-','_')
        bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
        bm=bmesh.new(); bm.from_mesh(ob.data); bmesh.ops.remove_doubles(bm,verts=bm.verts,dist=.000015)
        bmesh.ops.recalc_face_normals(bm,faces=bm.faces); bm.to_mesh(ob.data); bm.free()
        if lod_ratio<1:
            mod=ob.modifiers.new('LOD_preserve_silhouette','DECIMATE'); mod.ratio=lod_ratio
            bpy.context.view_layer.objects.active=ob; bpy.ops.object.modifier_apply(modifier=mod.name)
        if not ob.data.uv_layers:
            ob.data.uv_layers.new(name='UV_Surface')
            for poly in ob.data.polygons:
                for li in poly.loop_indices:
                    v=ob.data.vertices[ob.data.loops[li].vertex_index].co
                    ob.data.uv_layers.active.data[li].uv=(v.y*.2+.5,v.z*.5)
        # Bake object transforms before parenting. A newly created empty has no
        # evaluated matrix_world yet; using that stale inverse double-offsets
        # wheel meshes after glTF import even though the source render is right.
        source_matrix=ob.matrix_world.copy()
        if group!='body':
            pivot=bpy.data.objects.new(group,None); export_col.objects.link(pivot)
            center=Vector(next(src['wheel_center'] for src in objects if src.get('wheel_group')==group))
            pivot.location=center; pivot.parent=root
            ob.data.transform(Matrix.Translation(-center)@source_matrix)
            ob.parent=pivot; ob.matrix_parent_inverse=Matrix.Identity(4); ob.matrix_basis=Matrix.Identity(4)
        else:
            ob.data.transform(source_matrix)
            ob.parent=root; ob.matrix_parent_inverse=Matrix.Identity(4); ob.matrix_basis=Matrix.Identity(4)
        bpy.context.view_layer.update()
        ob.data.calc_loop_triangles(); triangles+=len(ob.data.loop_triangles)
        for c in ob.bound_box: all_bounds.append(ob.matrix_world@Vector(c))
        parts.append({'mesh':ob.name,'triangles':len(ob.data.loop_triangles),'materials':len(ob.data.materials)})
    bpy.ops.object.select_all(action='DESELECT')
    for ob in export_col.objects: ob.select_set(True)
    bpy.context.view_layer.objects.active=root
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_yup=True,
        export_apply=True,export_animations=False,export_cameras=False,export_lights=False,export_extras=True)
    dims=[max(v[k] for v in all_bounds)-min(v[k] for v in all_bounds) for k in range(3)]
    for ob in list(export_col.objects): bpy.data.objects.remove(ob,do_unlink=True)
    bpy.data.collections.remove(export_col)
    return {'triangles':triangles,'dimensions_blender_xyz':dims,'meshes':parts,'forward':'Godot +Z','ground_origin':'tire contact','meters':True}

def build(spec):
    key,L,W,H,r,axle,paint_color=spec
    print('AUTHORING',key,flush=True)
    paint=mat('Paint_'+key,paint_color,.38,.27,.62)
    before=set(geo.objects); half=L*.5; base=.22 if key!='suv' else .28
    belt=H*.68; hw=W*.5
    knots=[(-half,.78*hw,base+.07,belt*.82),(-half+.12,.94*hw,base,belt*.9),
           (-axle,hw,base,belt*.98),(-.7,hw,base,belt*1.02),(.65,hw,base,belt),
           (axle,.99*hw,base,belt*.96),(half-.12,.94*hw,base+.035,belt*.91),(half,.77*hw,base+.09,belt*.84)]
    body=loft(key+'_ContinuousSteelBody',knots,paint)
    # Real negative wheel-well volumes are retained as editable modifiers.
    for y in (-axle,axle):
        cut=cylinder(key+'_WheelArchCutter',(0,y,r),r+.052,W+1,None,64); link(cut,cutters)
        cut.hide_render=True; cut.display_type='WIRE'
        mod=body.modifiers.new('WheelArch_%s'%y,'BOOLEAN'); mod.operation='DIFFERENCE'; mod.solver='EXACT'; mod.object=cut
    bevel(body,.008,2)
    roof_front=-.40 if key=='sedan' else -.45
    roof_back=.78 if key=='sedan' else 1.15
    cabin_back=1.53 if key=='sedan' else half-.18
    rows=[(-1.00,hw*.89,belt*.955,belt*1.01),
          (roof_front,hw*.90,belt*.955,H-.035),(0,hw*.88,belt*.95,H),
          (roof_back,hw*.87,belt*.945,H-.025),(cabin_back,hw*.90,belt*.93,belt*1.015)]
    cabin(key+'_RoofAndPillars',rows,paint)
    # Pane surfaces follow the cab's actual cross-section and longitudinal roof.
    def skin_point(y,t,raise_z=.014):
        w,lo,hi=(interp(rows,y,k) for k in (1,2,3))
        return (w*t,y,lo+(hi-lo)*(1-abs(t)**5.5)+raise_z)
    def body_side(y,z):
        w,lo,hi=(interp(knots,y,k) for k in (1,2,3))
        vertical=max(-.9999,min(.9999,(z-(lo+hi)*.5)/((hi-lo)*.5)))
        sine=abs(vertical)**(1/.18)
        return w*(max(0,1-sine*sine)**.5)**.43
    def body_top(y,x):
        w,lo,hi=(interp(knots,y,k) for k in (1,2,3))
        cosine=min(.9999,abs(x)/w)**(1/.43)
        return (hi+lo)*.5+(hi-lo)*.5*(max(0,1-cosine*cosine)**.5)**.18
    # Curved windscreen and rear screen: an actual subdivided surface.
    for name,ya,yb in [('Windscreen',-.94,roof_front-.035),('RearScreen',roof_back+.10,cabin_back-.065)]:
        verts=[]; faces=[]; nu,nv=10,6
        for j in range(nv+1):
            y=ya+(yb-ya)*j/nv
            for i in range(nu+1): verts.append(skin_point(y,(-.84+1.68*i/nu)))
        for j in range(nv):
            for i in range(nu):
                a=j*(nu+1)+i; faces.append((a,a+1,a+nu+2,a+nu+1))
        pane=mesh(key+'_'+name,verts,faces,glass)
        solid=pane.modifiers.new('Glass_lamination','SOLIDIFY'); solid.thickness=.005
        for y in (ya,yb): curve(key+'_'+name+'_Seal', [skin_point(y,-.84+1.68*i/16) for i in range(17)],.012,trim)
    # The side glass has a low beltline and a separate B pillar.
    for side in (-1,1):
        ranges=[(-.72,.34),(.42,roof_back+.18)]
        for door,(ya,yb) in enumerate(ranges):
            top=[]; bottom=[]
            for j in range(13):
                y=ya+(yb-ya)*j/12
                # On the curved shell, t=.91 is the rising shoulder and
                # t=.72 runs just below the roof edge; x follows the skin.
                top.append(skin_point(y,side*.72,.018))
                bottom.append(skin_point(y,side*.977,.018))
            # Use a surface grid, not a non-planar n-gon: triangulating a bowed
            # window polygon produces bright paint triangles through its face.
            verts=[]; faces=[]; nu,nv=16,7
            for j in range(nu+1):
                y=ya+(yb-ya)*j/nu
                for i in range(nv+1): verts.append(skin_point(y,side*(.72+(.977-.72)*i/nv),.024))
            for j in range(nu):
                for i in range(nv):
                    a=j*(nv+1)+i; faces.append((a,a+1,a+nv+2,a+nv+1))
            pane=mesh(key+'_SideWindow_%s_%s'%(side,door),verts,faces,glass)
            solid=pane.modifiers.new('Solidify_side_glass','SOLIDIFY'); solid.thickness=.005
            pts=top+list(reversed(bottom)); curve(key+'_WindowSeal_%s_%s'%(side,door),pts,.009,trim,True)
        for ya,yb in ranges:
            y0=ya-.06; y1=yb+.025
            path=[]
            yz=[(y0,belt*.99),(y0+.06,.48 if key!='suv' else .57),(y1-.06,.40 if key!='suv' else .49),(y1,belt*.99)]
            for (ay,az),(by,bz) in zip(yz,yz[1:]):
                for j in range(9):
                    yy=ay+(by-ay)*j/8; zz=az+(bz-az)*j/8
                    path.append((side*(body_side(yy,zz)+.004),yy,zz))
            curve(key+'_DoorGap_%s_%s'%(side,ya),path,.0045,trim)
            handle_y=yb-.17
            hx=body_side(handle_y,belt-.07)
            cube(key+'_HandleRecess',(side*(hx+.005),handle_y,belt-.07),(.018,.175,.034),trim,.01)
            cube(key+'_DoorHandle',(side*(hx+.022),handle_y,belt-.056),(.025,.13,.018),alloy,.008)
        # Character crease, sill and authentic fender outlines.
        hood_line=[]
        for j in range(22):
            y=-half+.22+(-1.02-(-half+.22))*j/21; x=side*hw*.60
            hood_line.append((x,y,body_top(y,x)+.003))
        curve(key+'_HoodShutLine_'+str(side),hood_line,.0028,trim)
        curve(key+'_RockerTrim_'+str(side),[(side*(hw*.975),-axle+.36,base+.08),(side*(hw*.975),axle-.36,base+.08)],.025,trim)
        for y in (-axle,axle):
            pts=[]
            for j in range(33):
                a=math.pi*j/32
                pts.append((side*(hw+.012),y+math.cos(a)*(r+.055),r+math.sin(a)*(r+.055)))
            curve(key+'_WheelArchLip_'+str(side)+str(y),pts,.014,trim if key=='suv' else paint)
        stem=cube(key+'_MirrorStalk',(side*(hw+.035),-.62,belt+.09),(.15,.07,.038),trim,.016)
        sphere(key+'_MirrorHousing',(side*(hw+.14),-.64,belt+.15),(.26,.19,.135),paint)
        mirror=cube(key+'_MirrorGlass',(side*(hw+.14),-.543,belt+.15),(.20,.014,.08),glass,.025)
    # Grille, bumpers, lamp clusters, DRLs and license plate recesses.
    for front in (True,False):
        sign=-1 if front else 1; y=sign*(half-.018)
        cube(key+'_Bumper_'+str(front),(0,y,base+.17),(W*.84,.12,.15),paint,.045)
        cube(key+'_LowerValance_'+str(front),(0,sign*(half+.015),base+.045),(W*.71,.07,.12),trim,.035)
        if front:
            cube(key+'_Intake',(0,y-.045,belt*.64),(W*.43,.045,.155),trim,.025)
            for j in range(5):
                cube(key+'_GrilleSlat_'+str(j),(0,y-.073,belt*.58+j*.026),(W*.39,.012,.008),alloy,.003)
        for side in (-1,1):
            lx=side*W*.31; lz=belt*.74 if front else belt*.77
            cube(key+'_LampHousing_'+str(front)+str(side),(lx,y-sign*.008,lz),(W*.225,.06,.105),trim,.028)
            cube(key+'_LampLens_'+str(front)+str(side),(lx,y+sign*.024,lz),(W*.198,.014,.069),lamp if front else tail,.019)
            curve(key+'_LightSignature_'+str(front)+str(side),[(lx-side*.12,y+sign*.033,lz-.022),(lx+side*.11,y+sign*.033,lz-.022),(lx+side*.135,y+sign*.029,lz+.005)],.007,lamp if front else tail)
            if front: cube(key+'_AmberMarker_'+str(side),(side*W*.417,y-.03,lz),(.025,.017,.053),amber,.007)
        cube(key+'_PlateRecess_'+str(front),(0,y+sign*.05,base+.20),(.40,.035,.105),trim,.017)
        cube(key+'_LicensePlate_'+str(front),(0,y+sign*.071,base+.20),(.31,.012,.072),plate,.007)
        # Small engraved-looking bars make plates legible without fake branding.
        for j in range(6): cube(key+'_PlateGlyph_%s_%s'%(front,j),(-.103+j*.039,y+sign*.079,base+.20),(.018,.003,.028),trim,.002)
    if key=='suv':
        for side in (-1,1): curve(key+'_RoofRail_'+str(side),[(side*.62,-.38,H+.024),(side*.63,.95,H+.024),(side*.60,1.21,H-.006)],.026,trim)
    # Four independently turning real wheel assemblies.
    for side in (-1,1):
        for y in (-axle,axle):
            wheel_before=set(geo.objects)
            x=side*(hw-.073); center=(x,y,r*1.004)
            group='wheel-'+('front' if y<0 else 'rear')+'-'+('left' if side<0 else 'right')
            tire(key+'_'+group+'_RadialTire',center,r,.225 if key!='suv' else .25)
            outer=x+side*.127
            cylinder(key+'_'+group+'_BrakeDisc',(outer-side*.065,y,center[2]),r*.64,.017,alloy,48)
            ring(key+'_'+group+'_WheelBarrel',outer-side*.04,y,center[2],r*.72,.018,trim)
            ring(key+'_'+group+'_PolishedLip',outer,y,center[2],r*.72,.012,alloy)
            cylinder(key+'_'+group+'_Hub',(outer+side*.015,y,center[2]),r*.18,.025,alloy,24)
            for j in range(5 if key=='sedan' else 6):
                angle=math.tau*j/(5 if key=='sedan' else 6)
                for split in (-.045,.045):
                    a=angle+split
                    p0=(outer+side*.006,y+math.sin(a)*r*.15,center[2]+math.cos(a)*r*.15)
                    p1=(outer+side*.004,y+math.sin(a+.11)*r*.66,center[2]+math.cos(a+.11)*r*.66)
                    curve(key+'_'+group+'_ForgedSpoke', [p0,p1],.018,alloy)
                bolt=(outer+side*.033,y+math.sin(angle)*r*.12,center[2]+math.cos(angle)*r*.12)
                cylinder(key+'_'+group+'_Lug',bolt,.011,.01,trim,8)
            # Fine circumferential tread channels, not large toy tire blocks.
            for band in (-.066,0,.066): ring(key+'_'+group+'_Tread',x+band,y,center[2],r*1.004,.0024,trim,48)
            for ob in set(geo.objects)-wheel_before:
                ob['wheel_group']=group; ob['wheel_center']=center
    objects=list(set(geo.objects)-before)
    for ob in objects: ob['vehicle']=key
    # Keep simple scale envelopes in the editable file, excluded from render.
    ref=cube(key+'_BlockoutScale',(0,0,H*.5),(W,L,H),trim,0); link(ref,blockout); ref.hide_render=True; ref.hide_set(True)
    report=cleanup_export(objects,key,OUT/(key+'.glb'),.60)
    report['lod1']=cleanup_export(objects,key+'_LOD1',OUT/(key+'_lod1.glb'),.30)
    report['wheel_radius']=r; report['wheelbase']=2*axle; report['track']=W-.146
    return objects,report

specs=[('sedan',4.62,1.82,1.45,.325,1.40,(.095,.115,.135)),
       ('hatchback',4.08,1.79,1.51,.315,1.25,(.24,.27,.235)),
       ('suv',4.60,1.89,1.71,.355,1.39,(.025,.065,.108))]
fleet={}; reports={}
for spec in specs: fleet[spec[0]],reports[spec[0]]=build(spec)
total=sum(x['triangles'] for x in reports.values())
assert total<=80000, f'Fleet LOD0 budget exceeded: {total}'

# Neutral photographic studio. Kept separate from all exported game meshes.
ground=cube('StudioGround',(0,0,-.08),(200,200,.15),mat('Studio_Concrete',(.17,.19,.205),0,.72),0); link(ground,studio)
world=bpy.data.worlds.new('VehicleStudioWorld'); scene.world=world; world.use_nodes=True
world.node_tree.nodes['Background'].inputs['Color'].default_value=(.40,.46,.54,1)
world.node_tree.nodes['Background'].inputs['Strength'].default_value=.45
def light(name,loc,power,size,target=(0,0,.7)):
    data=bpy.data.lights.new(name,'AREA'); data.energy=power; data.shape='DISK'; data.size=size
    ob=bpy.data.objects.new(name,data); studio.objects.link(ob); ob.location=loc
    ob.rotation_euler=(Vector(target)-ob.location).to_track_quat('-Z','Y').to_euler()
light('Studio_Key',(3,-4,6),1600,5)
light('Studio_Side',(-4,-1,3),950,4)
light('Studio_Rim',(1,5,4),1900,3)
data=bpy.data.cameras.new('FleetReviewCamera'); cam=bpy.data.objects.new('FleetReviewCamera',data); studio.objects.link(cam); scene.camera=cam
cam.data.lens=56
cam.location=(6.5,-8.7,3.5); cam.rotation_euler=(Vector((0,0,.78))-cam.location).to_track_quat('-Z','Y').to_euler()
for key,objects in fleet.items():
    for ob in geo.objects: ob.hide_render=ob not in objects
    scene.render.filepath=str(REVIEW/(key+'_front.png')); bpy.ops.render.render(write_still=True)
    cam.location=(-6.2,8.2,3.1); cam.rotation_euler=(Vector((0,0,.85))-cam.location).to_track_quat('-Z','Y').to_euler()
    scene.render.filepath=str(REVIEW/(key+'_rear.png')); bpy.ops.render.render(write_still=True)
    cam.location=(6.5,-8.7,3.5); cam.rotation_euler=(Vector((0,0,.78))-cam.location).to_track_quat('-Z','Y').to_euler()
for ob in geo.objects: ob.hide_render=False
for i,(key,objects) in enumerate(fleet.items()):
    for ob in objects: ob.location.x+=(i-1)*3.1
    # Shift the live boolean references with the matching editable car.
    for ob in cutters.objects:
        if key in ob.name: ob.location.x+=(i-1)*3.1
cam.location=(10,-13,7); cam.data.lens=46
cam.rotation_euler=(Vector((0,0,.6))-cam.location).to_track_quat('-Z','Y').to_euler()
scene.render.filepath=str(REVIEW/'fleet.png'); bpy.ops.render.render(write_still=True)
reports['total_lod0_triangles']=total
reports['authorship']='Original procedural topology and editable live modifiers. No vendor car meshes.'
reports['shader_policy']='glTF metallic-roughness; opaque dark reflective glass, no Blender-only shader nodes.'
(REVIEW/'vehicle_asset_report.json').write_text(json.dumps(reports,indent=2),encoding='utf8')
(OUT/'manifest.json').write_text(json.dumps(reports,indent=2),encoding='utf8')
bpy.ops.wm.save_as_mainfile(filepath=str(ART/'RoadVehicles.blend'))
print('VEHICLE_AUTHORING_COMPLETE',total,flush=True)
