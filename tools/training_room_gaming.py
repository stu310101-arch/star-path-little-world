"""Contoured racing-chair and workstation detail pass, in original zone units."""
import bpy, bmesh, math
from mathutils import Vector
from collections import Counter


def refine_gaming(collection, materials):
    def mesh(name,vs,fs,mat):
        d=bpy.data.meshes.new(name);d.from_pydata(vs,[],fs);d.update()
        bm=bmesh.new();bm.from_mesh(d)
        loose=[v for v in bm.verts if not v.link_edges]
        if loose:bmesh.ops.delete(bm,geom=loose,context='VERTS')
        bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(d);bm.free()
        for p in d.polygons:p.use_smooth=True
        o=bpy.data.objects.new(name,d);collection.objects.link(o);d.materials.append(materials[mat]);return o
    def line(name,paths,mat,r=.006,closed=False):
        d=bpy.data.curves.new(name,'CURVE');d.dimensions='3D';d.bevel_depth=r;d.bevel_resolution=2
        for path in paths:
            s=d.splines.new('POLY');s.points.add(len(path)-1)
            for q,p in zip(s.points,path):q.co=(*p,1)
            s.use_cyclic_u=closed
        o=bpy.data.objects.new(name,d);collection.objects.link(o);d.materials.append(materials[mat]);return o
    def signed(v,p):return math.copysign(abs(v)**p,v)
    def pillow(name,loc,dims,exponent=.46):
        vs=[(loc[0],loc[1],loc[2]-dims[2]/2)];rings=[];n=48
        for j in range(1,24):
            lat=-math.pi/2+math.pi*j/24;ring=[]
            for i in range(n):
                a=i*math.tau/n
                x=dims[0]/2*signed(math.cos(lat),exponent)*signed(math.cos(a),exponent)
                y=dims[1]/2*signed(math.cos(lat),exponent)*signed(math.sin(a),exponent)
                z=dims[2]/2*signed(math.sin(lat),.57)
                if z>0:z-=.009*math.exp(-((x/(dims[0]*.30))**2+(y/(dims[1]*.33))**2))
                ring.append(len(vs));vs.append((loc[0]+x,loc[1]+y,loc[2]+z))
            rings.append(ring)
        top=len(vs);vs.append((loc[0],loc[1],loc[2]+dims[2]/2-.009))
        fs=[]
        for i in range(n):fs.append((0,rings[0][(i+1)%n],rings[0][i]));fs.append((top,rings[-1][i],rings[-1][(i+1)%n]))
        for a,b in zip(rings[:-1],rings[1:]):
            for i in range(n):j=(i+1)%n;fs.append((a[i],a[j],b[j],b[i]))
        o=mesh(name,vs,fs,'leather');o['upholstered']=True;return o

    # Replace only the old task-owned upholstery and flat castor/base geometry.
    patterns=['chair cushion','chair back','headrest','chair bolster','arm pad','chair star base','chair castor']
    for o in list(collection.objects):
        if any(t in o.name for t in patterns):bpy.data.objects.remove(o,do_unlink=True)

    for station,yc in enumerate([.35,2,3.65],1):
        cx=-4.91
        marker=bpy.data.objects.new('GAMING | station %d'%station,None);collection.objects.link(marker)
        marker['gaming_station_index']=station;marker.location=(cx,yc,0);marker.empty_display_size=.04
        pillow('GAMING | shaped seat %d'%station,(cx-.07,yc,.50),(.64,.62,.16))
        # Continuous shell surface, with broad shoulder wings, lumbar support,
        # narrowed neck, and two real through-openings for a racing harness.
        def width(z):
            stops=[(.59,.245),(.78,.235),(1.05,.29),(1.16,.29),(1.29,.195),(1.51,.185)]
            for (a,u),(b,v) in zip(stops[:-1],stops[1:]):
                if a<=z<=b:return u+(v-u)*(z-a)/(b-a)
            return stops[-1][1]
        def surface(u,z,back=False):
            w=width(z);x=cx+.25+.085*(z-.62)-.08*math.exp(-((z-.82)/.18)**2)-.075*abs(u)**3
            if back:x+=.062
            return (x,yc+u*w,z)
        nu=32;nz=48;vs=[]
        for back in [False,True]:
            for j in range(nz+1):
                z=.59+.92*j/nz
                for i in range(nu+1):vs.append(surface(-1+2*i/nu,z,back))
        count=(nu+1)*(nz+1);fs=[];front_edges=[]
        for j in range(nz):
            for i in range(nu):
                z=.59+.92*(j+.5)/nz;u=-1+2*(i+.5)/nu;yy=u*width(z)
                if any(((yy-h)/.044)**2+((z-1.29)/.059)**2<1 for h in [-.09,.09]):continue
                a=j*(nu+1)+i;q=(a,a+1,a+nu+2,a+nu+1)
                fs.append(q);fs.append(tuple(x+count for x in reversed(q)))
                front_edges.extend((q[k],q[(k+1)%4]) for k in range(4))
        counts=Counter(tuple(sorted(e)) for e in front_edges)
        for a,b in front_edges:
            if counts[tuple(sorted((a,b)))]==1:fs.append((a,b,b+count,a+count))
        shell=mesh('GAMING | sculpted racing shell %d'%station,vs,fs,'leather');shell['upholstered']=True;shell['true_harness_openings']=2
        bevel=shell.modifiers.new('Soft harness opening edges','BEVEL');bevel.width=.004;bevel.segments=2;bevel.limit_method='ANGLE'
        # Separate stitched wing upholstery emphasizes the shaped shell.
        for side in [-1,1]:
            path=[surface(side*.91,.62+.84*j/32) for j in range(33)]
            line('GAMING | wing seam %d'%station,[path],'seam',.0025)
            outline=[surface(side*.53,.68+.47*j/20) for j in range(21)]
            line('GAMING | lumbar panel seam %d'%station,[outline],'black',.004)
            pillow('GAMING | shaped arm pad %d'%station,(cx-.065,yc+side*.36,.76),(.43,.09,.075),.52)
        # Small shaped head cushion integrated into the continuous head support.
        pillow('GAMING | soft head pad %d'%station,(cx+.20,yc,1.445),(.09,.265,.115),.56)
        seatpath=[]
        for i in range(96):
            t=i*math.tau/96
            seatpath.append((cx-.07+.30*signed(math.cos(t),.44),yc+.29*signed(math.sin(t),.44),.55))
        line('GAMING | seat sewn welt',[seatpath],'black',.0022,True)

        # Five tapered, bent metal spokes; wheels roll on horizontal axles.
        for leg in range(5):
            a=leg*math.tau/5+.22;dx,dy=math.cos(a),math.sin(a);px,py=-dy,dx
            end=Vector((cx+.375*dx,yc+.375*dy,.13))
            profile=[(.04,.225,.045),(.12,.205,.04),(.27,.153,.026),(.38,.136,.020)]
            v=[]
            for radius,z,w in profile:
                for s,h in [(-1,-.015),(1,-.015),(1,.015),(-1,.015)]:v.append((cx+radius*dx+s*w*px,yc+radius*dy+s*w*py,z+h))
            f=[(3,2,1,0),(12,13,14,15)]
            for row in range(3):
                for k in range(4):f.append((row*4+k,row*4+(k+1)%4,(row+1)*4+(k+1)%4,(row+1)*4+k))
            o=mesh('GAMING | swept alloy spoke',v,f,'metal');b=o.modifiers.new('Rounded spoke edge','BEVEL');b.width=.008;b.segments=2
            line('GAMING | caster fork',[[tuple(end),(end.x,end.y,.105)]],'metal',.022)
            for side in [-1,1]:
                center=Vector((end.x+px*.025*side,end.y+py*.025*side,.091));v=[];f=[];n=24
                axial=[(-.014,.041),(-.012,.052),(.012,.052),(.014,.041)]
                for offset,radius in axial:
                    for k in range(n):
                        t=k*math.tau/n
                        v.append(tuple(center+Vector((px,py,0))*offset+Vector((dx,dy,0))*(radius*math.cos(t))+Vector((0,0,radius*math.sin(t)))))
                for j in range(3):
                    for k in range(n):q=(k+1)%n;f.append((j*n+k,j*n+q,(j+1)*n+q,(j+1)*n+k))
                f.extend([tuple(reversed(range(n))),tuple(range(3*n,4*n))]);mesh('GAMING | twin rolling castor',v,f,'black')
        # Fan blades sit behind the circular lights in each physical tower.
        for z in [.25,.48]:
            vs=[];fs=[]
            for i in range(7):
                a=i*math.tau/7;n=len(vs)
                for r,t in [(.015,a),(.065,a+.13),(.069,a+.51),(.025,a+.38)]:vs.append((-5.813,yc+.56+r*math.cos(t),z+r*math.sin(t)))
                fs.append((n,n+1,n+2,n+3))
            mesh('GAMING | curved intake fan blades',vs,fs,'metal')
    return [o for o in collection.objects if o.get('gaming_station_index')]
