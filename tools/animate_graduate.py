"""Author full-body walk/run variants and baked, looping garment corrections.

Input: art/Graduate/Male_Graduate.blend. Output contains two playable scenes.
Motion foundation: the user's Quaternius CC0 character actions; tailored here.
No handlers, drivers, external caches or executable scripts are needed to play.
"""
import bpy, math, json
from pathlib import Path
from mathutils import Vector, Matrix, Quaternion, Euler
from mathutils.geometry import closest_point_on_tri, barycentric_transform

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'art'/'Graduate'
ANIM=OUT/'animation'
ANIM.mkdir(exist_ok=True)
SOURCE=bpy.context.scene
SOURCE.name='01_WALK - Full Body'
for obj in SOURCE.objects: obj['graduate_role']=obj.name
if bpy.context.window: bpy.context.window.scene=SOURCE
bpy.ops.scene.new(type='FULL_COPY')
RUN=bpy.context.scene
RUN.name='02_RUN - Full Body'
CONFIGS=[(SOURCE,'Walk',36,'Man_Walk'),(RUN,'Run',24,'Man_Run')]
reports=[]

def role(scene,name):
    return next(o for o in scene.objects if o.get('graduate_role')==name)

def curves(action):
    result=[]
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags: result.extend(bag.fcurves)
    return result

def source_pose(rig,scene,action,frame):
    for b in rig.pose.bones: b.matrix_basis=Matrix.Identity(4)
    rig.animation_data.action=action
    if action.slots: rig.animation_data.action_slot=action.slots[0]
    whole=math.floor(frame)
    scene.frame_set(whole,subframe=frame-whole)
    bpy.context.view_layer.update()
    return {b.name:(b.location.copy(),b.rotation_quaternion.copy(),b.scale.copy()) for b in rig.pose.bones}

def add_rotation(values,name,x=0,y=0,z=0):
    loc,quat,scale=values[name]
    values[name]=(loc,(quat@Euler((x,y,z),'XYZ').to_quaternion()).normalized(),scale)

def build_motion(scene,label,period,source_name):
    rig=role(scene,'HumanArmature')
    rig.hide_set(False)
    original=bpy.data.actions[source_name]
    start,end=original.frame_range
    contact=8 if label=='Walk' else 15
    sampled=[source_pose(rig,scene,original,start+((contact-start+(end-start)*i/period)%(end-start))) for i in range(period)]
    middle={name:sampled[0][name][1].slerp(sampled[period//2][name][1],.5) for name in sampled[0]}
    isrun=label=='Run'
    authored=[]
    for i,base in enumerate(sampled):
        p=math.tau*i/period
        vals={name:tuple(v.copy() for v in value) for name,value in base.items()}
        loc,q,s=vals['Body']
        loc.x+=(.012 if isrun else .022)*math.sin(p)
        # Y is the rig's up axis in Body-local coordinates.
        loc.y+=.008*math.sin(2*p-.3)
        twist=math.radians(3 if isrun else 1.4)*math.cos(p)
        add_rotation(vals,'Body',y=-twist,z=-math.radians(.8)*math.sin(p))
        add_rotation(vals,'Torso',y=twist*(.50 if isrun else .85))
        if isrun:
            add_rotation(vals,'Abdomen',x=math.radians(2.5))
            chest_y=base['Torso'][1].to_euler('XYZ').y
            add_rotation(vals,'Neck',x=-math.radians(1.3),y=-.25*chest_y)
            add_rotation(vals,'Head',x=math.radians(.8)*math.sin(2*p-.35)-math.radians(1.2),y=-.22*chest_y)
        else:
            add_rotation(vals,'Head',x=math.radians(.4)*math.sin(2*p-.3),y=-twist*.25)
        for side,sign in [('L',1),('R',-1)]:
            # Foot controls drive the existing 2-bone IK chains.
            foot=vals['Foot.'+side][0]
            foot.y*=.80 if isrun else .83
            if isrun: foot.z*=.90
            for name in ['UpperArm.'+side,'LowerArm.'+side]:
                loc,q,scale=vals[name]
                if isrun: q=middle[name].slerp(q,.76)
                vals[name]=(loc,q,scale)
            add_rotation(vals,'Shoulder.'+side,z=math.radians(1.4 if isrun else .8)*math.sin(p-.18))
            add_rotation(vals,'Palm.'+side,y=sign*math.radians(3 if isrun else 2)*math.sin(p-.32))
        authored.append(vals)
    action=bpy.data.actions.new('Graduate_'+label+'_FullBody')
    action.use_fake_user=True
    rig.animation_data.action=action
    previous={}
    for i,values in enumerate(authored+[authored[0]]):
        frame=i+1
        for name,(loc,q,scale) in values.items():
            b=rig.pose.bones[name]
            b.rotation_mode='QUATERNION'
            q=q.copy()
            if name in previous and q.dot(previous[name])<0: q.negate()
            previous[name]=q.copy()
            b.location=loc; b.rotation_quaternion=q; b.scale=scale
            b.keyframe_insert('location',frame=frame,group=name)
            b.keyframe_insert('rotation_quaternion',frame=frame,group=name)
            b.keyframe_insert('scale',frame=frame,group=name)
    for fc in curves(action):
        for k in fc.keyframe_points: k.interpolation='LINEAR'
        fc.modifiers.new('CYCLES')
    scene.frame_start=1;scene.frame_end=period
    scene.render.fps=30;scene.render.fps_base=1
    scene.frame_set(1)
    action['description']='Tailored full-body '+label.lower()+' with coordinated pelvis, spine, shoulders, arms, wrists and stabilized head.'
    action['source']='Adapted from Quaternius '+source_name+' (CC0)'
    action['loop']='Frames 1-'+str(period)+'; frame '+str(period+1)+' duplicates frame 1.'
    return rig,action

def skin_matrix(obj,vertex,rig):
    matrices=[];total=0
    for group in vertex.groups:
        bone_name=obj.vertex_groups[group.group].name
        bone=rig.pose.bones.get(bone_name)
        if bone and bone.bone.use_deform and group.weight>0:
            matrices.append((bone.matrix@bone.bone.matrix_local.inverted(),group.weight))
            total+=group.weight
    if not matrices: return Matrix.Identity(4)
    result=Matrix([[0.0]*4 for _ in range(4)])
    for mat,weight in matrices:
        for a in range(4):
            for b in range(4): result[a][b]+=mat[a][b]*weight/total
    return result

def attachment_map(obj,gown):
    """Rest-space barycentric anchors let the stole stay above moving cloth."""
    gown.data.calc_loop_triangles()
    triangles=[tuple(t.vertices) for t in gown.data.loop_triangles]
    gv=[v.co.copy() for v in gown.data.vertices]
    anchors={}
    for v in obj.data.vertices:
        if v.co.z>3.81: continue
        best=None
        for ids in triangles:
            a,b,c=[gv[j] for j in ids]
            point=closest_point_on_tri(v.co,a,b,c)
            distance=(point-v.co).length_squared
            if best is None or distance<best[0]: best=(distance,ids,point)
        _,ids,point=best
        a,b,c=[gv[j] for j in ids]
        bary=barycentric_transform(point,a,b,c,Vector((1,0,0)),Vector((0,1,0)),Vector((0,0,1)))
        normal=(b-a).cross(c-a).normalized()
        gap=max(.025,abs((v.co-point).dot(normal)))
        anchors[v.index]=(ids,bary,gap)
    return anchors

def keyed_shape(obj,label,poses,period):
    if not poses: return
    basis=[v.co.copy() for v in obj.data.vertices]
    if max((p[i]-basis[i]).length for p in poses for i in range(len(basis)))<1e-5: return
    obj.shape_key_add(name='Basis')
    for i,positions in enumerate(poses):
        key=obj.shape_key_add(name=label+'_cloth_%02d'%(i+1))
        for d,co in zip(key.data,positions): d.co=co
        f=i+1
        samples={1:0,period+1:0,max(1,f-1):0,f:1,min(period+1,f+1):0}
        if i==0: samples.update({1:1,2:0,period:0,period+1:1})
        if i==period-1: samples.update({1:0,period-1:0,period:1,period+1:0})
        for frame,value in sorted(samples.items()):
            key.value=value;key.keyframe_insert('value',frame=frame)
    action=obj.data.shape_keys.animation_data.action
    action.name='Graduate_'+label+'_'+obj.get('graduate_role',obj.name).split('|')[-1].strip()
    action.use_fake_user=True
    for fc in curves(action):
        for k in fc.keyframe_points: k.interpolation='LINEAR'
        fc.modifiers.new('CYCLES')

def bake_clothing(scene,rig,label,period):
    gown=role(scene,'01 | Pleated bachelor gown')
    body=role(scene,'Graduate | original face, hands and trousers')
    stoles=[o for o in scene.objects if ('Blue and gold stole' in o.get('graduate_role','') or 'Stole woven bar' in o.get('graduate_role',''))]
    tassels=[o for o in scene.objects if any(s in o.get('graduate_role','') for s in ['Gold tassel cord','Tassel knot','Tassel strand'])]
    targets=[gown]+stoles+tassels
    samples={o:[] for o in targets}
    anchors={o:attachment_map(o,gown) for o in stoles}
    rest={o:[v.co.copy() for v in o.data.vertices] for o in targets}
    leg_indices=[v.index for v in body.data.vertices if v.co.z<2.42]
    isrun=label=='Run'
    rows=[(.62,.73,.48,.51),(.70,.726,.476,.507),(1.30,.69,.45,.49),(2.15,.61,.42,.46)]
    for frame in range(1,period+1):
        scene.frame_set(frame);bpy.context.view_layer.update()
        p=math.tau*(frame-1)/period
        dg=bpy.context.evaluated_depsgraph_get()
        ev=body.evaluated_get(dg);mesh=ev.to_mesh()
        hips=rig.pose.bones['Hips']
        pelvis=hips.matrix@hips.bone.matrix_local.inverted()
        inv_pelvis=pelvis.inverted()
        leg_points=[inv_pelvis@mesh.vertices[i].co for i in leg_indices]
        ev.to_mesh_clear()
        gm=[skin_matrix(gown,v,rig) for v in gown.data.vertices]
        world=[m@v for m,v in zip(gm,rest[gown])]
        # Use one continuous lower-skirt envelope. Independent height bands made
        # a knee bulge and a narrow hem; a hanging gown should flare smoothly.
        envelope_front=.48;envelope_back=.51
        for co in leg_points:
            factor=math.sqrt(max(.28,1-(co.x/.755)**2))
            if co.y<0:envelope_front=max(envelope_front,(-co.y+.13)/factor)
            else:envelope_back=max(envelope_back,(co.y+.13)/factor)
        envelope_front=min(envelope_front,1.75 if isrun else 1.48)
        envelope_back=min(envelope_back,1.95 if isrun else 1.55)
        for row,(z,rx,front,back) in enumerate(rows):
            factor=[1.03,1.02,.98,.38][row]
            required_front=max(front,envelope_front*factor)
            required_back=max(back,envelope_back*factor)
            for i in range(48):
                idx=row*48+i;a=math.tau*i/48
                v=rest[gown][idx]
                sine=math.sin(a)
                ry=required_back if sine>=0 else required_front
                flutter=(.024 if isrun else .012)*math.sin(2*p-.5+2*a)*(1-row/4)
                lift=[.16,.16,.05,0][row]
                local=Vector((v.x*(1+flutter),sine*ry*(1+.015*math.cos(12*a)),v.z+lift+(.045 if isrun else .018)*math.sin(2*p-.45+a)*(1-row/4)))
                desired=pelvis@local
                blend=.22 if row==3 else 1.0
                world[idx]=world[idx].lerp(desired,blend)
        samples[gown].append([m.inverted_safe()@co for m,co in zip(gm,world)])
        for obj in stoles:
            positions=[]
            for v in obj.data.vertices:
                mat=skin_matrix(obj,v,rig)
                if v.index not in anchors[obj]: positions.append(v.co.copy());continue
                ids,bary,gap=anchors[obj][v.index]
                a,b,c=[world[j] for j in ids]
                normal=(b-a).cross(c-a).normalized()
                point=a*bary.x+b*bary.y+c*bary.z
                ripple=.007*math.sin(2*p-.65+v.co.z)*max(0,(3-v.co.z)/1.4)
                positions.append(mat.inverted_safe()@(point+normal*(gap+ripple)))
            samples[obj].append(positions)
        for obj in tassels:
            positions=[]
            pivot=Vector((.65,.04,4.96))
            for v in rest[obj]:
                drop=min(1,max(0,(4.98-v.z)/.18))
                q=Euler(((.22 if isrun else .10)*math.sin(p-.55)*drop,
                         (.14 if isrun else .065)*math.sin(2*p-.8)*drop,0)).to_quaternion()
                positions.append(pivot+q@(v-pivot))
            samples[obj].append(positions)
    for obj,poses in samples.items(): keyed_shape(obj,label,poses,period)
    return targets

def configure(scene,label,period,rig):
    camera=role(scene,'Camera | graduate portrait')
    scene.camera=camera
    camera.location=(8,-16,7)
    camera.rotation_euler=(Vector((0,0,2.45))-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.ortho_scale=6.25
    scene.render.resolution_x=480;scene.render.resolution_y=600
    scene.cycles.samples=8;scene.cycles.device='CPU';scene.cycles.use_denoising=True
    scene.render.threads_mode='FIXED';scene.render.threads=4
    scene.render.filepath=str(ANIM/(label.lower()+'_frames')/'frame_')
    scene.timeline_markers.clear()
    for name,frame in [('LEFT CONTACT',1),('MID STEP',period//4+1),('RIGHT CONTACT',20 if label=='Walk' else 14),('MID STEP',3*period//4+1)]:
        scene.timeline_markers.new(name,frame=frame)
    scene['Clip']=label+' in place | Full body | 30 fps | loop '+str(period)+' frames'
    scene['Cloth']='Baked per-frame skirt clearance, surface-attached stole and lagged tassel; no external cloth cache.'
    scene['Playback']='Press Space. Choose the other scene from the top scene menu for the other gait.'
    scene.frame_start=1;scene.frame_end=period;scene.frame_set(1)
    rig.hide_set(True)

for scene,label,period,source_name in CONFIGS:
    bpy.context.window.scene=scene
    rig,action=build_motion(scene,label,period,source_name)
    targets=bake_clothing(scene,rig,label,period)
    configure(scene,label,period,rig)
    reports.append({'scene':scene.name,'action':action.name,'frames':period,'fps':30,'duration':period/30,
                    'animated_bones':len(rig.pose.bones),'cloth_objects':len(targets)})
    print('CLIP_BUILT',json.dumps(reports[-1]),flush=True)

for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            space=area.spaces.active
            space.shading.type='SOLID';space.shading.color_type='MATERIAL'
            space.shading.show_cavity=False
            space.shading.show_shadows=True
            space.shading.light='STUDIO';space.shading.studio_light='paint.sl'
            space.overlay.show_overlays=False
            space.region_3d.view_distance=7.7;space.region_3d.view_location=(0,0,2.45)
            space.region_3d.view_rotation=(Vector((7,-17,7))-Vector((0,0,2.45))).to_track_quat('Z','Y')
            space.region_3d.view_perspective='ORTHO'
bpy.context.window.scene=SOURCE
SOURCE.frame_set(1)
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'Male_Graduate_Animated.blend'))
(ANIM/'clips.json').write_text(json.dumps(reports,indent=2),encoding='utf-8')
print('ANIMATION_READY',str(OUT/'Male_Graduate_Animated.blend'),flush=True)
