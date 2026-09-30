"""Sewn, closed upholstery surfaces for the reference black-leather sectional.

The soft forms are modeled meshes: inflated face panels, side gussets, irregular
edge compression, seat depressions, and pulled pillow corners. No subdivision
of a bevelled cube is used for the exposed upholstery.
"""
import bpy, bmesh, math, random
from mathutils import Vector


def refine_upholstery(collection, materials):
    created=[]
    corner_source=next(o for o in collection.objects if o.name=='LOUNGE_Left_back_cushion_02')
    corner=corner_source.copy();corner.data=corner_source.data.copy()
    corner.name='LOUNGE_Corner_left_back_cushion_3';corner.location.y=-4.18
    collection.objects.link(corner);created.append(corner)
    cord=materials['black']
    thread=bpy.data.materials.new('MAT | dark leather saddle stitching')
    thread.diffuse_color=(.046,.052,.063,1);thread.use_nodes=True
    p=thread.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value=(.046,.052,.063,1);p.inputs['Roughness'].default_value=.7

    def curve(name,paths,radius,material,source,cyclic=False):
        data=bpy.data.curves.new(name,'CURVE');data.dimensions='3D';data.bevel_depth=radius;data.bevel_resolution=1;data.resolution_u=1
        for path in paths:
            sp=data.splines.new('POLY');sp.points.add(len(path)-1)
            for q,co in zip(sp.points,path):q.co=(*co,1)
            sp.use_cyclic_u=cyclic
        obj=bpy.data.objects.new(name,data);collection.objects.link(obj);data.materials.append(material)
        obj.location=source.location;obj.rotation_euler=source.rotation_euler;created.append(obj)
        return obj

    def soft_surface(obj,size,seed,loose=False,shell=False):
        thin=min(range(3),key=lambda a:size[a]); plane=[a for a in range(3) if a!=thin]
        half=[s*.5 for s in size]; n=52 if loose else (28 if shell else 40)
        exponent=4.1 if loose else 6.3
        rng=random.Random(seed)
        wrinkles=[]
        for axis in [0,1]:
            for sign in [-1,1]:
                for k in range(5 if loose else 4):
                    wrinkles.append((axis,sign,rng.uniform(-.78,.78),rng.uniform(-.72,.72),rng.uniform(.024,.045),rng.uniform(.002,.006)*(1.65 if loose else 1)))

        def rounded(u,v):
            m=max(abs(u),abs(v))
            den=(abs(u)**exponent+abs(v)**exponent)**(1/exponent)
            f=m/den if den else 1
            return u*f,v*f

        def point(u,v,side):
            ru,rv=rounded(u,v)
            puff=(max(0,1-u*u)*max(0,1-v*v))**.63
            normal=half[thin]*(.69+.31*puff)
            # Slight seat loading, uneven stuffing and tailored edge compressions.
            if not shell:
                normal-=.009*math.exp(-((u-.12)**2/.24+(v+.09)**2/.33))
                normal+=.004*math.sin(3*u+seed*.7)*math.cos(2.7*v+.4)*puff
                for ax,sg,center,slope,width,depth in wrinkles:
                    edge=1-(u if ax==0 else v)*sg
                    along=(v if ax==0 else u)-center+slope*edge
                    if 0<=edge<.62:
                        crease=math.exp(-(along/width)**2)*math.exp(-edge/(.22 if loose else .13))
                        ridge=math.exp(-((along-width*1.6)/(width*.85))**2)*math.exp(-edge/.17)
                        normal-=depth*crease;normal+=depth*.40*ridge
            if loose:
                normal-=.010*math.exp(-((u+.55*v-.16)/.11)**2)*math.exp(-((v-.65)/.37)**2)
                normal+=.009*math.sin(u*2.4+v*1.8+seed)*puff
            co=[0,0,0];co[plane[0]]=ru*half[plane[0]];co[plane[1]]=rv*half[plane[1]];co[thin]=side*normal
            # Back cushions and arms have a subtle asymmetric slump.
            if thin!=2:
                co[2]+= .009*math.sin(ru*3.2+seed*.6)*(1-rv*rv)
            return tuple(co)

        vs=[];fs=[];ids=[]
        for side in [1,-1]:
            grid=[]
            for j in range(n+1):
                row=[]
                for i in range(n+1):row.append(len(vs));vs.append(point(-1+2*i/n,-1+2*j/n,side))
                grid.append(row)
            ids.append(grid)
            for j in range(n):
                for i in range(n):fs.append((grid[j][i],grid[j][i+1],grid[j+1][i+1],grid[j+1][i]))
        def boundary(g):
            return g[0][:-1]+[g[j][n] for j in range(n)]+list(reversed(g[n][1:]))+[g[j][0] for j in range(n,0,-1)]
        top=boundary(ids[0]);bot=boundary(ids[1]);rings=[top]
        for t in [.2,.4,.6,.8]:
            row=[]
            for a,b in zip(top,bot):
                q=Vector(vs[a]).lerp(Vector(vs[b]),t)
                bulge=1+.025*math.sin(math.pi*t)
                q[plane[0]]*=bulge;q[plane[1]]*=bulge
                row.append(len(vs));vs.append(tuple(q))
            rings.append(row)
        rings.append(bot)
        for row1,row2 in zip(rings[:-1],rings[1:]):
            for i in range(len(top)):
                j=(i+1)%len(top);fs.append((row1[i],row1[j],row2[j],row2[i]))
        data=bpy.data.meshes.new(obj.name+' | sewn upholstery surface')
        data.from_pydata(vs,[],fs);data.update()
        bm=bmesh.new();bm.from_mesh(data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(data);bm.free()
        for face in data.polygons:face.use_smooth=True
        data.materials.append(materials['leather']);obj.data=data
        for mod in list(obj.modifiers):obj.modifiers.remove(mod)
        obj['upholstered']=True;obj['surface_model']='inflated sewn panels + modeled edge wrinkles + side gusset'
        # Sewn welting follows the actual shaped face edge; no bright chrome outline.
        path=[vs[i] for i in top]
        curve(obj.name+' | leather welt',[path],.0018,cord,obj,True)
        if not shell:
            stitches=[]
            for i in range(0,len(path),2):
                a=Vector(path[i]);b=Vector(path[(i+1)%len(path)])
                a[thin]+=.0008;b[thin]+=.0008
                q=a.lerp(b,.16);r=a.lerp(b,.53)
                stitches.append([tuple(q),tuple(r)])
            curve(obj.name+' | saddle stitches',stitches,.00068,thread,obj)

    # Delete the old, rigid-looking metallic piping; use shaped leather seams.
    for obj in list(collection.objects):
        if 'piping' in obj.name.lower() or obj.name.startswith('LOUNGE_Rug_weave'):bpy.data.objects.remove(obj,do_unlink=True)
    for obj in list(collection.objects):
        name=obj.name
        if any(s in name for s in ['Left_seat_','Return_seat_','Corner_seat','back_cushion_','Corner_back','Loose_pillow_','Left_end_arm','Return_end_arm','Left_back_shell','Return_back_shell']):
            coords=[v.co for v in obj.data.vertices]
            dims=tuple(max(v[a] for v in coords)-min(v[a] for v in coords) for a in range(3))
            soft_surface(obj,dims,sum(ord(c) for c in name),'Loose_pillow' in name,'shell' in name)

    # A third loose pillow is different in proportion, tilt and compression.
    data=bpy.data.meshes.new('LOUNGE | third throw pillow source')
    obj=bpy.data.objects.new('LOUNGE_Loose_pillow_C',data);collection.objects.link(obj)
    obj.location=(-5.78,-3.54,.68);obj.rotation_euler=(math.radians(-8),math.radians(-20),math.radians(-17));created.append(obj)
    soft_surface(obj,(.24,.47,.45),71,True)
    # Short, individually bent carpet tufts replace the old rigid stripe marks.
    tufts=[];rng=random.Random(20260927)
    for i in range(4200):
        x=rng.uniform(-6.56,-2.04);y=rng.uniform(-5.08,-1.32);h=rng.uniform(.010,.028)
        dx=rng.uniform(-.009,.009);dy=rng.uniform(-.009,.009)
        tufts.append([(x,y,.032),(x+dx*.45,y+dy*.45,.032+h*.65),(x+dx,y+dy,.032+h),(x+dx*1.2,y+dy*1.2,.032+h*.82)])
    data=bpy.data.curves.new('LOUNGE | short irregular carpet pile','CURVE');data.dimensions='3D';data.bevel_depth=.0013;data.bevel_resolution=0;data.resolution_u=1
    for path in tufts:
        sp=data.splines.new('POLY');sp.points.add(3)
        for q,p in zip(sp.points,path):q.co=(*p,1)
    tuft=bpy.data.objects.new('LOUNGE_Soft_carpet_pile',data);collection.objects.link(tuft);data.materials.append(materials['rug']);created.append(tuft)
    return created
