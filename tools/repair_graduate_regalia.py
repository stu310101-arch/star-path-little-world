"""Repair regalia layering on each final posed surface; preserve rig motion.

Cloth thickness is reduced to fabric scale. Stoles follow the evaluated gown,
including their neck/shoulder sections; applied gold bars follow their own
stole. All results are inverse-skinned and baked into ordinary shape keys.
Writes a separate candidate; no input file is overwritten.
"""
from pathlib import Path
import sys, json, math
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.geometry import barycentric_transform
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from simulate_portal_cloth import SCALE,SkinBinding,evaluated_points,bake_keys
from simulate_sleeve_cloth import bake_loop
from validate_sleeve_garment_contact import visible_surfaces
from regalia_neck_clearance import build_neck_collider, clear_neck
from probe_regalia_neck import local_faces
from repair_gown_sleeve_clearance import repair_clip as repair_gown_sleeves

GOWN='01 | Pleated bachelor gown'

def clear_sewn_neck(posed,faces,neck):
    unique=[];lookup={};maps={};all_faces=[]
    for obj,points in posed.items():
        mapping=[]
        for p in points:
            key=tuple(np.round(p,8))
            if key not in lookup:lookup[key]=len(unique);unique.append(p)
            mapping.append(lookup[key])
        maps[obj]=mapping
        all_faces.extend(tuple(mapping[i] for i in face) for face in faces[obj])
    unique=np.asarray(unique)
    result,report=clear_neck(unique,local_faces(unique,np.asarray(all_faces,dtype=np.int32),neck.bounds,.042),neck,margin=.004,sample_density=2)
    return {o:result[ids] for o,ids in maps.items()},report

def bar_points(parent_points, index, forward):
    # Both embroidered bars remain in distinct fixed positions on the last
    # rectangular panel, above the pointed tip. Never re-snap them to the gown.
    a,b,c,d=parent_points[[33,34,38,37]]
    center=.68 if index==0 else .38
    result=[]
    for u,v in [(.1,center-.011),(.9,center-.011),(.9,center+.011),(.1,center+.011)]:
        if u>=v:
            point=a*(1-u)+b*(u-v)+c*v;n=np.cross(b-a,c-a)
        else:
            point=a*(1-v)+c*u+d*(v-u);n=np.cross(c-a,d-a)
        n/=max(np.linalg.norm(n),1e-12)
        if np.dot(n,forward)<0:n=-n
        result.append(point+n*.0022)
    return np.asarray(result)

def continuous_back_collar(left,right,back):
    # Meet each front stole at its rear boundary rather than laying three
    # separate ribbons through the same shoulder region. Each cross-strip
    # column follows a smooth rear arc through the existing mid-neck point.
    # Preserve the ordered semicircular rear strip. Remove the redundant
    # backwards segment of each front piece by joining its first row to the
    # rear strip endpoint; row 1 continues forwards towards row 2.
    left[:4]=back[:4]
    right[:4]=back[-4:]
    left[4:8]=(left[:4]+left[8:12])*.5
    right[4:8]=(right[:4]+right[8:12])*.5
    return back

def stable_ribbon(points, side, across):
    result=points.copy()
    fractions=np.asarray([-.5,-.43,.43,.5])
    for row in range(10):
        start=4*row;center=(points[start]+points[start+3])*.5
        if row<3:
            width=points[start+3]-points[start]
        else:
            width=across*(1 if side=='L' else -1)*[.20,.195,.19,.18,.18,.18,.18][row-3]*SCALE
        result[start:start+4]=center+fractions[:,None]*width
    return result

def clear_ribbon_rows(points,faces,target,target_faces,gap=.007):
    # Translate whole cross-strip rows to keep the narrow gold borders ordered.
    # Independent per-vertex corrections can invert those tiny border faces.
    result=points.copy();tree=tree_for(target,target_faces)
    samples=[((i,),np.array([1.])) for i in range(len(result))]
    for face in faces:
        samples.append((face,np.full(3,1/3)))
        samples += [((face[i],face[(i+1)%3]),np.array([1-t,t])) for i in range(3) for t in [.25,.5,.75]]
        samples += [(face,np.asarray(w)) for w in [( .6,.2,.2),(.2,.6,.2),(.2,.2,.6)]]
    for iteration in range(24):
        deltas=np.zeros((11,3));counts=np.zeros(11);worst=0.
        for ids,weights in samples:
            point=Vector(result[list(ids)].T@weights);near,n,index,d=tree.find_nearest(point)
            signed=(point-near).dot(n)
            if d>.05 or signed>=gap:continue
            delta=np.asarray(n)*(gap-signed);worst=max(worst,gap-signed)
            for row in {i//4 for i in ids}:deltas[row]+=delta;counts[row]+=1
        if worst<.00005:break
        for row in range(11):
            if counts[row]:result[row*4:min(row*4+4,len(result))]+=deltas[row]/counts[row]
    return result

def triangles(obj):
    obj.data.calc_loop_triangles()
    result=[]
    for poly in obj.data.polygons:
        ids=tuple(poly.vertices)
        if len(ids)==4:result.extend([(ids[0],ids[1],ids[2]),(ids[0],ids[2],ids[3])])
        elif len(ids)==3:result.append(ids)
        else:result.extend(tuple(t.vertices) for t in obj.data.loop_triangles if t.polygon_index==poly.index)
    return result

def tree_for(points,faces):
    return BVHTree.FromPolygons([Vector(p) for p in points],faces,all_triangles=True)

def anchors(points,base,faces,gap,preserve_tangent):
    tree=tree_for(base,faces);result=[]
    for p in points:
        point=Vector(p);near,normal,index,distance=tree.find_nearest(point)
        ids=faces[index];a,b,c=[Vector(base[v]) for v in ids]
        n=(b-a).cross(c-a).normalized();u=(b-a).normalized();v=n.cross(u)
        bary=barycentric_transform(near,a,b,c,Vector((1,0,0)),Vector((0,1,0)),Vector((0,0,1)))
        delta=point-near
        result.append((ids,np.asarray(bary),delta.dot(u) if preserve_tangent else 0,
                       delta.dot(v) if preserve_tangent else 0,
                       max(gap,min(.015,delta.dot(n))) if preserve_tangent else gap))
    return result

def deform(links,points):
    output=[]
    for ids,bary,x,y,z in links:
        a,b,c=points[list(ids)];u=b-a;u/=max(np.linalg.norm(u),1e-12)
        n=np.cross(b-a,c-a);n/=max(np.linalg.norm(n),1e-12);v=np.cross(n,u)
        output.append(points[list(ids)].T@bary+u*x+v*y+n*z)
    return np.asarray(output)

def project_clearance(points,faces,target,target_faces,gap,iterations=6):
    """Prevent vertices, edges and triangle interiors crossing the outer layer."""
    result=points.copy();tree=tree_for(target,target_faces)
    for iteration in range(iterations):
        deltas=np.zeros_like(result);counts=np.zeros(len(result))
        samples=[((i,),np.array([1.])) for i in range(len(result))]
        for face in faces:
            samples.append((face,np.full(3,1/3)))
            samples += [((face[i],face[(i+1)%3]),np.array([.5,.5])) for i in range(3)]
        corrected=0
        for ids,weights in samples:
            p=Vector(result[list(ids)].T@weights)
            near,n,index,d=tree.find_nearest(p)
            # Boundary extensions at the upper collar are not forced onto a
            # distant surface; actual close layer contacts remain constrained.
            signed=(p-near).dot(n)
            if d>.035 or signed>=gap:continue
            delta=np.asarray(n)*(gap-signed)
            for vid,w in zip(ids,weights):
                deltas[vid]+=delta;counts[vid]+=1
            corrected+=1
        if not corrected:break
        mask=counts>0;result[mask]+=deltas[mask]/counts[mask,None]
    return result

def main():
    report={'source':bpy.data.filepath,'complete':False,'clips':{},'method':'Dynamic surface attachment, fabric-scale solidify, ordinary baked shape keys'}
    checkpoint=ROOT/'art/Graduate/Male_Graduate_Regalia_Checkpoint.blend'
    report_path=ROOT/'art/Graduate/animation/regalia-layer-repair.json'
    if bpy.data.filepath==str(checkpoint) and report_path.exists():report=json.loads(report_path.read_text(encoding='utf-8'))
    bpy.context.preferences.filepaths.save_version=0
    for scene in sorted(bpy.data.scenes,key=lambda s:s.name):
        if not scene.name.startswith(('01_WALK','02_RUN','03_JUMP','04_IDLE')):continue
        if scene.get('regalia_repair_stage')=='done':continue
        bpy.context.window.scene=scene
        roles={o.get('graduate_role'):o for o in scene.objects if o.type=='MESH' and o.get('graduate_role') and not o.get('preview_fx')}
        gown=roles[GOWN];rig=next(o for o in scene.objects if o.type=='ARMATURE')
        body=roles['Graduate | original face, hands and trousers']
        stoles=[o for r,o in roles.items() if r.startswith('03 |')]
        bars=[o for r,o in roles.items() if r.startswith('04 |')]
        for role,obj in roles.items():
            thickness=.0015 if role==GOWN else .0011 if 'Bell sleeve' in role else .0008 if role.startswith('03 |') else None
            if thickness is not None:
                for m in obj.modifiers:
                    if m.type=='SOLIDIFY':m.thickness=thickness/SCALE;m.offset=0
            solids=[m for m in obj.modifiers if m.type=='SOLIDIFY']
            if solids:
                tri=obj.modifiers.get('Regalia stable cloth triangles') or obj.modifiers.new('Regalia stable cloth triangles','TRIANGULATE')
                tri.quad_method='FIXED';tri.ngon_method='CLIP'
                obj.modifiers.move(list(obj.modifiers).index(tri),list(obj.modifiers).index(solids[0]))
        clip=next(label for prefix,label in {'01_WALK':'walk','02_RUN':'run','03_JUMP':'jump','04_IDLE':'idle'}.items() if scene.name.startswith(prefix))
        seams={p.index for p in gown.data.polygons if p.center.z>3.8 and abs(p.center.x)>.34}
        constraint_seams={p.index for p in gown.data.polygons if p.center.z>3.05 and abs(p.center.x)>.34}
        sleeve_path=ROOT/f'art/Graduate/animation/gown-clearance-final-{clip}.json'
        if scene.get('regalia_repair_stage')=='sleeves':sleeve_report=json.loads(sleeve_path.read_text(encoding='utf-8'))
        else:
            sleeve_report=repair_gown_sleeves(clip,report_path=str(sleeve_path),bake=True,
                iterations=60,clearance=.0025,maximum_displacement=.12,maximum_step=.005,seam_faces=seams,constraint_seam_faces=constraint_seams,smooth_strength=.05,
                warm_start=True,warm_start_iterations=12,check_every=8,warm_smooth_strength=.05)
            scene['regalia_repair_stage']='sleeves'
            report_path.write_text(json.dumps(report,indent=2),encoding='utf-8')
            bpy.ops.wm.save_as_mainfile(filepath=str(checkpoint))
        shirts=[o for r,o in roles.items() if r.startswith('05 |')]
        period=scene.frame_end
        with visible_surfaces(scene,[gown,body],'simulation'):
            binding=SkinBinding(gown,rig);gown_samples=[];neck_reports=[]
            for frame in range(1,period+1):
                scene.frame_set(frame);bpy.context.view_layer.update()
                neck=build_neck_collider(body)
                original=evaluated_points(gown)
                points,entry=clear_neck(original,local_faces(original,np.asarray(triangles(gown),dtype=np.int32),neck.bounds,.055),neck,margin=.004,allow_neckline_reshape=True,support_radius=.055,max_correction=.025,iterations=24)
                gown_samples.append(binding.inverse_points(points))
                neck_reports.append({'frame':frame,'gown':entry['after'],'max_shift':entry['maximum_vertex_shift_m']})
            if scene.name.startswith('03_JUMP'):bake_keys(gown,gown_samples,1,'Gown neck clearance')
            else:bake_loop(gown,gown_samples,'Gown neck clearance')
        objects=[gown,*stoles,*bars,*shirts,body]
        bindings={o:SkinBinding(o,rig) for o in stoles+bars+shirts}
        samples={o:[] for o in stoles+bars+shirts};maximum={o.name:0. for o in stoles+bars+shirts}
        with visible_surfaces(scene,objects,'simulation'):
            scene.frame_set(1);bpy.context.view_layer.update()
            base={o:evaluated_points(o) for o in objects}
            faces={o:triangles(o) for o in objects}
            links={o:anchors(base[o],base[gown],faces[gown],.0045,True) for o in stoles}
            initial={o:project_clearance(deform(links[o],base[gown]),faces[o],base[gown],faces[gown],.0045) for o in stoles}
            parents={}
            for bar in bars:
                side=bar.get('graduate_role').rsplit(' ',1)[1][0]
                parent=next(o for o in stoles if o.get('graduate_role').endswith(' '+side))
                parents[bar]=parent
            for frame in range(1,period+1):
                scene.frame_set(frame);bpy.context.view_layer.update()
                target=evaluated_points(gown);posed={}
                torso=rig.pose.bones['Torso']
                torso_basis=rig.matrix_world.to_3x3()@torso.matrix.to_3x3()@torso.bone.matrix_local.to_3x3().inverted()
                across=np.asarray((torso_basis@Vector((1,0,0))).normalized())
                for obj in stoles:
                    points=deform(links[obj],target)
                    if obj.get('graduate_role').endswith((' L',' R')):
                        points=stable_ribbon(points,obj.get('graduate_role')[-1],across)
                        posed[obj]=clear_ribbon_rows(points,faces[obj],target,faces[gown])
                    else:posed[obj]=project_clearance(points,faces[obj],target,faces[gown],.0045)
                back=next(o for o in stoles if 'back collar' in o.get('graduate_role'))
                left=next(o for o in stoles if o.get('graduate_role').endswith(' L'))
                right=next(o for o in stoles if o.get('graduate_role').endswith(' R'))
                posed[back]=continuous_back_collar(posed[left],posed[right],posed[back])
                neck=build_neck_collider(body)
                for obj in shirts:posed[obj]=evaluated_points(obj)
                posed,neck_entry=clear_sewn_neck(posed,faces,neck)
                neck_reports[frame-1]['layers']=neck_entry['after']
                for obj in bars:
                    parent=parents[obj]
                    torso=rig.pose.bones['Torso']
                    forward=rig.matrix_world.to_3x3()@torso.matrix.to_3x3()@torso.bone.matrix_local.to_3x3().inverted()@Vector((0,-1,0))
                    posed[obj]=bar_points(posed[parent],int(obj.get('graduate_role')[-1]),np.asarray(forward.normalized()))
                for obj,points in posed.items():
                    maximum[obj.name]=max(maximum[obj.name],float(np.linalg.norm(points-evaluated_points(obj),axis=1).max()))
                    samples[obj].append(np.asarray(bindings[obj].inverse_points(points)))
                if frame%20==0:print('REGALIA_LAYER_BAKE',scene.name,frame,flush=True)
            for obj in stoles+bars+shirts:
                label='Regalia_LayerClearance_'+obj.get('graduate_role')
                if scene.name.startswith('03_JUMP'):bake_keys(obj,samples[obj],1,label)
                else:bake_loop(obj,samples[obj],label)
        report['clips'][scene.name]={'frames':period,'max_vertex_correction_m':maximum,'stoles':[o.get('graduate_role') for o in stoles],'bars':[o.get('graduate_role') for o in bars],'neck':neck_reports,'gown_sleeve_free_crossings':sleeve_report['remaining_free_midsurface_crossings']}
        if scene.name.startswith('04_IDLE'):
            scene.render.fps=56;scene.render.fps_base=1
            scene['Animation']='Breathing at 56 fps; 120 samples / 56 = 15/7 seconds. Garment surface clearance repaired.'
            scene['Loop']='1-120 at 56fps; 121 repeats 1. Body amplitude preserved.'
        scene.frame_set(1)
        scene['regalia_repair_stage']='done'
        report_path.write_text(json.dumps(report,indent=2),encoding='utf-8')
        bpy.ops.wm.save_as_mainfile(filepath=str(checkpoint))
        print('REGALIA_LAYER_CLIP_DONE',scene.name,flush=True)
    scene=next(s for s in bpy.data.scenes if s.name.startswith('04_IDLE'));bpy.context.window.scene=scene
    text=bpy.data.texts.get('IDLE - Readable breathing')
    if text:
        text.clear();text.write('待機呼吸：120 幀／56 fps，約 2.14 秒循環。\n相對三秒版頻率再快 40%，保留呼吸幅度。\n披帶及裝飾改為跟隨最終衣料表面。\n')
    output=ROOT/'art/Graduate/Male_Graduate_Regalia_Layers_Candidate.blend'
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(output))
    report['complete']=True
    (ROOT/'art/Graduate/animation/regalia-layer-repair.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print('REGALIA_LAYER_CANDIDATE',str(output),flush=True)

if __name__=='__main__':main()
