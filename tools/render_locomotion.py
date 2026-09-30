import bpy,json,math,os,sys
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'art'/'Graduate'/'animation'
report={'clips':[]}
for scene in bpy.data.scenes:
    if not scene.name.startswith(('01_WALK','02_RUN')):continue
    bpy.context.window.scene=scene
    label='walk' if 'WALK' in scene.name else 'run'
    if '--walk-only' in sys.argv and label!='walk':continue
    period=36 if label=='walk' else 24
    rig=next(o for o in scene.objects if o.type=='ARMATURE')
    meshes=[o for o in scene.objects if o.type=='MESH' and o.get('graduate_role')!='Studio floor']
    path=OUT/(label+('_physics_probes' if '--probes' in sys.argv else '_frames'));path.mkdir(exist_ok=True)
    bone_samples={name:[] for name in ['Body','Hips','Abdomen','Torso','Neck','Head','Shoulder.L','Shoulder.R','UpperArm.L','UpperArm.R','LowerArm.L','LowerArm.R','Palm.L','Palm.R','Foot.L','Foot.R']}
    seam=[];finite=True;shape_sums=[]
    second_seam=[]
    for frame in range(1,period+3):
        scene.frame_set(frame);bpy.context.view_layer.update()
        for name in bone_samples:
            pb=rig.pose.bones[name]
            bone_samples[name].append({'local_q':pb.rotation_quaternion.copy(),'world_q':pb.matrix.to_quaternion(),'head':pb.head.copy()})
        dg=bpy.context.evaluated_depsgraph_get()
        allpoints=[]
        for obj in meshes:
            ev=obj.evaluated_get(dg);mesh=ev.to_mesh()
            coords=[ev.matrix_world@v.co for v in mesh.vertices]
            finite=finite and all(math.isfinite(n) for v in coords for n in v)
            if frame in [1,2,period+1,period+2]:allpoints.extend(coords)
            ev.to_mesh_clear()
            if obj.data.shape_keys:
                shape_sums.append(sum(k.value for k in obj.data.shape_keys.key_blocks[1:]))
        if frame in [1,period+1]:seam.append(allpoints)
        if frame in [2,period+2]:second_seam.append(allpoints)
    bones={}
    for name,samples in bone_samples.items():
        bones[name]={'local_rotation_degrees':max(math.degrees(samples[0]['local_q'].rotation_difference(s['local_q']).angle) for s in samples),
                     'world_rotation_degrees':max(math.degrees(samples[0]['world_q'].rotation_difference(s['world_q']).angle) for s in samples),
                     'head_motion':max((s['head']-samples[0]['head']).length for s in samples)}
    row={'scene':scene.name,'action':rig.animation_data.action.name,'frames':period,'fps':30,
         'loop_max_vertex_gap':max((a-b).length for a,b in zip(*seam)),
         'second_cycle_vertex_gap':max((a-b).length for a,b in zip(*second_seam)),
         'all_vertices_finite':finite,'cloth_weight_sum_min':min(shape_sums),'cloth_weight_sum_max':max(shape_sums),'body_motion':bones}
    report['clips'].append(row)
    (OUT/'motion-validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print('CLIP_VALIDATED',label,'SEAM',row['loop_max_vertex_gap'],'CLOTH_SUM',row['cloth_weight_sum_min'],row['cloth_weight_sum_max'],flush=True)
    scene.cycles.samples=6
    scene.render.resolution_x=480;scene.render.resolution_y=600
    scene.render.resolution_percentage=100
    scene.render.threads_mode='FIXED';scene.render.threads=4
    scene.render.image_settings.file_format='PNG'
    frames=[1,period//4+1,period//2+1,3*period//4+1] if '--probes' in sys.argv else range(1,period+1)
    for frame in frames:
        scene.frame_set(frame)
        scene.render.filepath=str(path/('frame_%04d.png'%frame))
        bpy.ops.render.render(write_still=True)
        print('FRAME_DONE',label,frame,period,flush=True)
print('LOCOMOTION_RENDER_DONE',flush=True)
