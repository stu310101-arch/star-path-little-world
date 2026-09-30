"""Add the optional closed-room light rig and save its eye-level camera.

This is also present in build_training_room.py; this updater avoids rebuilding
unchanged upholstered geometry when checking the enclosed interior view.
"""
from pathlib import Path
import bpy,json,math
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'art'/'TrainingRoom'
assert Path(bpy.data.filepath).resolve()==(OUT/'WordKing_TrainingRoom.blend').resolve()
s=bpy.context.scene;c=bpy.data.collections['13 | Roof and front wall - toggle for enclosed room']
bpy.data.objects['ARCH | optional ceiling'].location.z=3.49
assert not any(o.name.startswith('CEILING |') for o in c.objects),'Enclosure update already applied'
def box(name,loc,dims,material,bevel):
    x,y,z=[d/2 for d in dims]
    v=[(-x,-y,-z),(x,-y,-z),(x,y,-z),(-x,y,-z),(-x,-y,z),(x,-y,z),(x,y,z),(-x,y,z)]
    f=[(3,2,1,0),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]
    d=bpy.data.meshes.new(name);d.from_pydata(v,[],f);d.update();d.materials.append(bpy.data.materials[material])
    o=bpy.data.objects.new(name,d);c.objects.link(o);o.location=loc
    b=o.modifiers.new('Soft edge highlights','BEVEL');b.width=bevel;b.segments=3
    o.modifiers.new('Weighted normals','WEIGHTED_NORMAL')
for x in [-6,6]:
    box('CEILING | recessed channel',(x,0,3.36),(.20,14.1,.075),'MAT | Graphite brushed aluminium',.016)
    box('CEILING | diffused linear light',(x,0,3.315),(.055,13.8,.014),'MAT | Pearl white LED',.005)
for x in [-6,0,6]:
    for y in [-4.5,4.5]:
        d=bpy.data.lights.new('CEILING | soft interior fill','AREA');d.energy=240;d.color=(.64,.77,1);d.shape='DISK';d.size=3
        o=bpy.data.objects.new('CEILING | soft interior fill',d);c.objects.link(o);o.location=(x,y,3.22)
        o.rotation_euler=(Vector((x,y,0))-o.location).to_track_quat('-Z','Y').to_euler()
cam=bpy.data.objects['CAM | 02 eye-level room'];cam.location=(-3.8,-6.6,1.72)
cam.rotation_euler=(Vector((.7,2.6,1.52))-cam.location).to_track_quat('-Z','Y').to_euler()
c.hide_render=True;c.hide_viewport=True
note=bpy.data.texts.get('READ ME | Training Room')
if note:
    note.from_string(note.as_string()+'\nCamera 05: upholstered leather sofa. Optional enclosure collection now includes interior ceiling fixtures. Enable it for eye-level viewing.\n')
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'WordKing_TrainingRoom.blend'))
p=OUT/'validation'/'scene_manifest.json';report=json.loads(p.read_text(encoding='utf8'))
report['object_count']=len(s.objects)
report['mesh_source_triangles']=sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in s.objects if o.type=='MESH')
report['optional_enclosure_has_interior_lights']=True
p.write_text(json.dumps(report,indent=2),encoding='utf8')
print('ENCLOSURE_SAVED',flush=True)
