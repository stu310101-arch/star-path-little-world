"""Compare unchanged skeleton/body authoring and exact baked loop endpoints."""
from pathlib import Path
import sys,json,hashlib
import bpy,numpy as np
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from export_graduate_godot import action_curves,role_map
from simulate_portal_cloth import evaluated_points
from validate_sleeve_garment_contact import visible_surfaces

def skeleton_record():
    record={}
    for scene in bpy.data.scenes:
        if not scene.name.startswith(('01_WALK','02_RUN','03_JUMP','04_IDLE')):continue
        bpy.context.window.scene=scene;rig,meshes=role_map(scene)
        curves=[]
        for curve in action_curves(rig.animation_data.action):
            curves.append([curve.data_path,curve.array_index,[[*k.co,*k.handle_left,*k.handle_right,k.interpolation] for k in curve.keyframe_points]])
        body=meshes['Graduate | original face, hands and trousers']
        record[scene.name]={'bone_curve_hash':hashlib.sha256(json.dumps(curves).encode()).hexdigest(),
            'body_mesh_hash':hashlib.sha256(np.asarray([v.co[:] for v in body.data.vertices],dtype=np.float32).tobytes()).hexdigest(),
            'fps':scene.render.fps/scene.render.fps_base,'period':scene.frame_end}
    return record

candidate=skeleton_record();loops={}
for scene in bpy.data.scenes:
    if not scene.name.startswith(('01_WALK','02_RUN','04_IDLE')):continue
    rig,meshes=role_map(scene)
    with visible_surfaces(scene,list(meshes.values()),'rendered'):
        scene.frame_set(1);bpy.context.view_layer.update()
        first={r:evaluated_points(o) for r,o in meshes.items()}
        scene.frame_set(scene.frame_end+1);bpy.context.view_layer.update()
        errors={r:float(np.linalg.norm(evaluated_points(o)-first[r],axis=1).max()) for r,o in meshes.items()}
    loops[scene.name]=errors
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'art/Graduate/Male_Graduate_GameReady.blend'))
original=skeleton_record()
same=all(candidate[n][k]==original[n][k] for n in original for k in ('bone_curve_hash','body_mesh_hash','period'))
loop_error=max(v for row in loops.values() for v in row.values())
report={'skeleton_and_body_preserved':same,'loop_max_error_m':loop_error,'loops':loops,'candidate':candidate,'original':original}
(ROOT/'art/Graduate/animation/regalia-motion-validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
assert same
assert loop_error<1e-5,loop_error
assert candidate[next(n for n in candidate if n.startswith('04_IDLE'))]['fps']==56
print('REGALIA_MOTION_VALIDATION_PASSED',same,loop_error,flush=True)
