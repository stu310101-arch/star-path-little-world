"""Export only the new three-phase somersault, retaining the old assets byte-for-byte.

Uses the established graduate exporter's evaluated-surface/inverse-skin path.
No old clip or cloth cache is copied into the new GLB. The scene remains editable.
"""
import bpy, sys, json, hashlib, re
import numpy as np
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import export_graduate_godot as export
OUT=ROOT/'game/assets/character/graduate_jump.glb'
REPORT=ROOT/'deliverables/frontflip-refined'
PROTECTED=[ROOT/'art/Graduate/Male_Graduate_GameReady.blend',ROOT/'game/assets/character/graduate.glb',ROOT/'art/Graduate/Godot/assets/graduate.glb']
before={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in PROTECTED}
scene=next(s for s in bpy.data.scenes if s.name.startswith('05_FORWARD'))
bpy.context.window.scene=scene
rig,meshes=export.role_map(scene)
names=[b.name for b in rig.data.bones]
inverse_rest=np.linalg.inv(np.asarray([np.asarray(rig.data.bones[n].matrix_local) for n in names]))
templates={};samples=[]
for frame in range(1,218):
    scene.frame_set(frame)
    for o in [rig,*meshes.values()]:o.hide_set(False);o.hide_viewport=False;o.hide_render=False
    bpy.context.view_layer.update()
    deps=bpy.context.evaluated_depsgraph_get();er=rig.evaluated_get(deps)
    world=er.matrix_world.copy()
    bones={n:er.pose.bones[n].matrix.copy() for n in names}
    bone_deformation=np.asarray([np.asarray(bones[n]) for n in names])@inverse_rest
    sample={'frame':frame-1,'clip':'ForwardSomersault','sourceFrame':frame,'rigWorld':world,'bones':bones,'meshes':{}}
    for role,obj in sorted(meshes.items()):
        ev=obj.evaluated_get(deps);me=ev.to_mesh(preserve_all_data_layers=True,depsgraph=deps)
        try:
            signature=export.topology_signature(me)
            weights,weighted=export.skin_weights(obj,me,names,np)
            if role not in templates:
                templates[role]={'data':bpy.data.meshes.new_from_object(ev,preserve_all_data_layers=True,depsgraph=deps),
                  'signature':signature,'weights':weights,'groups':[g.name for g in obj.vertex_groups],
                  'maximumInfluences':int(np.max(np.count_nonzero(weights>1e-7,axis=1),initial=0))}
            else:assert signature==templates[role]['signature'] and np.allclose(weights,templates[role]['weights'],atol=1e-6)
            points=np.empty(len(me.vertices)*3,dtype=np.float64);me.vertices.foreach_get('co',points);points=points.reshape(-1,3)
            posed=np.c_[points,np.ones(len(points))]@np.asarray(world.inverted()@ev.matrix_world).T
            deformation=np.einsum('vb,bij->vij',weights,bone_deformation);deformation[~weighted]=np.eye(4)
            points=np.einsum('vij,vj->vi',np.linalg.inv(deformation),posed)[:,:3]
            assert np.isfinite(points).all()
            # Inverse skinning introduces micrometre roundoff on rigid parts.
            # Canonicalize only a whole surface within a 5-micrometre bound;
            # real garment deflections retain their complete frame samples.
            if samples and np.max(np.linalg.norm(points-samples[0]['meshes'][role],axis=1))*1.75/4.8 < .000005:
                points=samples[0]['meshes'][role]
            sample['meshes'][role]=points.astype(np.float32)
        finally:ev.to_mesh_clear()
    samples.append(sample)
    if frame%30==1:print(f'SOMERSAULT_EXPORT_SAMPLE {frame}/217',flush=True)
stage,morph_report=export.create_staging(bpy,np,templates,samples,rig,1.75/4.8,0)
options={
 'filepath':str(OUT),'export_format':'GLB','use_selection':True,'use_active_scene':True,
 'export_cameras':False,'export_lights':False,'export_extras':False,'export_yup':True,
 'export_apply':False,'export_materials':'EXPORT','export_animations':True,'export_animation_mode':'SCENE',
 'export_anim_scene_split_object':False,'export_anim_slide_to_zero':False,'export_force_sampling':True,
 'export_frame_step':1,'export_bake_animation':True,'export_anim_single_armature':False,
 'export_optimize_animation_size':False,'export_optimize_animation_keep_anim_armature':True,
 'export_optimize_animation_keep_anim_object':True,'export_skins':True,'export_def_bones':True,
 'export_rest_position_armature':True,'export_armature_object_remove':False,
 'export_morph':True,'export_morph_normal':True,'export_morph_tangent':False,
 'export_morph_animation':True,'export_morph_reset_sk_data':False,'export_current_frame':True,
 'export_influence_nb':8,'export_all_influences':False}
assert 'FINISHED' in bpy.ops.export_scene.gltf(**options)
segments=[{'name':'JumpStart','startFrame':0,'endFrame':24,'duration':.24,'fps':100,'loop':False},
 {'name':'JumpAir','startFrame':24,'endFrame':96,'duration':.72,'fps':100,'loop':False},
 {'name':'JumpLand','startFrame':96,'endFrame':216,'duration':1.20,'fps':100,'loop':False}]
export.split_animations(OUT,segments,np)
doc,binary=export.read_glb(OUT)
doc['asset']['extras']={'bodyHeightMeters':1.75,'forwardAxis':'+Z','sourceForwardAxis':'-Y',
 'motion':'Forward somersault around hips; external ballistic trajectory',
 'takeoffSeconds':.12,'rotationPivotMeters':[0,2.35*1.75/4.8,.05*1.75/4.8],
 'sourceBlend':'art/Graduate/Male_Graduate_Frontflip_Refined.blend',
 'cloth':'World-space gravity/contact bake with landing follow-through; .000005 m rigid-noise canonicalization'}
export.write_glb(OUT,doc,binary)
export.CLIPS=(('JumpStart','05_FORWARD',24),('JumpAir','05_FORWARD',72),('JumpLand','05_FORWARD',120))
export.CLIP_FPS={'JumpStart':100,'JumpAir':100,'JumpLand':100}
validation=export.validate_glb(OUT,np,0)
after={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in PROTECTED}
assert before==after
report={'asset':str(OUT),'source_blend':bpy.data.filepath,'protected_asset_hashes':before,
 'originals_unchanged':True,'segments':segments,'glb':validation,'morphs':morph_report,
 'source_body_height':4.8,'scale_once':1.75/4.8,'no_trajectory_root_lift':True,
 'rig_transform':'Positive X rotation around source COM(0,-.05,2.35); translation solely compensates pivot.',
 'validation_limit':'Structural export and source-boundary geometry; actual Godot playback and cloth visual review required.'}
(REPORT/'export-validation.json').write_text(json.dumps(report,indent=2,ensure_ascii=False),encoding='utf8')
print('SOMERSAULT_EXPORT_DONE '+json.dumps(validation),flush=True)
