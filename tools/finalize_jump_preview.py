"""Add optional Blender-only playback FX after the cloth bake; never exported."""
import bpy, math, random, json
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'art'/'Graduate';SCALE=1.75/4.8
scene=next(s for s in bpy.data.scenes if s.name.startswith('03_JUMP'))
bpy.context.window.scene=scene
for obj in list(scene.objects):
    if obj.get('preview_fx'):bpy.data.objects.remove(obj,do_unlink=True)
rig=next(o for o in scene.objects if o.type=='ARMATURE')
scene.frame_set(1);rig.hide_set(False)
character=[o for o in scene.objects if o.type=='MESH' and o.get('graduate_role')]
for obj in character:
    for f,hidden in [(1,False),(40,False),(41,True),(72,True)]:
        obj.hide_render=hidden;obj.keyframe_insert('hide_render',frame=f)
        obj.hide_viewport=hidden;obj.keyframe_insert('hide_viewport',frame=f)
    obj['Game export note']='Visibility is preview only. Godot controller triggers flash at 1.3s and hides the Visual at 1.333333s.'

def mat(name,color,strength):
    m=bpy.data.materials.get(name) or bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
    bs=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED');bs.inputs['Base Color'].default_value=(*color,1)
    bs.inputs['Emission Color'].default_value=(*color,1);bs.inputs['Emission Strength'].default_value=strength
    return m
white=mat('Preview FX | warm white',(1,.91,.65),5)
gold=mat('Preview FX | sparks',(1,.55,.12),3)
center=Vector((0,0,.32/SCALE))
bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2,radius=1,location=center)
flash=bpy.context.object;flash.name='Preview FX | flash';flash['preview_fx']=True;flash.data.materials.append(white)
for f,r in [(1,0),(39,0),(40,.10),(41,.56),(42,.45),(44,0),(72,0)]:
    flash.scale=(r/SCALE,)*3;flash.keyframe_insert('scale',frame=f)
rng=random.Random(714)
for i in range(24):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=1,location=center)
    obj=bpy.context.object;obj.name='Preview FX | mote %02d'%i;obj['preview_fx']=True;obj.data.materials.append(gold)
    direction=Vector((rng.uniform(-1,1),rng.uniform(-1,1),rng.uniform(-.4,1))).normalized()
    speed=rng.uniform(.55,1.6);size=rng.uniform(.015,.03)
    for f in [1,39,40,43,49,55,60,72]:
        t=max(0,(f-40)/30)
        obj.location=center+(direction*speed*t+Vector((0,0,-.8*t*t)))/SCALE
        amount=0 if f<40 or f>=60 else size*(1-max(0,(f-43)/17))
        obj.scale=(amount/SCALE,)*3
        obj.keyframe_insert('location',frame=f);obj.keyframe_insert('scale',frame=f)
for obj in scene.objects:
    if obj.get('preview_fx'):
        for layer in obj.animation_data.action.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    for fc in bag.fcurves:
                        for k in fc.keyframe_points:k.interpolation='LINEAR'
scene.frame_set(1);rig.hide_set(True)
scene.render.film_transparent=False
scene.camera.data.ortho_scale=8.5
scene.camera.rotation_euler=(Vector((0,0,1.8))-scene.camera.location).to_track_quat('-Z','Y').to_euler()
scene.world=scene.world.copy();scene.world.use_nodes=True
bg=next(n for n in scene.world.node_tree.nodes if n.type=='BACKGROUND')
bg.inputs[0].default_value=(.11,.12,.14,1);bg.inputs[1].default_value=.55
scene['Preview FX']='Optional preview objects only, tagged preview_fx and excluded from GLB. Actual reusable effect is implemented in Godot.'
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            sp=area.spaces.active;sp.shading.type='SOLID';sp.shading.color_type='MATERIAL';sp.overlay.show_overlays=False
            sp.shading.light='STUDIO';sp.shading.studio_light='paint.sl'
            sp.region_3d.view_location=(0,0,1.35);sp.region_3d.view_distance=7.2
            sp.region_3d.view_rotation=(Vector((8,-17,6))-Vector((0,0,1.35))).to_track_quat('Z','Y')
            sp.region_3d.view_perspective='CAMERA'
guide=bpy.data.texts.get('START HERE - Graduate animation') or bpy.data.texts.new('START HERE - Graduate animation')
guide.clear();guide.write('BLACK GRADUATE / GODOT ASSET\n\n01_WALK: 36f loop.\n02_RUN: 24f loop.\n03_JUMP: 72f, anticipation / vertical leap / downward drop / flash / disappear.\n\nNo portal or level geometry.\nBlender preview FX are excluded from the GLB.\nGodot/assets/graduate.glb contains reusable skeletal and cloth animation.\nGodot/scenes/graduate_character.tscn handles flash and visibility separately.\nAll physical cloth is embedded; no simulation cache dependency.\n')
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'Male_Graduate_GameReady.blend'))
print('JUMP_PREVIEW_FINALIZED',flush=True)
