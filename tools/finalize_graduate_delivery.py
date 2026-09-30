"""Save the verified black-regalia character with three accessible scenes."""
import bpy,json,math
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'art'/'Graduate'
expected={'01_WALK':36,'02_RUN':24,'03_PORTAL':150}
report=[]
for prefix,period in expected.items():
    scene=next(s for s in bpy.data.scenes if s.name.startswith(prefix))
    bpy.context.window.scene=scene
    scene.frame_start=1;scene.frame_end=period;scene.render.fps=30
    scene['Design']='Black and charcoal academic gown, hem between below knee and calf, black stole with narrow antique gold trim, black mortarboard.'
    rig=next(o for o in scene.objects if o.type=='ARMATURE')
    gown=next(o for o in scene.objects if o.get('graduate_role')=='01 | Pleated bachelor gown')
    lower=[v for v in gown.data.vertices if v.co.z<2.2]
    thigh_weights=[(v.index,g.weight) for v in lower for g in v.groups if 'Leg.' in gown.vertex_groups[g.group].name and g.weight>.00001]
    if thigh_weights:raise RuntimeError('Lower gown still has leg weights: '+scene.name)
    if not gown.data.shape_keys:raise RuntimeError('Missing baked gown motion: '+scene.name)
    active={}
    for f in [1,period//2,period]:
        scene.frame_set(f);bpy.context.view_layer.update()
        total=sum(k.value for k in gown.data.shape_keys.key_blocks[1:])
        if abs(total-1)>.0001:raise RuntimeError('Invalid cloth shape weights at '+str(f))
        active[f]=total
    report.append({'scene':scene.name,'frames':period,'fps':30,'gown_vertices':len(gown.data.vertices),'lower_gown_leg_weights':len(thigh_weights),'sampled_shape_weights':active})
    scene.frame_set(1);rig.hide_set(True)
walk=next(s for s in bpy.data.scenes if s.name.startswith('01_WALK'))
portal=next(s for s in bpy.data.scenes if s.name.startswith('03_PORTAL'))
camera=portal.camera
camera.animation_data_clear();camera.data.lens=31
for f,pos,target in [(1,(8,10,6.8),(0,-2.5,2.9)),(78,(7,8,6.4),(0,-3.7,3.3)),(108,(6,6,6.4),(0,-5.3,3.0)),(150,(5.5,5.5,6.1),(0,-6,1.8))]:
    camera.location=pos;camera.rotation_euler=(Vector(target)-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.keyframe_insert('location',frame=f);camera.keyframe_insert('rotation_euler',frame=f)
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
bpy.context.window.scene=walk
if bpy.data.workspaces.get('Animation'):bpy.context.window.workspace=bpy.data.workspaces['Animation']
guide=bpy.data.texts.get('START HERE - Graduate animation') or bpy.data.texts.new('START HERE - Graduate animation')
guide.clear();guide.write('BLACK GRADUATE / THREE SCENES\n\n01_WALK: 36 frames at 30 fps, in-place loop.\n02_RUN: 24 frames at 30 fps, in-place loop.\n03_PORTAL: 150 frames at 30 fps, approach / crouch / leap / fall into void.\n\nChoose a scene in the top-right Scene selector. Space starts/stops playback.\nIn the portal scene press Numpad 0 for the story camera.\nAll gown animations are baked into shape keys, with free lower hems and no thigh weights.\nOriginal Quaternius character and source clips: CC0. Gown and portal: locally procedural.\n')
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'Male_Graduate_Final.blend'))
(OUT/'animation'/'delivery-validation.json').write_text(json.dumps({'file':str(OUT/'Male_Graduate_Final.blend'),'scenes':report,'external_cloth_cache_required':False},indent=2),encoding='utf-8')
print('GRADUATE_THREE_SCENES_SAVED',flush=True)
