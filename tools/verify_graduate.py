import bpy, json, math
from pathlib import Path
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'art'/'Graduate'
QA=OUT/'review'
QA.mkdir(exist_ok=True)
scene=bpy.context.scene
rig=bpy.data.objects['HumanArmature']
camera=scene.camera
meshes=[o for o in scene.objects if o.type=='MESH' and o.name!='Studio floor']
report={'geometry':[],'pose_checks':[],'missing_images':[]}
for o in meshes:
    row={'name':o.name,'unweighted':sum(len(v.groups)==0 for v in o.data.vertices),
         'bad_weight_sum':sum(abs(sum(g.weight for g in v.groups)-1)>1e-4 for v in o.data.vertices),
         'degenerate_faces':sum(p.area<1e-9 for p in o.data.polygons)}
    report['geometry'].append(row)
for img in bpy.data.images:
    if img.source=='FILE' and not img.packed_file and img.filepath and not Path(bpy.path.abspath(img.filepath)).is_file():
        report['missing_images'].append(img.filepath)

scene.cycles.samples=16
scene.render.resolution_x=560;scene.render.resolution_y=720
def render(name,location,action='Man_Idle',frame=17):
    rig.animation_data.action=bpy.data.actions[action]
    scene.frame_set(frame)
    camera.location=location
    camera.rotation_euler=(Vector((0,0,2.5))-camera.location).to_track_quat('-Z','Y').to_euler()
    bpy.context.view_layer.update()
    dg=bpy.context.evaluated_depsgraph_get()
    points=[]
    for obj in meshes:
        ev=obj.evaluated_get(dg)
        m=ev.to_mesh()
        points.extend(ev.matrix_world@v.co for v in m.vertices)
        ev.to_mesh_clear()
    report['pose_checks'].append({'name':name,'action':action,'frame':frame,
       'finite':all(math.isfinite(n) for p in points for n in p),
       'bounds':[[min(p[k] for p in points) for k in range(3)],[max(p[k] for p in points) for k in range(3)]]})
    scene.render.filepath=str(QA/(name+'.png'))
    bpy.ops.render.render(write_still=True)

render('01_front',(0,-18,6))
render('02_back',(7,16,7))
render('03_side',(18,0,6))
render('04_idle_50',(8,-15,8.4),frame=50)
render('05_walk_check',(8,-15,8.4),'Man_Walk',7)
render('06_clapping_check',(8,-15,8.4),'Man_Clapping',15)
(QA/'validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('VALIDATION_SUMMARY',json.dumps(report))
