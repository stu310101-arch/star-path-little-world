"""Preserve foot contact and save the reviewed graduate animation package."""
import bpy,json,math
from mathutils import Vector
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'art'/'Graduate'
report=[]
for scene in bpy.data.scenes:
    if not scene.name.startswith(('01_WALK','02_RUN')):continue
    bpy.context.window.scene=scene
    rig=next(o for o in scene.objects if o.type=='ARMATURE')
    body=next(o for o in scene.objects if o.get('graduate_role')=='Graduate | original face, hands and trousers')
    period=36 if 'WALK' in scene.name else 24
    foot_ids={}
    for side in ['L','R']:
        group=body.vertex_groups.get('Foot.'+side)
        foot_ids[side]=[v.index for v in body.data.vertices if v.co.z<.40 and group and any(g.group==group.index and g.weight>.1 for g in v.groups)]
    changes=[]
    rig.hide_set(False)
    for f in range(1,period+2):
        scene.frame_set(f);bpy.context.view_layer.update()
        for side in ['L','R']:
            ev=body.evaluated_get(bpy.context.evaluated_depsgraph_get());me=ev.to_mesh()
            low=min((ev.matrix_world@me.vertices[i].co).z for i in foot_ids[side])
            ev.to_mesh_clear()
            if low<-.024:
                delta=-.024-low
                foot=rig.pose.bones['Foot.'+side]
                foot.location.z+=delta/foot.bone.matrix_local.col[2].z
                foot.keyframe_insert('location',frame=f)
                bpy.context.view_layer.update()
                changes.append({'frame':f,'foot':side,'raise_model_units':delta})
    for l in rig.animation_data.action.layers:
        for st in l.strips:
            for bag in st.channelbags:
                for fc in bag.fcurves:
                    for k in fc.keyframe_points:k.interpolation='LINEAR'
    rig.hide_set(True)
    scene.frame_start=1;scene.frame_end=period;scene.frame_set(1)
    scene['Cloth']='Front-opening cloth gown: gravity, leg contact and self collision; fitted to a repeating clip and baked. The lower garment has no thigh-bone skin weights.'
    report.append({'scene':scene.name,'foot_contact_corrections':changes})
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            sp=area.spaces.active
            sp.shading.type='SOLID';sp.shading.color_type='MATERIAL'
            sp.shading.light='STUDIO';sp.shading.studio_light='paint.sl'
            sp.overlay.show_overlays=False
            sp.region_3d.view_location=(0,0,2.45)
            sp.region_3d.view_distance=3.7*area.width/max(1,area.height)
            sp.region_3d.view_rotation=(Vector((7,-17,7))-Vector((0,0,2.45))).to_track_quat('Z','Y')
            sp.region_3d.view_perspective='ORTHO'
bpy.context.window.scene=next(s for s in bpy.data.scenes if s.name.startswith('01_WALK'))
if bpy.data.workspaces.get('Animation'):bpy.context.window.workspace=bpy.data.workspaces['Animation']
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'Male_Graduate_Final.blend'))
(OUT/'animation'/'foot-contact-validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('FINAL_GRADUATE_SAVED',flush=True)
