"""Review final exported garden assets in isolated Blender background mode.

This does not modify source .blend files or the user's interactive Blender.
Godot gameplay captures remain the authoritative engine acceptance check.
"""
import bpy
import json
import math
import os
from pathlib import Path
from mathutils import Vector, Matrix

ROOT=Path(__file__).resolve().parents[1]
ASSETS=ROOT/'game/assets/discussion_garden'
OUT=ROOT/'art/DiscussionGarden/review-v2'
OUT.mkdir(parents=True,exist_ok=True)
layout=json.loads((ASSETS/'layout.json').read_text(encoding='utf-8'))
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(ASSETS/'garden.glb'))
scene=bpy.context.scene

def v(p):return Vector((p[0],-p[2],p[1]))

for zone in layout['zones']:
    before=set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(ASSETS/zone['device_model']))
    source=[ob for ob in set(bpy.data.objects)-before if ob.type=='MESH']
    for slot in zone['slots']:
        transform=Matrix.Translation(v(slot['position']))@Matrix.Rotation(slot['rotation_y'],4,'Z')
        for original in source:
            ob=original.copy();ob.data=original.data;scene.collection.objects.link(ob)
            ob.matrix_world=transform@original.matrix_world
    for original in source:bpy.data.objects.remove(original,do_unlink=True)

scene.render.engine='CYCLES';scene.cycles.samples=24;scene.cycles.use_denoising=True
scene.render.resolution_x=1280;scene.render.resolution_y=800;scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX'
scene.world.use_nodes=True
background=next(n for n in scene.world.node_tree.nodes if n.type=='BACKGROUND')
background.inputs['Color'].default_value=(.66,.76,.84,1);background.inputs['Strength'].default_value=.62
sun_data=bpy.data.lights.new('ReviewSun','SUN');sun_data.energy=2.1;sun_data.angle=.16
sun=bpy.data.objects.new('ReviewSun',sun_data);scene.collection.objects.link(sun)
sun.rotation_euler=(math.radians(26),math.radians(-29),math.radians(-22))
camera_data=bpy.data.cameras.new('ReviewCamera');camera=bpy.data.objects.new('ReviewCamera',camera_data)
scene.collection.objects.link(camera);scene.camera=camera;camera_data.lens=26;camera_data.clip_end=400

def shot(name,p,target,lens=26):
    camera.location=v(p);camera.rotation_euler=(v(target)-camera.location).to_track_quat('-Z','Y').to_euler();camera_data.lens=lens
    scene.render.filepath=str(OUT/(name+'.png'));bpy.ops.render.render(write_still=True)

selection=os.environ.get('GARDEN_REVIEW_ZONES','hub,university,major,career,high_school,campus').split(',')
if 'hub' in selection:shot('00-hub',(0,2.6,10.5),(0,1.5,-10.0),24)
for index,zone in enumerate(layout['zones']):
    if zone['id'] not in selection:continue
    c=zone['center'];yaw=zone['rotation_y']
    def world(p):return(c[0]+math.cos(yaw)*p[0]+math.sin(yaw)*p[2],p[1],c[2]-math.sin(yaw)*p[0]+math.cos(yaw)*p[2])
    shot('%02d-%s'%(index+1,zone['id']),world((1,2.4,12.0)),world((0,1.55,-2)),24 if zone['id']=='campus' else 26)
