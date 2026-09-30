import bpy,json,sys
from pathlib import Path
from bpy_extras.object_utils import world_to_camera_view
ROOT=Path(__file__).resolve().parents[1]
scene=next(s for s in bpy.data.scenes if s.name.startswith('03_PORTAL'))
bpy.context.window.scene=scene
meshes=[o for o in scene.objects if o.type=='MESH' and o.get('graduate_role') and o.get('graduate_role')!='Studio floor']
rows=[]
for frame in range(1,111) if '--no-render' in sys.argv else [1,60,78,86,94,101,105,110]:
    scene.frame_set(frame);bpy.context.view_layer.update()
    points=[]
    for obj in meshes:
        ev=obj.evaluated_get(bpy.context.evaluated_depsgraph_get());me=ev.to_mesh()
        points.extend(world_to_camera_view(scene,scene.camera,ev.matrix_world@v.co) for v in me.vertices)
        ev.to_mesh_clear()
    rows.append({'frame':frame,'bounds_xy':[[min(p.x for p in points),min(p.y for p in points)],[max(p.x for p in points),max(p.y for p in points)]]})
    if '--no-render' not in sys.argv and frame in [1,94,110]:
        scene.cycles.samples=4;scene.cycles.device='CPU';scene.render.threads_mode='FIXED';scene.render.threads=4
        path=ROOT/'art'/'Graduate'/'animation'/'portal_framing_review';path.mkdir(exist_ok=True)
        scene.render.filepath=str(path/('frame_%04d.png'%frame));bpy.ops.render.render(write_still=True)
(ROOT/'art'/'Graduate'/'animation'/'portal-framing-validation.json').write_text(json.dumps(rows,indent=2),encoding='utf-8')
print('FRAMING',json.dumps(rows),flush=True)
